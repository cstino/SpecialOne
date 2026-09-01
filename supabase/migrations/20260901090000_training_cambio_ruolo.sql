-- ============================================================
--  TRAINING, secondo fronte: cambio ruolo.
--
--  Decisioni prese con l'utente in questa sessione:
--   - sostituisce il ruolo primario (non lo affianca): un giocatore
--     riqualificato smette di essere quello che era prima.
--   - "tempo" (che riduzione_tempi_ruolo_pct riduce fino al -40%) e' un
--     tempo di attesa in GIORNATE prima che il nuovo ruolo sia effettivo,
--     non una squalifica dal nuovo ruolo.
--   - ruoli raggiungibili: solo "vicini", stessa logica di
--     engine/config.js REPARTO/ADIACENTI (stesso reparto o reparto
--     adiacente: DEF<->MID, MID<->ATT). Niente portiere <-> movimento,
--     mai toccato dal motore per scelta di design pregressa.
--   - durata dipende dal giocatore: piu' ruoli conosce all'inizio, piu' e'
--     rapido a impararne uno nuovo (base 14 giornate per uno specialista
--     puro, -2 per ogni ruolo extra gia' noto, minimo 6 — poi la curva
--     TRAINING riduce fino al -40%, minimo 2 giornate).
--
--  Scelta autonoma non discussa esplicitamente, segnalata all'utente:
--   nessun limite al numero di cambi ruolo contemporanei per squadra
--   (solo uno per giocatore alla volta, ovviamente). Se serve un tetto
--   per bilanciamento, e' un indice partial da aggiungere in seguito.
-- ============================================================

begin;

-- ------------------------------------------------------------
--  Il ruolo cambiato vive per-istanza (per lega), mai sul catalogo
--  condiviso players.posizioni: lo stesso player_id e' usato da altre
--  leghe in corso, che non devono vedere il cambio.
-- ------------------------------------------------------------
alter table public.player_instances
  add column posizioni_override text[];
alter table public.player_instances
  add constraint player_instances_posizioni_override_check
  check (posizioni_override is null or (
    cardinality(posizioni_override) = 1 and posizioni_override <@ private.ruoli_validi()
  ));
comment on column public.player_instances.posizioni_override is
  'Ruolo assegnato da un cambio di ruolo completato (Gestione risorse, TRAINING): quando non e'' null sostituisce integralmente players.posizioni per questa istanza. Scritto solo da private.completa_cambi_ruolo().';

create table public.cambi_ruolo (
  id bigint generated always as identity primary key,
  league_id bigint not null references public.leagues(id) on delete cascade,
  team_id bigint not null references public.teams(id) on delete cascade,
  player_instance_id bigint not null references public.player_instances(id) on delete cascade,
  ruolo_precedente text not null check (ruolo_precedente = any (private.ruoli_validi())),
  ruolo_target text not null check (ruolo_target = any (private.ruoli_validi())),
  avviato_giornata integer not null,
  completa_giornata integer not null,
  completato_il timestamptz,
  creato_il timestamptz not null default now()
);
comment on table public.cambi_ruolo is
  'Riqualificazioni in corso o concluse (TRAINING, riduzione_tempi_ruolo_pct). avviato/completa_giornata sono numeri di giornata di campionato, non date.';
-- Un solo cambio ruolo alla volta per giocatore: indice parziale sulle
-- righe ancora aperte, stesso pattern di altri "uno-alla-volta" nel gioco.
create unique index cambi_ruolo_un_solo_in_corso on public.cambi_ruolo (player_instance_id) where completato_il is null;
create index cambi_ruolo_team_idx on public.cambi_ruolo(team_id);
create index cambi_ruolo_league_aperti_idx on public.cambi_ruolo(league_id) where completato_il is null;

alter table public.cambi_ruolo enable row level security;
create policy cambi_ruolo_lettura on public.cambi_ruolo
  for select using ((select private.e_membro(league_id)));
grant select on public.cambi_ruolo to authenticated;

