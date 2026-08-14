#!/usr/bin/env bash
set -euo pipefail

API_URL="http://127.0.0.1:54321"
DB_URL="postgresql://postgres:postgres@127.0.0.1:54322/postgres"

# Supabase CLI local credentials. We intentionally read them from the ephemeral
# local runtime instead of hard-coding any hosted key.
eval "$(supabase status -o env | grep -E '^(ANON_KEY|SERVICE_ROLE_KEY)=' | sed 's/^/export /')"

: "${ANON_KEY:?ANON_KEY missing from local Supabase status}"
: "${SERVICE_ROLE_KEY:?SERVICE_ROLE_KEY missing from local Supabase status}"

rand_suffix="$(date +%s)-$RANDOM"
password='EvoLocalTest!123456'

signup() {
  local email="$1"
  curl -fsS "$API_URL/auth/v1/signup" \
    -H "apikey: $ANON_KEY" \
    -H 'Content-Type: application/json' \
    -d "{\"email\":\"$email\",\"password\":\"$password\"}"
}

login() {
  local email="$1"
  curl -fsS "$API_URL/auth/v1/token?grant_type=password" \
    -H "apikey: $ANON_KEY" \
    -H 'Content-Type: application/json' \
    -d "{\"email\":\"$email\",\"password\":\"$password\"}"
}

rpc() {
  local token="$1" function_name="$2" body="$3"
  curl -fsS "$API_URL/rest/v1/rpc/$function_name" \
    -H "apikey: $ANON_KEY" \
    -H "Authorization: Bearer $token" \
    -H 'Content-Type: application/json' \
    -d "$body"
}

public_rpc() {
  local function_name="$1" body="$2"
  curl -fsS "$API_URL/rest/v1/rpc/$function_name" \
    -H "apikey: $ANON_KEY" \
    -H 'Content-Type: application/json' \
    -d "$body"
}

ADMIN_EMAIL="e2e-admin-$rand_suffix@example.test"
PARTNER_A_EMAIL="e2e-partner-a-$rand_suffix@example.test"
PARTNER_B_EMAIL="e2e-partner-b-$rand_suffix@example.test"
STAFF_EMAIL="e2e-staff-$rand_suffix@example.test"

signup "$ADMIN_EMAIL" >/dev/null
signup "$PARTNER_A_EMAIL" >/dev/null
signup "$PARTNER_B_EMAIL" >/dev/null
signup "$STAFF_EMAIL" >/dev/null

ADMIN_LOGIN="$(login "$ADMIN_EMAIL")"
PARTNER_A_LOGIN="$(login "$PARTNER_A_EMAIL")"
PARTNER_B_LOGIN="$(login "$PARTNER_B_EMAIL")"
STAFF_LOGIN="$(login "$STAFF_EMAIL")"

ADMIN_ID="$(jq -r '.user.id' <<<"$ADMIN_LOGIN")"
PARTNER_A_ID="$(jq -r '.user.id' <<<"$PARTNER_A_LOGIN")"
PARTNER_B_ID="$(jq -r '.user.id' <<<"$PARTNER_B_LOGIN")"
STAFF_ID="$(jq -r '.user.id' <<<"$STAFF_LOGIN")"

ADMIN_TOKEN="$(jq -r '.access_token' <<<"$ADMIN_LOGIN")"
PARTNER_A_TOKEN="$(jq -r '.access_token' <<<"$PARTNER_A_LOGIN")"
PARTNER_B_TOKEN="$(jq -r '.access_token' <<<"$PARTNER_B_LOGIN")"
STAFF_TOKEN="$(jq -r '.access_token' <<<"$STAFF_LOGIN")"

for value in "$ADMIN_ID" "$PARTNER_A_ID" "$PARTNER_B_ID" "$STAFF_ID" "$ADMIN_TOKEN" "$PARTNER_A_TOKEN" "$PARTNER_B_TOKEN" "$STAFF_TOKEN"; do
  if [[ -z "$value" || "$value" == "null" ]]; then
    echo "Auth signup/login did not return required signed identity/token" >&2
    exit 1
  fi
done

# Seed only disposable business fixtures, binding them to the real GoTrue Auth users.
# Use a service-role claim in the SQL session so trusted-server tenant guards apply
# exactly as intended for server provisioning.
psql "$DB_URL" -v ON_ERROR_STOP=1 \
  -v admin_uid="$ADMIN_ID" \
  -v partner_a_uid="$PARTNER_A_ID" \
  -v partner_b_uid="$PARTNER_B_ID" \
  -v staff_uid="$STAFF_ID" <<'SQL'
