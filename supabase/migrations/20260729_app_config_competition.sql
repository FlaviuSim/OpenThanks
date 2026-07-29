-- Remote app configuration (competition campaigns, future feature flags).
-- Reads are public; writes are service-role / Studio only.

create table if not exists public.app_config (
  key text primary key,
  value jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

alter table public.app_config enable row level security;

drop policy if exists "app_config_select_all" on public.app_config;
create policy "app_config_select_all"
  on public.app_config
  for select
  to anon, authenticated
  using (true);

-- Ensure gratitudes.source exists (used by competition eligibility).
alter table public.gratitudes
  add column if not exists source text;

comment on column public.gratitudes.source is
  'Client channel: ios | watch | web | email_reply | etc.';

-- Seed competition config (disabled until launch day — flip enabled in Studio).
insert into public.app_config (key, value, updated_at)
values (
  'competition',
  '{
    "enabled": false,
    "id": "gratitude-30-2026",
    "title": "30 Days of Thanks",
    "subtitle": "Post gratitude 30 days in a row. Win $30.",
    "prizeLabel": "$30",
    "targetDays": 30,
    "startsAt": "2026-08-01T00:00:00Z",
    "endsAt": null,
    "allowedSources": ["ios", "watch"],
    "requireAccepted": true,
    "requireOtherRecipient": true,
    "termsUrl": "https://openthanks.com/competition",
    "rulesSummary": [
      "Must post in the OpenThanks iPhone or Apple Watch app",
      "Each day must thank a real person (accepted by someone other than you)",
      "If you win, we will notify you in-app with how to receive your $30"
    ],
    "winnerNotifyBody": "You completed 30 days! Reply with your preferred transfer method to claim your $30."
  }'::jsonb,
  now()
)
on conflict (key) do nothing;

-- ---------------------------------------------------------------------------
-- Admin verification helpers (service role / SQL editor).
-- UI progress is informative; payouts must use these rules server-side.
--
-- Eligible day = local calendar date of created_at where:
--   author_id = user
--   source in allowedSources
--   recipient_id is not null and <> author_id
--   status = 'accepted' when requireAccepted
--   created_at within [startsAt, endsAt)
--
-- Example: consecutive eligible days for one user (America/New_York):
--
--   with cfg as (
--     select value from app_config where key = 'competition'
--   ),
--   eligible as (
--     select distinct (
--       (g.created_at at time zone 'America/New_York')::date
--     ) as day
--     from gratitudes g, cfg
--     where g.author_id = '<USER_UUID>'
--       and g.source = any (array(select jsonb_array_elements_text(cfg.value->'allowedSources')))
--       and g.recipient_id is not null
--       and g.recipient_id <> g.author_id
--       and (
--         coalesce((cfg.value->>'requireAccepted')::boolean, true) = false
--         or g.status = 'accepted'
--       )
--       and g.created_at >= (cfg.value->>'startsAt')::timestamptz
--       and (
--         cfg.value->>'endsAt' is null
--         or g.created_at < (cfg.value->>'endsAt')::timestamptz
--       )
--   ),
--   ordered as (
--     select day, day - (row_number() over (order by day))::int as grp
--     from eligible
--   )
--   select count(*) as streak_len, min(day) as streak_start, max(day) as streak_end
--   from ordered
--   group by grp
--   order by streak_end desc;
--
-- Notify a verified winner (in-app):
--   insert into notifications (user_id, type, from_user_id)
--   values ('<USER_UUID>', 'competition_winner', null);
-- ---------------------------------------------------------------------------

create or replace function public.competition_eligible_day_count(p_user_id uuid)
returns integer
language sql
stable
security definer
set search_path = public
as $$
  with cfg as (
    select value
    from public.app_config
    where key = 'competition'
  ),
  eligible as (
    select distinct ((g.created_at at time zone 'UTC')::date) as day
    from public.gratitudes g
    cross join cfg
    where g.author_id = p_user_id
      and coalesce((cfg.value->>'enabled')::boolean, false) = true
      and g.source = any (
        array(select jsonb_array_elements_text(cfg.value->'allowedSources'))
      )
      and (
        coalesce((cfg.value->>'requireOtherRecipient')::boolean, true) = false
        or (
          g.recipient_id is not null
          and g.recipient_id <> g.author_id
        )
      )
      and (
        coalesce((cfg.value->>'requireAccepted')::boolean, true) = false
        or g.status = 'accepted'
      )
      and (
        cfg.value->>'startsAt' is null
        or g.created_at >= (cfg.value->>'startsAt')::timestamptz
      )
      and (
        cfg.value->>'endsAt' is null
        or g.created_at < (cfg.value->>'endsAt')::timestamptz
      )
  )
  select coalesce(count(*)::integer, 0) from eligible;
$$;

revoke all on function public.competition_eligible_day_count(uuid) from public;
grant execute on function public.competition_eligible_day_count(uuid) to authenticated, service_role;
