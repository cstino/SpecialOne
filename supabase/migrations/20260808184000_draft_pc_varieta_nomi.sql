do $$ declare v_sql text; begin
  select pg_get_functiondef('private.completa_draft_squadra_pc(bigint,bigint)'::regprocedure) into v_sql;
  v_sql := replace(v_sql, 'order by p.id', 'order by abs(p.id - mod(p_team_id * 7919 + v_presi * 104729, 6000))');
  execute v_sql;
end $$;
update public.teams set nome = case stemma_url
  when 'preset:alci' then 'Borgo Alce' when 'preset:aliens' then 'Stella Verde' when 'preset:aquile' then 'Aquila Calcio'
  when 'preset:aviator' then 'Aviatori FC' when 'preset:bigbrain' then 'Genius FC' when 'preset:eagle' then 'Real Aquila'
  when 'preset:generale' then 'Atletico Imperiale' when 'preset:leoni' then 'Leoni 1926' when 'preset:lions' then 'Lions United'
  when 'preset:lupo' then 'Lupi FC' when 'preset:rocca' then 'Rocca Calcio' when 'preset:skull' then 'Teschio FC'
  when 'preset:torres' then 'Torres Nuova' when 'preset:wolves' then 'Wolves City' when 'preset:twins' then 'Gemini FC'
  when 'preset:rosa' then 'Roseto Calcio' when 'preset:piramidi' then 'Piramide FC' when 'preset:slot' then 'Fortuna FC'
  when 'preset:onepiece' then 'Grand Line FC' else nome end where controllata_da_pc;
