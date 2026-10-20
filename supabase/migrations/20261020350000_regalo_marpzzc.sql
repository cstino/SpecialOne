-- Regalo del committente: 100 crediti del casino' all'allenatore della M'ARPZZC FC (Serie F, squadra 277).
update public.casino_saldi s set crediti = crediti + 100, aggiornato_il = now()
  from public.teams t where t.id = 277 and s.league_id = t.league_id and s.user_id = t.user_id;
