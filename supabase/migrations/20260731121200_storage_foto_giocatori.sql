-- ============================================================
--  STORAGE FOTO GIOCATORI  (decisioni-fase1 §3)
--  Bucket privato: nessun hotlink e nessun accesso anonimo.
-- ============================================================

insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
) values (
  'player-photos',
  'player-photos',
  false,
  262144,
  array['image/webp']::text[]
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- Consente a un utente autenticato di scaricare un percorso noto, ma non di
-- enumerare il bucket. Upload e sostituzioni restano operazioni amministrative.
create policy player_photos_download
on storage.objects
for select
to authenticated
using (
  bucket_id = 'player-photos'
  and storage.allow_any_operation(
    array['object.get_authenticated_info', 'object.get_authenticated']
  )
);

comment on column public.players.foto_url is
  'Percorso nel bucket privato player-photos, mai URL del sito sorgente.';
