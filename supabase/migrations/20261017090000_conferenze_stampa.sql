-- ============================================================
--  CONFERENZE STAMPA POST PARTITA — fase 1 (docs/decisioni-conferenze-stampa.md)
--  Prova solo in LegaBot (lega 62), dietro l'interruttore leagues.conferenze_stampa.
--
--  Dopo la simulazione, per ogni allenatore umano nascono 1-2 domande sulla
--  sua partita (le scrive un'AI dalla Edge Function conferenza-stampa). Chi
--  risponde riceve una valutazione da -3 a +3 che sposta il morale della rosa,
--  e quello dei giocatori citati. Chi non risponde: effetto zero.
--
--  Il morale si scrive direttamente in player_instances.morale: il ricalcolo
--  a quarti di stagione (applica_morale_checkpoint) SOMMA le sue variazioni al
--  morale esistente, non lo ricostruisce, quindi l'effetto non si perde (come
--  la spinta del rinnovo, private.spinta_morale_rinnovo).
-- ============================================================

begin;

alter table public.leagues
  add column if not exists conferenze_stampa boolean not null default false;

update public.leagues set conferenze_stampa = true where id = 62;

-- La scadenza: il giorno dopo alle 22:30 di Roma, prima della simulazione delle 23:00.
create or replace function private.scadenza_conferenza(p_da timestamptz)
returns timestamptz
language sql stable set search_path = ''
as $$
  select (((p_da at time zone 'Europe/Rome')::date + 1) + time '22:30') at time zone 'Europe/Rome'
$$;

create table public.conferenze_domande (
  id              bigint generated always as identity primary key,
  league_id       bigint not null references public.leagues(id) on delete cascade,
  match_id        bigint not null references public.matches(id) on delete cascade,
  team_id         bigint not null references public.teams(id) on delete cascade,
  ordine          smallint not null check (ordine between 1 and 3),
  giornalista     text not null check (char_length(giornalista) between 1 and 80),
  domanda         text not null check (char_length(domanda) between 1 and 600),
  creata_il       timestamptz not null default now(),
  scade_il        timestamptz not null default private.scadenza_conferenza(now()),
  risposta        text check (risposta is null or char_length(risposta) between 1 and 1200),
  risposta_il     timestamptz,
  -- La valutazione: voto gia' limitato dal server, la reazione della sala
  -- stampa da mostrare, l'effetto medio sul morale e il dettaglio completo.
  voto            numeric(2,1) check (voto is null or voto between -3 and 3),
  reazione        text,
  effetto_morale  numeric(4,1),
  valutazione     jsonb,
  unique (match_id, team_id, ordine)
);

create index conferenze_domande_team_idx on public.conferenze_domande (team_id, creata_il desc);

alter table public.conferenze_domande enable row level security;

-- Ognuno vede solo le domande della propria squadra (fase 3: il feed renderà
-- pubbliche le risposte). Scritture solo dalla Edge Function (service role).
create policy conferenze_domande_lettura on public.conferenze_domande
  for select to authenticated
  using (exists (select 1 from public.teams t where t.id = team_id and t.user_id = (select auth.uid())));

-- Le richieste di generazione gia' lanciate, per non chiamare l'AI due volte
-- mentre la prima e' ancora in corso. Riprova dopo 30 minuti se non e' nato nulla.
create table private.conferenze_richieste (
  match_id     bigint primary key references public.matches(id) on delete cascade,
  richiesta_il timestamptz not null default now(),
  tentativi    smallint not null default 1
);

-- Avviso all'allenatore quando arriva la prima domanda di una partita.
create or replace function private.avvisa_conferenza()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if new.ordine = 1 then
    perform private.notifica(
      (select t.user_id from public.teams t where t.id = new.team_id),
      new.league_id, 'sistema', 'Conferenza stampa',
      'I giornalisti ti aspettano in sala stampa dopo la partita.',
      jsonb_build_object('conferenza_match_id', new.match_id));
  end if;
  return new;
end;
$$;

create trigger conferenze_domande_avviso
  after insert on public.conferenze_domande
  for each row execute function private.avvisa_conferenza();

