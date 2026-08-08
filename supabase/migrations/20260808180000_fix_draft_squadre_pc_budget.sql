-- Corregge la selezione PC: distribuisce il tetto draft sui posti residui
-- invece di scegliere i rating più alti finché il budget si esaurisce.
do $$
declare
  v_sql text;
begin
  select pg_get_functiondef('private.completa_draft_squadra_pc(bigint,bigint)'::regprocedure) into v_sql;
  v_sql := replace(
    v_sql,
    'order by (p.overall + random() * 7) desc',
    'order by abs(private.ingaggio_teorico(p.overall, p.eta) - least(3500000, (v_league.budget_draft - v_speso) / greatest(v_league.slot_rosa - v_presi, 1))) + random() * 250000'
  );
  execute v_sql;
end;
$$;
