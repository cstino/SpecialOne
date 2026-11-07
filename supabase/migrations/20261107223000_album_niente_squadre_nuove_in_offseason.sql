-- Album: le squadre entrate in off-season non finiscono nell'album della stagione appena chiusa (segnalazione del
-- committente, 7/11/2026: in Serie F l'album Season 2 mostrava gia' le quattro squadre nuove della Season 3).
-- Funzione dalla definizione viva; in off-season entra solo chi ha una riga in classifica di quella stagione.

create or replace function private.album_in_stagione(p_league_id bigint, p_stagione smallint, p_team_id bigint)
 returns boolean
 language sql
 stable security definer
 set search_path to ''
as $$
  select exists (select 1 from public.standings st join public.seasons se on se.id = st.season_id
                 where se.league_id = p_league_id and se.numero = p_stagione and st.team_id = p_team_id)
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
  v_off boolean;
begin
  select stagione_corrente, coalesce(conferenze_attive, false) into v_stag, v_conf from public.leagues where id = p_league_id;
  -- In off-season l'album e' ancora quello della stagione appena chiusa: le squadre entrate nell'off-season
  -- (senza classifica in quella stagione) arrivano con l'album della stagione dopo, non in questo.
  v_off := exists (select 1 from public.offseasons where league_id = p_league_id and stato = 'aperta');
  v_prima := not exists (select 1 from public.album_figurine where league_id = p_league_id and stagione = v_stag);
  insert into public.album_figurine (league_id, stagione, tipo, team_id)
  select p_league_id, v_stag, 'stemma', t.id from public.teams t where t.league_id = p_league_id and t.attiva and (not v_off or private.album_in_stagione(p_league_id, v_stag, t.id))
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
    and (not v_off or private.album_in_stagione(p_league_id, v_stag, pi.team_id))
    -- Solo chi non ha ancora la figurina: le statistiche costano, e senza questo filtro ogni bustina le
    -- ricalcolava per tutta la lega (7,5 s a bustina in Serie F) per poi scartarle col conflitto.
    and not exists (select 1 from public.album_figurine af where af.league_id = p_league_id and af.stagione = v_stag
                    and af.tipo = 'giocatore' and af.team_id = pi.team_id and af.player_id = pi.player_id)
  on conflict do nothing;
  if v_conf then
    insert into public.album_figurine (league_id, stagione, tipo, conferenza)
    values (p_league_id, v_stag, 'conferenza', 'est'), (p_league_id, v_stag, 'conferenza', 'ovest')
    on conflict do nothing;
  end if;
  return v_stag;
end $function$;