-- ------------------------------------------------------------
--  Ruoli raggiungibili da una posizione attuale: stesso reparto o
--  reparto adiacente (DEF<->MID, MID<->ATT), mai portiere.
-- ------------------------------------------------------------
create or replace function private.ruoli_target_cambio(p_posizioni_attuali text[])
returns text[]
language sql
immutable
security invoker
set search_path = ''
as $$
  select array_agg(r order by r) from unnest(private.ruoli_validi()) as r
  where private.macro_ruolo(p_posizioni_attuali) <> 'GK'
    and r <> 'GK'
    and r <> p_posizioni_attuali[1]
    and (
      private.macro_ruolo(array[r]) = private.macro_ruolo(p_posizioni_attuali)
      or (private.macro_ruolo(p_posizioni_attuali) = 'DEF' and private.macro_ruolo(array[r]) = 'MID')
      or (private.macro_ruolo(p_posizioni_attuali) = 'MID' and private.macro_ruolo(array[r]) in ('DEF', 'ATT'))
      or (private.macro_ruolo(p_posizioni_attuali) = 'ATT' and private.macro_ruolo(array[r]) = 'MID')
    );
$$;

-- Wrapper pubblico: il frontend deve poter mostrare i ruoli raggiungibili
-- prima di avviare il cambio, senza duplicare la logica lato client.
create or replace function public.ruoli_target_cambio(p_instance_id bigint)
returns text[]
language sql
stable
security invoker
set search_path = ''
as $$
  select private.ruoli_target_cambio(coalesce(pi.posizioni_override, p.posizioni))
  from public.player_instances pi
  join public.players p on p.id = pi.player_id
  where pi.id = p_instance_id;
$$;
grant execute on function public.ruoli_target_cambio(bigint) to authenticated;

-- ------------------------------------------------------------
--  Avvio del cambio ruolo.
-- ------------------------------------------------------------
create or replace function public.avvia_cambio_ruolo(p_instance_id bigint, p_ruolo_target text)
returns public.cambi_ruolo
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_utente uuid := (select auth.uid());
  v_istanza public.player_instances;
  v_squadra public.teams;
  v_lega public.leagues;
  v_posizioni_attuali text[];
  v_target_validi text[];
  v_livello smallint;
  v_riduzione numeric;
  v_base integer;
  v_durata integer;
  v_prossima integer;
  v_cambio public.cambi_ruolo;
begin
  if v_utente is null then
    raise exception using errcode = '42501', message = 'Devi accedere per gestire il training.';
  end if;

  select * into v_istanza from public.player_instances where id = p_instance_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Giocatore inesistente.';
  end if;

  select * into v_squadra from public.teams where id = v_istanza.team_id and user_id = v_utente;
  if not found then
    raise exception using errcode = '42501', message = 'Questo giocatore non appartiene alla tua squadra.';
  end if;

  select * into v_lega from public.leagues where id = v_istanza.league_id;
  if v_lega.stato <> 'stagione' then
    raise exception using errcode = '55000', message = 'Puoi avviare un cambio di ruolo solo durante la stagione.';
  end if;

  perform 1 from public.player_instances where id = p_instance_id for update;

  if exists (
    select 1 from public.cambi_ruolo
    where player_instance_id = p_instance_id and completato_il is null
  ) then
    raise exception using errcode = '55000', message = 'Questo giocatore ha già un cambio di ruolo in corso.';
  end if;

  select coalesce(pi.posizioni_override, p.posizioni) into v_posizioni_attuali
  from public.player_instances pi
  join public.players p on p.id = pi.player_id
  where pi.id = p_instance_id;

  v_target_validi := private.ruoli_target_cambio(v_posizioni_attuali);
  if v_target_validi is null or not (p_ruolo_target = any(v_target_validi)) then
    raise exception using errcode = '22023',
      message = 'Ruolo non raggiungibile da un giocatore che gioca ' || v_posizioni_attuali[1] || '.';
  end if;

  select livello_training into v_livello from public.team_risorse where team_id = v_squadra.id;
  v_riduzione := coalesce(
    (private.effetti_ramo('training', coalesce(v_livello, 0::smallint))->>'riduzione_tempi_ruolo_pct')::numeric, 0);

  -- Base 14 giornate per uno specialista puro (un solo ruolo noto), -2 per
  -- ogni ruolo extra gia' conosciuto, minimo 6: chi e' gia' versatile
  -- impara piu' in fretta un ruolo vicino.
  v_base := greatest(6, 14 - 2 * (cardinality(v_posizioni_attuali) - 1));
  v_durata := greatest(2, round(v_base * (1 - v_riduzione / 100.0)));

  select coalesce(min(f.giornata), v_lega.giornate_totali + 1) into v_prossima
  from public.fixtures f where f.league_id = v_lega.id and f.stato = 'programmata';

  insert into public.cambi_ruolo (
    league_id, team_id, player_instance_id, ruolo_precedente, ruolo_target,
    avviato_giornata, completa_giornata
  ) values (
    v_lega.id, v_squadra.id, p_instance_id, v_posizioni_attuali[1], p_ruolo_target,
    v_prossima, v_prossima + v_durata
  ) returning * into v_cambio;

  return v_cambio;
