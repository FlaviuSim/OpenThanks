-- =============================================================================
-- Retarget appreciation: kat-cozadd → connorgillooly
-- Executed against production (dsftvyuzmhlqadhbubgw / db.openthanks.com) on 2026-11-20.
-- Kept for audit / replay reference. Do NOT re-run against production.
-- =============================================================================
--
-- Why
--   https://openthanks.com/for/kat-cozadd/from/flaviu-simihaian was addressed to
--   Connor (message + recipient_email/name) but recipient_id / slug pointed at Kat.
--
-- Resolved IDs
--   gratitude  c19d65e1-0c72-4c51-b383-33fb0a67703b
--   author     flaviu / Flaviu Simihaian  7ab6b8ff-5f1f-4b13-80cf-e84c5e87fc14
--   was        katcozadd / Kat Cozadd     41103c1d-1f4e-4f07-b3ba-0de5458f2383
--   now        connorgillooly / Connor    6d39095a-6779-410a-98b1-c2f890be65cc
--
-- Changes
--   gratitudes.recipient_id → Connor
--   gratitudes.slug → connor-gillooly/from/flaviu-simihaian
--   notifications gratitude_received.from_user_id Kat → Connor
--   notifications gratitude_pending for Connor marked read
--
-- Web follow-up
--   Permanent redirect /for/kat-cozadd/from/flaviu-simihaian
--     → /for/connor-gillooly/from/flaviu-simihaian in next.config.mjs
-- =============================================================================

BEGIN;

UPDATE public.gratitudes
SET
  recipient_id = '6d39095a-6779-410a-98b1-c2f890be65cc',
  recipient_name = 'Connor Gillooly',
  recipient_email = 'connor@creditmark.io',
  slug = 'connor-gillooly/from/flaviu-simihaian'
WHERE id = 'c19d65e1-0c72-4c51-b383-33fb0a67703b'
  AND slug = 'kat-cozadd/from/flaviu-simihaian'
  AND recipient_id = '41103c1d-1f4e-4f07-b3ba-0de5458f2383';

UPDATE public.notifications
SET from_user_id = '6d39095a-6779-410a-98b1-c2f890be65cc'
WHERE id = '720a54f4-70c5-4279-9b1c-b98af3ce2eca'
  AND type = 'gratitude_received'
  AND gratitude_id = 'c19d65e1-0c72-4c51-b383-33fb0a67703b'
  AND from_user_id = '41103c1d-1f4e-4f07-b3ba-0de5458f2383';

UPDATE public.notifications
SET read = true
WHERE id = '9bdf90fe-0db1-4b52-91ae-796612da1d6b'
  AND type = 'gratitude_pending'
  AND user_id = '6d39095a-6779-410a-98b1-c2f890be65cc'
  AND gratitude_id = 'c19d65e1-0c72-4c51-b383-33fb0a67703b';

COMMIT;
