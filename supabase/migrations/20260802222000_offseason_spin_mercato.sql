-- Off-season: 5 spin diretti per squadra.
-- Uno spin propone un giocatore libero; la squadra puo' ingaggiarlo subito
-- oppure spedirlo nella lista svincolati del giorno.

alter table public.free_agent_auctions
  add column if not exists origine text not null default 'estrazione';

alter table public.free_agent_auctions
  drop constraint if exists free_agent_auctions_origine_check;

alter table public.free_agent_auctions
  add constraint free_agent_auctions_origine_check
  check (origine in ('estrazione', 'spin_offseason'));

create table public.offseason_spins (
  id              bigint generated always as identity primary key,
  offseason_id    bigint not null,
  league_id       bigint not null,
  team_id         bigint not null,
  player_id       bigint not null references public.players(id) on delete restrict,
  stato           text not null default 'proposto'
                  check (stato in ('proposto', 'ingaggiato', 'asta')),
  ingaggio        bigint not null check (ingaggio >= 500000),
  creata_il       timestamptz not null default now(),
  risolta_il      timestamptz,
  constraint offseason_spins_offseason_fk
    foreign key (offseason_id, league_id)
    references public.offseasons(id, league_id) on delete cascade,
  constraint offseason_spins_team_fk
    foreign key (team_id, league_id)
    references public.teams(id, league_id) on delete cascade,
  unique (offseason_id, team_id, player_id)
);

create unique index offseason_spins_uno_aperto_idx
  on public.offseason_spins(offseason_id, team_id)
  where stato = 'proposto';

create index offseason_spins_team_idx on public.offseason_spins(team_id, stato, id desc);
create index offseason_spins_player_idx on public.offseason_spins(league_id, player_id);

alter table public.offseason_spins enable row level security;

create policy offseason_spins_lettura_mia on public.offseason_spins
  for select to authenticated
  using ((select private.e_mia_squadra(team_id)));

grant select on public.offseason_spins to authenticated;
grant select, insert, update, delete on public.offseason_spins to service_role;
revoke all on public.offseason_spins from anon;

create or replace function private.offseason_spin_corrente(p_league_id bigint, p_user_id uuid)
returns table(v_league public.leagues, v_offseason public.offseasons, v_team public.teams)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return query
  select l, o, t
  from public.leagues l
  join public.offseasons o on o.league_id = l.id and o.stato = 'aperta'
  join public.teams t on t.league_id = l.id and t.user_id = p_user_id and t.attiva
  where l.id = p_league_id
    and l.fase_carriera = 'offseason'
    and now() < o.scade_il
  order by o.stagione_a desc
  limit 1;
end;
$$;

revoke all on function private.offseason_spin_corrente(bigint, uuid) from public, anon, authenticated;
grant execute on function private.offseason_spin_corrente(bigint, uuid) to service_role;

create or replace function public.stato_spin_offseason(p_league_id bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
  v_ctx record;
  v_usati integer;
  v_spin jsonb;
begin
  if v_user is null then
    raise exception using errcode = '42501', message = 'Devi accedere per usare gli spin off-season.';
  end if;

  select * into v_ctx from private.offseason_spin_corrente(p_league_id, v_user);
  if not found then
    return jsonb_build_object('attivo', false, 'rimasti', 0, 'spin', '[]'::jsonb);
  end if;

  select count(*)::integer into v_usati
  from public.offseason_spins
  where offseason_id = (v_ctx.v_offseason).id
    and team_id = (v_ctx.v_team).id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', s.id,
    'player_id', s.player_id,
    'stato', s.stato,
    'ingaggio', s.ingaggio,
    'nome', p.nome,
    'club', p.club,
    'ruolo', p.posizioni[1],
    'overall', p.overall,
    'eta', p.eta
  ) order by s.id desc), '[]'::jsonb)
  into v_spin
  from public.offseason_spins s
  join public.players p on p.id = s.player_id
  where s.offseason_id = (v_ctx.v_offseason).id
    and s.team_id = (v_ctx.v_team).id;

  return jsonb_build_object(
    'attivo', true,
    'rimasti', greatest(5 - v_usati, 0),
    'usati', v_usati,
    'spin', v_spin
  );
