begin;

do $$
declare
  v_league_id bigint;
  v_human public.teams;
  v_pc public.teams;
  v_player_id bigint;
  v_originale public.trade_proposals;
  v_contro public.trade_proposals;
  v_pc_pc_prima integer;
  v_pc_pc_dopo integer;
  v_tentativo integer;
begin
  select t.league_id into v_league_id
  from public.teams t
  where t.controllata_da_pc and t.attiva
  group by t.league_id
  having count(*) >= 2
  order by count(*) desc
  limit 1;
  if v_league_id is null then raise exception 'Nessuna lega con almeno due squadre PC'; end if;

  if exists (
    select 1 from public.teams
    where league_id = v_league_id and controllata_da_pc
      and (nome ilike '% pc %' or nome ilike '%algoritmo%' or nome ilike '%byte%' or nome ilike '%bot%')
  ) then
    raise exception 'Sono rimasti nomi tecnici nelle squadre PC';
  end if;

  select count(*) into v_pc_pc_prima
  from public.trade_proposals tp
  join public.teams d on d.id = tp.da_team_id and d.controllata_da_pc
  join public.teams a on a.id = tp.a_team_id and a.controllata_da_pc
  where tp.league_id = v_league_id;

  for v_tentativo in 1..12 loop
    perform private.proposte_mercato_squadre_pc(v_league_id);
  end loop;

  select count(*) into v_pc_pc_dopo
  from public.trade_proposals tp
  join public.teams d on d.id = tp.da_team_id and d.controllata_da_pc
  join public.teams a on a.id = tp.a_team_id and a.controllata_da_pc
  where tp.league_id = v_league_id;
  if v_pc_pc_dopo <= v_pc_pc_prima then
    raise exception 'Nessuna proposta PC-PC generata nei test';
  end if;

  select * into v_human from public.teams
  where league_id = v_league_id and not controllata_da_pc and user_id is not null and attiva
  limit 1;
  select * into v_pc from public.teams
  where league_id = v_league_id and controllata_da_pc and attiva
  limit 1;
  select id into v_player_id from public.player_instances where team_id = v_human.id limit 1;
  if v_human.id is null or v_pc.id is null or v_player_id is null then
    raise exception 'Dati insufficienti per testare la controfferta';
  end if;

  insert into public.trade_proposals(
    league_id, da_team_id, a_team_id, giocatori_offerti,
    giocatori_richiesti, conguaglio, messaggio, scade_il
  ) values (
    v_league_id, v_pc.id, v_human.id, '{}', array[v_player_id],
    2000000, 'Test controfferta', now() + interval '2 hours'
  ) returning * into v_originale;

  perform set_config('request.jwt.claim.sub', v_human.user_id::text, true);
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_human.user_id, 'role', 'authenticated')::text, true);

  select * into v_contro from public.controproponi(
    v_originale.id,
    v_originale.giocatori_richiesti,
    v_originale.giocatori_offerti,
    -v_originale.conguaglio,
    'Test risposta'
  );

  if (select stato from public.trade_proposals where id = v_originale.id) <> 'rifiutata' then
    raise exception 'La proposta originale non è stata chiusa';
  end if;
  if v_contro.controproposta_di is distinct from v_originale.id
     or v_contro.da_team_id <> v_human.id
     or v_contro.a_team_id <> v_pc.id then
    raise exception 'Controfferta non collegata o direzione errata';
  end if;
end;
$$;

rollback;