begin;
select set_config('request.jwt.claims','{"role":"service_role"}',true);

insert into public.admin_users(user_id,display_name,status)
values (:'admin_uid'::uuid,'E2E Admin','active');

insert into public.partners(partner_code,partner_name,voucher_limit,staff_access_enabled,status)
values
  ('E2E-PA','E2E Partner A',0,true,'active'),
  ('E2E-PB','E2E Partner B',0,true,'active');

insert into public.partner_users(user_id,partner_id,role,status,staff_name,login_email)
select :'partner_a_uid'::uuid,p.id,'partner_admin','active','Partner A Admin','e2e-a@example.test'
from public.partners p where p.partner_code='E2E-PA';

insert into public.partner_users(user_id,partner_id,role,status,staff_name,login_email)
select :'partner_b_uid'::uuid,p.id,'partner_admin','active','Partner B Admin','e2e-b@example.test'
from public.partners p where p.partner_code='E2E-PB';

insert into public.staff_users(user_id,branch_id,staff_name,role,status)
select :'staff_uid'::uuid,b.id,'E2E Mines Staff','staff','active'
from public.branches b where b.branch_code='MINES';

insert into public.partner_claim_settings(partner_id,all_branches)
select p.id,false from public.partners p where p.partner_code in ('E2E-PA','E2E-PB');

insert into public.partner_claim_branches(partner_id,branch_id)
select p.id,b.id
from public.partners p cross join public.branches b
where p.partner_code='E2E-PA' and b.branch_code='MINES';

insert into public.partner_claim_branches(partner_id,branch_id)
select p.id,b.id
from public.partners p cross join public.branches b
where p.partner_code='E2E-PB' and b.branch_code='BAHAU';

insert into public.voucher_templates(template_code,template_name,voucher_category,status,theme_code)
values ('E2E-HTTP','E2E HTTP Voucher','test','active','default');

insert into public.voucher_versions(
  template_id,version_no,version_name,face_value,validity_mode,valid_days,
  usage_limit,supply_limit,all_branches,status,effective_from
)
select vt.id,1,'E2E HTTP v1',60,'days',30,1,10,false,'active',now()
from public.voucher_templates vt where vt.template_code='E2E-HTTP';

update public.voucher_templates vt
set current_version_id=vv.id
from public.voucher_versions vv
where vv.template_id=vt.id and vt.template_code='E2E-HTTP' and vv.version_no=1;

insert into public.voucher_version_branches(version_id,branch_id)
select vv.id,b.id
from public.voucher_versions vv
join public.voucher_templates vt on vt.id=vv.template_id
cross join public.branches b
where vt.template_code='E2E-HTTP' and vv.version_no=1 and b.branch_code='MINES';

insert into public.partner_voucher_access(partner_id,template_id,status,quota_type)
select p.id,vt.id,'active','allocation'
from public.partners p cross join public.voucher_templates vt
where p.partner_code in ('E2E-PA','E2E-PB') and vt.template_code='E2E-HTTP';

insert into public.partner_voucher_allocations(partner_id,version_id,quantity_allocated,status)
select p.id,vv.id,2,'active'
from public.partners p
cross join public.voucher_versions vv
join public.voucher_templates vt on vt.id=vv.template_id
where p.partner_code='E2E-PA' and vt.template_code='E2E-HTTP' and vv.version_no=1;

commit;
SQL

VERSION_ID="$(psql "$DB_URL" -Atqc "select vv.id from public.voucher_versions vv join public.voucher_templates vt on vt.id=vv.template_id where vt.template_code='E2E-HTTP' and vv.version_no=1")"
[[ -n "$VERSION_ID" ]] || { echo 'E2E version missing' >&2; exit 1; }

ISSUE_A="$(rpc "$PARTNER_A_TOKEN" issue_engine_voucher "{\"p_version_id\":\"$VERSION_ID\",\"p_customer_name\":\"HTTP Customer\",\"p_customer_phone\":\"0123456789\"}")"
[[ "$(jq -r '.success' <<<"$ISSUE_A")" == "true" ]] || { echo "Partner A issue failed: $ISSUE_A" >&2; exit 1; }
VOUCHER_CODE="$(jq -r '.voucher_code' <<<"$ISSUE_A")"
PUBLIC_TOKEN="$(jq -r '.public_token' <<<"$ISSUE_A")"
ISSUED_PARTNER_ID="$(jq -r '.partner_id' <<<"$ISSUE_A")"

