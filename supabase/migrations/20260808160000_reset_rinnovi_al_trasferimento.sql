-- Un giocatore che cambia club apre una nuova trattativa contrattuale: i
-- rifiuti maturati con la squadra precedente non lo seguono nella nuova rosa.
-- Il contratto attuale e l'eventuale rinnovo gia' firmato restano invariati.

create or replace function private.reset_rinnovo_al_trasferimento()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.team_id is not null
     and new.team_id is not null
     and old.team_id is distinct from new.team_id then
    new.rinnovo_tentativi := 0;
  end if;

  return new;
end;
$$;

drop trigger if exists player_instances_reset_rinnovo_al_trasferimento on public.player_instances;
create trigger player_instances_reset_rinnovo_al_trasferimento
before update of team_id on public.player_instances
for each row execute function private.reset_rinnovo_al_trasferimento();

revoke all on function private.reset_rinnovo_al_trasferimento() from public, anon, authenticated;