end;
$$;

revoke all on function public.stato_spin_offseason(bigint) from public, anon, authenticated;
grant execute on function public.stato_spin_offseason(bigint) to authenticated;

create or replace function public.spin_offseason(p_league_id bigint)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
  v_ctx record;
  v_usati integer;
  v_rosa integer;
  v_impegnati integer;
  v_budget_disponibile bigint;
  v_player public.players;
  v_ingaggio bigint;
  v_spin public.offseason_spins;
begin
  if v_user is null then
    raise exception using errcode = '42501', message = 'Devi accedere per usare gli spin off-season.';
  end if;

  select * into v_ctx from private.offseason_spin_corrente(p_league_id, v_user);
  if not found then
    raise exception using errcode = '55000', message = 'Gli spin off-season non sono attivi.';
  end if;

  if exists (
    select 1 from public.offseason_spins
    where offseason_id = (v_ctx.v_offseason).id
      and team_id = (v_ctx.v_team).id
      and stato = 'proposto'
  ) then
    raise exception using errcode = '55000', message = 'Hai gia'' uno spin aperto: ingaggialo o mandalo al mercato.';
  end if;

  select count(*)::integer into v_usati
  from public.offseason_spins
  where offseason_id = (v_ctx.v_offseason).id
    and team_id = (v_ctx.v_team).id;
  if v_usati >= 5 then
    raise exception using errcode = '54000', message = 'Hai gia'' usato tutti e 5 gli spin off-season.';
  end if;

  select count(*)::integer into v_rosa
  from public.player_instances
  where team_id = (v_ctx.v_team).id;
  v_impegnati := private.slot_impegnati((v_ctx.v_team).id);
  if v_rosa + v_impegnati + 1 > private.rosa_massima() then
    raise exception using errcode = '22023', message = 'Non hai posti liberi per usare uno spin.';
  end if;

  v_budget_disponibile := (v_ctx.v_team).budget - private.budget_impegnato((v_ctx.v_team).id);

  select p.* into v_player
  from public.players p
  where p.campionato = any((v_ctx.v_league).campionati_attivi)
    and v_budget_disponibile >= private.ingaggio_teorico(p.overall, p.eta)
    and not exists (
      select 1 from public.player_instances pi
      where pi.league_id = p_league_id
        and pi.player_id = p.id
        and pi.team_id is not null
    )
    and not exists (
      select 1 from public.free_agent_auctions a
      where a.league_id = p_league_id
        and a.player_id = p.id
        and a.stato = 'aperta'
    )
    and not exists (
      select 1 from public.offseason_spins s
      where s.league_id = p_league_id
        and s.player_id = p.id
    )
  order by random()
  limit 1;

  if not found then
    raise exception using errcode = '55000', message = 'Non ci sono giocatori sostenibili disponibili per gli spin.';
  end if;

  v_ingaggio := private.ingaggio_teorico(v_player.overall, v_player.eta);
  insert into public.offseason_spins(offseason_id, league_id, team_id, player_id, ingaggio)
  values ((v_ctx.v_offseason).id, p_league_id, (v_ctx.v_team).id, v_player.id, v_ingaggio)
  returning * into v_spin;

  return public.stato_spin_offseason(p_league_id);
end;
$$;

revoke all on function public.spin_offseason(bigint) from public, anon, authenticated;
grant execute on function public.spin_offseason(bigint) to authenticated;

create or replace function public.ingaggia_spin_offseason(p_spin_id bigint)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
  v_spin public.offseason_spins;
  v_team public.teams;
  v_league public.leagues;
  v_player public.players;
  v_instance public.player_instances;
  v_rosa integer;
  v_budget_impegnato bigint;
