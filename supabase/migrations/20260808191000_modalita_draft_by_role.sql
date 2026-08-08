begin;

-- Due esperienze di draft convivono nella stessa lega:
-- 2 of 4 mantiene i pacchetti esistenti, BY ROLE assegna una carta alla volta.
alter table public.leagues
  add column modalita_draft text not null default '2_of_4'
  check (modalita_draft in ('2_of_4', 'by_role'));

alter table public.draft_team_state
  add column carta_ruolo bigint references public.players(id),
  add column ruolo_scelto text
    check (ruolo_scelto is null or ruolo_scelto in ('GK', 'DEF', 'MID', 'ATT'));

-- La nuova firma non rompe client o leghe gia' esistenti: delega alla RPC
-- con squadre PC e salva la modalita' prima che la transazione sia visibile.
create or replace function public.crea_lega(
  p_nome_lega text, p_nome_squadra text, p_stemma_url text,
  p_n_squadre smallint, p_n_gironi smallint, p_budget_iniziale bigint,
  p_budget_draft bigint, p_reroll_draft smallint, p_slot_rosa smallint,
  p_portieri_minimi smallint, p_campionati_attivi text[], p_squadre_pc smallint,
  p_modalita_draft text
) returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_esito jsonb;
begin
  if p_modalita_draft not in ('2_of_4', 'by_role') then
    raise exception using errcode = '22023', message = 'Modalita'' draft non valida.';
  end if;

  v_esito := public.crea_lega(
    p_nome_lega, p_nome_squadra, p_stemma_url,
    p_n_squadre, p_n_gironi, p_budget_iniziale,
    p_budget_draft, p_reroll_draft, p_slot_rosa,
    p_portieri_minimi, p_campionati_attivi, p_squadre_pc
  );

  update public.leagues
  set modalita_draft = p_modalita_draft
  where id = (v_esito->>'league_id')::bigint;

  return v_esito;
end;
$$;

revoke all on function public.crea_lega(text,text,text,smallint,smallint,bigint,bigint,smallint,smallint,smallint,text[],smallint,text)
  from public, anon;
grant execute on function public.crea_lega(text,text,text,smallint,smallint,bigint,bigint,smallint,smallint,smallint,text[],smallint,text)
  to authenticated;

create or replace function private.by_role_payload(p_league_id bigint, p_team_id bigint)
returns jsonb
language plpgsql stable security definer set search_path = ''
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
  v_speso := v_league.budget_iniziale - v_team.budget;

  if v_state.carta_ruolo is not null then
    select * into v_player from public.players where id = v_state.carta_ruolo;
    v_carta := jsonb_build_object(
      'ruolo', v_state.ruolo_scelto,
      'id', v_player.id, 'nome', v_player.nome, 'club', v_player.club,
      'campionato', v_player.campionato, 'overall', v_player.overall,
      'eta', v_player.eta, 'posizioni', v_player.posizioni, 'foto_url', v_player.foto_url,
      'ingaggio', private.ingaggio_teorico(v_player.overall, v_player.eta),
      'ingaggiabile', private.pick_sostenibile(
        v_team.budget, v_league.budget_draft, v_speso, v_league.slot_rosa,
        v_picked, v_player.overall, v_player.eta
      )
    );
  end if;

  return jsonb_build_object(
    'league_id', p_league_id, 'team_id', p_team_id,
    'pick_numero', v_state.pick_numero, 'stato', v_state.stato,
    'reroll_rimasti', v_team.reroll_rimasti, 'budget', v_team.budget,
    'slot_occupati', v_picked, 'ruolo_scelto', v_state.ruolo_scelto,
    'carta', v_carta
  );
end;
$$;

revoke all on function private.by_role_payload(bigint,bigint) from public, anon, authenticated;
grant execute on function private.by_role_payload(bigint,bigint) to service_role;

