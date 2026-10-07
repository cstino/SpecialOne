-- Regola fissa (7 ottobre 2026): chi viene svincolato durante l'off-season (rilasci a mano, contratti non rinnovati,
-- tagli per il tetto) entra nella coda dei rilasci gia' sospeso e non va fra i free agent finche' il committente
-- non lo chiede. Si decide al momento dell'inserimento guardando la fase della lega, cosi' vale per ogni
-- off-season futura e per qualunque funzione che scriva nella coda. Per liberarli:
--   update private.rilasci_in_coda set sospeso = false [where ...];
create or replace function private.rilasci_in_coda_sospendi_offseason()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if exists (select 1 from public.leagues l where l.id = new.league_id and l.fase_carriera = 'offseason') then
    new.sospeso := true;
  end if;
  return new;
end;
$$;

drop trigger if exists rilasci_in_coda_sospendi_offseason on private.rilasci_in_coda;
create trigger rilasci_in_coda_sospendi_offseason
  before insert on private.rilasci_in_coda
  for each row execute function private.rilasci_in_coda_sospendi_offseason();
