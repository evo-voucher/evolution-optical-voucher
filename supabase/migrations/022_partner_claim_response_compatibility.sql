-- Partner claim access response compatibility v1
-- Purpose: preserve the proven Partner UI contract while keeping the canonical
-- branch object array used by the reconstructed backend.
--
-- Historical Partner UI expects branch_codes + branch_names.
-- Newer code may use branches[] with code/name/address/phone.
-- Return both from one authoritative query; do not duplicate business logic.

create or replace function public.get_my_partner_claim_access()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_partner uuid := public.current_partner_id();
  v_all boolean := false;
  v_branches jsonb := '[]'::jsonb;
  v_branch_codes text[] := '{}'::text[];
  v_branch_names text[] := '{}'::text[];
begin
  if v_partner is null then
    raise exception 'Active Partner account not found';
  end if;

  select coalesce(s.all_branches,false)
  into v_all
  from public.partner_claim_settings s
  where s.partner_id=v_partner;

  if not found then
    v_all := false;
  end if;

  select
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'branch_code',b.branch_code,
          'branch_name',b.branch_name,
          'address',b.address,
          'phone',b.phone
        ) order by b.branch_name
      ),
      '[]'::jsonb
    ),
    coalesce(array_agg(b.branch_code order by b.branch_name),'{}'::text[]),
    coalesce(array_agg(b.branch_name order by b.branch_name),'{}'::text[])
  into v_branches,v_branch_codes,v_branch_names
  from public.partner_claim_branches pcb
  join public.branches b on b.id=pcb.branch_id
  where pcb.partner_id=v_partner
    and b.status='active';

  return jsonb_build_object(
    'success',true,
    'partner_id',v_partner,
    'all_branches',v_all,
    'branch_codes',v_branch_codes,
    'branch_names',v_branch_names,
    'branches',v_branches
  );
end;
$$;

revoke all on function public.get_my_partner_claim_access() from public, anon;
grant execute on function public.get_my_partner_claim_access() to authenticated;
