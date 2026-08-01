-- ============================================================
--  REGISTRAZIONE ATOMICA DI UNA PARTITA SIMULATA
--
--  La Edge Function calcola il risultato con il motore JavaScript; questa
--  RPC resta l'unico punto che scrive risultato, statistiche, classifica e
--  familiarita'. Il lock sulla fixture rende sicuri retry e doppie chiamate.
-- ============================================================

create or replace function public.registra_risultato_partita(
  p_fixture_id bigint,
  p_seed bigint,
  p_modulo_home text,
  p_modulo_away text,
  p_gol_home smallint,
  p_gol_away smallint,
  p_blocchi jsonb,
  p_stats_squadra jsonb,
  p_player_stats jsonb
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_fixture public.fixtures;
  v_match public.matches;
  v_season public.seasons;
begin
  select * into v_fixture
  from public.fixtures
  where id = p_fixture_id
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'Fixture non trovata.';
  end if;

  select * into v_match
  from public.matches
  where fixture_id = p_fixture_id;

  if found then
    return jsonb_build_object(
      'match_id', v_match.id,
      'fixture_id', v_match.fixture_id,
      'gia_simulata', true,
      'gol_home', v_match.gol_home,
      'gol_away', v_match.gol_away
    );
  end if;

  select * into v_season
  from public.seasons
  where id = v_fixture.season_id
    and league_id = v_fixture.league_id;

  if not found or v_season.stato <> 'in_corso' then
    raise exception using errcode = '55000', message = 'La stagione non e'' in corso.';
  end if;
  if v_fixture.stato not in ('programmata', 'in_corso') then
    raise exception using errcode = '55000', message = 'La fixture non puo'' essere simulata.';
  end if;
  if p_seed not between 1 and 4294967295 then
    raise exception using errcode = '22023', message = 'Seed non valido.';
  end if;
  if p_gol_home < 0 or p_gol_away < 0 then
    raise exception using errcode = '22023', message = 'Il risultato contiene gol negativi.';
  end if;
  if jsonb_typeof(p_blocchi) <> 'array'
     or jsonb_typeof(p_stats_squadra) <> 'object'
     or jsonb_typeof(p_player_stats) <> 'array' then
    raise exception using errcode = '22023', message = 'Payload statistiche non valido.';
  end if;
  if not (p_modulo_home = any(private.moduli_validi()))
     or not (p_modulo_away = any(private.moduli_validi())) then
    raise exception using errcode = '22023', message = 'Modulo non valido.';
  end if;

  if not exists (
    select 1 from public.lineups l
    where l.league_id = v_fixture.league_id
      and l.team_id = v_fixture.home_team_id
      and l.giornata = v_fixture.giornata
      and l.modulo = p_modulo_home
  ) or not exists (
    select 1 from public.lineups l
    where l.league_id = v_fixture.league_id
      and l.team_id = v_fixture.away_team_id
      and l.giornata = v_fixture.giornata
      and l.modulo = p_modulo_away
  ) then
    raise exception using errcode = '55000', message = 'Manca una formazione valida per questa partita.';
  end if;

  if exists (
    select 1
    from jsonb_to_recordset(p_player_stats) as x(
      player_instance_id bigint,
      team_id bigint,
      minuti smallint,
      gol smallint,
      assist smallint,
      tiri smallint,
      tiri_porta smallint,
      passaggi_tentati smallint,
      passaggi_riusciti smallint,
      contrasti_vinti smallint,
      contrasti_persi smallint,
      dribbling smallint
    )
    left join public.player_instances pi
      on pi.id = x.player_instance_id
     and pi.league_id = v_fixture.league_id
     and pi.team_id = x.team_id
    where pi.id is null
       or x.team_id not in (v_fixture.home_team_id, v_fixture.away_team_id)
  ) then
    raise exception using errcode = '42501', message = 'Le statistiche contengono un giocatore fuori dalle squadre della partita.';
  end if;

  insert into public.matches (
    fixture_id,
    league_id,
    gol_home,
    gol_away,
    modulo_home,
    modulo_away,
    seed,
    blocchi,
    stats_squadra
  ) values (
    p_fixture_id,
    v_fixture.league_id,
    p_gol_home,
    p_gol_away,
    p_modulo_home,
    p_modulo_away,
    p_seed,
    p_blocchi,
    p_stats_squadra
  )
  returning * into v_match;

  insert into public.match_stats (
    match_id,
    league_id,
    team_id,
    player_instance_id,
    minuti,
    gol,
    assist,
    tiri,
    tiri_porta,
    passaggi_tentati,
    passaggi_riusciti,
    contrasti_vinti,
    contrasti_persi,
    dribbling
  )
  select
    v_match.id,
    v_fixture.league_id,
    x.team_id,
    x.player_instance_id,
    x.minuti,
    x.gol,
    x.assist,
    x.tiri,
    x.tiri_porta,
    x.passaggi_tentati,
    x.passaggi_riusciti,
    x.contrasti_vinti,
    x.contrasti_persi,
    x.dribbling
  from jsonb_to_recordset(p_player_stats) as x(
    player_instance_id bigint,
    team_id bigint,
    minuti smallint,
    gol smallint,
    assist smallint,
    tiri smallint,
    tiri_porta smallint,
    passaggi_tentati smallint,
    passaggi_riusciti smallint,
    contrasti_vinti smallint,
    contrasti_persi smallint,
    dribbling smallint
  );

  update public.standings
  set
    vittorie = vittorie + case
      when team_id = v_fixture.home_team_id and p_gol_home > p_gol_away then 1
      when team_id = v_fixture.away_team_id and p_gol_away > p_gol_home then 1
      else 0 end,
    pareggi = pareggi + case when p_gol_home = p_gol_away then 1 else 0 end,
    sconfitte = sconfitte + case
      when team_id = v_fixture.home_team_id and p_gol_home < p_gol_away then 1
      when team_id = v_fixture.away_team_id and p_gol_away < p_gol_home then 1
      else 0 end,
    punti = punti + case
      when p_gol_home = p_gol_away then 1
      when team_id = v_fixture.home_team_id and p_gol_home > p_gol_away then 3
      when team_id = v_fixture.away_team_id and p_gol_away > p_gol_home then 3
      else 0 end,
    gol_fatti = gol_fatti + case when team_id = v_fixture.home_team_id then p_gol_home else p_gol_away end,
    gol_subiti = gol_subiti + case when team_id = v_fixture.home_team_id then p_gol_away else p_gol_home end,
    aggiornata_il = now()
  where season_id = v_fixture.season_id
    and team_id in (v_fixture.home_team_id, v_fixture.away_team_id);

  insert into public.formation_xp (team_id, league_id, modulo, partite_giocate)
  values
    (v_fixture.home_team_id, v_fixture.league_id, p_modulo_home, 1),
    (v_fixture.away_team_id, v_fixture.league_id, p_modulo_away, 1)
  on conflict (team_id, modulo) do update set
    partite_giocate = public.formation_xp.partite_giocate + 1,
    aggiornata_il = now();

  update public.fixtures
  set stato = 'simulata'
  where id = p_fixture_id;

  -- La posizione e' ricalcolata dopo ogni risultato. Gli scontri diretti
  -- considerano soltanto le avversarie a pari punti nella classifica attuale.
  update public.standings
  set posizione = null
  where season_id = v_fixture.season_id;

  with h2h as (
    select
      st.team_id,
      coalesce(sum(case
        when f.home_team_id = st.team_id and m.gol_home > m.gol_away then 3
        when f.away_team_id = st.team_id and m.gol_away > m.gol_home then 3
        when m.gol_home = m.gol_away then 1
        else 0
      end), 0)::integer as punti_diretti
    from public.standings st
    left join public.fixtures f
      on f.season_id = st.season_id
     and (f.home_team_id = st.team_id or f.away_team_id = st.team_id)
    left join public.matches m on m.fixture_id = f.id
    left join public.standings opponent
      on opponent.season_id = st.season_id
     and opponent.team_id = case
       when f.home_team_id = st.team_id then f.away_team_id
       else f.home_team_id
     end
     and opponent.punti = st.punti
    where st.season_id = v_fixture.season_id
      and opponent.team_id is not null
    group by st.team_id
  ), ranking as (
    select
      st.team_id,
      row_number() over (
        order by st.punti desc,
                 coalesce(h2h.punti_diretti, 0) desc,
                 st.differenza_reti desc,
                 st.gol_fatti desc,
                 st.team_id
      )::smallint as posizione
    from public.standings st
    left join h2h on h2h.team_id = st.team_id
    where st.season_id = v_fixture.season_id
  )
  update public.standings st
  set posizione = ranking.posizione
  from ranking
  where st.season_id = v_fixture.season_id
    and st.team_id = ranking.team_id;

  if not exists (
    select 1 from public.fixtures
    where season_id = v_fixture.season_id
      and stato = 'programmata'
  ) then
    update public.seasons
    set stato = 'conclusa', data_fine = (now() at time zone 'Europe/Rome')::date
    where id = v_fixture.season_id;
    update public.leagues
    set stato = 'conclusa'
    where id = v_fixture.league_id;
  end if;

  return jsonb_build_object(
    'match_id', v_match.id,
    'fixture_id', v_match.fixture_id,
    'gia_simulata', false,
    'gol_home', v_match.gol_home,
    'gol_away', v_match.gol_away
  );
end;
$$;

revoke all on function public.registra_risultato_partita(
  bigint, bigint, text, text, smallint, smallint, jsonb, jsonb, jsonb
) from public, anon, authenticated;
grant execute on function public.registra_risultato_partita(
  bigint, bigint, text, text, smallint, smallint, jsonb, jsonb, jsonb
) to service_role;

comment on function public.registra_risultato_partita(
  bigint, bigint, text, text, smallint, smallint, jsonb, jsonb, jsonb
) is 'Registra atomicamente una simulazione e aggiorna classifica e familiarita''; idempotente per fixture.';
