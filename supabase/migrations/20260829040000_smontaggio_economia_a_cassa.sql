-- Transazione esplicita: se una qualsiasi istruzione qui sotto fallisse
-- (una firma sbagliata, un riferimento residuo a una colonna rimossa),
-- tutto il file si annulla invece di lasciare il database a meta' strada
-- fra vecchio e nuovo modello.
begin;

-- ============================================================
--  SMONTAGGIO DEL MODELLO A CASSA — passo 6 di docs/decisioni-economia.md
--
--  I passi 1-5 (tetto, contratti annuali, aste, PC, draft, scambi) sono
--  fatti da giorni: verifica_capienza/monte_ingaggi/tetto_ingaggi sono gia'
--  la fonte di verita' per rinnovi, scambi e aste. Ma tre pezzi restavano
--  ancora sul vecchio modello a cassa, e non per dimenticanza cosmetica:
--
--  1. private.paga_premi_quando_giornata_completa (trigger su fixtures) e
--     tutta la catena che paga "premi partita" a ogni giornata simulata,
--     tuttora attiva ogni notte.
--  2. public.prepara_offseason accredita ancora sponsor/premi/partecipazione
--     e li somma a teams.budget.
--  3. private.finalizza_offseason decide chi viene svincolato d'ufficio e
--     chi completa la rosa a 21 confrontando teams.budget, non il tetto.
--
--  A queste si aggiunge un quarto pezzo emerso solo interrogando il
--  database live (non documentato nella tabella del passo 4 "Draft: fatto"):
--  l'intero draft (2-of-4 e BY ROLE, umano e PC) traccia ancora la spesa
--  aggiornando teams.budget. La buona notizia, verificata leggendo il
--  codice: private.pick_sostenibile ha gia' un parametro "p_budget" che il
--  suo corpo non usa affatto (la vera soglia e' p_tetto_ingaggi, alimentato
--  da league.budget_draft — il tetto SPECIFICO del draft, l'80% del budget
--  citato in CLAUDE.md §5, deliberatamente piu' basso del tetto ingaggi di
--  stagione: lascia margine per il mercato). E private.spesa_draft calcola
--  la spesa dalla tabella transactions, non da teams.budget. Rimuovere la
--  colonna dal draft e' quindi una pulizia meccanica, non una riscrittura
--  di logica: il parametro morto viene tolto, la scrittura ridondante pure.
--
--  Ordine di questo file: prima si riscrivono (CREATE OR REPLACE) tutte le
--  funzioni ancora vive che referenziano budget/budget_ingaggi_riservato,
--  poi si disattiva la catena dei premi partita, poi si elimina il codice
--  gia' morto (verificato a zero chiamanti nel database live), infine si
--  eliminano le colonne. Questo ordine e' obbligato: una volta tolte le
--  colonne, nessuna funzione puo' piu' referenziarle nemmeno nel corpo.
--
--  NON tocca leagues.budget_iniziale (letto da troppi altri punti, il
--  documento stesso dice "va spento per ultimo") ne' i contratti pluriennali
--  ereditati da Real Fampionato: questo file spegne solo il motore a cassa,
--  non riscrive le regole di durata dei contratti.
-- ============================================================


-- ------------------------------------------------------------
--  1. private.pick_sostenibile — toglie il parametro morto
-- ------------------------------------------------------------

drop function if exists private.pick_sostenibile(bigint, bigint, bigint, smallint, integer, smallint, smallint);

create function private.pick_sostenibile(
  p_tetto_ingaggi     bigint,
  p_speso             bigint,
  p_slot_rosa         smallint,
  p_giocatori_attuali integer,
  p_overall           smallint,
  p_eta               smallint
)
returns boolean
language sql
immutable parallel safe
set search_path = ''
as $$
  select
    p_tetto_ingaggi - p_speso - private.ingaggio_teorico(p_overall, p_eta)
      >= greatest(0, p_slot_rosa - p_giocatori_attuali - 1) * 500000
$$;

comment on function private.pick_sostenibile(bigint, bigint, smallint, integer, smallint, smallint) is
  'Vero test di sostenibilita'' di una scelta: tetto (in draft, league.budget_draft; altrove tetto_ingaggi) meno speso meno il nuovo ingaggio deve bastare per gli slot restanti al minimo di 500.000. Il parametro budget del vecchio modello a cassa e'' stato rimosso: il corpo non lo usava gia'' piu''.';

revoke all on function private.pick_sostenibile(bigint, bigint, smallint, integer, smallint, smallint) from public, anon, authenticated;
grant execute on function private.pick_sostenibile(bigint, bigint, smallint, integer, smallint, smallint) to service_role;


-- ------------------------------------------------------------
--  2. Draft: toglie la scrittura su teams.budget dalle funzioni di pick
--     e aggiorna le chiamate a pick_sostenibile alla firma nuova.
-- ------------------------------------------------------------

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
    'speso', v_speso,
    'slot_occupati', v_picked,
    'carte', v_carte
  );
end;
$$;

create or replace function private.completa_draft_squadra_pc(p_league_id bigint, p_team_id bigint)
returns void
language plpgsql
security definer
set search_path = ''
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

    select ob.ruolo into v_ruolo
    from private.obiettivi_rosa_pc(p_team_id, v_league.slot_rosa) ob
    left join (
      select private.macro_ruolo(p.posizioni) as ruolo, count(*)::integer as quanti
      from public.player_instances pi
      join public.players p on p.id = pi.player_id
      where pi.league_id = p_league_id and pi.team_id = p_team_id
      group by private.macro_ruolo(p.posizioni)
    ) attuali using (ruolo)
    where coalesce(attuali.quanti, 0) < ob.obiettivo
    order by random()
    limit 1;

    if v_ruolo is null then
      raise exception using errcode = '55000', message = 'Il profilo ruoli PC non copre tutti gli slot della rosa.';
    end if;

    v_speso := private.spesa_draft(v_team.id);
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
        v_league.budget_draft, v_speso, v_league.slot_rosa, v_presi, p.overall, p.eta
      )
    order by p.id
    limit 1;

    if not found then
      select p.* into v_player
      from public.players p
      where p.disponibile_estrazione
        and (p.elite_globale or p.campionato = any(v_league.campionati_attivi))
        and private.macro_ruolo(p.posizioni) = v_ruolo
        and not exists (
          select 1 from public.player_instances pi
          where pi.league_id = p_league_id and pi.player_id = p.id
        )
        and not exists (
          select 1 from public.retired_players rp
          where rp.league_id = p_league_id and rp.player_id = p.id
        )
        and private.pick_sostenibile(
          v_league.budget_draft, v_speso, v_league.slot_rosa, v_presi, p.overall, p.eta
        )
      order by private.ingaggio_teorico(p.overall, p.eta), p.id
      limit 1;
      if not found then
        raise exception using errcode = '55000',
          message = 'Il pool non contiene abbastanza giocatori sostenibili nel reparto richiesto.';
      end if;
    end if;

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

    update public.draft_state set pick_numero = pick_numero + 1, aggiornato_il = now()
    where league_id = p_league_id;
    insert into public.transactions (league_id, team_id, tipo, importo, descrizione, saldo_dopo)
    values (p_league_id, p_team_id, 'draft_pick', -v_ingaggio, 'Ingaggio draft PC: ' || v_player.nome, 0);
  end loop;

  update public.draft_team_state
  set pick_numero = v_league.slot_rosa, stato = 'concluso',
      carta_gk = null, carta_def = null, carta_mid = null, carta_att = null,
      carta_ruolo = null, ruolo_scelto = null, aggiornato_il = now()
  where league_id = p_league_id and team_id = p_team_id;
