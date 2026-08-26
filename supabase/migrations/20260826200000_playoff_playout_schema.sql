-- Schema di playoff e playout (design §10.7). Terzo tassello, dopo i
-- supplementari nel motore e il modulo dei rigori.
--
-- Contiene solo lo SCHEMA e i premi: la generazione dei tabelloni e la loro
-- simulazione arrivano nella migrazione successiva. Le partite di
-- eliminatoria restano normalissime fixtures, cosi' il cron notturno e la
-- pagina partita continuano a funzionare senza sapere nulla dei tabelloni;
-- quello che cambia e' che NON contano per la classifica (vedi la modifica a
-- registra_risultato_partita nella migrazione di generazione).

-- ------------------------------------------------------------
--  Tabelloni
-- ------------------------------------------------------------

create table if not exists public.brackets (
  id                bigint generated always as identity primary key,
  league_id         bigint not null references public.leagues(id) on delete cascade,
  season_id         bigint not null,
  tipo              text not null check (tipo in ('playoff', 'playout')),
  stato             text not null default 'in_corso' check (stato in ('in_corso', 'concluso')),
  vincitore_team_id bigint,
  finalista_team_id bigint,
  creato_il         timestamptz not null default now(),
  concluso_il       timestamptz,
  constraint brackets_season_fk foreign key (season_id, league_id)
    references public.seasons(id, league_id) on delete cascade,
  constraint brackets_vincitore_fk foreign key (vincitore_team_id, league_id)
    references public.teams(id, league_id) on delete set null,
  constraint brackets_finalista_fk foreign key (finalista_team_id, league_id)
    references public.teams(id, league_id) on delete set null,
  unique (season_id, tipo),
  unique (id, league_id)
);

comment on table public.brackets is
  'Un tabellone a eliminazione per stagione e tipo: playoff per il titolo, playout per il bonus economico (design §10.7).';

-- Un accoppiamento del tabellone. "alta" e "bassa" si riferiscono al seed
-- DENTRO il gruppo, non alla classifica assoluta: nel playout la testa di
-- serie e' l'ultima in classifica generale.
create table if not exists public.bracket_ties (
  id                bigint generated always as identity primary key,
  bracket_id        bigint not null,
  league_id         bigint not null,
  turno             smallint not null check (turno >= 1),
  posizione         smallint not null check (posizione >= 0),
  alta_team_id      bigint,
  bassa_team_id     bigint,
  alta_seed         smallint,
  bassa_seed        smallint,
  gara_secca        boolean not null default false,
  vincitore_team_id bigint,
  stato             text not null default 'in_attesa'
                    check (stato in ('in_attesa', 'in_corso', 'concluso')),
  constraint bracket_ties_bracket_fk foreign key (bracket_id, league_id)
    references public.brackets(id, league_id) on delete cascade,
  constraint bracket_ties_alta_fk foreign key (alta_team_id, league_id)
    references public.teams(id, league_id) on delete set null,
  constraint bracket_ties_bassa_fk foreign key (bassa_team_id, league_id)
    references public.teams(id, league_id) on delete set null,
  constraint bracket_ties_vincitore_fk foreign key (vincitore_team_id, league_id)
    references public.teams(id, league_id) on delete set null,
  constraint bracket_ties_squadre_diverse
    check (alta_team_id is null or bassa_team_id is null or alta_team_id <> bassa_team_id),
  unique (bracket_id, turno, posizione),
  unique (id, league_id)
);

comment on column public.bracket_ties.alta_team_id is
  'Seed migliore DEL GRUPPO: gioca il ritorno in casa. Nel playout e'' l''ultima in classifica assoluta.';

create index if not exists brackets_league_idx on public.brackets(league_id, season_id);
create index if not exists bracket_ties_bracket_idx on public.bracket_ties(bracket_id, turno, posizione);

-- ------------------------------------------------------------
--  Le fixtures sanno a quale accoppiamento appartengono
-- ------------------------------------------------------------

