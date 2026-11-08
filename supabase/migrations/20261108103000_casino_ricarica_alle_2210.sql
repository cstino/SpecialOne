-- Crediti giornalieri del casino' alle 22:10 Roma, come dice l'app: con la simulazione spostata alle 22:00
-- (20261105210000) era cambiato solo l'orario mostrato ('prossima_ricarica'), mentre il giorno dei crediti scattava
-- ancora alle 23:10 (segnalazione dell'8/11/2026: crediti non arrivati alle 22:10). Il giorno nuovo parte 1 h 50' prima
-- della mezzanotte. Vale anche per il conteggio giornaliero delle bustine, che usa lo stesso giorno.
CREATE OR REPLACE FUNCTION private.casino_settimana()
 RETURNS date
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$ select ((now() at time zone 'Europe/Rome') + interval '110 minutes')::date $function$;
