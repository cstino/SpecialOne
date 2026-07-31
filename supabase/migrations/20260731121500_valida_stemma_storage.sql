-- Lo stemma custom non è una stringa fiduciaria: deve esistere nel bucket,
-- appartenere all'utente e rispettare MIME/peso anche quando la RPC viene
-- chiamata fuori dal client ufficiale.
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
        '/[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.webp$'
      )
      and exists (
        select 1
        from storage.objects o
        where o.bucket_id = 'team-crests'
          and o.name = p_stemma_url
          and o.owner_id = p_user_id::text
          and o.metadata ->> 'mimetype' = 'image/webp'
          and (o.metadata ->> 'size')::bigint <= 524288
      )
    );
$$;

revoke all on function private.stemma_valido(text, uuid) from public, anon, authenticated;
grant execute on function private.stemma_valido(text, uuid) to service_role;
