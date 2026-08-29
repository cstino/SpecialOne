begin;

-- ============================================================
--  PACCHETTO DRAFT DA 7 CARTE (era 4)
--
--  Deciso il 29 agosto 2026, in conversazione con l'utente. Il pacchetto
--  del draft "2 of 4" (docs/decisioni-fase1.md §8) estraeva 1 carta per
--  ciascun macro-ruolo (GK/DEF/MID/ATT) e se ne tenevano 2. Ora estrae
--  1 portiere, 2 difensori, 2 centrocampisti, 2 attaccanti (7 carte) — se
--  ne tengono sempre 2, liberamente fra le 7. Non cambia nient'altro:
--  restano 12 pacchetti per una rosa fissa a 24, la soglia di solvibilita'
--  resta "almeno 2 carte ingaggiabili" (design §4.4), il reroll manuale
--  brucia ancora l'intero pacchetto.
--
--  Riguarda solo il draft '2_of_4' (public.leagues.modalita_draft): il
--  draft BY ROLE (un giocatore alla volta, docs/decisioni... non esiste
--  ancora un doc dedicato, vedi 20260808191000_modalita_draft_by_role.sql)
--  resta invariato, cosi' come il completamento automatico delle squadre
--  PC (private.completa_draft_squadra_pc), che non passa mai dal pacchetto.
-- ============================================================

alter table public.draft_team_state
  rename column carta_def to carta_def1;
alter table public.draft_team_state
  rename column carta_mid to carta_mid1;
alter table public.draft_team_state
  rename column carta_att to carta_att1;
alter table public.draft_team_state
  add column carta_def2 bigint references public.players (id),
  add column carta_mid2 bigint references public.players (id),
  add column carta_att2 bigint references public.players (id);

comment on column public.draft_team_state.carta_gk is
  'Le 7 carte del pacchetto aperto: 1 portiere, 2 difensori, 2 centrocampisti, 2 attaccanti. Tutte null = nessun pacchetto aperto.';

-- ------------------------------------------------------------
--  pesca_carta_ruolo: nuovo parametro p_esclusi per evitare di pescare due
--  volte la stessa carta quando un ruolo ne estrae 2 (DEF/MID/ATT). La
--  vecchia firma a 2 argomenti non serve piu' a nessun altro chiamante
--  (solo draft_apri_pacchetto_2_of_4_impl la usava).
-- ------------------------------------------------------------

drop function if exists private.pesca_carta_ruolo(public.leagues, text);

create or replace function private.pesca_carta_ruolo(
  p_league public.leagues,
  p_ruolo text,
  p_esclusi bigint[] default '{}'::bigint[]
) returns bigint
language sql
stable
set search_path = ''
as $$
  select p.id
  from public.players p
  where p.disponibile_estrazione
    and (p.elite_globale or p.campionato = any(p_league.campionati_attivi))
    and private.macro_ruolo(p.posizioni) = p_ruolo
    and not (p.id = any(p_esclusi))
    and not exists (
      select 1 from public.player_instances pi
      where pi.league_id = p_league.id and pi.player_id = p.id
    )
    and not exists (
      select 1 from public.retired_players rp
      where rp.league_id = p_league.id and rp.player_id = p.id
    )
  order by random()
  limit 1;
$$;

revoke all on function private.pesca_carta_ruolo(public.leagues, text, bigint[])
  from public, anon, authenticated;
grant execute on function private.pesca_carta_ruolo(public.leagues, text, bigint[])
  to service_role;

-- ------------------------------------------------------------
--  draft_apri_pacchetto_2_of_4_impl: estrae 7 carte invece di 4. La
--  soglia di solvibilita' resta "almeno 2 su tutte quelle estratte": chi
--  non e' ingaggiabile viene ripescato da solo, senza consumare reroll,
--  esattamente come prima (docs/decisioni-fase1.md §8).
-- ------------------------------------------------------------

