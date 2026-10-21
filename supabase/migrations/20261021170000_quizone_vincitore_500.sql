-- QuizOne: il vincitore del giorno prende 500 crediti invece di 1.000 (21/10/2026, committente).
CREATE OR REPLACE FUNCTION private.quiz_premia_giorno(p_league_id bigint, p_giorno date)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_da timestamptz := p_giorno::timestamp at time zone 'Europe/Rome'; v_a timestamptz := (p_giorno + 1)::timestamp at time zone 'Europe/Rome';
  v_id bigint; w record;
begin
  perform pg_advisory_xact_lock(hashtext('quizone_giorno'), p_league_id::int);
  if exists (select 1 from public.quizzone_vincitori where league_id = p_league_id and giorno = p_giorno) then return; end if;
  for v_id in select id from public.quizzone_domande where league_id = p_league_id and ora >= v_da and ora < v_a and not regolata loop
    perform private.quiz_regola(v_id);
  end loop;
  for w in
    with c as (
      select g.team_id, g.user_id, count(*) filter (where g.corretta) as giuste, sum(g.vinto) as vinto
        from public.quizzone_giocate g join public.quizzone_domande x on x.id = g.domanda_id
       where g.league_id = p_league_id and x.ora >= v_da and x.ora < v_a and x.regolata
       group by g.team_id, g.user_id)
    select * from c where giuste > 0
       and (giuste, vinto) = (select giuste, vinto from c order by giuste desc, vinto desc limit 1)
  loop
    insert into public.quizzone_vincitori (league_id, giorno, team_id, user_id, giuste, crediti)
    values (p_league_id, p_giorno, w.team_id, w.user_id, w.giuste, 500);
    update public.casino_saldi set crediti = crediti + 500, totale_vinto = totale_vinto + 500, aggiornato_il = now()
     where league_id = p_league_id and user_id = w.user_id;
    insert into public.notifications (user_id, league_id, tipo, titolo, corpo, dati)
    values (w.user_id, p_league_id, 'sistema', 'QuizOne: hai vinto la giornata!',
            format('Primo in classifica oggi con %s risposte giuste: +500 crediti.', w.giuste), '{"view": "quizzone"}'::jsonb);
  end loop;
  -- giornata senza vincitori: si segna comunque come chiusa (riga senza squadra)
  if not exists (select 1 from public.quizzone_vincitori where league_id = p_league_id and giorno = p_giorno) then
    insert into public.quizzone_vincitori (league_id, giorno, team_id, user_id, giuste, crediti) values (p_league_id, p_giorno, null, null, 0, 0);
  end if;
end $function$;