alter table public.fixtures
  add column if not exists bracket_tie_id bigint,
  add column if not exists mano smallint check (mano in (1, 2));

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'fixtures_bracket_tie_fk'
  ) then
    alter table public.fixtures
      add constraint fixtures_bracket_tie_fk foreign key (bracket_tie_id, league_id)
      references public.bracket_ties(id, league_id) on delete cascade;
  end if;
  if not exists (
    select 1 from pg_constraint where conname = 'fixtures_mano_coerente'
  ) then
    -- Una fixture di eliminatoria ha sempre una mano (1 andata, 2 ritorno o
    -- gara secca); una di campionato non ne ha mai.
    alter table public.fixtures
      add constraint fixtures_mano_coerente
      check ((bracket_tie_id is null and mano is null) or (bracket_tie_id is not null and mano is not null));
  end if;
end $$;

create index if not exists fixtures_bracket_tie_idx on public.fixtures(bracket_tie_id) where bracket_tie_id is not null;

comment on column public.fixtures.bracket_tie_id is
  'Se valorizzata, la partita e'' di playoff/playout e NON conta per la classifica (design §10.7).';

-- ------------------------------------------------------------
--  Il tabellino registra supplementari e rigori
-- ------------------------------------------------------------

alter table public.matches
  add column if not exists gol_home_90 smallint check (gol_home_90 >= 0),
  add column if not exists gol_away_90 smallint check (gol_away_90 >= 0),
  add column if not exists rigori_home smallint check (rigori_home >= 0),
  add column if not exists rigori_away smallint check (rigori_away >= 0),
  add column if not exists rigori_serie jsonb;

comment on column public.matches.gol_home_90 is
  'Parziale dei 90 minuti. NULL quando non si sono giocati supplementari: gol_home e'' gia'' il risultato dei regolamentari.';
comment on column public.matches.rigori_serie is
  'Tabellino della sequenza dai dischetti, come restituito da engine/rigori.js. NULL se non si e'' andati ai rigori.';

-- ------------------------------------------------------------
--  RLS: come per fixtures e standings, lettura ai membri della lega.
--  Nessuna policy di scrittura: si scrive solo da funzioni security definer.
-- ------------------------------------------------------------

alter table public.brackets enable row level security;
alter table public.bracket_ties enable row level security;

drop policy if exists brackets_lettura on public.brackets;
create policy brackets_lettura on public.brackets
  for select to authenticated
  using ((select private.e_membro(league_id)));

drop policy if exists bracket_ties_lettura on public.bracket_ties;
create policy bracket_ties_lettura on public.bracket_ties
  for select to authenticated
  using ((select private.e_membro(league_id)));

-- ------------------------------------------------------------
--  L'entrata minima garantita cambia (§5.7 -> §10.7)
--
--  Il tetto di sostenibilita' stimava, come componente peggiore, il premio
--  posizione dell'ultima in classifica. Quel premio non esiste piu': al suo
--  posto c'e' il premio di partecipazione, uguale per tutte e quindi
--  garantito per definizione. Il bonus del playout NON entra nel conto: e'
--  incerto, e il tetto deve restare prudente.
-- ------------------------------------------------------------

create or replace function private.entrata_minima_garantita(p_league_id bigint)
returns bigint
language sql
stable
set search_path = ''
as $$
  select
    (round(l.budget_iniziale * 0.20 / 100000)::bigint * 100000)   -- sponsor
    + (round(l.budget_iniziale * 0.135 / 100000)::bigint * 100000) -- premi partita, tutte sconfitte
    + (round(l.budget_iniziale * 0.15 / 100000)::bigint * 100000)  -- partecipazione (§10.7)
  from public.leagues l
  where l.id = p_league_id
$$;

comment on function private.entrata_minima_garantita(bigint) is
  'Entrata minima che una squadra incassa comunque in una stagione: sponsor + premi partita da ultima (tutte sconfitte) + premio di partecipazione. Esclude il bonus del playout, che e'' incerto.';

revoke all on function private.entrata_minima_garantita(bigint) from public, anon, authenticated;

