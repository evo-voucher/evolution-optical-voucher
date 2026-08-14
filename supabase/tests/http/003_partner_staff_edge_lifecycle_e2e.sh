#!/usr/bin/env bash
set -euo pipefail

API_URL="http://127.0.0.1:54321"
DB_URL="postgresql://postgres:postgres@127.0.0.1:54322/postgres"
eval "$(supabase status -o env | grep -E '^(ANON_KEY|SERVICE_ROLE_KEY)=' | sed 's/^/export /')"
: "${ANON_KEY:?ANON_KEY missing}"

suffix="$(date +%s)-$RANDOM"
password='EvoPartnerStaff!123456'
new_password='EvoPartnerStaff!654321'
ADMIN_EMAIL="ps-admin-$suffix@example.test"
PARTNER_EMAIL="ps-partner-$suffix@example.test"
STAFF_EMAIL="ps-staff-$suffix@example.test"
PARTNER_CODE="PS_$RANDOM"

signup() {
  curl -fsS "$API_URL/auth/v1/signup" -H "apikey: $ANON_KEY" -H 'Content-Type: application/json' \
    -d "{\"email\":\"$1\",\"password\":\"$2\"}"
}
login() {
  curl -fsS "$API_URL/auth/v1/token?grant_type=password" -H "apikey: $ANON_KEY" -H 'Content-Type: application/json' \
    -d "{\"email\":\"$1\",\"password\":\"$2\"}"
}
edge_post() {
  local fn="$1" token="$2" body="$3"
  curl -sS -w '\n%{http_code}' "$API_URL/functions/v1/$fn" \
    -H "apikey: $ANON_KEY" -H "Authorization: Bearer $token" -H 'Content-Type: application/json' -d "$body"
}

signup "$ADMIN_EMAIL" "$password" >/dev/null
ADMIN_LOGIN="$(login "$ADMIN_EMAIL" "$password")"
ADMIN_UID="$(jq -r '.user.id' <<<"$ADMIN_LOGIN")"
ADMIN_TOKEN="$(jq -r '.access_token' <<<"$ADMIN_LOGIN")"

psql "$DB_URL" -v ON_ERROR_STOP=1 -v uid="$ADMIN_UID" <<'SQL'
begin;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
insert into public.admin_users(user_id,display_name,status) values(:'uid'::uuid,'Partner Staff E2E Admin','active');
commit;
SQL

CREATE_PARTNER="$(edge_post create-partner "$ADMIN_TOKEN" "{\"partner_code\":\"$PARTNER_CODE\",\"partner_name\":\"Partner Staff E2E\",\"contact_person\":\"PS Admin\",\"email\":\"$PARTNER_EMAIL\",\"password\":\"$password\",\"voucher_limit\":0,\"staff_limit\":2}")"
[[ "$(tail -n1 <<<"$CREATE_PARTNER")" == "201" ]] || { echo "$CREATE_PARTNER" >&2; exit 1; }
PARTNER_LOGIN="$(login "$PARTNER_EMAIL" "$password")"
PARTNER_TOKEN="$(jq -r '.access_token' <<<"$PARTNER_LOGIN")"
[[ -n "$PARTNER_TOKEN" && "$PARTNER_TOKEN" != null ]] || exit 1

CREATE_STAFF="$(edge_post manage-partner-staff "$PARTNER_TOKEN" "{\"action\":\"create\",\"staff_name\":\"Partner Staff One\",\"email\":\"$STAFF_EMAIL\",\"password\":\"$password\"}")"
[[ "$(tail -n1 <<<"$CREATE_STAFF")" == "201" ]] || { echo "Partner Staff create failed: $CREATE_STAFF" >&2; exit 1; }
CREATE_BODY="$(sed '$d' <<<"$CREATE_STAFF")"
STAFF_ID="$(jq -r '.staff.id' <<<"$CREATE_BODY")"
STAFF_UID="$(jq -r '.staff.user_id' <<<"$CREATE_BODY")"
[[ -n "$STAFF_ID" && "$STAFF_ID" != null && -n "$STAFF_UID" && "$STAFF_UID" != null ]] || exit 1

