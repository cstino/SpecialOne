begin;

do $$
declare
  v_owner uuid;
  v_own_team public.teams;
  v_other_team public.teams;
begin
  select * into v_own_team from public.teams where id = 4;
  select * into v_other_team from public.teams where league_id = v_own_team.league_id and id <> v_own_team.id order by id limit 1;
  v_owner := v_own_team.user_id;

  perform set_config('request.jwt.claim.sub', v_owner::text, true);
  set local role authenticated;

  perform public.aggiorna_profilo_squadra(v_own_team.id, v_own_team.nome, v_own_team.stemma_url);

  begin
    perform public.aggiorna_profilo_squadra(v_other_team.id, v_other_team.nome, v_other_team.stemma_url);
    raise exception 'La modifica della squadra altrui non è stata bloccata.';
  exception
    when insufficient_privilege then null;
  end;
end;
$$;

reset role;

do $$
begin
  if has_function_privilege('anon', 'public.aggiorna_profilo_squadra(bigint,text,text)', 'execute') then
    raise exception 'anon non deve poter eseguire aggiorna_profilo_squadra.';
  end if;
  if not has_function_privilege('authenticated', 'public.aggiorna_profilo_squadra(bigint,text,text)', 'execute') then
    raise exception 'authenticated deve poter eseguire aggiorna_profilo_squadra.';
  end if;
end;
$$;

rollback;
