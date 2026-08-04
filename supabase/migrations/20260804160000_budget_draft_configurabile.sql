-- ============================================================
--  BUDGET DRAFT CONFIGURABILE, INDIPENDENTE DAL BUDGET INIZIALE
--
--  Decisione utente, 4 agosto 2026: dopo il primo vero test le rose sono
--  uscite parecchio squilibrate. La causa e' il tetto draft fisso all'80%
--  del budget iniziale (design §4.3): l'unico modo di stringerlo era finora
--  abbassare anche il budget di stagione, che pero' serve intatto per
--  sponsor, montepremi e mercato (v_sponsor/v_pool/premi_partita restano
--  ancorati a budget_iniziale, non al tetto draft — vedi offseason_carriera).
--
--  Si scorpora quindi il tetto in una colonna propria, budget_draft,
--  impostata dall'admin in creazione lega come importo assoluto (non piu'
--  una percentuale fissa), vincolata a non superare il budget iniziale.
--  Le leghe esistenti mantengono il comportamento di sempre: backfill
--  all'80% del loro budget_iniziale.
-- ============================================================

alter table public.leagues
  add column budget_draft bigint;

update public.leagues
  set budget_draft = round(budget_iniziale * 0.80 / 100000) * 100000
  where budget_draft is null;

alter table public.leagues
  alter column budget_draft set not null,
  add constraint leagues_budget_draft_check check (budget_draft between 20000000 and 200000000),
  add constraint leagues_budget_draft_entro_iniziale check (budget_draft <= budget_iniziale);

comment on column public.leagues.budget_draft is
  'Tetto di monte ingaggi utilizzabile nel draft (design §4.3). Scelto dall''admin come importo assoluto invece che fisso all''80% di budget_iniziale; vincolato a <= budget_iniziale.';

-- ------------------------------------------------------------
--  crea_lega: nuovo parametro p_budget_draft. Il vecchio overload a 10
--  parametri va rimosso esplicitamente: altrimenti postgres registra le due
--  firme come funzioni distinte invece di sostituire quella esistente.
-- ------------------------------------------------------------

drop function if exists public.crea_lega(text, text, text, smallint, smallint, bigint, smallint, smallint, smallint, text[]);

