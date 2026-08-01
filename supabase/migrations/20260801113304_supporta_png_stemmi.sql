-- Safari/iOS puo restituire PNG quando canvas.toBlob non supporta WebP.
-- Accettiamo entrambi i formati mantenendo invariati proprietario e limite di 512 KB.
update storage.buckets
set allowed_mime_types = array['image/webp', 'image/png']::text[]
where id = 'team-crests';

drop policy if exists team_crests_upload_proprio on storage.objects;
create policy team_crests_upload_proprio
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'team-crests'
  and (storage.foldername(name))[1] = (select auth.uid())::text
  and lower(storage.extension(name)) in ('webp', 'png')
);

create or replace function private.stemma_valido(
  p_stemma_url text,
  p_user_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    p_stemma_url = any (array[
      'preset:scudo',
      'preset:diagonale',
      'preset:torre',
      'preset:stella',
      'preset:quartieri',
      'preset:corona'
    ]::text[])
    or (
      p_stemma_url ~ (
        '^' || p_user_id::text ||
        '/[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.(webp|png)$'
      )
      and exists (
        select 1
        from storage.objects o
        where o.bucket_id = 'team-crests'
          and o.name = p_stemma_url
          and o.owner_id = p_user_id::text
          and o.metadata ->> 'mimetype' in ('image/webp', 'image/png')
          and (o.metadata ->> 'size')::bigint <= 524288
      )
    );
$$;

revoke all on function private.stemma_valido(text, uuid) from public, anon, authenticated;
grant execute on function private.stemma_valido(text, uuid) to service_role;
