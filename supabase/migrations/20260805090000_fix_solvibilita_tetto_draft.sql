-- ============================================================
--  FIX: il vincolo di solvibilita' del draft (design §4.4) controllava il
--  budget iniziale residuo, non il tetto draft residuo
--
--  Segnalato dall'utente su una lega reale (Fampionato, id 34, budget
--  iniziale 70M / tetto draft 40M): due squadre su cinque sono arrivate
--  vicino alla fine del draft senza piu' margine sotto al tetto per
--  completare la rosa a 24 slot, bloccando l'avvio della stagione.
--
--  private.pick_sostenibile (introdotta in 20260803120000_draft_pacchetti.sql,
--  poi in 20260804160000_budget_draft_configurabile.sql per il tetto
--  configurabile) confrontava la riserva per gli slot rimanenti col
--  PORTAFOGLIO della squadra (budget_iniziale - speso), non col TETTO DRAFT
--  residuo (budget_draft - speso):
--
--    p_budget - ingaggio >= slot_liberi_dopo_pick * 0,5M     -- portafoglio, non tetto
--    and p_speso + ingaggio <= p_tetto_ingaggi                -- solo QUESTO pick
--
--  Quando budget_draft e' vicino a budget_iniziale (l'80% di default) il
--  bug quasi non si vedeva. Con un tetto scelto molto piu' stretto del
--  budget iniziale (com'e' ora possibile dalla configurabilita' del 4
--  agosto) il portafoglio residuo resta sempre ampiamente sufficiente anche
--  quando il tetto draft e' ormai esaurito: il vincolo non blocca mai nulla
--  in pratica, ed e' esattamente il deadlock descritto in CLAUDE.md §7.
--
--  Verificato sui dati reali della lega 34: Amburgo a 22/24 aveva speso
--  39,5M dei 40M di tetto (margine 0,5M, ne servivano 1,0M per 2 slot);
--  Team AS Turbo a 16/24 aveva speso 38,8M (margine 1,2M, ne servivano 4,0M
--  per 8 slot). In entrambi i casi il portafoglio residuo (30-31M sui 70M
--  iniziali) era piu' che sufficiente, quindi la prima meta' della verifica
--  non aveva mai bloccato nulla.
--
--  Corretto riscrivendo la riserva sul tetto draft residuo:
--
--    p_tetto_ingaggi - p_speso - ingaggio >= slot_liberi_dopo_pick * 0,5M
--
--  che assorbe anche il vecchio secondo controllo (al'ultimo slot,
--  slot_liberi_dopo_pick = 0, la condizione diventa speso + ingaggio <=
--  tetto). Dato che budget_draft ha un minimo di 20M (vincolo gia' in DB) e
--  24 slot al floor di 0,5M richiedono 12M, il draft e' ora completabile per
--  costruzione qualunque sia la combinazione di budget_iniziale/budget_draft
--  scelta dall'admin. p_budget resta nella firma solo per non toccare le
--  4 chiamate esistenti (pacchetto_payload, draft_apri_pacchetto x4,
--  draft_scegli_pacchetto x2): non serve piu' al calcolo.
--
--  Lega 34 non recuperata da questa migrazione: l'utente ha scelto di
--  cancellarla e ricrearla piuttosto che sbloccare le due squadre incastrate
--  con dati gia' scritti sopra al nuovo tetto corretto.
-- ============================================================

create or replace function private.pick_sostenibile(
  p_budget bigint,
  p_tetto_ingaggi bigint,
  p_speso bigint,
  p_slot_rosa smallint,
  p_giocatori_attuali integer,
  p_overall smallint,
  p_eta smallint
) returns boolean
language sql
immutable
parallel safe
set search_path = ''
as $$
  select
    p_tetto_ingaggi - p_speso - private.ingaggio_teorico(p_overall, p_eta)
      >= greatest(0, p_slot_rosa - p_giocatori_attuali - 1) * 500000
$$;
