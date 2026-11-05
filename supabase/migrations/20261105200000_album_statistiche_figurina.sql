-- Figurine: statistiche e ruoli fotografati con l'overall (docs/DIARIO-SEASON3.md §8-9).
-- La card FUT mostrava l'overall della figurina ma le sei statistiche del catalogo FC 26: per un giocatore cresciuto
-- o calato i numeri non tornavano. Ora la figurina tiene le statistiche calcolate come nella scheda giocatore
-- (private.attributi_istanza: crescita e piano di allenamento) all'overall della figurina, e i ruoli di quel momento
-- (cambio ruolo compreso).

alter table public.album_figurine
  add column if not exists statistiche jsonb,
  add column if not exists posizioni text[];

-- Le dodici voci che la card puo' mostrare (sei per i giocatori di movimento, sei per i portieri).
create or replace function private.album_statistiche(p_attributi jsonb)
returns jsonb
language sql
immutable
set search_path to ''
as $$
  select coalesce(jsonb_object_agg(k, p_attributi->k), '{}'::jsonb)
  from unnest(array['pace','shooting','passing','dribbling_generale','defending','physic',
                    'gk_diving','gk_handling','gk_kicking','gk_reflexes','goalkeeping_speed','gk_positioning']) as k
  where p_attributi ? k
$$;

CREATE OR REPLACE FUNCTION private.album_sincronizza(p_league_id bigint)
 RETURNS smallint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_stag smallint;
  v_prima boolean;
  v_conf boolean;
begin
  select stagione_corrente, coalesce(conferenze_attive, false) into v_stag, v_conf from public.leagues where id = p_league_id;
  v_prima := not exists (select 1 from public.album_figurine where league_id = p_league_id and stagione = v_stag);
  insert into public.album_figurine (league_id, stagione, tipo, team_id)
  select p_league_id, v_stag, 'stemma', t.id from public.teams t where t.league_id = p_league_id and t.attiva
  on conflict do nothing;
  insert into public.album_figurine (league_id, stagione, tipo, team_id, player_id, overall, aggiornamento, statistiche, posizioni)
  select p_league_id, v_stag, 'giocatore', pi.team_id, pi.player_id, pi.overall_corrente, not v_prima,
    private.album_statistiche(private.attributi_istanza(
      p.attributi, coalesce(pi.posizioni_override, p.posizioni), pi.overall_corrente, p.overall,
      pi.piano_scostamenti, pi.specializzazione_attiva, pi.piano_overall_rif)),
    coalesce(pi.posizioni_override, p.posizioni)
  from public.player_instances pi join public.teams t on t.id = pi.team_id and t.attiva
  join public.players p on p.id = pi.player_id
  where pi.league_id = p_league_id and not pi.ritirato
  on conflict do nothing;
  if v_conf then
    insert into public.album_figurine (league_id, stagione, tipo, conferenza)
    values (p_league_id, v_stag, 'conferenza', 'est'), (p_league_id, v_stag, 'conferenza', 'ovest')
    on conflict do nothing;
  end if;
  return v_stag;
end $function$;

-- Figurine gia' esistenti: statistiche all'overall salvato nella figurina, con il piano e i ruoli di oggi
-- (quelli di allora non sono stati conservati: e' l'approssimazione migliore disponibile).
update public.album_figurine af
set statistiche = private.album_statistiche(private.attributi_istanza(
      p.attributi, coalesce(pi.posizioni_override, p.posizioni), af.overall, p.overall,
      pi.piano_scostamenti, pi.specializzazione_attiva, pi.piano_overall_rif)),
    posizioni = coalesce(pi.posizioni_override, p.posizioni)
from public.players p
left join public.player_instances pi on pi.player_id = p.id
where af.tipo = 'giocatore' and af.statistiche is null and p.id = af.player_id
  and (pi.id is null or pi.league_id = af.league_id);