-- L'effetto di una risposta sul morale. p_voto (-3..+1,5: asimmetrico, una grande
-- conferenza aiuta poco e una pessima fa danni veri) vale per tutta la
-- rosa, p_giocatori ([{id, effetto}]) aggiunge l'effetto sui giocatori citati.
-- Scala: 1 punto di voto = 1,5 punti di morale (su 0-100), smorzato vicino
-- agli estremi (un morale gia' a 95 sale poco, uno a 10 scende poco), cosi'
-- risposte buone a ripetizione non lo inchiodano a 100.
create or replace function public.applica_conferenza(p_domanda_id bigint, p_voto numeric, p_giocatori jsonb)
returns numeric
language plpgsql security definer set search_path = ''
as $$
declare
  v_team bigint;
  v_voto numeric := greatest(-3, least(1.5, coalesce(p_voto, 0)));
  v_media numeric;
begin
  select team_id into v_team from public.conferenze_domande where id = p_domanda_id;
  if v_team is null then raise exception 'Domanda % inesistente.', p_domanda_id; end if;

  with effetti as (
    select pi.id, pi.morale,
           (v_voto + coalesce((
              select greatest(-3, least(1.5, (g->>'effetto')::numeric))
              from jsonb_array_elements(coalesce(p_giocatori, '[]'::jsonb)) g
              where (g->>'id')::bigint = pi.id limit 1), 0)) * 1.5 as grezzo
    from public.player_instances pi
    where pi.team_id = v_team and not pi.ritirato
  ), nuovi as (
    update public.player_instances pi
       set morale = greatest(0, least(100, round(e.morale + e.grezzo *
             case when e.grezzo > 0 then least(1, (100 - e.morale) / 50.0)
                  else least(1, e.morale / 50.0) end)))::smallint
      from effetti e
     where pi.id = e.id
    returning pi.morale - e.morale as delta
  )
  select avg(delta) into v_media from nuovi;
  return round(coalesce(v_media, 0), 1);
end;
$$;

revoke all on function public.applica_conferenza(bigint, numeric, jsonb) from public, anon, authenticated;
grant execute on function public.applica_conferenza(bigint, numeric, jsonb) to service_role;

-- Il cron: per le leghe con le conferenze accese, le partite simulate nelle
-- ultime 20 ore con almeno un allenatore umano e ancora senza domande.
create or replace function private.lancia_conferenze_stampa()
returns integer
language plpgsql security definer set search_path = ''
as $$
declare
  v_chiave text;
  v_match bigint;
  v_lanciate integer := 0;
begin
  select decrypted_secret into v_chiave from vault.decrypted_secrets where name = 'chiave_simulazione';
  if v_chiave is null then return 0; end if;

  for v_match in
    select m.id
    from public.matches m
    join public.fixtures f on f.id = m.fixture_id
    join public.leagues l on l.id = f.league_id and l.conferenze_stampa
    where m.simulata_il > now() - interval '20 hours'
      and exists (select 1 from public.teams t
                  where t.id in (f.home_team_id, f.away_team_id) and t.user_id is not null and not t.controllata_da_pc)
      and not exists (select 1 from public.conferenze_domande d where d.match_id = m.id)
      and not exists (select 1 from private.conferenze_richieste r
                      where r.match_id = m.id and (r.richiesta_il > now() - interval '30 minutes' or r.tentativi >= 3))
    order by m.id
    limit 10
  loop
    insert into private.conferenze_richieste (match_id) values (v_match)
    on conflict (match_id) do update set richiesta_il = now(), tentativi = private.conferenze_richieste.tentativi + 1;
    perform net.http_post(
      url := 'http://api-gw:8000/functions/v1/conferenza-stampa',
      body := jsonb_build_object('azione', 'genera', 'match_id', v_match),
      headers := jsonb_build_object('Content-Type', 'application/json', 'apikey', v_chiave),
      timeout_milliseconds := 60000
    );
    v_lanciate := v_lanciate + 1;
  end loop;
  return v_lanciate;
end;
$$;

select cron.schedule('conferenze-stampa', '*/5 * * * *', 'select private.lancia_conferenze_stampa();');

commit;
