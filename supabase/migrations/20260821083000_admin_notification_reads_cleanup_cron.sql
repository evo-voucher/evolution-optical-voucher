do $$
begin
  if exists (select 1 from cron.job where jobname = 'admin_notification_reads_cleanup') then
    perform cron.unschedule('admin_notification_reads_cleanup');
  end if;
end
$$;

select cron.schedule(
  'admin_notification_reads_cleanup',
  '17 * * * *',
  $cron$delete from public.admin_notification_reads where expires_at <= now();$cron$
);
