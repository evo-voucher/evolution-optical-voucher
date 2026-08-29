-- Public Voucher links are bearer-token URLs. Keep the customer-facing card
-- useful while ensuring a leaked/shared URL does not disclose the full name.
-- Administrative, Partner and Staff RPCs retain the canonical customer name.

create or replace function public.get_public_voucher(p_token uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_result jsonb;
begin
  select jsonb_build_object(
    'success',true,
    'voucher_code',v.voucher_code,
    'voucher_type',v.voucher_type,
    'customer_name',case
      when nullif(trim(v.customer_name),'') is null then null
      when char_length(trim(v.customer_name))=1 then '*'
      else left(trim(v.customer_name),1)||'***'
    end,
    'partner_name',p.partner_name,
    'expiry_date',v.expiry_date,
    'status',case
      when v.status='redeemed' then 'redeemed'
      when v.status='revoked' then 'revoked'
      when v.status='expired' then 'expired'
      when v.expiry_date<(now() at time zone 'Asia/Kuala_Lumpur')::date then 'expired'
      when v.status='active' then 'valid'
      else v.status
    end,
    'canonical_status',v.status,
    'issued_at',v.issued_at,
    'all_branches',v.all_branches,
    'validity_anchor',v.validity_anchor_snapshot,
    'validity_value',v.validity_value_snapshot,
    'validity_unit',v.validity_unit_snapshot,
    'theme_code',coalesce(v.theme_code_snapshot,'default'),
    'theme_config',coalesce(v.theme_config_snapshot,'{}'::jsonb),
    'greeting',coalesce(
      nullif(v.greeting_snapshot,''),
      E'Hi 👋\\nA little gift for you 🎁✨\\nHere is your Evolution Optical Voucher.'
    ),
    'terms_text',v.terms_snapshot,
    'branches',coalesce(
      case
        when v.branch_scope_snapshotted or not v.all_branches then
          (select jsonb_agg(
             jsonb_build_object(
               'branch_code',b.branch_code,
               'branch_name',b.branch_name,
               'address',b.address,
               'phone',b.phone
             ) order by b.branch_name
           )
           from public.voucher_branches vb
           join public.branches b on b.id=vb.branch_id
           where vb.voucher_id=v.id and b.status='active')
        else
          (select jsonb_agg(
             jsonb_build_object(
               'branch_code',b.branch_code,
               'branch_name',b.branch_name,
               'address',b.address,
               'phone',b.phone
             ) order by b.branch_name
           )
           from public.branches b
           where b.status='active')
      end,
      '[]'::jsonb
    )
  )
  into v_result
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

comment on function public.get_public_voucher(uuid) is
  'Bearer-token public Voucher view. Returns a masked customer name and no private customer fields.';

revoke all on function public.get_public_voucher(uuid) from public;
grant execute on function public.get_public_voucher(uuid) to anon, authenticated;
