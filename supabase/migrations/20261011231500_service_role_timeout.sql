-- La simulazione notturna andava in timeout (11 ottobre 2026, 23:00): attributi_correnti per tutte le rose di Serie F
-- (609 giocatori) impiega circa 10 s, oltre gli 8 s che PostgREST concede di default (statement_timeout del ruolo
-- authenticator). La Edge Function usa il ruolo service_role: gli si da' un limite suo, piu' largo. Solo service_role
-- (server), gli utenti restano a 8 s.
alter role service_role set statement_timeout = '60s';
notify pgrst, 'reload config';
