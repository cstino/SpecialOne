-- Premi individuali: stagione regolare (un solo premio, ambito 'totale') e uno per ogni torneo dei playoff:
-- ambito 'champions' (tabellone title o champions), 'europa' e 'draft' (Draft Playoffs). Ogni premio del torneo
-- conta solo le partite di quel tabellone. Fase 'regular' o 'title' (= i tornei). Cambia il tipo restituito
-- (colonna ambito in piu'): si ricrea la funzione.
drop function if exists public.premi_individuali_lega(bigint);

create function public.premi_individuali_lega(p_league_id bigint)
 returns table(season_id bigint, fase text, premio text, player_instance_id bigint, nome text, foto_url text, team_id bigint, valore integer, ambito text)
 language plpgsql
 stable security definer
 set search_path to ''
as $function$
begin
  if not private.e_membro(p_league_id) then
    raise exception using errcode = '42501', message = 'Non fai parte di questa lega.';
  end if;

  return query
  with partite as (
    select f.season_id as sid,
           case when f.bracket_tie_id is null then 'regular' else 'title' end as ph,
           case when f.bracket_tie_id is null then 'totale'
                when b.tipo = 'draft' then 'draft'
                when b.tipo = 'europa' then 'europa'
                else 'champions' end as amb,
           m.id as mid, m.titolari_home, m.titolari_away, m.gol_home, m.gol_away,
           f.home_team_id, f.away_team_id
    from public.fixtures f
    join public.matches m on m.fixture_id = f.id
    join public.seasons s on s.id = f.season_id and s.stato = 'conclusa'
    left join public.bracket_ties t on t.id = f.bracket_tie_id
    left join public.brackets b on b.id = t.bracket_id
    where f.league_id = p_league_id
      and (f.bracket_tie_id is null or b.tipo in ('title', 'champions', 'europa', 'draft'))
  ),
  per_giocatore as (
    select p.sid, p.ph, p.amb, ms.player_instance_id as pid,
           sum(ms.gol)::int as gol, sum(ms.assist)::int as assist, sum(ms.minuti)::int as minuti,
           (array_agg(ms.team_id order by ms.minuti desc))[1] as tid
    from partite p
    join public.match_stats ms on ms.match_id = p.mid
    group by p.sid, p.ph, p.amb, ms.player_instance_id
  ),
  inviolate as (
    select x.sid, x.ph, x.amb, x.pid, count(*)::int as inviolate, sum(ms.minuti)::int as minuti,
           (array_agg(ms.team_id))[1] as tid
    from (
      select p.sid, p.ph, p.amb, p.mid, p.titolari_home[1] as pid from partite p where p.gol_away = 0
      union all
      select p.sid, p.ph, p.amb, p.mid, p.titolari_away[1] from partite p where p.gol_home = 0
    ) x
    join public.match_stats ms on ms.match_id = x.mid and ms.player_instance_id = x.pid and ms.minuti >= 45
    group by x.sid, x.ph, x.amb, x.pid
  ),
  -- Una riga per giocatore e premio, con le chiavi di ordinamento (o2 decrescente, o3 crescente):
  -- marcatore gol > assist > meno minuti; assistman assist > gol > meno minuti; portiere inviolate > piu' minuti.
  base as (
    select sid, ph, amb, 'marcatore'::text as pr, pid, tid, gol as val, assist as o2, minuti as o3
    from per_giocatore where gol > 0
    union all
    select sid, ph, amb, 'assistman', pid, tid, assist, gol, minuti from per_giocatore where assist > 0
    union all
    select sid, ph, amb, 'portiere', pid, tid, inviolate, minuti, 0 from inviolate
  ),
  candidati as (
    select b.*, row_number() over (partition by b.sid, b.ph, b.amb, b.pr order by b.val desc, b.o2 desc, b.o3 asc, b.pid) as pos
    from base b
  )
  select c.sid, c.ph, c.pr, c.pid, pl.nome, pl.foto_url, c.tid, c.val, c.amb
  from candidati c
  join public.player_instances pi on pi.id = c.pid
  join public.players pl on pl.id = pi.player_id
  where c.pos = 1
  order by c.sid desc, c.ph, c.pr, c.amb;
end;
$function$;

revoke all on function public.premi_individuali_lega(bigint) from public;
grant execute on function public.premi_individuali_lega(bigint) to postgres, service_role, anon, authenticated;
