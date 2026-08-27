-- ============================================================
--  IL DRAFT SMETTE DI CALCOLARE LA SPESA DALLA CASSA
--  docs/decisioni-economia.md §3 ("Draft")
--
--  Indagine preliminare, per chiarire cosa serviva DAVVERO cambiare qui e
--  cosa no — l'utente ha confermato che il tetto del draft resta
--  leagues.budget_draft, un tetto separato da leagues.tetto_ingaggi
--  (28 agosto 2026, "due tetti distinti, come oggi").
--
--  1. private.pick_sostenibile e' GIA' un controllo a tetto puro:
--       tetto_ingaggi_param - speso - ingaggio_teorico(...) >= riserva
--     Il suo primo parametro p_budget non e' nemmeno usato nella formula
--     (residuo di una versione precedente). Non serve toccarlo.
--
--  2. Il "vincolo di solvibilita'" di CLAUDE.md §7 con la riserva doppia
--     per i portieri e' logica MORTA: portieri_minimi e' stato azzerato e
--     bloccato a 0 il 2 agosto (20260802234000_rimuovi_minimo_portieri),
--     quindi la riserva per portieri mancanti non ha piu' senso e infatti
--     pick_sostenibile non la calcola.
--
--  3. contratto_scadenza e' gia' corretto per le squadre che entrano in
--     off-season: lo imposta il trigger player_instances_scadenza_contratto
--     (20260802215000), non l'insert. Verificato sui dati: le squadre
--     entrate in stagione 2 di Real Fampionato hanno gia' tutte
--     contratto_scadenza=2. Nessuna correzione necessaria.
--
--  L'UNICA cosa davvero cash-based rimasta e' v_speso, calcolato come
--  `budget_iniziale - budget`. Oggi il risultato e' corretto (nulla tocca
--  budget di una squadra a meta' draft, tranne il draft stesso), ma la
--  dipendenza da teams.budget non sopravvivrebbe al passo 5, che elimina
--  quella colonna. Si sostituisce con private.spesa_draft, che calcola la
--  stessa cosa dalla fonte diretta (le istanze gia' draftate) invece che
--  per differenza su un contatore che sta per sparire.
--
--  NON tocca gli aggiornamenti a teams.budget (restano, per ora: la
--  pagina Finanza li legge ancora e la sua pulizia e' il passo 6).
--
--  Tecnica: patch chirurgica via pg_get_functiondef + replace, come gia'
--  usato in 20260808191000 per completa_draft_squadra_pc. Riscrivere a
--  mano sette funzioni (~700 righe) per una riga di differenza ciascuna
--  sarebbe solo occasione di battitura.
-- ============================================================

do $$
declare
  v_bersagli regprocedure[] := array[
    'private.pacchetto_payload(bigint,bigint)'::regprocedure,
    'draft_apri_pacchetto_2_of_4_impl(bigint)'::regprocedure,
    'draft_scegli_pacchetto_2_of_4_impl(bigint,bigint,bigint)'::regprocedure,
    'private.by_role_payload(bigint,bigint)'::regprocedure,
    'draft_by_role_spin(bigint,text)'::regprocedure,
    'draft_by_role_reroll(bigint)'::regprocedure,
    'draft_by_role_ingaggia(bigint,bigint)'::regprocedure,
    -- Trovata solo in fase di verifica: stesso pattern, per le squadre
    -- controllate dal PC, che draftano da sole con lo stesso identico
    -- criterio di sostenibilita' delle squadre umane.
    'private.completa_draft_squadra_pc(bigint,bigint)'::regprocedure
  ];
  v_fn      regprocedure;
  v_sql     text;
  v_nuovo   text;
  v_vecchia constant text := 'v_speso := v_league.budget_iniziale - v_team.budget;';
  v_nuova   constant text := 'v_speso := private.spesa_draft(v_team.id);';
begin
  foreach v_fn in array v_bersagli loop
    select pg_get_functiondef(v_fn) into v_sql;
    -- Idempotente: se il patch e' gia' presente (riesecuzione della
    -- migrazione), salta senza errori. Solleva solo se la riga non e' ne'
    -- quella vecchia ne' quella nuova: significa che la funzione e'
    -- cambiata rispetto a quanto verificato, e va controllata a mano
    -- prima di patcharla alla cieca.
    if position(v_nuova in v_sql) > 0 then
      continue;
    end if;
    v_nuovo := replace(v_sql, v_vecchia, v_nuova);
    if v_nuovo = v_sql then
      raise exception 'Riga non trovata in %: la funzione e'' cambiata rispetto a quanto verificato, controllare a mano.', v_fn;
    end if;
    execute v_nuovo;
  end loop;
end $$;
