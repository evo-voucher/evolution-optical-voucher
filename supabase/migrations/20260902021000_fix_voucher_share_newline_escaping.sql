-- Correct newline escaping in get_partner_voucher_share(uuid) after PR #64.
-- PR #64 matched Production logic/ACL, but the migration source encoded E-string
-- newline escapes with an extra backslash, leaving a real definition hash mismatch.
-- This migration changes only string literal escaping. Production remains read-only.

CREATE OR REPLACE FUNCTION public.get_partner_voucher_share(p_voucher_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
declare
  v_partner_id uuid;
  v_code text;
  v_type text;
  v_expiry date;
  v_greeting text;
  v_all_branches boolean;
  v_branch_scope_snapshotted boolean;
  v_branches jsonb;
  v_branch_text text;
  v_message text;
begin
  select v.partner_id,
         v.voucher_code,
         v.voucher_type,
         v.expiry_date,
         coalesce(nullif(v.greeting_snapshot,''),E'Hi 👋\nA little gift for you 🎁✨\nHere is your Evolution Optical Voucher.'),
         v.all_branches,
         v.branch_scope_snapshotted
  into v_partner_id,v_code,v_type,v_expiry,v_greeting,v_all_branches,v_branch_scope_snapshotted
  from public.vouchers v
  where v.id=p_voucher_id;

  if not found then raise exception 'Voucher not found'; end if;

  if not public.is_voucher_admin()
     and public.current_partner_id() is distinct from v_partner_id then
    raise exception 'Voucher access denied';
  end if;

  if v_branch_scope_snapshotted or not v_all_branches then
    select
      coalesce(jsonb_agg(jsonb_build_object(
        'branch_code',b.branch_code,
        'branch_name',b.branch_name,
        'address',b.address,
        'phone',b.phone
      ) order by b.branch_name),'[]'::jsonb),
      coalesce(string_agg(
        'Evolution Optical – '||b.branch_name||E'\n'||coalesce(b.address,'')||
        case when nullif(b.phone,'') is not null then E'\n'||b.phone else '' end,
        E'\n\n' order by b.branch_name
      ),'')
    into v_branches,v_branch_text
    from public.voucher_branches vb
    join public.branches b on b.id=vb.branch_id
    where vb.voucher_id=p_voucher_id
      and b.status='active';
  else
    select
      coalesce(jsonb_agg(jsonb_build_object(
        'branch_code',b.branch_code,
        'branch_name',b.branch_name,
        'address',b.address,
        'phone',b.phone
      ) order by b.branch_name),'[]'::jsonb),
      coalesce(string_agg(
        'Evolution Optical – '||b.branch_name||E'\n'||coalesce(b.address,'')||
        case when nullif(b.phone,'') is not null then E'\n'||b.phone else '' end,
        E'\n\n' order by b.branch_name
      ),'')
    into v_branches,v_branch_text
    from public.branches b
    where b.status='active';
  end if;

  v_message:=v_greeting||E'\n\nVoucher: '||v_type||E'\nValid until: '||to_char(v_expiry,'DD Mon YYYY')||E'\n\nRedeem at:\n'||v_branch_text;

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
$function$;

REVOKE ALL ON FUNCTION public.get_partner_voucher_share(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_partner_voucher_share(uuid) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.get_partner_voucher_share(uuid) FROM service_role;
