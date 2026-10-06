-- Il pool di una finestra di scelte aperta e' RISERVATO: un giocatore estratto per il draft ON/OFF-Season non
-- puo' finire altrove prima che la finestra si risolva. Segnalato il 6 ottobre 2026: Aubameyang, nel pool
-- dell'OFF-Season 1, e' stato scelto da una nuova squadra nel suo mini-draft (che escludeva solo chi era gia' in
-- una rosa). Ora tutte le estrazioni da catalogo (draft a pacchetti e per ruolo, draft delle squadre PC, svincolati
-- del mercato) saltano chi sta in un pool non ancora risolto. Funzioni ricostruite dalla definizione live.

create or replace function private.giocatore_in_pool_aperto(p_league_id bigint, p_player_id bigint)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.scelte_pool sp
    join public.finestre_scelte f
      on f.league_id = sp.league_id and f.stagione = sp.stagione and f.finestra = sp.finestra
    where sp.league_id = p_league_id and sp.player_id = p_player_id and f.risolta_il is null
  )
$$;
revoke all on function private.giocatore_in_pool_aperto(bigint, bigint) from public, anon, authenticated;

CREATE OR REPLACE FUNCTION public.draft_by_role_reroll(p_league_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
    and not private.giocatore_in_pool_aperto(p_league_id, p.id)
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
$function$;

CREATE OR REPLACE FUNCTION public.draft_by_role_spin(p_league_id bigint, p_ruolo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
    and not private.giocatore_in_pool_aperto(p_league_id, p.id)
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
$function$;

CREATE OR REPLACE FUNCTION private.completa_draft_squadra_pc(p_league_id bigint, p_team_id bigint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_league public.leagues;
  v_team public.teams;
  v_player public.players;
  v_fap_overall smallint;
  v_fap_eta smallint;
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
    left join public.free_agent_progression fap on fap.league_id = p_league_id and fap.player_id = p.id
    where p.disponibile_estrazione
      and (p.elite_globale or p.campionato = any(v_league.campionati_attivi))
      and private.macro_ruolo(p.posizioni) = v_ruolo
      and private.ingaggio_teorico(coalesce(fap.overall_corrente, p.overall), coalesce(fap.eta_corrente, p.eta))
        between greatest(500000, v_target - 250000) and v_target + 250000
      and not exists (
        select 1 from public.player_instances pi
        where pi.league_id = p_league_id and pi.player_id = p.id
      )
    and not private.giocatore_in_pool_aperto(p_league_id, p.id)
      and not exists (
        select 1 from public.retired_players rp
        where rp.league_id = p_league_id and rp.player_id = p.id
      )
      and private.pick_sostenibile(
        v_league.budget_draft, v_speso, v_league.slot_rosa, v_presi,
        coalesce(fap.overall_corrente, p.overall), coalesce(fap.eta_corrente, p.eta)
      )
    order by p.id
    limit 1;

    if not found then
      select p.* into v_player
      from public.players p
      left join public.free_agent_progression fap on fap.league_id = p_league_id and fap.player_id = p.id
      where p.disponibile_estrazione
        and (p.elite_globale or p.campionato = any(v_league.campionati_attivi))
        and private.macro_ruolo(p.posizioni) = v_ruolo
        and not exists (
          select 1 from public.player_instances pi
          where pi.league_id = p_league_id and pi.player_id = p.id
        )
    and not private.giocatore_in_pool_aperto(p_league_id, p.id)
        and not exists (
          select 1 from public.retired_players rp
          where rp.league_id = p_league_id and rp.player_id = p.id
        )
        and private.pick_sostenibile(
          v_league.budget_draft, v_speso, v_league.slot_rosa, v_presi,
          coalesce(fap.overall_corrente, p.overall), coalesce(fap.eta_corrente, p.eta)
        )
      order by private.ingaggio_teorico(coalesce(fap.overall_corrente, p.overall), coalesce(fap.eta_corrente, p.eta)), p.id
      limit 1;
      if not found then
        raise exception using errcode = '55000',
          message = 'Il pool non contiene abbastanza giocatori sostenibili nel reparto richiesto.';
      end if;
    end if;

    select fap.overall_corrente, fap.eta_corrente into v_fap_overall, v_fap_eta
    from public.free_agent_progression fap where fap.league_id = p_league_id and fap.player_id = v_player.id;
    if v_fap_overall is not null then v_player.overall := v_fap_overall; v_player.eta := v_fap_eta; end if;

    v_ingaggio := private.ingaggio_teorico(v_player.overall, v_player.eta);
    insert into public.player_instances
      (league_id, player_id, team_id, overall_corrente, eta_corrente, ingaggio)
    values
      (p_league_id, v_player.id, p_team_id, v_player.overall, v_player.eta, v_ingaggio);

    delete from public.free_agent_progression where league_id = p_league_id and player_id = v_player.id;

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
      carta_gk = null, carta_def1 = null, carta_def2 = null,
      carta_mid1 = null, carta_mid2 = null, carta_att1 = null, carta_att2 = null,
      carta_ruolo = null, ruolo_scelto = null, aggiornato_il = now()
  where league_id = p_league_id and team_id = p_team_id;
end;
$function$;

CREATE OR REPLACE FUNCTION private.pesca_carta_ruolo(p_league leagues, p_ruolo text, p_esclusi bigint[] DEFAULT '{}'::bigint[])
 RETURNS bigint
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
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
    and not private.giocatore_in_pool_aperto(p_league.id, p.id)
    and not exists (
      select 1 from public.retired_players rp
      where rp.league_id = p_league.id and rp.player_id = p.id
    )
  order by random()
  limit 1;
$function$;

CREATE OR REPLACE FUNCTION private.estrai_svincolati_lega(p_league_id bigint, p_giorno date)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_lega       public.leagues;
  v_per_ruolo  integer;
  v_tornata    integer;
  v_creati     integer := 0;
  v_dalla_coda integer := 0;
  v_asta       record;
begin
  select * into v_lega from public.leagues where id = p_league_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Lega inesistente.';
  end if;
  select coalesce(max(a.tornata), 0) + 1 into v_tornata
  from public.free_agent_auctions a
  where a.league_id = p_league_id and a.giorno = p_giorno and a.origine = 'estrazione';
  v_per_ruolo := private.svincolati_per_ruolo(p_league_id);

  with disponibili as (
    select p.id, private.macro_ruolo(p.posizioni) as macro,
           coalesce(oi.overall_corrente, fap.overall_corrente, p.overall) as overall_attuale,
           coalesce(oi.eta_corrente, fap.eta_corrente, p.eta) as eta_attuale
    from public.players p
    left join public.player_instances oi
      on oi.league_id = p_league_id and oi.player_id = p.id and oi.team_id is null
    left join public.free_agent_progression fap
      on fap.league_id = p_league_id and fap.player_id = p.id
    where p.disponibile_estrazione
      -- decisioni-draft-picks §3.3: sopra 75 si passa dal mercato a scelte
      and coalesce(oi.overall_corrente, fap.overall_corrente, p.overall) <= 75
      and (p.elite_globale or p.campionato = any(v_lega.campionati_attivi))
      and private.macro_ruolo(p.posizioni) in ('GK', 'DEF', 'MID', 'ATT')
      and not exists (
        select 1 from public.player_instances pi
        where pi.league_id = p_league_id and pi.player_id = p.id and pi.team_id is not null
      )
    and not private.giocatore_in_pool_aperto(p_league_id, p.id)
      and not exists (
        select 1 from public.retired_players rp
        where rp.league_id = p_league_id and rp.player_id = p.id
      )
      and not exists (
        select 1 from public.free_agent_auctions a
        where a.league_id = p_league_id and a.giorno = p_giorno and a.player_id = p.id
      )
      -- Gli svincolati che un club paga ancora entrano a parte, tutti.
      and not exists (
        select 1 from public.player_instances pp
        where pp.league_id = p_league_id and pp.player_id = p.id
          and pp.team_id is null and pp.peso_team_id is not null
          and pp.contratto_scadenza >= private.stagione_contratto(p_league_id)
      )
      -- I rilasci in coda non concorrono ai posti del sorteggio: entrano
      -- extra piu' sotto, garantiti.
      and not exists (
        select 1 from private.rilasci_in_coda rc
        where rc.league_id = p_league_id and rc.player_id = p.id
      )
  ), ranked as (
    select id, macro, overall_attuale, eta_attuale,
           row_number() over (partition by macro order by random()) as rn
    from disponibili
  ), scelti as (
    select id, overall_attuale, eta_attuale from ranked where rn <= v_per_ruolo
  )
  insert into public.free_agent_auctions
    (league_id, giorno, player_id, ingaggio_teorico, origine, tornata)
  select p_league_id, p_giorno, s.id,
         private.ingaggio_teorico(s.overall_attuale, s.eta_attuale), 'estrazione', v_tornata
  from scelti s;

  get diagnostics v_creati = row_count;

  -- Rilasci in coda: entrano nella STESSA tornata appena creata, in piu'
  -- rispetto alla quota per ruolo. Solo chi e' ancora davvero libero — nel
  -- frattempo puo' essere stato ripreso da un'asta o uno scambio.
  with liberi as (
    select rc.player_id
    from private.rilasci_in_coda rc
    join public.player_instances pi
      on pi.league_id = rc.league_id and pi.player_id = rc.player_id
    where rc.league_id = p_league_id and pi.team_id is null and not pi.ritirato
  ), inseriti as (
    insert into public.free_agent_auctions
      (league_id, giorno, player_id, ingaggio_teorico, origine, tornata)
    select p_league_id, p_giorno, pi.player_id,
           private.ingaggio_teorico(pi.overall_corrente, pi.eta_corrente), 'estrazione', v_tornata
    from liberi l
    join public.player_instances pi on pi.league_id = p_league_id and pi.player_id = l.player_id
    returning player_id
  )
  delete from private.rilasci_in_coda
  where league_id = p_league_id and player_id in (select player_id from inseriti);
  get diagnostics v_dalla_coda = row_count;
  v_creati := v_creati + v_dalla_coda;

  -- Svincolati dalle squadre ancora a carico del vecchio club: ogni giorno,
  -- finche' qualcuno li prende o il contratto scade (poi tornano nel pool
  -- generico come tutti).
  insert into public.free_agent_auctions
    (league_id, giorno, player_id, ingaggio_teorico, origine, tornata)
  select p_league_id, p_giorno, pi.player_id,
         private.ingaggio_teorico(pi.overall_corrente, pi.eta_corrente), 'estrazione', v_tornata
  from public.player_instances pi
  where pi.league_id = p_league_id and pi.team_id is null and not pi.ritirato
    and pi.peso_team_id is not null
    and pi.contratto_scadenza >= private.stagione_contratto(p_league_id)
    and not exists (
      select 1 from public.free_agent_auctions a
      where a.league_id = p_league_id and a.giorno = p_giorno and a.player_id = pi.player_id
    );
  get diagnostics v_dalla_coda = row_count;
  v_creati := v_creati + v_dalla_coda;

  for v_asta in
    select a.id, a.ingaggio_teorico from public.free_agent_auctions a
    where a.league_id = p_league_id and a.giorno = p_giorno
  loop
    insert into private.auction_thresholds (auction_id, soglia)
    values (v_asta.id, round(v_asta.ingaggio_teorico * (0.90 + random() * 0.20)))
    on conflict (auction_id) do nothing;
  end loop;
  return v_creati;
end;
$function$;

