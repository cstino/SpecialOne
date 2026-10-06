-- Amichevoli sospese su richiesta del committente (6 ottobre 2026): tolte dall'app. Qui si chiudono anche gli
-- ingressi del database, cosi' una versione vecchia dell'app rimasta aperta non puo' piu' inviare o accettare inviti.
-- I dati restano (tabella `amichevoli`, referti compresi) e il ramo della funzione di simulazione resta dormiente.
-- Per riaprirle: ridare `grant execute` alle due funzioni a `authenticated` e rimettere voce di menu e pagina (commit eabc8e0).
revoke execute on function public.invia_amichevole(bigint, bigint) from authenticated;
revoke execute on function public.rispondi_amichevole(bigint, boolean) from authenticated;
