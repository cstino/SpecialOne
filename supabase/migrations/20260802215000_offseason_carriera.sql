-- ============================================================
--  OFF-SEASON E CARRIERA PLURISTAGIONALE (design §10.2-§10.6)
--
--  `leagues.stato` resta `stagione` durante la settimana: in questo modo
--  tutte le RPC del mercato già verificate continuano a funzionare. La fase
--  di carriera separa la stagione giocata dalla preparazione della successiva.
-- ============================================================

alter table public.leagues
  add column fase_carriera text not null default 'normale'
    check (fase_carriera in ('normale', 'offseason', 'terminata')),
  add column offseason_fine timestamptz;

alter table public.teams
  add column attiva boolean not null default true,
  add column entrata_stagione smallint not null default 1 check (entrata_stagione >= 1),
  add column uscita_stagione smallint check (uscita_stagione >= entrata_stagione);

alter table public.player_instances
  add column contratto_scadenza smallint not null default 1 check (contratto_scadenza >= 1),
  add column ritirato boolean not null default false;

-- Le istanze storiche hanno firmato per la stagione corrente della lega.
update public.player_instances pi
set contratto_scadenza = l.stagione_corrente
from public.leagues l
where l.id = pi.league_id;

create table public.offseasons (
  id                 bigint generated always as identity primary key,
  league_id          bigint not null references public.leagues(id) on delete cascade,
  stagione_da        smallint not null check (stagione_da >= 1),
  stagione_a         smallint not null check (stagione_a = stagione_da + 1),
  stato              text not null default 'aperta' check (stato in ('aperta','conclusa')),
  scade_il           timestamptz not null,
  posti_nuovi        smallint not null default 0 check (posti_nuovi between 0 and 16),
  creata_il          timestamptz not null default now(),
  conclusa_il        timestamptz,
  unique (league_id, stagione_a),
  unique (id, league_id)
);

create table public.contract_renewals (
  id                  bigint generated always as identity primary key,
  offseason_id        bigint not null,
  league_id           bigint not null,
  team_id             bigint not null,
  player_instance_id  bigint not null,
  richiesta_min       bigint not null check (richiesta_min >= 500000),
  richiesta_max       bigint not null check (richiesta_max >= richiesta_min),
  offerta             bigint check (offerta >= 500000),
  durata              smallint check (durata between 1 and 4),
  stato               text not null default 'in_attesa'
                      check (stato in ('in_attesa','accettato','rifiutato','scaduto','ritirato')),
  risolta_il          timestamptz,
  creata_il           timestamptz not null default now(),
  constraint contract_renewals_offseason_fk
    foreign key (offseason_id, league_id)
    references public.offseasons(id, league_id) on delete cascade,
  constraint contract_renewals_team_fk
    foreign key (team_id, league_id)
    references public.teams(id, league_id) on delete cascade,
  constraint contract_renewals_player_fk
    foreign key (player_instance_id, league_id)
    references public.player_instances(id, league_id) on delete cascade,
  unique (offseason_id, player_instance_id)
);

create table private.contract_renewal_terms (
  renewal_id bigint primary key references public.contract_renewals(id) on delete cascade,
  richiesta_esatta bigint not null check (richiesta_esatta >= 500000)
);

create index offseasons_league_idx on public.offseasons(league_id, stagione_a desc);
create index contract_renewals_team_idx on public.contract_renewals(team_id, stato, id);
create index contract_renewals_offseason_idx on public.contract_renewals(offseason_id, stato);

alter table public.offseasons enable row level security;
alter table public.contract_renewals enable row level security;
alter table private.contract_renewal_terms enable row level security;

create policy offseasons_lettura on public.offseasons
  for select to authenticated
  using ((select private.e_membro(league_id)));

create policy contract_renewals_lettura on public.contract_renewals
  for select to authenticated
  using ((select private.e_mia_squadra(team_id)));

grant select on public.offseasons, public.contract_renewals to authenticated;
grant select, insert, update, delete on public.offseasons, public.contract_renewals to service_role;
revoke all on private.contract_renewal_terms from public, anon, authenticated;
grant select, insert, update, delete on private.contract_renewal_terms to service_role;

-- Le nuove tabelle nascono chiuse per default nel progetto: i GRANT sopra
-- sono intenzionali e separati dalla RLS, come richiesto dal Data API 2026.
revoke all on public.offseasons, public.contract_renewals from anon;

