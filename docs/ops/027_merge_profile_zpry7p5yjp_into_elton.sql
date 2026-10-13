-- =============================================================================
-- Profile merge: zpry7p5yjp → elton
-- Executed against production (dsftvyuzmhlqadhbubgw / db.openthanks.com) on 2026-10-13.
-- Kept for audit / replay reference. Do NOT re-run against production.
-- =============================================================================
--
-- Goal
--   Keep username `elton` and that profile's avatar.
--   Move all activity from `zpry7p5yjp` onto elton.
--   Link Apple Sign In from the source auth user onto elton so either login works.
--   Retire the duplicate auth.users + profiles row.
--
-- Resolved IDs (production)
--   KEEP   elton        8a4f63b0-f80b-4954-9a3a-4cabac87159a  (Google)
--   SOURCE zpry7p5yjp   a5eb41c0-67f1-4d95-a111-609f0f051067  (Apple)
--   Apple identity      fac8789f-9d2b-4f9b-8095-0541d2e84a11
--
-- Preflight counts (source → keep)
--   gratitudes.author_id:      1 → moved
--   gratitudes.recipient_id:   0
--   hearts.user_id:            0 (no overlaps)
--   notifications.user_id:     2 → moved
--   notifications.from_user_id:1 → moved
--   device_push_tokens:        1 → moved
--   idempotency_keys:          1 → moved
--   user_blocks / donations / content_reports / email_reply_tokens: 0
--
-- Web follow-up
--   Permanent redirect /zpry7p5yjp → /elton in next.config.mjs
--
-- Manual checklist (already done in the linked transaction; listed for future merges)
--   [x] Reassign public activity tables to KEEP id (dedupe hearts / blocks / tokens)
--   [x] UPDATE auth.identities SET user_id = KEEP WHERE provider = 'apple' (source)
--   [x] UPDATE auth.users.raw_app_meta_data.providers to include apple + google
--   [x] DELETE source sessions / tokens
--   [x] DELETE source profiles + auth.users
--   [x] Confirm KEEP username = elton, avatar retained, both identities present
--   [ ] After deploy: curl -sI https://openthanks.com/zpry7p5yjp → 308 Location: /elton
--   [ ] Smoke: Sign in with Apple → lands on elton; Sign in with Google → same user
-- =============================================================================

BEGIN;

-- Sanity (abort if usernames drifted)
DO $$
DECLARE
  keep_id uuid := '8a4f63b0-f80b-4954-9a3a-4cabac87159a';
  source_id uuid := 'a5eb41c0-67f1-4d95-a111-609f0f051067';
  keep_username text;
  source_username text;
BEGIN
  SELECT username INTO keep_username FROM public.profiles WHERE id = keep_id;
  SELECT username INTO source_username FROM public.profiles WHERE id = source_id;
  IF keep_username IS DISTINCT FROM 'elton' OR source_username IS DISTINCT FROM 'zpry7p5yjp' THEN
    RAISE EXCEPTION 'Unexpected usernames: keep=%, source=%', keep_username, source_username;
  END IF;
END $$;

-- Hearts: drop overlaps, then reassign
DELETE FROM public.hearts h
WHERE h.user_id = 'a5eb41c0-67f1-4d95-a111-609f0f051067'
  AND EXISTS (
    SELECT 1 FROM public.hearts k
    WHERE k.user_id = '8a4f63b0-f80b-4954-9a3a-4cabac87159a'
      AND k.gratitude_id = h.gratitude_id
  );

UPDATE public.hearts
SET user_id = '8a4f63b0-f80b-4954-9a3a-4cabac87159a'
WHERE user_id = 'a5eb41c0-67f1-4d95-a111-609f0f051067';

UPDATE public.gratitudes
SET author_id = '8a4f63b0-f80b-4954-9a3a-4cabac87159a'
WHERE author_id = 'a5eb41c0-67f1-4d95-a111-609f0f051067';

UPDATE public.gratitudes
SET recipient_id = '8a4f63b0-f80b-4954-9a3a-4cabac87159a'
WHERE recipient_id = 'a5eb41c0-67f1-4d95-a111-609f0f051067';

UPDATE public.notifications
SET user_id = '8a4f63b0-f80b-4954-9a3a-4cabac87159a'
WHERE user_id = 'a5eb41c0-67f1-4d95-a111-609f0f051067';

UPDATE public.notifications
SET from_user_id = '8a4f63b0-f80b-4954-9a3a-4cabac87159a'
WHERE from_user_id = 'a5eb41c0-67f1-4d95-a111-609f0f051067';

