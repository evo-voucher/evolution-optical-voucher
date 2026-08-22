create or replace function public.admin_archive_voucher_template(
  p_template_id uuid,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_actor_name text;
  v_template_code text;
  v_template_name text;
  v_status text;
  v_versions_retired bigint := 0;
  v_allocations_closed bigint := 0;
begin
  if not public.is_voucher_admin() then
    raise exception 'Admin access required';
  end if;
  if p_template_id is null then
    raise exception 'Classification is required';
  end if;

  select coalesce(nullif(trim(a.display_name),''),'Admin')
    into v_actor_name
  from public.admin_users a
  where a.user_id=v_actor and a.status='active';
  if not found then raise exception 'Active Admin actor required'; end if;

  perform pg_advisory_xact_lock(hashtextextended(p_template_id::text, 2801));

  select t.template_code,t.template_name,t.status
    into v_template_code,v_template_name,v_status
  from public.voucher_templates t
  where t.id=p_template_id
  for update;
  if not found then raise exception 'Voucher Classification not found'; end if;

  if v_status='archived' then
    return jsonb_build_object(
      'success',true,
      'template_id',p_template_id,
      'template_code',v_template_code,
      'status','archived',
      'already_archived',true,
      'versions_retired',0,
      'allocations_closed',0
    );
  end if;

  update public.voucher_versions
     set status='inactive'
   where template_id=p_template_id
     and status='active';
  get diagnostics v_versions_retired=row_count;

  update public.partner_voucher_allocations a
     set status='closed',updated_at=now()
   where a.status='active'
     and exists (
       select 1 from public.voucher_versions vv
       where vv.id=a.version_id and vv.template_id=p_template_id
     );
  get diagnostics v_allocations_closed=row_count;

  update public.voucher_templates
     set status='archived'
   where id=p_template_id;

  insert into public.admin_audit_log(
    actor_user_id,actor_name,action_type,entity_type,entity_id,after_data,metadata
  ) values (
    v_actor,v_actor_name,'voucher_template_archived','voucher_template',p_template_id::text,
    jsonb_build_object(
      'template_code',v_template_code,
      'template_name',v_template_name,
      'status','archived',
      'versions_retired',v_versions_retired,
      'allocations_closed',v_allocations_closed
    ),
    jsonb_build_object('reason',nullif(trim(coalesce(p_reason,'')),''))
  );

  return jsonb_build_object(
    'success',true,
    'template_id',p_template_id,
    'template_code',v_template_code,
    'status','archived',
    'already_archived',false,
    'versions_retired',v_versions_retired,
    'allocations_closed',v_allocations_closed
  );
end;
$function$;

revoke all on function public.admin_archive_voucher_template(uuid,text) from public;
revoke all on function public.admin_archive_voucher_template(uuid,text) from anon;
grant execute on function public.admin_archive_voucher_template(uuid,text) to authenticated;
