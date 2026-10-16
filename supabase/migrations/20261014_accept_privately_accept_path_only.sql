-- Do not apply this from the iOS app or from CI. Apply it to production
-- before 1.3 ships. It is not applied by this change.
--
-- The accept-as-private trigger was raising
-- "Only the recipient can accept a public appreciation as private"
-- on ordinary sends. That happened when the rule ran on INSERT
-- (OLD is null, so a sender-chosen private row looks like a downgrade)
-- and when a still-pending row was updated to private without moving
-- pending → accepted.
--
-- Only the accept path is restricted: a recipient accepting a public
-- appreciation as private. Authors may insert public or private, and
-- may change visibility while the appreciation is still pending.

CREATE OR REPLACE FUNCTION public.gratitude_visibility_on_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.visibility IS NULL OR btrim(NEW.visibility) = '' THEN
    NEW.visibility := 'public';
  END IF;
  -- Authors cannot pre-set the recipient downgrade flag.
  NEW.accepted_as_private := false;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.enforce_gratitude_visibility()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  downgraded boolean := false;
  pending_author_edit boolean := false;
BEGIN
  -- INSERT is never an accept. If this function is attached to INSERT,
  -- still let the author choose public or private.
  IF TG_OP = 'INSERT' THEN
    IF NEW.visibility IS NULL OR btrim(NEW.visibility) = '' THEN
      NEW.visibility := 'public';
    END IF;
    NEW.accepted_as_private := false;
    RETURN NEW;
  END IF;

  IF NEW.visibility IS NULL OR btrim(NEW.visibility) = '' THEN
    NEW.visibility := COALESCE(OLD.visibility, 'public');
  END IF;

  IF NEW.accepted_as_private IS NULL THEN
    NEW.accepted_as_private := COALESCE(OLD.accepted_as_private, false);
  END IF;

  -- Author edits, and service-role writes (auth.uid() is null) that keep
  -- the row pending, are not the accept-as-private path.
  pending_author_edit :=
    OLD.status IS NOT DISTINCT FROM 'pending'
    AND NEW.status IS NOT DISTINCT FROM 'pending'
    AND (
      auth.uid() IS NULL
      OR OLD.author_id IS NOT DISTINCT FROM auth.uid()
    );

  IF OLD.visibility = 'private' AND NEW.visibility IS DISTINCT FROM 'private' THEN
    IF NOT pending_author_edit THEN
      RAISE EXCEPTION 'A private appreciation cannot be made public'
        USING ERRCODE = '42501';
    END IF;
  END IF;

  -- Public → private is restricted only when it is an accept.
  -- A pending author edit (or a create pipeline updating a pending row)
  -- may choose private and must not set the downgrade flag.
  IF COALESCE(OLD.visibility, 'public') IS DISTINCT FROM 'private'
     AND NEW.visibility = 'private' THEN
    IF pending_author_edit THEN
      NEW.accepted_as_private := false;
    ELSIF OLD.status IS NOT DISTINCT FROM 'pending'
      AND NEW.status IS NOT DISTINCT FROM 'accepted'
      AND auth.uid() IS NOT NULL
      AND NEW.recipient_id IS NOT DISTINCT FROM auth.uid()
      AND (
        OLD.recipient_id IS NULL
        OR OLD.recipient_id IS NOT DISTINCT FROM auth.uid()
      )
    THEN
      NEW.accepted_as_private := true;
      downgraded := true;
    ELSE
      RAISE EXCEPTION 'Only the recipient can accept a public appreciation as private'
        USING ERRCODE = '42501';
    END IF;
  END IF;

  -- Clients cannot set the flag on their own. Only the downgrade above can.
  IF COALESCE(NEW.accepted_as_private, false)
    AND NOT COALESCE(OLD.accepted_as_private, false)
    AND NOT downgraded
  THEN
    NEW.accepted_as_private := false;
  END IF;

  -- Once privately accepted, it stays private.
  IF COALESCE(OLD.accepted_as_private, false) THEN
    NEW.accepted_as_private := true;
    NEW.visibility := 'private';
  END IF;

  RETURN NEW;
END;
$$;

-- Drop every trigger that calls the accept rule, including one that was
-- attached to INSERT or to INSERT OR UPDATE under another name. Recreate
-- it below as UPDATE-only so a sender-chosen private row can be inserted.
DO $$
DECLARE
  trg record;
BEGIN
  FOR trg IN
    SELECT t.tgname
    FROM pg_trigger t
    JOIN pg_proc p ON p.oid = t.tgfoid
    WHERE t.tgrelid = 'public.gratitudes'::regclass
      AND NOT t.tgisinternal
      AND p.proname = 'enforce_gratitude_visibility'
  LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS %I ON public.gratitudes', trg.tgname);
  END LOOP;
END
$$;

DROP TRIGGER IF EXISTS gratitude_visibility_on_insert_trigger ON public.gratitudes;
CREATE TRIGGER gratitude_visibility_on_insert_trigger
BEFORE INSERT ON public.gratitudes
FOR EACH ROW
EXECUTE FUNCTION public.gratitude_visibility_on_insert();

DROP TRIGGER IF EXISTS enforce_gratitude_visibility_trigger ON public.gratitudes;
CREATE TRIGGER enforce_gratitude_visibility_trigger
BEFORE UPDATE ON public.gratitudes
FOR EACH ROW
EXECUTE FUNCTION public.enforce_gratitude_visibility();

COMMENT ON FUNCTION public.enforce_gratitude_visibility() IS
  'Accept-as-private is only enforced when a recipient accepts a public appreciation as private. Inserts and pending author edits are not that path.';
