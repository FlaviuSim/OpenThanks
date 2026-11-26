-- Fix: device token upsert fails RLS when the APNs token already belongs to
-- another account on the same device ("violates … USING expression").
--
-- 1) Claim policy — lets authenticated clients reassign a token to themselves
--    via normal upsert (UPDATE USING passes; WITH CHECK still requires own user_id).
-- 2) RPC — preferred path from the app (reclaim + upsert in one call).

-- ---------------------------------------------------------------------------
-- 1) Claim policy
-- ---------------------------------------------------------------------------
drop policy if exists "device_push_tokens_claim_token" on public.device_push_tokens;
create policy "device_push_tokens_claim_token"
  on public.device_push_tokens
  for update
  to authenticated
  using (true)
  with check (auth.uid() = user_id);

comment on policy "device_push_tokens_claim_token" on public.device_push_tokens is
  'Allow reclaiming an APNs/FCM token from a prior account on the same device.';

-- ---------------------------------------------------------------------------
-- 2) RPC
-- ---------------------------------------------------------------------------
create or replace function public.upsert_device_push_token(
  p_token text,
  p_platform text default 'ios',
  p_environment text default 'production'
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_platform text := lower(coalesce(nullif(trim(p_platform), ''), 'ios'));
  v_environment text := lower(coalesce(nullif(trim(p_environment), ''), 'production'));
  v_token text := trim(p_token);
begin
  if v_uid is null then
    raise exception 'Not authenticated';
  end if;

  if v_token is null or length(v_token) < 8 then
    raise exception 'Invalid device token';
  end if;

  if v_platform not in ('ios', 'android') then
    raise exception 'Invalid platform';
  end if;

  if v_environment not in ('sandbox', 'production') then
    raise exception 'Invalid environment';
  end if;

  delete from public.device_push_tokens
  where token = v_token
    and user_id is distinct from v_uid;

  insert into public.device_push_tokens as t (user_id, token, platform, environment)
  values (v_uid, v_token, v_platform, v_environment)
  on conflict (token) do update
    set user_id = excluded.user_id,
        platform = excluded.platform,
        environment = excluded.environment,
        updated_at = now()
  where t.user_id = v_uid;
end;
$$;

revoke all on function public.upsert_device_push_token(text, text, text) from public;
grant execute on function public.upsert_device_push_token(text, text, text) to authenticated;

comment on function public.upsert_device_push_token(text, text, text) is
  'Registers the caller''s APNs/FCM token; reclaims the token if another user had it.';
