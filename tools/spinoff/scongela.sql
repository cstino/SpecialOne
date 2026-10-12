-- SCONGELA: rimette ESATTAMENTE i permessi di prima (salvati da congela.sql), funzione per funzione.
do $$
declare r record; a record; n int := 0;
begin
  for r in select proc, acl from private.acl_congelamento loop
    execute format('revoke all on function %s from public, anon, authenticated', r.proc);
    if r.acl is null then
      execute format('grant execute on function %s to public', r.proc);  -- nessun ACL esplicito = default (PUBLIC)
    else
      for a in select grantee, privilege_type from aclexplode(r.acl) loop
        if a.privilege_type = 'EXECUTE' and a.grantee <> (select oid from pg_roles where rolname = 'postgres') then
          execute format('grant execute on function %s to %s', r.proc, case when a.grantee = 0 then 'public' else quote_ident((select rolname from pg_roles where oid = a.grantee)) end);
        end if;
      end loop;
    end if;
    n := n + 1;
  end loop;
  raise notice 'permessi ripristinati su % funzioni', n;
end $$;
