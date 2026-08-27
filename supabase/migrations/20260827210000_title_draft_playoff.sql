-- ============================================================
--  PLAYOFF A DOPPIO TABELLONE — passo 2b: Title Playoff / Draft Playoff
--  docs/decisioni-draft-picks.md §1
--
--  Sostituisce Playoff/Playout (docs/design.md §10.7, gia' live ma senza
--  che nessun tabellone sia mai stato generato finora — nessuna riga in
--  brackets su nessuna lega, verificato prima di questa migrazione: e'
--  sicuro riscrivere senza dover gestire stato in corso).
--
--  Cosa cambia rispetto a prima:
--   - Il gruppo alto (ora "title") non e' piu' meta' classifica: sono
--     sempre le prime 8, punto fisso, a prescindere da quante squadre
--     ha la lega (docs/decisioni-draft-picks.md §1.1).
--   - Il gruppo basso (ora "draft") e' il resto — puo' avere qualunque
--     dimensione, anche 0 o 1 (una lega da 8 squadre non ha Draft
--     Playoff: nessun tabellone basso; una da 9 ne ha uno da 1 squadra,
--     che vince a tavolino, comportamento gia' presente nel codice
--     originale e non toccato qui).
--   - Il seeding del Draft Playoff usa l'accoppiamento adiacente
--     (private.ordine_draft_playoff, migrazione precedente), non piu'
--     quello incrociato.
--   - Il Draft Playoff non paga piu' premi in denaro al vincitore e al
--     finalista: la ricompensa e' la posizione nell'ordine di scelta
--     della stagione successiva (docs/decisioni-draft-picks.md §2.2),
--     non ancora collegata qui — l'assegnazione delle posizioni in
--     scelte_draft resta un passo a parte.
-- ============================================================

alter table public.brackets drop constraint brackets_tipo_check;
alter table public.brackets add constraint brackets_tipo_check
  check (tipo = any (array['title', 'draft']));

comment on column public.brackets.tipo is
  'title: le prime 8 in classifica, si gioca il titolo (seeding incrociato). draft: il resto, seeding ad accoppiamento adiacente, il piazzamento determina l''ordine di scelta della stagione successiva. docs/decisioni-draft-picks.md';

-- ------------------------------------------------------------
--  Creazione dei due tabelloni dalla classifica finale — sostituisce la
--  versione playoff/playout. Soglia d'ingresso (8 squadre) e struttura
--  del turno 1/avanzamento identiche a prima; cambiano solo la
--  composizione dei due gruppi e il seeding del gruppo basso.
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

  -- Title Playoff: sempre le prime 8, punto fisso (§1.1). Draft Playoff:
  -- il resto, puo' essere vuoto (v_n = 8) o anche una sola squadra.
  v_n_alta := 8;
  v_n_bassa := v_n - v_n_alta;
  v_turni_max := private.turni_tabellone(v_n_alta);
  if v_n_bassa >= 1 then
    v_turni_max := greatest(v_turni_max, private.turni_tabellone(v_n_bassa));
  end if;
  select max(giornata) into v_base from public.fixtures
  where season_id = p_season_id and bracket_tie_id is null;

  foreach v_tipo in array array['title', 'draft'] loop
    if v_tipo = 'title' then
      v_gruppo := v_squadre[1:v_n_alta];
    else
      if v_n_bassa < 1 then continue; end if;
      -- Ordinato al contrario: la testa di serie del Draft Playoff e'
      -- l'ultima in classifica assoluta, stesso principio di prima.
      select array_agg(x order by ord desc)
        into v_gruppo
      from unnest(v_squadre[v_n_alta + 1:v_n]) with ordinality as u(x, ord);
    end if;

    v_m := cardinality(v_gruppo);
    v_posti := private.posti_tabellone(v_m);
    v_turni := private.turni_tabellone(v_m);
    v_ordine := case when v_tipo = 'title'
      then private.ordine_tabellone(v_posti)
      else private.ordine_draft_playoff(v_m)
    end;

    insert into public.brackets (league_id, season_id, tipo)
    values (v_season.league_id, p_season_id, v_tipo)
    on conflict (season_id, tipo) do nothing
    returning id into v_bracket_id;
    if v_bracket_id is null then continue; end if;

    -- Turno 1: le coppie dell'ordine (incrociato per il title, adiacente
    -- per il draft). Un seed oltre v_m non esiste, quindi l'altro passa
    -- senza giocare.
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

    -- Se il primo turno era tutto bye (gruppo gia' potenza di 2 con byes,
    -- o gruppo da una sola squadra), si avanza subito.
    perform private.avanza_bracket(v_bracket_id);
  end loop;

  return jsonb_build_object('creati', v_creati, 'squadre', v_n, 'turni_max', v_turni_max);
end;
$$;

-- ------------------------------------------------------------
--  Avanzamento: identico a prima, tranne che alla conclusione del Draft
--  Playoff non paga piu' premi in denaro (docs/decisioni-draft-picks.md
--  §2.2: la ricompensa e' l'ordine di scelta, non il denaro).
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

  -- Turno finale concluso: si assegna il vincitore. Nessun premio in
  -- denaro (ne' per il title ne' per il draft playoff): il primo da'
  -- il titolo, il secondo determina l'ordine di scelta della prossima
  -- stagione (assegnazione ancora da collegare).
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
      private.turni_tabellone(least(8, count(*))::integer),
      private.turni_tabellone(greatest(count(*) - 8, 0)::integer))
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

revoke all on function private.crea_tabelloni(bigint) from public, anon, authenticated;
revoke all on function private.avanza_bracket(bigint) from public, anon, authenticated;
