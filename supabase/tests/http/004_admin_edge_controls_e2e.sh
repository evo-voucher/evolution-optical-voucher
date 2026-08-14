#!/usr/bin/env bash
set -euo pipefail

API_URL="http://127.0.0.1:54321"
DB_URL="postgresql://postgres:postgres@127.0.0.1:54322/postgres"
eval "$(supabase status -o env | grep -E '^(ANON_KEY|SERVICE_ROLE_KEY)=' | sed 's/^/export /')"
: "${ANON_KEY:?ANON_KEY missing}"

suffix="$(date +%s)-$RANDOM"
password='EvoAdminEdge!123456'
new_password='EvoAdminEdge!654321'
ADMIN_EMAIL="ctrl-admin-$suffix@example.test"
PARTNER_EMAIL="ctrl-partner-$suffix@example.test"
PARTNER_CODE="CTRL_$RANDOM"

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
insert into public.admin_users(user_id,display_name,status) values(:'uid'::uuid,'Admin Controls E2E','active');
commit;
SQL

CREATE="$(edge_post create-partner "$ADMIN_TOKEN" "{\"partner_code\":\"$PARTNER_CODE\",\"partner_name\":\"Admin Controls Partner\",\"contact_person\":\"Control Admin\",\"email\":\"$PARTNER_EMAIL\",\"password\":\"$password\",\"voucher_limit\":0,\"staff_limit\":1}")"
[[ "$(tail -n1 <<<"$CREATE")" == "201" ]] || { echo "$CREATE" >&2; exit 1; }
CREATE_BODY="$(sed '$d' <<<"$CREATE")"
PARTNER_ID="$(jq -r '.partner.id' <<<"$CREATE_BODY")"
[[ -n "$PARTNER_ID" && "$PARTNER_ID" != null ]] || exit 1

PARTNER_LOGIN="$(login "$PARTNER_EMAIL" "$password")"
PARTNER_TOKEN="$(jq -r '.access_token' <<<"$PARTNER_LOGIN")"
PARTNER_UID="$(jq -r '.user.id' <<<"$PARTNER_LOGIN")"

LIMIT="$(edge_post admin-set-partner-staff-limit "$ADMIN_TOKEN" "{\"partner_id\":\"$PARTNER_ID\",\"staff_limit\":5}")"
[[ "$(tail -n1 <<<"$LIMIT")" == "200" ]] || { echo "Admin staff-limit update failed: $LIMIT" >&2; exit 1; }
DB_LIMIT="$(psql "$DB_URL" -Atqc "select staff_limit from public.partners where id='$PARTNER_ID'::uuid")"
[[ "$DB_LIMIT" == "5" ]] || { echo "Staff limit mismatch: $DB_LIMIT" >&2; exit 1; }

# Partner JWT must not cross the Admin control RPC boundary.
PARTNER_LIMIT="$(edge_post admin-set-partner-staff-limit "$PARTNER_TOKEN" "{\"partner_id\":\"$PARTNER_ID\",\"staff_limit\":9}")"
[[ "$(tail -n1 <<<"$PARTNER_LIMIT")" != "200" ]] || { echo 'Partner unexpectedly changed Admin staff limit' >&2; exit 1; }
[[ "$(psql "$DB_URL" -Atqc "select staff_limit from public.partners where id='$PARTNER_ID'::uuid")" == "5" ]] || exit 1

RESET="$(edge_post reset-partner-password "$ADMIN_TOKEN" "{\"partner_id\":\"$PARTNER_ID\",\"new_password\":\"$new_password\"}")"
[[ "$(tail -n1 <<<"$RESET")" == "200" ]] || { echo "Admin Partner password reset failed: $RESET" >&2; exit 1; }
NEW_LOGIN="$(login "$PARTNER_EMAIL" "$new_password")"
[[ "$(jq -r '.user.id' <<<"$NEW_LOGIN")" == "$PARTNER_UID" ]] || { echo 'Partner cannot authenticate with reset password' >&2; exit 1; }

# A Partner signed JWT must be rejected before Auth-admin mutation.
NEW_PARTNER_TOKEN="$(jq -r '.access_token' <<<"$NEW_LOGIN")"
DENY_RESET="$(edge_post reset-partner-password "$NEW_PARTNER_TOKEN" "{\"partner_id\":\"$PARTNER_ID\",\"new_password\":\"$password\"}")"
[[ "$(tail -n1 <<<"$DENY_RESET")" == "403" ]] || { echo "Partner unexpectedly crossed reset boundary: $DENY_RESET" >&2; exit 1; }

AUDIT_COUNT="$(psql "$DB_URL" -Atqc "select count(*) from public.admin_audit_log where action_type='partner_password_reset' and partner_id='$PARTNER_ID'::uuid and actor_user_id='$ADMIN_UID'::uuid")"
[[ "$AUDIT_COUNT" == "1" ]] || { echo "Expected one Partner password reset audit row, got $AUDIT_COUNT" >&2; exit 1; }

echo 'Admin Edge controls E2E passed.'
