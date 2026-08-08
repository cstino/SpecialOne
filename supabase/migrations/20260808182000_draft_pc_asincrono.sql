-- La creazione lega non deve dipendere dalla durata del draft delle PC.
do $$ declare v_sql text; begin
  select pg_get_functiondef('public.crea_lega(text,text,text,smallint,smallint,bigint,bigint,smallint,smallint,smallint,text[],smallint)'::regprocedure) into v_sql;
  v_sql := replace(v_sql, '    perform private.completa_draft_squadra_pc(v_league.id, v_team.id);', '');
  execute v_sql;
end $$;

create or replace function public.completa_prossima_squadra_pc(p_league_id bigint)
returns boolean language plpgsql security definer set search_path = '' as $$
declare v_team_id bigint; begin
  if not exists (select 1 from public.leagues where id = p_league_id and admin_id = auth.uid()) then
    raise exception using errcode = '42501', message = 'Solo l''admin puo'' preparare le squadre PC.';
  end if;
  select t.id into v_team_id from public.teams t join public.draft_team_state d on d.team_id = t.id
  where t.league_id = p_league_id and t.controllata_da_pc and d.stato <> 'concluso' order by t.id limit 1;
  if v_team_id is null then return false; end if;
  perform private.completa_draft_squadra_pc(p_league_id, v_team_id);
  return true;
end $$;
revoke all on function public.completa_prossima_squadra_pc(bigint) from public, anon;
grant execute on function public.completa_prossima_squadra_pc(bigint) to authenticated;
