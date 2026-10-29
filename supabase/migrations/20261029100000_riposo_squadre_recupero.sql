-- Squadre che riposano (primi turni dei playoff, turni di riposo delle leghe dispari): il tempo deve passare lo stesso.
-- Prima il recupero (condizione, infortuni, reparto medico) girava solo dentro la simulazione delle partite, quindi
-- una squadra senza partita restava ferma: infortunati ancora fuori, stanchi ancora stanchi.
-- Chi riposa recupera come un giocatore in tribuna (REC_TRIBUNA = 45 in engine/config.js) e gli infortuni scalano di
-- una giornata, con la possibilita' in piu' del reparto medico (stessa funzione delle squadre che giocano).
-- Squalifiche e ammonizioni NON passano: si scontano in partite, non in giorni.
-- Allenamenti, cambi ruolo, specializzazioni, vivaio e crescita erano gia' a livello di lega: non cambiano.

create table if not exists private.riposo_applicato (
  league_id bigint not null,
  giornata integer not null,
  team_id bigint not null,
  applicato_il timestamptz not null default now(),
  primary key (league_id, giornata, team_id)
);

create or replace function public.applica_riposo_squadre(p_league_id bigint, p_giornata integer)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_valori jsonb;
  v_squadre integer;
  v_stagione bigint;
begin
  select id into v_stagione from public.seasons where league_id = p_league_id and stato = 'in_corso' order by numero desc limit 1;
  if v_stagione is null then return 0; end if;

  -- Solo se la lega ha davvero una giornata con quel numero (altrimenti nessuno "riposa", e' solo una giornata che non esiste).
  if not exists (select 1 from public.fixtures f where f.season_id = v_stagione and f.giornata = p_giornata) then
    return 0;
  end if;

  with riposano as (
    select t.id
    from public.teams t
    where t.league_id = p_league_id and t.attiva
      and not exists (
        select 1 from public.fixtures f
        where f.season_id = v_stagione and f.giornata = p_giornata
          and (f.home_team_id = t.id or f.away_team_id = t.id))
  ), nuovi as (
    insert into private.riposo_applicato (league_id, giornata, team_id)
    select p_league_id, p_giornata, r.id from riposano r
    on conflict do nothing
    returning team_id
  )
  select count(*)::int,
         jsonb_agg(jsonb_build_object(
           'id', pi.id,
           'condizione', case
              when pi.infortunato_fino_a > 0 then (case when pi.infortunato_fino_a = 1 then 65 else pi.condizione end)
              else least(100, pi.condizione + 45) end,
           'infortunato_fino_a', greatest(0, pi.infortunato_fino_a - 1)))
  into v_squadre, v_valori
  from nuovi n join public.player_instances pi on pi.team_id = n.team_id and not pi.ritirato;

  if v_valori is not null then
    perform public.aggiorna_condizione_rosa(p_league_id, v_valori);
  end if;
  return coalesce(jsonb_array_length(v_valori), 0);
end $$;

revoke all on function public.applica_riposo_squadre(bigint, integer) from public, anon, authenticated;
grant execute on function public.applica_riposo_squadre(bigint, integer) to service_role;
