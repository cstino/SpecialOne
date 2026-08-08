begin;

do $$
declare
  v_user uuid;
  v_competitions text[];
  v_result jsonb;
  v_league_id bigint;
  v_team_id bigint;
  v_first_card bigint;
  v_second_card bigint;
  v_budget_before bigint;
  v_budget_after bigint;
  v_count integer;
  v_pc_calls integer := 0;
  v_definition text;
begin
  select user_id into v_user
  from public.teams
  where user_id is not null
  order by id
  limit 1;
  if v_user is null then raise exception 'Smoke test: nessun utente disponibile.'; end if;

  perform set_config('request.jwt.claim.sub', v_user::text, true);
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_user, 'role', 'authenticated')::text, true);
  v_competitions := array['Serie A'];

  v_result := public.crea_lega(
    'Smoke BY ROLE ' || clock_timestamp()::text,
    'Smoke Human', 'preset:slot', 4::smallint, 2::smallint,
    60000000::bigint, 40000000::bigint, 3::smallint, 24::smallint,
    0::smallint, v_competitions, 3::smallint, 'by_role'
  );
  v_league_id := (v_result->>'league_id')::bigint;
  v_team_id := (v_result->>'team_id')::bigint;

  if (select modalita_draft from public.leagues where id = v_league_id) <> 'by_role' then
    raise exception 'Smoke test: modalita non salvata.';
  end if;
  select count(*) into v_count from public.teams where league_id = v_league_id;
  if v_count <> 4 then raise exception 'Smoke test: attese 4 squadre, trovate %.', v_count; end if;

  select pg_get_functiondef('private.completa_draft_squadra_pc(bigint,bigint)'::regprocedure)
  into v_definition;
  if position('v_league.modalita_draft = ''by_role''' in v_definition) = 0 then
    raise exception 'Smoke test: il draft PC non distingue BY ROLE.';
  end if;

  while public.completa_prossima_squadra_pc(v_league_id) loop
    v_pc_calls := v_pc_calls + 1;
    if v_pc_calls > 3 then raise exception 'Smoke test: troppe squadre PC completate.'; end if;
  end loop;
  if v_pc_calls <> 3 then raise exception 'Smoke test: completate % squadre PC invece di 3.', v_pc_calls; end if;
  if exists (
    select 1 from public.teams t
    where t.league_id = v_league_id and t.controllata_da_pc
      and ((select count(*) from public.player_instances pi where pi.team_id = t.id) <> 24
        or t.budget < 20000000)
  ) then
    raise exception 'Smoke test: una rosa PC non rispetta slot o budget draft.';
  end if;

  select budget into v_budget_before from public.teams where id = v_team_id;
  v_result := public.draft_by_role_spin(v_league_id, 'ATT');
  v_first_card := (v_result->'carta'->>'id')::bigint;
  if v_first_card is null or v_result->>'ruolo_scelto' <> 'ATT'
     or coalesce((v_result->'carta'->>'ingaggiabile')::boolean, false) is not true then
    raise exception 'Smoke test: spin BY ROLE non valido: %', v_result;
  end if;

  v_result := public.draft_by_role_reroll(v_league_id);
  v_second_card := (v_result->'carta'->>'id')::bigint;
  if v_second_card is null or v_second_card = v_first_card then
    raise exception 'Smoke test: il reroll non ha sostituito la carta.';
  end if;

  v_result := public.draft_by_role_ingaggia(v_league_id, v_second_card);
  select budget into v_budget_after from public.teams where id = v_team_id;
  if v_budget_after >= v_budget_before then raise exception 'Smoke test: budget non scalato.'; end if;
  select count(*) into v_count from public.player_instances
  where league_id = v_league_id and team_id = v_team_id;
  if v_count <> 1 then raise exception 'Smoke test: il giocatore non e stato assegnato.'; end if;

  begin
    perform public.draft_apri_pacchetto(v_league_id);
    raise exception 'Smoke test: RPC 2 of 4 utilizzabile in una lega BY ROLE.';
  exception when sqlstate '55000' then
    null;
  end;

  -- Anche la modalita' preesistente deve continuare a funzionare attraverso
  -- i wrapper che impediscono di mischiare le due API.
  v_result := public.crea_lega(
    'Smoke 2 OF 4 ' || clock_timestamp()::text,
    'Smoke Classic', 'preset:slot', 4::smallint, 2::smallint,
    60000000::bigint, 40000000::bigint, 3::smallint, 24::smallint,
    0::smallint, v_competitions, 0::smallint, '2_of_4'
  );
  v_league_id := (v_result->>'league_id')::bigint;
  v_result := public.draft_apri_pacchetto(v_league_id);
  if jsonb_array_length(v_result->'carte') <> 4 then
    raise exception 'Smoke test: il pacchetto 2 of 4 non contiene quattro carte.';
  end if;
end;
$$;

rollback;