create or replace function public.draft_apri_pacchetto_2_of_4_impl(p_league_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_league  public.leagues;
  v_global  public.draft_state;
  v_team    public.teams;
  v_state   public.draft_team_state;
  v_gk bigint; v_def1 bigint; v_def2 bigint; v_mid1 bigint; v_mid2 bigint; v_att1 bigint; v_att2 bigint;
  v_picked integer;
  v_speso bigint;
  v_ok_gk boolean; v_ok_def1 boolean; v_ok_def2 boolean;
  v_ok_mid1 boolean; v_ok_mid2 boolean; v_ok_att1 boolean; v_ok_att2 boolean;
  v_n_ok integer;
  v_tentativi int := 0;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'Devi accedere prima di aprire un pacchetto.';
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

  select * into v_state from public.draft_team_state
  where team_id = v_team.id and league_id = p_league_id for update;
  if not found or v_state.stato <> 'in_corso'
     or not (v_league.stato = 'draft'
             or (v_league.fase_carriera = 'offseason' and v_team.entrata_stagione = v_league.stagione_corrente + 1)) then
    raise exception using errcode = '55000', message = 'Il tuo draft non è attivo.';
  end if;

  if v_state.carta_gk is not null then
    return private.pacchetto_payload(p_league_id, v_team.id);
  end if;

  select count(*) into v_picked
  from public.player_instances where league_id = p_league_id and team_id = v_team.id;
  v_speso := private.spesa_draft(v_team.id);

  v_gk := null; v_def1 := null; v_def2 := null; v_mid1 := null; v_mid2 := null; v_att1 := null; v_att2 := null;
  loop
    v_tentativi := v_tentativi + 1;
    if v_tentativi > 40 then
      raise exception using errcode = '55000',
        message = 'Il pool attivo non ha più abbastanza giocatori sostenibili per completare un pacchetto.';
    end if;

    if v_gk is null then
      v_gk := private.pesca_carta_ruolo(v_league, 'GK');
      if v_gk is null then
        raise exception using errcode = '55000', message = 'Nessun portiere disponibile nel pool attivo.';
      end if;
    end if;
    if v_def1 is null then
      v_def1 := private.pesca_carta_ruolo(v_league, 'DEF', array_remove(array[v_def2], null));
      if v_def1 is null then
        raise exception using errcode = '55000', message = 'Nessun difensore disponibile nel pool attivo.';
      end if;
    end if;
    if v_def2 is null then
      v_def2 := private.pesca_carta_ruolo(v_league, 'DEF', array_remove(array[v_def1], null));
      if v_def2 is null then
        raise exception using errcode = '55000', message = 'Non ci sono abbastanza difensori disponibili nel pool attivo.';
      end if;
    end if;
    if v_mid1 is null then
      v_mid1 := private.pesca_carta_ruolo(v_league, 'MID', array_remove(array[v_mid2], null));
      if v_mid1 is null then
        raise exception using errcode = '55000', message = 'Nessun centrocampista disponibile nel pool attivo.';
      end if;
    end if;
    if v_mid2 is null then
      v_mid2 := private.pesca_carta_ruolo(v_league, 'MID', array_remove(array[v_mid1], null));
      if v_mid2 is null then
        raise exception using errcode = '55000', message = 'Non ci sono abbastanza centrocampisti disponibili nel pool attivo.';
      end if;
    end if;
    if v_att1 is null then
      v_att1 := private.pesca_carta_ruolo(v_league, 'ATT', array_remove(array[v_att2], null));
      if v_att1 is null then
        raise exception using errcode = '55000', message = 'Nessun attaccante disponibile nel pool attivo.';
      end if;
    end if;
    if v_att2 is null then
      v_att2 := private.pesca_carta_ruolo(v_league, 'ATT', array_remove(array[v_att1], null));
      if v_att2 is null then
        raise exception using errcode = '55000', message = 'Non ci sono abbastanza attaccanti disponibili nel pool attivo.';
      end if;
    end if;

    select private.pick_sostenibile(v_league.budget_draft, v_speso, v_league.slot_rosa, v_picked, p.overall, p.eta)
      into v_ok_gk from public.players p where p.id = v_gk;
    select private.pick_sostenibile(v_league.budget_draft, v_speso, v_league.slot_rosa, v_picked, p.overall, p.eta)
      into v_ok_def1 from public.players p where p.id = v_def1;
    select private.pick_sostenibile(v_league.budget_draft, v_speso, v_league.slot_rosa, v_picked, p.overall, p.eta)
      into v_ok_def2 from public.players p where p.id = v_def2;
    select private.pick_sostenibile(v_league.budget_draft, v_speso, v_league.slot_rosa, v_picked, p.overall, p.eta)
      into v_ok_mid1 from public.players p where p.id = v_mid1;
    select private.pick_sostenibile(v_league.budget_draft, v_speso, v_league.slot_rosa, v_picked, p.overall, p.eta)
      into v_ok_mid2 from public.players p where p.id = v_mid2;
    select private.pick_sostenibile(v_league.budget_draft, v_speso, v_league.slot_rosa, v_picked, p.overall, p.eta)
      into v_ok_att1 from public.players p where p.id = v_att1;
    select private.pick_sostenibile(v_league.budget_draft, v_speso, v_league.slot_rosa, v_picked, p.overall, p.eta)
      into v_ok_att2 from public.players p where p.id = v_att2;

    v_n_ok := (case when v_ok_gk then 1 else 0 end) + (case when v_ok_def1 then 1 else 0 end)
            + (case when v_ok_def2 then 1 else 0 end) + (case when v_ok_mid1 then 1 else 0 end)
            + (case when v_ok_mid2 then 1 else 0 end) + (case when v_ok_att1 then 1 else 0 end)
            + (case when v_ok_att2 then 1 else 0 end);

    exit when v_n_ok >= 2;

    update public.draft_team_state set spin_a_vuoto = spin_a_vuoto + 1 where team_id = v_team.id;
    if not v_ok_gk   then v_gk   := null; end if;
    if not v_ok_def1 then v_def1 := null; end if;
    if not v_ok_def2 then v_def2 := null; end if;
    if not v_ok_mid1 then v_mid1 := null; end if;
    if not v_ok_mid2 then v_mid2 := null; end if;
    if not v_ok_att1 then v_att1 := null; end if;
    if not v_ok_att2 then v_att2 := null; end if;
  end loop;

  update public.draft_team_state
  set carta_gk = v_gk, carta_def1 = v_def1, carta_def2 = v_def2,
      carta_mid1 = v_mid1, carta_mid2 = v_mid2, carta_att1 = v_att1, carta_att2 = v_att2,
      aggiornato_il = now()
  where team_id = v_team.id;

  return private.pacchetto_payload(p_league_id, v_team.id);
end;
$$;

-- ------------------------------------------------------------
--  pacchetto_payload: 7 righe invece di 4. L'ordine (GK, DEF, DEF, MID,
--  MID, ATT, ATT) e' fissato via colonna ordinale esplicita: il frontend
--  vi si affida per posizionare le carte nella griglia prima ancora che
--  arrivi il payload (segnaposto), quindi deve restare deterministico.
-- ------------------------------------------------------------

