begin;

-- ============================================================
--  Draft BY ROLE: stessa estensione della pipeline 2 of 4.
-- ============================================================

create or replace function public.draft_by_role_spin(p_league_id bigint, p_ruolo text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_league public.leagues;
  v_team public.teams;
  v_state public.draft_team_state;
  v_player_id bigint;
  v_picked integer;
  v_speso bigint;
  v_ruolo text := upper(btrim(coalesce(p_ruolo, '')));
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'Devi accedere prima di effettuare lo spin.';
  end if;
  if v_ruolo not in ('GK', 'DEF', 'MID', 'ATT') then
    raise exception using errcode = '22023', message = 'Scegli un ruolo valido.';
  end if;

  select * into v_league from public.leagues where id = p_league_id;
  if not found then raise exception using errcode = 'P0002', message = 'Lega non trovata.'; end if;
  if v_league.modalita_draft <> 'by_role' then
    raise exception using errcode = '55000', message = 'Questa lega usa il draft 2 of 4.';
  end if;

  perform 1 from public.draft_state where league_id = p_league_id for update;
  if not found then raise exception using errcode = '55000', message = 'Il draft non e'' attivo.'; end if;
  select * into v_team from public.teams
  where league_id = p_league_id and user_id = v_user_id and attiva;
  if not found then raise exception using errcode = '42501', message = 'Non hai una squadra attiva in questa lega.'; end if;
  select * into v_state from public.draft_team_state
  where team_id = v_team.id and league_id = p_league_id for update;
  if not found or v_state.stato <> 'in_corso'
     or not (v_league.stato = 'draft' or
       (v_league.fase_carriera = 'offseason' and v_team.entrata_stagione = v_league.stagione_corrente + 1)) then
    raise exception using errcode = '55000', message = 'Il tuo draft non e'' attivo.';
  end if;

  if v_state.carta_ruolo is not null then
    return private.by_role_payload(p_league_id, v_team.id);
  end if;

  select count(*) into v_picked from public.player_instances
  where league_id = p_league_id and team_id = v_team.id;
  v_speso := private.spesa_draft(v_team.id);

  select p.id into v_player_id
  from public.players p
  left join public.free_agent_progression fap on fap.league_id = p_league_id and fap.player_id = p.id
  where p.disponibile_estrazione
    and (p.elite_globale or p.campionato = any(v_league.campionati_attivi))
    and private.macro_ruolo(p.posizioni) = v_ruolo
    and not exists (
      select 1 from public.player_instances pi
      where pi.league_id = p_league_id and pi.player_id = p.id
    )
    and private.pick_sostenibile(
      v_league.budget_draft, v_speso, v_league.slot_rosa, v_picked,
      coalesce(fap.overall_corrente, p.overall), coalesce(fap.eta_corrente, p.eta)
    )
  order by random()
  limit 1;
  if v_player_id is null then
    raise exception using errcode = '55000',
      message = 'Non ci sono giocatori sostenibili disponibili per questo ruolo. Scegli un altro ruolo.';
  end if;

  update public.draft_team_state
  set carta_ruolo = v_player_id, ruolo_scelto = v_ruolo, aggiornato_il = now()
  where team_id = v_team.id;
  return private.by_role_payload(p_league_id, v_team.id);
end;
$$;

create or replace function private.by_role_payload(p_league_id bigint, p_team_id bigint)
returns jsonb
language plpgsql
stable security definer
set search_path = ''
as $$
declare
  v_league public.leagues;
  v_team public.teams;
  v_state public.draft_team_state;
  v_player public.players;
  v_fap_overall smallint;
  v_fap_eta smallint;
  v_picked integer;
  v_speso bigint;
  v_carta jsonb := null;
begin
  select * into v_league from public.leagues where id = p_league_id;
  select * into v_team from public.teams where id = p_team_id and league_id = p_league_id;
  select * into v_state from public.draft_team_state where team_id = p_team_id and league_id = p_league_id;

  select count(*) into v_picked
  from public.player_instances where league_id = p_league_id and team_id = p_team_id;
  v_speso := private.spesa_draft(v_team.id);

  if v_state.carta_ruolo is not null then
    select * into v_player from public.players where id = v_state.carta_ruolo;
    select fap.overall_corrente, fap.eta_corrente into v_fap_overall, v_fap_eta
    from public.free_agent_progression fap where fap.league_id = p_league_id and fap.player_id = v_player.id;
    if v_fap_overall is not null then v_player.overall := v_fap_overall; v_player.eta := v_fap_eta; end if;

    v_carta := jsonb_build_object(
      'ruolo', v_state.ruolo_scelto,
      'id', v_player.id, 'nome', v_player.nome, 'club', v_player.club,
      'campionato', v_player.campionato, 'overall', v_player.overall,
      'eta', v_player.eta, 'posizioni', v_player.posizioni, 'foto_url', v_player.foto_url,
      'ingaggio', private.ingaggio_teorico(v_player.overall, v_player.eta),
      'ingaggiabile', private.pick_sostenibile(
        v_league.budget_draft, v_speso, v_league.slot_rosa,
        v_picked, v_player.overall, v_player.eta
      )
    );
  end if;

  return jsonb_build_object(
    'league_id', p_league_id, 'team_id', p_team_id,
    'pick_numero', v_state.pick_numero, 'stato', v_state.stato,
    'reroll_rimasti', v_team.reroll_rimasti, 'speso', v_speso,
    'slot_occupati', v_picked, 'ruolo_scelto', v_state.ruolo_scelto,
    'carta', v_carta
  );
end;
$$;

create or replace function public.draft_by_role_ingaggia(p_league_id bigint, p_player_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_league public.leagues;
  v_global public.draft_state;
  v_team public.teams;
  v_state public.draft_team_state;
  v_player public.players;
  v_fap_overall smallint;
  v_fap_eta smallint;
  v_instance public.player_instances;
  v_ingaggio bigint;
  v_picked integer;
  v_speso bigint;
  v_done boolean;
  v_squadre_iscritte integer;
begin
  if v_user_id is null then raise exception using errcode = '42501', message = 'Devi accedere prima di ingaggiare.'; end if;
  select * into v_league from public.leagues where id = p_league_id;
  if not found or v_league.modalita_draft <> 'by_role' then
    raise exception using errcode = '55000', message = 'Questa lega non usa il draft BY ROLE.';
  end if;
  select * into v_global from public.draft_state where league_id = p_league_id for update;
  if not found then raise exception using errcode = '55000', message = 'Il draft non e'' attivo.'; end if;
  select * into v_team from public.teams
  where league_id = p_league_id and user_id = v_user_id and attiva for update;
  if not found then raise exception using errcode = '42501', message = 'Non hai una squadra attiva in questa lega.'; end if;
  select * into v_state from public.draft_team_state
  where team_id = v_team.id and league_id = p_league_id for update;
  if not found or v_state.stato <> 'in_corso' or v_state.carta_ruolo is null then
    raise exception using errcode = '55000', message = 'Devi effettuare uno spin prima di ingaggiare.';
  end if;
  if p_player_id <> v_state.carta_ruolo then
    raise exception using errcode = '22023', message = 'Puoi ingaggiare solo il giocatore dello spin aperto.';
  end if;
  if not (v_league.stato = 'draft' or
    (v_league.fase_carriera = 'offseason' and v_team.entrata_stagione = v_league.stagione_corrente + 1)) then
    raise exception using errcode = '55000', message = 'Il tuo draft non e'' attivo.';
  end if;

  select * into v_player from public.players where id = p_player_id;
  select fap.overall_corrente, fap.eta_corrente into v_fap_overall, v_fap_eta
  from public.free_agent_progression fap where fap.league_id = p_league_id and fap.player_id = p_player_id;
  if v_fap_overall is not null then v_player.overall := v_fap_overall; v_player.eta := v_fap_eta; end if;

  if exists (select 1 from public.player_instances where league_id = p_league_id and player_id = p_player_id) then
    raise exception using errcode = '23505', message = 'Il giocatore e'' appena stato assegnato a un''altra squadra: usa il reroll.';
  end if;
  select count(*) into v_picked from public.player_instances
  where league_id = p_league_id and team_id = v_team.id;
  v_speso := private.spesa_draft(v_team.id);
  if not private.pick_sostenibile(
    v_league.budget_draft, v_speso, v_league.slot_rosa, v_picked, v_player.overall, v_player.eta
  ) then
    raise exception using errcode = '22023', message = 'Il giocatore non e'' sostenibile per completare la rosa.';
  end if;

  v_ingaggio := private.ingaggio_teorico(v_player.overall, v_player.eta);
  insert into public.player_instances
    (league_id, player_id, team_id, overall_corrente, eta_corrente, ingaggio)
  values
    (p_league_id, v_player.id, v_team.id, v_player.overall, v_player.eta, v_ingaggio)
  returning * into v_instance;

  delete from public.free_agent_progression where league_id = p_league_id and player_id = p_player_id;

  insert into public.draft_picks
    (league_id, team_id, player_instance_id, pick_numero, club_estratto, ingaggio_pagato)
  values
    (p_league_id, v_team.id, v_instance.id, v_global.pick_numero, v_state.ruolo_scelto, v_ingaggio);

  insert into public.transactions (league_id, team_id, tipo, importo, descrizione, saldo_dopo)
  values (p_league_id, v_team.id, 'draft_pick', -v_ingaggio, 'Ingaggio draft BY ROLE: ' || v_player.nome, 0);

  v_done := v_picked + 1 >= v_league.slot_rosa;
  update public.draft_team_state
  set pick_numero = pick_numero + 1, carta_ruolo = null, ruolo_scelto = null,
      stato = case when v_done then 'concluso' else 'in_corso' end,
      aggiornato_il = now()
  where team_id = v_team.id;
  update public.draft_state set pick_numero = pick_numero + 1, aggiornato_il = now()
  where league_id = p_league_id;

  if v_league.stato = 'draft' then
    select count(*) into v_squadre_iscritte from public.teams where league_id = p_league_id;
    if v_squadre_iscritte = v_league.n_squadre and not exists (
      select 1 from public.draft_team_state where league_id = p_league_id and stato <> 'concluso'
    ) then
      update public.draft_state set stato = 'concluso' where league_id = p_league_id;
      update public.leagues set stato = 'stagione' where id = p_league_id;
    end if;
  end if;

  return jsonb_build_object(
    'league_id', p_league_id, 'team_id', v_team.id,
    'player_instance_id', v_instance.id, 'ingaggio', v_ingaggio,
    'speso', v_speso + v_ingaggio, 'draft_concluso', v_done
  );
end;
$$;

commit;