end;
$$;

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
  v_speso := private.spesa_draft(v_team.id);

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

    select private.pick_sostenibile(v_league.budget_draft, v_speso, v_league.slot_rosa, v_picked, p.overall, p.eta)
      into v_ok_gk from public.players p where p.id = v_gk;
    select private.pick_sostenibile(v_league.budget_draft, v_speso, v_league.slot_rosa, v_picked, p.overall, p.eta)
      into v_ok_def from public.players p where p.id = v_def;
    select private.pick_sostenibile(v_league.budget_draft, v_speso, v_league.slot_rosa, v_picked, p.overall, p.eta)
      into v_ok_mid from public.players p where p.id = v_mid;
    select private.pick_sostenibile(v_league.budget_draft, v_speso, v_league.slot_rosa, v_picked, p.overall, p.eta)
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

create or replace function public.draft_by_role_reroll(p_league_id bigint)
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
  v_vecchio_id bigint;
  v_picked integer;
  v_speso bigint;
begin
  if v_user_id is null then raise exception using errcode = '42501', message = 'Devi accedere prima di usare un reroll.'; end if;
  select * into v_league from public.leagues where id = p_league_id;
  if not found or v_league.modalita_draft <> 'by_role' then
    raise exception using errcode = '55000', message = 'Questa lega non usa il draft BY ROLE.';
  end if;
  perform 1 from public.draft_state where league_id = p_league_id for update;
  select * into v_team from public.teams
  where league_id = p_league_id and user_id = v_user_id and attiva for update;
  if not found then raise exception using errcode = '42501', message = 'Non hai una squadra attiva in questa lega.'; end if;
  select * into v_state from public.draft_team_state
  where team_id = v_team.id and league_id = p_league_id for update;
  if not found or v_state.stato <> 'in_corso' or v_state.carta_ruolo is null then
    raise exception using errcode = '55000', message = 'Devi effettuare uno spin prima del reroll.';
  end if;
  if v_team.reroll_rimasti < 1 then
    raise exception using errcode = '22023', message = 'Non hai reroll disponibili.';
  end if;

  select count(*) into v_picked from public.player_instances
  where league_id = p_league_id and team_id = v_team.id;
  v_speso := private.spesa_draft(v_team.id);
  v_vecchio_id := v_state.carta_ruolo;

  select p.id into v_player_id
  from public.players p
  where p.disponibile_estrazione
    and (p.elite_globale or p.campionato = any(v_league.campionati_attivi))
    and private.macro_ruolo(p.posizioni) = v_state.ruolo_scelto
    and p.id <> v_vecchio_id
    and not exists (
      select 1 from public.player_instances pi
      where pi.league_id = p_league_id and pi.player_id = p.id
    )
    and private.pick_sostenibile(
      v_league.budget_draft, v_speso, v_league.slot_rosa, v_picked, p.overall, p.eta
    )
  order by random()
  limit 1;
  if v_player_id is null then
    raise exception using errcode = '55000', message = 'Non esiste un''altra carta sostenibile per questo ruolo.';
  end if;

  update public.teams set reroll_rimasti = reroll_rimasti - 1 where id = v_team.id;
  update public.draft_team_state set carta_ruolo = v_player_id, aggiornato_il = now()
  where team_id = v_team.id;
  return private.by_role_payload(p_league_id, v_team.id);
end;
$$;

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
  where p.disponibile_estrazione
    and (p.elite_globale or p.campionato = any(v_league.campionati_attivi))
    and private.macro_ruolo(p.posizioni) = v_ruolo
    and not exists (
      select 1 from public.player_instances pi
      where pi.league_id = p_league_id and pi.player_id = p.id
    )
    and private.pick_sostenibile(
      v_league.budget_draft, v_speso, v_league.slot_rosa, v_picked, p.overall, p.eta
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
    'speso', v_speso + v_w1 + v_w2,
    'draft_concluso', v_done
  );
end;
$$;


-- ------------------------------------------------------------
--  3. Creazione lega / ingresso: niente piu' teams.budget ne'
--     transazioni 'dotazione_iniziale' (docs/decisioni-economia.md §1:
--     "Non esistono entrate. Spariscono... dotazione iniziale").
--     leagues.budget_iniziale RESTA: serve ancora a p_budget_draft e ad
--     altri 130+ punti che questo passo non tocca.
-- ------------------------------------------------------------

create or replace function public.crea_lega(p_nome_lega text, p_nome_squadra text, p_stemma_url text, p_n_squadre smallint, p_n_gironi smallint, p_budget_iniziale bigint, p_budget_draft bigint, p_reroll_draft smallint, p_slot_rosa smallint, p_portieri_minimi smallint, p_campionati_attivi text[])
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
    league_id, user_id, nome, stemma_url, reroll_rimasti
  ) values (
    v_league.id, v_user_id, p_nome_squadra, p_stemma_url, v_league.reroll_draft
  ) returning * into v_team;

  insert into public.draft_state (league_id) values (v_league.id);
  insert into public.draft_team_state (team_id, league_id) values (v_team.id, v_league.id);

  return jsonb_build_object(
    'league_id', v_league.id,
    'team_id', v_team.id,
    'codice_invito', v_league.codice_invito
  );
end;
$$;

create or replace function public.crea_lega(p_nome_lega text, p_nome_squadra text, p_stemma_url text, p_n_squadre smallint, p_n_gironi smallint, p_budget_iniziale bigint, p_budget_draft bigint, p_reroll_draft smallint, p_slot_rosa smallint, p_portieri_minimi smallint, p_campionati_attivi text[], p_squadre_pc smallint)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_esito jsonb;
  v_league public.leagues;
  v_team public.teams;
  v_nomi constant text[] := array['Atletico Byte','Real Algoritmo','FC Circuito','Dynamo Pixel','Sporting Vector','Union Bot','AC Neurale','Olympique Dati','Rangers Cloud','Deportivo Codice','FC Sintesi','Stella Automatica','United Runtime','Club Modello','Borgo AI','Virtus Logica','Nova Calcio','Rapid Server','Aurora Machine'];
  v_stemmi constant text[] := array['preset:alci','preset:aliens','preset:aquile','preset:aviator','preset:bigbrain','preset:eagle','preset:generale','preset:leoni','preset:lions','preset:lupo','preset:rocca','preset:skull','preset:torres','preset:wolves','preset:twins','preset:rosa','preset:piramidi','preset:slot','preset:onepiece'];
  i integer;
begin
  if p_squadre_pc not between 0 and p_n_squadre - 1 then
    raise exception using errcode = '22023', message = 'Il numero di squadre PC non e'' valido.';
  end if;

  v_esito := public.crea_lega(p_nome_lega, p_nome_squadra, p_stemma_url,
    p_n_squadre, p_n_gironi, p_budget_iniziale, p_budget_draft,
    p_reroll_draft, p_slot_rosa, p_portieri_minimi, p_campionati_attivi);
  select * into v_league from public.leagues where id = (v_esito->>'league_id')::bigint;

  for i in 1..p_squadre_pc loop
    insert into public.teams (league_id, user_id, controllata_da_pc, nome, stemma_url, reroll_rimasti, ordine_draft)
    values (
      v_league.id, null, true, format('%s PC %s', v_nomi[i], i), v_stemmi[i],
      v_league.reroll_draft, i
    )
    returning * into v_team;
    insert into public.draft_team_state (team_id, league_id) values (v_team.id, v_league.id);
  end loop;
  return v_esito;
end;
$$;

