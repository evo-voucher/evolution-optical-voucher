create or replace function public.admin_preview_allocation_effective_branches(
  p_partner_id uuid,
  p_version_id uuid,
  p_all_branches boolean default true,
  p_branch_codes text[] default null
)
returns table(
  branch_id uuid,
  branch_code text,
  branch_name text,
  address text,
  phone text
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_partner_all boolean := false;
  v_version_all boolean := false;
  v_requested integer := 0;
  v_resolved integer := 0;
begin
  if not public.is_voucher_admin() then
    raise exception 'Admin access required';
  end if;

  if not exists(select 1 from public.partners p where p.id=p_partner_id and p.status='active') then
    raise exception 'Active Partner not found';
  end if;

  select vv.all_branches
  into v_version_all
  from public.voucher_versions vv
  join public.voucher_templates vt on vt.id=vv.template_id
  where vv.id=p_version_id and vv.status='active' and vt.status='active';
  if not found then raise exception 'Active Voucher Version not found'; end if;

  select coalesce(s.all_branches,false)
  into v_partner_all
  from public.partner_claim_settings s
  where s.partner_id=p_partner_id;
  if not found then v_partner_all:=false; end if;

  if not coalesce(p_all_branches,true) then
    v_requested:=coalesce((
      select count(distinct upper(trim(x)))
      from unnest(coalesce(p_branch_codes,array[]::text[])) x
      where nullif(trim(x),'') is not null
    ),0);
    if v_requested<1 then raise exception 'Select at least one Allocation branch'; end if;

    select count(*) into v_resolved
    from public.branches b
    where b.status='active'
      and upper(b.branch_code)=any(
        select upper(trim(x))
        from unnest(coalesce(p_branch_codes,array[]::text[])) x
        where nullif(trim(x),'') is not null
      );
    if v_resolved<>v_requested then raise exception 'One or more Allocation branches are invalid or inactive'; end if;
  end if;

  return query
  select b.id,b.branch_code,b.branch_name,b.address,b.phone
  from public.branches b
  where b.status='active'
    and (
      v_partner_all
      or exists(
        select 1 from public.partner_claim_branches pcb
        where pcb.partner_id=p_partner_id and pcb.branch_id=b.id
      )
    )
    and (
      v_version_all
      or exists(
        select 1 from public.voucher_version_branches vvb
        where vvb.version_id=p_version_id and vvb.branch_id=b.id
      )
    )
    and (
      coalesce(p_all_branches,true)
      or upper(b.branch_code)=any(
        select upper(trim(x))
        from unnest(coalesce(p_branch_codes,array[]::text[])) x
        where nullif(trim(x),'') is not null
      )
    )
  order by b.branch_name,b.branch_code;
end;
$$;

revoke all on function public.admin_preview_allocation_effective_branches(uuid,uuid,boolean,text[]) from public,anon;
grant execute on function public.admin_preview_allocation_effective_branches(uuid,uuid,boolean,text[]) to authenticated;
