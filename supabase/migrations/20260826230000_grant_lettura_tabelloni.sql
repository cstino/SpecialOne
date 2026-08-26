-- I GRANT mancavano: brackets e bracket_ties avevano la policy RLS di lettura
-- ma non il privilegio SELECT per il ruolo authenticated, quindi PostgREST
-- rispondeva "permission denied" e la pagina Tabellone sarebbe rimasta vuota.
-- In Postgres i due controlli sono indipendenti: la policy filtra le righe,
-- il GRANT decide se puoi guardare la tabella. Servono entrambi.
--
-- Stesso identico schema di fixtures e standings: solo SELECT ad authenticated
-- (le righe le scrivono le funzioni security definer), niente ad anon.
grant select on public.brackets to authenticated;
grant select on public.bracket_ties to authenticated;
