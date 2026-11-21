-- Faster people search: prefix indexes + trigram for substring matches.
-- Called from the app/web via rpc('search_profiles').

CREATE EXTENSION IF NOT EXISTS pg_trgm;

CREATE INDEX IF NOT EXISTS profiles_username_lower_prefix_idx
  ON public.profiles (lower(username) text_pattern_ops);

CREATE INDEX IF NOT EXISTS profiles_full_name_lower_prefix_idx
  ON public.profiles (lower(full_name) text_pattern_ops)
  WHERE full_name IS NOT NULL;

CREATE INDEX IF NOT EXISTS profiles_username_trgm_idx
  ON public.profiles USING gin (username gin_trgm_ops);

CREATE INDEX IF NOT EXISTS profiles_full_name_trgm_idx
  ON public.profiles USING gin (full_name gin_trgm_ops)
  WHERE full_name IS NOT NULL;

CREATE OR REPLACE FUNCTION public.search_profiles(
  search_query text,
  result_limit integer DEFAULT 10
)
RETURNS TABLE (
  id uuid,
  full_name text,
  username text,
  avatar_url text,
  headline text,
  email text,
  phone text,
  favorite_nonprofit_ein text,
  favorite_nonprofit_name text,
  favorite_nonprofit_website text,
  favorite_nonprofit_headline text
)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  WITH q AS (
    SELECT lower(trim(search_query)) AS needle
  )
  SELECT
    p.id,
    p.full_name,
    p.username,
    p.avatar_url,
    p.headline,
    p.email,
    p.phone,
    p.favorite_nonprofit_ein,
    p.favorite_nonprofit_name,
    p.favorite_nonprofit_website,
    p.favorite_nonprofit_headline
  FROM public.profiles p, q
  WHERE length(q.needle) >= 2
    AND (
      lower(p.username) LIKE q.needle || '%'
      OR lower(coalesce(p.full_name, '')) LIKE q.needle || '%'
      OR p.username ILIKE '%' || q.needle || '%'
      OR coalesce(p.full_name, '') ILIKE '%' || q.needle || '%'
    )
  ORDER BY
    CASE
      WHEN lower(p.username) = q.needle THEN 0
      WHEN lower(p.username) LIKE q.needle || '%' THEN 1
      WHEN lower(coalesce(p.full_name, '')) LIKE q.needle || '%' THEN 2
      ELSE 3
    END,
    p.full_name ASC NULLS LAST,
    p.username ASC
  LIMIT GREATEST(1, LEAST(coalesce(result_limit, 10), 25));
$$;

GRANT EXECUTE ON FUNCTION public.search_profiles(text, integer) TO anon, authenticated;
