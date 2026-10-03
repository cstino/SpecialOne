-- ============================================================
--  ALBO D'ORO: PREMI INDIVIDUALI PER STAGIONE
--
--  Per ogni stagione conclusa, in due fasi (stagione regolare e Title Playoff):
--    - miglior marcatore   (gol; a parita': assist, poi meno minuti)
--    - miglior assistman   (assist; a parita': gol, poi meno minuti)
--    - miglior portiere    (porte inviolate; a parita': piu' minuti)
--
--  Stagione regolare = partite senza tabellone. Title Playoff = partite dei
--  tabelloni di tipo 'title' (il Draft Playoff non assegna premi).
--  Porta inviolata = il portiere titolare (primo degli undici) ha giocato
--  almeno 45' e la squadra avversaria non ha segnato (supplementari compresi).
--  Un solo vincitore per premio: i pari merito li scioglie lo spareggio sopra.
--  La squadra e' quella in cui il giocatore ha giocato piu' minuti.
-- ============================================================

create or replace function public.premi_individuali_lega(p_league_id bigint)
returns table (
  season_id bigint,
  fase text,
  premio text,
  player_instance_id bigint,
  nome text,
  foto_url text,
  team_id bigint,
  valore integer
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not private.e_membro(p_league_id) then
    raise exception using errcode = '42501', message = 'Non fai parte di questa lega.';
  end if;

  return query
  with partite as (
    select f.season_id as sid,
           case when f.bracket_tie_id is null then 'regular' else 'title' end as ph,
           m.id as mid, m.titolari_home, m.titolari_away, m.gol_home, m.gol_away,
           f.home_team_id, f.away_team_id
    from public.fixtures f
    join public.matches m on m.fixture_id = f.id
    join public.seasons s on s.id = f.season_id and s.stato = 'conclusa'
    left join public.bracket_ties t on t.id = f.bracket_tie_id
    left join public.brackets b on b.id = t.bracket_id
    where f.league_id = p_league_id
      and (f.bracket_tie_id is null or b.tipo = 'title')
  ),
  per_giocatore as (
    select p.sid, p.ph, ms.player_instance_id as pid,
           sum(ms.gol)::int as gol, sum(ms.assist)::int as assist, sum(ms.minuti)::int as minuti,
           (array_agg(ms.team_id order by ms.minuti desc))[1] as tid
    from partite p
    join public.match_stats ms on ms.match_id = p.mid
    group by p.sid, p.ph, ms.player_instance_id
  ),
  inviolate as (
    select x.sid, x.ph, x.pid, count(*)::int as inviolate, sum(ms.minuti)::int as minuti,
           (array_agg(ms.team_id))[1] as tid
    from (
      select p.sid, p.ph, p.mid, p.titolari_home[1] as pid from partite p where p.gol_away = 0
      union all
      select p.sid, p.ph, p.mid, p.titolari_away[1] from partite p where p.gol_home = 0
    ) x
    join public.match_stats ms on ms.match_id = x.mid and ms.player_instance_id = x.pid and ms.minuti >= 45
    group by x.sid, x.ph, x.pid
  ),
  candidati as (
    select sid, ph, 'marcatore'::text as pr, pid, tid, gol as val,
           row_number() over (partition by sid, ph order by gol desc, assist desc, minuti asc, pid) as pos
    from per_giocatore where gol > 0
    union all
    select sid, ph, 'assistman', pid, tid, assist,
           row_number() over (partition by sid, ph order by assist desc, gol desc, minuti asc, pid)
    from per_giocatore where assist > 0
    union all
    select sid, ph, 'portiere', pid, tid, inviolate,
           row_number() over (partition by sid, ph order by inviolate desc, minuti desc, pid)
    from inviolate
  )
  select c.sid, c.ph, c.pr, c.pid, pl.nome, pl.foto_url, c.tid, c.val
  from candidati c
  join public.player_instances pi on pi.id = c.pid
  join public.players pl on pl.id = pi.player_id
  where c.pos = 1
  order by c.sid desc, c.ph, c.pr;
end;
$$;

revoke all on function public.premi_individuali_lega(bigint) from public, anon;
grant execute on function public.premi_individuali_lega(bigint) to authenticated;
