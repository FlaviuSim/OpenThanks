-- One unsent compose draft per account, plus when to nudge.
--
-- The phone still schedules its own local notification. This row is the email
-- backup, and the remote push for a draft that was saved on the website
-- (where there is no local notification). Older app versions never read it.
--
-- Timing, chosen once when the recipient is first saved:
--   push scheduled (local or one remote APNs) → email 48h later, and only if
--     the push was not opened (push_responded_at is null)
--   no push → email 24h later
-- Sending or clearing the draft deletes the row, which cancels the email.
-- A message edit for the same recipient does not reset the clock.
-- A different recipient replaces the row and starts a new clock.
--
-- Website (signed-in) should call, on leaving the form with text:
--   select public.upsert_compose_draft(
--     null, recipient, message, false, 'web');
-- and public.delete_compose_draft() after a successful send.
-- Web push is not available; a saved iOS device token gets one remote push
-- at 24h, then the email at 48h if that push is not opened.

create table if not exists public.compose_drafts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references public.profiles(id) on delete cascade,
  recipient text not null default '',
  message text not null default '',
  -- none: email only. local: this phone already scheduled the banner.
  -- remote: send one APNs at push_due_at (web-originated, device token exists).
  push_channel text not null default 'none'
    check (push_channel in ('none', 'local', 'remote')),
  push_due_at timestamptz,
  push_sent_at timestamptz,
  push_responded_at timestamptz,
  push_attempts integer not null default 0,
  push_claimed_at timestamptz,
  email_due_at timestamptz,
  email_sent_at timestamptz,
  email_attempts integer not null default 0,
  email_claimed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint compose_drafts_has_text check (
    length(btrim(recipient)) > 0 or length(btrim(message)) > 0
  )
);

create index if not exists compose_drafts_email_due_idx
  on public.compose_drafts (email_due_at)
  where email_sent_at is null
    and push_responded_at is null
    and email_due_at is not null;

create index if not exists compose_drafts_push_due_idx
  on public.compose_drafts (push_due_at)
  where push_channel = 'remote'
    and push_sent_at is null
    and push_responded_at is null;

alter table public.compose_drafts enable row level security;

revoke all on public.compose_drafts from public, anon, authenticated;
grant select, delete on public.compose_drafts to authenticated;

drop policy if exists compose_drafts_select_own on public.compose_drafts;
create policy compose_drafts_select_own
  on public.compose_drafts for select to authenticated
  using (auth.uid() = user_id);

drop policy if exists compose_drafts_delete_own on public.compose_drafts;
create policy compose_drafts_delete_own
  on public.compose_drafts for delete to authenticated
  using (auth.uid() = user_id);

