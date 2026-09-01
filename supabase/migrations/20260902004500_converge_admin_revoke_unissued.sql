-- Converge admin_engine_revoke_unissued(...) to the current Production behavior.
--
-- Production migration history contains an explicit hard-delete / hard-reduce
-- allocation path; voucher-stage currently carries an older soft-revoke
-- implementation that increments quantity_revoked and preserves allocation
-- event rows. This migration replaces only this exact function signature.
--
-- Production remains read-only; apply to voucher-stage first.

CREATE OR REPLACE FUNCTION public.admin_engine_revoke_unissued(
  p_allocation_id uuid,
  p_quantity integer,
  p_reason text DEFAULT NULL::text,
  p_actor_user_id uuid DEFAULT NULL::uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
declare
  v_actor uuid;
  v_allocation public.partner_voucher_allocations%rowtype;
  v_issued bigint;
  v_remaining bigint;
  v_new_allocated integer;
  v_template_id uuid;
  v_deleted boolean := false;
begin
  if p_allocation_id is null then raise exception 'Allocation is required'; end if;
  if p_quantity is null or p_quantity < 1 then raise exception 'Quantity must be positive'; end if;

  if public.is_voucher_admin() then
    v_actor := (select auth.uid());
  elsif public.is_trusted_service_role() then
    v_actor := p_actor_user_id;
  else
    raise exception 'Admin access required';
  end if;

  if not exists(select 1 from public.admin_users a where a.user_id=v_actor and a.status='active') then
    raise exception 'Active Admin actor required';
  end if;

  select * into v_allocation
  from public.partner_voucher_allocations a
  where a.id=p_allocation_id and a.status='active'
  for update;
  if not found then raise exception 'Active allocation not found'; end if;

  select count(*) into v_issued
  from public.vouchers v
  where v.allocation_id=p_allocation_id;

  v_remaining := v_allocation.quantity_allocated-v_allocation.quantity_revoked-v_issued;
  if p_quantity > v_remaining then
    raise exception 'Cannot reduce more than remaining unissued quantity';
  end if;

  v_new_allocated := v_allocation.quantity_allocated-p_quantity;
  select vv.template_id into v_template_id
  from public.voucher_versions vv
  where vv.id=v_allocation.version_id;

  delete from public.voucher_allocation_events
  where allocation_id=p_allocation_id;

  if v_new_allocated=0 and v_issued=0 and v_allocation.quantity_revoked=0 then
    delete from public.partner_voucher_allocations where id=p_allocation_id;
    v_deleted := true;

    if v_template_id is not null
       and not exists(
         select 1
         from public.partner_voucher_allocations a
         join public.voucher_versions vv on vv.id=a.version_id
         where a.partner_id=v_allocation.partner_id
           and vv.template_id=v_template_id
           and a.status='active'
       ) then
      delete from public.partner_voucher_access
      where partner_id=v_allocation.partner_id and template_id=v_template_id;
    end if;
  else
    perform set_config('evo.hard_reduce_allowed','on',true);
    update public.partner_voucher_allocations
    set quantity_allocated=v_new_allocated,updated_at=now()
    where id=p_allocation_id;
    perform set_config('evo.hard_reduce_allowed','off',true);
  end if;

  insert into public.admin_audit_log(
    actor_user_id,action_type,entity_type,entity_id,partner_id,before_data,after_data,metadata
  ) values (
    v_actor,'voucher_allocation_hard_reduced','voucher_allocation',p_allocation_id::text,v_allocation.partner_id,
    jsonb_build_object('quantity_allocated',v_allocation.quantity_allocated,'quantity_revoked',v_allocation.quantity_revoked,'issued',v_issued),
    jsonb_build_object('quantity_allocated',v_new_allocated,'allocation_deleted',v_deleted),
    jsonb_build_object('reason',nullif(trim(coalesce(p_reason,'')),''),'history_retained',true)
  );

  return jsonb_build_object(
    'success',true,
    'allocation_id',p_allocation_id,
    'hard_reduced',p_quantity,
    'remaining_unissued',v_remaining-p_quantity,
    'allocation_deleted',v_deleted,
    'history_retained',true
  );
end;
$function$;

REVOKE ALL ON FUNCTION public.admin_engine_revoke_unissued(uuid, integer, text, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_engine_revoke_unissued(uuid, integer, text, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_engine_revoke_unissued(uuid, integer, text, uuid) TO service_role;
