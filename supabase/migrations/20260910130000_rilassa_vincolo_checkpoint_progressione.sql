-- ============================================================
--  VINCOLO RESIDUO DEL VECCHIO SCHEMA A QUATTRO QUARTI
--
--  Scoperto testando dal vivo la migrazione precedente (20260910120000):
--  season_progression_checkpoints aveva un check "checkpoint between 1 and
--  4", risalente a quando quella colonna significava "numero del quarto".
--  Ora significa "numero della giornata", che puo' arrivare fino a
--  giornate_totali (oggi al massimo 30 fra le leghe esistenti, ma
--  configurabile dall'admin per ogni lega — nessun limite fisso ha senso).
--
--  season_vivaio_checkpoints non ha mai avuto un vincolo analogo: solo
--  questa tabella va corretta.
-- ============================================================

begin;

alter table public.season_progression_checkpoints
  drop constraint season_progression_checkpoints_checkpoint_check;
alter table public.season_progression_checkpoints
  add constraint season_progression_checkpoints_checkpoint_check
  check (checkpoint >= 1);

commit;
