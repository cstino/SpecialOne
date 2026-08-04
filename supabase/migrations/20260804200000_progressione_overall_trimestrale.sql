-- ============================================================
--  PROGRESSIONE OVERALL TRIMESTRALE
--
--  Il design §10.2 definisce le fasce di crescita annuali. Gli overall non
--  aspettano più l'off-season: l'effetto annuo viene distribuito in quattro
--  checkpoint, calcolati sulle giornate reali della singola lega.
-- ============================================================

alter table public.player_instances
  add column progressione_residuo numeric not null default 0
  check (progressione_residuo > -1 and progressione_residuo < 1);

comment on column public.player_instances.progressione_residuo is
  'Frazione di overall accumulata fra i quattro checkpoint della stagione.';

create table public.season_progression_checkpoints (
  id          bigint generated always as identity primary key,
  league_id   bigint not null references public.leagues(id) on delete cascade,
  season_id   bigint not null references public.seasons(id) on delete cascade,
  checkpoint  smallint not null check (checkpoint between 1 and 4),
  giornata    smallint not null check (giornata >= 1),
  applicato_il timestamptz not null default now(),

  unique (season_id, checkpoint)
);

create index season_progression_checkpoints_league_idx
  on public.season_progression_checkpoints (league_id, season_id);

alter table public.season_progression_checkpoints enable row level security;

comment on table public.season_progression_checkpoints is
  'Registro interno e idempotente dei quattro aggiornamenti overall stagionali.';

