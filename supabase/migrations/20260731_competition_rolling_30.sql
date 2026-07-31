-- Rolling 30-day challenge: no fixed month window (clear startsAt/endsAt).
update public.app_config
set
  value = value
    || jsonb_build_object(
      'startsAt', null,
      'endsAt', null,
      'subtitle', 'Start anytime. Build a rolling 30-day streak. Unlock $30 to give away.',
      'rulesSummary', jsonb_build_array(
        'Rolling challenge — start any day; not tied to a calendar month',
        'Must post in the OpenThanks iPhone or Apple Watch app',
        'Each day must thank a real person (accepted by someone other than you)',
        'Finishers unlock $30 to give away via a DonorsChoose gift card — not cash to keep'
      )
    ),
  updated_at = now()
where key = 'competition';
