create table if not exists public.admin_notification_reads (
  admin_user_id uuid not null references auth.users(id) on delete cascade,
  event_id text not null,
  read_at timestamptz not null default now(),
  expires_at timestamptz not null,
  primary key (admin_user_id, event_id)
);

alter table public.admin_notification_reads enable row level security;
revoke all on table public.admin_notification_reads from public, anon, authenticated;

create index if not exists admin_notification_reads_expires_idx
  on public.admin_notification_reads (expires_at);

create or replace function public.admin_notifications(p_limit integer default 30)
returns table (
  event_id text,
  event_type text,
  event_time timestamptz,
  partner_id uuid,
  partner_name text,
  title text,
  detail text,
  voucher_id uuid,
  voucher_code text,
  branch_name text,
  is_read boolean
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_voucher_admin() then
    raise exception 'Admin access required';
  end if;

  delete from public.admin_notification_reads r
  where r.admin_user_id = auth.uid()
    and r.expires_at <= now();

  return query
  select
    a.event_id,
    a.event_type,
    a.event_time,
    a.partner_id,
    a.partner_name,
    a.title,
    a.detail,
    a.voucher_id,
    a.voucher_code,
    a.branch_name,
    (r.event_id is not null) as is_read
  from public.admin_latest_activity(least(greatest(coalesce(p_limit, 30), 1), 100)) a
  left join public.admin_notification_reads r
    on r.admin_user_id = auth.uid()
   and r.event_id = a.event_id
   and r.expires_at > now()
  where a.event_time >= now() - interval '24 hours'
  order by a.event_time desc, a.event_id desc
  limit least(greatest(coalesce(p_limit, 30), 1), 100);
end;
$$;

create or replace function public.admin_mark_notifications_read()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer := 0;
begin
  if not public.is_voucher_admin() then
    raise exception 'Admin access required';
  end if;

  delete from public.admin_notification_reads r
  where r.admin_user_id = auth.uid()
    and r.expires_at <= now();

  insert into public.admin_notification_reads (admin_user_id, event_id, read_at, expires_at)
  select
    auth.uid(),
    a.event_id,
    now(),
    a.event_time + interval '24 hours'
  from public.admin_latest_activity(100) a
  where a.event_time >= now() - interval '24 hours'
  on conflict (admin_user_id, event_id)
  do update set
    read_at = excluded.read_at,
    expires_at = excluded.expires_at;

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke all on function public.admin_notifications(integer) from public, anon;
revoke all on function public.admin_mark_notifications_read() from public, anon;
grant execute on function public.admin_notifications(integer) to authenticated;
grant execute on function public.admin_mark_notifications_read() to authenticated;
