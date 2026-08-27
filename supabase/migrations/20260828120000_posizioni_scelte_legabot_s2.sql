-- Assegna le posizioni delle scelte ON-Season 2 / OFF-Season 2 di LegaBot.
--
-- LegaBot ha 8 squadre, tutte entrate in stagione 1 (nessuna new entrant,
-- verificato su teams.entrata_stagione prima di questa migrazione) e la
-- stagione 1 non ha giocato nessun playoff (il sistema Title/Draft Playoff
-- non esisteva ancora). Non si applica ne' l'ordine da Title/Draft Playoff
-- (§2, nessun tabellone giocato) ne' la regola ibrida di transizione di
-- Real Fampionato (§2.1, pensata per le squadre "nuove entranti" — qui non
-- ce ne sono). Resta solo la classifica finale della stagione 1, invertita:
-- l'ultima classificata ha piu' bisogno di rinforzarsi, quindi sceglie
-- prima — stesso principio del vecchio playout e del Draft Playoff.
--
-- posizione = 9 - posizione_classifica (8a in classifica -> 1a scelta,
-- 1a in classifica -> 8a scelta, l'unica formula lineare che soddisfa
-- "l'ultima sceglie prima" su 8 squadre).

update public.scelte_draft sd
set posizione = 9 - st.posizione,
    stato = 'determinata',
    aggiornata_il = now()
from public.standings st
join public.seasons se on se.id = st.season_id
where se.league_id = 62 and se.numero = 1
  and sd.league_id = 62 and sd.stagione = 2
  and sd.team_origine_id = st.team_id
  and sd.posizione is null;
