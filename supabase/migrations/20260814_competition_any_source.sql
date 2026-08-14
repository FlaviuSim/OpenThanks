-- Allow any post source for the challenge; drop iPhone/Watch-only copy.
update public.app_config
set
  value = value
    || jsonb_build_object(
      'allowedSources', '[]'::jsonb,
      'rulesSummary', jsonb_build_array(
        'Send thanks 30 days in a row (start any day)',
        'Finishers unlock $30 to give away to a classroom (not cash to keep)'
      )
    ),
  updated_at = now()
where key = 'competition';