create or replace function public.entra_in_lega(p_codice text, p_nome_squadra text, p_stemma_url text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_league public.leagues;
  v_team public.teams;
  v_partecipanti integer;
  v_ordine integer;
  v_offseason public.offseasons;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'Devi accedere prima di entrare in una lega.';
  end if;

  p_codice := upper(trim(p_codice));
  p_nome_squadra := trim(p_nome_squadra);

  if p_codice !~ '^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{6}$' then
    raise exception using errcode = '22023', message = 'Il codice invito deve contenere 6 caratteri.';
  end if;
  if length(p_nome_squadra) not between 2 and 40 then
    raise exception using errcode = '22023', message = 'Il nome della squadra deve avere da 2 a 40 caratteri.';
  end if;
  if not private.stemma_valido(p_stemma_url, v_user_id) then
    raise exception using errcode = '22023', message = 'Lo stemma selezionato non e'' valido.';
  end if;

  select * into v_league from public.leagues where codice_invito = p_codice for update;
  if not found then raise exception using errcode = 'P0002', message = 'Codice invito non trovato.'; end if;
  if not (v_league.stato in ('setup', 'draft') or (v_league.stato = 'stagione' and v_league.fase_carriera = 'offseason')) then
    raise exception using errcode = '55000', message = 'Questa lega non accetta nuovi partecipanti.';
  end if;
  if exists (select 1 from public.teams where league_id = v_league.id and user_id = v_user_id) then
    raise exception using errcode = '23505', message = 'Hai gia'' una squadra in questa lega.';
  end if;
  if not private.stemma_libero_in_lega(v_league.id, p_stemma_url, null) then
    raise exception using errcode = '23505', message = 'Questo stemma e'' gia'' usato nella lega.';
  end if;

  select count(*) into v_partecipanti from public.teams where league_id = v_league.id and attiva;
  if v_partecipanti >= v_league.n_squadre then
    raise exception using errcode = '54000', message = 'La lega ha gia'' raggiunto il numero massimo di squadre.';
  end if;
  select coalesce(max(ordine_draft), -1) + 1 into v_ordine
  from public.teams where league_id = v_league.id;

  begin
    insert into public.teams(
      league_id, user_id, nome, stemma_url, reroll_rimasti,
      ordine_draft, attiva, entrata_stagione
    ) values (
      v_league.id, v_user_id, p_nome_squadra, p_stemma_url,
      v_league.reroll_draft, v_ordine, true,
      case when v_league.fase_carriera = 'offseason' then v_league.stagione_corrente + 1 else 1 end
    ) returning * into v_team;
  exception when unique_violation then
    raise exception using errcode = '23505', message = 'Questo nome squadra e'' gia'' usato nella lega.';
  end;

  if v_league.fase_carriera = 'offseason' then
    select * into v_offseason from public.offseasons
    where league_id = v_league.id and stato = 'aperta' order by stagione_a desc limit 1;
    if not found or now() >= v_offseason.scade_il then
      raise exception using errcode = '55000', message = 'La finestra d''ingresso e'' terminata.';
    end if;
    insert into public.draft_team_state(team_id, league_id) values (v_team.id, v_league.id);
    insert into public.draft_state(league_id, pick_numero, stato)
    values (v_league.id,
      coalesce((select max(dp.pick_numero) + 1 from public.draft_picks dp where dp.league_id = v_league.id), 0),
      'in_corso')
    on conflict (league_id) do update set stato = 'in_corso', aggiornato_il = now();
    perform private.notifica(v_league.admin_id, v_league.id, 'sistema', 'Nuova squadra iscritta',
      v_team.nome || ' e'' entrata e puo'' iniziare il draft.', jsonb_build_object('team_id', v_team.id));
  elsif v_league.stato = 'draft' then
    insert into public.draft_team_state(team_id, league_id) values (v_team.id, v_league.id);
  end if;

  return jsonb_build_object('league_id', v_league.id, 'team_id', v_team.id,
    'codice_invito', v_league.codice_invito, 'offseason', v_league.fase_carriera = 'offseason');
end;
$$;


-- ------------------------------------------------------------
--  4. Scambi: saldo_dopo non ha piu' un budget da leggere. Il vincolo
--     tabellare (saldo_dopo >= 0, not null) resta: si scrive 0, un
--     segnaposto onesto per un campo che non significa piu' "cassa dopo
--     il movimento" per queste righe (registrano spazio salariale, non
--     denaro — docs/decisioni-economia.md §4, "Il registro transactions
--     resta... cambia solo cosa registra").
-- ------------------------------------------------------------

create or replace function public.rispondi_a_proposta(p_proposta_id bigint, p_accetta boolean)
returns trade_proposals
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_utente     uuid := (select auth.uid());
  v_p          public.trade_proposals;
  v_lega       public.leagues;
  v_da         public.teams;
  v_a          public.teams;
  v_stagione   smallint;
  v_n          integer;
  v_rosa_da    integer;
  v_rosa_a     integer;
  v_prossima   integer;
  v_tutti      bigint[];
  v_form_tolte integer := 0;
  v_nota       text := '';
  v_delta_da   bigint;
  v_delta_a    bigint;
begin
  if v_utente is null then
    raise exception using errcode = '42501', message = 'Devi accedere per usare il mercato.';
  end if;

  select * into v_p from public.trade_proposals where id = p_proposta_id for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Proposta inesistente.';
  end if;
  if not (select private.e_mia_squadra(v_p.a_team_id)) then
    raise exception using errcode = '42501', message = 'Questa proposta non e'' indirizzata a te.';
  end if;
  if v_p.stato <> 'in_attesa' then
    raise exception using errcode = '55000', message = 'Questa proposta e'' gia'' stata risolta.';
  end if;
  if now() >= v_p.scade_il then
    raise exception using errcode = '55000', message = 'Questa proposta e'' scaduta.';
  end if;

  if not coalesce(p_accetta, false) then
    update public.trade_proposals set stato = 'rifiutata', risolta_il = now()
    where id = v_p.id
    returning * into v_p;

    perform private.notifica(
      (select user_id from public.teams where id = v_p.da_team_id),
      v_p.league_id, 'mercato_esito', 'Proposta rifiutata',
      (select nome from public.teams where id = v_p.a_team_id) || ' ha rifiutato la tua proposta.',
      jsonb_build_object('proposta_id', v_p.id)
    );
    return v_p;
  end if;

  if not private.mercato_aperto_lega(v_p.league_id) then
    raise exception using errcode = '55000',
      message = 'Il mercato e'' chiuso: si conclude dalle 23:30 alle 21:00, o quando l''admin lo apre.';
  end if;

  select * into v_lega from public.leagues where id = v_p.league_id;

  perform 1 from public.teams where id in (v_p.da_team_id, v_p.a_team_id) order by id for update;
  select * into v_da from public.teams where id = v_p.da_team_id;
  select * into v_a  from public.teams where id = v_p.a_team_id;

  select count(*) into v_n from public.player_instances
  where id = any(v_p.giocatori_offerti) and team_id = v_da.id;
  if v_n <> cardinality(v_p.giocatori_offerti) then
    raise exception using errcode = '55000',
      message = 'Un giocatore offerto non e'' piu'' in quella rosa: la proposta non e'' piu'' valida.';
  end if;
  select count(*) into v_n from public.player_instances
  where id = any(v_p.giocatori_richiesti) and team_id = v_a.id;
  if v_n <> cardinality(v_p.giocatori_richiesti) then
    raise exception using errcode = '55000',
      message = 'Un giocatore richiesto non e'' piu'' nella tua rosa: la proposta non e'' piu'' valida.';
  end if;
  if exists (
    select 1 from public.player_instances
    where id = any(v_p.giocatori_offerti || v_p.giocatori_richiesti) and ritiro_annunciato
  ) then
    raise exception using errcode = '55000',
      message = 'Uno dei giocatori coinvolti ha annunciato il ritiro: la proposta non e'' piu'' valida.';
  end if;

  select count(*) into v_n from public.scelte_draft
  where id = any(v_p.scelte_offerte) and team_proprietario_id = v_da.id and stato in ('futura', 'determinata');
  if v_n <> cardinality(v_p.scelte_offerte) then
    raise exception using errcode = '55000',
      message = 'Una scelta offerta non e'' piu'' disponibile: la proposta non e'' piu'' valida.';
  end if;
  select count(*) into v_n from public.scelte_draft
  where id = any(v_p.scelte_richieste) and team_proprietario_id = v_a.id and stato in ('futura', 'determinata');
  if v_n <> cardinality(v_p.scelte_richieste) then
    raise exception using errcode = '55000',
      message = 'Una scelta richiesta non e'' piu'' disponibile: la proposta non e'' piu'' valida.';
  end if;

  if cardinality(v_p.scelte_offerte) > 0 and private.viola_regola_stepien(v_da.id, v_p.scelte_offerte) then
    raise exception using errcode = '22023',
      message = 'Questo scambio lascerebbe ' || v_da.nome || ' senza una propria scelta d''origine per due stagioni consecutive nella stessa finestra (regola Stepien): la proposta non e'' piu'' valida.';
  end if;
  if cardinality(v_p.scelte_richieste) > 0 and private.viola_regola_stepien(v_a.id, v_p.scelte_richieste) then
    raise exception using errcode = '22023',
      message = 'Questo scambio ti lascerebbe senza una tua scelta d''origine per due stagioni consecutive nella stessa finestra (regola Stepien).';
  end if;

  select count(*) into v_rosa_da from public.player_instances where team_id = v_da.id;
  select count(*) into v_rosa_a  from public.player_instances where team_id = v_a.id;
  v_rosa_da := v_rosa_da - cardinality(v_p.giocatori_offerti) + cardinality(v_p.giocatori_richiesti);
  v_rosa_a  := v_rosa_a  - cardinality(v_p.giocatori_richiesti) + cardinality(v_p.giocatori_offerti);
  if v_rosa_da > private.rosa_massima() or v_rosa_a > private.rosa_massima() then
    raise exception using errcode = '22023', message = 'Lo scambio porterebbe una rosa oltre i 30 giocatori.';
  end if;
  if v_rosa_da < private.rosa_minima() or v_rosa_a < private.rosa_minima() then
    raise exception using errcode = '22023', message = 'Lo scambio lascerebbe una rosa sotto i 21 giocatori.';
  end if;

  select min(f.giornata) into v_prossima
  from public.fixtures f where f.league_id = v_lega.id and f.stato = 'programmata';

  update public.player_instances set team_id = v_a.id,  giornata_acquisizione = v_prossima where id = any(v_p.giocatori_offerti);
  update public.player_instances set team_id = v_da.id, giornata_acquisizione = v_prossima where id = any(v_p.giocatori_richiesti);
  update public.scelte_draft set team_proprietario_id = v_a.id,  aggiornata_il = now() where id = any(v_p.scelte_offerte);
  update public.scelte_draft set team_proprietario_id = v_da.id, aggiornata_il = now() where id = any(v_p.scelte_richieste);

  v_stagione := private.stagione_contratto(v_p.league_id);
  if private.monte_ingaggi(v_da.id, v_stagione) + private.ingaggi_impegnati_aste(v_da.id, null) > v_lega.tetto_ingaggi then
    raise exception using errcode = '22023',
      message = 'Questo scambio porterebbe ' || v_da.nome || ' oltre il tetto ingaggi.';
  end if;
  if private.monte_ingaggi(v_a.id, v_stagione) + private.ingaggi_impegnati_aste(v_a.id, null) > v_lega.tetto_ingaggi then
    raise exception using errcode = '22023',
      message = 'Questo scambio ti porterebbe oltre il tetto ingaggi.';
  end if;

  v_tutti := v_p.giocatori_offerti || v_p.giocatori_richiesti;
  if v_prossima is not null and cardinality(v_tutti) > 0 then
    delete from public.lineups
    where league_id = v_lega.id
      and team_id in (v_da.id, v_a.id)
      and giornata >= v_prossima
      and (titolari && v_tutti or panchina && v_tutti or tribuna && v_tutti);
    get diagnostics v_form_tolte = row_count;
  end if;
  if v_form_tolte > 0 then
    v_nota := ' Controlla la formazione: era schierato un giocatore coinvolto.';
  end if;

  select coalesce(sum(ingaggio), 0) into v_delta_da
  from public.player_instances where id = any(v_p.giocatori_richiesti);
  v_delta_da := v_delta_da - coalesce((select sum(ingaggio) from public.player_instances where id = any(v_p.giocatori_offerti)), 0);
  v_delta_a := -v_delta_da;

  if v_delta_da <> 0 then
    insert into public.transactions (league_id, team_id, tipo, importo, descrizione, saldo_dopo)
    values (v_lega.id, v_da.id, 'mercato_scambio', v_delta_da, 'Scambio con ' || v_a.nome, 0);
  end if;
  if v_delta_a <> 0 then
    insert into public.transactions (league_id, team_id, tipo, importo, descrizione, saldo_dopo)
    values (v_lega.id, v_a.id, 'mercato_scambio', v_delta_a, 'Scambio con ' || v_da.nome, 0);
  end if;

  update public.trade_proposals set stato = 'accettata', risolta_il = now()
  where id = v_p.id
  returning * into v_p;

  perform private.notifica(v_da.user_id, v_lega.id, 'mercato_esito', 'Scambio concluso con ' || v_a.nome,
    'La tua proposta e'' stata accettata.' || v_nota, jsonb_build_object('proposta_id', v_p.id));
  perform private.notifica(v_a.user_id, v_lega.id, 'mercato_esito', 'Scambio concluso con ' || v_da.nome,
    'Hai accettato la proposta.' || v_nota, jsonb_build_object('proposta_id', v_p.id));

  return v_p;
end;
$$;

create or replace function private.rispondi_a_proposta_pc(p_proposta_id bigint)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_p public.trade_proposals;
  v_lega public.leagues;
  v_da public.teams;
  v_a public.teams;
  v_valore_offerto bigint;
  v_valore_richiesto bigint;
  v_rosa_da integer;
  v_rosa_a integer;
  v_stagione smallint;
  v_ing_verso_a bigint;
  v_ing_verso_da bigint;
  v_delta_a bigint;
  v_delta_da bigint;
begin
  select * into v_p from public.trade_proposals where id = p_proposta_id for update;
  if not found or v_p.stato <> 'in_attesa' then return; end if;
  select * into v_lega from public.leagues where id = v_p.league_id;
  select * into v_da from public.teams where id = v_p.da_team_id for update;
  select * into v_a from public.teams where id = v_p.a_team_id and controllata_da_pc for update;
  if not found then return; end if;

  if cardinality(v_p.scelte_richieste) > 0 then
    update public.trade_proposals set stato = 'rifiutata', risolta_il = now() where id = v_p.id;
    perform private.notifica(v_da.user_id, v_p.league_id, 'mercato_esito', 'Proposta rifiutata',
      v_a.nome || ' non tratta le proprie scelte di draft.', jsonb_build_object('proposta_id', v_p.id));
    return;
  end if;

  if (select count(*) from public.player_instances where id = any(v_p.giocatori_offerti) and team_id = v_da.id) <> cardinality(v_p.giocatori_offerti)
     or (select count(*) from public.player_instances where id = any(v_p.giocatori_richiesti) and team_id = v_a.id) <> cardinality(v_p.giocatori_richiesti)
     or (select count(*) from public.scelte_draft where id = any(v_p.scelte_offerte) and team_proprietario_id = v_da.id and stato in ('futura','determinata')) <> cardinality(v_p.scelte_offerte)
  then
    update public.trade_proposals set stato = 'rifiutata', risolta_il = now() where id = v_p.id;
    return;
  end if;

  select coalesce(sum(private.valore_mercato_pc(pi.overall_corrente, pi.ingaggio)), 0)::bigint
    into v_valore_offerto from public.player_instances pi where pi.id = any(v_p.giocatori_offerti);
  select coalesce(sum(private.valore_mercato_pc(pi.overall_corrente, pi.ingaggio)), 0)::bigint
    into v_valore_richiesto from public.player_instances pi where pi.id = any(v_p.giocatori_richiesti);

  if v_valore_offerto < round(v_valore_richiesto * (0.94 + random() * 0.12)) then
    update public.trade_proposals set stato = 'rifiutata', risolta_il = now() where id = v_p.id;
    perform private.notifica(v_da.user_id, v_p.league_id, 'mercato_esito', 'Proposta rifiutata',
      v_a.nome || ' ha rifiutato la tua proposta.', jsonb_build_object('proposta_id', v_p.id));
    return;
  end if;

  select count(*) into v_rosa_da from public.player_instances where team_id = v_da.id;
  select count(*) into v_rosa_a from public.player_instances where team_id = v_a.id;
  v_rosa_da := v_rosa_da - cardinality(v_p.giocatori_offerti) + cardinality(v_p.giocatori_richiesti);
  v_rosa_a := v_rosa_a - cardinality(v_p.giocatori_richiesti) + cardinality(v_p.giocatori_offerti);
  if v_rosa_da not between private.rosa_minima() and private.rosa_massima()
     or v_rosa_a not between private.rosa_minima() and private.rosa_massima() then
    update public.trade_proposals set stato = 'rifiutata', risolta_il = now() where id = v_p.id;
    return;
  end if;

  v_stagione := private.stagione_contratto(v_p.league_id);
  select coalesce(sum(ingaggio), 0) into v_ing_verso_a from public.player_instances where id = any(v_p.giocatori_offerti);
  select coalesce(sum(ingaggio), 0) into v_ing_verso_da from public.player_instances where id = any(v_p.giocatori_richiesti);
  v_delta_a := v_ing_verso_a - v_ing_verso_da;
  v_delta_da := v_ing_verso_da - v_ing_verso_a;

  if v_delta_a > 0 and private.capienza_residua(v_a.id, v_stagione) < v_delta_a then
    update public.trade_proposals set stato = 'rifiutata', risolta_il = now() where id = v_p.id;
    return;
  end if;
  if v_da.controllata_da_pc and v_delta_da > 0 and private.capienza_residua(v_da.id, v_stagione) < v_delta_da then
    update public.trade_proposals set stato = 'rifiutata', risolta_il = now() where id = v_p.id;
    return;
  end if;

  update public.player_instances set team_id = v_a.id where id = any(v_p.giocatori_offerti);
  update public.player_instances set team_id = v_da.id where id = any(v_p.giocatori_richiesti);
  update public.scelte_draft set team_proprietario_id = v_a.id, aggiornata_il = now() where id = any(v_p.scelte_offerte);
  delete from public.lineups where league_id = v_p.league_id and team_id in (v_da.id, v_a.id);

  if v_delta_da <> 0 then
    insert into public.transactions(league_id, team_id, tipo, importo, descrizione, saldo_dopo)
    values (v_p.league_id, v_da.id, 'mercato_scambio', v_delta_da, 'Scambio con ' || v_a.nome, 0);
  end if;
  if v_delta_a <> 0 then
    insert into public.transactions(league_id, team_id, tipo, importo, descrizione, saldo_dopo)
    values (v_p.league_id, v_a.id, 'mercato_scambio', v_delta_a, 'Scambio con ' || v_da.nome, 0);
  end if;

  update public.trade_proposals set stato = 'accettata', risolta_il = now() where id = v_p.id;
  perform private.notifica(v_da.user_id, v_p.league_id, 'mercato_esito', 'Proposta accettata',
    v_a.nome || ' ha accettato la tua proposta.', jsonb_build_object('proposta_id', v_p.id));
end;
$$;

create or replace function public.offri_rinnovo(p_instance_id bigint, p_ingaggio bigint, p_durata smallint)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_inst public.player_instances;
  v_league public.leagues;
  v_team public.teams;
  v_player public.players;
  v_proposta record;
  v_posizione smallint;
  v_tolleranza numeric;
  v_soglia numeric;
  v_valore numeric;
  v_rapporto numeric;
  v_scadenza smallint;
  v_tentativi smallint;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'Devi accedere prima di trattare un rinnovo.';
  end if;
  if p_ingaggio < 500000 then
    raise exception using errcode = '22023', message = 'L''ingaggio minimo è 0,5 M€.';
  end if;
  if p_durata <> 1 then
    raise exception using errcode = '22023',
      message = 'I contratti durano una stagione: il rinnovo estende di un anno.';
  end if;

  select * into v_inst from public.player_instances where id = p_instance_id for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Giocatore non trovato.';
  end if;

  select * into v_team from public.teams
  where id = v_inst.team_id and league_id = v_inst.league_id and user_id = v_user_id and attiva;
  if not found then
    raise exception using errcode = '42501', message = 'Questo giocatore non è nella tua rosa.';
  end if;

  select * into v_league from public.leagues where id = v_inst.league_id;
  if v_league.stato <> 'stagione' then
    raise exception using errcode = '55000', message = 'I rinnovi si trattano solo a stagione avviata.';
  end if;
  if v_inst.ritirato or v_inst.ritiro_annunciato then
    raise exception using errcode = '55000', message = 'Ha già annunciato il ritiro: non rinnoverà il contratto.';
  end if;
  if v_inst.rinnovo_stagione is not null and v_inst.rinnovo_stagione = v_league.stagione_corrente then
    raise exception using errcode = '55000',
      message = 'Ha già rinnovato in questa stagione: se ne riparla dalla prossima.';
  end if;
  if v_inst.rinnovo_tentativi >= 3 then
    raise exception using errcode = '55000',
      message = 'Ha chiuso la trattativa: andrà a scadenza e lascerà la squadra.';
  end if;

  select * into v_player from public.players where id = v_inst.player_id;
  select * into v_proposta
  from private.rinnovo_proposta(
    v_inst.id, v_inst.overall_corrente, v_inst.eta_corrente, v_inst.ingaggio,
    v_player.mentalita_bandiera, v_player.mentalita_economia
  );

  select coalesce(st.posizione, 1) into v_posizione
  from public.seasons se
  join public.standings st on st.season_id = se.id and st.team_id = v_inst.team_id
  where se.league_id = v_inst.league_id and se.numero = v_league.stagione_corrente;

  v_tolleranza := private.rinnovo_tolleranza(
    v_inst.morale, v_player.mentalita_bandiera, v_player.mentalita_economia,
    v_player.mentalita_vittorie, coalesce(v_posizione, 1::smallint), v_league.n_squadre::smallint
  );
  v_soglia := v_proposta.richiesta * (1 - v_tolleranza);

  v_valore := p_ingaggio;
  v_rapporto := v_valore / greatest(1, v_soglia);

  if v_rapporto >= 1 then
    perform private.verifica_capienza(
      v_team.id,
      p_ingaggio - case
        when v_inst.contratto_scadenza > v_league.stagione_corrente then v_inst.ingaggio
        else 0 end,
      (v_league.stagione_corrente + 1)::smallint
    );

    v_scadenza := greatest(v_inst.contratto_scadenza, (v_league.stagione_corrente + 1)::smallint);
    update public.player_instances
    set ingaggio = p_ingaggio,
        contratto_scadenza = v_scadenza,
        rinnovo_tentativi = 0,
        rinnovo_stagione = v_league.stagione_corrente
    where id = v_inst.id;

    insert into public.transactions (league_id, team_id, tipo, importo, descrizione, saldo_dopo)
    values (
      v_inst.league_id, v_team.id, 'rinnovo_in_stagione',
      greatest(1, p_ingaggio - v_inst.ingaggio),
      'Rinnovo: ' || coalesce(v_player.nome, 'giocatore') || ' — '
        || round(p_ingaggio / 1000000.0, 1) || ' M€ fino alla stagione ' || v_scadenza,
      0
    );

    return jsonb_build_object(
      'esito', 'accettato',
      'ingaggio', p_ingaggio,
      'durata', 1,
      'contratto_scadenza', v_scadenza,
      'tentativi_usati', 0,
      'messaggio', 'Ci sto, mister. Grazie della fiducia.'
    );
  end if;

  v_tentativi := (v_inst.rinnovo_tentativi + 1)::smallint;
  update public.player_instances set rinnovo_tentativi = v_tentativi where id = v_inst.id;

  return jsonb_build_object(
    'esito', case when v_tentativi >= 3 then 'chiusa' else 'rifiutato' end,
    'tentativi_usati', v_tentativi,
    'tentativi_totali', 3,
    'messaggio', case
      when v_tentativi >= 3 then 'Basta così, mister. Andrò a scadenza.'
      when v_rapporto >= 0.95 then 'Ci siamo quasi, ma non ancora.'
      when v_rapporto >= 0.85 then 'È troppo poco per quello che valgo.'
      else 'Non se ne parla nemmeno, mister.'
    end
  );
end;
$$;


-- ------------------------------------------------------------
--  5. stato_offseason: toglie 'budget' dal payload per squadra.
-- ------------------------------------------------------------

create or replace function public.stato_offseason(p_league_id bigint)
returns jsonb
language plpgsql
stable security definer
set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
  v_lega public.leagues;
  v_offseason public.offseasons;
  v_squadre jsonb;
begin
  if v_user is null or not (select private.e_membro(p_league_id)) then
    raise exception using errcode = '42501', message = 'Non fai parte di questa lega.';
  end if;
  select * into v_lega from public.leagues where id = p_league_id;
  select * into v_offseason from public.offseasons
  where league_id = p_league_id and stato = 'aperta'
  order by stagione_a desc limit 1;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', t.id, 'nome', t.nome, 'attiva', t.attiva,
    'entrante', t.entrata_stagione = coalesce(v_offseason.stagione_a, v_lega.stagione_corrente + 1),
    'rosa', (select count(*) from public.player_instances pi where pi.team_id = t.id and not pi.ritirato),
    'rinnovi_in_attesa', (select count(*) from public.contract_renewals cr where cr.offseason_id = v_offseason.id and cr.team_id = t.id and cr.stato = 'in_attesa'),
    'draft', (select dts.stato from public.draft_team_state dts where dts.team_id = t.id)
  ) order by t.attiva desc, t.nome), '[]'::jsonb)
  into v_squadre
  from public.teams t where t.league_id = p_league_id;

  return jsonb_build_object(
    'fase', v_lega.fase_carriera,
    'stagione_corrente', v_lega.stagione_corrente,
    'stagione_prossima', coalesce(v_offseason.stagione_a, v_lega.stagione_corrente + 1),
    'scade_il', v_offseason.scade_il,
    'posti_nuovi', coalesce(v_offseason.posti_nuovi, 0),
    'squadre_attese', v_lega.n_squadre,
    'squadre', v_squadre
  );
