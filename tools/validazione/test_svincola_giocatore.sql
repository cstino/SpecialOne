begin;

create temporary table esiti (
  n integer,
  verifica text,
  misurato text,
  esito text
) on commit drop;

-- Il test cambia ruolo dentro la transazione: anche la tabella temporanea
-- deve essere scrivibile da authenticated per registrare gli esiti negativi.
grant select, insert on table esiti to authenticated;

do $$
declare
  v_team public.teams;
  v_league public.leagues;
  v_instance public.player_instances;
  v_gk_instance public.player_instances;
  v_other_user uuid;
  v_budget_before bigint;
  v_lineup_id bigint;
  v_auction_id bigint;
  v_max_auction_id bigint;
  v_max_player_id bigint;
  v_conti jsonb;
  v_ids bigint[];
  v_giornata smallint;
  v_message text;
begin
  select t.* into v_team
  from public.teams t
  join public.leagues l on l.id = t.league_id
  where (select count(*) from public.player_instances pi where pi.team_id = t.id) >= 22
    and exists (
      select 1 from public.player_instances pi join public.players p on p.id = pi.player_id
      where pi.team_id = t.id and p.posizioni[1] <> 'GK'
    )
  order by t.id
  limit 1;

  if not found then raise exception 'Nessuna rosa adatta al test'; end if;
  select * into v_league from public.leagues where id = v_team.league_id;

  update public.leagues set stato = 'stagione' where id = v_league.id;
  v_budget_before := v_team.budget;

  select pi.* into v_instance
  from public.player_instances pi
  join public.players p on p.id = pi.player_id
  where pi.team_id = v_team.id and p.posizioni[1] <> 'GK'
  order by pi.id
  limit 1;

  select user_id into v_other_user
  from public.teams
  where league_id = v_league.id and id <> v_team.id
  order by id limit 1;

  -- Un altro partecipante della stessa lega vede la rosa, ma non puo'
  -- svincolarne i giocatori.
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_other_user, 'role', 'authenticated')::text, true);
  set local role authenticated;
  begin
    perform public.svincola_giocatore(v_instance.id);
    insert into esiti values (1, 'proprieta'' verificata', 'accettato', 'ERRORE');
  exception when insufficient_privilege then
    get stacked diagnostics v_message = message_text;
    insert into esiti values (1, 'proprieta'' verificata', v_message, 'OK');
  end;
  reset role;

  -- Portiamo temporaneamente la rosa a 21, incluso il candidato. La
  -- sotto-transazione annulla la preparazione quando la RPC rifiuta.
  begin
    update public.player_instances pi
    set team_id = null
    where pi.team_id = v_team.id
      and pi.id not in (
        select keep.id from public.player_instances keep
        where keep.team_id = v_team.id
        order by (keep.id = v_instance.id) desc, keep.id
        limit 21
      );
    perform set_config('request.jwt.claims',
      json_build_object('sub', v_team.user_id, 'role', 'authenticated')::text, true);
    set local role authenticated;
    perform public.svincola_giocatore(v_instance.id);
    reset role;
    insert into esiti values (2, 'minimo 21 protetto', 'accettato', 'ERRORE');
  exception when invalid_parameter_value then
    get stacked diagnostics v_message = message_text;
    insert into esiti values (2, 'minimo 21 protetto', v_message, 'OK');
  end;

  -- Stesso controllo per i portieri: lasciamo esattamente il minimo della
  -- lega e tentiamo di svincolarne uno.
  select pi.* into v_gk_instance
  from public.player_instances pi
  join public.players p on p.id = pi.player_id
  where pi.team_id = v_team.id and p.posizioni[1] = 'GK'
  order by pi.id limit 1;

  if v_gk_instance.id is not null and v_league.portieri_minimi > 0 then
    begin
      update public.player_instances pi
      set team_id = null
      where pi.team_id = v_team.id
        and pi.id in (
          select candidati.id
          from public.player_instances candidati
          join public.players p on p.id = candidati.player_id
          where candidati.team_id = v_team.id
            and p.posizioni[1] = 'GK'
            and candidati.id <> v_gk_instance.id
          order by candidati.id desc
          offset greatest(v_league.portieri_minimi - 1, 0)
        );
      perform set_config('request.jwt.claims',
        json_build_object('sub', v_team.user_id, 'role', 'authenticated')::text, true);
      set local role authenticated;
      perform public.svincola_giocatore(v_gk_instance.id);
      reset role;
      insert into esiti values (3, 'minimo portieri protetto', 'accettato', 'ERRORE');
    exception when invalid_parameter_value then
      get stacked diagnostics v_message = message_text;
      insert into esiti values (3, 'minimo portieri protetto', v_message, 'OK');
    end;
  else
    insert into esiti values (3, 'minimo portieri rimosso', 'nessun vincolo', 'OK');
  end if;

  select array_agg(id order by rn) into v_ids
  from (
    select pi.id, row_number() over (order by pi.overall_corrente desc, pi.id) rn
    from public.player_instances pi where pi.team_id = v_team.id and pi.id <> v_instance.id
    limit 11
  ) q;
  v_ids[1] := v_instance.id;

  select coalesce(max(giornata), 0) + 1 into v_giornata
  from public.lineups where team_id = v_team.id;

  insert into public.fixtures (season_id, league_id, giornata, home_team_id, away_team_id, data_sim, stato)
  select s.id, v_league.id, v_giornata, v_team.id,
         (select id from public.teams where league_id = v_league.id and id <> v_team.id order by id limit 1),
         now(), 'programmata'
  from public.seasons s where s.league_id = v_league.id order by s.numero desc limit 1;

  insert into public.lineups (league_id, team_id, giornata, modulo, titolari, panchina, tribuna)
  values (v_league.id, v_team.id, v_giornata, '4-3-3', v_ids, '{}', '{}')
  returning id into v_lineup_id;

  perform set_config('request.jwt.claims',
    json_build_object('sub', v_team.user_id, 'role', 'authenticated')::text, true);
  set local role authenticated;
  perform public.svincola_giocatore(v_instance.id);
  reset role;

  insert into esiti values
    (4, 'istanza liberata', (select coalesce(team_id::text, 'null') from public.player_instances where id = v_instance.id),
     case when (select team_id is null from public.player_instances where id = v_instance.id) then 'OK' else 'ERRORE' end),
    (5, 'budget invariato', (select budget::text from public.teams where id = v_team.id),
     case when (select budget from public.teams where id = v_team.id) = v_budget_before then 'OK' else 'ERRORE' end),
    (6, 'formazione futura rimossa', (select count(*)::text from public.lineups where id = v_lineup_id),
     case when not exists (select 1 from public.lineups where id = v_lineup_id) then 'OK' else 'ERRORE' end),
    (7, 'notifica creata', (select count(*)::text from public.notifications where user_id = v_team.user_id and dati ->> 'player_instance_id' = v_instance.id::text),
     case when exists (select 1 from public.notifications where user_id = v_team.user_id and dati ->> 'player_instance_id' = v_instance.id::text) then 'OK' else 'ERRORE' end);

  -- Lo stesso giocatore non e' piu' della squadra e non puo' essere svincolato due volte.
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_team.user_id, 'role', 'authenticated')::text, true);
  set local role authenticated;
  begin
    perform public.svincola_giocatore(v_instance.id);
    insert into esiti values (8, 'secondo svincolo respinto', 'accettato', 'ERRORE');
  exception when insufficient_privilege then
    get stacked diagnostics v_message = message_text;
    insert into esiti values (8, 'secondo svincolo respinto', v_message, 'OK');
  end;
  reset role;

  -- Il ciclo si chiude davvero solo se un'asta successiva riusa la stessa
  -- istanza libera, invece di tentare un INSERT che violerebbe l'unicita'.
  insert into public.free_agent_auctions
    (league_id, giorno, player_id, ingaggio_teorico)
  values
    (v_league.id, date '2099-12-31', v_instance.player_id, 500000)
  returning id into v_auction_id;
  insert into private.auction_thresholds (auction_id, soglia) values (v_auction_id, 500000);
  insert into public.free_agent_bids
    (auction_id, league_id, team_id, ingaggio_offerto)
  values
    (v_auction_id, v_league.id, v_team.id, 500000);

  perform private.risolvi_aste_giorno(date '2099-12-31');

  insert into esiti values
    (9, 'asta riusa la stessa istanza',
     (select id::text || ':' || coalesce(team_id::text, 'null') from public.player_instances where league_id = v_league.id and player_id = v_instance.player_id),
     case when exists (select 1 from public.player_instances where id = v_instance.id and team_id = v_team.id)
       and (select count(*) from public.player_instances where league_id = v_league.id and player_id = v_instance.player_id) = 1
       then 'OK' else 'ERRORE' end);

  -- Portiamo la rosa a 30 con giocatori non ancora presenti nella lega.
  insert into public.player_instances
    (league_id, player_id, team_id, overall_corrente, eta_corrente, ingaggio)
  select v_league.id, p.id, v_team.id, p.overall, p.eta, 500000
  from public.players p
  where not exists (
    select 1 from public.player_instances pi
    where pi.league_id = v_league.id and pi.player_id = p.id
  )
  order by p.id
  limit greatest(0, 30 - (select count(*) from public.player_instances where team_id = v_team.id));

  perform set_config('request.jwt.claims',
    json_build_object('sub', v_team.user_id, 'role', 'authenticated')::text, true);
  set local role authenticated;
  select public.budget_disponibile(v_league.id) into v_conti;
  reset role;

  insert into esiti values
    (10, 'massimo 30 nei conti',
     (select count(*)::text from public.player_instances where team_id = v_team.id)
       || ' giocatori, ' || (v_conti ->> 'slot_liberi') || ' slot liberi',
     case when (select count(*) from public.player_instances where team_id = v_team.id) = 30
       and (v_conti ->> 'slot_liberi')::integer = 0 then 'OK' else 'ERRORE' end);

  select p.id into v_max_player_id
  from public.players p
  where not exists (
    select 1 from public.player_instances pi
    where pi.league_id = v_league.id and pi.player_id = p.id
  )
  order by p.id
  limit 1;

  insert into public.free_agent_auctions
    (league_id, giorno, player_id, ingaggio_teorico)
  values
    (v_league.id, date '2099-12-30', v_max_player_id, 500000)
  returning id into v_max_auction_id;
  insert into private.auction_thresholds (auction_id, soglia)
  values (v_max_auction_id, 500000);

  perform set_config('request.jwt.claims',
    json_build_object('sub', v_team.user_id, 'role', 'authenticated')::text, true);
  set local role authenticated;
  begin
    perform public.offri_per_svincolato(v_max_auction_id, 500000);
    insert into esiti values (11, 'offerta oltre 30 respinta', 'accettata', 'ERRORE');
  exception when invalid_parameter_value then
    get stacked diagnostics v_message = message_text;
    insert into esiti values (11, 'offerta oltre 30 respinta', v_message, 'OK');
  end;
  reset role;

  -- Anche il resolver ricontrolla il limite, nel caso di dati concorrenti
  -- o offerte create prima che la rosa arrivasse a 30.
  insert into public.free_agent_bids
    (auction_id, league_id, team_id, ingaggio_offerto)
  values
    (v_max_auction_id, v_league.id, v_team.id, 500000);
  perform private.risolvi_aste_giorno(date '2099-12-30');

  insert into esiti values
    (12, 'resolver rispetta massimo 30',
     (select stato from public.free_agent_auctions where id = v_max_auction_id),
     case when (select stato from public.free_agent_auctions where id = v_max_auction_id) = 'deserta'
       and not exists (
         select 1 from public.player_instances
         where league_id = v_league.id and player_id = v_max_player_id
       ) then 'OK' else 'ERRORE' end);
end;
$$;

do $$
begin
  insert into esiti values
    (13, 'anon senza execute', has_function_privilege('anon', 'public.svincola_giocatore(bigint)', 'execute')::text,
     case when not has_function_privilege('anon', 'public.svincola_giocatore(bigint)', 'execute') then 'OK' else 'ERRORE' end),
    (14, 'authenticated con execute', has_function_privilege('authenticated', 'public.svincola_giocatore(bigint)', 'execute')::text,
     case when has_function_privilege('authenticated', 'public.svincola_giocatore(bigint)', 'execute') then 'OK' else 'ERRORE' end);
end;
$$;

select n, verifica, misurato, esito from esiti order by n;

rollback;
