-- Mercato svincolati: estrazione bilanciata per macro-ruolo.
-- Stagione normale: 3 GK, 3 DEF, 3 MID, 3 ATT = 12.
-- Off-season: 10 per macro-ruolo = 40.

create or replace function private.macro_ruolo(p_posizioni text[])
returns text
language sql
immutable
security invoker
set search_path = ''
as $$
  select case
    when p_posizioni && array['GK']::text[] then 'GK'
    when p_posizioni && array['CB','LB','RB','LWB','RWB']::text[] then 'DEF'
    when p_posizioni && array['CDM','CM','CAM','LM','RM']::text[] then 'MID'
    when p_posizioni && array['ST','CF','LW','RW']::text[] then 'ATT'
    else 'MID'
  end;
$$;

revoke all on function private.macro_ruolo(text[]) from public, anon, authenticated;
grant execute on function private.macro_ruolo(text[]) to service_role;

create or replace function private.svincolati_per_ruolo(p_league_id bigint)
returns integer
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_lega public.leagues;
begin
  select * into v_lega from public.leagues where id = p_league_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Lega inesistente.';
  end if;
  if v_lega.fase_carriera = 'offseason' then
    return 10;
  end if;
  return 3;
end;
$$;

revoke all on function private.svincolati_per_ruolo(bigint) from public, anon, authenticated;
grant execute on function private.svincolati_per_ruolo(bigint) to service_role;

create or replace function private.svincolati_da_estrarre(p_league_id bigint)
returns integer
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return private.svincolati_per_ruolo(p_league_id) * 4;
end;
$$;

revoke all on function private.svincolati_da_estrarre(bigint) from public, anon, authenticated;
grant execute on function private.svincolati_da_estrarre(bigint) to service_role;

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
  v_per_ruolo integer;
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

  v_per_ruolo := private.svincolati_per_ruolo(p_league_id);

  with disponibili as (
    select p.id, p.overall, p.eta, private.macro_ruolo(p.posizioni) as macro
    from public.players p
    where p.campionato = any(v_lega.campionati_attivi)
      and private.macro_ruolo(p.posizioni) in ('GK', 'DEF', 'MID', 'ATT')
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
  ranked as (
    select id, macro,
           row_number() over (partition by macro order by random()) as rn
    from disponibili
  ),
  scelti as (
    select id
    from ranked
    where rn <= v_per_ruolo
  )
  insert into public.free_agent_auctions (league_id, giorno, player_id, ingaggio_teorico, origine)
  select p_league_id, p_giorno, p.id, private.ingaggio_teorico(p.overall, p.eta), 'estrazione'
  from public.players p
  join scelti s on s.id = p.id;

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
