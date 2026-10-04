-- ============================================================
--  NOME COMPLETO DEI GIOCATORI
--  Richiesta del committente, 4 ottobre 2026: nella scheda giocatore si vede
--  il nome per intero (piu' piccolo) sopra il cognome, invece dell'iniziale
--  puntata del dataset ("K. Nedeljkovic").
--
--  Il dataset FC 26 ha il campo long_name, finora non importato. La colonna
--  si riempie con tools/importazione/nome_completo.py (una tantum, dal CSV
--  originale). I giocatori generati (vivaio, regen) non ce l'hanno: restano
--  con il solo nome breve.
-- ============================================================

alter table public.players add column if not exists nome_completo text;

comment on column public.players.nome_completo is
  'Nome completo dal dataset FC 26 (long_name), ripulito dagli alfabeti non latini. Vuoto per i giocatori generati.';
