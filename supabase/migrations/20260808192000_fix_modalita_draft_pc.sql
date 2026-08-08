begin;

-- La funzione PC era stata compattata da una migrazione precedente: questa
-- sostituzione usa la forma effettivamente presente anche sul database remoto.
do $$
declare v_sql text;
begin
  select pg_get_functiondef('private.completa_draft_squadra_pc(bigint,bigint)'::regprocedure) into v_sql;
  v_sql := replace(v_sql,
    $old$    v_ruolo := (array['GK','DEF','MID','ATT','DEF','MID','ATT','DEF','MID','ATT','DEF','MID','GK','DEF','MID','ATT','DEF','MID','ATT','DEF','MID','DEF','MID','ATT'])[v_presi + 1];$old$,
    $new$    if v_league.modalita_draft = 'by_role' then
      v_ruolo := (array['GK','DEF','MID','ATT'])[1 + floor(random() * 4)::integer];
    else
      v_ruolo := (array['GK','DEF','MID','ATT','DEF','MID','ATT','DEF','MID','ATT','DEF','MID','GK','DEF','MID','ATT','DEF','MID','ATT','DEF','MID','DEF','MID','ATT'])[v_presi + 1];
    end if;$new$);
  v_sql := replace(v_sql,
    '    v_ingaggio := private.ingaggio_teorico(v_player.overall, v_player.eta);',
    '    v_ruolo := private.macro_ruolo(v_player.posizioni);' || chr(10) ||
    '    v_ingaggio := private.ingaggio_teorico(v_player.overall, v_player.eta);'
  );
  v_sql := replace(v_sql,
    '      carta_gk = null, carta_def = null, carta_mid = null, carta_att = null, aggiornato_il = now()',
    '      carta_gk = null, carta_def = null, carta_mid = null, carta_att = null,' || chr(10) ||
    '      carta_ruolo = null, ruolo_scelto = null, aggiornato_il = now()'
  );
  if position('v_league.modalita_draft = ''by_role''' in v_sql) = 0 then
    raise exception 'Impossibile aggiornare il comportamento draft delle squadre PC.';
  end if;
  execute v_sql;
end $$;

commit;
