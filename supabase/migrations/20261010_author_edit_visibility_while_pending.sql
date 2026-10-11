-- Let the author change public ↔ private while an appreciation is still pending.
-- After accept, the previous rules remain:
--   - private cannot become public
--   - public → private is only the recipient's "accept as private" path

CREATE OR REPLACE FUNCTION public.enforce_gratitude_visibility()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  downgraded boolean := false;
  author_editing_pending boolean := false;
BEGIN
  -- A JSON null must not wipe the sender's choice (and must not turn
  -- private into "missing", which the app treats as public).
  IF NEW.visibility IS NULL THEN
    NEW.visibility := COALESCE(OLD.visibility, 'public');
  END IF;

  IF NEW.accepted_as_private IS NULL THEN
    NEW.accepted_as_private := COALESCE(OLD.accepted_as_private, false);
  END IF;

  author_editing_pending :=
    OLD.status IS NOT DISTINCT FROM 'pending'
    AND NEW.status IS NOT DISTINCT FROM 'pending'
    AND auth.uid() IS NOT NULL
    AND OLD.author_id IS NOT DISTINCT FROM auth.uid();

  IF OLD.visibility = 'private' AND NEW.visibility IS DISTINCT FROM 'private' THEN
    IF NOT author_editing_pending THEN
      RAISE EXCEPTION 'A private appreciation cannot be made public'
        USING ERRCODE = '42501';
    END IF;
  END IF;

  -- Public → private: recipient accept-as-private, or author editing while pending.
  IF OLD.visibility IS DISTINCT FROM 'private' AND NEW.visibility = 'private' THEN
    IF OLD.status IS DISTINCT FROM 'pending' OR NEW.status IS DISTINCT FROM 'accepted' THEN
      IF author_editing_pending THEN
        -- Author chose private before accept — not a recipient downgrade.
        NEW.accepted_as_private := false;
      ELSE
        RAISE EXCEPTION 'Only the recipient can accept a public appreciation as private'
          USING ERRCODE = '42501';
      END IF;
    ELSE
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

COMMENT ON COLUMN gratitudes.visibility IS
  'public: visible in feeds, profiles, and share pages after accept. private: only the sender and recipient. Authors may change public/private while pending. Recipients may set private while accepting; after accept, private cannot become public.';
