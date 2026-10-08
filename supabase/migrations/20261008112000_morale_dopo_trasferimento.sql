-- Il trasferimento a un'altra squadra (scambio) alza il morale: aria nuova, ripartenza (8 ottobre 2026, committente).
-- +20, e comunque almeno 60: chi era in rotta col vecchio club non si porta dietro tutto il malcontento.
-- Solo da una squadra a un'altra (old e new team_id valorizzati): firma di svincolati e svincoli non sono toccati.
create or replace function private.morale_al_trasferimento()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.team_id is not null and new.team_id is not null and old.team_id is distinct from new.team_id then
    new.morale := least(100, greatest(60, coalesce(old.morale, 50) + 20))::smallint;
  end if;
  return new;
end;
$$;

drop trigger if exists player_instances_morale_al_trasferimento on public.player_instances;
create trigger player_instances_morale_al_trasferimento
  before update of team_id on public.player_instances
  for each row execute function private.morale_al_trasferimento();
