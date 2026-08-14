#!/usr/bin/env bash
set -euo pipefail

API_URL="http://127.0.0.1:54321"
DB_URL="postgresql://postgres:postgres@127.0.0.1:54322/postgres"

eval "$(supabase status -o env | grep -E '^(ANON_KEY|SERVICE_ROLE_KEY)=' | sed 's/^/export /')"
: "${ANON_KEY:?ANON_KEY missing}"
: "${SERVICE_ROLE_KEY:?SERVICE_ROLE_KEY missing}"

rand_suffix="$(date +%s)-$RANDOM"
password='EvoEdgeTest!123456'
ADMIN_EMAIL="edge-admin-$rand_suffix@example.test"
PARTNER_EMAIL="edge-partner-$rand_suffix@example.test"
STAFF_EMAIL="edge-staff-$rand_suffix@example.test"
PARTNER_CODE="EDGE_$RANDOM"

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

edge_post() {
  local function_name="$1" token="$2" body="$3"
  curl -sS -w '\n%{http_code}' "$API_URL/functions/v1/$function_name" \
    -H "apikey: $ANON_KEY" \
    -H "Authorization: Bearer $token" \
    -H 'Content-Type: application/json' \
    -d "$body"
}

signup "$ADMIN_EMAIL" >/dev/null
ADMIN_LOGIN="$(login "$ADMIN_EMAIL")"
ADMIN_ID="$(jq -r '.user.id' <<<"$ADMIN_LOGIN")"
ADMIN_TOKEN="$(jq -r '.access_token' <<<"$ADMIN_LOGIN")"
[[ -n "$ADMIN_ID" && "$ADMIN_ID" != null && -n "$ADMIN_TOKEN" && "$ADMIN_TOKEN" != null ]] || exit 1

# Bind the real GoTrue Admin UID to the operational Admin realm.
psql "$DB_URL" -v ON_ERROR_STOP=1 -v admin_uid="$ADMIN_ID" <<'SQL'
begin;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
insert into public.admin_users(user_id,display_name,status)
values (:'admin_uid'::uuid,'Edge E2E Admin','active');
commit;
SQL

# Missing bearer must fail before any business mutation.
NO_AUTH="$(curl -sS -o /tmp/edge-no-auth.json -w '%{http_code}' "$API_URL/functions/v1/create-partner" \
  -H "apikey: $ANON_KEY" -H 'Content-Type: application/json' -d '{}')"
[[ "$NO_AUTH" == "401" ]] || { cat /tmp/edge-no-auth.json >&2; echo "Expected create-partner 401 without bearer, got $NO_AUTH" >&2; exit 1; }

CREATE_RAW="$(edge_post create-partner "$ADMIN_TOKEN" "{\"partner_code\":\"$PARTNER_CODE\",\"partner_name\":\"Edge Partner\",\"contact_person\":\"Edge Admin\",\"contact_phone\":\"0120000000\",\"email\":\"$PARTNER_EMAIL\",\"password\":\"$password\",\"voucher_limit\":0,\"staff_limit\":3}")"
CREATE_STATUS="$(tail -n1 <<<"$CREATE_RAW")"
CREATE_BODY="$(sed '$d' <<<"$CREATE_RAW")"
[[ "$CREATE_STATUS" == "201" ]] || { echo "create-partner failed ($CREATE_STATUS): $CREATE_BODY" >&2; exit 1; }
[[ "$(jq -r '.success' <<<"$CREATE_BODY")" == "true" ]] || { echo "$CREATE_BODY" >&2; exit 1; }
PARTNER_ID="$(jq -r '.partner.id' <<<"$CREATE_BODY")"
PARTNER_UID="$(jq -r '.user_id' <<<"$CREATE_BODY")"
[[ -n "$PARTNER_ID" && "$PARTNER_ID" != null && -n "$PARTNER_UID" && "$PARTNER_UID" != null ]] || exit 1

DB_LINK_COUNT="$(psql "$DB_URL" -Atqc "select count(*) from public.partner_users where user_id='$PARTNER_UID'::uuid and partner_id='$PARTNER_ID'::uuid and role='partner_admin' and status='active' and removed_at is null")"
[[ "$DB_LINK_COUNT" == "1" ]] || { echo 'create-partner did not create canonical Partner Admin linkage' >&2; exit 1; }

PARTNER_LOGIN="$(login "$PARTNER_EMAIL")"
PARTNER_TOKEN="$(jq -r '.access_token' <<<"$PARTNER_LOGIN")"
[[ -n "$PARTNER_TOKEN" && "$PARTNER_TOKEN" != null ]] || { echo 'Created Partner cannot log in' >&2; exit 1; }

# Non-Admin signed JWT must be rejected by the trusted Voucher Engine boundary.
DENY_RAW="$(edge_post voucher-engine "$PARTNER_TOKEN" '{"action":"allocate_all","version_id":"00000000-0000-0000-0000-000000000000","quantity":1}')"
DENY_STATUS="$(tail -n1 <<<"$DENY_RAW")"
[[ "$DENY_STATUS" == "403" ]] || { echo "Partner unexpectedly crossed Admin Edge boundary: $DENY_RAW" >&2; exit 1; }

