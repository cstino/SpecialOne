-- Crediti del casino' azzerati quando la lega passa alla stagione nuova (decisione del committente, 8/11/2026: in
-- Serie F, appena entrata nella Season 3, erano rimasti i crediti della Season 2). Si azzerano anche gli arretrati
-- della ricarica giornaliera: 'settimana' passa a oggi, quindi i prossimi 1.000 arrivano alle 22:10. Restano bustine
-- e giri gratis gia' vinti e le statistiche (giri, vincita massima, totale vinto).

create or replace function private.casino_azzera_nuova_stagione()
 returns trigger
 language plpgsql
 security definer
 set search_path to ''
as $function$
begin
  update public.casino_saldi
     set crediti = 0, settimana = private.casino_settimana(), aggiornato_il = now()
   where league_id = new.id;
  return null;
end $function$;

drop trigger if exists leagues_azzera_crediti_casino on public.leagues;
create trigger leagues_azzera_crediti_casino
  after update of stagione_corrente on public.leagues
  for each row when (new.stagione_corrente > old.stagione_corrente)
  execute function private.casino_azzera_nuova_stagione();

-- Serie F e' gia' entrata nella Season 3 oggi: azzeramento a mano.
update public.casino_saldi
   set crediti = 0, settimana = private.casino_settimana(), aggiornato_il = now()
 where league_id = 63;
