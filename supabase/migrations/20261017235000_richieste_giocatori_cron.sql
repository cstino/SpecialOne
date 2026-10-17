-- Attiva il cron delle richieste dei giocatori (ogni 5 minuti): genera le richieste dopo la simulazione,
-- fa scadere quelle senza risposta e verifica a fine partita le promesse fatte.
-- Separato dalla migrazione delle tabelle per accenderlo solo a funzione e schermata pronte.
select cron.schedule('richieste-giocatori', '*/5 * * * *', 'select private.genera_richieste_giocatori(); select private.verifica_richieste();');
