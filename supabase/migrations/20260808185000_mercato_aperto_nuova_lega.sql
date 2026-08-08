-- Se il draft termina mentre la finestra giornaliera è già aperta, la nuova
-- lega riceve subito la sua estrazione. Nessun anticipo nella fascia 21:00-23:30.
create or replace function private.apri_mercato_nuova_lega()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ora time := (now() at time zone 'Europe/Rome')::time;
begin
  if old.stato <> 'stagione' and new.stato = 'stagione'
     and (v_ora >= time '23:30' or v_ora < time '21:00') then
    perform private.estrai_svincolati_lega(new.id, (now() at time zone 'Europe/Rome')::date);
    perform private.offerte_mercato_squadre_pc(new.id);
    perform private.proposte_mercato_squadre_pc(new.id);
  end if;
  return new;
end;
$$;

drop trigger if exists leagues_apri_mercato_nuova_stagione on public.leagues;
create trigger leagues_apri_mercato_nuova_stagione
after update of stato on public.leagues
for each row execute function private.apri_mercato_nuova_lega();

revoke all on function private.apri_mercato_nuova_lega() from public, anon, authenticated;
grant execute on function private.apri_mercato_nuova_lega() to service_role;