begin
  if v_user is null then
    raise exception using errcode = '42501', message = 'Devi accedere per ingaggiare dallo spin.';
  end if;

  select * into v_spin from public.offseason_spins where id = p_spin_id for update;
  if not found or v_spin.stato <> 'proposto' then
    raise exception using errcode = '55000', message = 'Questo spin non e'' piu'' ingaggiabile.';
  end if;
  select * into v_team from public.teams where id = v_spin.team_id and user_id = v_user and attiva for update;
  if not found then
    raise exception using errcode = '42501', message = 'Questo spin non appartiene alla tua squadra.';
  end if;
  select * into v_league from public.leagues where id = v_spin.league_id for update;
  if v_league.fase_carriera <> 'offseason' or now() >= v_league.offseason_fine then
    raise exception using errcode = '55000', message = 'La finestra off-season e'' terminata.';
  end if;
  select * into v_player from public.players where id = v_spin.player_id;

  if exists (
    select 1 from public.player_instances
    where league_id = v_spin.league_id
      and player_id = v_spin.player_id
      and team_id is not null
  ) then
    raise exception using errcode = '23505', message = 'Questo giocatore e'' gia'' stato preso.';
  end if;

  select count(*)::integer into v_rosa from public.player_instances where team_id = v_team.id;
  if v_rosa + private.slot_impegnati(v_team.id) + 1 > private.rosa_massima() then
    raise exception using errcode = '22023', message = 'Non hai posti liberi in rosa.';
  end if;

  v_budget_impegnato := private.budget_impegnato(v_team.id);
  if v_team.budget - v_budget_impegnato < v_spin.ingaggio then
    raise exception using errcode = '22023', message = 'Budget insufficiente per ingaggiare questo giocatore.';
  end if;

  insert into public.player_instances
    (league_id, player_id, team_id, overall_corrente, eta_corrente, ingaggio)
  values (v_spin.league_id, v_spin.player_id, null, v_player.overall, v_player.eta, v_spin.ingaggio)
  on conflict (league_id, player_id) do nothing;

  update public.player_instances
  set team_id = v_team.id,
      ingaggio = v_spin.ingaggio,
      overall_corrente = coalesce(overall_corrente, v_player.overall),
      eta_corrente = coalesce(eta_corrente, v_player.eta)
  where league_id = v_spin.league_id
    and player_id = v_spin.player_id
    and team_id is null
  returning * into v_instance;

  if not found then
    raise exception using errcode = '55000', message = 'Il giocatore non e'' piu'' disponibile.';
  end if;

  update public.teams
  set budget = budget - v_spin.ingaggio
  where id = v_team.id;

  insert into public.transactions(league_id, team_id, tipo, importo, descrizione, saldo_dopo)
  values (v_spin.league_id, v_team.id, 'spin_offseason', -v_spin.ingaggio,
          'Spin off-season: ' || v_player.nome,
          (select budget from public.teams where id = v_team.id));

  update public.offseason_spins
  set stato = 'ingaggiato', risolta_il = now()
  where id = v_spin.id;

  perform private.notifica(v_team.user_id, v_spin.league_id, 'mercato_esito',
    'Spin ingaggiato', v_player.nome || ' entra nella tua rosa.',
    jsonb_build_object('player_instance_id', v_instance.id, 'player_id', v_player.id));

  return public.stato_spin_offseason(v_spin.league_id);
end;
$$;

revoke all on function public.ingaggia_spin_offseason(bigint) from public, anon, authenticated;
grant execute on function public.ingaggia_spin_offseason(bigint) to authenticated;

create or replace function public.manda_spin_al_mercato(p_spin_id bigint)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
  v_spin public.offseason_spins;
  v_team public.teams;
  v_league public.leagues;
  v_asta_id bigint;
  v_giorno date := (now() at time zone 'Europe/Rome')::date;
