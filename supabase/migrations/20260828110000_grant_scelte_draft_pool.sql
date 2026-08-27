-- Bug: scelte_draft e scelte_pool hanno una policy RLS di lettura ma non il
-- GRANT SELECT a authenticated che la policy presuppone — senza il grant,
-- Postgres nega l'accesso alla tabella prima ancora di valutare la policy.
-- Stessa classe di errore gia' vista per brackets/bracket_ties: la migrazione
-- che le ha create includeva "create policy" ma non "grant select", e in
-- questo progetto sono due passi distinti e nessuno dei due basta da solo.
-- Scoperto perche' un utente reale su LegaBot vedeva la pagina Draft vuota;
-- verificato in transazione con un JWT finto prima di questo fix ("permission
-- denied for table scelte_draft").

grant select on public.scelte_draft to authenticated;
grant select on public.scelte_pool to authenticated;
