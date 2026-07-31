-- Challenge window: count streaks from July 1, 2026 (was Aug 1, which hid all current progress).
update public.app_config
set
  value = jsonb_set(value, '{startsAt}', '"2026-07-01T00:00:00Z"'::jsonb),
  updated_at = now()
where key = 'competition';
