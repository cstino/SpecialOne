begin;

create temp table risultati_spin_offseason (
  step text primary key,
  ok boolean not null,
  dettaglio text
) on commit drop;

grant insert, select on risultati_spin_offseason to authenticated;

do $$
declare
  v_league_id bigint := 3;
  v_team_id bigint := 4;
  v_user uuid := '5ef47be9-3b4f-40c3-86e4-03a7bb3ec266';
  v_offseason_id bigint;
  v_state jsonb;
  v_spin_id bigint;
  v_spin_ingaggio bigint;
  v_budget_prima bigint;
  v_budget_dopo bigint;
  v_asta_id bigint;
begin
  update public.leagues
  set fase_carriera = 'offseason',
      offseason_fine = now() + interval '1 day'
  where id = v_league_id;

  insert into public.offseasons(league_id, stagione_da, stagione_a, stato, scade_il, posti_nuovi)
  values (v_league_id, 1, 2, 'aperta', now() + interval '1 day', 0)
  returning id into v_offseason_id;

  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claim.sub', v_user::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_user, 'role', 'authenticated')::text, true);

  v_state := public.stato_spin_offseason(v_league_id);
  insert into risultati_spin_offseason
  values ('stato iniziale', coalesce((v_state->>'attivo')::boolean, false) and (v_state->>'rimasti')::int = 5, v_state::text);

  v_state := public.spin_offseason(v_league_id);
  select id, ingaggio into v_spin_id, v_spin_ingaggio
  from public.offseason_spins
  where offseason_id = v_offseason_id and team_id = v_team_id and stato = 'proposto'
  order by id desc
  limit 1;
  insert into risultati_spin_offseason
  values ('spin proposto', v_spin_id is not null and (v_state->>'rimasti')::int = 4, coalesce(v_state::text, 'null'));

  v_state := public.manda_spin_al_mercato(v_spin_id);
  select id into v_asta_id
  from public.free_agent_auctions
  where league_id = v_league_id
    and player_id = (select player_id from public.offseason_spins where id = v_spin_id)
    and origine = 'spin_offseason'
  limit 1;
  insert into risultati_spin_offseason
  values ('spin a mercato', v_asta_id is not null and not exists (
    select 1 from public.offseason_spins where id = v_spin_id and stato = 'proposto'
  ), coalesce(v_state::text, 'null'));

  v_state := public.spin_offseason(v_league_id);
  select id, ingaggio into v_spin_id, v_spin_ingaggio
  from public.offseason_spins
  where offseason_id = v_offseason_id and team_id = v_team_id and stato = 'proposto'
  order by id desc
  limit 1;
  select budget into v_budget_prima from public.teams where id = v_team_id;
  v_state := public.ingaggia_spin_offseason(v_spin_id);
  select budget into v_budget_dopo from public.teams where id = v_team_id;
  insert into risultati_spin_offseason
  values ('spin ingaggiato', v_budget_dopo = v_budget_prima - v_spin_ingaggio and exists (
    select 1
    from public.player_instances pi
    join public.offseason_spins s on s.player_id = pi.player_id and s.league_id = pi.league_id
    where s.id = v_spin_id and pi.team_id = v_team_id and s.stato = 'ingaggiato'
  ), coalesce(v_state::text, 'null'));
end $$;

select * from risultati_spin_offseason order by step;

rollback;