create or replace function public.crea_lega(
  p_nome_lega text,
  p_nome_squadra text,
  p_stemma_url text,
  p_n_squadre smallint,
  p_n_gironi smallint,
  p_budget_iniziale bigint,
  p_budget_draft bigint,
  p_reroll_draft smallint,
  p_slot_rosa smallint,
  p_portieri_minimi smallint,
  p_campionati_attivi text[]
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_league public.leagues;
  v_team public.teams;
  v_codice text;
  v_campionati_validi constant text[] := array[
    'Premier League', 'La Liga', 'Serie A', 'Bundesliga', 'Ligue 1',
    'Eredivisie', 'Liga Portugal', 'Süper Lig', 'Saudi Pro League',
    'EFL Championship'
  ];
  v_tentativi smallint := 0;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'Devi accedere prima di creare una lega.';
  end if;

  p_nome_lega := trim(p_nome_lega);
  p_nome_squadra := trim(p_nome_squadra);
  p_portieri_minimi := 0;

  if length(p_nome_lega) not between 3 and 60 then
    raise exception using errcode = '22023', message = 'Il nome della lega deve avere da 3 a 60 caratteri.';
  end if;
  if length(p_nome_squadra) not between 2 and 40 then
    raise exception using errcode = '22023', message = 'Il nome della squadra deve avere da 2 a 40 caratteri.';
  end if;
  if p_n_squadre not between 4 and 20
    or p_n_gironi not between 2 and 6
    or p_budget_iniziale not between 50000000 and 200000000
    or p_budget_draft not between 20000000 and 200000000
    or p_budget_draft > p_budget_iniziale
    or p_reroll_draft not between 0 and 30
    or p_slot_rosa <> 24 then
    raise exception using errcode = '22023', message = 'Una o più impostazioni della lega non sono valide.';
  end if;
  if coalesce(cardinality(p_campionati_attivi), 0) = 0
    or not (p_campionati_attivi <@ v_campionati_validi)
    or cardinality(p_campionati_attivi) <> cardinality(array(select distinct unnest(p_campionati_attivi))) then
    raise exception using errcode = '22023', message = 'Seleziona almeno un campionato valido, senza duplicati.';
  end if;
  if not private.stemma_valido(p_stemma_url, v_user_id) then
    raise exception using errcode = '22023', message = 'Lo stemma selezionato non è valido.';
  end if;

  loop
    v_tentativi := v_tentativi + 1;
    v_codice := private.genera_codice_invito();
    begin
      -- Nasce gia' in 'draft': l'admin non aspetta gli altri per cominciare.
      insert into public.leagues (
        nome, admin_id, codice_invito, n_squadre, n_gironi,
        budget_iniziale, budget_draft, reroll_draft, slot_rosa, portieri_minimi,
        campionati_attivi, stato
      ) values (
        p_nome_lega, v_user_id, v_codice, p_n_squadre, p_n_gironi,
        p_budget_iniziale, p_budget_draft, p_reroll_draft, 24, p_portieri_minimi,
        p_campionati_attivi, 'draft'
      ) returning * into v_league;
      exit;
    exception when unique_violation then
      if v_tentativi >= 10 then
        raise exception 'Impossibile generare un codice invito univoco.';
      end if;
    end;
  end loop;

  insert into public.teams (
    league_id, user_id, nome, stemma_url, budget, reroll_rimasti
  ) values (
    v_league.id, v_user_id, p_nome_squadra, p_stemma_url,
    v_league.budget_iniziale, v_league.reroll_draft
  ) returning * into v_team;

  insert into public.transactions (
    league_id, team_id, tipo, importo, descrizione, saldo_dopo
  ) values (
    v_league.id, v_team.id, 'dotazione_iniziale', v_league.budget_iniziale,
    'Dotazione iniziale della lega', v_league.budget_iniziale
  );

  -- Contatore di lega (usato per numerare draft_picks, design §4) e stato di
  -- draft della squadra dell'admin: da qui puo' gia' aprire il primo pacchetto.
  insert into public.draft_state (league_id) values (v_league.id);
  insert into public.draft_team_state (team_id, league_id) values (v_team.id, v_league.id);

  return jsonb_build_object(
    'league_id', v_league.id,
    'team_id', v_team.id,
    'codice_invito', v_league.codice_invito
  );
end;
$$;

revoke all on function public.crea_lega(text, text, text, smallint, smallint, bigint, bigint, smallint, smallint, smallint, text[]) from public, anon, authenticated;
grant execute on function public.crea_lega(text, text, text, smallint, smallint, bigint, bigint, smallint, smallint, smallint, text[]) to authenticated;

-- ------------------------------------------------------------
--  pick_sostenibile: il secondo parametro era "budget_iniziale" e la
--  funzione calcolava da sola l'80%. Ora riceve direttamente il tetto
--  (budget_draft) gia' calcolato dal chiamante: stessi tipi di parametro,
--  cambia solo il nome (da qui il drop esplicito, postgres non permette di
--  rinominare un parametro con un semplice create or replace) e sparisce
--  la moltiplicazione interna.
-- ------------------------------------------------------------

drop function if exists private.pick_sostenibile(bigint, bigint, bigint, smallint, integer, smallint, smallint);

create or replace function private.pick_sostenibile(
  p_budget bigint,
  p_tetto_ingaggi bigint,
  p_speso bigint,
  p_slot_rosa smallint,
  p_giocatori_attuali integer,
  p_overall smallint,
  p_eta smallint
) returns boolean
language sql
immutable
parallel safe
set search_path = ''
as $$
  select
    p_budget - private.ingaggio_teorico(p_overall, p_eta)
      >= greatest(0, p_slot_rosa - p_giocatori_attuali - 1) * 500000
    and p_speso + private.ingaggio_teorico(p_overall, p_eta)
      <= p_tetto_ingaggi
$$;

revoke all on function private.pick_sostenibile(bigint, bigint, bigint, smallint, integer, smallint, smallint)
  from public, anon, authenticated;
grant execute on function private.pick_sostenibile(bigint, bigint, bigint, smallint, integer, smallint, smallint)
  to service_role;

-- ------------------------------------------------------------
--  pacchetto_payload: il flag "ingaggiabile" di ogni carta deve confrontarsi
--  col tetto draft, non con l'intero budget iniziale.
-- ------------------------------------------------------------

create or replace function private.pacchetto_payload(
  p_league_id bigint,
  p_team_id bigint
) returns jsonb
language plpgsql
stable
security definer
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
  v_speso := v_league.budget_iniziale - v_team.budget;

  select coalesce(jsonb_agg(jsonb_build_object(
    'ruolo', c.ruolo,
    'id', p.id, 'nome', p.nome, 'club', p.club, 'campionato', p.campionato,
    'overall', p.overall, 'eta', p.eta, 'posizioni', p.posizioni, 'foto_url', p.foto_url,
    'ingaggio', private.ingaggio_teorico(p.overall, p.eta),
    'ingaggiabile', private.pick_sostenibile(
      v_team.budget, v_league.budget_draft, v_speso, v_league.slot_rosa, v_picked, p.overall, p.eta
    )
  ) order by array_position(array['GK','DEF','MID','ATT'], c.ruolo)), '[]'::jsonb)
  into v_carte
  from (values
    ('GK',  v_state.carta_gk),
    ('DEF', v_state.carta_def),
    ('MID', v_state.carta_mid),
    ('ATT', v_state.carta_att)
  ) as c(ruolo, player_id)
  join public.players p on p.id = c.player_id;

  return jsonb_build_object(
    'league_id', p_league_id,
    'team_id', p_team_id,
    'pick_numero', v_state.pick_numero,
    'stato', v_state.stato,
    'reroll_rimasti', v_team.reroll_rimasti,
    'budget', v_team.budget,
    'slot_occupati', v_picked,
    'carte', v_carte
  );
end;
$$;

-- ------------------------------------------------------------
--  draft_apri_pacchetto: stessi 4 confronti di sostenibilita', contro il
--  tetto draft invece che contro l'80% del budget iniziale.
-- ------------------------------------------------------------

create or replace function public.draft_apri_pacchetto(p_league_id bigint)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_league  public.leagues;
  v_global  public.draft_state;
  v_team    public.teams;
  v_state   public.draft_team_state;
  v_gk bigint; v_def bigint; v_mid bigint; v_att bigint;
  v_picked integer;
  v_speso bigint;
  v_ok_gk boolean; v_ok_def boolean; v_ok_mid boolean; v_ok_att boolean;
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
  v_speso := v_league.budget_iniziale - v_team.budget;

  v_gk := null; v_def := null; v_mid := null; v_att := null;
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
    if v_def is null then
      v_def := private.pesca_carta_ruolo(v_league, 'DEF');
      if v_def is null then
        raise exception using errcode = '55000', message = 'Nessun difensore disponibile nel pool attivo.';
      end if;
    end if;
    if v_mid is null then
      v_mid := private.pesca_carta_ruolo(v_league, 'MID');
      if v_mid is null then
        raise exception using errcode = '55000', message = 'Nessun centrocampista disponibile nel pool attivo.';
      end if;
    end if;
    if v_att is null then
      v_att := private.pesca_carta_ruolo(v_league, 'ATT');
      if v_att is null then
        raise exception using errcode = '55000', message = 'Nessun attaccante disponibile nel pool attivo.';
      end if;
    end if;

    select private.pick_sostenibile(v_team.budget, v_league.budget_draft, v_speso, v_league.slot_rosa, v_picked, p.overall, p.eta)
      into v_ok_gk from public.players p where p.id = v_gk;
    select private.pick_sostenibile(v_team.budget, v_league.budget_draft, v_speso, v_league.slot_rosa, v_picked, p.overall, p.eta)
      into v_ok_def from public.players p where p.id = v_def;
    select private.pick_sostenibile(v_team.budget, v_league.budget_draft, v_speso, v_league.slot_rosa, v_picked, p.overall, p.eta)
      into v_ok_mid from public.players p where p.id = v_mid;
    select private.pick_sostenibile(v_team.budget, v_league.budget_draft, v_speso, v_league.slot_rosa, v_picked, p.overall, p.eta)
      into v_ok_att from public.players p where p.id = v_att;

    v_n_ok := (case when v_ok_gk then 1 else 0 end) + (case when v_ok_def then 1 else 0 end)
            + (case when v_ok_mid then 1 else 0 end) + (case when v_ok_att then 1 else 0 end);

    exit when v_n_ok >= 2;

    update public.draft_team_state set spin_a_vuoto = spin_a_vuoto + 1 where team_id = v_team.id;
    if not v_ok_gk  then v_gk  := null; end if;
    if not v_ok_def then v_def := null; end if;
    if not v_ok_mid then v_mid := null; end if;
    if not v_ok_att then v_att := null; end if;
  end loop;

  update public.draft_team_state
  set carta_gk = v_gk, carta_def = v_def, carta_mid = v_mid, carta_att = v_att, aggiornato_il = now()
  where team_id = v_team.id;

  return private.pacchetto_payload(p_league_id, v_team.id);
end;
$$;

-- ------------------------------------------------------------
--  draft_scegli_pacchetto: stessa validazione di sostenibilita' dei due
--  pick, contro il tetto draft invece che contro l'80% del budget iniziale.
--  Corpo identico a 20260803180000_fix_stagione_solo_a_lega_piena.sql a
--  parte i due argomenti a pick_sostenibile.
-- ------------------------------------------------------------

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
  if not private.pick_sostenibile(v_team.budget, v_league.budget_draft, v_speso, v_league.slot_rosa, v_picked, v_p1.overall, v_p1.eta) then
    raise exception using errcode = '22023', message = 'Il primo giocatore non è sostenibile per la tua rosa.';
  end if;

  v_w2 := private.ingaggio_teorico(v_p2.overall, v_p2.eta);
  if not private.pick_sostenibile(v_team.budget - v_w1, v_league.budget_draft, v_speso + v_w1, v_league.slot_rosa, v_picked + 1, v_p2.overall, v_p2.eta) then
    raise exception using errcode = '22023', message = 'Il secondo giocatore non è sostenibile insieme al primo.';
  end if;

  v_new_budget := v_team.budget - v_w1 - v_w2;

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
    'budget', v_new_budget,
    'draft_concluso', v_done
  );
end;
$$;