-- Un team rimosso conserva risultati e storico, ma non può più operare nel
-- mercato della lega. I trigger coprono anche chiamate forgiate fuori dalla UI.
create or replace function private.verifica_squadra_mercato_attiva()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_team_id bigint;
begin
  v_team_id := case when tg_table_name = 'free_agent_bids' then new.team_id else new.da_team_id end;
  if not exists (select 1 from public.teams where id = v_team_id and attiva) then
    raise exception using errcode = '55000', message = 'La squadra non è attiva in questa lega.';
  end if;
  if tg_table_name = 'trade_proposals'
     and not exists (select 1 from public.teams where id = new.a_team_id and attiva) then
    raise exception using errcode = '55000', message = 'La squadra destinataria non è attiva in questa lega.';
  end if;
  return new;
end;
$$;

revoke all on function private.verifica_squadra_mercato_attiva() from public, anon, authenticated;

create trigger trade_proposals_squadre_attive
  before insert on public.trade_proposals
  for each row execute function private.verifica_squadra_mercato_attiva();

create trigger free_agent_bids_squadra_attiva
  before insert or update on public.free_agent_bids
  for each row execute function private.verifica_squadra_mercato_attiva();

-- Un acquisto a stagione in corso dura fino alla fine della stagione; durante
-- l'off-season il contratto copre invece la stagione che sta per iniziare.
create or replace function private.imposta_scadenza_nuovo_contratto()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_lega public.leagues;
begin
  if new.team_id is null then
    return new;
  end if;
  if tg_op = 'INSERT' then
    select * into v_lega from public.leagues where id = new.league_id;
    new.contratto_scadenza := v_lega.stagione_corrente
      + case when v_lega.fase_carriera = 'offseason' then 1 else 0 end;
  elsif old.team_id is null then
    select * into v_lega from public.leagues where id = new.league_id;
    new.contratto_scadenza := v_lega.stagione_corrente
      + case when v_lega.fase_carriera = 'offseason' then 1 else 0 end;
  end if;
  return new;
end;
$$;

revoke all on function private.imposta_scadenza_nuovo_contratto() from public, anon, authenticated;

create trigger player_instances_scadenza_contratto
  before insert or update of team_id on public.player_instances
  for each row execute function private.imposta_scadenza_nuovo_contratto();

