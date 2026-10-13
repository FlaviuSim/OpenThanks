-- When a pending appreciation is created for a linked member, ensure they get
-- an in-app `gratitude_pending` notification even if the web/iOS create path
-- forgets to insert one. Dedupes on (user_id, gratitude_id, type).

CREATE OR REPLACE FUNCTION public.notify_recipient_on_gratitude_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.recipient_id IS NULL THEN
    RETURN NEW;
  END IF;

  IF NEW.recipient_id = NEW.author_id THEN
    RETURN NEW;
  END IF;

  -- Only pending receives (accepted rows use gratitude_received on accept).
  IF COALESCE(NEW.status, 'pending') IS DISTINCT FROM 'pending' THEN
    RETURN NEW;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.notifications n
    WHERE n.user_id = NEW.recipient_id
      AND n.gratitude_id = NEW.id
      AND n.type = 'gratitude_pending'
    LIMIT 1
  ) THEN
    RETURN NEW;
  END IF;

  INSERT INTO public.notifications (user_id, type, gratitude_id, from_user_id)
  VALUES (NEW.recipient_id, 'gratitude_pending', NEW.id, NEW.author_id);

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_recipient_on_gratitude_insert ON public.gratitudes;
CREATE TRIGGER trg_notify_recipient_on_gratitude_insert
  AFTER INSERT ON public.gratitudes
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_recipient_on_gratitude_insert();

COMMENT ON FUNCTION public.notify_recipient_on_gratitude_insert() IS
  'Inserts gratitude_pending for the member recipient when a pending appreciation is created.';
