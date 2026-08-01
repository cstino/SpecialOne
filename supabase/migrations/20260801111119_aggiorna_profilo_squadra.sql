create or replace function public.aggiorna_profilo_squadra(
  p_team_id bigint,
  p_nome text,
  p_stemma_url text
)
returns public.teams
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_team public.teams;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'Devi accedere per modificare la squadra.';
  end if;

  select * into v_team
  from public.teams
  where id = p_team_id
    and user_id = v_user_id
  for update;

  if not found then
    raise exception using errcode = '42501', message = 'Puoi modificare soltanto la tua squadra.';
  end if;

  p_nome := trim(p_nome);
  if length(p_nome) not between 2 and 40 then
    raise exception using errcode = '22023', message = 'Il nome della squadra deve avere da 2 a 40 caratteri.';
  end if;
  if not private.stemma_valido(p_stemma_url, v_user_id) then
    raise exception using errcode = '22023', message = 'Lo stemma selezionato non è valido.';
  end if;

  begin
    update public.teams
    set nome = p_nome,
        stemma_url = p_stemma_url
    where id = p_team_id
    returning * into v_team;
  exception when unique_violation then
    raise exception using errcode = '23505', message = 'Questo nome squadra è già usato nella lega.';
  end;

  return v_team;
end;
$$;

revoke all on function public.aggiorna_profilo_squadra(bigint, text, text)
  from public, anon;
grant execute on function public.aggiorna_profilo_squadra(bigint, text, text)
  to authenticated;

comment on function public.aggiorna_profilo_squadra(bigint, text, text) is
  'Modifica nome e stemma esclusivamente per il proprietario della squadra.';
