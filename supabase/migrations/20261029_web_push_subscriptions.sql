-- Web Push subscriptions for the website and the Android Trusted Web Activity.
--
-- platform = 'web'
--   token    = PushSubscription.endpoint (https URL)
--   p256dh   = PushSubscription.keys.p256dh (base64url)
--   auth_key = PushSubscription.keys.auth (base64url)
--
-- send-web-push reads these rows. iOS rows leave the new columns null.
-- platform = 'android' stays unused (reserved for a future native FCM token).
-- The TWA does not register a native token; Chrome delivers the site's Web Push.
--
-- Also installs (or replaces) dispatch_notification_push so the same allowlist
-- POSTs to send-apns and send-web-push. Both calls use vault secret
-- send_apns_service_role (the service-role JWT). The name is historical.

alter table public.device_push_tokens
  add column if not exists p256dh text;

alter table public.device_push_tokens
  add column if not exists auth_key text;

alter table public.device_push_tokens
  drop constraint if exists device_push_tokens_platform_check;

alter table public.device_push_tokens
  add constraint device_push_tokens_platform_check
  check (platform is null or platform in ('ios', 'android', 'web'));

alter table public.device_push_tokens
  drop constraint if exists device_push_tokens_web_keys_check;

alter table public.device_push_tokens
  add constraint device_push_tokens_web_keys_check
  check (
    platform is distinct from 'web'
    or (
      p256dh is not null
      and auth_key is not null
      and length(btrim(p256dh)) > 0
      and length(btrim(auth_key)) > 0
      and token like 'https://%'
    )
  );

comment on column public.device_push_tokens.p256dh is
  'Web Push client public key (base64url). Required when platform = web.';

comment on column public.device_push_tokens.auth_key is
  'Web Push auth secret (base64url), PushSubscription.keys.auth. Required when platform = web.';

comment on column public.device_push_tokens.token is
  'APNs device token when platform = ios. Web Push endpoint URL when platform = web.';

comment on table public.device_push_tokens is
  'APNs tokens (platform ios) and Web Push subscriptions (platform web). Written by the signed-in client; read by send-apns and send-web-push (service role).';

create extension if not exists pg_net with schema extensions;

create or replace function public.dispatch_notification_push()
returns trigger
language plpgsql
security definer
set search_path = public, extensions, vault
as $$
declare
  allowed constant text[] := array[
    'gratitude_pending',
    'gratitude_received',
    'heart_received',
    'email_bounced',
    'competition_winner'
  ];
  service_key text;
  payload jsonb;
begin
  if new.type is null or not (new.type = any (allowed)) then
    return new;
  end if;

  select ds.decrypted_secret
    into service_key
  from vault.decrypted_secrets ds
  where ds.name = 'send_apns_service_role'
  limit 1;

  if service_key is null or length(trim(service_key)) = 0 then
    return new;
  end if;

  payload := jsonb_build_object(
    'user_id', new.user_id,
    'type', new.type,
    'notification_id', new.id,
    'gratitude_id', new.gratitude_id
  );

  begin
    perform net.http_post(
      url := 'https://dsftvyuzmhlqadhbubgw.supabase.co/functions/v1/send-apns',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || service_key
      ),
      body := payload
    );
  exception
    when others then
      raise warning 'dispatch_notification_push send-apns failed: %', sqlerrm;
  end;

  begin
    perform net.http_post(
      url := 'https://dsftvyuzmhlqadhbubgw.supabase.co/functions/v1/send-web-push',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || service_key
      ),
      body := payload
    );
  exception
    when others then
      raise warning 'dispatch_notification_push send-web-push failed: %', sqlerrm;
  end;

  return new;
exception
  when undefined_table then
    -- vault / pg_net not available in this environment — never block inserts.
    return new;
  when undefined_function then
    return new;
  when others then
    raise warning 'dispatch_notification_push failed: %', sqlerrm;
    return new;
end;
$$;

drop trigger if exists trg_dispatch_notification_push on public.notifications;
create trigger trg_dispatch_notification_push
  after insert on public.notifications
  for each row
  execute function public.dispatch_notification_push();

comment on function public.dispatch_notification_push() is
  'Best-effort fan-out to send-apns and send-web-push for allowlisted notification types. Needs vault secret send_apns_service_role.';

-- Trigger functions are not an RPC. Revoke so the Data API cannot call it.
revoke all on function public.dispatch_notification_push() from public;
revoke all on function public.dispatch_notification_push() from anon, authenticated;
