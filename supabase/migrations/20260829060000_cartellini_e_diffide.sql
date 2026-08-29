begin;

-- ============================================================
--  CARTELLINI E DIFFIDE
--
--  Decisione dell'utente: i cartellini vivono dentro il motore, con
--  l'effetto vero dell'uomo in meno (vedi engine/engine.js e
--  engine/config.js, commit precedente). Questo file aggiunge la parte
--  che il motore non deve conoscere: la squalifica e' un vincolo di
--  disponibilita' della rosa, non un effetto di simulazione — stesso
--  principio gia' in vigore per infortunato_fino_a, mai passato al motore
--  come "gioca peggio" ma sempre come "non e' selezionabile".
--
--  Diffida: ogni 5 ammonizioni in stagione (DIFFIDA_SOGLIA nella Edge
--  Function) scatta una squalifica automatica di 1 giornata; il conto si
--  azzera li'. Si azzera ANCHE qui, prima dei tabelloni di fine stagione
--  regolare (private.crea_tabelloni): un giallo preso a giornata 3 non deve
--  pesare sui playoff. Una squalifica gia' in corso non si cancella con
--  questo azzeramento — solo il CONTEGGIO delle ammonizioni si ferma,
--  l'eventuale giornata di squalifica residua resta da scontare.
-- ============================================================

alter table public.player_instances
  add column if not exists ammonizioni_stagione smallint not null default 0,
  add column if not exists squalificato_fino_a  smallint not null default 0;

comment on column public.player_instances.ammonizioni_stagione is
  'Ammonizioni accumulate nella stagione corrente. Si azzera alla diffida (ogni 5) e prima dei tabelloni di fine stagione regolare (private.crea_tabelloni).';
comment on column public.player_instances.squalificato_fino_a is
  'Giornate di squalifica residue (rosso diretto, doppio giallo o diffida). Stessa convenzione di infortunato_fino_a: si scala di uno per ogni giornata giocata dalla squadra, indipendentemente da chi era davvero in campo.';


-- ------------------------------------------------------------
--  RPC di scrittura, stesso schema di public.aggiorna_condizione_rosa: la
--  Edge Function calcola i nuovi valori (compresa la soglia di diffida),
--  qui si scrive soltanto.
-- ------------------------------------------------------------

create or replace function public.aggiorna_cartellini_rosa(p_league_id bigint, p_valori jsonb)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_aggiornati integer;
begin
  if jsonb_typeof(p_valori) <> 'array' then
    raise exception using errcode = '22023', message = 'Payload cartellini non valido.';
  end if;

  with valori as (
    select *
    from jsonb_to_recordset(p_valori) as x(
      id                    bigint,
      ammonizioni_stagione  smallint,
      squalificato_fino_a   smallint
    )
  )
  update public.player_instances pi
  set ammonizioni_stagione = greatest(0, v.ammonizioni_stagione),
      squalificato_fino_a  = greatest(0, v.squalificato_fino_a)
  from valori v
  where pi.id = v.id
    and pi.league_id = p_league_id;

  get diagnostics v_aggiornati = row_count;
  return v_aggiornati;
end;
$$;

comment on function public.aggiorna_cartellini_rosa(bigint, jsonb) is
  'Scrive ammonizioni stagionali e giornate di squalifica residue calcolate dalla Edge Function di simulazione. Stesso schema di aggiorna_condizione_rosa.';

revoke all on function public.aggiorna_cartellini_rosa(bigint, jsonb) from public, anon, authenticated;
grant execute on function public.aggiorna_cartellini_rosa(bigint, jsonb) to service_role;


-- ------------------------------------------------------------
--  Notifiche: nuovo tipo 'squalifica' (rosso diretto, doppio giallo o
--  diffida), accanto a 'infortunio'.
-- ------------------------------------------------------------

alter table public.notifications drop constraint if exists notifications_tipo_check;
alter table public.notifications add constraint notifications_tipo_check
  check (tipo = any (array[
    'giornata_simulata', 'formazione_mancante', 'infortunio', 'squalifica',
    'mercato_proposta', 'mercato_esito', 'mercato_asta', 'sistema'
  ]));


-- ------------------------------------------------------------
--  Azzeramento delle ammonizioni prima dei tabelloni di fine stagione
--  regolare. Stesso corpo di private.crea_tabelloni, con una riga in piu'
--  in testa: nessuna formula del motore ne' logica di tabellone toccata.
-- ------------------------------------------------------------

create or replace function private.crea_tabelloni(p_season_id bigint)
returns jsonb
language plpgsql
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

  -- Diffida: il conto delle ammonizioni non deve attraversare il confine
  -- fra stagione regolare e playoff. Non tocca squalificato_fino_a: una
  -- squalifica gia' maturata (es. presa all'ultima giornata) resta da
  -- scontare anche ai playoff, si azzera solo il conteggio che la genera.
  update public.player_instances pi
  set ammonizioni_stagione = 0
  from public.teams t
  where pi.team_id = t.id and t.league_id = v_season.league_id and pi.ammonizioni_stagione > 0;

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

commit;
