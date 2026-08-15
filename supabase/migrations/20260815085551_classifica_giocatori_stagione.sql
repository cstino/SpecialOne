-- Aggregazione autorevole: il client non deve ricostruire la stagione dalla
-- propria cache di fixture, altrimenti puo' visualizzare un sottoinsieme di
-- partite durante i refresh asincroni.
create or replace function public.classifica_giocatori_stagione(p_league_id bigint)
returns table(player_instance_id bigint, team_id bigint, gol integer, assist integer)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_stagione bigint;
begin
  if not exists (
    select 1 from public.teams t
    where t.league_id = p_league_id and t.user_id = (select auth.uid()) and t.attiva
  ) then
    raise exception using errcode = '42501', message = 'Non partecipi a questa lega.';
  end if;

  select s.id into v_stagione
  from public.seasons s
  join public.leagues l on l.id = s.league_id
  where l.id = p_league_id and s.numero = l.stagione_corrente;

  if v_stagione is null then return; end if;

  return query
  select ms.player_instance_id,
         coalesce(pi.team_id, max(ms.team_id)) as team_id,
         coalesce(sum(ms.gol), 0)::integer as gol,
         coalesce(sum(ms.assist), 0)::integer as assist
  from public.match_stats ms
  join public.matches m on m.id = ms.match_id
  join public.fixtures f on f.id = m.fixture_id and f.season_id = v_stagione and f.stato = 'simulata'
  left join public.player_instances pi on pi.id = ms.player_instance_id
  where ms.league_id = p_league_id
  group by ms.player_instance_id, pi.team_id;
end;
$$;

revoke all on function public.classifica_giocatori_stagione(bigint) from public, anon;
grant execute on function public.classifica_giocatori_stagione(bigint) to authenticated;
