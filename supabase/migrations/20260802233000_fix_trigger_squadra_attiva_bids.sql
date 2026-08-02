create or replace function private.verifica_squadra_mercato_attiva()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_new jsonb := to_jsonb(new);
  v_team_id bigint;
begin
  if v_new ? 'team_id' then
    v_team_id := (v_new->>'team_id')::bigint;
  else
    v_team_id := (v_new->>'da_team_id')::bigint;
  end if;

  if not exists (select 1 from public.teams where id = v_team_id and attiva) then
    raise exception using errcode = '55000', message = 'La squadra non è attiva in questa lega.';
  end if;

  if (v_new ? 'a_team_id')
     and not exists (select 1 from public.teams where id = (v_new->>'a_team_id')::bigint and attiva) then
    raise exception using errcode = '55000', message = 'La squadra destinataria non è attiva in questa lega.';
  end if;

  return new;
end;
$$;

revoke all on function private.verifica_squadra_mercato_attiva() from public, anon, authenticated;