begin
  if v_user is null then
    raise exception using errcode = '42501', message = 'Devi accedere per usare gli spin off-season.';
  end if;

  select * into v_spin from public.offseason_spins where id = p_spin_id for update;
  if not found or v_spin.stato <> 'proposto' then
    raise exception using errcode = '55000', message = 'Questo spin non puo'' essere mandato al mercato.';
  end if;
  select * into v_team from public.teams where id = v_spin.team_id and user_id = v_user and attiva;
  if not found then
    raise exception using errcode = '42501', message = 'Questo spin non appartiene alla tua squadra.';
  end if;
  select * into v_league from public.leagues where id = v_spin.league_id;
  if v_league.fase_carriera <> 'offseason' or now() >= v_league.offseason_fine then
    raise exception using errcode = '55000', message = 'La finestra off-season e'' terminata.';
  end if;
  if exists (
    select 1 from public.player_instances
    where league_id = v_spin.league_id
      and player_id = v_spin.player_id
      and team_id is not null
  ) then
    raise exception using errcode = '23505', message = 'Questo giocatore e'' gia'' stato preso.';
  end if;

  insert into public.free_agent_auctions(league_id, giorno, player_id, ingaggio_teorico, origine)
  values (v_spin.league_id, v_giorno, v_spin.player_id, v_spin.ingaggio, 'spin_offseason')
  on conflict (league_id, giorno, player_id) do nothing
  returning id into v_asta_id;

  if v_asta_id is null then
    select id into v_asta_id
    from public.free_agent_auctions
    where league_id = v_spin.league_id
      and giorno = v_giorno
      and player_id = v_spin.player_id;
  end if;

  insert into private.auction_thresholds(auction_id, soglia)
  values (v_asta_id, round(v_spin.ingaggio * (0.90 + random() * 0.20)))
  on conflict (auction_id) do nothing;

  update public.offseason_spins
  set stato = 'asta', risolta_il = now()
  where id = v_spin.id;

  return public.stato_spin_offseason(v_spin.league_id);
end;
$$;

revoke all on function public.manda_spin_al_mercato(bigint) from public, anon, authenticated;
grant execute on function public.manda_spin_al_mercato(bigint) to authenticated;

-- L'estrazione giornaliera dei 20 svincolati deve convivere con gli spin
-- gia' mandati al mercato: una riga `origine = spin_offseason` non conta
-- come estrazione giornaliera gia' eseguita.
create or replace function private.estrai_svincolati_lega(
  p_league_id bigint,
  p_giorno    date
)
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_lega    public.leagues;
  v_quanti  integer;
  v_creati  integer := 0;
  v_asta    record;
begin
  select * into v_lega from public.leagues where id = p_league_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Lega inesistente.';
  end if;

  if exists (
    select 1 from public.free_agent_auctions a
    where a.league_id = p_league_id
      and a.giorno = p_giorno
      and a.origine = 'estrazione'
  ) then
    return 0;
  end if;

  v_quanti := private.svincolati_da_estrarre(p_league_id);

  with disponibili as (
    select p.id, p.eta
    from public.players p
    where p.campionato = any(v_lega.campionati_attivi)
      and not exists (
        select 1 from public.player_instances pi
        where pi.league_id = p_league_id
          and pi.player_id = p.id
          and pi.team_id is not null
      )
      and not exists (
        select 1 from public.free_agent_auctions a
        where a.league_id = p_league_id
          and a.giorno = p_giorno
          and a.player_id = p.id
      )
      and not exists (
        select 1 from public.offseason_spins s
        where s.league_id = p_league_id
          and s.player_id = p.id
          and s.stato = 'proposto'
      )
  ),
  giovani as (
    select id from disponibili where eta < 20 order by random() limit 3
  ),
  resto as (
    select id from disponibili
    where id not in (select id from giovani)
    order by random()
    limit greatest(v_quanti - (select count(*) from giovani), 0)
  ),
  scelti as (
    select id from giovani union all select id from resto
  )
  insert into public.free_agent_auctions (league_id, giorno, player_id, ingaggio_teorico, origine)
  select p_league_id, p_giorno, p.id, private.ingaggio_teorico(p.overall, p.eta), 'estrazione'
  from public.players p join scelti s on s.id = p.id;

  get diagnostics v_creati = row_count;

  for v_asta in
    select a.id, a.ingaggio_teorico
    from public.free_agent_auctions a
    where a.league_id = p_league_id and a.giorno = p_giorno
  loop
    insert into private.auction_thresholds (auction_id, soglia)
    values (v_asta.id, round(v_asta.ingaggio_teorico * (0.90 + random() * 0.20)))
    on conflict (auction_id) do nothing;
  end loop;

  return v_creati;
end;
$$;

revoke all on function private.estrai_svincolati_lega(bigint, date) from public, anon, authenticated;
grant execute on function private.estrai_svincolati_lega(bigint, date) to service_role;
