-- Mirror of web scripts/019 — claim email bounce / delivery status.
ALTER TABLE public.gratitudes
  ADD COLUMN IF NOT EXISTS recipient_email_status TEXT,
  ADD COLUMN IF NOT EXISTS recipient_email_status_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS recipient_email_error TEXT,
  ADD COLUMN IF NOT EXISTS last_resend_email_id TEXT;

CREATE INDEX IF NOT EXISTS idx_gratitudes_last_resend_email_id
  ON public.gratitudes (last_resend_email_id)
  WHERE last_resend_email_id IS NOT NULL;
