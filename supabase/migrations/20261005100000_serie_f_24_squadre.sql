-- ============================================================
--  SERIE F: PRONTA AD ACCOGLIERE LE 8 NUOVE SQUADRE (5 ottobre 2026)
--  - n_squadre 24: entra_in_lega rifiuta chi arriva oltre n_squadre
--    ("numero massimo di squadre"), quindi senza questo i nuovi non entrano;
--  - budget_draft 48 M EUR (uguale per tutti i nuovi, deciso dal committente):
--    il mini-draft delle nuove squadre usa questo valore; le 16 esistenti
--    hanno gia' completato il loro draft;
--  - conferenze_attive: se l'off-season si chiudesse prima del previsto, nascerebbe
--    il sorteggio East/West (22 giornate) e non un calendario unico a 24 squadre.
--  Il committente continua a posticipare a mano la scadenza dell'off-season.
-- ============================================================

update public.leagues
set n_squadre = 24, budget_draft = 48000000, conferenze_attive = true
where id = 63;
