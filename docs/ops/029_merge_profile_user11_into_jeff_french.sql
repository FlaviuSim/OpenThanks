-- =============================================================================
-- Profile merge: user11 → jeff-french
-- Executed against production (dsftvyuzmhlqadhbubgw / db.openthanks.com) on 2026-11-15.
-- Kept for audit / replay reference. Do NOT re-run against production.
-- =============================================================================
--
-- Goal
--   Keep username `jeff-french`.
--   Use the profile photo from `user11`.
--   Move all activity from `user11` onto jeff-french.
--   Link phone OTP from the source auth user onto jeff-french so Google + phone both work.
--   Retire the duplicate auth.users + profiles row.
--
-- Resolved IDs (production)
--   KEEP   jeff-french  02bf0638-7b47-4b9b-93bc-b212fca3961c  (Google / frenchjeff50@gmail.com)
--   SOURCE user11       10e779d1-bf36-441d-ad6d-c8844e81e2e5  (phone / +12197136098)
--   Phone identity      4723bb87-065b-46b3-8dd4-e2892f953d47
--
-- Preflight counts (source → keep)
--   gratitudes.author_id:       7 → moved (keep already 7 → 14)
--   gratitudes.recipient_id:    0 (keep 3)
--   hearts.user_id:             0 (keep 2)
--   notifications.user_id:      5 → moved (keep 17 → 22)
--   notifications.from_user_id: 3 → moved (keep 4 → 7)
--   idempotency_keys:           7 → moved (keep 8 → 15; no key overlaps)
--   nudge_sends / device_push_tokens / user_blocks / donations: 0
--
-- Postflight
--   authored=14 received=3 notif_to=22 notif_from=7 idem=15
--   identities on KEEP: google + phone
--   username=jeff-french, avatar from user11, phone=+12197136098
--
-- Web follow-up
--   Permanent redirect /user11 → /jeff-french in next.config.mjs
-- =============================================================================

BEGIN;

DO $$
DECLARE
  keep_id uuid := '02bf0638-7b47-4b9b-93bc-b212fca3961c';
  source_id uuid := '10e779d1-bf36-441d-ad6d-c8844e81e2e5';
  keep_username text;
  source_username text;
BEGIN
  SELECT username INTO keep_username FROM public.profiles WHERE id = keep_id;
  SELECT username INTO source_username FROM public.profiles WHERE id = source_id;
  IF keep_username IS DISTINCT FROM 'jeff-french' OR source_username IS DISTINCT FROM 'user11' THEN
    RAISE EXCEPTION 'Unexpected usernames: keep=%, source=%', keep_username, source_username;
  END IF;
END $$;

-- Hearts: drop overlaps, then reassign
DELETE FROM public.hearts h
WHERE h.user_id = '10e779d1-bf36-441d-ad6d-c8844e81e2e5'
  AND EXISTS (
    SELECT 1 FROM public.hearts k
    WHERE k.user_id = '02bf0638-7b47-4b9b-93bc-b212fca3961c'
      AND k.gratitude_id = h.gratitude_id
  );

UPDATE public.hearts
SET user_id = '02bf0638-7b47-4b9b-93bc-b212fca3961c'
WHERE user_id = '10e779d1-bf36-441d-ad6d-c8844e81e2e5';

UPDATE public.gratitudes
SET author_id = '02bf0638-7b47-4b9b-93bc-b212fca3961c'
WHERE author_id = '10e779d1-bf36-441d-ad6d-c8844e81e2e5';

UPDATE public.gratitudes
SET recipient_id = '02bf0638-7b47-4b9b-93bc-b212fca3961c'
WHERE recipient_id = '10e779d1-bf36-441d-ad6d-c8844e81e2e5';

UPDATE public.notifications
SET user_id = '02bf0638-7b47-4b9b-93bc-b212fca3961c'
WHERE user_id = '10e779d1-bf36-441d-ad6d-c8844e81e2e5';

UPDATE public.notifications
SET from_user_id = '02bf0638-7b47-4b9b-93bc-b212fca3961c'
WHERE from_user_id = '10e779d1-bf36-441d-ad6d-c8844e81e2e5';

-- Blocks: drop self/dupe edges, then reassign
DELETE FROM public.user_blocks
WHERE (blocker_id = '10e779d1-bf36-441d-ad6d-c8844e81e2e5' AND blocked_id = '02bf0638-7b47-4b9b-93bc-b212fca3961c')
   OR (blocker_id = '02bf0638-7b47-4b9b-93bc-b212fca3961c' AND blocked_id = '10e779d1-bf36-441d-ad6d-c8844e81e2e5');

UPDATE public.user_blocks
SET blocker_id = '02bf0638-7b47-4b9b-93bc-b212fca3961c'
WHERE blocker_id = '10e779d1-bf36-441d-ad6d-c8844e81e2e5';

UPDATE public.user_blocks
SET blocked_id = '02bf0638-7b47-4b9b-93bc-b212fca3961c'
WHERE blocked_id = '10e779d1-bf36-441d-ad6d-c8844e81e2e5';

DELETE FROM public.device_push_tokens d
WHERE d.user_id = '10e779d1-bf36-441d-ad6d-c8844e81e2e5'
  AND EXISTS (
    SELECT 1 FROM public.device_push_tokens k
    WHERE k.user_id = '02bf0638-7b47-4b9b-93bc-b212fca3961c'
      AND k.token = d.token
  );