create or replace function public.applica_progressione_trimestrale(
  p_league_id bigint,
  p_giornata smallint
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_lega record;
  v_stagione_id bigint;
  v_step smallint;
  v_soglia smallint;
  v_player record;
  v_delta numeric;
  v_valore numeric;
  v_ovr smallint;
  v_residuo numeric;
  v_checkpoint_applicati smallint[] := array[]::smallint[];
  v_giocatori_aggiornati integer := 0;
begin
  select l.id, l.stagione_corrente, l.giornate_totali, s.id season_id
  into v_lega
  from public.leagues l
  join public.seasons s
    on s.league_id = l.id and s.numero = l.stagione_corrente and s.stato = 'in_corso'
  where l.id = p_league_id and l.stato = 'stagione';

  if not found then
    raise exception using errcode = '55000', message = 'Non esiste una stagione in corso per la progressione overall.';
  end if;
  if p_giornata < 1 or p_giornata > v_lega.giornate_totali then
    raise exception using errcode = '22023', message = 'Giornata non valida per la progressione overall.';
  end if;

  v_stagione_id := v_lega.season_id;

  -- Se una chiamata fosse ritentata dopo un errore, recuperiamo ogni
  -- checkpoint maturato ma ancora mancante: nessun aggiornamento si perde.
  for v_step in select generate_series(1, 4)::smallint loop
    v_soglia := ceil(v_lega.giornate_totali::numeric * v_step / 4.0)::smallint;
    if p_giornata < v_soglia then
      continue;
    end if;

    insert into public.season_progression_checkpoints(
      league_id, season_id, checkpoint, giornata
    ) values (
      p_league_id, v_stagione_id, v_step, v_soglia
    )
    on conflict (season_id, checkpoint) do nothing;

    if not found then
      continue;
    end if;

    for v_player in
      select pi.id, pi.overall_corrente, pi.eta_corrente, pi.progressione_residuo,
             p.potential
      from public.player_instances pi
      join public.players p on p.id = pi.player_id
      join public.teams t on t.id = pi.team_id and t.attiva
      where pi.league_id = p_league_id and not pi.ritirato
      order by pi.id
      for update of pi
    loop
      -- È la formula annuale di design §10.2 divisa in quattro quote. Il
      -- residuo conserva le frazioni, quindi anche le oscillazioni piccole
      -- degli adulti arrivano a un overall intero entro la stagione.
      if v_player.eta_corrente <= 22 then
        v_delta := (greatest(v_player.potential, v_player.overall_corrente) - v_player.overall_corrente)
          * (0.15 + random() * 0.30) / 4.0;
      elsif v_player.eta_corrente <= 26 then
        v_delta := (greatest(v_player.potential, v_player.overall_corrente) - v_player.overall_corrente)
          * (0.05 + random() * 0.20) / 4.0;
      elsif v_player.eta_corrente <= 31 then
        v_delta := (-1 + random() * 2) / 4.0;
      elsif v_player.eta_corrente <= 35 then
        v_delta := -(0.5 + random() * 2) / 4.0;
      else
        v_delta := -(1.5 + random() * 2.5) / 4.0;
      end if;

      v_valore := v_player.overall_corrente + v_player.progressione_residuo + v_delta;
      v_ovr := greatest(40, least(
        greatest(v_player.potential, v_player.overall_corrente),
        round(v_valore)
      ))::smallint;
      v_residuo := case when v_ovr = 40
        or v_ovr = greatest(v_player.potential, v_player.overall_corrente)
        then 0 else v_valore - v_ovr end;

      update public.player_instances
      set overall_corrente = v_ovr,
          progressione_residuo = v_residuo
      where id = v_player.id;
      v_giocatori_aggiornati := v_giocatori_aggiornati + 1;
    end loop;

    v_checkpoint_applicati := array_append(v_checkpoint_applicati, v_step);
    exit;
  end loop;

  return jsonb_build_object(
    'checkpoint_applicati', v_checkpoint_applicati,
    'giocatori_aggiornati', v_giocatori_aggiornati
  );
end;
$$;

revoke all on function public.applica_progressione_trimestrale(bigint, smallint)
  from public, anon, authenticated;
grant execute on function public.applica_progressione_trimestrale(bigint, smallint)
  to service_role;

comment on function public.applica_progressione_trimestrale(bigint, smallint) is
  'Applica una sola volta per checkpoint la progressione annuale distribuita su quattro fasi.';

-- A fine stagione restano soltanto invecchiamento, recupero e rinnovi: la
-- variazione dell'overall è già arrivata nel quarto checkpoint.
create or replace function public.prepara_offseason(
  p_league_id bigint,
  p_squadre_rimosse bigint[] default '{}'::bigint[],
  p_posti_nuovi smallint default 0
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
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
  v_richiesta bigint;
  v_min bigint;
  v_max bigint;
  v_renewal_id bigint;
  v_ambizione numeric;
  v_sponsor bigint;
  v_premi_partita bigint;
  v_premio_posizione bigint;
  v_pool numeric;
  v_pesi numeric;
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
  v_pool := 0.12 * v_lega.budget_iniziale * (v_attive - v_rimosse);
  select sum(power((v_attive - v_rimosse - s.posizione + 1)::numeric, 1.8))
    into v_pesi
  from public.standings s
  join public.seasons se on se.id = s.season_id
  join public.teams t on t.id = s.team_id and t.attiva
  where se.league_id = p_league_id and se.numero = v_lega.stagione_corrente;

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
    v_premio_posizione := case when coalesce(v_pesi, 0) > 0
      then round((v_pool * power((v_attive - v_rimosse - v_team.posizione + 1)::numeric, 1.8) / v_pesi) / 100000) * 100000
      else 0 end;
    v_accreditato := v_sponsor + v_premi_partita + v_premio_posizione;

    update public.teams set budget = budget + v_accreditato where id = v_team.id;
    if v_premi_partita <> 0 then
      insert into public.transactions(league_id, team_id, tipo, importo, descrizione, saldo_dopo)
      values (p_league_id, v_team.id, 'premi_partite', v_premi_partita,
              'Premi partita stagione ' || v_lega.stagione_corrente,
              (select budget from public.teams where id = v_team.id));
    end if;
    if v_premio_posizione <> 0 then
      insert into public.transactions(league_id, team_id, tipo, importo, descrizione, saldo_dopo)
      values (p_league_id, v_team.id, 'premio_classifica', v_premio_posizione,
              'Premio ' || v_team.posizione || '° posto',
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

  for v_player in
    with numeri as (
      select pi.id, pi.team_id, pi.overall_corrente, pi.eta_corrente, pi.ingaggio,
             p.nome, p.posizioni[1] ruolo,
             coalesce(sum(ms.gol * 5 + ms.assist * 3 + ms.minuti::numeric / 900), 0) rendimento
      from public.player_instances pi
      join public.players p on p.id = pi.player_id
      join public.teams t on t.id = pi.team_id and t.attiva
      left join public.match_stats ms on ms.player_instance_id = pi.id
      where pi.league_id = p_league_id and not pi.ritirato
        and pi.contratto_scadenza <= v_lega.stagione_corrente
      group by pi.id, p.nome, p.posizioni[1]
    ), ordinati as (
      select n.*, percent_rank() over (partition by ruolo order by rendimento) percentile
      from numeri n
    )
    select o.*, coalesce(s.posizione, v_attive) posizione
    from ordinati o
    left join public.seasons se on se.league_id = p_league_id and se.numero = v_lega.stagione_corrente
    left join public.standings s on s.season_id = se.id and s.team_id = o.team_id
    order by o.id
  loop
    v_ambizione := case
      when v_player.posizione <= 3 then 0.90
      when v_player.posizione > ceil((v_attive - v_rimosse) * 2.0 / 3.0) then 1.15
      else 1.00 end;
    v_richiesta := greatest(500000, v_player.ingaggio, round((private.ingaggio_teorico(v_player.overall_corrente, v_player.eta_corrente)
      * (0.85 + 0.50 * v_player.percentile) * v_ambizione * (0.95 + random() * 0.10)) / 100000) * 100000);
    v_min := greatest(500000, round((v_richiesta * 0.88)::numeric / 100000) * 100000);
    v_max := greatest(v_min, round((v_richiesta * 1.12)::numeric / 100000) * 100000);

    insert into public.contract_renewals(
      offseason_id, league_id, team_id, player_instance_id, richiesta_min, richiesta_max
    ) values (v_offseason.id, p_league_id, v_player.team_id, v_player.id, v_min, v_max)
    returning id into v_renewal_id;
    insert into private.contract_renewal_terms(renewal_id, richiesta_esatta)
    values (v_renewal_id, v_richiesta);
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
$$;

revoke all on function public.prepara_offseason(bigint, bigint[], smallint)
  from public, anon, authenticated;
grant execute on function public.prepara_offseason(bigint, bigint[], smallint)
  to authenticated;
