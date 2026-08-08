do $$ declare v_sql text; begin
  select pg_get_functiondef('private.completa_draft_squadra_pc(bigint,bigint)'::regprocedure) into v_sql;
  v_sql := replace(v_sql, 'order by abs(p.id - mod(p_team_id * 7919 + v_presi * 104729, 6000))', 'order by p.id');
  execute v_sql;
end $$;