-- ------------------------------------------------------------
--  prepara_offseason: il premio posizione a curva diventa piatto
--  (unica modifica alla funzione, il resto e' identico alla versione live)
-- ------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.prepara_offseason(p_league_id bigint, p_squadre_rimosse bigint[] DEFAULT '{}'::bigint[], p_posti_nuovi smallint DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_user uuid := (select auth.uid());
  v_lega public.leagues;
  v_offseason public.offseasons;
  v_attive integer;
  v_rimosse integer;
  v_target integer;
  v_team record;
  v_player record;
  v_eta smallint;
  v_sponsor bigint;
  v_premi_partita bigint;
  v_partecipazione bigint;
  v_accreditato bigint;
  v_ritirati integer := 0;
begin
  if v_user is null then
    raise exception using errcode = '42501', message = 'Devi accedere per aprire l''off-season.';
  end if;

  select * into v_lega from public.leagues where id = p_league_id for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Lega non trovata.';
  end if;
  if v_lega.admin_id <> v_user then
    raise exception using errcode = '42501', message = 'Solo l''admin può aprire l''off-season.';
  end if;
  if v_lega.stato <> 'conclusa' or v_lega.fase_carriera <> 'normale' then
    raise exception using errcode = '55000', message = 'L''off-season è disponibile soltanto dopo una stagione conclusa.';
  end if;
  if coalesce(p_posti_nuovi, 0) not between 0 and 16 then
    raise exception using errcode = '22023', message = 'Numero di nuovi posti non valido.';
  end if;
  if cardinality(coalesce(p_squadre_rimosse, '{}'::bigint[])) <>
     (select count(distinct id) from unnest(coalesce(p_squadre_rimosse, '{}'::bigint[])) x(id)) then
    raise exception using errcode = '22023', message = 'La lista delle squadre rimosse contiene duplicati.';
  end if;
  if exists (
    select 1 from unnest(coalesce(p_squadre_rimosse, '{}'::bigint[])) x(id)
    left join public.teams t on t.id = x.id and t.league_id = p_league_id and t.attiva
    where t.id is null
  ) then
    raise exception using errcode = '22023', message = 'Una squadra da rimuovere non appartiene alla lega o è già inattiva.';
  end if;
  if exists (
    select 1 from public.teams
    where id = any(coalesce(p_squadre_rimosse, '{}'::bigint[])) and user_id = v_lega.admin_id
  ) then
    raise exception using errcode = '22023', message = 'L''admin non può rimuovere la propria squadra.';
  end if;

  select count(*) into v_attive from public.teams where league_id = p_league_id and attiva;
  v_rimosse := cardinality(coalesce(p_squadre_rimosse, '{}'::bigint[]));
  v_target := v_attive - v_rimosse + coalesce(p_posti_nuovi, 0);
  if v_target not between 4 and 20 then
    raise exception using errcode = '22023', message = 'La prossima stagione deve avere da 4 a 20 squadre.';
  end if;

  insert into public.offseasons (league_id, stagione_da, stagione_a, scade_il, posti_nuovi)
  values (p_league_id, v_lega.stagione_corrente, v_lega.stagione_corrente + 1,
          ((now() at time zone 'Europe/Rome') + interval '7 days') at time zone 'Europe/Rome',
          coalesce(p_posti_nuovi, 0))
  returning * into v_offseason;

  if v_rimosse > 0 then
    update public.trade_proposals
    set stato = 'scaduta', risolta_il = now()
    where league_id = p_league_id and stato = 'in_attesa'
      and (da_team_id = any(p_squadre_rimosse) or a_team_id = any(p_squadre_rimosse));

    update public.player_instances
    set team_id = null
    where league_id = p_league_id and team_id = any(p_squadre_rimosse);

    update public.teams
    set attiva = false, uscita_stagione = v_lega.stagione_corrente
    where league_id = p_league_id and id = any(p_squadre_rimosse);
  end if;

  v_sponsor := round((v_lega.budget_iniziale * 0.20)::numeric / 100000) * 100000;
  -- Premio di partecipazione (design §10.7): uguale per tutte, la posizione
  -- finale non lo tocca piu'. Il denaro differenziato si vince nel playout.
  v_partecipazione := round((v_lega.budget_iniziale * 0.15)::numeric / 100000) * 100000;

  for v_team in
    select t.id, t.user_id, t.nome, t.budget,
           coalesce(s.vittorie, 0) vittorie, coalesce(s.pareggi, 0) pareggi,
           coalesce(s.sconfitte, 0) sconfitte, coalesce(s.posizione, v_attive) posizione
    from public.teams t
    left join public.seasons se on se.league_id = t.league_id and se.numero = v_lega.stagione_corrente
    left join public.standings s on s.season_id = se.id and s.team_id = t.id
    where t.league_id = p_league_id and t.attiva
    order by t.id
    for update of t
  loop
    v_premi_partita := round((v_lega.budget_iniziale::numeric
      * (0.54 * v_team.vittorie + 0.27 * v_team.pareggi + 0.135 * v_team.sconfitte)
      / greatest(v_lega.partite_per_squadra, 1)) / 100000) * 100000;
    v_accreditato := v_sponsor + v_premi_partita + v_partecipazione;

    update public.teams set budget = budget + v_accreditato where id = v_team.id;
    if v_premi_partita <> 0 then
      insert into public.transactions(league_id, team_id, tipo, importo, descrizione, saldo_dopo)
      values (p_league_id, v_team.id, 'premi_partite', v_premi_partita,
              'Premi partita stagione ' || v_lega.stagione_corrente,
              (select budget from public.teams where id = v_team.id));
    end if;
    if v_partecipazione <> 0 then
      insert into public.transactions(league_id, team_id, tipo, importo, descrizione, saldo_dopo)
      values (p_league_id, v_team.id, 'premio_partecipazione', v_partecipazione,
              'Premio di partecipazione stagione ' || v_lega.stagione_corrente,
              (select budget from public.teams where id = v_team.id));
    end if;
    if v_sponsor <> 0 then
      insert into public.transactions(league_id, team_id, tipo, importo, descrizione, saldo_dopo)
      values (p_league_id, v_team.id, 'sponsor', v_sponsor,
              'Sponsor stagione ' || v_offseason.stagione_a,
              (select budget from public.teams where id = v_team.id));
    end if;
  end loop;

  for v_player in
    select pi.id, pi.player_id, p.nome, t.user_id
    from public.player_instances pi
    join public.players p on p.id = pi.player_id
    join public.teams t on t.id = pi.team_id and t.attiva
    where pi.league_id = p_league_id and pi.ritiro_annunciato and not pi.ritirato
  loop
    update public.player_instances
    set team_id = null, ritirato = true, ritiro_annunciato = false
    where id = v_player.id;
    insert into public.retired_players(league_id, player_id, stagione)
    values (p_league_id, v_player.player_id, v_lega.stagione_corrente)
    on conflict do nothing;
    v_ritirati := v_ritirati + 1;
    perform private.notifica(v_player.user_id, p_league_id, 'sistema',
      v_player.nome || ' si ritira',
      'Il ritiro annunciato a inizio stagione e'' ora effettivo: la carriera termina qui.',
      jsonb_build_object('player_instance_id', v_player.id));
  end loop;

  -- La progressione OVR è stata applicata ai quattro checkpoint; qui età e
  -- recupero vengono portati alla nuova stagione senza un quinto aggiornamento.
  for v_player in
    select pi.id, pi.eta_corrente
    from public.player_instances pi
    join public.teams t on t.id = pi.team_id and t.attiva
    where pi.league_id = p_league_id and not pi.ritirato
    order by pi.id
    for update of pi
  loop
    v_eta := least(45, v_player.eta_corrente + 1);
    update public.player_instances
    set eta_corrente = v_eta,
        condizione = 100,
        infortunato_fino_a = 0,
        progressione_residuo = 0
    where id = v_player.id;
  end loop;


  update public.leagues
  set n_squadre = v_target,
      stato = 'stagione',
      fase_carriera = 'offseason',
      offseason_fine = v_offseason.scade_il
  where id = p_league_id;

  return jsonb_build_object(
    'league_id', p_league_id,
    'offseason_id', v_offseason.id,
    'stagione_a', v_offseason.stagione_a,
    'scade_il', v_offseason.scade_il,
    'squadre_attese', v_target,
    'posti_nuovi', p_posti_nuovi,
    'ritirati', v_ritirati
  );
end;
$function$;

revoke all on function public.prepara_offseason(bigint, bigint[], smallint) from public, anon;
grant execute on function public.prepara_offseason(bigint, bigint[], smallint) to authenticated;
