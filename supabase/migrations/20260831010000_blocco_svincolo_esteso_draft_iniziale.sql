-- ============================================================
--  BLOCCO SVINCOLO ESTESO AL DRAFT INIZIALE (E AL DRAFT DI RIENTRO
--  OFF-SEASON)
--  Deciso il 31 agosto 2026, in conversazione con l'utente, come
--  seguito di 20260829010000 e 20260829020000.
--
--  Quelle due migrazioni bloccavano lo svincolo prima di 10 giornate
--  per asta svincolati, scambio e mercato a scelte (scelte_draft), ma
--  escludevano esplicitamente il draft di costruzione rosa (25
--  giocatori, pacchetti a carte — sia modalita' 'by_role' che
--  '2_of_4'), motivando che a stato 'draft' lo svincolo e' gia'
--  bloccato fuori da stato 'stagione', quindi non c'era un canale di
--  abuso da chiudere.
--
--  L'utente ha chiesto di applicare la regola anche li', per
--  congruenza: un giocatore preso al draft deve aspettare le stesse
--  10 giornate prima di poter essere svincolato dalla squadra che lo
--  ha preso, esattamente come uno preso all'asta o via scambio.
--  Riguarda anche il draft di rientro in off-season (stessa RPC, stesso
--  ramo v_league.fase_carriera = 'offseason'): la giornata di
--  riferimento e' comunque la 1, perche' la numerazione delle giornate
--  riparte da 1 a ogni nuova stagione (vedi inizializza_stagione) e in
--  entrambi i casi il draft si chiude prima che le fixtures della
--  stagione in arrivo esistano — non c'e' quindi una v_prossima da
--  leggere da public.fixtures, a differenza di risolvi_aste_giorno e
--  rispondi_a_proposta.
--
--  Effetto pratico: chi finisce un pacchetto col portiere di troppo (o
--  qualunque doppione) non puo' piu' sistemarlo svincolandolo subito
--  dopo il draft — deve aspettare la giornata 11. E' una conseguenza
--  voluta della richiesta di congruenza, non un effetto collaterale
--  trascurato.
--
--  Non retroattivo, per lo stesso motivo delle due migrazioni
--  precedenti: tocca solo le insert di player_instances da qui in
--  avanti, le righe gia' a giornata_acquisizione NULL restano NULL (e
--  quindi mai bloccate).
-- ============================================================

begin;

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
    (league_id, player_id, team_id, overall_corrente, eta_corrente, ingaggio, giornata_acquisizione)
  values
    (p_league_id, v_player.id, v_team.id, v_player.overall, v_player.eta, v_ingaggio, 1)
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

