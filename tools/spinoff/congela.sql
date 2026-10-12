-- CONGELA: l'app (ruoli anon e authenticated) non puo' piu' eseguire nessuna funzione di public: ogni scrittura (e lettura via RPC)
-- fallisce con "permission denied". service_role (job, simulazione) e il proprietario non sono toccati.
-- Il blocco in sola lettura per ruolo/database NON funziona con PostgREST (provato 12 ottobre 2026: le scritture passano).
create table if not exists private.acl_congelamento (proc regprocedure primary key, acl aclitem[]);
delete from private.acl_congelamento;
insert into private.acl_congelamento select p.oid::regprocedure, p.proacl from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.prokind = 'f';
revoke execute on all functions in schema public from public, anon, authenticated;
grant execute on all functions in schema public to service_role;  -- job, simulazione e funzioni server continuano a funzionare
