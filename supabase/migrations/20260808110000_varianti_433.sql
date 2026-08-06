-- ============================================================
--  VARIANTI DEL 4-3-3: OFFENSIVO (CAM) E DIFENSIVO (CDM)
--
--  Richiesto dall'utente: pochi moduli usano CAM o CDM (solo il 4-2-3-1).
--  Due nuove voci derivate dal 4-3-3, che cambiano solo uno dei tre CM
--  centrali:
--  - 4-3-3 offensivo: CM, CM, CAM al posto di CM, CM, CM
--  - 4-3-3 difensivo: CM, CM, CDM al posto di CM, CM, CM
--
--  Aggiunte a engine/config.js (MODULI) e validate con
--  node tools/validazione/simulate.js: nessuna delle 13 metriche target
--  peggiora, i due nuovi moduli si inseriscono in mezzo al gruppo nel
--  torneo di bilanciamento (1.378 e 1.349 punti/partita su un range
--  1.335-1.413 fra tutti e nove i moduli), scarto massimo 0.078 contro un
--  target di 0.000-0.220 (anche piu' stretto del baseline a 7 moduli,
--  0.122). Nessuna formula toccata: il profilo strutturale si calcola gia'
--  a runtime dal monte-pesi degli slot (design.md §6.4), non serve
--  ritarare nulla a mano.
-- ============================================================

create or replace function private.moduli_validi()
returns text[]
language sql
immutable
parallel safe
set search_path = ''
as $$
  select array[
    '4-3-3','4-3-3 offensivo','4-3-3 difensivo',
    '4-4-2','4-2-3-1','3-5-2','3-4-3','5-3-2','4-2-4'
  ]::text[];
$$;
