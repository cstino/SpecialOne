create or replace function private.completa_una_squadra_pc_background()
returns void language plpgsql security definer set search_path = '' as $$
declare v_league_id bigint; v_team_id bigint; begin
  select t.league_id, t.id into v_league_id, v_team_id
  from public.teams t join public.draft_team_state d on d.team_id=t.id
  where t.controllata_da_pc and d.stato <> 'concluso'
  order by t.league_id desc, t.id limit 1;
  if v_team_id is not null then perform private.completa_draft_squadra_pc(v_league_id, v_team_id); end if;
  if v_league_id is not null and not exists (select 1 from public.draft_team_state where league_id=v_league_id and stato <> 'concluso') then
    update public.draft_state set stato='concluso' where league_id=v_league_id;
    update public.leagues set stato='stagione' where id=v_league_id and stato='draft';
  end if;
end $$;
