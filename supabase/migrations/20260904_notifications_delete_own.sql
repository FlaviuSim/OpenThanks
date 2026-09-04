-- Allow users to delete their own notification rows (e.g. expired Friday prompts).
CREATE POLICY "notifications_delete_own"
  ON public.notifications
  FOR DELETE
  USING (auth.uid() = user_id);
