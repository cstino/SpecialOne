-- ============================================================
--  MERCATO A SCELTE: POOL A 30 CON 24 SQUADRE (5 ottobre 2026)
--  Corregge 20261005080000: il committente preferisce 30 eleggibili invece di 35.
--    - giocatori di movimento per ruolo: max(6, squadre/3)  -> 6 fino a 20 squadre, 8 a 24;
--    - portieri: max(5, ceil(squadre/4))                    -> 5 fino a 20 squadre, 6 a 24.
--  Con 24 squadre: 6 portieri + 8 difensori + 8 centrocampisti + 8 attaccanti = 30.
--  Fino a 16 squadre resta 23 (5 + 6 + 6 + 6), come prima: nessun cambiamento
--  per Real Fampionato e le altre leghe. La dimensione si fissa quando la
--  finestra viene svelata, quindi le finestre gia' estratte non cambiano.
-- ============================================================

create or replace function private.eleggibili_per_ruolo(p_squadre integer)
returns integer
language sql
immutable
set search_path = ''
as $$
  select greatest(6, p_squadre / 3)
$$;

create or replace function private.eleggibili_portieri(p_squadre integer)
returns integer
language sql
immutable
set search_path = ''
as $$
  select greatest(5, ceil(p_squadre / 4.0)::integer)
$$;

CREATE OR REPLACE FUNCTION private.estrai_pool_scelte(p_league_id bigint, p_stagione smallint, p_finestra text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_lega public.leagues;
  v_creati integer := 0;
  v_per_ruolo integer;
  v_portieri integer;
  v_squadre integer;
begin
  if p_finestra not in ('on', 'off') then
    raise exception using errcode = '22023', message = 'Finestra non valida.';
  end if;
  select * into v_lega from public.leagues where id = p_league_id;
  select count(*)::integer into v_squadre from public.teams where league_id = p_league_id and attiva;
  v_per_ruolo := private.eleggibili_per_ruolo(v_squadre);
  v_portieri := private.eleggibili_portieri(v_squadre);
  if not found then
    raise exception using errcode = 'P0002', message = 'Lega non trovata.';
  end if;
  if exists (select 1 from public.scelte_pool where league_id = p_league_id and stagione = p_stagione and finestra = p_finestra) then
    return 0;
  end if;

  with disponibili as (
    select p.id, private.macro_ruolo(p.posizioni) as macro,
           coalesce(fap.overall_corrente, p.overall) as overall_attuale,
           coalesce(fap.eta_corrente, p.eta) as eta_attuale
    from public.players p
    left join public.free_agent_progression fap
      on fap.league_id = p_league_id and fap.player_id = p.id
    where p.disponibile_estrazione
      and coalesce(fap.overall_corrente, p.overall) > 75
      and (p.elite_globale or p.campionato = any(v_lega.campionati_attivi))
      and private.macro_ruolo(p.posizioni) in ('GK', 'DEF', 'MID', 'ATT')
      and not exists (
        select 1 from public.player_instances pi
        where pi.league_id = p_league_id and pi.player_id = p.id
      )
      and not exists (
        select 1 from public.retired_players rp
        where rp.league_id = p_league_id and rp.player_id = p.id
      )
  ), ranked as (
    select id, macro, overall_attuale, eta_attuale,
           row_number() over (partition by macro order by random()) as rn
    from disponibili
  ), scelti as (
    select id, overall_attuale, eta_attuale from ranked
    where (macro = 'GK' and rn <= v_portieri) or (macro <> 'GK' and rn <= v_per_ruolo)
  )
  insert into public.scelte_pool (league_id, stagione, finestra, player_id, ingaggio_teorico)
  select p_league_id, p_stagione, p_finestra, s.id, private.ingaggio_teorico(s.overall_attuale, s.eta_attuale)
  from scelti s;

  get diagnostics v_creati = row_count;
  return v_creati;
end;
$function$;
