-- Con molte squadre PC il sort casuale a ogni pick superava il timeout HTTP.
-- La qualità viene già regolata dal tetto ingaggi: un ordine indicizzato
-- rende la creazione della lega veloce anche con 7 PC.
do $$
declare
  v_sql text;
begin
  select pg_get_functiondef('private.completa_draft_squadra_pc(bigint,bigint)'::regprocedure) into v_sql;
  v_sql := replace(
    v_sql,
    'order by abs(private.ingaggio_teorico(p.overall, p.eta) - least(3500000, (v_league.budget_draft - v_speso) / greatest(v_league.slot_rosa - v_presi, 1))) + random() * 250000',
    'order by p.id'
  );
  execute v_sql;
end;
$$;
