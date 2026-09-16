-- ============================================================
--  IL TRAINING SI CHIUDE AL MINUTO, NON OGNI QUARTO D'ORA
--
--  Segnalato il 14 settembre 2026 alle 23:05: la scheda mostrava "Pronto tra 0
--  giornate" con la barra piena, l'allenamento ancora in corso e il cambio
--  ruolo bloccato da un allenamento che di fatto era finito.
--
--  Non era un errore di calcolo. La catena:
--
--    1. la giornata 16 di Serie F viene simulata in serata, quindi la prima
--       giornata ancora da giocare diventa la 17;
--    2. da quell'istante le 27 specializzazioni con completa_giornata = 17
--       soddisfano la condizione di completamento (completa_giornata <=
--       prossima giornata programmata);
--    3. ma i due job che le chiudono giravano ogni 15 minuti. L'ultima
--       esecuzione era delle 23:00 e la segnalazione e' arrivata alle 23:05.
--
--  Per un quarto d'ora dopo ogni simulazione, quindi, un'intera lega poteva
--  vedere allenamenti conclusi ma non ancora chiusi — e restare bloccata
--  nell'avviarne di nuovi, perche' l'esclusivita' e' controllata sulla riga
--  ancora aperta.
--
--  I due job passano al minuto, come gli altri cinque del progetto. Le due
--  funzioni erano gia' scritte per girare a vuoto senza costo: scorrono le
--  leghe in stagione e non trovano nulla da fare quasi sempre. Non si scrive
--  un orario perche' cron.timezone e' GMT e l'ora di Roma si sposta con l'ora
--  legale: gira sempre, ed e' la funzione a decidere se c'e' qualcosa da fare.
-- ============================================================

do $$
begin
  perform cron.unschedule('completa-cambi-ruolo');
exception when others then null;
end $$;

do $$
begin
  perform cron.unschedule('completa-specializzazioni');
exception when others then null;
end $$;

select cron.schedule('completa-cambi-ruolo', '* * * * *', 'select private.completa_cambi_ruolo();');
select cron.schedule('completa-specializzazioni', '* * * * *', 'select private.completa_specializzazioni();');

-- Chiude subito gli allenamenti gia' dovuti, senza aspettare il primo giro:
-- sono quelli che hanno fatto nascere la segnalazione.
select private.completa_cambi_ruolo() as cambi_ruolo_chiusi;
select private.completa_specializzazioni() as specializzazioni_chiuse;
