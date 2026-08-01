-- ============================================================
--  CORREZIONE LETTURA FOTO GIOCATORI
--
--  La policy originale limitava l'accesso alle sole operazioni
--  'object.get_authenticated_info' e 'object.get_authenticated'. La creazione
--  di una URL firmata e' un'operazione diversa e restava quindi negata.
--
--  Il difetto non si era mai manifestato perche' fino ad ora `foto_url` era
--  nullo per tutti i giocatori: il client non aveva mai chiesto una firma.
--  Appena le foto sono state caricate, ogni ritratto e' sparito.
--
--  Allineiamo la policy a quella degli stemmi (`team_crests_lettura`), che usa
--  il solo vincolo sul bucket e funziona con `createSignedUrl`.
--
--  Conseguenza accettata: un partecipante autenticato puo' anche elencare il
--  bucket. Le foto sono il catalogo giocatori condiviso, gia' visibile a tutti
--  durante il draft, quindi non c'e' nulla da proteggere fra i partecipanti.
--  Il bucket resta privato verso l'esterno: nessun accesso anonimo.
-- ============================================================

drop policy if exists player_photos_download on storage.objects;

create policy player_photos_download
on storage.objects
for select
to authenticated
using (bucket_id = 'player-photos');
