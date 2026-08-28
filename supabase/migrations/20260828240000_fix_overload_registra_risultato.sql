-- ============================================================
--  URGENTE: RISOLVE L'AMBIGUITA' DI OVERLOAD SU registra_risultato_partita
--
--  Causa reale del blocco della simulazione notturna (non il tetto
--  salariale, che era la mia ipotesi iniziale — quella e' una causa
--  distinta e gia' corretta a parte).
--
--  20260826210000_playoff_playout_generazione.sql ha aggiunto i 5
--  parametri dei rigori/supplementari con CREATE OR REPLACE, ma senza il
--  DROP FUNCTION che ogni altra modifica a questa firma aveva sempre
--  fatto prima (vedi 20260805110000_stile_di_gioco.sql e
--  20260806090000_titolari_effettivi_partita.sql, che seguono entrambe
--  correttamente drop-poi-create). CREATE OR REPLACE non sostituisce una
--  funzione quando la firma cambia: ha coesistito con la vecchia a 13
--  parametri invece di sostituirla.
--
--  Risultato: da quando la Edge Function chiama la funzione con i 13
--  parametri di base (nome per nome, nessuna partita coinvolge rigori),
--  PostgREST trova DUE candidati validi — la firma esatta a 13 e quella a
--  18 con i 5 extra sui default — e rifiuta con PGRST203
--  "Could not choose the best candidate function". Confermato nei log
--  della Edge Function: lo stesso errore a ogni tentativo del cron dalle
--  23:55 UTC del 27 agosto, quando LegaBot ha generato le prime fixture
--  della stagione 2.
--
--  La firma a 18 parametri (oid piu' recente, dalla migrazione playoff)
--  ha i default su tutti e 7 gli argomenti che la vecchia non aveva:
--  droppare la vecchia non toglie nessuna chiamata esistente, che
--  continua a risolvere sugli stessi default.
-- ============================================================

drop function if exists public.registra_risultato_partita(
  bigint, bigint, text, text, text, text, smallint, smallint, jsonb, jsonb, jsonb, bigint[], bigint[]
);
