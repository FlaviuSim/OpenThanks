-- 30 Days of Thanks: count sends only (acceptance not required); shorter in-app rules.
update public.app_config
set
  value = value
    || jsonb_build_object(
      'requireAccepted', false,
      'subtitle', 'Send one thanks a day for 30 days. They don’t need to accept — sending counts.',
      'prizeLabel', '$30 to give',
      'rulesSummary', jsonb_build_array(
        'Send thanks 30 days in a row (start any day)',
        'Post from the iPhone or Apple Watch app',
        'Sending counts — the other person doesn’t have to accept',
        'Finishers unlock $30 to give away to a classroom (not cash to keep)'
      ),
      'winnerNotifyBody', 'You finished 30 days! Open this note for how to unlock your $30 classroom gift.'
    ),
  updated_at = now()
where key = 'competition';
