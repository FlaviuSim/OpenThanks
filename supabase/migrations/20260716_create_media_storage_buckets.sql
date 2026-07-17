-- Creates Supabase Storage buckets used by the iOS app for profile photos
-- and appreciation media. The web app currently uses Vercel Blob via
-- /api/file; these buckets unlock native uploads.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('avatars', 'avatars', true, 5242880, array['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif']),
  ('gratitude-media', 'gratitude-media', true, 20971520, array['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif', 'video/mp4', 'video/quicktime'])
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

create policy "Public read avatars"
  on storage.objects for select
  using (bucket_id = 'avatars');

create policy "Authenticated upload own avatars"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "Authenticated update own avatars"
  on storage.objects for update to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  )
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "Authenticated delete own avatars"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "Public read gratitude media"
  on storage.objects for select
  using (bucket_id = 'gratitude-media');

create policy "Authenticated upload own gratitude media"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'gratitude-media'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "Authenticated update own gratitude media"
  on storage.objects for update to authenticated
  using (
    bucket_id = 'gratitude-media'
    and (storage.foldername(name))[1] = auth.uid()::text
  )
  with check (
    bucket_id = 'gratitude-media'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "Authenticated delete own gratitude media"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'gratitude-media'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
