begin;

do $$
declare
  v_user uuid;
  v_result jsonb;
  v_league_id bigint;
  v_calls integer := 0;
  v_competitions text[] := array[
    'Premier League', 'La Liga', 'Serie A', 'Bundesliga', 'Ligue 1',
    'Eredivisie', 'Liga Portugal', 'Süper Lig', 'Saudi Pro League',
    'EFL Championship'
  ];
begin
  select user_id into v_user from public.teams
  where user_id is not null order by id limit 1;
  perform set_config('request.jwt.claim.sub', v_user::text, true);
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_user, 'role', 'authenticated')::text, true);

  v_result := public.crea_lega(
    'Smoke 16 PC ' || clock_timestamp()::text,
    'Smoke Human 16', 'preset:slot', 16::smallint, 2::smallint,
    60000000::bigint, 40000000::bigint, 3::smallint, 24::smallint,
    0::smallint, v_competitions, 15::smallint, 'by_role'
  );
  v_league_id := (v_result->>'league_id')::bigint;

  while public.completa_prossima_squadra_pc(v_league_id) loop
    v_calls := v_calls + 1;
    if v_calls > 15 then raise exception 'Smoke 16: ciclo PC non termina.'; end if;
  end loop;
  if v_calls <> 15 then raise exception 'Smoke 16: completate % squadre PC.', v_calls; end if;
  if exists (
    select 1 from public.teams t
    where t.league_id = v_league_id and t.controllata_da_pc
      and ((select count(*) from public.player_instances pi where pi.team_id = t.id) <> 24
        or t.budget < 20000000)
  ) then
    raise exception 'Smoke 16: almeno una squadra viola slot o budget.';
  end if;
end;
$$;

rollback;
