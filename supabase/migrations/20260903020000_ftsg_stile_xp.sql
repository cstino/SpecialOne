-- ============================================================
--  INDICE FTSG (FAMILIARITA' TATTICHE E STILE DI GIOCO), deciso con
--  l'utente il 3 settembre 2026.
--
--  Finora il motore penalizzava (malus fino a -3.5 di overall, engine.js
--  familiarita()) solo il cambio di MODULO, mai il cambio di STILE DI
--  GIOCO (che pure ridistribuisce punti DEF/MID/ATT via stileTattico()).
--  Da oggi il malus e' calcolato sulla media tra le due familiarita' (0%
--  modulo nuovo + 0% stile nuovo = malus pieno -3.5, esattamente come un
--  modulo mai giocato prima; non due malus che si sommano). Vedi
--  engine/engine.js familiarita(rosa, modulo, stile) e la validazione
--  gia' rilanciata (tools/validazione/simulate.js), che non passa mai lo
--  stile e quindi resta byte-identica alla formula precedente.
--
--  public.stile_xp mirror esatto di public.formation_xp (stessa RLS,
--  stessi grant), solo con "stile" al posto di "modulo". La scrittura
--  avviene in registra_risultato_partita, mirror esatto del blocco
--  formation_xp gia' presente li'. Corpo completo ri-fetchato dal vivo
--  con pg_get_functiondef (mai retipizzato a memoria), poi solo il nuovo
--  blocco insert...on conflict aggiunto.
-- ============================================================

begin;

create table public.stile_xp (
  team_id          bigint not null,
  league_id        bigint not null,
  stile            text not null check (stile = any (private.stili_validi())),
  partite_giocate  smallint not null default 0 check (partite_giocate >= 0),
  aggiornata_il    timestamptz not null default now(),

  constraint stile_xp_team_league_fk
    foreign key (team_id, league_id)
    references public.teams (id, league_id) on delete cascade,
  primary key (team_id, stile)
);

create index stile_xp_league_idx on public.stile_xp (league_id);

alter table public.stile_xp enable row level security;

create policy stile_xp_lettura on public.stile_xp
  for select to authenticated
  using ((select private.e_membro(league_id)));

revoke all on table public.stile_xp from anon, authenticated, service_role;
grant select on table public.stile_xp to authenticated;
grant select, insert, update, delete on table public.stile_xp to service_role;

CREATE OR REPLACE FUNCTION public.registra_risultato_partita(p_fixture_id bigint, p_seed bigint, p_modulo_home text, p_modulo_away text, p_stile_home text, p_stile_away text, p_gol_home smallint, p_gol_away smallint, p_blocchi jsonb, p_stats_squadra jsonb, p_player_stats jsonb, p_titolari_home bigint[] DEFAULT '{}'::bigint[], p_titolari_away bigint[] DEFAULT '{}'::bigint[], p_gol_home_90 smallint DEFAULT NULL::smallint, p_gol_away_90 smallint DEFAULT NULL::smallint, p_rigori_home smallint DEFAULT NULL::smallint, p_rigori_away smallint DEFAULT NULL::smallint, p_rigori_serie jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
  if not (p_stile_home = any(private.stili_validi()))
     or not (p_stile_away = any(private.stili_validi())) then
    raise exception using errcode = '22023', message = 'Stile di gioco non valido.';
  end if;

  if not exists (
    select 1 from public.lineups l
    where l.league_id = v_fixture.league_id
      and l.team_id = v_fixture.home_team_id
      and l.giornata = v_fixture.giornata
      and l.modulo = p_modulo_home
      and l.stile_gioco = p_stile_home
  ) or not exists (
    select 1 from public.lineups l
    where l.league_id = v_fixture.league_id
      and l.team_id = v_fixture.away_team_id
      and l.giornata = v_fixture.giornata
      and l.modulo = p_modulo_away
      and l.stile_gioco = p_stile_away
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
    stile_home,
    stile_away,
    seed,
    blocchi,
    stats_squadra,
    titolari_home,
    titolari_away,
    gol_home_90,
    gol_away_90,
    rigori_home,
    rigori_away,
    rigori_serie
  ) values (
    p_fixture_id,
    v_fixture.league_id,
    p_gol_home,
    p_gol_away,
    p_modulo_home,
    p_modulo_away,
    p_stile_home,
    p_stile_away,
    p_seed,
    p_blocchi,
    p_stats_squadra,
    coalesce(p_titolari_home, '{}'::bigint[]),
    coalesce(p_titolari_away, '{}'::bigint[]),
    p_gol_home_90,
    p_gol_away_90,
    p_rigori_home,
    p_rigori_away,
    p_rigori_serie
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

  -- Le partite di playoff/playout non entrano in classifica (design §10.7):
  -- la stagione regolare e' gia' chiusa e la sua classifica e' congelata.
  if v_fixture.bracket_tie_id is null then
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
  end if;

  insert into public.formation_xp (team_id, league_id, modulo, partite_giocate)
  values
    (v_fixture.home_team_id, v_fixture.league_id, p_modulo_home, 1),
    (v_fixture.away_team_id, v_fixture.league_id, p_modulo_away, 1)
  on conflict (team_id, modulo) do update set
    partite_giocate = public.formation_xp.partite_giocate + 1,
    aggiornata_il = now();

  insert into public.stile_xp (team_id, league_id, stile, partite_giocate)
  values
    (v_fixture.home_team_id, v_fixture.league_id, p_stile_home, 1),
    (v_fixture.away_team_id, v_fixture.league_id, p_stile_away, 1)
  on conflict (team_id, stile) do update set
    partite_giocate = public.stile_xp.partite_giocate + 1,
    aggiornata_il = now();

  update public.fixtures
  set stato = 'simulata'
  where id = p_fixture_id;

  -- La posizione e' ricalcolata dopo ogni risultato. Gli scontri diretti
  -- considerano soltanto le avversarie a pari punti nella classifica attuale.
  if v_fixture.bracket_tie_id is null then
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
  end if;

  -- Un accoppiamento si risolve appena entrambe le sue mani sono giocate:
  -- da li' nasce il turno successivo, e alla fine i premi del playout.
  if v_fixture.bracket_tie_id is not null then
    perform private.risolvi_tie(v_fixture.bracket_tie_id);
  end if;

  if not exists (
    select 1 from public.fixtures
    where season_id = v_fixture.season_id
      and stato = 'programmata'
  ) then
    -- Finita la stagione regolare non si chiude subito: se la lega ha almeno
    -- 8 squadre nascono playoff e playout, con le loro fixtures (design
    -- §10.7). La stagione finisce davvero solo quando anche quelle sono state
    -- giocate, e a quel punto qui non si crea piu' nulla.
    if not exists (select 1 from public.brackets where season_id = v_fixture.season_id) then
      perform private.crea_tabelloni(v_fixture.season_id);
    end if;

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
  end if;

  return jsonb_build_object(
    'match_id', v_match.id,
    'fixture_id', v_match.fixture_id,
    'gia_simulata', false,
    'gol_home', v_match.gol_home,
    'gol_away', v_match.gol_away
  );
end;
$function$;

commit;
