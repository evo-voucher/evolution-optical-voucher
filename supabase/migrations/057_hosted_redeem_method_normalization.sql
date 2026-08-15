-- Hosted redemption method normalization.
-- Existing hosted production constrains redemptions.redeem_method to:
--   qr_scan | manual
-- Newer callers may send qr | qr_scan | manual | manual_code | admin.
-- Keep input compatibility at the RPC boundary while storing only the hosted
-- authoritative values. Fresh canonical schema is intentionally unchanged.

do $migration$
begin
  if not exists(
    select 1 from information_schema.columns
    where table_schema='public' and table_name='vouchers' and column_name='usage_limit'
  ) and not exists(
    select 1 from information_schema.columns
    where table_schema='public' and table_name='vouchers' and column_name='branch_scope_snapshotted'
  ) then
    execute $sql$
      create or replace function public.redeem_voucher(
        p_voucher_code text,
        p_notes text default null,
        p_branch_code text default null,
        p_redeem_method text default 'manual_code'
      )
      returns jsonb
      language plpgsql
      security definer
      set search_path=public
      as $fn$
      declare
        v_staff public.staff_users%rowtype;
        v_voucher public.vouchers%rowtype;
        v_branch_id uuid;
        v_branch_name text;
        v_allowed boolean:=false;
        v_now timestamptz:=now();
        v_method_input text:=lower(trim(coalesce(p_redeem_method,'manual_code')));
        v_method_store text;
        v_redemption_id uuid;
      begin
        if v_method_input not in ('qr','qr_scan','manual','manual_code','admin') then
          return jsonb_build_object('success',false,'error','Invalid redeem method');
        end if;

        v_method_store:=case
          when v_method_input in ('qr','qr_scan') then 'qr_scan'
          else 'manual'
        end;

        select * into v_staff
        from public.staff_users su
        where su.user_id=(select auth.uid())
          and lower(coalesce(su.status,''))='active'
        limit 1;
        if not found then
          return jsonb_build_object('success',false,'error','Staff account is not authorised or is suspended');
        end if;

        if lower(coalesce(v_staff.role,''))='all_branch_manager' then
          if nullif(trim(coalesce(p_branch_code,'')),'') is null then
            return jsonb_build_object('success',false,'error','Branch selection is required for All Branch Manager');
          end if;
          select b.id,b.branch_name into v_branch_id,v_branch_name
          from public.branches b
          where upper(b.branch_code)=upper(trim(p_branch_code))
            and lower(coalesce(b.status,''))='active'
          limit 1;
        else
          if v_staff.branch_id is null then
            return jsonb_build_object('success',false,'error','Staff account has no branch assigned');
          end if;
          select b.id,b.branch_name into v_branch_id,v_branch_name
          from public.branches b
          where b.id=v_staff.branch_id
            and lower(coalesce(b.status,''))='active'
          limit 1;
        end if;

        if v_branch_id is null then
          return jsonb_build_object('success',false,'error','Active branch not found');
        end if;

        select * into v_voucher
        from public.vouchers v
        where upper(v.voucher_code)=upper(trim(p_voucher_code))
        for update;
        if not found then
          return jsonb_build_object('success',false,'error','Voucher not found');
        end if;

        if lower(coalesce(v_voucher.status,''))='revoked' then
          return jsonb_build_object('success',false,'error','Voucher has been revoked','status','revoked');
        end if;
        if lower(coalesce(v_voucher.status,''))='expired'
           or v_voucher.expiry_date<(now() at time zone 'Asia/Kuala_Lumpur')::date then
          return jsonb_build_object('success',false,'error','Voucher has expired','status','expired');
        end if;
        if lower(coalesce(v_voucher.status,''))='redeemed'
           or exists(
             select 1 from public.redemptions r
             where r.voucher_id=v_voucher.id
               and lower(coalesce(r.status,'')) in ('success','completed')
           ) then
          return jsonb_build_object('success',false,'error','Voucher has already been redeemed','status','redeemed');
        end if;
        if lower(coalesce(v_voucher.status,'')) not in ('valid','active') then
          return jsonb_build_object('success',false,'error','Voucher is not valid','status',v_voucher.status);
        end if;

        if v_voucher.all_branches then
          v_allowed:=true;
        else
          select exists(
            select 1 from public.voucher_branches vb
            where vb.voucher_id=v_voucher.id
              and vb.branch_id=v_branch_id
          ) into v_allowed;
        end if;
        if not v_allowed then
          return jsonb_build_object('success',false,'error','Voucher cannot be redeemed at this branch');
        end if;

        insert into public.redemptions(
          voucher_id,branch_id,staff_user_id,partner_id,staff_name_snapshot,
          redeem_method,status,redeemed_at,notes
        ) values (
          v_voucher.id,v_branch_id,v_staff.id,v_voucher.partner_id,v_staff.staff_name,
          v_method_store,'success',v_now,nullif(trim(coalesce(p_notes,'')),'')
        ) returning id into v_redemption_id;

        update public.vouchers
        set status='redeemed',
            redeemed_at=v_now,
            redeemed_by=v_staff.staff_name,
            usage_count=greatest(coalesce(usage_count,0),1)
        where id=v_voucher.id;

        return jsonb_build_object(
          'success',true,
          'redemption_id',v_redemption_id,
          'voucher_id',v_voucher.id,
          'voucher_code',v_voucher.voucher_code,
          'customer_name',v_voucher.customer_name,
          'voucher_type',v_voucher.voucher_type,
          'branch_id',v_branch_id,
          'branch_name',v_branch_name,
          'staff_name',v_staff.staff_name,
          'redeemed_at',v_now,
          'redeem_method',v_method_store,
          'usage_count',1,
          'usage_limit',1,
          'remaining_uses',0,
          'status','redeemed'
        );
      exception
        when unique_violation then
          return jsonb_build_object('success',false,'error','Voucher has already been redeemed');
      end;
      $fn$;

      revoke all on function public.redeem_voucher(text,text,text,text) from public,anon;
      grant execute on function public.redeem_voucher(text,text,text,text) to authenticated;
    $sql$;
  end if;
end
$migration$;
