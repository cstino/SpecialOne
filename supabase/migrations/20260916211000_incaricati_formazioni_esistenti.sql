-- ============================================================
--  GLI INCARICHI SULLE FORMAZIONI GIA' SALVATE
--
--  Le formazioni in attesa della prossima giornata sono state salvate prima
--  che gli incarichi esistessero: senza questo riempimento partirebbero con i
--  tre campi vuoti, e in partita si tornerebbe a dedurre l'incaricato dal
--  migliore in campo — che e' il comportamento che stiamo sostituendo.
--
--  Solo le giornate ANCORA DA GIOCARE. Le formazioni passate restano com'erano:
--  sono il verbale di una partita gia' avvenuta, non una scelta da aggiornare.
-- ============================================================

do $$
declare v_riga record;
begin
  for v_riga in
    select l.team_id, l.giornata
    from public.lineups l
    join public.leagues lg on lg.id = l.league_id
    where l.giornata >= coalesce(
      (select min(f.giornata) from public.fixtures f
       where f.league_id = l.league_id and f.stato = 'programmata'), 0)
  loop
    perform private.sistema_incaricati(v_riga.team_id, v_riga.giornata);
  end loop;
end $$;
