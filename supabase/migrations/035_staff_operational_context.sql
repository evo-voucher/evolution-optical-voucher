-- Staff operational context v1
-- Provides the Staff portal only the identity/branch context it needs without
-- exposing direct staff_users/branches table reads to the browser.

create or replace function public.staff_operational_context()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid uuid := (select auth.uid());
  v_staff public.staff_users%rowtype;
  v_branch public.branches%rowtype;
  v_branches jsonb := '[]'::jsonb;
begin
  if v_uid is null then
    raise exception 'Authentication required';
  end if;

  select * into v_staff
  from public.staff_users su
  where su.user_id=v_uid
    and su.status='active'
  limit 1;

  if not found then
    raise exception 'Active Staff account not found';
  end if;

  if v_staff.role='all_branch_manager' then
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'branch_id',b.id,
          'branch_code',b.branch_code,
          'branch_name',b.branch_name,
          'address',b.address,
          'phone',b.phone
        ) order by b.branch_name
      ),
      '[]'::jsonb
    ) into v_branches
    from public.branches b
    where b.status='active';
  else
    if v_staff.branch_id is null then
      raise exception 'Staff account has no branch assigned';
    end if;

    select * into v_branch
    from public.branches b
    where b.id=v_staff.branch_id
      and b.status='active';

    if not found then
      raise exception 'Assigned branch is not active';
    end if;

    v_branches := jsonb_build_array(
      jsonb_build_object(
        'branch_id',v_branch.id,
        'branch_code',v_branch.branch_code,
        'branch_name',v_branch.branch_name,
        'address',v_branch.address,
        'phone',v_branch.phone
      )
    );
  end if;

  return jsonb_build_object(
    'success',true,
    'staff_user_id',v_uid,
    'staff_name',v_staff.staff_name,
    'role',v_staff.role,
    'branch_id',v_staff.branch_id,
    'branch_selection_required',v_staff.role='all_branch_manager',
    'branches',v_branches
  );
end;
$$;

revoke all on function public.staff_operational_context() from public, anon;
grant execute on function public.staff_operational_context() to authenticated;

comment on function public.staff_operational_context() is
'Staff-scoped identity and active branch context for Verify/Redeem UI; no direct browser table read required.';
