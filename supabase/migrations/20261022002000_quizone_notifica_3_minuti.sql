-- QuizOne: notifica (e preparazione della domanda) 3 minuti prima invece di 1 (22/10/2026, committente).
CREATE OR REPLACE FUNCTION private.quizzone_cron()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare l record; v_ora timestamptz := date_trunc('hour', now()) + interval '1 hour'; d public.quizzone_domande; v_h int;
  v_roma timestamp := now() at time zone 'Europe/Rome';
begin
  if v_roma::time >= time '22:30' then
    for l in select id from public.leagues where quizzone loop
      continue when exists (select 1 from public.quizzone_vincitori where league_id = l.id and giorno = v_roma::date);
      continue when not exists (select 1 from public.quizzone_domande where league_id = l.id
                                 and ora >= v_roma::date::timestamp at time zone 'Europe/Rome');
      perform private.quiz_premia_giorno(l.id, v_roma::date);
    end loop;
  end if;
  if now() < v_ora - interval '190 seconds' then return; end if;
  v_h := extract(hour from v_ora at time zone 'Europe/Rome');
  for l in select id from public.leagues where quizzone loop
    continue when exists (select 1 from public.quizzone_domande where league_id = l.id and ora = v_ora);
    d := private.quiz_genera(l.id, v_ora);
    if d.id is not null and v_h between 8 and 22 then
      insert into public.notifications (user_id, league_id, tipo, titolo, corpo, dati)
      select t.user_id, l.id, 'sistema', 'QuizOne', format('Tra 3 minuti la domanda delle %s! Apri QuizOne: avrai 10 secondi per entrare.', v_h || ':00'), '{"view": "quizzone"}'::jsonb
        from public.teams t where t.league_id = l.id and t.attiva and t.user_id is not null;
    end if;
  end loop;
end $function$;