create or replace function public.draft_scegli_pacchetto_2_of_4_impl(p_league_id bigint, p_player_id_1 bigint, p_player_id_2 bigint)
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
  v_carte bigint[];
  v_p1 public.players;
  v_p2 public.players;
  v_fap_overall smallint;
  v_fap_eta smallint;
  v_w1 bigint;
  v_w2 bigint;
  v_picked integer;
  v_speso bigint;
  v_inst1 public.player_instances;
  v_inst2 public.player_instances;
  v_done boolean;
  v_squadre_iscritte integer;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'Devi accedere prima di scegliere.';
  end if;
  if p_player_id_1 = p_player_id_2 then
    raise exception using errcode = '22023', message = 'Devi scegliere due giocatori diversi.';
  end if;

  select * into v_league from public.leagues where id = p_league_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Lega non trovata.';
  end if;
  select * into v_global from public.draft_state where league_id = p_league_id for update;
  if not found then
    raise exception using errcode = '55000', message = 'Il draft non è attivo.';
  end if;

  select * into v_team from public.teams
  where league_id = p_league_id and user_id = v_user_id and attiva;
  if not found then
    raise exception using errcode = '42501', message = 'Non hai una squadra attiva in questa lega.';
  end if;
  if not (v_league.stato = 'draft'
          or (v_league.fase_carriera = 'offseason' and v_team.entrata_stagione = v_league.stagione_corrente + 1)) then
    raise exception using errcode = '55000', message = 'Il draft non è attivo.';
  end if;

  select * into v_state from public.draft_team_state
  where team_id = v_team.id and league_id = p_league_id for update;
  if not found or v_state.stato <> 'in_corso' then
    raise exception using errcode = '55000', message = 'La tua rosa è già completa.';
  end if;
  if v_state.carta_gk is null then
    raise exception using errcode = '55000', message = 'Devi aprire un pacchetto prima di scegliere.';
  end if;

  v_carte := array[
    v_state.carta_gk, v_state.carta_def1, v_state.carta_def2,
    v_state.carta_mid1, v_state.carta_mid2, v_state.carta_att1, v_state.carta_att2
  ];
  if not (p_player_id_1 = any(v_carte) and p_player_id_2 = any(v_carte)) then
    raise exception using errcode = '22023', message = 'Puoi scegliere solo tra le carte del pacchetto aperto.';
  end if;

  select * into v_p1 from public.players where id = p_player_id_1;
  select * into v_p2 from public.players where id = p_player_id_2;

  -- Se il giocatore era nel pool tracciato (mai scelto prima), l'overall
  -- e l'eta' che entrano in rosa sono quelli evoluti fin qui, non quelli
  -- statici del catalogo.
  select fap.overall_corrente, fap.eta_corrente into v_fap_overall, v_fap_eta
  from public.free_agent_progression fap where fap.league_id = p_league_id and fap.player_id = p_player_id_1;
  if v_fap_overall is not null then v_p1.overall := v_fap_overall; v_p1.eta := v_fap_eta; end if;

  select fap.overall_corrente, fap.eta_corrente into v_fap_overall, v_fap_eta
  from public.free_agent_progression fap where fap.league_id = p_league_id and fap.player_id = p_player_id_2;
  if v_fap_overall is not null then v_p2.overall := v_fap_overall; v_p2.eta := v_fap_eta; end if;

  if exists (
    select 1 from public.player_instances
    where league_id = p_league_id and player_id in (p_player_id_1, p_player_id_2)
  ) then
    raise exception using errcode = '23505',
      message = 'Uno dei due giocatori è già stato assegnato: apri un nuovo pacchetto.';
  end if;

  select count(*) into v_picked
  from public.player_instances where league_id = p_league_id and team_id = v_team.id;
  v_speso := private.spesa_draft(v_team.id);

  v_w1 := private.ingaggio_teorico(v_p1.overall, v_p1.eta);
  if not private.pick_sostenibile(v_league.budget_draft, v_speso, v_league.slot_rosa, v_picked, v_p1.overall, v_p1.eta) then
    raise exception using errcode = '22023', message = 'Il primo giocatore non è sostenibile per la tua rosa.';
  end if;

  v_w2 := private.ingaggio_teorico(v_p2.overall, v_p2.eta);
  if not private.pick_sostenibile(v_league.budget_draft, v_speso + v_w1, v_league.slot_rosa, v_picked + 1, v_p2.overall, v_p2.eta) then
    raise exception using errcode = '22023', message = 'Il secondo giocatore non è sostenibile insieme al primo.';
  end if;

  insert into public.player_instances (league_id, player_id, team_id, overall_corrente, eta_corrente, ingaggio, giornata_acquisizione)
  values (p_league_id, p_player_id_1, v_team.id, v_p1.overall, v_p1.eta, v_w1, 1)
  returning * into v_inst1;
  insert into public.player_instances (league_id, player_id, team_id, overall_corrente, eta_corrente, ingaggio, giornata_acquisizione)
  values (p_league_id, p_player_id_2, v_team.id, v_p2.overall, v_p2.eta, v_w2, 1)
  returning * into v_inst2;

  delete from public.free_agent_progression
  where league_id = p_league_id and player_id in (p_player_id_1, p_player_id_2);

  insert into public.draft_picks (league_id, team_id, player_instance_id, pick_numero, club_estratto, ingaggio_pagato)
  values
    (p_league_id, v_team.id, v_inst1.id, v_global.pick_numero,     private.macro_ruolo(v_p1.posizioni), v_w1),
    (p_league_id, v_team.id, v_inst2.id, v_global.pick_numero + 1, private.macro_ruolo(v_p2.posizioni), v_w2);

  insert into public.transactions (league_id, team_id, tipo, importo, descrizione, saldo_dopo)
  values
    (p_league_id, v_team.id, 'draft_pick', -v_w1, 'Ingaggio draft: ' || v_p1.nome, 0),
    (p_league_id, v_team.id, 'draft_pick', -v_w2, 'Ingaggio draft: ' || v_p2.nome, 0);

  v_done := (v_state.pick_numero + 2) >= v_league.slot_rosa;
  update public.draft_team_state
  set pick_numero = pick_numero + 2,
      carta_gk = null, carta_def1 = null, carta_def2 = null,
      carta_mid1 = null, carta_mid2 = null, carta_att1 = null, carta_att2 = null,
      stato = case when v_done then 'concluso' else 'in_corso' end,
      aggiornato_il = now()
  where team_id = v_team.id;

  update public.draft_state set pick_numero = pick_numero + 2, aggiornato_il = now() where league_id = p_league_id;

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
    'league_id', p_league_id,
    'team_id', v_team.id,
    'player_instance_id_1', v_inst1.id,
    'player_instance_id_2', v_inst2.id,
    'ingaggio_1', v_w1,
    'ingaggio_2', v_w2,
    'speso', v_speso + v_w1 + v_w2,
    'draft_concluso', v_done
  );
end;
$$;

commit;
