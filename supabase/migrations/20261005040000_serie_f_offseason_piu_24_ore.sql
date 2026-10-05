-- ============================================================
--  SERIE F: OFF-SEASON PROLUNGATA DI 24 ORE (5 ottobre 2026)
--  Il committente sta per portare la lega a 24 squadre in due conferenze
--  (Est e Ovest): serve tempo prima che finalizza_offseason generi il
--  calendario della stagione 2. La scadenza passa da 05/10 23:55 a 06/10 23:55
--  (ora di Roma). La finestra del draft OFF si riallinea da sola
--  (trigger leagues_sincronizza_estrazione_off su leagues.offseason_fine).
-- ============================================================

update public.offseasons
set scade_il = scade_il + interval '24 hours'
where league_id = 63 and stato = 'aperta';

update public.leagues l
set offseason_fine = o.scade_il
from public.offseasons o
where l.id = 63 and o.league_id = 63 and o.stato = 'aperta';
