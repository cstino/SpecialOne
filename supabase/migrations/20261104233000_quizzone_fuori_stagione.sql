-- QuizOne fermo fuori stagione (4/11/2026): a campionato concluso, in off-season e prima della prima giornata
-- della stagione nuova non ci sono partite recenti su cui fare domande. Il quiz riparte da solo dopo la prima
-- giornata simulata della stagione successiva. Il premio del giorno resta com'era (premia solo giorni con domande).

create or replace function private.quizzone_in_corso(p_league_id bigint)
 returns boolean
 language sql
 stable security definer
 set search_path to ''
as $function$
  select exists (
    select 1 from public.leagues l
    join public.seasons s on s.league_id = l.id and s.stato = 'in_corso'
    where l.id = p_league_id and l.stato = 'stagione' and l.fase_carriera = 'normale'
      and exists (select 1 from public.fixtures f where f.season_id = s.id and f.stato = 'simulata')
  )
$function$;
revoke all on function private.quizzone_in_corso(bigint) from public, anon, authenticated;

create or replace function public.quizzone_attivo(p_league_id bigint)
 returns boolean
 language sql
 stable security definer
 set search_path to ''
as $function$
  select coalesce((select l.quizzone from public.leagues l where l.id = p_league_id), false)
    and (select private.e_membro(p_league_id))
    and (select private.quizzone_in_corso(p_league_id))
$function$;

CREATE OR REPLACE FUNCTION private.quizzone_cron()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare l record; v_ora timestamptz := date_trunc('hour', now()) + interval '1 hour'; d public.quizzone_domande; v_h int;
  v_roma timestamp := now() at time zone 'Europe/Rome';
begin
  -- Le notifiche di avviso non servono a domanda passata: via dopo 4 minuti (la domanda e' alle :00, si chiude alle :00:26).
  delete from public.notifications where titolo = 'QuizOne' and dati ->> 'view' = 'quizzone' and creata_il < now() - interval '4 minutes';
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
  -- Domande nuove solo a stagione in corso con almeno una giornata giocata (private.quizzone_in_corso).
  for l in select id from public.leagues where quizzone and private.quizzone_in_corso(id) loop
    continue when exists (select 1 from public.quizzone_domande where league_id = l.id and ora = v_ora);
    d := private.quiz_genera(l.id, v_ora);
    if d.id is not null and v_h between 8 and 22 then
      insert into public.notifications (user_id, league_id, tipo, titolo, corpo, dati)
      select t.user_id, l.id, 'sistema', 'QuizOne', format('Tra 3 minuti la domanda delle %s! Apri QuizOne: avrai 10 secondi per entrare.', v_h || ':00'), '{"view": "quizzone"}'::jsonb
        from public.teams t where t.league_id = l.id and t.attiva and t.user_id is not null;
    end if;
  end loop;
end $function$;
