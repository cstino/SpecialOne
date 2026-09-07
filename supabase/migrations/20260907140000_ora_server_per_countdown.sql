-- ============================================================
--  I COUNTDOWN USAVANO L'OROLOGIO DEL TELEFONO.
--
--  Terza e ultima delle cause dell'imprecisione segnalata dall'utente il
--  7 settembre 2026 (le prime due: deriva cumulativa del calendario in
--  20260907120000, cron sfalsati in 20260907130000).
--
--  src/lib/countdown.ts calcolava il tempo mancante con Date.now(), cioe'
--  l'orologio del dispositivo. Su un telefono avanti o indietro di
--  qualche minuto — cosa comunissima, soprattutto se il fuso o la
--  sincronizzazione automatica sono disattivati — il countdown mostrava
--  un numero sbagliato, e due partecipanti allo stesso momento vedevano
--  mancare tempi diversi allo stesso evento. Il server, invece, ha sempre
--  fatto la cosa giusta: rifiuta le offerte in base a now(), non a quello
--  che dice il client.
--
--  Questa funzione espone l'ora del server perche' il client possa
--  calcolare il proprio scarto e correggerlo. Non e' un dato sensibile e
--  non tocca nulla: e' la stessa now() che qualunque risposta HTTP
--  espone gia' nell'header Date.
-- ============================================================

begin;

create or replace function public.ora_server()
returns timestamptz
language sql
stable
set search_path = ''
as $$
  select now();
$$;

comment on function public.ora_server() is
  'Ora del server, per sincronizzare i countdown del client: senza, il '
  'conto alla rovescia dipende dall''orologio del telefono e ogni '
  'partecipante vede un numero diverso.';

grant execute on function public.ora_server() to authenticated, anon;

commit;
