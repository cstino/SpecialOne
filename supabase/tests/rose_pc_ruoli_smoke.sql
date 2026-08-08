do $$
declare
  v_league_id bigint;
begin
  select id into v_league_id from public.leagues where nome = 'Test2' order by id desc limit 1;
  if v_league_id is null then raise exception 'Test2 non trovata'; end if;

  if exists (
    with conteggi as (
      select t.id,
             count(*) filter (where private.macro_ruolo(p.posizioni) = 'GK')::integer as gk,
             count(*) filter (where private.macro_ruolo(p.posizioni) = 'DEF')::integer as def,
             count(*) filter (where private.macro_ruolo(p.posizioni) = 'MID')::integer as mid,
             count(*) filter (where private.macro_ruolo(p.posizioni) = 'ATT')::integer as att,
             count(*)::integer as totale
      from public.teams t
      join public.player_instances pi on pi.team_id = t.id and pi.league_id = v_league_id
      join public.players p on p.id = pi.player_id
      where t.league_id = v_league_id and t.controllata_da_pc
      group by t.id
    )
    select 1 from conteggi c
    cross join lateral (
      select
        max(obiettivo) filter (where ruolo = 'GK') as gk,
        max(obiettivo) filter (where ruolo = 'DEF') as def,
        max(obiettivo) filter (where ruolo = 'MID') as mid,
        max(obiettivo) filter (where ruolo = 'ATT') as att
      from private.obiettivi_rosa_pc(c.id, c.totale)
    ) o
    where (c.gk, c.def, c.mid, c.att) is distinct from (o.gk, o.def, o.mid, o.att)
  ) then
    raise exception 'Una rosa PC di Test2 non rispetta il proprio profilo ruoli';
  end if;

  if exists (
    select 1
    from generate_series(1, 20) id
    cross join lateral private.obiettivi_rosa_pc(id, 24) o
    group by id
    having sum(o.obiettivo) <> 24
       or max(o.obiettivo) filter (where o.ruolo = 'GK') not between 2 and 3
  ) then
    raise exception 'Profilo PC futuro non valido';
  end if;
end;
$$;

select t.nome,
       count(*) filter (where private.macro_ruolo(p.posizioni) = 'GK') as portieri,
       count(*) filter (where private.macro_ruolo(p.posizioni) = 'DEF') as difensori,
       count(*) filter (where private.macro_ruolo(p.posizioni) = 'MID') as centrocampisti,
       count(*) filter (where private.macro_ruolo(p.posizioni) = 'ATT') as attaccanti,
       count(*) as totale
from public.teams t
join public.leagues l on l.id = t.league_id
join public.player_instances pi on pi.team_id = t.id and pi.league_id = l.id
join public.players p on p.id = pi.player_id
where l.nome = 'Test2' and t.controllata_da_pc
group by t.id
order by t.id;
