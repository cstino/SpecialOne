-- Controllo di appartenenza alla lega calcolato UNA volta per richiesta, non riga per riga (8 ottobre 2026, carico).
-- Le regole facevano (select private.e_membro(tabella.league_id)): il valore dipende dalla riga, quindi Postgres
-- rieseguiva la funzione per ogni riga (in Serie F ~260 volte per leggere il calendario). Ora la lista delle leghe
-- dell'utente si calcola una volta (initplan) e ogni riga confronta solo un numero. Stessa regola: membro della
-- lega (ha una squadra) o suo admin, come private.e_membro.
create or replace function private.mie_leghe()
returns bigint[]
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(array_agg(distinct id), '{}'::bigint[]) from (
    select t.league_id as id from public.teams t where t.user_id = (select auth.uid())
    union
    select l.id from public.leagues l where l.admin_id = (select auth.uid())
  ) x;
$$;
revoke all on function private.mie_leghe() from public;
grant execute on function private.mie_leghe() to authenticated;

alter policy bracket_ties_lettura on public.bracket_ties using (league_id = any ((select private.mie_leghe())::bigint[]));
alter policy brackets_lettura on public.brackets using (league_id = any ((select private.mie_leghe())::bigint[]));
alter policy cambi_ruolo_lettura on public.cambi_ruolo using (league_id = any ((select private.mie_leghe())::bigint[]));
alter policy draft_picks_lettura on public.draft_picks using (league_id = any ((select private.mie_leghe())::bigint[]));
alter policy draft_state_lettura on public.draft_state using (league_id = any ((select private.mie_leghe())::bigint[]));
alter policy draft_team_state_lettura on public.draft_team_state using (league_id = any ((select private.mie_leghe())::bigint[]));
alter policy finestre_scelte_lettura on public.finestre_scelte using (league_id = any ((select private.mie_leghe())::bigint[]));
alter policy fixtures_lettura on public.fixtures using (league_id = any ((select private.mie_leghe())::bigint[]));
alter policy free_agent_auctions_lettura on public.free_agent_auctions using (league_id = any ((select private.mie_leghe())::bigint[]));
alter policy free_agent_progression_lettura on public.free_agent_progression using (league_id = any ((select private.mie_leghe())::bigint[]));
alter policy leagues_lettura on public.leagues using (id = any ((select private.mie_leghe())::bigint[]));
alter policy match_stats_lettura on public.match_stats using (league_id = any ((select private.mie_leghe())::bigint[]));
alter policy matches_lettura on public.matches using (league_id = any ((select private.mie_leghe())::bigint[]));
alter policy offseasons_lettura on public.offseasons using (league_id = any ((select private.mie_leghe())::bigint[]));
alter policy pagelle_lettura on public.pagelle using (league_id = any ((select private.mie_leghe())::bigint[]));
alter policy player_instances_lettura on public.player_instances using (league_id = any ((select private.mie_leghe())::bigint[]));
alter policy reazioni_live_membri on public.reazioni_live using (league_id = any ((select private.mie_leghe())::bigint[]));
alter policy retired_players_lettura on public.retired_players using (league_id = any ((select private.mie_leghe())::bigint[]));
alter policy scelte_draft_lettura on public.scelte_draft using (league_id = any ((select private.mie_leghe())::bigint[]));
alter policy scelte_live_membri on public.scelte_live using (league_id = any ((select private.mie_leghe())::bigint[]));
alter policy scelte_pool_lettura on public.scelte_pool using (league_id = any ((select private.mie_leghe())::bigint[]));
alter policy season_morale_checkpoints_lettura on public.season_morale_checkpoints using (league_id = any ((select private.mie_leghe())::bigint[]));
alter policy season_punti_checkpoints_lettura on public.season_punti_checkpoints using (league_id = any ((select private.mie_leghe())::bigint[]));
alter policy seasons_lettura on public.seasons using (league_id = any ((select private.mie_leghe())::bigint[]));
alter policy sorteggi_conferenze_lettura on public.sorteggi_conferenze using (league_id = any ((select private.mie_leghe())::bigint[]));
alter policy specializzazioni_giocatore_lettura on public.specializzazioni_giocatore using (league_id = any ((select private.mie_leghe())::bigint[]));
alter policy standings_lettura on public.standings using (league_id = any ((select private.mie_leghe())::bigint[]));
alter policy stile_xp_lettura on public.stile_xp using (league_id = any ((select private.mie_leghe())::bigint[]));
alter policy team_risorse_lettura on public.team_risorse using (league_id = any ((select private.mie_leghe())::bigint[]));
alter policy teams_lettura on public.teams using (league_id = any ((select private.mie_leghe())::bigint[]));
alter policy under_auctions_lettura on public.under_auctions using (league_id = any ((select private.mie_leghe())::bigint[]));
alter policy vivaio_prospetti_lettura on public.vivaio_prospetti using (league_id = any ((select private.mie_leghe())::bigint[]));
