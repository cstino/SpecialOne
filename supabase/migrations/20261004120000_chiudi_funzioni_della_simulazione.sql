-- ============================================================
--  SICUREZZA: FUNZIONI DELLA SIMULAZIONE CHIUSE AGLI UTENTI
--
--  Trovato nel controllo del 4 ottobre 2026, prima del lancio Season 2.
--  registra_risultato_partita e assegna_punti_abilita sono SECURITY DEFINER,
--  non verificano chi le chiama e le invoca solo la Edge Function
--  simula-giornata con la chiave di servizio (ctx.supabaseAdmin). Erano
--  pero' eseguibili da qualunque utente autenticato (e la seconda anche da
--  anon): un partecipante poteva registrare a mano il risultato di una
--  partita non ancora simulata, o anticipare i punti abilita'.
-- ============================================================

revoke all on function public.registra_risultato_partita(bigint, bigint, text, text, text, text, smallint, smallint, jsonb, jsonb, jsonb, bigint[], bigint[], smallint, smallint, smallint, smallint, jsonb)
  from public, anon, authenticated;
grant execute on function public.registra_risultato_partita(bigint, bigint, text, text, text, text, smallint, smallint, jsonb, jsonb, jsonb, bigint[], bigint[], smallint, smallint, smallint, smallint, jsonb)
  to service_role;

revoke all on function public.assegna_punti_abilita(bigint, smallint) from public, anon, authenticated;
grant execute on function public.assegna_punti_abilita(bigint, smallint) to service_role;
