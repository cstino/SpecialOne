-- Completa una sola rosa PC per esecuzione: la creazione della lega resta
-- istantanea anche con 19 squadre controllate dal PC.
create or replace function private.completa_una_squadra_pc_background()
returns void language plpgsql security definer set search_path = '' as $$
declare v_league_id bigint; v_team_id bigint; begin
  select t.league_id, t.id into v_league_id, v_team_id
  from public.teams t join public.draft_team_state d on d.team_id=t.id
  where t.controllata_da_pc and d.stato <> 'concluso'
  order by t.league_id, t.id limit 1;
  if v_team_id is not null then perform private.completa_draft_squadra_pc(v_league_id, v_team_id); end if;
end $$;
select cron.unschedule(jobid) from cron.job where jobname = 'completa-squadre-pc';
select cron.schedule('completa-squadre-pc', '* * * * *', $$select private.completa_una_squadra_pc_background();$$);
