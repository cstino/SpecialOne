-- Se il ruolo programmato non ha più carte sostenibili, il PC fa un reroll
-- tra tutti i ruoli disponibili senza mai allentare il tetto draft.
do $$
declare v_sql text; begin
  select pg_get_functiondef('private.completa_draft_squadra_pc(bigint,bigint)'::regprocedure) into v_sql;
  v_sql := replace(v_sql,
    'if not found then' || chr(10) || '      raise exception using errcode = ''55000'', message = ''Il pool non contiene giocatori PC sostenibili per il draft.'';' || chr(10) || '    end if;',
    'if not found then' || chr(10) ||
    '      select p.* into v_player from public.players p where p.campionato = any(v_league.campionati_attivi) and not exists (select 1 from public.player_instances pi where pi.league_id = p_league_id and pi.player_id = p.id) and private.pick_sostenibile(v_team.budget, v_league.budget_draft, v_speso, v_league.slot_rosa, v_presi, p.overall, p.eta) order by p.id limit 1;' || chr(10) ||
    '      if not found then raise exception using errcode = ''55000'', message = ''Il pool non contiene giocatori PC sostenibili per il draft.''; end if;' || chr(10) ||
    '    end if;'
  );
  execute v_sql;
end $$;
