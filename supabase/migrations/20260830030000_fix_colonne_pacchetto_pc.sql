begin;

-- ============================================================
--  BUG: completa_draft_squadra_pc (completamento automatico del draft
--  per le squadre controllate dal PC) referenziava ancora le colonne
--  carta_def/carta_mid/carta_att di draft_team_state, rinominate in
--  carta_def1/carta_mid1/carta_att1 dalla migrazione del pacchetto a 7
--  carte (20260829110000_pacchetto_7_carte.sql). Da allora questa
--  funzione avrebbe fallito con "column does not exist" appena una
--  squadra PC avesse finito la propria rosa in una lega 2_of_4.
-- ============================================================

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
      carta_gk = null, carta_def1 = null, carta_def2 = null,
      carta_mid1 = null, carta_mid2 = null, carta_att1 = null, carta_att2 = null,
      carta_ruolo = null, ruolo_scelto = null, aggiornato_il = now()
  where league_id = p_league_id and team_id = p_team_id;
end;
$$;

commit;
