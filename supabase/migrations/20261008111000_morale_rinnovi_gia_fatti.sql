-- La spinta di morale del rinnovo, data una volta ai giocatori di Serie F gia' rinnovati in questa stagione
-- (stagione 2, prima che la regola esistesse). Scelta del committente, 8 ottobre 2026.
select private.spinta_morale_rinnovo(pi.id)
from public.player_instances pi
where pi.league_id = 63 and pi.rinnovo_stagione = 2 and pi.team_id is not null;
