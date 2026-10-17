-- The first schedule looked for a Vault copy of the service-role JWT, which
-- this project does not have. Call the worker with the cron header instead.
-- The function only sends reminders that are already due.

do $cron$
begin
  begin
    perform cron.unschedule('compose-draft-reminders');
  exception when others then
    null;
  end;

  perform cron.schedule(
    'compose-draft-reminders',
    '*/5 * * * *',
    $job$
    select net.http_post(
      url := 'https://dsftvyuzmhlqadhbubgw.supabase.co/functions/v1/send-draft-reminders',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-openthanks-cron', 'compose-draft-reminders'
      ),
      body := '{}'::jsonb,
      timeout_milliseconds := 10000
    );
    $job$
  );
exception when others then
  raise warning 'compose draft reminders: cron not rescheduled: %', sqlerrm;
end
$cron$;