create or replace function private.pacchetto_payload(p_league_id bigint, p_team_id bigint)
returns jsonb
language plpgsql
stable security definer
set search_path = ''
as $$
declare
  v_league public.leagues;
  v_team public.teams;
  v_state public.draft_team_state;
  v_picked integer;
  v_speso bigint;
  v_carte jsonb;
begin
  select * into v_league from public.leagues where id = p_league_id;
  select * into v_team from public.teams where id = p_team_id and league_id = p_league_id;
  select * into v_state from public.draft_team_state where team_id = p_team_id and league_id = p_league_id;

  select count(*) into v_picked
  from public.player_instances where league_id = p_league_id and team_id = p_team_id;
  v_speso := private.spesa_draft(v_team.id);

  select coalesce(jsonb_agg(jsonb_build_object(
    'ruolo', c.ruolo,
    'id', p.id, 'nome', p.nome, 'club', p.club, 'campionato', p.campionato,
    'overall', p.overall, 'eta', p.eta, 'posizioni', p.posizioni, 'foto_url', p.foto_url,
    'ingaggio', private.ingaggio_teorico(p.overall, p.eta),
    'ingaggiabile', private.pick_sostenibile(
      v_league.budget_draft, v_speso, v_league.slot_rosa, v_picked, p.overall, p.eta
    )
  ) order by c.ordine), '[]'::jsonb)
  into v_carte
  from (values
    (0, 'GK',  v_state.carta_gk),
    (1, 'DEF', v_state.carta_def1),
    (2, 'DEF', v_state.carta_def2),
    (3, 'MID', v_state.carta_mid1),
    (4, 'MID', v_state.carta_mid2),
    (5, 'ATT', v_state.carta_att1),
    (6, 'ATT', v_state.carta_att2)
  ) as c(ordine, ruolo, player_id)
  join public.players p on p.id = c.player_id;

  return jsonb_build_object(
    'league_id', p_league_id,
    'team_id', p_team_id,
    'pick_numero', v_state.pick_numero,
    'stato', v_state.stato,
    'reroll_rimasti', v_team.reroll_rimasti,
    'speso', v_speso,
    'slot_occupati', v_picked,
    'carte', v_carte
  );
