-- Six for '26 finisher ledger (first 20, offline payout).
-- Qualification is re-checked in claim_six_for_2026_finisher().

create table if not exists public.campaign_finishers (
  id uuid primary key default gen_random_uuid(),
  campaign_id text not null,
  user_id uuid not null references public.profiles (id) on delete cascade,
  completed_at timestamptz not null default now(),
  gratitude_ids uuid[] not null default '{}',
  nonprofit_ein text,
  nonprofit_name text not null,
  rank integer,
  status text not null default 'pending_review'
    check (status in ('pending_review', 'eligible', 'paid', 'rejected', 'pool_full')),
  notes text,
  created_at timestamptz not null default now(),
  unique (campaign_id, user_id)
);

create index if not exists campaign_finishers_campaign_rank_idx
  on public.campaign_finishers (campaign_id, rank)
  where rank is not null;

create index if not exists campaign_finishers_campaign_completed_idx
  on public.campaign_finishers (campaign_id, completed_at);

alter table public.campaign_finishers enable row level security;

drop policy if exists "campaign_finishers_select_own" on public.campaign_finishers;
create policy "campaign_finishers_select_own"
  on public.campaign_finishers
  for select
  to authenticated
  using (auth.uid() = user_id);

create or replace function public.six_for_2026_qualifying_ids(p_user_id uuid)
returns uuid[]
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  window_start timestamptz := timezone('UTC', timezone('America/New_York', timestamp '2026-12-01 00:00:00'));
  window_end timestamptz := timezone('UTC', timezone('America/New_York', timestamp '2027-01-01 00:00:00'));
  r record;
  used_days date[] := '{}';
  used_keys text[] := '{}';
  result uuid[] := '{}';
  recipient_key text;
  day_et date;
begin
  for r in
    select
      g.id,
      g.created_at,
      (timezone('America/New_York', g.created_at))::date as day_et,
      lower(coalesce(
        g.recipient_id::text,
        nullif(trim(g.recipient_email), ''),
        nullif(trim(g.recipient_phone), ''),
        nullif(trim(g.recipient_name), '')
      )) as recipient_key
    from public.gratitudes g
    where g.author_id = p_user_id
      and g.created_at >= window_start
      and g.created_at < window_end
      and g.status = 'accepted'
      and coalesce(g.visibility, 'public') = 'public'
      and coalesce(g.accepted_as_private, false) = false
    order by g.created_at asc, g.id asc
  loop
    recipient_key := r.recipient_key;
    day_et := r.day_et;
    if recipient_key is null then
      continue;
    end if;
    if day_et = any (used_days) then
      continue;
    end if;
    if recipient_key = any (used_keys) then
      continue;
    end if;
    used_days := array_append(used_days, day_et);
    used_keys := array_append(used_keys, recipient_key);
    result := array_append(result, r.id);
    exit when coalesce(array_length(result, 1), 0) >= 6;
  end loop;

  return result;
end;
$$;

revoke all on function public.six_for_2026_qualifying_ids(uuid) from public;
grant execute on function public.six_for_2026_qualifying_ids(uuid) to authenticated;
grant execute on function public.six_for_2026_qualifying_ids(uuid) to service_role;

create or replace function public.claim_six_for_2026_finisher()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  ids uuid[];
  nonprofit_name text;
  nonprofit_ein text;
  existing public.campaign_finishers%rowtype;
  taken integer;
  new_rank integer;
  inserted public.campaign_finishers%rowtype;
begin
  if uid is null then
    return jsonb_build_object('ok', false, 'error', 'not_authenticated');
  end if;

  select f.* into existing
  from public.campaign_finishers f
  where f.campaign_id = 'six-for-2026' and f.user_id = uid;

  if found then
    return jsonb_build_object(
      'ok', existing.status in ('pending_review', 'eligible', 'paid'),
      'rank', existing.rank,
      'status', existing.status,
      'poolFull', existing.status = 'pool_full',
      'message', case
        when existing.status = 'pool_full' then 'The first 20 finishers are already claimed.'
        when existing.rank is not null then format('You are #%s of 20.', existing.rank)
        else 'Already submitted.'
      end
    );
  end if;

  select p.favorite_nonprofit_name, p.favorite_nonprofit_ein
  into nonprofit_name, nonprofit_ein
  from public.profiles p
  where p.id = uid;

  if nonprofit_name is null or length(trim(nonprofit_name)) = 0 then
    return jsonb_build_object(
      'ok', false,
      'error', 'missing_nonprofit',
      'message', 'Add a favorite charity on your profile before claiming.'
    );
  end if;

  ids := public.six_for_2026_qualifying_ids(uid);
  if coalesce(array_length(ids, 1), 0) < 6 then
    return jsonb_build_object(
      'ok', false,
      'error', 'not_qualified',
      'qualified', coalesce(array_length(ids, 1), 0),
      'message', 'Need 6 public-accepted thank-yous to 6 different people on 6 different December days.'
    );
  end if;

  select count(*)::integer into taken
  from public.campaign_finishers
  where campaign_id = 'six-for-2026'
    and status in ('pending_review', 'eligible', 'paid')
    and rank is not null;

  if taken >= 20 then
    insert into public.campaign_finishers (
      campaign_id, user_id, gratitude_ids, nonprofit_ein, nonprofit_name, rank, status
    ) values (
      'six-for-2026', uid, ids, nonprofit_ein, trim(nonprofit_name), null, 'pool_full'
    )
    returning * into inserted;

    return jsonb_build_object(
      'ok', false,
      'poolFull', true,
      'status', inserted.status,
      'message', 'The first 20 finishers are already claimed. Thank you for completing Six for ''26 anyway.'
    );
  end if;

  new_rank := taken + 1;

  insert into public.campaign_finishers (
    campaign_id, user_id, gratitude_ids, nonprofit_ein, nonprofit_name, rank, status
  ) values (
    'six-for-2026', uid, ids, nonprofit_ein, trim(nonprofit_name), new_rank, 'eligible'
  )
  returning * into inserted;

  return jsonb_build_object(
    'ok', true,
    'rank', inserted.rank,
    'status', inserted.status,
    'poolFull', false,
    'message', format('You are #%s of 20. We will contact you outside the app about the $600 donation.', inserted.rank)
  );
exception
  when unique_violation then
    select f.* into existing
    from public.campaign_finishers f
    where f.campaign_id = 'six-for-2026' and f.user_id = uid;
    return jsonb_build_object(
      'ok', existing.status in ('pending_review', 'eligible', 'paid'),
      'rank', existing.rank,
      'status', existing.status,
      'poolFull', existing.status = 'pool_full'
    );
end;
$$;

revoke all on function public.claim_six_for_2026_finisher() from public;
grant execute on function public.claim_six_for_2026_finisher() to authenticated;
grant execute on function public.claim_six_for_2026_finisher() to service_role;
