-- Compatibilita' per leghe gia' avviate prima del draft indipendente.
insert into public.draft_team_state (team_id, league_id, pick_numero, stato)
select
  t.id,
  t.league_id,
  count(dp.id)::integer,
  case when count(dp.id) >= l.slot_rosa then 'concluso' else 'in_corso' end
from public.teams t
join public.leagues l on l.id = t.league_id
left join public.draft_picks dp on dp.team_id = t.id and dp.league_id = t.league_id
where l.stato = 'draft'
group by t.id, t.league_id, l.slot_rosa
on conflict (team_id) do nothing;