EXPECTED_PARTNER_A_ID="$(psql "$DB_URL" -Atqc "select id from public.partners where partner_code='E2E-PA'")"
[[ "$ISSUED_PARTNER_ID" == "$EXPECTED_PARTNER_A_ID" ]] || { echo 'Issuer tenant was not Auth-derived Partner A' >&2; exit 1; }

# Partner B has access to the template but deliberately no allocation.
set +e
ISSUE_B_RAW="$(rpc "$PARTNER_B_TOKEN" issue_engine_voucher "{\"p_version_id\":\"$VERSION_ID\",\"p_customer_name\":\"Cross Tenant Attempt\",\"p_customer_phone\":null}" 2>&1)"
ISSUE_B_STATUS=$?
set -e
if [[ $ISSUE_B_STATUS -eq 0 ]]; then
  echo "Partner B unexpectedly issued Partner A allocation: $ISSUE_B_RAW" >&2
  exit 1
fi

PUBLIC_RESULT="$(public_rpc get_public_voucher "{\"p_token\":\"$PUBLIC_TOKEN\"}")"
[[ "$(jq -r '.success' <<<"$PUBLIC_RESULT")" == "true" ]] || { echo "Public lookup failed: $PUBLIC_RESULT" >&2; exit 1; }
[[ "$(jq -r '.voucher_code' <<<"$PUBLIC_RESULT")" == "$VOUCHER_CODE" ]] || { echo 'Public lookup returned wrong voucher' >&2; exit 1; }
[[ "$(jq -r 'has("customer_phone")' <<<"$PUBLIC_RESULT")" == "false" ]] || { echo 'Public RPC leaked customer_phone' >&2; exit 1; }

VERIFY="$(rpc "$STAFF_TOKEN" verify_voucher "{\"p_voucher_code\":\"$VOUCHER_CODE\",\"p_branch_code\":\"BAHAU\"}")"
[[ "$(jq -r '.success' <<<"$VERIFY")" == "true" ]] || { echo "Verify failed: $VERIFY" >&2; exit 1; }
[[ "$(jq -r '.branch_name' <<<"$VERIFY")" == "The Mines" ]] || { echo 'Normal Staff escaped assigned branch' >&2; exit 1; }
[[ "$(jq -r '.can_redeem' <<<"$VERIFY")" == "true" ]] || { echo 'Voucher should be redeemable at Mines' >&2; exit 1; }

REDEEM="$(rpc "$STAFF_TOKEN" redeem_voucher "{\"p_voucher_code\":\"$VOUCHER_CODE\",\"p_notes\":\"HTTP E2E\",\"p_branch_code\":\"BAHAU\",\"p_redeem_method\":\"qr\"}")"
[[ "$(jq -r '.success' <<<"$REDEEM")" == "true" ]] || { echo "Redeem failed: $REDEEM" >&2; exit 1; }
[[ "$(jq -r '.branch_name' <<<"$REDEEM")" == "The Mines" ]] || { echo 'Redeem used caller-supplied wrong branch' >&2; exit 1; }
REDEMPTION_ID="$(jq -r '.redemption_id' <<<"$REDEEM")"

SECOND_REDEEM="$(rpc "$STAFF_TOKEN" redeem_voucher "{\"p_voucher_code\":\"$VOUCHER_CODE\",\"p_notes\":null,\"p_branch_code\":null,\"p_redeem_method\":\"qr\"}")"
[[ "$(jq -r '.success' <<<"$SECOND_REDEEM")" == "false" ]] || { echo 'Single-use voucher redeemed twice' >&2; exit 1; }

REVERSE="$(rpc "$ADMIN_TOKEN" reverse_redemption "{\"p_redemption_id\":\"$REDEMPTION_ID\",\"p_reason\":\"HTTP E2E reversal\"}")"
[[ "$(jq -r '.success' <<<"$REVERSE")" == "true" ]] || { echo "Reverse failed: $REVERSE" >&2; exit 1; }
[[ "$(jq -r '.usage_count' <<<"$REVERSE")" == "0" ]] || { echo 'Reverse did not restore usage_count' >&2; exit 1; }
[[ "$(jq -r '.status' <<<"$REVERSE")" == "active" ]] || { echo 'Reverse did not restore active voucher status' >&2; exit 1; }

DB_REDEMPTION_STATUS="$(psql "$DB_URL" -Atqc "select status from public.redemptions where id='$REDEMPTION_ID'::uuid")"
[[ "$DB_REDEMPTION_STATUS" == "reversed" ]] || { echo 'Reversal history was not preserved' >&2; exit 1; }

echo 'Signed GoTrue HTTP core flow E2E passed.'
