-- QuizOne (24/10/2026, committente):
-- 1) le notifiche "Tra 3 minuti la domanda..." si cancellano da sole 4 minuti dopo l'invio, a domanda passata non servono piu';
-- 2) chi non e' entrato nei primi 10 secondi ma apre la domanda in tempo puo' rispondere lo stesso: gioca gratis
--    (puntata 0), come se "gratis" fosse la scelta di default. Le puntate restano possibili solo nei primi 10 secondi.
-- Funzioni riscritte dalla definizione viva.

CREATE OR REPLACE FUNCTION public.quizzone_rispondi(p_league_id bigint, p_risposta integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_utente uuid := (select auth.uid()); d public.quizzone_domande; v_ora timestamptz := clock_timestamp(); v public.casino_saldi;
begin
  perform private.quiz_attivo(p_league_id);
  select * into d from public.quizzone_domande where league_id = p_league_id and ora <= v_ora and ora > v_ora - interval '1 hour' order by ora desc limit 1;
  if d.id is null or v_ora < d.ora + interval '10 seconds' or v_ora >= d.ora + interval '26 seconds' then
    raise exception using errcode = '55000', message = 'Tempo scaduto per rispondere.';
  end if;
  if p_risposta is null or p_risposta not between 0 and 3 then raise exception using errcode = '22023', message = 'Risposta non valida.'; end if;
  -- Non e' entrato nei primi 10 secondi: gioca gratis (puntata 0). L'indice unico (domanda, utente) regge i doppi tocchi.
  if not exists (select 1 from public.quizzone_giocate where domanda_id = d.id and user_id = v_utente) then
    v := private.casino_saldo(p_league_id, v_utente);
    insert into public.quizzone_giocate (domanda_id, league_id, user_id, team_id, puntata) values (d.id, p_league_id, v_utente, v.team_id, 0)
    on conflict (domanda_id, user_id) do nothing;
  end if;
  update public.quizzone_giocate set risposta = p_risposta, risposta_il = v_ora where domanda_id = d.id and user_id = v_utente and risposta is null;
  if not found then raise exception using errcode = '55000', message = 'Non sei entrato in questa domanda, o hai già risposto.'; end if;
  return public.quizzone_stato(p_league_id);
end $function$;

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

-- Pulizia una tantum degli avvisi QuizOne gia' passati.
delete from public.notifications where titolo = 'QuizOne' and dati ->> 'view' = 'quizzone' and creata_il < now() - interval '4 minutes';
