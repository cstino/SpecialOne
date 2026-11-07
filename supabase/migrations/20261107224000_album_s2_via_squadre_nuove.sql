-- Serie F: tolte dall'album Season 2 le figurine delle quattro squadre entrate nell'off-season (7/11/2026, decisione
-- del committente). Chi le aveva trovate nelle bustine viene rimborsato a 83 crediti a copia (una bustina da 250
-- ne contiene 3); i premi da 200 per le pagine "complete" di quelle squadre (contate complete col solo stemma)
-- vengono tolti e scalati dal rimborso.

with nuove as (
  select id from public.album_figurine
  where league_id = 63 and stagione = 2 and team_id in (310, 311, 312, 313)
), copie as (
  select ap.user_id, sum(ap.normali + ap.ultra + ap.rare + ap.ultimate) as n
  from public.album_possesso ap where ap.figurina_id in (select id from nuove)
  group by ap.user_id
), premi as (
  select user_id, count(*) as n from public.album_premi
  where league_id = 63 and stagione = 2 and chiave in ('pagina:310', 'pagina:311', 'pagina:312', 'pagina:313')
  group by user_id
), saldo as (
  select coalesce(c.user_id, p.user_id) as user_id, coalesce(c.n, 0) * 83 - coalesce(p.n, 0) * 200 as delta
  from copie c full join premi p on p.user_id = c.user_id
)
update public.casino_saldi s set crediti = greatest(0, s.crediti + saldo.delta), aggiornato_il = now()
from saldo where s.league_id = 63 and s.user_id = saldo.user_id;

delete from public.album_premi
where league_id = 63 and stagione = 2 and chiave in ('pagina:310', 'pagina:311', 'pagina:312', 'pagina:313');

-- album_possesso va via in cascata
delete from public.album_figurine where league_id = 63 and stagione = 2 and team_id in (310, 311, 312, 313);
