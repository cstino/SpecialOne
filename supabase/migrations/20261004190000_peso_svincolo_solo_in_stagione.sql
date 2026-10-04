-- ============================================================
--  LO STIPENDIO DI CHI SVINCOLI RESTA SUL TETTO: SOLO DA SEASON 2
--  Decisione del committente, 4 ottobre 2026 (docs/decisioni-economia.md)
--
--  La regola "lo svincolo libera il posto ma non lo stipendio" non deve
--  partire subito: dall'inizio della stagione nuova, cioe' dalla chiusura
--  dell'off-season. Durante l'off-season (fase_carriera = 'offseason') si
--  svincola come prima: l'ingaggio smette di pesare subito.
--
--  1. public.svincola_giocatore_cassa_legacy non imposta peso_team_id quando la
--     lega e' in off-season.
--  2. Chi e' stato svincolato in off-season dopo l'entrata in vigore della
--     regola (4 ottobre mattina) viene alleggerito: peso azzerato.
--  Il resto (monte_ingaggi, estrazione, firme) e' invariato: senza peso non
--  cambia nulla per chi non ce l'ha. Il rilascio entra comunque nella coda dei
--  rilasci come prima.
-- ============================================================

begin;

do $$
declare
  v_def text := pg_get_functiondef('public.svincola_giocatore_cassa_legacy(bigint)'::regprocedure);
  v_a text := E'    peso_team_id = case when v_istanza.ritiro_annunciato then null else v_squadra.id end\n';
begin
  if position(v_a in v_def) = 0 then
    raise exception 'svincola_giocatore_cassa_legacy: riga del peso non trovata, controllare a mano.';
  end if;
  v_def := replace(v_def, v_a,
    E'    -- In off-season si svincola come prima: il peso vale dalla stagione nuova.\n'
    || E'    peso_team_id = case when v_istanza.ritiro_annunciato then null\n'
    || E'                        when v_lega.fase_carriera = ''offseason'' then null\n'
    || E'                        else v_squadra.id end\n');
  execute v_def;
end;
$$;

update public.player_instances pi
set peso_team_id = null
from public.leagues l
where l.id = pi.league_id and l.fase_carriera = 'offseason'
  and pi.team_id is null and pi.peso_team_id is not null;

commit;
