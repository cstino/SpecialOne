-- Il cron delle 21:00 deve essere idempotente anche quando una vecchia
-- tornata resta aperta per un disservizio o per una chiusura manuale mancata.
-- Risolve tutte le aste aperte fino a oggi, non soltanto quelle datate oggi.

create or replace function private.risolvi_aste()
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_oggi date := (now() at time zone 'Europe/Rome')::date;
  v_giorno record;
  v_assegnate integer := 0;
begin
  if extract(hour from (now() at time zone 'Europe/Rome')) <> 21 then
    return 0;
  end if;

  for v_giorno in
    select distinct a.giorno
    from public.free_agent_auctions a
    where a.stato = 'aperta'
      and a.giorno <= v_oggi
    order by a.giorno
  loop
    v_assegnate := v_assegnate + private.risolvi_aste_giorno(v_giorno.giorno);
  end loop;

  return v_assegnate;
end;
$$;

revoke all on function private.risolvi_aste() from public, anon, authenticated;
grant execute on function private.risolvi_aste() to service_role;
