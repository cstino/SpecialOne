-- ============================================================
--  ALBO D'ORO: LA RIVELAZIONE SI APRE SUBITO DOPO L'ULTIMA PARTITA
--  (deciso dal committente il 3 ottobre 2026: niente attesa di 30 minuti).
--  Chi gioca l'ultima giornata la vede comunque solo dopo il proprio risultato.
-- ============================================================
create or replace function public.albo_rivelazione_pendente(p_league_id bigint)
returns bigint
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_stagione public.seasons;
  v_ultima timestamptz;
  v_giornata_finale smallint;
begin
  if not (select private.e_membro(p_league_id)) then
    raise exception using errcode = '42501', message = 'Non fai parte di questa lega.';
  end if;

  select * into v_stagione
  from public.seasons s
  where s.league_id = p_league_id and s.stato = 'conclusa'
  order by s.numero desc
  limit 1;
  if not found then return null; end if;

  select max(m.simulata_il) into v_ultima
  from public.matches m
  join public.fixtures f on f.id = m.fixture_id
  where f.season_id = v_stagione.id;
  if v_ultima is null or v_ultima < now() - interval '4 days' then return null; end if;

  if clock_timestamp() < v_ultima + interval '0 minutes' then return null; end if;

  if exists (
    select 1 from public.albo_rivelazioni r
    where r.user_id = (select auth.uid()) and r.season_id = v_stagione.id
  ) then return null; end if;

  -- Chi gioca nell'ultima giornata deve aver gia' visto il risultato.
  select max(f.giornata) into v_giornata_finale
  from public.fixtures f where f.season_id = v_stagione.id;

  if exists (
    select 1
    from public.fixtures f
    join public.matches m on m.fixture_id = f.id
    join public.teams t on t.league_id = p_league_id
      and t.user_id = (select auth.uid())
      and t.id in (f.home_team_id, f.away_team_id)
    where f.season_id = v_stagione.id
      and f.giornata = v_giornata_finale
      and not exists (
        select 1 from public.match_reveals mr
        where mr.user_id = (select auth.uid()) and mr.match_id = m.id
      )
  ) then return null; end if;

  return v_stagione.id;
end;
$$;

revoke all on function public.albo_rivelazione_pendente(bigint) from public, anon;
grant execute on function public.albo_rivelazione_pendente(bigint) to authenticated;

notify pgrst, 'reload schema';
