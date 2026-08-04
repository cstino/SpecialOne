-- Estensione del filtro di test: gli under 60 sono esclusi a prescindere
-- dall'età. Nessun record viene eliminato dal catalogo.
update public.players
set disponibile_estrazione = false
where disponibile_estrazione
  and overall < 60;
