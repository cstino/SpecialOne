-- La pagina Risorse non si apriva dal 5/11/2026 (migrazione 20261105130000_stadio): tabella_risorse non e'
-- security definer e chiama private.punti_abilita_massimi_lega, a cui era stato tolto il permesso. Stesso permesso
-- delle altre funzioni che la tabella usa (punti_abilita_massimi, punti_per_checkpoint): legge solo il tetto dei punti.
grant execute on function private.punti_abilita_massimi_lega(bigint) to anon, authenticated, service_role;
