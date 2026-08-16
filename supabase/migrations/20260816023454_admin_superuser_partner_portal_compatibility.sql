-- Admin Superuser Partner Portal Compatibility
-- Production-applied: 2026-08-16
-- Purpose: allow the internal ADMIN system partner context to use Partner Portal read surfaces
-- without weakening tenant isolation for normal Partner accounts.

create or replace function public.get_my_partner_dashboard()
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare v_result jsonb;
begin
  select jsonb_build_object(
    'partner_id',p.id,'partner_code',p.partner_code,'partner_name',p.partner_name,
    'voucher_limit',coalesce(p.voucher_limit,0),'vouchers_issued',coalesce(p.vouchers_issued,0),
    'remaining',greatest(0,coalesce(p.voucher_limit,0)-coalesce(p.vouchers_issued,0)),
    'partner_status',p.status,'role',pu.role,'staff_name',pu.staff_name,
    'staff_access_enabled',coalesce(p.staff_access_enabled,false),'staff_limit',coalesce(p.staff_limit,0),
    'can_issue_voucher',case when lower(coalesce(pu.role,'')) in ('admin','partner_admin') then true when lower(coalesce(pu.role,''))='partner_staff' then coalesce(p.staff_access_enabled,false) else false end
  ) into v_result
  from public.partner_users pu join public.partners p on p.id=pu.partner_id
  where pu.user_id=auth.uid() and lower(coalesce(pu.status,''))='active' and pu.removed_at is null
    and lower(coalesce(p.status,''))='active' and lower(coalesce(pu.role,'')) in ('admin','partner_admin','partner_staff')
  order by case when lower(coalesce(pu.role,''))='admin' then 0 else 1 end
  limit 1;
  if v_result is null then raise exception 'Active Partner account not found'; end if;
  return v_result;
end;$function$;

create or replace function public.partner_voucher_summary()
returns jsonb
language plpgsql stable security definer set search_path to 'public'
as $function$
declare v_partner_id uuid; v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
begin
  select pu.partner_id into v_partner_id from public.partner_users pu join public.partners p on p.id=pu.partner_id
  where pu.user_id=auth.uid() and lower(coalesce(pu.status,''))='active' and pu.removed_at is null
    and lower(coalesce(pu.role,'')) in ('admin','partner_admin','partner_staff') and lower(coalesce(p.status,''))='active'
  order by case when lower(coalesce(pu.role,''))='admin' then 0 else 1 end limit 1;
  if v_partner_id is null then raise exception 'Active Partner account not found'; end if;
  return jsonb_build_object(
    'partner_id',v_partner_id,
    'issued_total',(select count(*) from public.vouchers v where v.partner_id=v_partner_id),
    'active_total',(select count(*) from public.vouchers v where v.partner_id=v_partner_id and lower(coalesce(v.status,'')) in ('valid','active') and v.expiry_date>=v_today),
    'redeemed_total',(select count(*) from public.vouchers v where v.partner_id=v_partner_id and lower(coalesce(v.status,''))='redeemed'),
    'expired_total',(select count(*) from public.vouchers v where v.partner_id=v_partner_id and (lower(coalesce(v.status,''))='expired' or (lower(coalesce(v.status,'')) in ('valid','active') and v.expiry_date<v_today))),
    'revoked_total',(select count(*) from public.vouchers v where v.partner_id=v_partner_id and lower(coalesce(v.status,''))='revoked'),
    'completed_redemptions',(select count(*) from public.redemptions r where r.partner_id=v_partner_id and lower(coalesce(r.status,'')) in ('success','completed'))
  );
end;$function$;

create or replace function public.get_my_partner_claim_access()
returns jsonb
language plpgsql security definer set search_path to 'public'
as $function$
declare v_partner uuid; v_all boolean; v_codes text[]; v_names text[];
begin
  select pu.partner_id into v_partner from public.partner_users pu join public.partners p on p.id=pu.partner_id
  where pu.user_id=auth.uid() and lower(coalesce(pu.status,''))='active' and pu.removed_at is null
    and lower(coalesce(pu.role,'')) in ('admin','partner_admin','partner_staff') and lower(coalesce(p.status,''))='active'
  order by case when lower(coalesce(pu.role,''))='admin' then 0 else 1 end limit 1;
  if v_partner is null then raise exception 'Active Partner account not found'; end if;
  select coalesce(s.all_branches,true) into v_all from public.partner_claim_settings s where s.partner_id=v_partner;
  if not found then v_all:=true; end if;
  select coalesce(array_agg(b.branch_code order by b.branch_name),'{}'::text[]),coalesce(array_agg(coalesce(b.branch_name,b.branch_code) order by b.branch_name),'{}'::text[])
  into v_codes,v_names from public.partner_claim_branches pcb join public.branches b on b.id=pcb.branch_id
  where pcb.partner_id=v_partner and lower(coalesce(b.status,'active'))='active';
  return jsonb_build_object('success',true,'all_branches',v_all,'branch_codes',v_codes,'branch_names',v_names);
end;$function$;

create or replace function public.partner_recent_vouchers(p_limit integer default 50)
returns table(voucher_id uuid,voucher_code text,customer_name text,customer_phone text,voucher_type text,voucher_status text,expiry_date date,issued_at timestamptz,issued_by_name text,usage_count integer,usage_limit integer,last_redeemed_at timestamptz,last_branch_name text)
language plpgsql stable security definer set search_path to 'public'
as $function$
declare v_partner_id uuid;
begin
  select pu.partner_id into v_partner_id from public.partner_users pu join public.partners p on p.id=pu.partner_id
  where pu.user_id=auth.uid() and lower(coalesce(pu.status,''))='active' and pu.removed_at is null
    and lower(coalesce(pu.role,'')) in ('admin','partner_admin','partner_staff') and lower(coalesce(p.status,''))='active'
  order by case when lower(coalesce(pu.role,''))='admin' then 0 else 1 end limit 1;
  if v_partner_id is null then raise exception 'Active Partner account not found'; end if;
  if p_limit is null or p_limit<1 or p_limit>500 then raise exception 'Limit must be between 1 and 500'; end if;
  return query select v.id,v.voucher_code,v.customer_name,v.customer_phone,v.voucher_type,
    case when lower(coalesce(v.status,''))='revoked' then 'revoked' when lower(coalesce(v.status,''))='expired' or (lower(coalesce(v.status,'')) in ('valid','active') and v.expiry_date<(now() at time zone 'Asia/Kuala_Lumpur')::date) then 'expired' when lower(coalesce(v.status,''))='redeemed' then 'redeemed' else 'active' end,
    v.expiry_date,v.issued_at,v.issued_by_name,case when lower(coalesce(v.status,''))='redeemed' then greatest(coalesce(v.usage_count,0),1) else coalesce(v.usage_count,0) end,1::integer,lr.redeemed_at,lr.branch_name
  from public.vouchers v left join lateral (select r.redeemed_at,b.branch_name from public.redemptions r left join public.branches b on b.id=r.branch_id where r.voucher_id=v.id and lower(coalesce(r.status,'')) in ('success','completed') order by r.redeemed_at desc limit 1) lr on true
  where v.partner_id=v_partner_id order by v.issued_at desc nulls last limit p_limit;
end;$function$;
