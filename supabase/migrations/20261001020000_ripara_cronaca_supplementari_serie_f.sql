-- ============================================================
--  SERIE F: RIPARA LA CRONACA DI DUE RITORNI CON SUPPLEMENTARI
--
--  La Edge Function (fino alla v64) abbinava i marcatori ai gol in ordine
--  cronologico e, se al gol dei supplementari restava un marcatore gia'
--  sostituito, lo spostava nel blocco piu' vicino in cui era in campo:
--  dentro i 90'. Risultato e supplementari erano giusti (decisi dal motore
--  su gol_home_90/gol_away_90), la cronaca no. Dalla v65 un gol non
--  attraversa mai il 90'.
--
--  Fixture 2393 (match 1193) Fel Lazio - FC Salisburro, 90' = 2-1: il gol di
--  Ivanovic (6085) al 9' e' uno dei tre dei supplementari. Si sposta al 97',
--  marcatori e statistiche invariati (Ivanovic resta a 2 gol).
--
--  Fixture 2421 (match 1195) Piacenza - M'ARPZZC, 90' = 0-2: il gol del 44'
--  e' dei supplementari, ma Dompe (6429) era uscito al 45'. Come fa ora la
--  Edge Function, lo segna chi era in campo: Sauer (7064), entrato al suo
--  posto. Si spostano gol e statistica individuale.
-- ============================================================

update public.matches m
set blocchi = (
  select jsonb_agg(
    case when e->>'tipo' = 'gol' and (e->>'marcatore')::bigint = 6085 and (e->>'minuto')::int = 9
      then e || jsonb_build_object('minuto', 97, 'blocco', 7)
      else e end
    order by case when e->>'tipo' = 'gol' and (e->>'marcatore')::bigint = 6085 and (e->>'minuto')::int = 9 then 97 else (e->>'minuto')::int end)
  from jsonb_array_elements(m.blocchi) e)
where m.id = 1193 and m.fixture_id = 2393;

update public.matches m
set blocchi = (
  select jsonb_agg(
    case when e->>'tipo' = 'gol' and (e->>'marcatore')::bigint = 6429 and (e->>'minuto')::int = 44
      then e || jsonb_build_object('minuto', 98, 'blocco', 7, 'marcatore', 7064)
      else e end
    order by case when e->>'tipo' = 'gol' and (e->>'marcatore')::bigint = 6429 and (e->>'minuto')::int = 44 then 98 else (e->>'minuto')::int end)
  from jsonb_array_elements(m.blocchi) e)
where m.id = 1195 and m.fixture_id = 2421;

update public.match_stats set gol = gol - 1 where match_id = 1195 and player_instance_id = 6429 and gol > 0;
update public.match_stats set gol = gol + 1 where match_id = 1195 and player_instance_id = 7064;