end;
$$;


-- ------------------------------------------------------------
--  6. prepara_offseason: tolto l'accredito sponsor/premi/partecipazione.
--     "Vincere non da' nulla di economico" (docs/decisioni-economia.md
--     §1) — il resto della funzione (rimozione squadre, ritiri, apertura
--     finestra) e' invariato.
-- ------------------------------------------------------------

create or replace function public.prepara_offseason(p_league_id bigint, p_squadre_rimosse bigint[] default '{}'::bigint[], p_posti_nuovi smallint default 0)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
  v_lega public.leagues;
  v_offseason public.offseasons;
  v_attive integer;
  v_rimosse integer;
  v_target integer;
  v_player record;
  v_ritirati integer := 0;
begin
  if v_user is null then
    raise exception using errcode = '42501', message = 'Devi accedere per aprire l''off-season.';
  end if;

  select * into v_lega from public.leagues where id = p_league_id for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Lega non trovata.';
  end if;
  if v_lega.admin_id <> v_user then
    raise exception using errcode = '42501', message = 'Solo l''admin può aprire l''off-season.';
  end if;
  if v_lega.stato <> 'conclusa' or v_lega.fase_carriera <> 'normale' then
    raise exception using errcode = '55000', message = 'L''off-season è disponibile soltanto dopo una stagione conclusa.';
  end if;
  if coalesce(p_posti_nuovi, 0) not between 0 and 16 then
    raise exception using errcode = '22023', message = 'Numero di nuovi posti non valido.';
  end if;
  if cardinality(coalesce(p_squadre_rimosse, '{}'::bigint[])) <>
     (select count(distinct id) from unnest(coalesce(p_squadre_rimosse, '{}'::bigint[])) x(id)) then
    raise exception using errcode = '22023', message = 'La lista delle squadre rimosse contiene duplicati.';
  end if;
  if exists (
    select 1 from unnest(coalesce(p_squadre_rimosse, '{}'::bigint[])) x(id)
    left join public.teams t on t.id = x.id and t.league_id = p_league_id and t.attiva
    where t.id is null
  ) then
    raise exception using errcode = '22023', message = 'Una squadra da rimuovere non appartiene alla lega o è già inattiva.';
  end if;
  if exists (
    select 1 from public.teams
    where id = any(coalesce(p_squadre_rimosse, '{}'::bigint[])) and user_id = v_lega.admin_id
  ) then
    raise exception using errcode = '22023', message = 'L''admin non può rimuovere la propria squadra.';
  end if;

  select count(*) into v_attive from public.teams where league_id = p_league_id and attiva;
  v_rimosse := cardinality(coalesce(p_squadre_rimosse, '{}'::bigint[]));
  v_target := v_attive - v_rimosse + coalesce(p_posti_nuovi, 0);
  if v_target not between 4 and 20 then
    raise exception using errcode = '22023', message = 'La prossima stagione deve avere da 4 a 20 squadre.';
  end if;

  insert into public.offseasons (league_id, stagione_da, stagione_a, scade_il, posti_nuovi)
  values (p_league_id, v_lega.stagione_corrente, v_lega.stagione_corrente + 1,
          ((now() at time zone 'Europe/Rome') + interval '7 days') at time zone 'Europe/Rome',
          coalesce(p_posti_nuovi, 0))
  returning * into v_offseason;

  if v_rimosse > 0 then
    update public.trade_proposals
    set stato = 'scaduta', risolta_il = now()
    where league_id = p_league_id and stato = 'in_attesa'
      and (da_team_id = any(p_squadre_rimosse) or a_team_id = any(p_squadre_rimosse));

    update public.player_instances
    set team_id = null
    where league_id = p_league_id and team_id = any(p_squadre_rimosse);

    delete from public.scelte_draft
    where league_id = p_league_id
      and team_origine_id = any(p_squadre_rimosse)
      and stato = 'futura';

    update public.teams
    set attiva = false, uscita_stagione = v_lega.stagione_corrente
    where league_id = p_league_id and id = any(p_squadre_rimosse);
  end if;

  for v_player in
    select pi.id, pi.player_id, p.nome, t.user_id
    from public.player_instances pi
    join public.players p on p.id = pi.player_id
    join public.teams t on t.id = pi.team_id and t.attiva
    where pi.league_id = p_league_id and pi.ritiro_annunciato and not pi.ritirato
  loop
    update public.player_instances
    set team_id = null, ritirato = true, ritiro_annunciato = false
    where id = v_player.id;
    insert into public.retired_players(league_id, player_id, stagione)
    values (p_league_id, v_player.player_id, v_lega.stagione_corrente)
    on conflict do nothing;
    v_ritirati := v_ritirati + 1;
    perform private.notifica(v_player.user_id, p_league_id, 'sistema',
      v_player.nome || ' si ritira',
      'Il ritiro annunciato a inizio stagione e'' ora effettivo: la carriera termina qui.',
      jsonb_build_object('player_instance_id', v_player.id));
  end loop;

  for v_player in
    select pi.id, pi.eta_corrente
    from public.player_instances pi
    join public.teams t on t.id = pi.team_id and t.attiva
    where pi.league_id = p_league_id and not pi.ritirato
    order by pi.id
    for update of pi
  loop
    update public.player_instances
    set eta_corrente = least(45, v_player.eta_corrente + 1),
        condizione = 100,
        infortunato_fino_a = 0,
        progressione_residuo = 0
    where id = v_player.id;
  end loop;

  update public.leagues
  set n_squadre = v_target,
      stato = 'stagione',
      fase_carriera = 'offseason',
      offseason_fine = v_offseason.scade_il
  where id = p_league_id;

  return jsonb_build_object(
    'league_id', p_league_id,
    'offseason_id', v_offseason.id,
    'stagione_a', v_offseason.stagione_a,
    'scade_il', v_offseason.scade_il,
    'squadre_attese', v_target,
    'posti_nuovi', p_posti_nuovi,
    'ritirati', v_ritirati
  );
