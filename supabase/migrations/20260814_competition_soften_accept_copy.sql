-- Drop “doesn’t have to accept” wording from in-app challenge copy (send-only rules unchanged).
update public.app_config
set
  value = value
    || jsonb_build_object(
      'subtitle', 'Send one thanks a day for 30 days. Finishers unlock $30 to give away.',
      'rulesSummary', jsonb_build_array(
        'Send thanks 30 days in a row (start any day)',
        'Post from the iPhone or Apple Watch app',
        'Finishers unlock $30 to give away to a classroom (not cash to keep)'
      )
    ),
  updated_at = now()
where key = 'competition';
