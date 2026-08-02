-- Il limite di rosa e' fisso: non serve caricare la configurazione della lega.

create or replace function public.budget_disponibile(p_league_id bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_squadra public.teams;
  v_rosa    integer;
begin
  select * into v_squadra from public.teams
  where league_id = p_league_id and user_id = (select auth.uid());
  if not found then
    raise exception using errcode = '42501', message = 'Non partecipi a questa lega.';
  end if;

  select count(*) into v_rosa from public.player_instances where team_id = v_squadra.id;

  return jsonb_build_object(
    'budget',            v_squadra.budget,
    'impegnato',         private.budget_impegnato(v_squadra.id),
    'disponibile',       v_squadra.budget - private.budget_impegnato(v_squadra.id),
    'rosa',              v_rosa,
    'slot_impegnati',    private.slot_impegnati(v_squadra.id),
    'slot_liberi',       private.rosa_massima() - v_rosa - private.slot_impegnati(v_squadra.id)
  );
end;
$$;

revoke all on function public.budget_disponibile(bigint) from public, anon, authenticated;
grant execute on function public.budget_disponibile(bigint) to authenticated;
