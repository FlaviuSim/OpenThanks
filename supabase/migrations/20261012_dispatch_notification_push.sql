-- Fire APNs via send-apns when an allowlisted notification row is inserted.
--
-- Requires:
--   1. extensions.pg_net enabled (Supabase default on hosted projects)
--   2. Vault secret named `send_apns_service_role` = project service_role JWT
--      Dashboard → Project Settings → Vault → New secret
--      (or: select vault.create_secret('SERVICE_ROLE_KEY', 'send_apns_service_role');)
--
-- If the vault secret is missing, inserts still succeed and push is skipped.
-- Alternatively use Dashboard → Database → Webhooks on notifications INSERT
-- (see supabase/functions/send-apns/README.md); send-apns accepts both shapes.

CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;

CREATE OR REPLACE FUNCTION public.dispatch_notification_push()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, vault
AS $$
DECLARE
  allowed constant text[] := ARRAY[
    'gratitude_pending',
    'gratitude_received',
    'heart_received',
    'email_bounced',
    'competition_winner'
  ];
  service_key text;
  payload jsonb;
BEGIN
  IF NEW.type IS NULL OR NOT (NEW.type = ANY (allowed)) THEN
    RETURN NEW;
  END IF;

  SELECT ds.decrypted_secret
    INTO service_key
  FROM vault.decrypted_secrets ds
  WHERE ds.name = 'send_apns_service_role'
  LIMIT 1;

  IF service_key IS NULL OR length(trim(service_key)) = 0 THEN
    RETURN NEW;
  END IF;

  payload := jsonb_build_object(
    'user_id', NEW.user_id,
    'type', NEW.type,
    'notification_id', NEW.id,
    'gratitude_id', NEW.gratitude_id
  );

  PERFORM net.http_post(
    url := 'https://dsftvyuzmhlqadhbubgw.supabase.co/functions/v1/send-apns',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || service_key
    ),
    body := payload
  );

  RETURN NEW;
EXCEPTION
  WHEN undefined_table THEN
    -- vault / pg_net not available in this environment — never block inserts.
    RETURN NEW;
  WHEN undefined_function THEN
    RETURN NEW;
  WHEN OTHERS THEN
    RAISE WARNING 'dispatch_notification_push failed: %', SQLERRM;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_dispatch_notification_push ON public.notifications;
CREATE TRIGGER trg_dispatch_notification_push
  AFTER INSERT ON public.notifications
  FOR EACH ROW
  EXECUTE FUNCTION public.dispatch_notification_push();

COMMENT ON FUNCTION public.dispatch_notification_push() IS
  'Best-effort APNs fan-out via send-apns for allowlisted notification types. Needs vault secret send_apns_service_role.';
