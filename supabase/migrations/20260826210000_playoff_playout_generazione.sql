-- Generazione e avanzamento dei tabelloni (design §10.7). Quarto tassello.
--
-- I tabelloni nascono da soli quando finisce l'ultima giornata di stagione
-- regolare: registra_risultato_partita, invece di chiudere subito la stagione,
-- crea playoff e playout con le loro fixtures. La stagione si conclude davvero
-- solo quando anche quelle sono state giocate.

-- ------------------------------------------------------------
--  Ordine di tabellone standard
--
--  Per un tabellone da S posti (S potenza di 2) restituisce l'ordine dei seed
--  tale che, accoppiando gli elementi a due a due, le teste di serie stiano
--  ai lati opposti e si possano incontrare solo il piu' tardi possibile.
--  S=8 -> {1,8,4,5,2,7,3,6}, cioe' 1v8, 4v5, 2v7, 3v6.
--  Un gruppo da 6 usa S=8: i seed 7 e 8 non esistono, quindi 1 e 2 passano
--  senza giocare e restano 3v6 e 4v5 — gli accoppiamenti del design §10.7.
-- ------------------------------------------------------------
create or replace function private.ordine_tabellone(p_posti integer)
returns integer[]
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_ordine integer[] := array[1];
  v_nuovo integer[];
  v_taglia integer := 1;
  v_seed integer;
begin
  while v_taglia < p_posti loop
    v_taglia := v_taglia * 2;
    v_nuovo := array[]::integer[];
    foreach v_seed in array v_ordine loop
      v_nuovo := v_nuovo || v_seed || (v_taglia + 1 - v_seed);
    end loop;
    v_ordine := v_nuovo;
  end loop;
  return v_ordine;
end;
$$;

-- Posti del tabellone per un gruppo di p_squadre: la potenza di 2 successiva.
create or replace function private.posti_tabellone(p_squadre integer)
returns integer
language sql
immutable
set search_path = ''
as $$
  select greatest(2, 2 ^ ceil(log(2, greatest(p_squadre, 2)::numeric)))::integer
$$;

create or replace function private.turni_tabellone(p_squadre integer)
returns integer
language sql
immutable
set search_path = ''
as $$
  select ceil(log(2, greatest(private.posti_tabellone(p_squadre), 2)::numeric))::integer
$$;

-- ------------------------------------------------------------
--  Le fixtures di un accoppiamento
--
--  Andata in casa del seed peggiore, ritorno in casa del migliore (design
--  §10.7). La finale e' gara secca in campo neutro: e' il formato classico di
--  una finale unica e toglie il vantaggio di campo da una partita sola.
-- ------------------------------------------------------------
create or replace function private.crea_fixtures_tie(
  p_tie_id bigint,
  p_giornata_andata integer
)
returns integer
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_tie public.bracket_ties;
  v_bracket public.brackets;
  v_ultima_data timestamptz;
  v_ultima_giornata integer;
  v_n integer := 0;
