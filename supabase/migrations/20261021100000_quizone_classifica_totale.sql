-- QuizOne: classifica totale (da sempre) accanto a quella di oggi; il win rate lo calcola la pagina da questa.
CREATE OR REPLACE FUNCTION public.quizzone_stato(p_league_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_utente uuid := (select auth.uid()); v_ora timestamptz := clock_timestamp(); v_inizio timestamptz := date_trunc('hour', clock_timestamp());
  d public.quizzone_domande; v public.casino_saldi; q public.quizzone_giocate; v_d jsonb; v_prec bigint;
begin
  perform private.quiz_attivo(p_league_id);
  v := private.casino_saldo(p_league_id, v_utente);
  -- se il cron non l'ha preparata, la domanda dell'ora si genera adesso (solo finche' si puo' ancora entrare)
  if v_ora < v_inizio + interval '10 seconds' and not exists (select 1 from public.quizzone_domande where league_id = p_league_id and ora = v_inizio) then
    perform private.quiz_genera(p_league_id, v_inizio);
  end if;
  for v_prec in select id from public.quizzone_domande where league_id = p_league_id and not regolata and ora + interval '26 seconds' <= v_ora loop
    perform private.quiz_regola(v_prec);
  end loop;
  select * into d from public.quizzone_domande where league_id = p_league_id and ora <= v_ora and ora > v_ora - interval '1 hour' order by ora desc limit 1;
  if d.id is not null then
    select * into q from public.quizzone_giocate where domanda_id = d.id and user_id = v_utente;
    v_d := jsonb_build_object('id', d.id, 'ora', floor(extract(epoch from d.ora) * 1000), 'regolata', d.regolata,
      'testo', case when v_ora >= d.ora + interval '10 seconds' then d.testo end,
      'risposte', case when v_ora >= d.ora + interval '10 seconds' then d.risposte end,
      'corretta', case when d.regolata then d.corretta end,
      'giocatori', (select count(*) from public.quizzone_giocate where domanda_id = d.id),
      'esiti', case when d.regolata then coalesce((select jsonb_agg(jsonb_build_object('team_id', g.team_id, 'corretta', g.corretta, 'puntata', g.puntata, 'vinto', g.vinto) order by g.corretta desc nulls last, g.risposta_il nulls last)
                                                   from public.quizzone_giocate g where g.domanda_id = d.id), '[]'::jsonb) end);
  end if;
  return jsonb_build_object('adesso', floor(extract(epoch from v_ora) * 1000), 'crediti', v.crediti,
    'prossima', floor(extract(epoch from least(v_inizio + interval '1 hour', coalesce((select min(x.ora) from public.quizzone_domande x where x.league_id = p_league_id and x.ora > v_ora), 'infinity'))) * 1000),
    'domanda', v_d,
    'mia', case when q.id is not null then jsonb_build_object('puntata', q.puntata, 'risposta', q.risposta, 'corretta', q.corretta, 'vinto', q.vinto) end,
    'oggi', coalesce((select jsonb_agg(jsonb_build_object('ora', floor(extract(epoch from x.ora) * 1000), 'testo', x.testo, 'risposta', x.risposte ->> x.corretta) order by x.ora desc)
                      from public.quizzone_domande x where x.league_id = p_league_id and x.regolata
                       and x.ora >= date_trunc('day', v_ora at time zone 'Europe/Rome') at time zone 'Europe/Rome'), '[]'::jsonb),
    'classifica_totale', coalesce((select jsonb_agg(c order by (c ->> 'giuste')::int desc, (c ->> 'vinto')::bigint desc) from (
                      select jsonb_build_object('team_id', g.team_id, 'giuste', count(*) filter (where g.corretta), 'giocate', count(*), 'vinto', sum(g.vinto)) c
                        from public.quizzone_giocate g join public.quizzone_domande x on x.id = g.domanda_id
                       where g.league_id = p_league_id and x.regolata group by g.team_id) s), '[]'::jsonb),
    'classifica', coalesce((select jsonb_agg(c order by (c ->> 'giuste')::int desc, (c ->> 'vinto')::bigint desc) from (
                      select jsonb_build_object('team_id', g.team_id, 'giuste', count(*) filter (where g.corretta), 'giocate', count(*), 'vinto', sum(g.vinto)) c
                        from public.quizzone_giocate g join public.quizzone_domande x on x.id = g.domanda_id
                       where g.league_id = p_league_id and x.ora >= date_trunc('day', v_ora at time zone 'Europe/Rome') at time zone 'Europe/Rome'
                       group by g.team_id) s), '[]'::jsonb));
end $function$;
