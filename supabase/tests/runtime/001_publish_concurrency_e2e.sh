#!/usr/bin/env bash
set -euo pipefail

DB_URL="postgresql://postgres:postgres@127.0.0.1:54322/postgres"
ADMIN_UID="55555555-5555-4555-8555-555555555555"
TEMPLATE_CODE="CONCURRENCY_RUNTIME_TEST"

psql "$DB_URL" -v ON_ERROR_STOP=1 <<SQL
begin;
insert into auth.users(id,aud,role,email,encrypted_password,email_confirmed_at,created_at,updated_at,instance_id)
values ('$ADMIN_UID','authenticated','authenticated','publish-concurrency@example.test','',now(),now(),now(),'00000000-0000-0000-0000-000000000000')
on conflict (id) do nothing;
insert into public.admin_users(user_id,display_name,status)
values ('$ADMIN_UID','Concurrency Runtime Admin','active')
on conflict (user_id) do update set status='active';
delete from public.voucher_versions where template_id in (select id from public.voucher_templates where template_code='$TEMPLATE_CODE');
delete from public.voucher_templates where template_code='$TEMPLATE_CODE';
insert into public.voucher_templates(template_code,template_name,voucher_category,status,theme_code,created_by)
values ('$TEMPLATE_CODE','Concurrency Runtime Template','test','active','default','$ADMIN_UID');
commit;
SQL

TEMPLATE_ID="$(psql "$DB_URL" -Atqc "select id from public.voucher_templates where template_code='$TEMPLATE_CODE'")"
if [[ -z "$TEMPLATE_ID" ]]; then
  echo "Template fixture was not created" >&2
  exit 1
fi

publish_one() {
  local version_name="$1"
  psql "$DB_URL" -v ON_ERROR_STOP=1 <<SQL
begin;
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"$ADMIN_UID","role":"authenticated"}',true);
select public.admin_publish_voucher_version_theme(
  '$TEMPLATE_ID'::uuid,
  '$version_name',
  60,
  null,
  'calendar_months_after_issue',
  null,
  3,
  null,
  null,
  1,
  true,
  null,
  100,
  true,
  null
);
commit;
SQL
}

publish_one "Concurrent A" > /tmp/evo-publish-a.log 2>&1 &
PID_A=$!
publish_one "Concurrent B" > /tmp/evo-publish-b.log 2>&1 &
PID_B=$!

set +e
wait "$PID_A"; STATUS_A=$?
wait "$PID_B"; STATUS_B=$?
set -e

if [[ "$STATUS_A" -ne 0 || "$STATUS_B" -ne 0 ]]; then
  echo "Concurrent publish failed" >&2
  cat /tmp/evo-publish-a.log >&2 || true
  cat /tmp/evo-publish-b.log >&2 || true
  exit 1
fi

RESULT="$(psql "$DB_URL" -Atqc "select count(*)||':'||min(version_no)||':'||max(version_no)||':'||count(distinct version_no) from public.voucher_versions where template_id='$TEMPLATE_ID'::uuid")"
if [[ "$RESULT" != "2:1:2:2" ]]; then
  echo "Concurrent publish did not serialize into distinct canonical version numbers. Got $RESULT" >&2
  psql "$DB_URL" -c "select version_no,version_name,id from public.voucher_versions where template_id='$TEMPLATE_ID'::uuid order by version_no" >&2
  exit 1
fi

CURRENT_NO="$(psql "$DB_URL" -Atqc "select vv.version_no from public.voucher_templates vt join public.voucher_versions vv on vv.id=vt.current_version_id where vt.id='$TEMPLATE_ID'::uuid")"
if [[ "$CURRENT_NO" != "2" ]]; then
  echo "Template current_version_id does not point to the latest serialized version. Got version $CURRENT_NO" >&2
  exit 1
fi

psql "$DB_URL" -v ON_ERROR_STOP=1 <<SQL
begin;
delete from public.voucher_versions where template_id='$TEMPLATE_ID'::uuid;
delete from public.voucher_templates where id='$TEMPLATE_ID'::uuid;
delete from public.admin_users where user_id='$ADMIN_UID'::uuid;
delete from auth.users where id='$ADMIN_UID'::uuid;
commit;
SQL

echo "Concurrent voucher version publish runtime E2E passed: versions 1 and 2 published without collision."
