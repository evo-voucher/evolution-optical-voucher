-- Trusted server tenant boundary v1
-- Purpose: keep Partner tenant guards strict for browser/authenticated users while
-- allowing explicitly trusted service_role server code (e.g. Admin Edge Functions)
-- to perform cross-Partner administrative operations.
--
-- Why this exists:
-- 019 write guards call assert_partner_tenant(). Edge Functions such as the
-- Voucher Engine use a service-role Supabase client after separately verifying
-- the caller is an active Admin. In that database request auth.uid() is not the
-- Admin caller, so an Admin-only test based only on is_voucher_admin() can reject
-- legitimate server writes. The service_role JWT claim is the correct server
-- boundary; it is signed by Supabase and is never present in browser keys.

create or replace function public.is_trusted_service_role()
returns boolean
language sql
stable
security invoker
set search_path = public
as $$
  select coalesce((auth.jwt() ->> 'role') = 'service_role', false);
$$;

revoke all on function public.is_trusted_service_role() from public, anon;
grant execute on function public.is_trusted_service_role() to authenticated, service_role;

create or replace function public.assert_partner_tenant(p_partner_id uuid)
returns void
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  -- Cross-Partner access is allowed only for:
  -- 1) an authenticated active Voucher Admin operating through user-context RPCs; or
  -- 2) trusted service_role server code whose caller authorization is enforced by
  --    the server/Edge Function before the database write.
  if public.is_voucher_admin() or public.is_trusted_service_role() then
    return;
  end if;

  if p_partner_id is null or p_partner_id is distinct from public.current_partner_id() then
    raise exception 'Cross-Partner access denied';
  end if;
end;
$$;

revoke all on function public.assert_partner_tenant(uuid) from public, anon;
grant execute on function public.assert_partner_tenant(uuid) to authenticated, service_role;

-- 019 defined Partner User tenant protection separately rather than through
-- assert_partner_tenant(). Bring it under the same trusted-server boundary.
create or replace function public.guard_partner_user_tenant()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if public.is_voucher_admin() or public.is_trusted_service_role() then
    return new;
  end if;

  if new.partner_id is null or new.partner_id is distinct from public.current_partner_id() then
    raise exception 'Cross-Partner Partner User write denied';
  end if;

  return new;
end;
$$;

-- Defensive rule: public/anon must never be able to invoke the helper directly.
-- service_role may execute it only inside trusted server requests.
revoke all on function public.guard_partner_user_tenant() from public, anon;

comment on function public.is_trusted_service_role() is
'True only for a verified Supabase service_role JWT. Never expose a service_role credential to browser code.';

comment on function public.assert_partner_tenant(uuid) is
'Partner tenant assertion. Allows current Partner, active Admin user context, or verified service_role server context only.';