end;
$$;
grant execute on function public.avvia_cambio_ruolo(bigint, text) to authenticated;

-- ------------------------------------------------------------
--  Annullamento: non richiesto esplicitamente, ma senza una via d'uscita
--  un errore di battitura blocca un giocatore per 6-14 giornate. Stesso
--  costo/beneficio di public.ritira_offerta_under.
-- ------------------------------------------------------------
create or replace function public.annulla_cambio_ruolo(p_id bigint)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_utente uuid := (select auth.uid());
begin
  if v_utente is null then
    raise exception using errcode = '42501', message = 'Devi accedere per gestire il training.';
  end if;
  delete from public.cambi_ruolo c
  using public.teams t
  where c.id = p_id and c.team_id = t.id and t.user_id = v_utente and c.completato_il is null;
end;
$$;
grant execute on function public.annulla_cambio_ruolo(bigint) to authenticated;

-- ------------------------------------------------------------
--  Completamento: job periodico, stessa idea di finalizza_offseason_scadute
--  (ogni 15 minuti, idempotente — agisce solo sulle righe ancora aperte la
--  cui giornata bersaglio e' stata raggiunta o superata).
-- ------------------------------------------------------------
create or replace function private.completa_cambi_ruolo()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_lega record;
  v_prossima integer;
  v_cambio record;
  v_completati integer := 0;
begin
  for v_lega in select id, giornate_totali from public.leagues where stato = 'stagione' loop
    select coalesce(min(f.giornata), v_lega.giornate_totali + 1) into v_prossima
    from public.fixtures f where f.league_id = v_lega.id and f.stato = 'programmata';

    for v_cambio in
      select * from public.cambi_ruolo
      where league_id = v_lega.id and completato_il is null and completa_giornata <= v_prossima
      order by id
      for update
    loop
      update public.player_instances
      set posizioni_override = array[v_cambio.ruolo_target]
      where id = v_cambio.player_instance_id;

      update public.cambi_ruolo set completato_il = now() where id = v_cambio.id;

      perform private.notifica(
        t.user_id, v_lega.id, 'sistema', 'Riqualificazione completata',
        'Un giocatore ha completato il training: ora gioca ' || v_cambio.ruolo_target || '.',
        jsonb_build_object('view', 'team', 'player_instance_id', v_cambio.player_instance_id)
      )
      from public.teams t where t.id = v_cambio.team_id;

      v_completati := v_completati + 1;
    end loop;
  end loop;
  return v_completati;
end;
$$;

revoke all on function private.completa_cambi_ruolo() from public, anon, authenticated;
grant execute on function private.completa_cambi_ruolo() to service_role;

select cron.schedule(
  'completa-cambi-ruolo',
  '*/15 * * * *',
  $cron$select private.completa_cambi_ruolo();$cron$
);

commit;
