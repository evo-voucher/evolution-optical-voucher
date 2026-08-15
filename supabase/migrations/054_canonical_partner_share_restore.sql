-- Restore the canonical Partner share contract after hosted compatibility.
-- 050 carries hosted-production identity semantics. Fresh canonical rebuilds
-- must retain 044's tenant boundary through current_partner_id().
-- Hosted production lacks the canonical Voucher markers, so this is a no-op there.

do $migration$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='vouchers' and column_name='usage_limit'
  ) and exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='vouchers' and column_name='branch_scope_snapshotted'
  ) then
    execute $sql$
      create or replace function public.get_partner_voucher_share(p_voucher_id uuid)
      returns jsonb
      language plpgsql
      stable
      security definer
      set search_path=public
      as $fn$
      declare
        v_partner_id uuid;
        v_code text;
        v_type text;
        v_expiry date;
        v_greeting text;
        v_branches jsonb;
        v_branch_text text;
        v_message text;
      begin
        select
          v.partner_id,
          v.voucher_code,
          v.voucher_type,
          v.expiry_date,
          coalesce(nullif(v.greeting_snapshot,''),E'Hi 👋\nA little gift for you 🎁✨\nHere is your Evolution Optical Voucher.')
        into v_partner_id,v_code,v_type,v_expiry,v_greeting
        from public.vouchers v
        where v.id=p_voucher_id;

        if not found then raise exception 'Voucher not found'; end if;

        if not public.is_voucher_admin()
           and public.current_partner_id() is distinct from v_partner_id then
          raise exception 'Voucher access denied';
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
          coalesce(
            string_agg(
              'Evolution Optical – '||b.branch_name||E'\n'||coalesce(b.address,'')||
              case when nullif(b.phone,'') is not null then E'\n'||b.phone else '' end,
              E'\n\n' order by b.branch_name
            ),
            ''
          )
        into v_branches,v_branch_text
        from public.voucher_branches vb
        join public.branches b on b.id=vb.branch_id
        where vb.voucher_id=p_voucher_id
          and b.status='active';

        v_message:=v_greeting
          ||E'\n\nVoucher: '||v_type
          ||E'\nValid until: '||to_char(v_expiry,'DD Mon YYYY')
          ||E'\n\nRedeem at:\n'||v_branch_text;

        return jsonb_build_object(
          'success',true,
          'voucher_id',p_voucher_id,
          'voucher_code',v_code,
          'voucher_type',v_type,
          'expiry_date',v_expiry,
          'greeting',v_greeting,
          'branches',v_branches,
          'message_body',v_message
        );
      end;
      $fn$;

      revoke all on function public.get_partner_voucher_share(uuid) from public,anon;
      grant execute on function public.get_partner_voucher_share(uuid) to authenticated;
    $sql$;
  end if;
end
$migration$;