-- ------------------------------------------------------------
--  APERTURA OFF-SEASON
-- ------------------------------------------------------------

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
  v_ovr smallint;
  v_delta numeric;
  v_prob_ritiro numeric;
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

  -- Le squadre uscite restano nello storico, ma rosa e mercato vengono chiusi.
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

  -- Premi mancanti della stagione appena finita, premio posizione e sponsor
  -- della nuova stagione: servono prima dei rinnovi, quando il budget conta.
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

  -- Invecchiamento, crescita/declino e ritiri avvengono una volta sola: la
  -- UNIQUE sull'off-season rende questa funzione non ripetibile.
  for v_player in
    select pi.*, p.potential, p.nome, t.user_id
    from public.player_instances pi
    join public.players p on p.id = pi.player_id
    join public.teams t on t.id = pi.team_id and t.attiva
    where pi.league_id = p_league_id and not pi.ritirato
    order by pi.id
    for update of pi
  loop
    v_eta := least(45, v_player.eta_corrente + 1);
    if v_eta <= 22 then
      v_delta := (greatest(v_player.potential, v_player.overall_corrente) - v_player.overall_corrente) * (0.15 + random() * 0.30);
    elsif v_eta <= 26 then
      v_delta := (greatest(v_player.potential, v_player.overall_corrente) - v_player.overall_corrente) * (0.05 + random() * 0.20);
    elsif v_eta <= 31 then
      v_delta := -1 + random() * 2;
    elsif v_eta <= 35 then
      v_delta := -(0.5 + random() * 2);
    else
      v_delta := -(1.5 + random() * 2.5);
    end if;
    v_ovr := greatest(40, least(greatest(v_player.potential, v_player.overall_corrente), round(v_player.overall_corrente + v_delta)))::smallint;
    v_prob_ritiro := greatest(0, (v_eta - 33) * 0.12);

    if v_eta >= 42 or random() < v_prob_ritiro then
      update public.player_instances
      set eta_corrente = v_eta, overall_corrente = v_ovr, team_id = null,
          ritirato = true, condizione = 100, infortunato_fino_a = 0
      where id = v_player.id;
      v_ritirati := v_ritirati + 1;
      perform private.notifica(v_player.user_id, p_league_id, 'sistema',
        v_player.nome || ' si ritira', 'Il giocatore ha concluso la carriera al termine della stagione.',
        jsonb_build_object('player_instance_id', v_player.id));
    else
      update public.player_instances
      set eta_corrente = v_eta, overall_corrente = v_ovr,
          condizione = 100, infortunato_fino_a = 0
      where id = v_player.id;
    end if;
  end loop;

  -- Rendimento relativo nel reparto: percent_rank 0..1 trasformato nel
  -- moltiplicatore 0,85..1,35 previsto dal design.
  for v_player in
    with numeri as (
      select pi.id, pi.team_id, pi.overall_corrente, pi.eta_corrente,
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
    v_richiesta := greatest(500000, round((private.ingaggio_teorico(v_player.overall_corrente, v_player.eta_corrente)
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

revoke all on function public.prepara_offseason(bigint, bigint[], smallint) from public, anon, authenticated;
grant execute on function public.prepara_offseason(bigint, bigint[], smallint) to authenticated;

-- ------------------------------------------------------------
--  RINNOVI
-- ------------------------------------------------------------

create or replace function public.rispondi_rinnovo(
  p_rinnovo_id bigint,
  p_offerta bigint,
  p_durata smallint
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
  v_rinnovo public.contract_renewals;
  v_offseason public.offseasons;
  v_richiesta bigint;
  v_rapporto numeric;
  v_accetta boolean := false;
  v_ingaggio bigint;
  v_nome text;
begin
  if v_user is null then
    raise exception using errcode = '42501', message = 'Devi accedere per rispondere al rinnovo.';
  end if;
  if p_offerta < 500000 or p_offerta % 100000 <> 0 then
    raise exception using errcode = '22023', message = 'L''offerta deve essere almeno 0,5 M€ e a scatti di 0,1 M€.';
  end if;
  if p_durata not between 1 and 4 then
    raise exception using errcode = '22023', message = 'La durata deve essere fra 1 e 4 anni.';
  end if;

  select * into v_rinnovo from public.contract_renewals where id = p_rinnovo_id for update;
  if not found then raise exception using errcode = 'P0002', message = 'Rinnovo non trovato.'; end if;
  if not (select private.e_mia_squadra(v_rinnovo.team_id)) then
    raise exception using errcode = '42501', message = 'Questo rinnovo non appartiene alla tua squadra.';
  end if;
  if v_rinnovo.stato <> 'in_attesa' then
    raise exception using errcode = '55000', message = 'Questo rinnovo è già stato risolto.';
  end if;
  select * into v_offseason from public.offseasons where id = v_rinnovo.offseason_id;
  if v_offseason.stato <> 'aperta' or now() >= v_offseason.scade_il then
    raise exception using errcode = '55000', message = 'La finestra dei rinnovi è terminata.';
  end if;
  select richiesta_esatta into v_richiesta
  from private.contract_renewal_terms where renewal_id = v_rinnovo.id;

  v_rapporto := p_offerta::numeric / v_richiesta;
  if v_rapporto >= 1 then
    v_accetta := true;
  elsif v_rapporto >= 0.90 then
    v_accetta := random() < least(1, greatest(0, (v_rapporto - 0.90) / 0.10));
  end if;

  select p.nome into v_nome
  from public.player_instances pi join public.players p on p.id = pi.player_id
  where pi.id = v_rinnovo.player_instance_id;

  if v_accetta then
    v_ingaggio := round((p_offerta * (1 + 0.08 * (p_durata - 1)))::numeric / 100000) * 100000;
    update public.player_instances
    set ingaggio = v_ingaggio,
        contratto_scadenza = v_offseason.stagione_a + p_durata - 1
    where id = v_rinnovo.player_instance_id and team_id = v_rinnovo.team_id;
    update public.contract_renewals
    set offerta = p_offerta, durata = p_durata, stato = 'accettato', risolta_il = now()
    where id = v_rinnovo.id;
  else
    update public.player_instances set team_id = null
    where id = v_rinnovo.player_instance_id and team_id = v_rinnovo.team_id;
    update public.contract_renewals
    set offerta = p_offerta, durata = p_durata, stato = 'rifiutato', risolta_il = now()
    where id = v_rinnovo.id;
  end if;

  perform private.notifica(v_user, v_rinnovo.league_id, 'sistema',
    case when v_accetta then 'Rinnovo accettato' else 'Rinnovo rifiutato' end,
    case when v_accetta
      then v_nome || ' ha firmato per ' || p_durata || case when p_durata = 1 then ' anno.' else ' anni.' end
      else v_nome || ' non ha accettato l''offerta ed è ora svincolato.' end,
    jsonb_build_object('player_instance_id', v_rinnovo.player_instance_id, 'rinnovo_id', v_rinnovo.id));

  return jsonb_build_object('id', v_rinnovo.id, 'accettato', v_accetta,
    'ingaggio', case when v_accetta then v_ingaggio else null end);
end;
$$;

revoke all on function public.rispondi_rinnovo(bigint, bigint, smallint) from public, anon, authenticated;
grant execute on function public.rispondi_rinnovo(bigint, bigint, smallint) to authenticated;

create or replace function public.stato_offseason(p_league_id bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
  v_lega public.leagues;
  v_offseason public.offseasons;
  v_squadre jsonb;
begin
  if v_user is null or not (select private.e_membro(p_league_id)) then
    raise exception using errcode = '42501', message = 'Non fai parte di questa lega.';
  end if;
  select * into v_lega from public.leagues where id = p_league_id;
  select * into v_offseason from public.offseasons
  where league_id = p_league_id and stato = 'aperta'
  order by stagione_a desc limit 1;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', t.id, 'nome', t.nome, 'attiva', t.attiva,
    'entrante', t.entrata_stagione = coalesce(v_offseason.stagione_a, v_lega.stagione_corrente + 1),
    'rosa', (select count(*) from public.player_instances pi where pi.team_id = t.id and not pi.ritirato),
    'rinnovi_in_attesa', (select count(*) from public.contract_renewals cr where cr.offseason_id = v_offseason.id and cr.team_id = t.id and cr.stato = 'in_attesa'),
    'draft', (select dts.stato from public.draft_team_state dts where dts.team_id = t.id),
    'budget', t.budget
  ) order by t.attiva desc, t.nome), '[]'::jsonb)
  into v_squadre
  from public.teams t where t.league_id = p_league_id;

  return jsonb_build_object(
    'fase', v_lega.fase_carriera,
    'stagione_corrente', v_lega.stagione_corrente,
    'stagione_prossima', coalesce(v_offseason.stagione_a, v_lega.stagione_corrente + 1),
    'scade_il', v_offseason.scade_il,
    'posti_nuovi', coalesce(v_offseason.posti_nuovi, 0),
    'squadre_attese', v_lega.n_squadre,
    'squadre', v_squadre
  );
end;
$$;

revoke all on function public.stato_offseason(bigint) from public, anon, authenticated;
grant execute on function public.stato_offseason(bigint) to authenticated;

create or replace function public.termina_lega(p_league_id bigint)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
begin
  if not exists (select 1 from public.leagues where id = p_league_id and admin_id = v_user and stato = 'conclusa') then
    raise exception using errcode = '42501', message = 'Solo l''admin può terminare una lega conclusa.';
  end if;
  update public.leagues set fase_carriera = 'terminata' where id = p_league_id;
  return jsonb_build_object('league_id', p_league_id, 'fase', 'terminata');
end;
$$;

revoke all on function public.termina_lega(bigint) from public, anon, authenticated;
grant execute on function public.termina_lega(bigint) to authenticated;

-- ------------------------------------------------------------
--  INGRESSO DI NUOVE SQUADRE DURANTE L'OFF-SEASON
-- ------------------------------------------------------------

create or replace function public.entra_in_lega(
  p_codice text,
  p_nome_squadra text,
  p_stemma_url text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_league public.leagues;
  v_team public.teams;
  v_partecipanti integer;
  v_offseason public.offseasons;
  v_ordine smallint;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'Devi accedere prima di entrare in una lega.';
  end if;
  p_codice := upper(trim(p_codice));
  p_nome_squadra := trim(p_nome_squadra);
  if p_codice !~ '^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{6}$' then
    raise exception using errcode = '22023', message = 'Il codice invito deve contenere 6 caratteri.';
  end if;
  if length(p_nome_squadra) not between 2 and 40 then
    raise exception using errcode = '22023', message = 'Il nome della squadra deve avere da 2 a 40 caratteri.';
  end if;
  if not private.stemma_valido(p_stemma_url, v_user_id) then
    raise exception using errcode = '22023', message = 'Lo stemma selezionato non è valido.';
  end if;

  select * into v_league from public.leagues where codice_invito = p_codice for update;
  if not found then raise exception using errcode = 'P0002', message = 'Codice invito non trovato.'; end if;
  if not (v_league.stato = 'setup' or (v_league.stato = 'stagione' and v_league.fase_carriera = 'offseason')) then
    raise exception using errcode = '55000', message = 'Questa lega non accetta nuovi partecipanti.';
  end if;
  if exists (select 1 from public.teams where league_id = v_league.id and user_id = v_user_id) then
    raise exception using errcode = '23505', message = 'Hai già una squadra in questa lega.';
  end if;
  select count(*) into v_partecipanti from public.teams where league_id = v_league.id and attiva;
  if v_partecipanti >= v_league.n_squadre then
    raise exception using errcode = '54000', message = 'La lega ha già raggiunto il numero massimo di squadre.';
  end if;
  select coalesce(max(ordine_draft), -1) + 1 into v_ordine
  from public.teams where league_id = v_league.id;

  begin
    insert into public.teams(
      league_id, user_id, nome, stemma_url, budget, reroll_rimasti,
      ordine_draft, attiva, entrata_stagione
    ) values (
      v_league.id, v_user_id, p_nome_squadra, p_stemma_url,
      v_league.budget_iniziale, v_league.reroll_draft, v_ordine, true,
      case when v_league.fase_carriera = 'offseason' then v_league.stagione_corrente + 1 else 1 end
    ) returning * into v_team;
  exception when unique_violation then
    raise exception using errcode = '23505', message = 'Questo nome squadra è già usato nella lega.';
  end;

  insert into public.transactions(league_id, team_id, tipo, importo, descrizione, saldo_dopo)
  values (v_league.id, v_team.id, 'dotazione_iniziale', v_league.budget_iniziale,
          case when v_league.fase_carriera = 'offseason'
            then 'Dotazione squadra entrante stagione ' || (v_league.stagione_corrente + 1)
            else 'Dotazione iniziale della lega' end,
          v_league.budget_iniziale);

  if v_league.fase_carriera = 'offseason' then
    select * into v_offseason from public.offseasons
    where league_id = v_league.id and stato = 'aperta' order by stagione_a desc limit 1;
    if not found or now() >= v_offseason.scade_il then
      raise exception using errcode = '55000', message = 'La finestra d''ingresso è terminata.';
    end if;
    insert into public.draft_team_state(team_id, league_id) values (v_team.id, v_league.id);
    insert into public.draft_state(league_id, pick_numero, stato)
    values (v_league.id,
      coalesce((select max(dp.pick_numero) + 1 from public.draft_picks dp where dp.league_id = v_league.id), 0),
      'in_corso')
    on conflict (league_id) do update set stato = 'in_corso', aggiornato_il = now();
    perform private.notifica(v_league.admin_id, v_league.id, 'sistema', 'Nuova squadra iscritta',
      v_team.nome || ' è entrata e può iniziare il draft.', jsonb_build_object('team_id', v_team.id));
  end if;

  return jsonb_build_object('league_id', v_league.id, 'team_id', v_team.id,
    'codice_invito', v_league.codice_invito, 'offseason', v_league.fase_carriera = 'offseason');
end;
$$;

revoke all on function public.entra_in_lega(text, text, text) from public, anon, authenticated;
grant execute on function public.entra_in_lega(text, text, text) to authenticated;

-- In off-season si mostrano venti svincolati al giorno (design §10.6).
create or replace function private.svincolati_da_estrarre(p_league_id bigint)
returns integer language sql stable set search_path = '' as $$
  select case when l.fase_carriera = 'offseason' then 20 else 10 end
  from public.leagues l where l.id = p_league_id;
$$;
revoke all on function private.svincolati_da_estrarre(bigint) from public, anon, authenticated;
grant execute on function private.svincolati_da_estrarre(bigint) to service_role;

-- Il draft indipendente viene riaperto soltanto per le squadre entranti.
create or replace function public.draft_spin(p_league_id bigint)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_user_id uuid := (select auth.uid());
  v_league public.leagues; v_team public.teams; v_state public.draft_team_state; v_club text;
begin
  if v_user_id is null then raise exception using errcode = '42501', message = 'Devi accedere prima di fare SPIN.'; end if;
  select * into v_league from public.leagues where id = p_league_id;
  select * into v_team from public.teams where league_id = p_league_id and user_id = v_user_id and attiva;
  if not found then raise exception using errcode = '42501', message = 'Non hai una squadra attiva in questa lega.'; end if;
  select * into v_state from public.draft_team_state where team_id = v_team.id and league_id = p_league_id for update;
  if not found or v_state.stato <> 'in_corso'
     or not (v_league.stato = 'draft' or (v_league.fase_carriera = 'offseason' and v_team.entrata_stagione = v_league.stagione_corrente + 1)) then
    raise exception using errcode = '55000', message = 'Il tuo draft non è attivo.';
  end if;
  if v_state.club_corrente is not null then return private.draft_payload(p_league_id, v_team.id, v_state.club_corrente); end if;
  select p.club into v_club from public.players p
  where p.campionato = any(v_league.campionati_attivi)
    and not exists (select 1 from public.player_instances pi where pi.league_id = p_league_id and pi.player_id = p.id)
    and v_team.budget - private.ingaggio_teorico(p.overall, p.eta) >= greatest(0, v_league.slot_rosa - (select count(*) from public.player_instances where team_id = v_team.id) - 1) * 500000
    and v_team.budget - private.ingaggio_teorico(p.overall, p.eta) >= greatest(0, v_league.portieri_minimi - (select count(*) from public.player_instances pi join public.players pg on pg.id = pi.player_id where pi.team_id = v_team.id and pg.posizioni[1] = 'GK') - case when p.posizioni[1] = 'GK' then 1 else 0 end) * 500000
    and (v_league.budget_iniziale - v_team.budget) + private.ingaggio_teorico(p.overall, p.eta) <= v_league.budget_iniziale * 0.80
  group by p.club order by random() limit 1;
  if v_club is null then raise exception using errcode = '55000', message = 'Non ci sono più giocatori ingaggiabili nel pool attivo.'; end if;
  update public.draft_team_state set club_corrente = v_club, aggiornato_il = now() where team_id = v_team.id;
  return private.draft_payload(p_league_id, v_team.id, v_club);
end; $$;

create or replace function public.draft_reroll(p_league_id bigint)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare v_user_id uuid := (select auth.uid()); v_team public.teams; v_state public.draft_team_state;
begin
  select * into v_team from public.teams where league_id = p_league_id and user_id = v_user_id and attiva;
  select * into v_state from public.draft_team_state where team_id = v_team.id and league_id = p_league_id for update;
  if not found or v_state.stato <> 'in_corso' then raise exception using errcode = '55000', message = 'Il tuo draft non è attivo.'; end if;
  if v_state.club_corrente is null then raise exception using errcode = '55000', message = 'Devi fare SPIN prima del reroll.'; end if;
  if v_team.reroll_rimasti <= 0 then raise exception using errcode = '55000', message = 'Non hai più reroll disponibili.'; end if;
  update public.teams set reroll_rimasti = reroll_rimasti - 1 where id = v_team.id;
  update public.draft_team_state set club_corrente = null, aggiornato_il = now() where team_id = v_team.id;
  return public.draft_spin(p_league_id);
end; $$;

create or replace function public.draft_pick(p_league_id bigint, p_player_id bigint)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_user_id uuid := (select auth.uid()); v_league public.leagues; v_global public.draft_state;
  v_state public.draft_team_state; v_team public.teams; v_player public.players;
  v_wage bigint; v_picked integer; v_goalkeepers integer; v_new_budget bigint;
  v_instance public.player_instances; v_done boolean;
begin
  select * into v_league from public.leagues where id = p_league_id;
  select * into v_global from public.draft_state where league_id = p_league_id for update;
  if v_user_id is null or not found then raise exception using errcode = '55000', message = 'Il draft non è attivo.'; end if;
  select * into v_team from public.teams where league_id = p_league_id and user_id = v_user_id and attiva;
  if not found then raise exception using errcode = '42501', message = 'Non hai una squadra attiva in questa lega.'; end if;
  if not (v_league.stato = 'draft' or (v_league.fase_carriera = 'offseason' and v_team.entrata_stagione = v_league.stagione_corrente + 1)) then
    raise exception using errcode = '55000', message = 'Il draft non è attivo.';
  end if;
  select * into v_state from public.draft_team_state where team_id = v_team.id and league_id = p_league_id for update;
  if not found or v_state.stato <> 'in_corso' then raise exception using errcode = '55000', message = 'La tua rosa è già completa.'; end if;
  if v_state.club_corrente is null then raise exception using errcode = '55000', message = 'Devi fare SPIN prima di scegliere.'; end if;
  select * into v_player from public.players where id = p_player_id and club = v_state.club_corrente and campionato = any(v_league.campionati_attivi);
  if not found then raise exception using errcode = '22023', message = 'Il giocatore non appartiene al club estratto.'; end if;
  if exists (select 1 from public.player_instances where league_id = p_league_id and player_id = p_player_id) then raise exception using errcode = '23505', message = 'Questo giocatore è già stato scelto.'; end if;
  v_wage := private.ingaggio_teorico(v_player.overall, v_player.eta);
  select count(*)::integer, count(*) filter (where p.posizioni[1] = 'GK')::integer into v_picked, v_goalkeepers
  from public.player_instances pi join public.players p on p.id = pi.player_id where pi.team_id = v_team.id;
  v_new_budget := v_team.budget - v_wage;
  if v_new_budget < greatest(0, v_league.slot_rosa - v_picked - 1) * 500000 + greatest(0, v_league.portieri_minimi - v_goalkeepers - case when v_player.posizioni[1] = 'GK' then 1 else 0 end) * 500000
     or (v_league.budget_iniziale - v_team.budget) + v_wage > v_league.budget_iniziale * 0.80 then
    raise exception using errcode = '22023', message = 'Questo giocatore non è sostenibile per la tua rosa.';
  end if;
  insert into public.player_instances(league_id, player_id, team_id, overall_corrente, eta_corrente, ingaggio)
  values (p_league_id, p_player_id, v_team.id, v_player.overall, v_player.eta, v_wage) returning * into v_instance;
  insert into public.draft_picks(league_id, team_id, player_instance_id, pick_numero, club_estratto, ingaggio_pagato)
  values (p_league_id, v_team.id, v_instance.id, v_global.pick_numero, v_state.club_corrente, v_wage);
  update public.teams set budget = v_new_budget where id = v_team.id;
  insert into public.transactions(league_id, team_id, tipo, importo, descrizione, saldo_dopo)
  values (p_league_id, v_team.id, 'draft_pick', -v_wage, 'Ingaggio draft: ' || v_player.nome, v_new_budget);
  v_done := v_state.pick_numero + 1 >= v_league.slot_rosa;
  update public.draft_team_state set pick_numero = pick_numero + 1, club_corrente = null,
    stato = case when v_done then 'concluso' else 'in_corso' end, aggiornato_il = now() where team_id = v_team.id;
  update public.draft_state set pick_numero = pick_numero + 1, aggiornato_il = now() where league_id = p_league_id;
  if v_league.stato = 'draft' and not exists (select 1 from public.draft_team_state where league_id = p_league_id and stato <> 'concluso') then
    update public.draft_state set stato = 'concluso' where league_id = p_league_id;
    update public.leagues set stato = 'stagione' where id = p_league_id;
  end if;
  return jsonb_build_object('league_id', p_league_id, 'team_id', v_team.id, 'player_instance_id', v_instance.id,
    'ingaggio', v_wage, 'budget', v_new_budget, 'draft_concluso', v_done);
end; $$;

revoke all on function public.draft_spin(bigint), public.draft_reroll(bigint), public.draft_pick(bigint,bigint) from public, anon, authenticated;
grant execute on function public.draft_spin(bigint), public.draft_reroll(bigint), public.draft_pick(bigint,bigint) to authenticated;

-- Calendario delle sole squadre attive; le squadre uscite restano leggibili
-- nelle classifiche storiche delle stagioni precedenti.
create or replace function private.inizializza_stagione(p_league_id bigint)
returns bigint language plpgsql volatile security invoker set search_path = '' as $$
declare
  v_league public.leagues; v_season_id bigint; v_teams bigint[]; v_rotation bigint[]; v_next bigint[];
  v_team_count integer; v_slot_count integer; v_rounds integer; v_giornata integer;
  v_home bigint; v_away bigint; v_swap bigint; v_start date;
begin
  select * into v_league from public.leagues where id = p_league_id for update;
  if not found then raise exception using errcode = 'P0002', message = 'Lega non trovata.'; end if;
  select id into v_season_id from public.seasons where league_id = p_league_id and numero = v_league.stagione_corrente;
  if found then return v_season_id; end if;
  if v_league.stato <> 'stagione' or v_league.fase_carriera <> 'normale' then
    raise exception using errcode = '55000', message = 'La lega non è pronta per iniziare la stagione.';
  end if;
  if exists (
    select 1 from public.draft_team_state dts join public.teams t on t.id = dts.team_id and t.attiva
    where dts.league_id = p_league_id and dts.stato <> 'concluso'
  ) then raise exception using errcode = '55000', message = 'Tutte le nuove squadre devono completare il draft.'; end if;
  select coalesce(array_agg(t.id order by t.ordine_draft nulls last, t.id), array[]::bigint[]), count(*)::integer
  into v_teams, v_team_count from public.teams t where t.league_id = p_league_id and t.attiva;
  if v_team_count <> v_league.n_squadre then raise exception using errcode = '55000', message = 'Il numero di squadre attive non coincide con le impostazioni.'; end if;
  v_start := (clock_timestamp() at time zone 'Europe/Rome')::date + 1;
  insert into public.seasons(league_id, numero, stato, data_inizio, data_fine)
  values (p_league_id, v_league.stagione_corrente, 'in_corso', v_start, v_start + (v_league.giornate_totali - 1))
  returning id into v_season_id;
  insert into public.standings(season_id, league_id, team_id, posizione)
  select v_season_id, p_league_id, t.id, row_number() over(order by t.nome,t.id)::smallint
  from public.teams t where t.league_id = p_league_id and t.attiva;
  v_slot_count := v_team_count + (v_team_count % 2); v_rounds := v_slot_count - 1;
  for v_leg in 1..v_league.n_gironi loop
    v_rotation := v_teams;
    if v_team_count % 2 = 1 then v_rotation := array_append(v_rotation, null::bigint); end if;
    for v_round in 1..v_rounds loop
      v_giornata := (v_leg - 1) * v_rounds + v_round;
      for v_pair in 1..(v_slot_count / 2) loop
        v_home := v_rotation[v_pair]; v_away := v_rotation[v_slot_count-v_pair+1];
        if v_home is null or v_away is null then continue; end if;
        if mod(v_round+v_pair,2)=0 then v_swap:=v_home; v_home:=v_away; v_away:=v_swap; end if;
        if mod(v_leg,2)=0 then v_swap:=v_home; v_home:=v_away; v_away:=v_swap; end if;
        insert into public.fixtures(season_id,league_id,giornata,home_team_id,away_team_id,data_sim)
        values(v_season_id,p_league_id,v_giornata,v_home,v_away,(v_start+(v_giornata-1))::timestamp at time zone 'Europe/Rome');
      end loop;
      v_next := array[v_rotation[1],v_rotation[v_slot_count]];
      for v_index in 2..(v_slot_count-1) loop v_next:=array_append(v_next,v_rotation[v_index]); end loop;
      v_rotation:=v_next;
    end loop;
  end loop;
  return v_season_id;
end; $$;
revoke all on function private.inizializza_stagione(bigint) from public, anon, authenticated;
grant execute on function private.inizializza_stagione(bigint) to service_role;

-- Chiusura atomica: mancati rinnovi = svincolo, ingaggi pagati una volta,
-- controllo rosa e generazione della nuova stagione.
create or replace function public.avvia_prossima_stagione(p_league_id bigint)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_user uuid := (select auth.uid()); v_league public.leagues; v_off public.offseasons;
  v_team record; v_rosa integer; v_gk integer; v_ingaggi bigint; v_season bigint;
begin
  select * into v_league from public.leagues where id=p_league_id for update;
  if not found then raise exception using errcode='P0002',message='Lega non trovata.'; end if;
  if v_league.admin_id<>v_user then raise exception using errcode='42501',message='Solo l''admin può avviare la nuova stagione.'; end if;
  if v_league.fase_carriera<>'offseason' then raise exception using errcode='55000',message='L''off-season non è attiva.'; end if;
  select * into v_off from public.offseasons where league_id=p_league_id and stato='aperta' order by stagione_a desc limit 1 for update;
  if not found then raise exception using errcode='55000',message='Off-season aperta non trovata.'; end if;
  if (select count(*) from public.teams where league_id=p_league_id and attiva)<>v_league.n_squadre then
    raise exception using errcode='55000',message='Mancano ancora squadre per la prossima stagione.';
  end if;
  if exists(select 1 from public.draft_team_state d join public.teams t on t.id=d.team_id and t.attiva
            where d.league_id=p_league_id and t.entrata_stagione=v_off.stagione_a and d.stato<>'concluso') then
    raise exception using errcode='55000',message='Una nuova squadra deve ancora completare il draft.';
  end if;
  update public.player_instances pi set team_id=null
  from public.contract_renewals cr where cr.offseason_id=v_off.id and cr.player_instance_id=pi.id and cr.stato='in_attesa';
  update public.contract_renewals set stato='scaduto',risolta_il=now() where offseason_id=v_off.id and stato='in_attesa';
  for v_team in select * from public.teams where league_id=p_league_id and attiva order by id for update loop
    select count(*)::integer, count(*) filter(where p.posizioni[1]='GK')::integer, coalesce(sum(pi.ingaggio),0)::bigint
    into v_rosa,v_gk,v_ingaggi from public.player_instances pi join public.players p on p.id=pi.player_id where pi.team_id=v_team.id and not pi.ritirato;
    if v_rosa not between 21 and 30 or v_gk<v_league.portieri_minimi then
      raise exception using errcode='55000',message='La rosa di '||v_team.nome||' deve avere 21-30 giocatori e almeno '||v_league.portieri_minimi||' portieri.';
    end if;
    if v_team.budget<v_ingaggi then raise exception using errcode='55000',message='Budget insufficiente per gli ingaggi di '||v_team.nome||'.'; end if;
    update public.teams set budget=budget-v_ingaggi where id=v_team.id;
    insert into public.transactions(league_id,team_id,tipo,importo,descrizione,saldo_dopo)
    values(p_league_id,v_team.id,'ingaggi_stagione',-v_ingaggi,'Ingaggi stagione '||v_off.stagione_a,v_team.budget-v_ingaggi);
  end loop;
  update public.offseasons set stato='conclusa',conclusa_il=now() where id=v_off.id;
  update public.leagues set stagione_corrente=v_off.stagione_a,fase_carriera='normale',offseason_fine=null,stato='stagione' where id=p_league_id;
  v_season:=private.inizializza_stagione(p_league_id);
  return jsonb_build_object('league_id',p_league_id,'season_id',v_season,'stagione',v_off.stagione_a);
end; $$;
revoke all on function public.avvia_prossima_stagione(bigint) from public,anon,authenticated;
grant execute on function public.avvia_prossima_stagione(bigint) to authenticated;
