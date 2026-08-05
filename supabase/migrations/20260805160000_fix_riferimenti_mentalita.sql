-- I commenti di 20260805150000 citano "design §11" per mentalità e morale, ma
-- §11 è il modello dati — citato per numero da sei migrazioni storiche, quindi
-- non rinumerabile. La sezione è stata scritta come §10 bis: qui si allineano i
-- commenti, perché un riferimento sbagliato manda il prossimo agent a leggere
-- la sezione sbagliata. Solo metadati, nessun cambiamento di comportamento.

comment on column public.players.mentalita_bandiera is
  'Mentalità §10bis.1: attaccamento alla maglia. I tre rami sommano sempre 100. Generata dall''id, identica in ogni lega.';

comment on column public.player_instances.morale is
  'Morale §10bis.3, 0-100. Ricalcolato a ogni quarto di stagione da applica_morale_checkpoint.';

comment on function public.applica_morale_checkpoint(bigint, smallint) is
  'Ricalcola il morale della lega al quarto di stagione raggiunto (design §10bis.3). Idempotente per (stagione, checkpoint).';
