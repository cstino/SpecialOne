-- La libertà totale del BY ROLE resta per gli utenti. Le squadre PC, invece,
-- usano profili da rosa calcistica: base 3/8/8/5 con piccole variazioni.

create or replace function private.obiettivi_rosa_pc(
  p_team_id bigint,
  p_totale integer default 24
) returns table (ruolo text, obiettivo integer)
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_gk integer;
  v_def integer;
  v_mid integer;
  v_att integer;
  v_extra integer := greatest(coalesce(p_totale, 24) - 24, 0);
begin
  case mod(abs(p_team_id), 5)
    when 0 then v_gk := 3; v_def := 8; v_mid := 8; v_att := 5;
    when 1 then v_gk := 3; v_def := 9; v_mid := 7; v_att := 5;
    when 2 then v_gk := 2; v_def := 8; v_mid := 9; v_att := 5;
    when 3 then v_gk := 3; v_def := 7; v_mid := 8; v_att := 6;
    else        v_gk := 2; v_def := 9; v_mid := 8; v_att := 5;
  end case;

  -- Eventuali giocatori oltre i 24, arrivati dal mercato, ampliano prima i
  -- reparti di movimento e non il numero dei portieri.
  v_def := v_def + ((v_extra + 1) / 2);
  v_mid := v_mid + (v_extra / 2);

  return query values
    ('GK'::text, v_gk), ('DEF'::text, v_def),
    ('MID'::text, v_mid), ('ATT'::text, v_att);
end;
$$;

revoke all on function private.obiettivi_rosa_pc(bigint, integer)
  from public, anon, authenticated;
grant execute on function private.obiettivi_rosa_pc(bigint, integer) to service_role;

create or replace function private.completa_draft_squadra_pc(
  p_league_id bigint,
  p_team_id bigint
) returns void
language plpgsql
volatile
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

    -- Sceglie fra i reparti ancora sotto obiettivo. Il profilo varia per
    -- squadra, ma nessun PC può accumulare casualmente cinque o più portieri.
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
    -- L'ordine resta mescolato: non prende prima tutti i difensori e poi
    -- tutti gli altri reparti, ma alla fine rispetta comunque il profilo.
    order by random()
    limit 1;

    if v_ruolo is null then
      raise exception using errcode = '55000', message = 'Il profilo ruoli PC non copre tutti gli slot della rosa.';
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
      -- Il fallback resta nello stesso reparto: prima poteva pescare un
      -- ruolo qualsiasi e annullare il bilanciamento appena calcolato.
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
          v_team.budget, v_league.budget_draft, v_speso, v_league.slot_rosa,
          v_presi, p.overall, p.eta
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

-- Correzione una tantum per Test2: nessuna partita è stata giocata. Cambia
-- soltanto pick originali dei PC con alternative dello stesso identico
-- ingaggio; budget, dimensione rosa e giocatori coinvolti in trattative
-- restano invariati.
do $$
declare
  v_league_id bigint;
  v_team public.teams;
  v_totale integer;
  v_eccesso text;
  v_manca text;
  v_vecchio public.player_instances;
  v_nuovo public.players;
begin
  select l.id into v_league_id
  from public.leagues l
  where l.nome = 'Test2'
    and not exists (
      select 1 from public.fixtures f
      where f.league_id = l.id and f.stato = 'simulata'
    )
  order by l.id desc
  limit 1;
  if v_league_id is null then return; end if;

  perform pg_catalog.pg_advisory_xact_lock(v_league_id);
  for v_team in
    select * from public.teams
    where league_id = v_league_id and controllata_da_pc and attiva
    order by id
  loop
    select count(*) into v_totale from public.player_instances where team_id = v_team.id;
    loop
      with conteggi as (
        select ru.ruolo, count(p.id)::integer as quanti
        from (values ('GK'), ('DEF'), ('MID'), ('ATT')) ru(ruolo)
        left join public.player_instances pi on pi.team_id = v_team.id
        left join public.players p on p.id = pi.player_id
          and private.macro_ruolo(p.posizioni) = ru.ruolo
        group by ru.ruolo
      )
      select c.ruolo into v_eccesso
      from conteggi c
      join private.obiettivi_rosa_pc(v_team.id, v_totale) o using (ruolo)
      where c.quanti > o.obiettivo
      order by (c.quanti - o.obiettivo) desc, (c.ruolo = 'GK') desc
      limit 1;

      with conteggi as (
        select ru.ruolo, count(p.id)::integer as quanti
        from (values ('GK'), ('DEF'), ('MID'), ('ATT')) ru(ruolo)
        left join public.player_instances pi on pi.team_id = v_team.id
        left join public.players p on p.id = pi.player_id
          and private.macro_ruolo(p.posizioni) = ru.ruolo
        group by ru.ruolo
      )
      select c.ruolo into v_manca
      from conteggi c
      join private.obiettivi_rosa_pc(v_team.id, v_totale) o using (ruolo)
      where c.quanti < o.obiettivo
      order by (o.obiettivo - c.quanti) desc
      limit 1;

      exit when v_eccesso is null or v_manca is null;

      select pi.* into v_vecchio
      from public.player_instances pi
      join public.players p on p.id = pi.player_id
      where pi.team_id = v_team.id
        and private.macro_ruolo(p.posizioni) = v_eccesso
        and exists (select 1 from public.draft_picks dp where dp.player_instance_id = pi.id)
        and not exists (
          select 1 from public.trade_proposals tp
          where pi.id = any(tp.giocatori_offerti) or pi.id = any(tp.giocatori_richiesti)
        )
      order by pi.overall_corrente, pi.id
      limit 1
      for update;
      if not found then
        raise exception 'Impossibile riequilibrare %, nessun % sostituibile', v_team.nome, v_eccesso;
      end if;

      select p.* into v_nuovo
      from public.players p
      where p.disponibile_estrazione
        and private.macro_ruolo(p.posizioni) = v_manca
        and private.ingaggio_teorico(p.overall, p.eta) = v_vecchio.ingaggio
        and not exists (
          select 1 from public.player_instances pi
          where pi.league_id = v_league_id and pi.player_id = p.id
        )
        and not exists (
          select 1 from public.retired_players rp
          where rp.league_id = v_league_id and rp.player_id = p.id
        )
        and not exists (
          select 1 from public.free_agent_auctions fa
          where fa.league_id = v_league_id and fa.player_id = p.id
        )
      order by abs(p.overall - v_vecchio.overall_corrente), p.id
      limit 1;
      if not found then
        raise exception 'Nessun % libero con ingaggio % per riequilibrare %', v_manca, v_vecchio.ingaggio, v_team.nome;
      end if;

      update public.player_instances
      set player_id = v_nuovo.id,
          overall_corrente = v_nuovo.overall,
          eta_corrente = v_nuovo.eta
      where id = v_vecchio.id;
      update public.draft_picks set club_estratto = v_manca
      where player_instance_id = v_vecchio.id;
    end loop;

    delete from public.lineups where league_id = v_league_id and team_id = v_team.id;
  end loop;
end;
$$;
