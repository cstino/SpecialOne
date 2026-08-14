-- Allinea immediatamente il turno in corso al nuovo ciclo dinamico. Senza
-- questo passaggio, il primo countdown continuerebbe a usare il vecchio 23:00
-- fisso fino alla prossima simulazione.
with ultima_partita as (
  select f.league_id, max(m.simulata_il) as completata_il
  from public.matches m
  join public.fixtures f on f.id = m.fixture_id
  join public.leagues l on l.id = f.league_id
  where l.stato = 'stagione' and l.fase_carriera = 'normale'
  group by f.league_id
), prossima_giornata as (
  select f.league_id, min(f.giornata) as giornata
  from public.fixtures f
  join ultima_partita u on u.league_id = f.league_id
  where f.stato = 'programmata'
  group by f.league_id
)
update public.fixtures f
set data_sim = u.completata_il + interval '24 hours'
from ultima_partita u
join prossima_giornata p on p.league_id = u.league_id
where f.league_id = p.league_id
  and f.giornata = p.giornata
  and f.stato = 'programmata';
