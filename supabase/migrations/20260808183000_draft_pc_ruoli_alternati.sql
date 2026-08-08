-- Le rose PC devono spendere il budget su tutti i reparti, non a blocchi.
do $$
declare v_sql text; begin
  select pg_get_functiondef('private.completa_draft_squadra_pc(bigint,bigint)'::regprocedure) into v_sql;
  v_sql := regexp_replace(
    v_sql,
    '(?s)select case.*?where pi\.league_id = p_league_id and pi\.team_id = p_team_id;',
    $replacement$v_ruolo := (array['GK','DEF','MID','ATT','DEF','MID','ATT','DEF','MID','ATT','DEF','MID','GK','DEF','MID','ATT','DEF','MID','ATT','DEF','MID','DEF','MID','ATT'])[v_presi + 1];$replacement$
  );
  execute v_sql;
end $$;
