-- Uno scambio sostituisce con 0 (slot vuoto) i titolari ceduti (20261008170000): con due o piu' titolari ceduti
-- la distinta ha piu' zeri e il vincolo lineups_giocatori_unici scattava, bloccando l'accettazione dello scambio.
-- Lo 0 non e' mai un giocatore: il controllo dei doppioni lo ignora.
create or replace function private.senza_duplicati(a bigint[])
 returns boolean
 language sql
 immutable parallel safe
 set search_path to ''
as $function$
  select a is null
      or cardinality(array_remove(a, 0::bigint)) = (select count(distinct x) from unnest(a) as x where x <> 0);
$function$;
