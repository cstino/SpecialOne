-- QuizOne, premi nuovi (21/10/2026, richiesta del committente):
-- 1) risposta giusta = 250 crediti dalle domande del 22/10/2026 (prima 100), piu' il doppio della puntata come sempre;
-- 2) vincitore del giorno: alle 22:30 (dopo l'ultima domanda delle 22:00) il primo della classifica di oggi
--    (risposte giuste, a parita' crediti vinti) riceve 1.000 crediti. A parita' piena li ricevono tutti i primi.

-- Premio per una risposta giusta, in base al giorno della domanda (le domande gia' giocate non cambiano).
create or replace function private.quiz_premio(p_ora timestamptz)
returns integer language sql immutable set search_path = '' as $$
  select case when p_ora >= timestamp '2026-10-22 00:00' at time zone 'Europe/Rome' then 250 else 100 end
$$;

create table public.quizzone_vincitori (
  id bigint generated always as identity primary key,
  league_id bigint not null references public.leagues (id) on delete cascade,
  giorno date not null,
  team_id bigint references public.teams (id) on delete set null,
  user_id uuid,
  giuste integer not null,
  crediti integer not null,
  creata_il timestamptz not null default now()
);
create unique index quizzone_vincitori_giorno on public.quizzone_vincitori (league_id, giorno, team_id);
alter table public.quizzone_vincitori enable row level security;
create policy quizzone_vincitori_lettura on public.quizzone_vincitori for select to authenticated
  using (exists (select 1 from public.teams t where t.league_id = quizzone_vincitori.league_id and t.user_id = (select auth.uid())));
grant select on public.quizzone_vincitori to anon;
grant select, insert, update, delete on public.quizzone_vincitori to authenticated, service_role;

-- Regolamento: identico a prima, solo il premio fisso passa da quiz_premio.
create or replace function private.quiz_regola(p_domanda bigint)
 returns void language plpgsql security definer set search_path to ''
as $function$
declare d public.quizzone_domande; q record; v_ok boolean; v_vinto bigint;
begin
  select * into d from public.quizzone_domande where id = p_domanda for update;
  if d.regolata or now() < d.ora + interval '26 seconds' then return; end if;
  for q in select * from public.quizzone_giocate where domanda_id = d.id for update loop
    v_ok := q.risposta is not null and q.risposta = d.corretta;
    v_vinto := case when v_ok then private.quiz_premio(d.ora) + 2 * q.puntata else 0 end;
    update public.quizzone_giocate set corretta = v_ok, vinto = v_vinto where id = q.id;
    if v_vinto > 0 then
      update public.casino_saldi set crediti = crediti + v_vinto, totale_vinto = totale_vinto + v_vinto, aggiornato_il = now()
       where league_id = q.league_id and user_id = q.user_id;
    end if;
  end loop;
  update public.quizzone_domande set regolata = true where id = d.id;
end $function$;

-- Vincitore del giorno di una lega: regola le domande rimaste aperte, poi paga i primi. Idempotente.
create or replace function private.quiz_premia_giorno(p_league_id bigint, p_giorno date)
 returns void language plpgsql security definer set search_path to ''
as $function$
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
    values (p_league_id, p_giorno, w.team_id, w.user_id, w.giuste, 1000);
    update public.casino_saldi set crediti = crediti + 1000, totale_vinto = totale_vinto + 1000, aggiornato_il = now()
     where league_id = p_league_id and user_id = w.user_id;
    insert into public.notifications (user_id, league_id, tipo, titolo, corpo, dati)
    values (w.user_id, p_league_id, 'sistema', 'QuizOne: hai vinto la giornata!',
            format('Primo in classifica oggi con %s risposte giuste: +1.000 crediti.', w.giuste), '{"view": "quizzone"}'::jsonb);
  end loop;
  -- giornata senza vincitori: si segna comunque come chiusa (riga senza squadra)
  if not exists (select 1 from public.quizzone_vincitori where league_id = p_league_id and giorno = p_giorno) then
    insert into public.quizzone_vincitori (league_id, giorno, team_id, user_id, giuste, crediti) values (p_league_id, p_giorno, null, null, 0, 0);
  end if;
end $function$;

-- Cron: in piu' rispetto a prima, dalle 22:30 premia il vincitore del giorno (una volta per lega).
create or replace function private.quizzone_cron()
 returns void language plpgsql security definer set search_path to ''
as $function$
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
  if now() < v_ora - interval '70 seconds' then return; end if;
  v_h := extract(hour from v_ora at time zone 'Europe/Rome');
  for l in select id from public.leagues where quizzone loop
    continue when exists (select 1 from public.quizzone_domande where league_id = l.id and ora = v_ora);
    d := private.quiz_genera(l.id, v_ora);
    if d.id is not null and v_h between 8 and 22 then
      insert into public.notifications (user_id, league_id, tipo, titolo, corpo, dati)
      select t.user_id, l.id, 'sistema', 'QuizOne', format('Tra un minuto la domanda delle %s! Apri QuizOne: avrai 10 secondi per entrare.', v_h || ':00'), '{"view": "quizzone"}'::jsonb
        from public.teams t where t.league_id = l.id and t.attiva and t.user_id is not null;
    end if;
  end loop;
end $function$;

-- Stato: aggiunge 'premio' (premio fisso della domanda in corso o della prossima) e 'vincitori' (premiati di oggi).
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
    'premio', private.quiz_premio(coalesce(d.ora, least(v_inizio + interval '1 hour', coalesce((select min(x.ora) from public.quizzone_domande x where x.league_id = p_league_id and x.ora > v_ora), v_inizio + interval '1 hour')))),
    'vincitori', coalesce((select jsonb_agg(jsonb_build_object('team_id', w.team_id, 'giuste', w.giuste, 'crediti', w.crediti)) from public.quizzone_vincitori w
                           where w.league_id = p_league_id and w.giorno = (v_ora at time zone 'Europe/Rome')::date and w.team_id is not null), '[]'::jsonb),
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
