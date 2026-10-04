-- ============================================================
--  MINUTAGGIO: la percentuale conta anche i playoff
--  Segnalazione del committente, 4 ottobre 2026 (C. Nkunku: 225 minuti, 0%)
--
--  I minuti mostrati in rosa sono quelli di tutta la stagione, playoff
--  compresi; la percentuale accanto invece contava solo la stagione regolare
--  (giornata <= giornate_totali). Un giocatore arrivato all'ultima giornata
--  regolare e utilizzato nei playoff (225 minuti nelle giornate 31-34)
--  risultava allo 0%: una partita di regolare senza minuti. Ora il conteggio
--  comprende tutte le partite simulate della stagione dall'arrivo in poi.
--  I controlli dei richiami e il morale girano solo durante la stagione
--  regolare (giornate 8, 13... e quarti di stagione), quindi per loro non
--  cambia nulla.
-- ============================================================

begin;

create or replace function private.minuti_stagione(p_instance_id bigint)
returns table(partite integer, minuti numeric)
language sql
stable
security definer
set search_path = ''
as $$
  with g as (
    select pi.id, pi.team_id, pi.league_id,
           coalesce(pi.giornata_acquisizione, 1) as inizio,
           l.stagione_corrente
    from public.player_instances pi
    join public.leagues l on l.id = pi.league_id
    where pi.id = p_instance_id
  ), f as (
    select fx.id as fixture_id
    from g
    join public.seasons s on s.league_id = g.league_id and s.numero = g.stagione_corrente
    join public.fixtures fx on fx.season_id = s.id and fx.stato = 'simulata'
      and fx.giornata >= g.inizio
      and (fx.home_team_id = g.team_id or fx.away_team_id = g.team_id)
    where not exists (select 1 from private.assenze_partita a
                      where a.fixture_id = fx.id and a.player_instance_id = g.id)
  )
  select (select count(*) from f)::integer,
         coalesce((select sum(ms.minuti) from public.match_stats ms
                   join public.matches m on m.id = ms.match_id
                   join f on f.fixture_id = m.fixture_id
                   join g on true
                   where ms.player_instance_id = g.id and ms.team_id = g.team_id), 0)::numeric;
$$;

commit;
