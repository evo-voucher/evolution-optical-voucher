-- Public voucher lookup for customer share links.
-- Exposes only the minimum customer-facing fields. No phone, user IDs or internal metadata.
-- Canonical DB status active is exposed as valid for the validated customer page.

drop function if exists public.get_public_voucher(uuid);
create function public.get_public_voucher(p_token uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_result jsonb;
begin
  select jsonb_build_object(
    'success',true,
    'voucher_code',v.voucher_code,
    'voucher_type',v.voucher_type,
    'customer_name',v.customer_name,
    'partner_name',p.partner_name,
    'expiry_date',v.expiry_date,
    'status',case
      when v.status='redeemed' then 'redeemed'
      when v.status='revoked' then 'revoked'
      when v.status='expired' then 'expired'
      when v.expiry_date < (now() at time zone 'Asia/Kuala_Lumpur')::date then 'expired'
      when v.status='active' then 'valid'
      else v.status
    end,
    'canonical_status',v.status,
    'issued_at',v.issued_at,
    'all_branches',v.all_branches,
    'branches',coalesce(
      case
        when v.all_branches then (
          select jsonb_agg(
            jsonb_build_object(
              'branch_code',b.branch_code,
              'branch_name',b.branch_name,
              'address',b.address,
              'phone',b.phone
            ) order by b.branch_name
          )
          from public.branches b
          where b.status='active'
        )
        else (
          select jsonb_agg(
            jsonb_build_object(
              'branch_code',b.branch_code,
              'branch_name',b.branch_name,
              'address',b.address,
              'phone',b.phone
            ) order by b.branch_name
          )
          from public.voucher_branches vb
          join public.branches b on b.id=vb.branch_id
          where vb.voucher_id=v.id
            and b.status='active'
        )
      end,
      '[]'::jsonb
    )
  ) into v_result
  from public.vouchers v
  join public.partners p on p.id=v.partner_id
  where v.public_token=p_token
  limit 1;

  if v_result is null then
    return jsonb_build_object('success',false,'error','Voucher not found');
  end if;

  return v_result;
end;
$$;

revoke all on function public.get_public_voucher(uuid) from public;
grant execute on function public.get_public_voucher(uuid) to anon, authenticated;