create or replace function public.draft_by_role_spin(p_league_id bigint, p_ruolo text)
returns jsonb
language plpgsql volatile security definer set search_path = ''
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

  -- Uno spin aperto resta stabile anche dopo un refresh del browser.
  if v_state.carta_ruolo is not null then
    return private.by_role_payload(p_league_id, v_team.id);
  end if;

  select count(*) into v_picked from public.player_instances
  where league_id = p_league_id and team_id = v_team.id;
  v_speso := v_league.budget_iniziale - v_team.budget;

  -- Equivale a ripetere automaticamente lo spin finche' esce una carta
  -- sostenibile, senza consumare reroll e senza poter bloccare la rosa.
  select p.id into v_player_id
  from public.players p
  where p.campionato = any(v_league.campionati_attivi)
    and private.macro_ruolo(p.posizioni) = v_ruolo
    and not exists (
      select 1 from public.player_instances pi
      where pi.league_id = p_league_id and pi.player_id = p.id
    )
    and private.pick_sostenibile(
      v_team.budget, v_league.budget_draft, v_speso, v_league.slot_rosa,
      v_picked, p.overall, p.eta
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

create or replace function public.draft_by_role_reroll(p_league_id bigint)
returns jsonb
language plpgsql volatile security definer set search_path = ''
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
  v_speso := v_league.budget_iniziale - v_team.budget;
  v_vecchio_id := v_state.carta_ruolo;

  select p.id into v_player_id
  from public.players p
  where p.campionato = any(v_league.campionati_attivi)
    and private.macro_ruolo(p.posizioni) = v_state.ruolo_scelto
    and p.id <> v_vecchio_id
    and not exists (
      select 1 from public.player_instances pi
      where pi.league_id = p_league_id and pi.player_id = p.id
    )
    and private.pick_sostenibile(
      v_team.budget, v_league.budget_draft, v_speso, v_league.slot_rosa,
      v_picked, p.overall, p.eta
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

create or replace function public.draft_by_role_ingaggia(p_league_id bigint, p_player_id bigint)
returns jsonb
language plpgsql volatile security definer set search_path = ''
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
  v_new_budget bigint;
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
  v_speso := v_league.budget_iniziale - v_team.budget;
  if not private.pick_sostenibile(
    v_team.budget, v_league.budget_draft, v_speso, v_league.slot_rosa,
    v_picked, v_player.overall, v_player.eta
  ) then
    raise exception using errcode = '22023', message = 'Il giocatore non e'' sostenibile per completare la rosa.';
  end if;

  v_ingaggio := private.ingaggio_teorico(v_player.overall, v_player.eta);
  v_new_budget := v_team.budget - v_ingaggio;
  insert into public.player_instances
    (league_id, player_id, team_id, overall_corrente, eta_corrente, ingaggio)
  values
    (p_league_id, v_player.id, v_team.id, v_player.overall, v_player.eta, v_ingaggio)
  returning * into v_instance;
  insert into public.draft_picks
    (league_id, team_id, player_instance_id, pick_numero, club_estratto, ingaggio_pagato)
  values
    (p_league_id, v_team.id, v_instance.id, v_global.pick_numero, v_state.ruolo_scelto, v_ingaggio);

  update public.teams set budget = v_new_budget where id = v_team.id;
  insert into public.transactions (league_id, team_id, tipo, importo, descrizione, saldo_dopo)
  values (p_league_id, v_team.id, 'draft_pick', -v_ingaggio, 'Ingaggio draft BY ROLE: ' || v_player.nome, v_new_budget);

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
    'budget', v_new_budget, 'draft_concluso', v_done
  );
end;
$$;

revoke all on function public.draft_by_role_spin(bigint,text) from public, anon;
revoke all on function public.draft_by_role_reroll(bigint) from public, anon;
revoke all on function public.draft_by_role_ingaggia(bigint,bigint) from public, anon;
grant execute on function public.draft_by_role_spin(bigint,text) to authenticated;
grant execute on function public.draft_by_role_reroll(bigint) to authenticated;
grant execute on function public.draft_by_role_ingaggia(bigint,bigint) to authenticated;

-- Le RPC storiche restano disponibili soltanto per le leghe 2 of 4.
alter function public.draft_apri_pacchetto(bigint) rename to draft_apri_pacchetto_2_of_4_impl;
alter function public.draft_pacchetto_reroll(bigint) rename to draft_pacchetto_reroll_2_of_4_impl;
alter function public.draft_scegli_pacchetto(bigint,bigint,bigint) rename to draft_scegli_pacchetto_2_of_4_impl;

revoke all on function public.draft_apri_pacchetto_2_of_4_impl(bigint) from public, anon, authenticated;
revoke all on function public.draft_pacchetto_reroll_2_of_4_impl(bigint) from public, anon, authenticated;
revoke all on function public.draft_scegli_pacchetto_2_of_4_impl(bigint,bigint,bigint) from public, anon, authenticated;

create function public.draft_apri_pacchetto(p_league_id bigint) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
begin
  if (select modalita_draft from public.leagues where id = p_league_id) <> '2_of_4' then
    raise exception using errcode = '55000', message = 'Questa lega usa il draft BY ROLE.';
  end if;
  return public.draft_apri_pacchetto_2_of_4_impl(p_league_id);
end; $$;

create function public.draft_pacchetto_reroll(p_league_id bigint) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
begin
  if (select modalita_draft from public.leagues where id = p_league_id) <> '2_of_4' then
    raise exception using errcode = '55000', message = 'Questa lega usa il draft BY ROLE.';
  end if;
  return public.draft_pacchetto_reroll_2_of_4_impl(p_league_id);
end; $$;

create function public.draft_scegli_pacchetto(p_league_id bigint, p_player_id_1 bigint, p_player_id_2 bigint)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
begin
  if (select modalita_draft from public.leagues where id = p_league_id) <> '2_of_4' then
    raise exception using errcode = '55000', message = 'Questa lega usa il draft BY ROLE.';
  end if;
  return public.draft_scegli_pacchetto_2_of_4_impl(p_league_id, p_player_id_1, p_player_id_2);
end; $$;

revoke all on function public.draft_apri_pacchetto(bigint) from public, anon;
revoke all on function public.draft_pacchetto_reroll(bigint) from public, anon;
revoke all on function public.draft_scegli_pacchetto(bigint,bigint,bigint) from public, anon;
grant execute on function public.draft_apri_pacchetto(bigint) to authenticated;
grant execute on function public.draft_pacchetto_reroll(bigint) to authenticated;
grant execute on function public.draft_scegli_pacchetto(bigint,bigint,bigint) to authenticated;

-- Nelle leghe BY ROLE il PC sceglie liberamente il reparto a ogni pick;
-- in 2 of 4 conserva la distribuzione alternata gia' esistente.
do $$
declare v_sql text;
begin
  select pg_get_functiondef('private.completa_draft_squadra_pc(bigint,bigint)'::regprocedure) into v_sql;
  v_sql := replace(v_sql,
    $old$    v_ruolo := (array['GK','DEF','MID','ATT','DEF','MID','ATT','DEF','MID','ATT','DEF','MID','GK','DEF','MID','ATT','DEF','MID','ATT','DEF','MID','DEF','MID','ATT'])[v_presi + 1];$old$,
    $new$    if v_league.modalita_draft = 'by_role' then
      v_ruolo := (array['GK','DEF','MID','ATT'])[1 + floor(random() * 4)::integer];
    else
      v_ruolo := (array[
        'GK','DEF','MID','ATT','DEF','MID','ATT','DEF',
        'MID','ATT','DEF','MID','GK','DEF','MID','ATT',
        'DEF','MID','ATT','DEF','MID','DEF','MID','ATT'
      ])[v_presi + 1];
    end if;$new$);
  execute v_sql;
end $$;

commit;
