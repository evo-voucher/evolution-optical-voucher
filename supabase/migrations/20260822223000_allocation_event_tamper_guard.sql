create or replace function public.guard_voucher_allocation_event_immutable()
returns trigger
language plpgsql
set search_path to 'public'
as $function$
begin
  if tg_op = 'UPDATE' then
    raise exception 'Voucher allocation events are append-only';
  end if;

  if tg_op = 'DELETE' then
    if public.is_voucher_admin()
       or public.is_trusted_service_role()
       or coalesce(current_setting('evo.sandbox_reset', true), 'off') = 'on' then
      return old;
    end if;

    raise exception 'Voucher allocation events are append-only';
  end if;

  return new;
end;
$function$;

drop trigger if exists voucher_allocation_events_guard_immutable
on public.voucher_allocation_events;

create trigger voucher_allocation_events_guard_immutable
before update or delete on public.voucher_allocation_events
for each row execute function public.guard_voucher_allocation_event_immutable();

revoke all on function public.guard_voucher_allocation_event_immutable() from public;
revoke all on function public.guard_voucher_allocation_event_immutable() from anon;
revoke all on function public.guard_voucher_allocation_event_immutable() from authenticated;
