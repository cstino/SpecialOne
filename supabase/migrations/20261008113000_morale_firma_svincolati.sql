-- Anche chi firma da svincolato (aste free agent, scelte del draft) parte con la stessa spinta: +20, almeno 60
-- (8 ottobre 2026, committente). Restano esclusi solo gli svincoli (new team_id nullo).
create or replace function private.morale_al_trasferimento()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.team_id is not null and old.team_id is distinct from new.team_id then
    new.morale := least(100, greatest(60, coalesce(old.morale, 50) + 20))::smallint;
  end if;
  return new;
end;
$$;
