-- Il Quizzone si chiama QuizOne (con una z sola, come SlotOne, AviatOne, CrazyOne): nome nelle notifiche.
CREATE OR REPLACE FUNCTION private.quizzone_cron()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare l record; v_ora timestamptz := date_trunc('hour', now()) + interval '1 hour'; d public.quizzone_domande; v_h int;
begin
  if now() < v_ora - interval '70 seconds' then return; end if;
  v_h := extract(hour from v_ora at time zone 'Europe/Rome');
  for l in select id from public.leagues where quizzone loop
    continue when exists (select 1 from public.quizzone_domande where league_id = l.id and ora = v_ora);
    d := private.quiz_genera(l.id, v_ora);
    if d.id is not null and v_h between 9 and 23 then
      insert into public.notifications (user_id, league_id, tipo, titolo, corpo, dati)
      select t.user_id, l.id, 'sistema', 'QuizOne', format('Tra un minuto la domanda delle %s! Apri QuizOne: avrai 10 secondi per entrare.', v_h || ':00'), '{"view": "quizzone"}'::jsonb
        from public.teams t where t.league_id = l.id and t.attiva and t.user_id is not null;
    end if;
  end loop;
end $function$;