begin
  select * into v_tie from public.bracket_ties where id = p_tie_id;
  select * into v_bracket from public.brackets where id = v_tie.bracket_id;

  -- Le eliminatorie si giocano alla stessa ora delle giornate di campionato,
  -- un turno al giorno: la data si ricava scalando dall'ultima giornata di
  -- stagione regolare, cosi' resta agganciata al ritmo gia' impostato.
  select max(data_sim), max(giornata) into v_ultima_data, v_ultima_giornata
  from public.fixtures where season_id = v_bracket.season_id and bracket_tie_id is null;

  if v_tie.gara_secca then
    insert into public.fixtures (season_id, league_id, giornata, home_team_id, away_team_id,
                                 data_sim, stato, campo_neutro, bracket_tie_id, mano)
    values (v_bracket.season_id, v_tie.league_id, p_giornata_andata,
            v_tie.alta_team_id, v_tie.bassa_team_id,
            v_ultima_data + make_interval(days => p_giornata_andata - v_ultima_giornata),
            'programmata', true, v_tie.id, 2);
    v_n := 1;
  else
    insert into public.fixtures (season_id, league_id, giornata, home_team_id, away_team_id,
                                 data_sim, stato, campo_neutro, bracket_tie_id, mano)
    values
      (v_bracket.season_id, v_tie.league_id, p_giornata_andata,
       v_tie.bassa_team_id, v_tie.alta_team_id,
       v_ultima_data + make_interval(days => p_giornata_andata - v_ultima_giornata),
       'programmata', false, v_tie.id, 1),
      (v_bracket.season_id, v_tie.league_id, p_giornata_andata + 1,
       v_tie.alta_team_id, v_tie.bassa_team_id,
       v_ultima_data + make_interval(days => p_giornata_andata + 1 - v_ultima_giornata),
       'programmata', false, v_tie.id, 2);
    v_n := 2;
  end if;

  update public.bracket_ties set stato = 'in_corso' where id = p_tie_id;
  return v_n;
end;
$$;

-- La giornata di partenza del turno globale g (1-based), sapendo che la
-- finale (turno Tmax) e' secca. Serve a far cadere le due finali lo stesso
-- giorno anche quando i due gruppi hanno un numero di turni diverso.
create or replace function private.giornata_turno(
  p_base integer, p_turno_globale integer
)
returns integer
language sql
immutable
set search_path = ''
as $$
  select p_base + 2 * (p_turno_globale - 1) + 1
$$;

-- ------------------------------------------------------------
--  Creazione dei due tabelloni dalla classifica finale
-- ------------------------------------------------------------
create or replace function private.crea_tabelloni(p_season_id bigint)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_season public.seasons;
  v_lega public.leagues;
  v_squadre bigint[];
  v_n integer;
  v_n_alta integer;
  v_n_bassa integer;
  v_turni_max integer;
  v_base integer;
  v_tipo text;
  v_gruppo bigint[];
  v_m integer;
  v_posti integer;
  v_turni integer;
  v_ordine integer[];
  v_bracket_id bigint;
  v_tie_id bigint;
  v_alta bigint; v_bassa bigint;
  v_seed_a integer; v_seed_b integer;
  v_pos integer;
  v_turno_globale integer;
  v_creati integer := 0;