end;
$$;

-- ------------------------------------------------------------
--  draft_scegli_pacchetto_2_of_4_impl: la scelta resta "2 su tutte le
--  carte aperte", ora 7 invece di 4.
-- ------------------------------------------------------------

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

  insert into public.player_instances (league_id, player_id, team_id, overall_corrente, eta_corrente, ingaggio)
  values (p_league_id, p_player_id_1, v_team.id, v_p1.overall, v_p1.eta, v_w1)
  returning * into v_inst1;
  insert into public.player_instances (league_id, player_id, team_id, overall_corrente, eta_corrente, ingaggio)
  values (p_league_id, p_player_id_2, v_team.id, v_p2.overall, v_p2.eta, v_w2)
  returning * into v_inst2;

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

-- ------------------------------------------------------------
--  draft_pacchetto_reroll_2_of_4_impl: brucia ancora l'intero pacchetto,
--  ora 7 carte invece di 4.
-- ------------------------------------------------------------

create or replace function public.draft_pacchetto_reroll_2_of_4_impl(p_league_id bigint)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_team public.teams;
  v_state public.draft_team_state;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'Devi accedere prima del reroll.';
  end if;
  select * into v_team from public.teams
  where league_id = p_league_id and user_id = v_user_id and attiva;
  if not found then
    raise exception using errcode = '42501', message = 'Non hai una squadra attiva in questa lega.';
  end if;
  select * into v_state from public.draft_team_state
  where team_id = v_team.id and league_id = p_league_id for update;
  if not found or v_state.stato <> 'in_corso' then
    raise exception using errcode = '55000', message = 'Il tuo draft non è attivo.';
  end if;
  if v_state.carta_gk is null then
    raise exception using errcode = '55000', message = 'Devi aprire un pacchetto prima del reroll.';
  end if;
  if v_team.reroll_rimasti <= 0 then
    raise exception using errcode = '55000', message = 'Non hai più reroll disponibili.';
  end if;

  update public.teams set reroll_rimasti = reroll_rimasti - 1 where id = v_team.id;
  update public.draft_team_state
  set carta_gk = null, carta_def1 = null, carta_def2 = null,
      carta_mid1 = null, carta_mid2 = null, carta_att1 = null, carta_att2 = null,
      aggiornato_il = now()
  where team_id = v_team.id;

  return public.draft_apri_pacchetto(p_league_id);
end;
$$;

commit;
