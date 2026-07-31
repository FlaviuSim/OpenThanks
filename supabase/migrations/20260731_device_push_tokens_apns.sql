-- APNs / remote push foundation: device tokens + helper to fan out later.
-- Edge Function `send-apns` reads these rows and talks to Apple.

create table if not exists public.device_push_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  token text not null,
  platform text not null default 'ios'
    check (platform in ('ios', 'android')),
  -- sandbox = Xcode debug / development APNs; production = TestFlight + App Store
  environment text not null default 'production'
    check (environment in ('sandbox', 'production')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Evolve existing tables that only had user_id / token / platform.
alter table public.device_push_tokens
  add column if not exists environment text;

alter table public.device_push_tokens
  add column if not exists created_at timestamptz;

alter table public.device_push_tokens
  add column if not exists updated_at timestamptz;

alter table public.device_push_tokens
  add column if not exists id uuid;

update public.device_push_tokens
set environment = coalesce(nullif(environment, ''), 'production')
where environment is null or environment = '';

update public.device_push_tokens
set created_at = coalesce(created_at, now())
where created_at is null;

update public.device_push_tokens
set updated_at = coalesce(updated_at, now())
where updated_at is null;

update public.device_push_tokens
set id = coalesce(id, gen_random_uuid())
where id is null;

alter table public.device_push_tokens
  alter column environment set default 'production';

alter table public.device_push_tokens
  alter column environment set not null;

-- Unique device token (one row per APNs token).
create unique index if not exists device_push_tokens_token_uidx
  on public.device_push_tokens (token);

create index if not exists device_push_tokens_user_id_idx
  on public.device_push_tokens (user_id);

alter table public.device_push_tokens enable row level security;

drop policy if exists "device_push_tokens_select_own" on public.device_push_tokens;
create policy "device_push_tokens_select_own"
  on public.device_push_tokens for select to authenticated
  using (auth.uid() = user_id);

drop policy if exists "device_push_tokens_insert_own" on public.device_push_tokens;
create policy "device_push_tokens_insert_own"
  on public.device_push_tokens for insert to authenticated
  with check (auth.uid() = user_id);

drop policy if exists "device_push_tokens_update_own" on public.device_push_tokens;
create policy "device_push_tokens_update_own"
  on public.device_push_tokens for update to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "device_push_tokens_delete_own" on public.device_push_tokens;
create policy "device_push_tokens_delete_own"
  on public.device_push_tokens for delete to authenticated
  using (auth.uid() = user_id);

-- Keep updated_at fresh on upsert/update.
create or replace function public.set_device_push_token_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists device_push_tokens_set_updated_at on public.device_push_tokens;
create trigger device_push_tokens_set_updated_at
  before update on public.device_push_tokens
  for each row execute function public.set_device_push_token_updated_at();

comment on table public.device_push_tokens is
  'APNs / FCM device tokens. Written by the app; read by Edge Function send-apns (service role).';

-- ---------------------------------------------------------------------------
-- Optional: after secrets are set and `send-apns` is deployed, add a Database
-- Webhook (Dashboard → Database → Webhooks) on public.notifications INSERT
-- that POSTs to:
--   https://<project-ref>.supabase.co/functions/v1/send-apns
-- with body mapped from the new row, e.g.:
--   { "user_id": <user_id>, "notification_id": <id>, "type": <type> }
-- Or call the function from your Next.js API / cron with the service role key.
-- ---------------------------------------------------------------------------
