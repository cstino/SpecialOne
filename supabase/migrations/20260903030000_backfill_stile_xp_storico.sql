-- ============================================================
--  BACKFILL STORICO DI stile_xp.
--
--  stile_xp e' nata oggi (20260903020000_ftsg_stile_xp.sql): le leghe gia'
--  in corso avevano gia' giocato delle giornate PRIMA che la tabella
--  esistesse, quindi per loro partiva a 0 anche se lo stile scelto era
--  sempre lo stesso da inizio stagione — segnalato dall'utente su Serie F
--  (modulo 27% dopo 4 giornate di 4-4-2, stile 0% dopo le stesse 4
--  giornate di contropiede: nessun bug, formation_xp esisteva gia' da
--  Fase 1, stile_xp no).
--
--  Lo storico pero' non e' perso: public.matches.stile_home/stile_away
--  registra lo stile davvero giocato in OGNI partita gia' simulata (anche
--  playoff/playout), fin da 20260805110000_stile_di_gioco.sql. Si
--  ricostruisce da li' invece di far ripartire tutti da zero.
--
--  SET assoluto (non incremento) sul conflitto: idempotente, ricalcola
--  sempre il conteggio vero dallo storico immutabile — sicuro anche se
--  rilanciata per errore o se gira dopo che qualche partita nuova ha gia'
--  scritto la propria riga.
-- ============================================================

insert into public.stile_xp (team_id, league_id, stile, partite_giocate)
select team_id, league_id, stile, count(*)::smallint
from (
  select f.home_team_id as team_id, f.league_id, m.stile_home as stile
  from public.matches m
  join public.fixtures f on f.id = m.fixture_id
  union all
  select f.away_team_id as team_id, f.league_id, m.stile_away as stile
  from public.matches m
  join public.fixtures f on f.id = m.fixture_id
) storico
group by team_id, league_id, stile
on conflict (team_id, stile) do update set
  partite_giocate = excluded.partite_giocate,
  aggiornata_il = now();
