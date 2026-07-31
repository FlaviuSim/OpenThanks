-- Reframe 30 Days of Thanks: unlock $30 to give away (DonorsChoose), not cash to keep.
update public.app_config
set
  value = jsonb_set(
    jsonb_set(
      jsonb_set(
        jsonb_set(
          jsonb_set(
            value,
            '{subtitle}',
            '"Post 30 days in a row. Unlock $30 to give away to a classroom."'::jsonb
          ),
          '{prizeLabel}',
          '"$30 to give"'::jsonb
        ),
        '{rulesSummary}',
        '[
          "Must post in the OpenThanks iPhone or Apple Watch app",
          "Each day must thank a real person (accepted by someone other than you)",
          "Finishers unlock $30 to give away via a DonorsChoose gift card — not cash to keep"
        ]'::jsonb
      ),
      '{winnerNotifyBody}',
      '"You finished 30 days! Open this note for how to unlock your $30 DonorsChoose gift for a classroom."'::jsonb
    ),
    '{title}',
    '"30 Days of Thanks"'::jsonb
  ),
  updated_at = now()
where key = 'competition';