# Evolution Staff provisioning must also cross only the server-only atomic RPC boundary.
MINES_ID="$(psql "$DB_URL" -Atqc "select id from public.branches where branch_code='MINES' and status='active'")"
[[ -n "$MINES_ID" ]] || { echo 'MINES branch missing' >&2; exit 1; }
STAFF_RAW="$(edge_post create-staff "$ADMIN_TOKEN" "{\"staff_name\":\"Edge Mines Staff\",\"email\":\"$STAFF_EMAIL\",\"password\":\"$password\",\"branch_id\":\"$MINES_ID\",\"role\":\"staff\"}")"
STAFF_STATUS="$(tail -n1 <<<"$STAFF_RAW")"
STAFF_BODY="$(sed '$d' <<<"$STAFF_RAW")"
[[ "$STAFF_STATUS" == "201" ]] || { echo "create-staff failed ($STAFF_STATUS): $STAFF_BODY" >&2; exit 1; }
[[ "$(jq -r '.success' <<<"$STAFF_BODY")" == "true" ]] || { echo "$STAFF_BODY" >&2; exit 1; }
STAFF_UID="$(jq -r '.staff.user_id' <<<"$STAFF_BODY")"
[[ -n "$STAFF_UID" && "$STAFF_UID" != null ]] || { echo 'Staff Auth linkage missing' >&2; exit 1; }
STAFF_LOGIN="$(login "$STAFF_EMAIL")"
STAFF_TOKEN="$(jq -r '.access_token' <<<"$STAFF_LOGIN")"
[[ -n "$STAFF_TOKEN" && "$STAFF_TOKEN" != null ]] || { echo 'Created Staff cannot log in' >&2; exit 1; }
STAFF_CONTEXT="$(rpc "$STAFF_TOKEN" staff_operational_context '{}')"
[[ "$(jq -r '.success' <<<"$STAFF_CONTEXT")" == "true" ]] || { echo "Staff context failed: $STAFF_CONTEXT" >&2; exit 1; }
[[ "$(jq -r '.branches[0].branch_code' <<<"$STAFF_CONTEXT")" == "MINES" ]] || { echo "Created Staff not bound to MINES: $STAFF_CONTEXT" >&2; exit 1; }

# Seed one active Version directly as trusted test fixture; allocation itself MUST go through Edge -> atomic RPC.
psql "$DB_URL" -v ON_ERROR_STOP=1 <<'SQL'
begin;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
insert into public.voucher_templates(template_code,template_name,voucher_category,status,theme_code)
values ('EDGE-E2E','Edge E2E Voucher','test','active','default');
insert into public.voucher_versions(template_id,version_no,version_name,face_value,validity_mode,valid_days,usage_limit,supply_limit,all_branches,status,effective_from)
select id,1,'Edge E2E v1',60,'days',30,1,20,true,'active',now()
from public.voucher_templates where template_code='EDGE-E2E';
update public.voucher_templates vt set current_version_id=vv.id
from public.voucher_versions vv
where vv.template_id=vt.id and vt.template_code='EDGE-E2E' and vv.version_no=1;
commit;
SQL
VERSION_ID="$(psql "$DB_URL" -Atqc "select vv.id from public.voucher_versions vv join public.voucher_templates vt on vt.id=vv.template_id where vt.template_code='EDGE-E2E' and vv.version_no=1")"

ALLOC_RAW="$(edge_post voucher-engine "$ADMIN_TOKEN" "{\"action\":\"allocate\",\"partner_id\":\"$PARTNER_ID\",\"version_id\":\"$VERSION_ID\",\"quantity\":2}")"
ALLOC_STATUS="$(tail -n1 <<<"$ALLOC_RAW")"
ALLOC_BODY="$(sed '$d' <<<"$ALLOC_RAW")"
[[ "$ALLOC_STATUS" == "200" ]] || { echo "Voucher Engine allocate failed ($ALLOC_STATUS): $ALLOC_BODY" >&2; exit 1; }
[[ "$(jq -r '.success' <<<"$ALLOC_BODY")" == "true" ]] || { echo "$ALLOC_BODY" >&2; exit 1; }

ALLOC_QTY="$(psql "$DB_URL" -Atqc "select quantity_allocated from public.partner_voucher_allocations where partner_id='$PARTNER_ID'::uuid and version_id='$VERSION_ID'::uuid and status='active'")"
[[ "$ALLOC_QTY" == "2" ]] || { echo "Atomic Edge allocation did not persist expected quantity: $ALLOC_QTY" >&2; exit 1; }

ACCESS_COUNT="$(psql "$DB_URL" -Atqc "select count(*) from public.partner_voucher_access pva join public.voucher_templates vt on vt.id=pva.template_id where pva.partner_id='$PARTNER_ID'::uuid and vt.template_code='EDGE-E2E' and pva.status='active'")"
[[ "$ACCESS_COUNT" == "1" ]] || { echo 'Atomic allocation did not establish active Partner voucher access' >&2; exit 1; }

echo 'Edge Function trusted-boundary E2E passed.'
