-- Converge allocation supply and effective branch-scope guards with Production.
-- Production remains read-only reference.

create or replace function public.guard_allocation_supply_capacity()
returns trigger
language plpgsql
set search_path to 'public'
as $function$
declare
  v_supply_limit integer;
  v_reserved bigint;
begin
  if new.status <> 'active' then return new; end if;

  perform pg_advisory_xact_lock(hashtextextended(new.version_id::text,2601));

  select vv.supply_limit into v_supply_limit
  from public.voucher_versions vv
  where vv.id=new.version_id;

  if v_supply_limit is null then return new; end if;

  select coalesce(sum(a.quantity_allocated-a.quantity_revoked),0)
  into v_reserved
  from public.partner_voucher_allocations a
  where a.version_id=new.version_id
    and a.status='active'
    and a.id<>new.id;

  v_reserved:=v_reserved+(new.quantity_allocated-new.quantity_revoked);
  if v_reserved>v_supply_limit then
    raise exception 'Voucher Version supply limit exceeded: reserved %, supply limit %',v_reserved,v_supply_limit;
  end if;
  return new;
end;
$function$;

create or replace function public.guard_allocation_effective_branch_scope()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_allocation_id uuid;
  v_partner_id uuid;
  v_version_id uuid;
  v_allocation_all boolean;
  v_partner_all boolean := false;
  v_version_all boolean := false;
  v_has_effective boolean := false;
begin
  if tg_table_name='partner_voucher_allocations' then
    v_allocation_id := case when tg_op='DELETE' then old.id else new.id end;
  elsif tg_table_name='partner_voucher_allocation_branches' then
    v_allocation_id := case when tg_op='DELETE' then old.allocation_id else new.allocation_id end;
  else
    raise exception 'Unsupported allocation scope guard table: %',tg_table_name;
  end if;

  select a.partner_id,a.version_id,a.all_branches
  into v_partner_id,v_version_id,v_allocation_all
  from public.partner_voucher_allocations a
  where a.id=v_allocation_id;

  if not found then
    return coalesce(new,old);
  end if;

  select coalesce(s.all_branches,false)
  into v_partner_all
  from public.partner_claim_settings s
  where s.partner_id=v_partner_id;
  if not found then v_partner_all:=false; end if;

  select coalesce(vv.all_branches,false)
  into v_version_all
  from public.voucher_versions vv
  where vv.id=v_version_id;
  if not found then v_version_all:=false; end if;

  select exists(
    select 1
    from public.branches b
    where b.status='active'
      and (
        v_partner_all
        or exists(
          select 1 from public.partner_claim_branches pcb
          where pcb.partner_id=v_partner_id and pcb.branch_id=b.id
        )
      )
      and (
        v_version_all
        or exists(
          select 1 from public.voucher_version_branches vvb
          where vvb.version_id=v_version_id and vvb.branch_id=b.id
        )
      )
      and (
        coalesce(v_allocation_all,true)
        or exists(
          select 1 from public.partner_voucher_allocation_branches ab
          where ab.allocation_id=v_allocation_id and ab.branch_id=b.id
        )
      )
  ) into v_has_effective;

  if not v_has_effective then
    raise exception 'Allocation must retain at least one effective redemption branch';
  end if;

  return coalesce(new,old);
end;
$function$;

revoke all on function public.guard_allocation_supply_capacity() from public, anon, authenticated, service_role;
revoke all on function public.guard_allocation_effective_branch_scope() from public, anon, authenticated, service_role;

drop trigger if exists vouchers_guard_allocation_supply_capacity on public.partner_voucher_allocations;
create trigger vouchers_guard_allocation_supply_capacity
before insert or update of version_id, quantity_allocated, quantity_revoked, status
on public.partner_voucher_allocations
for each row execute function public.guard_allocation_supply_capacity();

drop trigger if exists allocation_guard_effective_branch_scope on public.partner_voucher_allocations;
create constraint trigger allocation_guard_effective_branch_scope
after insert or update of partner_id, version_id, all_branches
on public.partner_voucher_allocations
deferrable initially deferred
for each row execute function public.guard_allocation_effective_branch_scope();

drop trigger if exists allocation_branch_guard_effective_scope on public.partner_voucher_allocation_branches;
create constraint trigger allocation_branch_guard_effective_scope
after insert or delete or update
on public.partner_voucher_allocation_branches
deferrable initially deferred
for each row execute function public.guard_allocation_effective_branch_scope();
