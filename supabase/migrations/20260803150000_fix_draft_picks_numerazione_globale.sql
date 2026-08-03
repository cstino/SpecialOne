-- ============================================================
--  FIX: draft_scegli_pacchetto scriveva il pick_numero SBAGLIATO in draft_picks
--
--  `draft_picks` ha un vincolo UNIQUE (league_id, pick_numero): e' pensato
--  come numerazione GLOBALE di lega (il conteggio "pick n. tale dell'intero
--  draft"), non un contatore per squadra. Lo dimostra il codice di ieri per
--  l'ingresso in off-season, che semina il contatore leggendo
--  max(draft_picks.pick_numero)+1 su TUTTA la lega
--  (20260802215000_offseason_carriera.sql, 20260802221000_...), e la vecchia
--  funzione draft_pick dello spin-club, che infatti inseriva v_global.pick_numero
--  (il contatore di lega bloccato in draft_state), non quello di squadra.
--
--  draft_scegli_pacchetto, scritta oggi per il draft a pacchetti, inserisce
--  invece v_state.pick_numero: il contatore PER SQUADRA di draft_team_state,
--  che riparte da 0 per ogni squadra. Probabile scambio di variabile fra
--  v_state (per-squadra) e v_global (di lega), che hanno entrambe un campo
--  chiamato pick_numero.
--
--  L'effetto, scoperto completando il draft di una lega di prova con piu'
--  squadre: la prima squadra della lega occupa i numeri 0..23 senza problemi
--  (e' sola, nessuna collisione). La SECONDA squadra a scegliere fallisce
--  gia' alla prima coppia di carte: riparte anche lei da 0, che collide con
--  la riga gia' scritta dalla prima. In una lega vera qualsiasi squadra che
--  non sia la prima a completare un pacchetto avrebbe sbattuto contro questo
--  vincolo. Non e' un caso limite: e' il caso normale con piu' di un
--  partecipante, cioe' ogni lega reale.
--
--  Fix: usare v_global.pick_numero (gia' letto e lockato in testa alla
--  funzione con `for update`, quindi al riparo da corse fra scelte
--  simultanee di squadre diverse) al posto di v_state.pick_numero. Il
--  contatore per-squadra resta usato ESATTAMENTE come prima per capire se
--  quella squadra ha finito (v_state.pick_numero + 2 >= slot_rosa) e per
--  aggiornare il proprio draft_team_state: quella parte era corretta, il
--  problema era solo nei due valori scritti dentro draft_picks.
-- ============================================================

create or replace function public.draft_scegli_pacchetto(
  p_league_id bigint,
  p_player_id_1 bigint,
  p_player_id_2 bigint
) returns jsonb
language plpgsql
volatile
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
  v_w1 bigint;
  v_w2 bigint;
  v_picked integer;
  v_speso bigint;
  v_new_budget bigint;
  v_inst1 public.player_instances;
  v_inst2 public.player_instances;
  v_done boolean;
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

  v_carte := array[v_state.carta_gk, v_state.carta_def, v_state.carta_mid, v_state.carta_att];
  if not (p_player_id_1 = any(v_carte) and p_player_id_2 = any(v_carte)) then
    raise exception using errcode = '22023', message = 'Puoi scegliere solo tra le carte del pacchetto aperto.';
  end if;

  select * into v_p1 from public.players where id = p_player_id_1;
  select * into v_p2 from public.players where id = p_player_id_2;

  if exists (
    select 1 from public.player_instances
    where league_id = p_league_id and player_id in (p_player_id_1, p_player_id_2)
  ) then
    raise exception using errcode = '23505',
      message = 'Uno dei due giocatori è già stato assegnato: apri un nuovo pacchetto.';
  end if;

  select count(*) into v_picked
  from public.player_instances where league_id = p_league_id and team_id = v_team.id;
  v_speso := v_league.budget_iniziale - v_team.budget;

  v_w1 := private.ingaggio_teorico(v_p1.overall, v_p1.eta);
  if not private.pick_sostenibile(v_team.budget, v_league.budget_iniziale, v_speso, v_league.slot_rosa, v_picked, v_p1.overall, v_p1.eta) then
    raise exception using errcode = '22023', message = 'Il primo giocatore non è sostenibile per la tua rosa.';
  end if;

  v_w2 := private.ingaggio_teorico(v_p2.overall, v_p2.eta);
  if not private.pick_sostenibile(v_team.budget - v_w1, v_league.budget_iniziale, v_speso + v_w1, v_league.slot_rosa, v_picked + 1, v_p2.overall, v_p2.eta) then
    raise exception using errcode = '22023', message = 'Il secondo giocatore non è sostenibile insieme al primo.';
  end if;

  v_new_budget := v_team.budget - v_w1 - v_w2;

  insert into public.player_instances (league_id, player_id, team_id, overall_corrente, eta_corrente, ingaggio)
  values (p_league_id, p_player_id_1, v_team.id, v_p1.overall, v_p1.eta, v_w1)
  returning * into v_inst1;
  insert into public.player_instances (league_id, player_id, team_id, overall_corrente, eta_corrente, ingaggio)
  values (p_league_id, p_player_id_2, v_team.id, v_p2.overall, v_p2.eta, v_w2)
  returning * into v_inst2;

  -- FIX: v_global.pick_numero (contatore di LEGA, unico su tutta draft_picks)
  -- al posto di v_state.pick_numero (contatore di SQUADRA, riparte da 0 per
  -- ognuna e collide con qualunque altra squadra oltre la prima).
  insert into public.draft_picks (league_id, team_id, player_instance_id, pick_numero, club_estratto, ingaggio_pagato)
  values
    (p_league_id, v_team.id, v_inst1.id, v_global.pick_numero,     private.macro_ruolo(v_p1.posizioni), v_w1),
    (p_league_id, v_team.id, v_inst2.id, v_global.pick_numero + 1, private.macro_ruolo(v_p2.posizioni), v_w2);

  update public.teams set budget = v_new_budget where id = v_team.id;
  insert into public.transactions (league_id, team_id, tipo, importo, descrizione, saldo_dopo)
  values
    (p_league_id, v_team.id, 'draft_pick', -v_w1, 'Ingaggio draft: ' || v_p1.nome, v_new_budget + v_w2),
    (p_league_id, v_team.id, 'draft_pick', -v_w2, 'Ingaggio draft: ' || v_p2.nome, v_new_budget);

  v_done := (v_state.pick_numero + 2) >= v_league.slot_rosa;
  update public.draft_team_state
  set pick_numero = pick_numero + 2,
      carta_gk = null, carta_def = null, carta_mid = null, carta_att = null,
      stato = case when v_done then 'concluso' else 'in_corso' end,
      aggiornato_il = now()
  where team_id = v_team.id;

  update public.draft_state set pick_numero = pick_numero + 2, aggiornato_il = now() where league_id = p_league_id;

  if v_league.stato = 'draft' and not exists (
    select 1 from public.draft_team_state where league_id = p_league_id and stato <> 'concluso'
  ) then
    update public.draft_state set stato = 'concluso' where league_id = p_league_id;
    update public.leagues set stato = 'stagione' where id = p_league_id;
  end if;

  return jsonb_build_object(
    'league_id', p_league_id,
    'team_id', v_team.id,
    'player_instance_id_1', v_inst1.id,
    'player_instance_id_2', v_inst2.id,
    'ingaggio_1', v_w1,
    'ingaggio_2', v_w2,
    'budget', v_new_budget,
    'draft_concluso', v_done
  );
end;
$$;

revoke all on function public.draft_scegli_pacchetto(bigint, bigint, bigint) from public, anon;
grant execute on function public.draft_scegli_pacchetto(bigint, bigint, bigint) to authenticated;
