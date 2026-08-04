-- Gli esterni da 75+ mantengono il campionato di origine ma sono pescabili in
-- ogni lega, anche quando quel campionato non e' fra quelli configurati.
alter table public.players
  add column elite_globale boolean not null default false;

comment on column public.players.elite_globale is
  'Giocatore OVR 75+ importato da un campionato esterno: disponibile in ogni pool di lega.';

create index players_elite_globale_idx
  on public.players (overall desc)
  where elite_globale and disponibile_estrazione;

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
  v_lega      public.leagues;
  v_per_ruolo integer;
  v_tornata   integer;
  v_creati    integer := 0;
  v_asta      record;
begin
  select * into v_lega from public.leagues where id = p_league_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Lega inesistente.';
  end if;
  select coalesce(max(a.tornata), 0) + 1 into v_tornata
  from public.free_agent_auctions a
  where a.league_id = p_league_id and a.giorno = p_giorno and a.origine = 'estrazione';
  v_per_ruolo := private.svincolati_per_ruolo(p_league_id);

  with disponibili as (
    select p.id, private.macro_ruolo(p.posizioni) as macro
    from public.players p
    where p.disponibile_estrazione
      and (p.elite_globale or p.campionato = any(v_lega.campionati_attivi))
      and private.macro_ruolo(p.posizioni) in ('GK', 'DEF', 'MID', 'ATT')
      and not exists (
        select 1 from public.player_instances pi
        where pi.league_id = p_league_id and pi.player_id = p.id and pi.team_id is not null
      )
      and not exists (
        select 1 from public.retired_players rp
        where rp.league_id = p_league_id and rp.player_id = p.id
      )
      and not exists (
        select 1 from public.free_agent_auctions a
        where a.league_id = p_league_id and a.giorno = p_giorno and a.player_id = p.id
      )
      and not exists (
        select 1 from public.offseason_spins s
        where s.league_id = p_league_id and s.player_id = p.id and s.stato = 'proposto'
      )
  ), ranked as (
    select id, macro, row_number() over (partition by macro order by random()) as rn from disponibili
  ), scelti as (
    select id from ranked where rn <= v_per_ruolo
  )
  insert into public.free_agent_auctions
    (league_id, giorno, player_id, ingaggio_teorico, origine, tornata)
  select p_league_id, p_giorno, p.id,
         private.ingaggio_teorico(p.overall, p.eta), 'estrazione', v_tornata
  from public.players p join scelti s on s.id = p.id;

  get diagnostics v_creati = row_count;
  for v_asta in
    select a.id, a.ingaggio_teorico from public.free_agent_auctions a
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

create or replace function private.pesca_carta_ruolo(
  p_league public.leagues,
  p_ruolo text
) returns bigint
language sql
stable
set search_path = ''
as $$
  select p.id
  from public.players p
  where p.disponibile_estrazione
    and (p.elite_globale or p.campionato = any(p_league.campionati_attivi))
    and private.macro_ruolo(p.posizioni) = p_ruolo
    and not exists (
      select 1 from public.player_instances pi
      where pi.league_id = p_league.id and pi.player_id = p.id
    )
    and not exists (
      select 1 from public.retired_players rp
      where rp.league_id = p_league.id and rp.player_id = p.id
    )
  order by random()
  limit 1;
$$;

revoke all on function private.pesca_carta_ruolo(public.leagues, text)
  from public, anon, authenticated;
grant execute on function private.pesca_carta_ruolo(public.leagues, text)
  to service_role;

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
    where offseason_id = (v_ctx.v_offseason).id and team_id = (v_ctx.v_team).id and stato = 'proposto'
  ) then
    raise exception using errcode = '55000', message = 'Hai gia'' uno spin aperto: ingaggialo o mandalo al mercato.';
  end if;
  select count(*)::integer into v_usati
  from public.offseason_spins
  where offseason_id = (v_ctx.v_offseason).id and team_id = (v_ctx.v_team).id;
  if v_usati >= 5 then
    raise exception using errcode = '54000', message = 'Hai gia'' usato tutti e 5 gli spin off-season.';
  end if;
  select count(*)::integer into v_rosa from public.player_instances where team_id = (v_ctx.v_team).id;
  v_impegnati := private.slot_impegnati((v_ctx.v_team).id);
  if v_rosa + v_impegnati + 1 > private.rosa_massima() then
    raise exception using errcode = '22023', message = 'Non hai posti liberi per usare uno spin.';
  end if;
  v_budget_disponibile := (v_ctx.v_team).budget - private.budget_impegnato((v_ctx.v_team).id);

  select p.* into v_player
  from public.players p
  where p.disponibile_estrazione
    and (p.elite_globale or p.campionato = any((v_ctx.v_league).campionati_attivi))
    and v_budget_disponibile >= private.ingaggio_teorico(p.overall, p.eta)
    and not exists (
      select 1 from public.player_instances pi
      where pi.league_id = p_league_id and pi.player_id = p.id and pi.team_id is not null
    )
    and not exists (
      select 1 from public.retired_players rp
      where rp.league_id = p_league_id and rp.player_id = p.id
    )
    and not exists (
      select 1 from public.free_agent_auctions a
      where a.league_id = p_league_id and a.player_id = p.id and a.stato = 'aperta'
    )
    and not exists (
      select 1 from public.offseason_spins s
      where s.league_id = p_league_id and s.player_id = p.id
    )
  order by random()
  limit 1;
  if not found then
    raise exception using errcode = '55000', message = 'Non ci sono giocatori sostenibili disponibili per gli spin.';
  end if;
  v_ingaggio := private.ingaggio_teorico(v_player.overall, v_player.eta);
  insert into public.offseason_spins(offseason_id, league_id, team_id, player_id, ingaggio)
  values ((v_ctx.v_offseason).id, p_league_id, (v_ctx.v_team).id, v_player.id, v_ingaggio);
  return public.stato_spin_offseason(p_league_id);
end;
$$;

revoke all on function public.spin_offseason(bigint) from public, anon, authenticated;
grant execute on function public.spin_offseason(bigint) to authenticated;