UPDATE public.device_push_tokens
SET user_id = '02bf0638-7b47-4b9b-93bc-b212fca3961c'
WHERE user_id = '10e779d1-bf36-441d-ad6d-c8844e81e2e5';

UPDATE public.content_reports
SET reporter_id = '02bf0638-7b47-4b9b-93bc-b212fca3961c'
WHERE reporter_id = '10e779d1-bf36-441d-ad6d-c8844e81e2e5';

UPDATE public.donations
SET donor_id = '02bf0638-7b47-4b9b-93bc-b212fca3961c'
WHERE donor_id = '10e779d1-bf36-441d-ad6d-c8844e81e2e5';

UPDATE public.donations
SET honoree_id = '02bf0638-7b47-4b9b-93bc-b212fca3961c'
WHERE honoree_id = '10e779d1-bf36-441d-ad6d-c8844e81e2e5';

UPDATE public.donation_pledges
SET pledger_id = '02bf0638-7b47-4b9b-93bc-b212fca3961c'
WHERE pledger_id = '10e779d1-bf36-441d-ad6d-c8844e81e2e5';

UPDATE public.donation_pledges
SET recipient_id = '02bf0638-7b47-4b9b-93bc-b212fca3961c'
WHERE recipient_id = '10e779d1-bf36-441d-ad6d-c8844e81e2e5';

UPDATE public.email_reply_tokens
SET user_id = '02bf0638-7b47-4b9b-93bc-b212fca3961c'
WHERE user_id = '10e779d1-bf36-441d-ad6d-c8844e81e2e5';

-- Idempotency keys are globally unique on idempotency_key.
DELETE FROM public.idempotency_keys s
WHERE s.user_id = '10e779d1-bf36-441d-ad6d-c8844e81e2e5'
  AND EXISTS (
    SELECT 1 FROM public.idempotency_keys k
    WHERE k.user_id = '02bf0638-7b47-4b9b-93bc-b212fca3961c'
      AND k.idempotency_key = s.idempotency_key
  );

UPDATE public.idempotency_keys
SET user_id = '02bf0638-7b47-4b9b-93bc-b212fca3961c'
WHERE user_id = '10e779d1-bf36-441d-ad6d-c8844e81e2e5';

UPDATE public.nudge_sends
SET user_id = '02bf0638-7b47-4b9b-93bc-b212fca3961c'
WHERE user_id = '10e779d1-bf36-441d-ad6d-c8844e81e2e5';

-- Profile: keep jeff-french username; take user11 avatar + phone.
UPDATE public.profiles AS keep
SET
  avatar_url = source.avatar_url,
  phone = COALESCE(keep.phone, source.phone),
  full_name = COALESCE(NULLIF(keep.full_name, ''), source.full_name)
FROM public.profiles AS source
WHERE keep.id = '02bf0638-7b47-4b9b-93bc-b212fca3961c'
  AND source.id = '10e779d1-bf36-441d-ad6d-c8844e81e2e5';

-- Auth phone is globally unique — clear source before attaching to keep.
UPDATE auth.users
SET phone = NULL,
    phone_confirmed_at = NULL
WHERE id = '10e779d1-bf36-441d-ad6d-c8844e81e2e5';

UPDATE auth.users
SET phone = '12197136098',
    phone_confirmed_at = '2026-10-02 13:50:43.183298+00'::timestamptz
WHERE id = '02bf0638-7b47-4b9b-93bc-b212fca3961c';

-- Auth: move phone identity onto jeff-french
UPDATE auth.identities
SET user_id = '02bf0638-7b47-4b9b-93bc-b212fca3961c'
WHERE id = '4723bb87-065b-46b3-8dd4-e2892f953d47'
  AND user_id = '10e779d1-bf36-441d-ad6d-c8844e81e2e5';

UPDATE auth.users
SET raw_app_meta_data = jsonb_set(
  coalesce(raw_app_meta_data, '{}'::jsonb),
  '{providers}',
  (
    SELECT to_jsonb(array_agg(DISTINCT p ORDER BY p))
    FROM (
      SELECT jsonb_array_elements_text(
        coalesce(raw_app_meta_data->'providers', '[]'::jsonb) || '["phone"]'::jsonb
      ) AS p
    ) s
  )
)
WHERE id = '02bf0638-7b47-4b9b-93bc-b212fca3961c';

DELETE FROM auth.sessions WHERE user_id = '10e779d1-bf36-441d-ad6d-c8844e81e2e5';
DELETE FROM auth.refresh_tokens WHERE user_id = '10e779d1-bf36-441d-ad6d-c8844e81e2e5';
DELETE FROM auth.identities WHERE user_id = '10e779d1-bf36-441d-ad6d-c8844e81e2e5';

DELETE FROM public.profiles WHERE id = '10e779d1-bf36-441d-ad6d-c8844e81e2e5';
DELETE FROM auth.users WHERE id = '10e779d1-bf36-441d-ad6d-c8844e81e2e5';

COMMIT;

-- Web redirect: /user11 → /jeff-french in v0-gratitude-network next.config.mjs
