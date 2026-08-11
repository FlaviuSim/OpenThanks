-- Stories-style appreciation card layout
ALTER TABLE public.gratitudes
  ADD COLUMN IF NOT EXISTS card_style JSONB;

COMMENT ON COLUMN public.gratitudes.card_style IS
  'Optional Stories-style card: { version, backgroundId, typePreset, textAlign }.';
