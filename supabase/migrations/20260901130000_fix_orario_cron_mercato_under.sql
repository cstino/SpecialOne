-- ============================================================
--  FIX: il mercato UNDER non estraeva mai (ne' risolveva le aste).
--
--  cron.timezone e' GMT (UTC), ma le due schedule erano scritte come se
--  pg_cron leggesse l'ora di Roma: '46 23 * * *' (23:46 UTC) doveva
--  coincidere col controllo interno di estrai_under() (Europe/Rome fra
--  23:30 e 23:45), e '2 21 * * *' (21:02 UTC) con quello di
--  risolvi_aste_under() (ora di Roma = 21). Con l'ora legale (UTC+2)
--  23:46 UTC sono le 01:46 del giorno dopo a Roma, e 21:02 UTC sono le
--  23:02: nessuno dei due cade mai nella finestra richiesta. La lega
--  non ha mai sbagliato "oggi": non ha mai potuto funzionare, e
--  smettera' di nuovo al cambio dell'ora legale anche se per assurdo
--  qualcuno avesse ricalcolato l'offset giusto per l'estate.
--
--  Fix: stesso schema gia' usato per svincolati e aste (estrazione-
--  svincolati, risoluzione-aste) — schedule frequenti, il controllo
--  vero sull'ora di Roma resta dentro la funzione SQL. Cosi' non serve
--  ricalcolare nulla al cambio stagione, e la finestra di 15 minuti di
--  estrai_under() viene comunque intercettata.
-- ============================================================

select cron.schedule(
  'estrazione-under',
  '*/5 * * * *',
  $cron$select private.estrai_under();$cron$
);

select cron.schedule(
  'risoluzione-aste-under',
  '2 * * * *',
  $cron$select private.risolvi_aste_under();$cron$
);