begin
  select * into v_season from public.seasons where id = p_season_id;
  select * into v_lega from public.leagues where id = v_season.league_id;

  -- Classifica finale, dalla prima all'ultima.
  select array_agg(st.team_id order by st.posizione)
    into v_squadre
  from public.standings st
  join public.teams t on t.id = st.team_id and t.attiva
  where st.season_id = p_season_id and st.posizione is not null;

  v_n := coalesce(cardinality(v_squadre), 0);
  if v_n < 8 then
    -- Sotto la soglia di §10.7 non si gioca nessun tabellone.
    return jsonb_build_object('creati', 0, 'motivo', 'meno di 8 squadre');
  end if;

  v_n_alta := ceil(v_n / 2.0);
  v_n_bassa := v_n - v_n_alta;
  v_turni_max := greatest(private.turni_tabellone(v_n_alta), private.turni_tabellone(v_n_bassa));
  select max(giornata) into v_base from public.fixtures
  where season_id = p_season_id and bracket_tie_id is null;

  foreach v_tipo in array array['playoff', 'playout'] loop
    if v_tipo = 'playoff' then
      -- Prime ceil(N/2): con N dispari la squadra di mezzo sta in alto.
      v_gruppo := v_squadre[1:v_n_alta];
    else
      -- Ultime floor(N/2), ma ORDINATE AL CONTRARIO: la testa di serie del
      -- playout e' l'ultima in classifica assoluta (design §10.7).
      select array_agg(x order by ord desc)
        into v_gruppo
      from unnest(v_squadre[v_n_alta + 1:v_n]) with ordinality as u(x, ord);
    end if;

    v_m := cardinality(v_gruppo);
    v_posti := private.posti_tabellone(v_m);
    v_turni := private.turni_tabellone(v_m);
    v_ordine := private.ordine_tabellone(v_posti);

    insert into public.brackets (league_id, season_id, tipo)
    values (v_season.league_id, p_season_id, v_tipo)
    on conflict (season_id, tipo) do nothing
    returning id into v_bracket_id;
    if v_bracket_id is null then continue; end if;

    -- Turno 1: le coppie dell'ordine standard. Un seed oltre v_m non esiste,
    -- quindi l'altro passa senza giocare.
    v_pos := 0;
    v_turno_globale := v_turni_max - v_turni + 1;
    for i in 1..(v_posti / 2) loop
      v_seed_a := v_ordine[i * 2 - 1];
      v_seed_b := v_ordine[i * 2];
      v_alta := case when v_seed_a <= v_m then v_gruppo[v_seed_a] end;
      v_bassa := case when v_seed_b <= v_m then v_gruppo[v_seed_b] end;

      insert into public.bracket_ties (
        bracket_id, league_id, turno, posizione,
        alta_team_id, bassa_team_id, alta_seed, bassa_seed,
        gara_secca, vincitore_team_id, stato
      ) values (
        v_bracket_id, v_season.league_id, 1, v_pos,
        v_alta, v_bassa,
        case when v_seed_a <= v_m then v_seed_a end,
        case when v_seed_b <= v_m then v_seed_b end,
        v_turni = 1,
        -- Bye: se manca un lato, l'altro e' gia' qualificato.
        case when v_bassa is null then v_alta when v_alta is null then v_bassa end,
        case when v_alta is null or v_bassa is null then 'concluso' else 'in_attesa' end
      ) returning id into v_tie_id;

      if v_alta is not null and v_bassa is not null then
        perform private.crea_fixtures_tie(v_tie_id, private.giornata_turno(v_base, v_turno_globale));
      end if;
      v_pos := v_pos + 1;
      v_creati := v_creati + 1;
    end loop;

    -- Se il primo turno era tutto bye (gruppo gia' potenza di 2 con byes),
    -- si avanza subito.
    perform private.avanza_bracket(v_bracket_id);
  end loop;

  return jsonb_build_object('creati', v_creati, 'squadre', v_n, 'turni_max', v_turni_max);
end;
$$;

-- ------------------------------------------------------------
--  Avanzamento: crea il turno successivo quando quello corrente e' completo
-- ------------------------------------------------------------
create or replace function private.avanza_bracket(p_bracket_id bigint)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_bracket public.brackets;
  v_lega public.leagues;
  v_turno integer;
  v_rimasti integer;
  v_vincitori bigint[];
  v_seeds integer[];
  v_n_ties integer;
  v_base integer;
  v_turni_max integer;
  v_turno_globale integer;
  v_tie_id bigint;
  v_alta bigint; v_bassa bigint;
  v_seed_a integer; v_seed_b integer;
  v_premio bigint;
  v_saldo bigint;
  v_finalista bigint;
begin
  select * into v_bracket from public.brackets where id = p_bracket_id for update;
  if v_bracket.stato = 'concluso' then return; end if;
  select * into v_lega from public.leagues where id = v_bracket.league_id;

  select max(turno) into v_turno from public.bracket_ties where bracket_id = p_bracket_id;
  select count(*) into v_rimasti from public.bracket_ties
  where bracket_id = p_bracket_id and turno = v_turno and stato <> 'concluso';
  if v_rimasti > 0 then return; end if;

  select count(*) into v_n_ties from public.bracket_ties
  where bracket_id = p_bracket_id and turno = v_turno;

  -- Turno finale concluso: si assegnano titolo e premi.
  if v_n_ties = 1 then
    select vincitore_team_id,
           case when alta_team_id = vincitore_team_id then bassa_team_id else alta_team_id end
      into v_bracket.vincitore_team_id, v_finalista
    from public.bracket_ties where bracket_id = p_bracket_id and turno = v_turno;

    update public.brackets
    set stato = 'concluso', concluso_il = now(),
        vincitore_team_id = v_bracket.vincitore_team_id,
        finalista_team_id = v_finalista
    where id = p_bracket_id;

    if v_bracket.tipo = 'playout' then
      -- 0,10 x B al vincitore, 0,05 x B al finalista (design §10.7).
      v_premio := round((v_lega.budget_iniziale * 0.10)::numeric / 100000) * 100000;
      update public.teams set budget = budget + v_premio
      where id = v_bracket.vincitore_team_id returning budget into v_saldo;
      insert into public.transactions(league_id, team_id, tipo, importo, descrizione, saldo_dopo)
      values (v_bracket.league_id, v_bracket.vincitore_team_id, 'premio_playout', v_premio,
              'Vittoria del playout', v_saldo);

      v_premio := round((v_lega.budget_iniziale * 0.05)::numeric / 100000) * 100000;
      update public.teams set budget = budget + v_premio
      where id = v_finalista returning budget into v_saldo;
      insert into public.transactions(league_id, team_id, tipo, importo, descrizione, saldo_dopo)
      values (v_bracket.league_id, v_finalista, 'premio_playout', v_premio,
              'Finale del playout', v_saldo);
    end if;
    return;
  end if;

  -- Altrimenti si costruisce il turno successivo accoppiando i vincitori
  -- adiacenti: 0 con 1, 2 con 3, e cosi' via.
  select array_agg(vincitore_team_id order by posizione),
         array_agg(coalesce(
           case when vincitore_team_id = alta_team_id then alta_seed else bassa_seed end,
           999) order by posizione)
    into v_vincitori, v_seeds
  from public.bracket_ties where bracket_id = p_bracket_id and turno = v_turno;

  select max(giornata) into v_base from public.fixtures
  where season_id = v_bracket.season_id and bracket_tie_id is null;
  select greatest(
      private.turni_tabellone(ceil(count(*) / 2.0)::integer),
      private.turni_tabellone(floor(count(*) / 2.0)::integer))
    into v_turni_max
  from public.standings st join public.teams t on t.id = st.team_id and t.attiva
  where st.season_id = v_bracket.season_id and st.posizione is not null;

  -- Quanti turni restano a questo tabellone, per allineare la finale.
  v_turno_globale := v_turni_max - (ceil(log(2, greatest(v_n_ties, 2)::numeric))::integer);

  for i in 1..(v_n_ties / 2) loop
    -- Fra i due qualificati, il seed migliore (numero piu' basso) e' la "alta".
    if v_seeds[i * 2 - 1] <= v_seeds[i * 2] then
      v_alta := v_vincitori[i * 2 - 1]; v_seed_a := v_seeds[i * 2 - 1];
      v_bassa := v_vincitori[i * 2];     v_seed_b := v_seeds[i * 2];
    else
      v_alta := v_vincitori[i * 2];     v_seed_a := v_seeds[i * 2];
      v_bassa := v_vincitori[i * 2 - 1]; v_seed_b := v_seeds[i * 2 - 1];
    end if;

    insert into public.bracket_ties (
      bracket_id, league_id, turno, posizione,
      alta_team_id, bassa_team_id, alta_seed, bassa_seed, gara_secca
    ) values (
      p_bracket_id, v_bracket.league_id, v_turno + 1, i - 1,
      v_alta, v_bassa, v_seed_a, v_seed_b,
      (v_n_ties / 2) = 1
    ) returning id into v_tie_id;

    perform private.crea_fixtures_tie(v_tie_id, private.giornata_turno(v_base, v_turno_globale + 1));
  end loop;
end;
$$;

-- ------------------------------------------------------------
--  Risoluzione di un accoppiamento quando tutte le sue partite sono giocate
-- ------------------------------------------------------------
create or replace function private.risolvi_tie(p_tie_id bigint)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_tie public.bracket_ties;
  v_da_giocare integer;
  v_gol_alta integer := 0;
  v_gol_bassa integer := 0;
  v_rig_alta integer;
  v_rig_bassa integer;
  v_vincitore bigint;
begin
  select * into v_tie from public.bracket_ties where id = p_tie_id for update;
  if v_tie.stato = 'concluso' then return; end if;

  select count(*) into v_da_giocare from public.fixtures
  where bracket_tie_id = p_tie_id and stato <> 'simulata';
  if v_da_giocare > 0 then return; end if;

  -- Aggregato sulle due mani (o sull'unica gara secca). I gol in trasferta
  -- non valgono doppio: regola UEFA post-2021, design §10.7.
  select
    coalesce(sum(case when f.home_team_id = v_tie.alta_team_id then m.gol_home else m.gol_away end), 0),
    coalesce(sum(case when f.home_team_id = v_tie.alta_team_id then m.gol_away else m.gol_home end), 0)
  into v_gol_alta, v_gol_bassa
  from public.fixtures f join public.matches m on m.fixture_id = f.id
  where f.bracket_tie_id = p_tie_id;

  if v_gol_alta > v_gol_bassa then
    v_vincitore := v_tie.alta_team_id;
  elsif v_gol_bassa > v_gol_alta then
    v_vincitore := v_tie.bassa_team_id;
  else
    -- Parita' anche dopo i supplementari: decidono i rigori dell'ultima mano.
    select
      case when f.home_team_id = v_tie.alta_team_id then m.rigori_home else m.rigori_away end,
      case when f.home_team_id = v_tie.alta_team_id then m.rigori_away else m.rigori_home end
    into v_rig_alta, v_rig_bassa
    from public.fixtures f join public.matches m on m.fixture_id = f.id
    where f.bracket_tie_id = p_tie_id and m.rigori_home is not null
    order by f.mano desc limit 1;

    if v_rig_alta is null then
      -- Nessuna sequenza registrata: non deve accadere, ma un tabellone
      -- bloccato sarebbe peggio di un criterio di riserva. Passa il seed
      -- migliore, coerentemente con il resto del regolamento.
      v_vincitore := v_tie.alta_team_id;
    elsif v_rig_alta > v_rig_bassa then
      v_vincitore := v_tie.alta_team_id;
    else
      v_vincitore := v_tie.bassa_team_id;
    end if;
  end if;

  update public.bracket_ties
  set vincitore_team_id = v_vincitore, stato = 'concluso'
  where id = p_tie_id;

  perform private.avanza_bracket(v_tie.bracket_id);
end;
$$;

revoke all on function private.crea_tabelloni(bigint) from public, anon, authenticated;
revoke all on function private.avanza_bracket(bigint) from public, anon, authenticated;
revoke all on function private.risolvi_tie(bigint) from public, anon, authenticated;
revoke all on function private.crea_fixtures_tie(bigint, integer) from public, anon, authenticated;

-- ------------------------------------------------------------
--  registra_risultato_partita: le partite di tabellone non entrano
--  in classifica, risolvono il loro accoppiamento, e la fine della
--  stagione regolare fa nascere i tabelloni invece di chiudere tutto.
--  (unica modifica: il resto e' identico alla versione live)
-- ------------------------------------------------------------

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

revoke all on function public.registra_risultato_partita(bigint, bigint, text, text, text, text, smallint, smallint, jsonb, jsonb, jsonb, bigint[], bigint[], smallint, smallint, smallint, smallint, jsonb) from public, anon;
grant execute on function public.registra_risultato_partita(bigint, bigint, text, text, text, text, smallint, smallint, jsonb, jsonb, jsonb, bigint[], bigint[], smallint, smallint, smallint, smallint, jsonb) to service_role;