end;
$$;


-- ------------------------------------------------------------
--  7. finalizza_offseason: l'insolvenza e il completamento rosa a 21 ora
--     confrontano il tetto ingaggi, non piu' teams.budget. Tolto anche
--     l'addebito cassa finale ('ingaggi_stagione'): occupare spazio
--     salariale non e' una spesa (docs/decisioni-economia.md §1).
-- ------------------------------------------------------------

create or replace function private.finalizza_offseason(p_league_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_league public.leagues;
  v_off public.offseasons;
  v_team record;
  v_candidate record;
  v_player record;
  v_rosa integer;
  v_ingaggi bigint;
  v_da_aggiungere integer;
  v_wage bigint;
  v_season bigint;
  v_aggiunti text[];
  v_rilasciati integer;
  v_attive integer;
begin
  select * into v_league from public.leagues where id = p_league_id for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Lega non trovata.';
  end if;
  if v_league.fase_carriera <> 'offseason' then
    raise exception using errcode = '55000', message = 'L''off-season non e'' attiva.';
  end if;

  select * into v_off
  from public.offseasons
  where league_id = p_league_id and stato = 'aperta'
  order by stagione_a desc limit 1
  for update;
  if not found then
    raise exception using errcode = '55000', message = 'Off-season aperta non trovata.';
  end if;
  if clock_timestamp() < v_off.scade_il then
    raise exception using errcode = '55000',
      message = 'L''off-season dura 24 ore e non puo'' essere chiusa prima della scadenza.';
  end if;

  if exists (
    select 1 from public.finestre_scelte
    where league_id = p_league_id and stagione = v_off.stagione_a and finestra = 'off'
      and risolta_il is null
  ) then
    begin
      perform private.risolvi_finestra_scelte(p_league_id, v_off.stagione_a, 'off', true);
    exception when others then
      raise warning 'mercato a scelte: risoluzione OFF-Season fallita per lega % stagione %: % (%)',
        p_league_id, v_off.stagione_a, sqlerrm, sqlstate;
    end;
  end if;

  select count(*)::integer into v_attive
  from public.teams where league_id = p_league_id and attiva;
  if v_attive < 4 then
    raise exception using errcode = '55000', message = 'Servono almeno 4 squadre attive per iniziare la stagione.';
  end if;

  update public.leagues set n_squadre = v_attive where id = p_league_id;

  update public.player_instances
  set team_id = null
  where league_id = p_league_id
    and team_id is not null
    and not ritirato
    and contratto_scadenza <= v_league.stagione_corrente;

  for v_team in
    select * from public.teams
    where league_id = p_league_id and attiva
    order by id for update
  loop
    v_aggiunti := array[]::text[];
    v_rilasciati := 0;

    -- Se la rosa attuale non e' sostenibile sotto il tetto, si applica
    -- l'insolvenza del design: escono prima gli ingaggi piu' alti finche'
    -- restano finanziabili anche i posti mancanti al minimo di 21. Sotto
    -- il tetto questo non dovrebbe piu' accadere per una rosa costruita
    -- interamente dopo la migrazione (ogni acquisizione verifica gia' la
    -- capienza), ma resta il paracadute per le rose ereditate dal vecchio
    -- modello a cassa (v. private.capienza_residua).
    loop
      select count(*)::integer, coalesce(sum(ingaggio), 0)::bigint
      into v_rosa, v_ingaggi
      from public.player_instances
      where team_id = v_team.id and not ritirato;

      exit when v_ingaggi + greatest(21 - v_rosa, 0) * 500000 <= v_league.tetto_ingaggi;

      select pi.id into v_candidate
      from public.player_instances pi
      where pi.team_id = v_team.id and not pi.ritirato
      order by pi.ingaggio desc, pi.overall_corrente asc, pi.id
      limit 1;
      if not found then
        raise exception using errcode = '55000', message = 'Tetto ingaggi insufficiente per completare la rosa di ' || v_team.nome || '.';
      end if;
      update public.player_instances set team_id = null where id = v_candidate.id;
      v_rilasciati := v_rilasciati + 1;
    end loop;

    select count(*)::integer, coalesce(sum(ingaggio), 0)::bigint
    into v_rosa, v_ingaggi
    from public.player_instances
    where team_id = v_team.id and not ritirato;
    v_da_aggiungere := greatest(21 - v_rosa, 0);

    while v_da_aggiungere > 0 loop
      select p.id as player_id, p.nome, p.overall, p.eta,
             pi.id as instance_id,
             coalesce(pi.ingaggio, private.ingaggio_teorico(p.overall, p.eta))::bigint as ingaggio
      into v_candidate
      from public.players p
      left join public.player_instances pi
        on pi.league_id = p_league_id and pi.player_id = p.id
      where p.campionato = any(v_league.campionati_attivi)
        and (pi.id is null or (pi.team_id is null and not pi.ritirato))
        and not exists (select 1 from public.retired_players rp where rp.league_id = p_league_id and rp.player_id = p.id)
        and coalesce(pi.ingaggio, private.ingaggio_teorico(p.overall, p.eta))
          <= v_league.tetto_ingaggi - v_ingaggi - ((v_da_aggiungere - 1) * 500000)
      order by coalesce(pi.ingaggio, private.ingaggio_teorico(p.overall, p.eta)) asc,
               p.overall asc, p.id
      limit 1;

      if not found then
        raise exception using errcode = '55000', message = 'Non ci sono svincolati sostenibili per completare la rosa di ' || v_team.nome || '.';
      end if;

      v_wage := greatest(500000, v_candidate.ingaggio);
      if v_candidate.instance_id is null then
        insert into public.player_instances(
          league_id, player_id, team_id, overall_corrente, eta_corrente, ingaggio,
          condizione, infortunato_fino_a, contratto_scadenza
        ) values (
          p_league_id, v_candidate.player_id, v_team.id, v_candidate.overall,
          v_candidate.eta, v_wage, 100, 0, v_off.stagione_a
        );
      else
        update public.player_instances
        set team_id = v_team.id,
            ingaggio = v_wage,
            contratto_scadenza = v_off.stagione_a,
            condizione = 100,
            infortunato_fino_a = 0
        where id = v_candidate.instance_id and team_id is null;
      end if;

      v_ingaggi := v_ingaggi + v_wage;
      v_da_aggiungere := v_da_aggiungere - 1;
      v_aggiunti := array_append(v_aggiunti, v_candidate.nome);
    end loop;

    select count(*)::integer, coalesce(sum(ingaggio), 0)::bigint
    into v_rosa, v_ingaggi
    from public.player_instances
    where team_id = v_team.id and not ritirato;

    if v_rosa not between 21 and 30 then
      raise exception using errcode = '55000', message = 'La rosa di ' || v_team.nome || ' non rispetta il limite 21-30.';
    end if;
    if v_league.tetto_ingaggi < v_ingaggi then
      raise exception using errcode = '55000', message = 'Tetto ingaggi insufficiente per gli ingaggi di ' || v_team.nome || '.';
    end if;

    update public.draft_team_state
    set stato = 'concluso', aggiornato_il = clock_timestamp()
    where league_id = p_league_id and team_id = v_team.id and stato <> 'concluso';

    if cardinality(v_aggiunti) > 0 or v_rilasciati > 0 then
      perform private.notifica(
        v_team.user_id, p_league_id, 'sistema', 'Rosa completata automaticamente',
        case when cardinality(v_aggiunti) > 0
          then cardinality(v_aggiunti) || ' svincolati aggiunti per raggiungere il minimo di 21 giocatori.'
          else 'Rosa riequilibrata automaticamente per rispettare il tetto ingaggi.' end,
        jsonb_build_object('view', 'team', 'aggiunti', cardinality(v_aggiunti), 'rilasciati', v_rilasciati)
      );
    end if;
  end loop;

  update public.offseasons
  set stato = 'conclusa', conclusa_il = clock_timestamp()
  where id = v_off.id;
  update public.leagues
  set stagione_corrente = v_off.stagione_a,
      fase_carriera = 'normale',
      offseason_fine = null,
      stato = 'stagione'
  where id = p_league_id;

  for v_player in
    select pi.id, pi.eta_corrente, p.nome, t.user_id
    from public.player_instances pi
    join public.players p on p.id = pi.player_id
    join public.teams t on t.id = pi.team_id and t.attiva
    where pi.league_id = p_league_id and not pi.ritirato and not pi.ritiro_annunciato
      and pi.eta_corrente >= 34
      and random() < private.probabilita_ritiro(pi.eta_corrente)
  loop
    update public.player_instances set ritiro_annunciato = true where id = v_player.id;
    perform private.notifica(v_player.user_id, p_league_id, 'sistema',
      v_player.nome || ' annuncia il ritiro',
      'Giochera'' ancora questa stagione, poi lascera'' la carriera: non puo'' essere ceduto in trattativa.',
      jsonb_build_object('player_instance_id', v_player.id));
  end loop;

  insert into public.retired_players(league_id, player_id, stagione)
  select p_league_id, p.id, v_off.stagione_a
  from public.players p
  where p.campionato = any(v_league.campionati_attivi)
    and not exists (
      select 1 from public.player_instances pi
      where pi.league_id = p_league_id and pi.player_id = p.id and pi.team_id is not null
    )
    and not exists (
      select 1 from public.retired_players rp
      where rp.league_id = p_league_id and rp.player_id = p.id
    )
    and (p.eta + (v_off.stagione_a - 1)) >= 34
    and random() < private.probabilita_ritiro(least(45, p.eta + (v_off.stagione_a - 1))::smallint)
  on conflict do nothing;

  v_season := private.inizializza_stagione(p_league_id);

  perform private.notifica(
    t.user_id, p_league_id, 'sistema', 'La nuova stagione e'' iniziata',
    'La prima giornata si giochera'' alle 23:00. Prepara la formazione.',
    jsonb_build_object('view', 'overview', 'season_id', v_season)
  )
  from public.teams t
  where t.league_id = p_league_id and t.attiva;

  return jsonb_build_object(
    'league_id', p_league_id,
    'season_id', v_season,
    'stagione', v_off.stagione_a,
    'prima_giornata', private.primo_calcio_dopo(v_off.scade_il)
  );
end;
$$;


-- ------------------------------------------------------------
--  8. Mercato: budget_disponibile sostituita da capienza_squadra (gia'
--     usata da Scambi.tsx). Mercato.tsx e' stato aggiornato a chiamare
--     capienza_squadra direttamente: questa funzione non serve piu'.
-- ------------------------------------------------------------

drop function if exists public.budget_disponibile(bigint);


-- ------------------------------------------------------------
--  9. Disattiva la catena dei premi partita: trigger prima, poi le
--     funzioni che diventano orfane. Nessuna sostituzione economica
--     (docs/decisioni-economia.md §1: "Vincere non da' nulla di
--     economico"). private.premi_partita_giornata (la tabella di
--     supporto) resta: e' storico, non fa piu' nulla senza chi ci scrive.
-- ------------------------------------------------------------

drop trigger if exists fixtures_paga_premi_giornata on public.fixtures;
drop trigger if exists transactions_annulla_premio_partite_stagionale on public.transactions;

drop function if exists private.paga_premi_quando_giornata_completa();
drop function if exists private.accredita_premi_partite_giornata(bigint, integer);
drop function if exists private.annulla_premio_partite_stagionale();
drop function if exists private.ricalcola_premi_partite_giornata(bigint, integer);


-- ------------------------------------------------------------
--  10. Codice gia' morto, verificato a zero chiamanti nel database live:
--      il vincolo di sostenibilita' pre-tetto e i suoi soli dipendenti,
--      le funzioni di stipendio a rate (gia' spente da
--      20260828230000_disattiva_addebito_ingaggi_giornata.sql, qui si
--      toglie solo il codice che non gira piu'), e l'asta a cassa legacy
--      mai promossa a produzione dopo l'introduzione del tetto.
-- ------------------------------------------------------------

drop function if exists private.verifica_sostenibilita(bigint, bigint, bigint);
drop function if exists private.budget_impegnato(bigint, bigint);
drop function if exists private.entrata_minima_garantita(bigint);
drop function if exists private.monte_ingaggi_prossima_stagione(bigint);
drop function if exists private.quota_ingaggio_giornata(bigint, integer, integer);
drop function if exists private.ingaggio_residuo_stagione(bigint, integer, integer);
drop function if exists private.risolvi_aste_giorno_cassa_legacy(date, bigint);


-- ------------------------------------------------------------
--  11. Le colonne. Ultimo passo, a valle di tutto il resto: nessuna
--      funzione viva le referenzia piu'.
-- ------------------------------------------------------------

alter table public.teams drop column if exists budget;
alter table public.teams drop column if exists budget_ingaggi_riservato;

commit;
