do $$
declare
  v_incoerenti integer;
  v_manning integer;
begin
  with gol_legacy as (
    select m.id as match_id, f.home_team_id, f.away_team_id,
           m.titolari_home, m.titolari_away, evento.value,
           ms.minuti,
           (evento.value->>'marcatore')::bigint = any(
             case
               when (evento.value->>'team_id')::bigint = f.home_team_id then m.titolari_home
               else m.titolari_away
             end
           ) as titolare
    from public.matches m
    join public.fixtures f on f.id = m.fixture_id
    cross join lateral jsonb_array_elements(m.blocchi) evento(value)
    join public.match_stats ms
      on ms.match_id = m.id
     and ms.player_instance_id = (evento.value->>'marcatore')::bigint
    where cardinality(m.titolari_home) > 0
      and cardinality(m.titolari_away) > 0
      and not exists (
        select 1 from jsonb_array_elements(m.blocchi) elemento
        where not (elemento ? 'marcatore')
      )
  )
  select count(*) into v_incoerenti
  from gol_legacy
  where minuti <= 0
     or (titolare and (value->>'minuto')::integer not between 1 and minuti)
     or (not titolare and (value->>'minuto')::integer not between greatest(1, 90 - minuti) and 90);

  if v_incoerenti <> 0 then
    raise exception 'Trovati % gol legacy fuori dall intervallo di gioco.', v_incoerenti;
  end if;

  select (evento.value->>'minuto')::integer into v_manning
  from public.leagues l
  join public.fixtures f on f.league_id = l.id and f.giornata = 3
  join public.matches m on m.fixture_id = f.id
  cross join lateral jsonb_array_elements(m.blocchi) evento(value)
  join public.player_instances pi on pi.id = (evento.value->>'marcatore')::bigint
  join public.players p on p.id = pi.player_id
  where l.nome = 'Real Fampionato' and p.nome ilike '%Manning%'
  limit 1;

  if v_manning <> 75 then
    raise exception 'Il gol di Manning risulta ancora al minuto % invece che al 75.', v_manning;
  end if;
end;
$$;