create or replace function public.upsert_compose_draft(
  p_id uuid default null,
  p_recipient text default '',
  p_message text default '',
  p_push_scheduled boolean default false,
  p_origin text default 'web'
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  rec text := btrim(coalesce(p_recipient, ''));
  msg text := left(btrim(coalesce(p_message, '')), 1500);
  origin text := case when p_origin = 'ios' then 'ios' else 'web' end;
  existing public.compose_drafts%rowtype;
  channel text;
  due_email timestamptz;
  due_push timestamptz;
begin
  if uid is null then
    raise exception 'not authenticated';
  end if;

  if rec = '' and msg = '' then
    delete from public.compose_drafts where user_id = uid;
    return;
  end if;

  select * into existing
  from public.compose_drafts
  where user_id = uid;

  -- Same recipient: keep the one reminder. A local push that was just
  -- accepted (within 10 minutes) moves the email out to 48h. A later
  -- permission grant does not postpone an email that is already planned.
  if found and existing.recipient = rec then
    if p_push_scheduled
       and existing.push_channel = 'none'
       and existing.push_sent_at is null
       and existing.push_responded_at is null
       and existing.email_sent_at is null
       and existing.created_at > now() - interval '10 minutes'
       and rec <> '' then
      update public.compose_drafts
      set message = msg,
          push_channel = 'local',
          push_due_at = null,
          email_due_at = now() + interval '48 hours',
          updated_at = now()
      where user_id = uid;
    else
      update public.compose_drafts
      set message = msg,
          updated_at = now()
      where user_id = uid;
    end if;
    return;
  end if;

  if rec = '' then
    channel := 'none';
    due_email := null;
    due_push := null;
  elsif p_push_scheduled then
    channel := 'local';
    due_email := now() + interval '48 hours';
    due_push := null;
  elsif origin = 'web' and exists (
    select 1 from public.device_push_tokens t where t.user_id = uid
  ) then
    channel := 'remote';
    due_push := now() + interval '24 hours';
    due_email := now() + interval '48 hours';
  else
    -- iOS with notifications off, or web with no device token.
    channel := 'none';
    due_email := now() + interval '24 hours';
    due_push := null;
  end if;

  insert into public.compose_drafts (
    id, user_id, recipient, message, push_channel,
    push_due_at, email_due_at, updated_at
  ) values (
    coalesce(p_id, gen_random_uuid()),
    uid, rec, msg, channel, due_push, due_email, now()
  )
  on conflict (user_id) do update set
    id = excluded.id,
    recipient = excluded.recipient,
    message = excluded.message,
    push_channel = excluded.push_channel,
    push_due_at = excluded.push_due_at,
    push_sent_at = null,
    push_responded_at = null,
    push_attempts = 0,
    push_claimed_at = null,
    email_due_at = excluded.email_due_at,
    email_sent_at = null,
    email_attempts = 0,
    email_claimed_at = null,
    created_at = now(),
    updated_at = now();
end;
$$;

create or replace function public.delete_compose_draft()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'not authenticated';
  end if;
  delete from public.compose_drafts where user_id = uid;
end;
$$;

create or replace function public.respond_compose_draft()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'not authenticated';
  end if;
  update public.compose_drafts
  set push_responded_at = coalesce(push_responded_at, now()),
      updated_at = now()
  where user_id = uid;
end;
$$;

-- Service-role worker claims. Not granted to signed-in users.
create or replace function public.claim_compose_draft_pushes(p_limit integer default 50)
returns setof public.compose_drafts
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
  with due as (
    select d.id
    from public.compose_drafts d
    where d.push_channel = 'remote'
      and d.push_sent_at is null
      and d.push_responded_at is null
      and d.push_due_at is not null
      and d.push_due_at <= now()
      and d.push_attempts < 3
      and (
        d.push_claimed_at is null
        or d.push_claimed_at < now() - interval '15 minutes'
      )
    order by d.push_due_at
    limit greatest(1, least(coalesce(p_limit, 50), 100))
    for update skip locked
  )
  update public.compose_drafts d
  set push_claimed_at = now(),
      push_attempts = d.push_attempts + 1
  from due
  where d.id = due.id
  returning d.*;
end;
$$;

create or replace function public.finish_compose_draft_push(p_id uuid, p_sent boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_sent then
    update public.compose_drafts
    set push_sent_at = now(),
        push_claimed_at = null
    where id = p_id;
  else
    update public.compose_drafts
    set push_sent_at = case when push_attempts >= 3 then now() else null end,
        push_claimed_at = null
    where id = p_id;
  end if;
end;
$$;

create or replace function public.claim_compose_draft_emails(p_limit integer default 50)
returns setof public.compose_drafts
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
  with due as (
    select d.id
    from public.compose_drafts d
    where d.email_sent_at is null
      and d.push_responded_at is null
      and d.email_due_at is not null
      and d.email_due_at <= now()
      and d.email_attempts < 3
      and length(btrim(d.recipient)) > 0
      and (
        d.email_claimed_at is null
        or d.email_claimed_at < now() - interval '15 minutes'
      )
    order by d.email_due_at
    limit greatest(1, least(coalesce(p_limit, 50), 100))
    for update skip locked
  )
  update public.compose_drafts d
  set email_claimed_at = now(),
      email_attempts = d.email_attempts + 1
  from due
  where d.id = due.id
  returning d.*;
end;
$$;

create or replace function public.finish_compose_draft_email(p_id uuid, p_sent boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_sent then
    update public.compose_drafts
    set email_sent_at = now(),
        email_claimed_at = null
    where id = p_id;
  else
    update public.compose_drafts
    set email_sent_at = case when email_attempts >= 3 then now() else null end,
        email_claimed_at = null
    where id = p_id;
  end if;
end;
$$;

revoke all on function public.upsert_compose_draft(uuid, text, text, boolean, text) from public, anon;
revoke all on function public.delete_compose_draft() from public, anon;
revoke all on function public.respond_compose_draft() from public, anon;
grant execute on function public.upsert_compose_draft(uuid, text, text, boolean, text) to authenticated, service_role;
grant execute on function public.delete_compose_draft() to authenticated, service_role;
grant execute on function public.respond_compose_draft() to authenticated, service_role;

revoke all on function public.claim_compose_draft_pushes(integer) from public, anon, authenticated;
revoke all on function public.finish_compose_draft_push(uuid, boolean) from public, anon, authenticated;
revoke all on function public.claim_compose_draft_emails(integer) from public, anon, authenticated;
revoke all on function public.finish_compose_draft_email(uuid, boolean) from public, anon, authenticated;
grant execute on function public.claim_compose_draft_pushes(integer) to service_role;
grant execute on function public.finish_compose_draft_push(uuid, boolean) to service_role;
grant execute on function public.claim_compose_draft_emails(integer) to service_role;
grant execute on function public.finish_compose_draft_email(uuid, boolean) to service_role;

comment on table public.compose_drafts is
  'One unsent thank-you per account. Email at 24h if no push was scheduled, or at 48h if a push was scheduled and not opened.';

-- Best-effort scheduler. Missing pg_cron, pg_net, or the vault key does not
-- roll back the table. The key is read on the server; it is not stored here.
do $cron$
declare
  service_key text;
begin
  begin
    create extension if not exists pg_net with schema extensions;
  exception when others then
    raise warning 'compose draft reminders: pg_net unavailable: %', sqlerrm;
    return;
  end;

  begin
    create extension if not exists pg_cron with schema pg_catalog;
  exception when others then
    raise warning 'compose draft reminders: pg_cron unavailable: %', sqlerrm;
    return;
  end;

  select ds.decrypted_secret
    into service_key
  from vault.decrypted_secrets ds
  where ds.name = 'compose_draft_reminder_key'
  limit 1;

  if service_key is null or length(btrim(service_key)) = 0 then
    begin
      service_key := nullif(current_setting('supabase.service_role_key', true), '');
    exception when others then
      service_key := null;
    end;
    if service_key is not null and length(btrim(service_key)) > 20 then
      begin
        perform vault.create_secret(
          service_key,
          'compose_draft_reminder_key',
          'Authorization for the compose draft reminder cron'
        );
      exception when others then
        raise warning 'compose draft reminders: could not store cron key: %', sqlerrm;
      end;
    end if;
  end if;

  begin
    perform cron.unschedule('compose-draft-reminders');
  exception when others then
    null;
  end;

  perform cron.schedule(
    'compose-draft-reminders',
    '*/5 * * * *',
    $job$
    select net.http_post(
      url := 'https://dsftvyuzmhlqadhbubgw.supabase.co/functions/v1/send-draft-reminders',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-openthanks-cron', 'compose-draft-reminders'
      ),
      body := '{}'::jsonb,
      timeout_milliseconds := 10000
    );
    $job$
  );
exception when others then
  raise warning 'compose draft reminders: cron not scheduled: %', sqlerrm;
end
$cron$;
