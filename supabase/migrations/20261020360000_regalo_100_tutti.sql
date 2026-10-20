-- Regalo del committente: 100 crediti del casino' a tutti i giocatori delle leghe con il casino' (Serie F e LegaBot).
update public.casino_saldi s set crediti = crediti + 100, aggiornato_il = now()
 where s.league_id in (62, 63)
   and exists (select 1 from public.teams t where t.league_id = s.league_id and t.user_id = s.user_id and t.attiva);
