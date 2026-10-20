-- Reassign an APNs token to the currently signed-in user.
-- Plain upsert fails RLS UPDATE USING when the token row still belongs to a
-- previous account on the same device (unique index on token).

create or replace function public.upsert_my_device_push_token(
  p_token text,
  p_platform text default 'ios',
  p_environment text default 'production'
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  if p_token is null or btrim(p_token) = '' then
    raise exception 'token required';
  end if;

  if p_platform is null or p_platform not in ('ios', 'android') then
    raise exception 'invalid platform';
  end if;

  if p_environment is null or p_environment not in ('sandbox', 'production') then
    raise exception 'invalid environment';
  end if;

  delete from public.device_push_tokens
  where token = p_token;

  insert into public.device_push_tokens (user_id, token, platform, environment)
  values (auth.uid(), p_token, p_platform, p_environment);
end;
$$;

revoke all on function public.upsert_my_device_push_token(text, text, text) from public;
grant execute on function public.upsert_my_device_push_token(text, text, text) to authenticated;

comment on function public.upsert_my_device_push_token(text, text, text) is
  'Moves a device push token to auth.uid(), replacing any prior owner of that token.';
