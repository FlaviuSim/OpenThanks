-- Applied to production project dsftvyuzmhlqadhbubgw (open-thanks) on 2026-10-08.
-- Same script as FlaviuSim/v0-gratitude-network scripts/026_accept_as_private.sql.
--
-- Let a recipient accept a public appreciation as private.
--
-- visibility stays the source of truth for feeds and profiles:
--   public  → community feed, public profiles, sitemap, share pages
--   private → sender and recipient only
--
-- accepted_as_private is true only when the recipient downgraded a public
-- appreciation at accept time. Sender-chosen private rows stay false.
-- A private appreciation can never be flipped back to public.

ALTER TABLE gratitudes
  ADD COLUMN IF NOT EXISTS accepted_as_private BOOLEAN NOT NULL DEFAULT false;

COMMENT ON COLUMN gratitudes.visibility IS
  'public: visible in feeds, profiles, and share pages after accept. private: only the sender and recipient. Recipients may set this to private while accepting; it cannot move from private back to public.';

COMMENT ON COLUMN gratitudes.accepted_as_private IS
  'True when the recipient accepted a public appreciation as private. Sender-chosen private appreciations stay false.';

CREATE OR REPLACE FUNCTION public.enforce_gratitude_visibility()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  downgraded boolean := false;
BEGIN
  -- A JSON null must not wipe the sender's choice (and must not turn
  -- private into "missing", which the app treats as public).
  IF NEW.visibility IS NULL THEN
    NEW.visibility := COALESCE(OLD.visibility, 'public');
  END IF;

  IF NEW.accepted_as_private IS NULL THEN
    NEW.accepted_as_private := COALESCE(OLD.accepted_as_private, false);
  END IF;

  IF OLD.visibility = 'private' AND NEW.visibility IS DISTINCT FROM 'private' THEN
    RAISE EXCEPTION 'A private appreciation cannot be made public'
      USING ERRCODE = '42501';
  END IF;

  -- Public → private is only the recipient accepting a pending appreciation.
  IF OLD.visibility IS DISTINCT FROM 'private' AND NEW.visibility = 'private' THEN
    IF OLD.status IS DISTINCT FROM 'pending' OR NEW.status IS DISTINCT FROM 'accepted' THEN
      RAISE EXCEPTION 'Only the recipient can accept a public appreciation as private'
        USING ERRCODE = '42501';
    END IF;

    IF auth.uid() IS NULL
      OR NEW.recipient_id IS DISTINCT FROM auth.uid()
      OR (OLD.recipient_id IS NOT NULL AND OLD.recipient_id IS DISTINCT FROM auth.uid())
    THEN
      RAISE EXCEPTION 'Only the recipient can accept a public appreciation as private'
        USING ERRCODE = '42501';
    END IF;

    NEW.accepted_as_private := true;
    downgraded := true;
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

DROP TRIGGER IF EXISTS enforce_gratitude_visibility_trigger ON gratitudes;
CREATE TRIGGER enforce_gratitude_visibility_trigger
BEFORE UPDATE ON gratitudes
FOR EACH ROW
EXECUTE FUNCTION public.enforce_gratitude_visibility();

-- Authors choose visibility at insert time. They cannot pre-set the
-- recipient downgrade flag.
CREATE OR REPLACE FUNCTION public.gratitude_visibility_on_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.visibility IS NULL THEN
    NEW.visibility := 'public';
  END IF;
  NEW.accepted_as_private := false;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS gratitude_visibility_on_insert_trigger ON gratitudes;
CREATE TRIGGER gratitude_visibility_on_insert_trigger
BEFORE INSERT ON gratitudes
FOR EACH ROW
EXECUTE FUNCTION public.gratitude_visibility_on_insert();