# Created Partner Staff must belong to the caller Partner and be a distinct Partner realm identity.
PARTNER_ID="$(psql "$DB_URL" -Atqc "select partner_id from public.partner_users where user_id='${STAFF_UID}'::uuid")"
CALLER_PARTNER_ID="$(psql "$DB_URL" -Atqc "select partner_id from public.partner_users where user_id='$(jq -r '.user.id' <<<"$PARTNER_LOGIN")'::uuid")"
[[ "$PARTNER_ID" == "$CALLER_PARTNER_ID" ]] || { echo 'Partner Staff crossed tenant boundary' >&2; exit 1; }

RENAME="$(edge_post manage-partner-staff "$PARTNER_TOKEN" "{\"action\":\"rename\",\"staff_id\":\"$STAFF_ID\",\"staff_name\":\"Renamed Partner Staff\"}")"
[[ "$(tail -n1 <<<"$RENAME")" == "200" ]] || { echo "$RENAME" >&2; exit 1; }
[[ "$(jq -r '.staff.staff_name' <<<"$(sed '$d' <<<"$RENAME")")" == "Renamed Partner Staff" ]] || exit 1

SUSPEND="$(edge_post manage-partner-staff "$PARTNER_TOKEN" "{\"action\":\"suspend\",\"staff_id\":\"$STAFF_ID\"}")"
[[ "$(tail -n1 <<<"$SUSPEND")" == "200" ]] || { echo "$SUSPEND" >&2; exit 1; }
[[ "$(jq -r '.staff.status' <<<"$(sed '$d' <<<"$SUSPEND")")" == "suspended" ]] || exit 1

ACTIVATE="$(edge_post manage-partner-staff "$PARTNER_TOKEN" "{\"action\":\"activate\",\"staff_id\":\"$STAFF_ID\"}")"
[[ "$(tail -n1 <<<"$ACTIVATE")" == "200" ]] || { echo "$ACTIVATE" >&2; exit 1; }
[[ "$(jq -r '.staff.status' <<<"$(sed '$d' <<<"$ACTIVATE")")" == "active" ]] || exit 1

RESET="$(edge_post manage-partner-staff "$PARTNER_TOKEN" "{\"action\":\"reset_password\",\"staff_id\":\"$STAFF_ID\",\"new_password\":\"$new_password\"}")"
[[ "$(tail -n1 <<<"$RESET")" == "200" ]] || { echo "$RESET" >&2; exit 1; }
NEW_LOGIN="$(login "$STAFF_EMAIL" "$new_password")"
[[ "$(jq -r '.user.id' <<<"$NEW_LOGIN")" == "$STAFF_UID" ]] || { echo 'Reset password did not authenticate target Staff' >&2; exit 1; }

REMOVE="$(edge_post manage-partner-staff "$PARTNER_TOKEN" "{\"action\":\"remove\",\"staff_id\":\"$STAFF_ID\"}")"
[[ "$(tail -n1 <<<"$REMOVE")" == "200" ]] || { echo "$REMOVE" >&2; exit 1; }
[[ "$(jq -r '.staff.status' <<<"$(sed '$d' <<<"$REMOVE")")" == "removed" ]] || exit 1
REMOVED_AT="$(jq -r '.staff.removed_at' <<<"$(sed '$d' <<<"$REMOVE")")"
[[ -n "$REMOVED_AT" && "$REMOVED_AT" != null ]] || { echo 'Removed Partner Staff missing removed_at' >&2; exit 1; }

# After removal the Auth UID must be released from the operational Partner realm registry.
REALM_COUNT="$(psql "$DB_URL" -Atqc "select count(*) from public.operational_identity_realms where user_id='${STAFF_UID}'::uuid")"
[[ "$REALM_COUNT" == "0" ]] || { echo 'Removed Partner Staff still owns operational realm' >&2; exit 1; }

echo 'Partner Staff Edge lifecycle E2E passed.'
