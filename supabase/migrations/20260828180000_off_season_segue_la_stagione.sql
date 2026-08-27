-- ============================================================
--  LA FINESTRA OFF-SEASON X SEGUE LA STAGIONE X, NON LA PRECEDE
--  docs/decisioni-draft-picks.md §3.1 (corretto il 28 agosto 2026)
--
--  Avevo implementato la lettura letterale di §3.1 nella sua prima
--  stesura: "l'off-season che porta ALLA stagione X", quindi finestra 'off'
--  di stagione X = off-season con stagione_corrente = X - 1. L'utente ha
--  corretto, con un argomento che chiude la questione: una lega nuova
--  comincia dalla stagione 1 con il draft iniziale, non da un'off-season.
--  Un "OFF-Season 1" precedente alla stagione 1 non esisterebbe mai.
--
--  Conferma indipendente dall'elenco di §3.2 — ON-Season 2, OFF-Season 2,
--  ON-Season 3, OFF-Season 3... — che e' in ordine cronologico solo se
--  OFF-X viene dopo ON-X.
--
--  Quindi: la finestra 'off' di stagione X e' quella dell'off-season che
--  si apre a fine stagione X, quando stagione_corrente vale ancora X.
--  Cambia una sola condizione, in due punti: `stagione_corrente + 1`
--  diventa `stagione_corrente`.
--
--  Verifica sui dati: Real Fampionato ha fase_carriera 'offseason' con
--  stagione_corrente 1, cioe' si trova nell'off-season che segue la
--  stagione 1. Le scelte partono da stagione 2, quindi questa off-season
--  non ha nessun draft associato — corretto, il sistema a scelte nasce
--  adesso e la sua prima finestra e' ON-Season 2.
-- ============================================================

create or replace function private.sincronizza_estrazione_off()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.finestre_scelte f
  set estrazione_il = new.offseason_fine
  where f.league_id = new.id
    and f.finestra  = 'off'
    -- L'off-season in corso segue la stagione_corrente: e' la finestra
    -- 'off' di QUELLA stagione.
    and f.stagione  = new.stagione_corrente
    and f.risolta_il is null
    and f.estrazione_il is distinct from new.offseason_fine;
  return new;
end;
$$;

comment on function private.sincronizza_estrazione_off() is
  'Tiene la finestra ''off'' della stagione corrente allineata a leagues.offseason_fine, che l''admin puo'' spostare.';

create or replace function private.svela_finestra_scelte(
  p_league_id     bigint,
  p_stagione      smallint,
  p_finestra      text,
  p_estrazione_il timestamptz default null
)
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_lega        public.leagues;
  v_totali      integer;
  v_determinate integer;
  v_quando      timestamptz;
  v_estratti    integer;
begin
  if p_finestra not in ('on', 'off') then
    raise exception using errcode = '22023', message = 'Finestra non valida: ' || p_finestra;
  end if;

  select * into v_lega from public.leagues where id = p_league_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Lega non trovata.';
  end if;

  -- Per la 'off' l'istante non si passa: e' la scadenza dell'off-season
  -- che segue quella stagione. Finche' quell'off-season non e' cominciata
  -- la scadenza non esiste, e l'istante resta ignoto.
  if p_finestra = 'off' then
    v_quando := case when p_stagione = v_lega.stagione_corrente
                     then v_lega.offseason_fine else null end;
  else
    v_quando := p_estrazione_il;
  end if;

  if v_quando is not null and v_quando <= now() then
    raise exception using errcode = '22023',
      message = 'L''estrazione va fissata nel futuro: le preferenze nascerebbero gia'' congelate.';
  end if;

  select count(*), count(*) filter (where stato = 'determinata')
    into v_totali, v_determinate
  from public.scelte_draft
  where league_id = p_league_id and stagione = p_stagione and finestra = p_finestra;

  if v_totali = 0 then
    raise exception using errcode = 'P0002',
      message = 'Nessuna scelta esiste per questa finestra: vanno generate prima.';
  end if;

  if v_determinate = 0 then
    raise exception using errcode = '55000',
      message = 'Le posizioni di questa finestra non sono ancora state assegnate: '
                || 'senza ordine di scelta la finestra non puo'' essere svelata.';
  end if;

  insert into public.finestre_scelte (league_id, stagione, finestra, estrazione_il)
  values (p_league_id, p_stagione, p_finestra, v_quando)
  on conflict (league_id, stagione, finestra) do nothing;

  v_estratti := private.estrai_pool_scelte(p_league_id, p_stagione, p_finestra);
  return v_estratti;
end;
$$;

comment on function private.svela_finestra_scelte(bigint, smallint, text, timestamptz) is
  'Svela il pool di una finestra. Per la ''off'' l''istante e'' offseason_fine della stagione stessa (l''off-season che la segue) e puo'' essere ancora ignoto. Idempotente.';

revoke all on function private.svela_finestra_scelte(bigint, smallint, text, timestamptz) from public, anon, authenticated;
grant execute on function private.svela_finestra_scelte(bigint, smallint, text, timestamptz) to service_role;