-- Blocks: drop self/dupe edges, then reassign
DELETE FROM public.user_blocks
WHERE (blocker_id = 'a5eb41c0-67f1-4d95-a111-609f0f051067' AND blocked_id = '8a4f63b0-f80b-4954-9a3a-4cabac87159a')
   OR (blocker_id = '8a4f63b0-f80b-4954-9a3a-4cabac87159a' AND blocked_id = 'a5eb41c0-67f1-4d95-a111-609f0f051067');

UPDATE public.user_blocks
SET blocker_id = '8a4f63b0-f80b-4954-9a3a-4cabac87159a'
WHERE blocker_id = 'a5eb41c0-67f1-4d95-a111-609f0f051067';

UPDATE public.user_blocks
SET blocked_id = '8a4f63b0-f80b-4954-9a3a-4cabac87159a'
WHERE blocked_id = 'a5eb41c0-67f1-4d95-a111-609f0f051067';

DELETE FROM public.device_push_tokens d
WHERE d.user_id = 'a5eb41c0-67f1-4d95-a111-609f0f051067'
  AND EXISTS (
    SELECT 1 FROM public.device_push_tokens k
    WHERE k.user_id = '8a4f63b0-f80b-4954-9a3a-4cabac87159a'
      AND k.token = d.token
  );

UPDATE public.device_push_tokens
SET user_id = '8a4f63b0-f80b-4954-9a3a-4cabac87159a'
WHERE user_id = 'a5eb41c0-67f1-4d95-a111-609f0f051067';

UPDATE public.content_reports
SET reporter_id = '8a4f63b0-f80b-4954-9a3a-4cabac87159a'
WHERE reporter_id = 'a5eb41c0-67f1-4d95-a111-609f0f051067';

UPDATE public.donations
SET donor_id = '8a4f63b0-f80b-4954-9a3a-4cabac87159a'
WHERE donor_id = 'a5eb41c0-67f1-4d95-a111-609f0f051067';

UPDATE public.donations
SET honoree_id = '8a4f63b0-f80b-4954-9a3a-4cabac87159a'
WHERE honoree_id = 'a5eb41c0-67f1-4d95-a111-609f0f051067';

UPDATE public.donation_pledges
SET pledger_id = '8a4f63b0-f80b-4954-9a3a-4cabac87159a'
WHERE pledger_id = 'a5eb41c0-67f1-4d95-a111-609f0f051067';

UPDATE public.donation_pledges
SET recipient_id = '8a4f63b0-f80b-4954-9a3a-4cabac87159a'
WHERE recipient_id = 'a5eb41c0-67f1-4d95-a111-609f0f051067';

UPDATE public.email_reply_tokens
SET user_id = '8a4f63b0-f80b-4954-9a3a-4cabac87159a'
WHERE user_id = 'a5eb41c0-67f1-4d95-a111-609f0f051067';

UPDATE public.idempotency_keys
SET user_id = '8a4f63b0-f80b-4954-9a3a-4cabac87159a'
WHERE user_id = 'a5eb41c0-67f1-4d95-a111-609f0f051067';

-- Auth: move Apple identity onto elton
UPDATE auth.identities
SET user_id = '8a4f63b0-f80b-4954-9a3a-4cabac87159a'
WHERE id = 'fac8789f-9d2b-4f9b-8095-0541d2e84a11'
  AND user_id = 'a5eb41c0-67f1-4d95-a111-609f0f051067';

UPDATE auth.users
SET raw_app_meta_data = jsonb_set(
  coalesce(raw_app_meta_data, '{}'::jsonb),
  '{providers}',
  (
    SELECT to_jsonb(array_agg(DISTINCT p ORDER BY p))
    FROM (
      SELECT jsonb_array_elements_text(
        coalesce(raw_app_meta_data->'providers', '[]'::jsonb) || '["apple"]'::jsonb
      ) AS p
    ) s
  )
)
WHERE id = '8a4f63b0-f80b-4954-9a3a-4cabac87159a';

DELETE FROM auth.sessions WHERE user_id = 'a5eb41c0-67f1-4d95-a111-609f0f051067';
DELETE FROM auth.refresh_tokens WHERE user_id = 'a5eb41c0-67f1-4d95-a111-609f0f051067';
DELETE FROM auth.identities WHERE user_id = 'a5eb41c0-67f1-4d95-a111-609f0f051067';

DELETE FROM public.profiles WHERE id = 'a5eb41c0-67f1-4d95-a111-609f0f051067';
DELETE FROM auth.users WHERE id = 'a5eb41c0-67f1-4d95-a111-609f0f051067';

COMMIT;

-- Web redirect: v0-gratitude-network branch cursor/merge-elton-zpry-redirect-9469 (next.config.mjs)
