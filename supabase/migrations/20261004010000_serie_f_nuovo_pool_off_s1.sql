-- ============================================================
--  SERIE F: NUOVA ESTRAZIONE DEGLI ELEGGIBILI DEL DRAFT OFF (STAGIONE 1)
--  Chiesto dal committente il 4 ottobre 2026. Nessuna preferenza era stata
--  ancora salvata sulla finestra; per sicurezza si cancellano comunque quelle
--  delle scelte della finestra prima di ricreare il pool.
-- ============================================================

delete from public.scelte_preferenze pr
using public.scelte_draft sd
where sd.id = pr.scelta_id and sd.league_id = 63 and sd.stagione = 1 and sd.finestra = 'off';

delete from public.scelte_pool where league_id = 63 and stagione = 1 and finestra = 'off';

select private.estrai_pool_scelte(63, 1::smallint, 'off');
