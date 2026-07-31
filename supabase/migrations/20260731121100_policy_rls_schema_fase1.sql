-- ============================================================
--  POLICY RLS E PRIVILEGI DELLO SCHEMA FASE 1
-- ============================================================

create or replace function private.e_admin(p_league_id bigint)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.leagues l
    where l.id = p_league_id
      and l.admin_id = (select auth.uid())
  );
$$;

-- Propria formazione: sempre. Formazione altrui: soltanto quando la sua
-- partita di quella giornata risulta simulata, e solo ai membri della lega.
create or replace function private.lineup_visibile(
  p_team_id bigint,
  p_giornata smallint
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.teams t
    where t.id = p_team_id
      and t.user_id = (select auth.uid())
  ) or exists (
    select 1
    from public.teams t
    join public.fixtures f
      on f.league_id = t.league_id
     and f.giornata = p_giornata
     and (f.home_team_id = t.id or f.away_team_id = t.id)
    where t.id = p_team_id
      and f.stato = 'simulata'
      and (select private.e_membro(t.league_id))
  );
$$;

revoke all on function private.e_admin(bigint)
  from public, anon;
revoke all on function private.lineup_visibile(bigint, smallint)
  from public, anon;

grant execute on function private.e_admin(bigint)
  to authenticated, service_role;
grant execute on function private.lineup_visibile(bigint, smallint)
  to authenticated, service_role;

create policy seasons_lettura on public.seasons
  for select to authenticated
  using ((select private.e_membro(league_id)));

create policy fixtures_lettura on public.fixtures
  for select to authenticated
  using ((select private.e_membro(league_id)));

create policy lineups_lettura on public.lineups
  for select to authenticated
  using ((select private.lineup_visibile(team_id, giornata)));

create policy formation_xp_lettura on public.formation_xp
  for select to authenticated
  using ((select private.e_membro(league_id)));

create policy matches_lettura on public.matches
  for select to authenticated
  using ((select private.e_membro(league_id)));

create policy match_stats_lettura on public.match_stats
  for select to authenticated
  using ((select private.e_membro(league_id)));

create policy standings_lettura on public.standings
  for select to authenticated
  using ((select private.e_membro(league_id)));

create policy transactions_lettura on public.transactions
  for select to authenticated
  using (
    (select private.e_mia_squadra(team_id))
    or (select private.e_admin(league_id))
  );

-- Nessuna tabella e' pubblica e nessun client scrive direttamente: le
-- scritture applicative passeranno da RPC validate nei rispettivi task.
revoke all on table
  public.seasons,
  public.fixtures,
  public.lineups,
  public.formation_xp,
  public.matches,
  public.match_stats,
  public.standings,
  public.transactions
from anon, authenticated, service_role;

grant select on table
  public.seasons,
  public.fixtures,
  public.lineups,
  public.formation_xp,
  public.matches,
  public.match_stats,
  public.standings,
  public.transactions
to authenticated;

grant select, insert, update, delete on table
  public.seasons,
  public.fixtures,
  public.lineups,
  public.formation_xp,
  public.matches,
  public.match_stats,
  public.standings
to service_role;

-- Il registro economico e' append-only anche per il backend applicativo.
grant select, insert on table public.transactions to service_role;

grant usage, select on sequence
  public.seasons_id_seq,
  public.fixtures_id_seq,
  public.lineups_id_seq,
  public.matches_id_seq,
  public.match_stats_id_seq,
  public.transactions_id_seq
to service_role;
