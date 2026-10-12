-- Nel Supabase del Mac le funzioni del database che chiamano le Edge Function devono puntare al gateway interno
-- (http://api-gw:8000), non all'indirizzo del cloud. Da eseguire dopo aver caricato lo schema. Idempotente.
do $$
declare r record; def text;
begin
  for r in select p.oid from pg_proc p join pg_namespace n on n.oid=p.pronamespace
           where n.nspname in ('public','private') and p.prosrc like '%hhvyyjpbsgjcaaaizgwb.supabase.co%' loop
    def := replace(pg_get_functiondef(r.oid), 'https://hhvyyjpbsgjcaaaizgwb.supabase.co', 'http://api-gw:8000');
    execute def;
  end loop;
end $$;
