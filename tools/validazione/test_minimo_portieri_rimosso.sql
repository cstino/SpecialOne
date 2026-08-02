begin;

create temporary table esiti (
  n integer,
  verifica text,
  misurato text,
  esito text
) on commit drop;

do $$
declare
  v_user uuid;
  v_result jsonb;
  v_portieri integer;
begin
  select user_id into v_user
  from public.teams
  where user_id is not null
  limit 1;

  if v_user is null then
    insert into esiti values (1, 'utente test disponibile', 'nessun utente', 'ERRORE');
    return;
  end if;

  set local role authenticated;
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', v_user, 'role', 'authenticated')::text,
    true
  );

  select public.crea_lega(
    'Test Portieri Zero',
    'Squadra Zero',
    'preset:1',
    4::smallint,
    2::smallint,
    100000000,
    12::smallint,
    21::smallint,
    0::smallint,
    array['Premier League']
  ) into v_result;

  reset role;

  select portieri_minimi into v_portieri
  from public.leagues
  where id = (v_result->>'league_id')::bigint;

  insert into esiti values (
    1,
    'crea_lega con portieri_minimi 0',
    coalesce(v_portieri::text, 'null'),
    case when v_portieri = 0 then 'OK' else 'ERRORE' end
  );
exception when others then
  reset role;
  insert into esiti values (1, 'crea_lega con portieri_minimi 0', sqlerrm, 'ERRORE');
end $$;

select verifica, misurato, esito from esiti order by n;

rollback;
