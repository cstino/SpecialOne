begin;

do $$
declare
  v_fixture public.fixtures;
  v_team_id bigint;
  v_home_modulo text;
  v_away_modulo text;
  v_match_count integer;
  v_giocate_before integer;
  v_giocate_after integer;
  v_first_result jsonb;
  v_retry_result jsonb;
begin
  select f.* into v_fixture
  from public.fixtures f
  join public.leagues l on l.id = f.league_id
  where lower(l.nome) = lower('sdsDas')
    and f.stato = 'programmata'
  order by f.giornata, f.id
  limit 1;

  if not found then
    raise exception 'Nessuna fixture programmata disponibile per il test';
  end if;

  foreach v_team_id in array array[v_fixture.home_team_id, v_fixture.away_team_id]
  loop
    if not exists (
      select 1 from public.lineups
      where team_id = v_team_id and giornata = v_fixture.giornata
    ) then
      insert into public.lineups (
        league_id, team_id, giornata, modulo, titolari, panchina, tribuna, automatica
      )
      select
        v_fixture.league_id,
        v_team_id,
        v_fixture.giornata,
        '4-3-3',
        array_agg(id order by rn) filter (where rn <= 11),
        coalesce(array_agg(id order by rn) filter (where rn between 12 and 20), '{}'::bigint[]),
        coalesce(array_agg(id order by rn) filter (where rn > 20), '{}'::bigint[]),
        true
      from (
        select pi.id, row_number() over (order by pi.overall_corrente desc, pi.id) as rn
        from public.player_instances pi
        where pi.league_id = v_fixture.league_id and pi.team_id = v_team_id
      ) players;
    end if;
  end loop;

  select modulo into v_home_modulo from public.lineups
  where team_id = v_fixture.home_team_id and giornata = v_fixture.giornata;
  select modulo into v_away_modulo from public.lineups
  where team_id = v_fixture.away_team_id and giornata = v_fixture.giornata;
  select sum(giocate) into v_giocate_before from public.standings
  where season_id = v_fixture.season_id;

  v_first_result := public.registra_risultato_partita(
    v_fixture.id, 123456789::bigint, v_home_modulo, v_away_modulo,
    1::smallint, 1::smallint, '[]'::jsonb,
    '{"home":{"possesso":0.5},"away":{"possesso":0.5}}'::jsonb,
    '[]'::jsonb
  );
  v_retry_result := public.registra_risultato_partita(
    v_fixture.id, 987654321::bigint, v_home_modulo, v_away_modulo,
    9::smallint, 0::smallint, '[]'::jsonb, '{}'::jsonb, '[]'::jsonb
  );

  select count(*) into v_match_count from public.matches where fixture_id = v_fixture.id;
  select sum(giocate) into v_giocate_after from public.standings
  where season_id = v_fixture.season_id;

  if v_match_count <> 1 then
    raise exception 'Idempotenza fallita: trovate % partite', v_match_count;
  end if;
  if coalesce(v_giocate_after, 0) <> coalesce(v_giocate_before, 0) + 2 then
    raise exception 'Classifica non aggiornata correttamente: prima %, dopo %', v_giocate_before, v_giocate_after;
  end if;
  if (v_first_result ->> 'gia_simulata')::boolean
     or not (v_retry_result ->> 'gia_simulata')::boolean then
    raise exception 'Risposta idempotente non coerente';
  end if;
end;
$$;

rollback;
