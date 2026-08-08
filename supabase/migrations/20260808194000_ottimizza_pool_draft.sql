begin;

create index if not exists players_draft_pool_lookup_idx
  on public.players (
    campionato,
    (private.macro_ruolo(posizioni)),
    (private.ingaggio_teorico(overall, eta)),
    id
  )
  where disponibile_estrazione;

-- Allinea BY ROLE allo stesso pool del draft classico: giocatori nascosti e
-- ritirati non possono essere estratti, gli elite globali restano disponibili.
do $$
declare v_sql text;
begin
  select pg_get_functiondef('public.draft_by_role_spin(bigint,text)'::regprocedure) into v_sql;
  v_sql := replace(v_sql,
    'where p.campionato = any(v_league.campionati_attivi)',
    'where p.disponibile_estrazione' || chr(10) ||
    '    and (p.elite_globale or p.campionato = any(v_league.campionati_attivi))');
  execute v_sql;

  select pg_get_functiondef('public.draft_by_role_reroll(bigint)'::regprocedure) into v_sql;
  v_sql := replace(v_sql,
    'where p.campionato = any(v_league.campionati_attivi)',
    'where p.disponibile_estrazione' || chr(10) ||
    '    and (p.elite_globale or p.campionato = any(v_league.campionati_attivi))');
  execute v_sql;
end $$;

-- Versione indicizzata e adattiva del draft PC. La prima ricerca usa una
-- fascia d'ingaggio stretta e l'ordine della PK, evitando ORDER BY random()
-- su tutto il catalogo; il fallback economico garantisce il completamento.
create or replace function private.completa_draft_squadra_pc(
  p_league_id bigint,
  p_team_id bigint
) returns void
language plpgsql volatile security definer set search_path = ''
as $$
declare
  v_league public.leagues;
  v_team public.teams;
  v_player public.players;
  v_ruolo text;
  v_presi integer;
  v_speso bigint;
  v_ingaggio bigint;
  v_pick bigint;
  v_slot_rimasti integer;
  v_media_disponibile bigint;
  v_target bigint;
begin
  select * into v_league from public.leagues where id = p_league_id for update;
  select * into v_team from public.teams
  where id = p_team_id and league_id = p_league_id and controllata_da_pc and attiva
  for update;
  if not found then
    raise exception using errcode = '22023', message = 'La squadra indicata non e'' controllata dal PC.';
  end if;

  loop
    select count(*) into v_presi from public.player_instances
    where league_id = p_league_id and team_id = p_team_id;
    exit when v_presi >= v_league.slot_rosa;

    if v_league.modalita_draft = 'by_role' then
      v_ruolo := (array['GK','DEF','MID','ATT'])[1 + floor(random() * 4)::integer];
    else
      v_ruolo := (array['GK','DEF','MID','ATT','DEF','MID','ATT','DEF','MID','ATT','DEF','MID','GK','DEF','MID','ATT','DEF','MID','ATT','DEF','MID','DEF','MID','ATT'])[v_presi + 1];
    end if;

    v_speso := v_league.budget_iniziale - v_team.budget;
    v_slot_rimasti := greatest(v_league.slot_rosa - v_presi, 1);
    v_media_disponibile := greatest(500000, (v_league.budget_draft - v_speso) / v_slot_rimasti);
    v_target := greatest(500000, round(v_media_disponibile * (0.78 + random() * 0.28))::bigint);

    select p.* into v_player
    from public.players p
    where p.disponibile_estrazione
      and (p.elite_globale or p.campionato = any(v_league.campionati_attivi))
      and private.macro_ruolo(p.posizioni) = v_ruolo
      and private.ingaggio_teorico(p.overall, p.eta)
        between greatest(500000, v_target - 250000) and v_target + 250000
      and not exists (
        select 1 from public.player_instances pi
        where pi.league_id = p_league_id and pi.player_id = p.id
      )
      and not exists (
        select 1 from public.retired_players rp
        where rp.league_id = p_league_id and rp.player_id = p.id
      )
      and private.pick_sostenibile(
        v_team.budget, v_league.budget_draft, v_speso, v_league.slot_rosa,
        v_presi, p.overall, p.eta
      )
    order by p.id
    limit 1;

    if not found then
      select p.* into v_player
      from public.players p
      where p.disponibile_estrazione
        and (p.elite_globale or p.campionato = any(v_league.campionati_attivi))
        and not exists (
          select 1 from public.player_instances pi
          where pi.league_id = p_league_id and pi.player_id = p.id
        )
        and not exists (
          select 1 from public.retired_players rp
          where rp.league_id = p_league_id and rp.player_id = p.id
        )
        and private.pick_sostenibile(
          v_team.budget, v_league.budget_draft, v_speso, v_league.slot_rosa,
          v_presi, p.overall, p.eta
        )
      order by private.ingaggio_teorico(p.overall, p.eta), p.id
      limit 1;
      if not found then
        raise exception using errcode = '55000',
          message = 'Il pool non contiene abbastanza giocatori sostenibili per completare tutte le rose.';
      end if;
    end if;

    v_ruolo := private.macro_ruolo(v_player.posizioni);
    v_ingaggio := private.ingaggio_teorico(v_player.overall, v_player.eta);
    insert into public.player_instances
      (league_id, player_id, team_id, overall_corrente, eta_corrente, ingaggio)
    values
      (p_league_id, v_player.id, p_team_id, v_player.overall, v_player.eta, v_ingaggio);

    select pick_numero into v_pick from public.draft_state where league_id = p_league_id for update;
    insert into public.draft_picks
      (league_id, team_id, player_instance_id, pick_numero, club_estratto, ingaggio_pagato)
    select p_league_id, p_team_id, id, v_pick, v_ruolo, v_ingaggio
    from public.player_instances
    where league_id = p_league_id and player_id = v_player.id;

    v_team.budget := v_team.budget - v_ingaggio;
    update public.teams set budget = v_team.budget where id = p_team_id;
    update public.draft_state set pick_numero = pick_numero + 1, aggiornato_il = now()
    where league_id = p_league_id;
    insert into public.transactions (league_id, team_id, tipo, importo, descrizione, saldo_dopo)
    values (p_league_id, p_team_id, 'draft_pick', -v_ingaggio, 'Ingaggio draft PC: ' || v_player.nome, v_team.budget);
  end loop;

  update public.draft_team_state
  set pick_numero = v_league.slot_rosa, stato = 'concluso',
      carta_gk = null, carta_def = null, carta_mid = null, carta_att = null,
      carta_ruolo = null, ruolo_scelto = null, aggiornato_il = now()
  where league_id = p_league_id and team_id = p_team_id;
end;
$$;

revoke all on function private.completa_draft_squadra_pc(bigint,bigint)
  from public, anon, authenticated;
grant execute on function private.completa_draft_squadra_pc(bigint,bigint) to service_role;

commit;
