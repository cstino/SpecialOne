-- ============================================================
--  DRAFT INDIPENDENTE PER SQUADRA
--
--  Ogni squadra puo' procedere senza aspettare le altre. Il database resta
--  l'arbitro: draft_state viene bloccato durante un pick, mentre
--  unique(league_id, player_id) impedisce che lo stesso giocatore venga
--  assegnato due volte.
-- ============================================================

create table public.draft_team_state (
  team_id       bigint primary key,
  league_id     bigint not null,
  pick_numero   int not null default 0 check (pick_numero >= 0),
  club_corrente text,
  spin_a_vuoto  int not null default 0 check (spin_a_vuoto >= 0),
  stato         text not null default 'in_corso'
                check (stato in ('in_corso', 'concluso')),
  aggiornato_il timestamptz not null default now(),
  constraint draft_team_state_team_league_fk
    foreign key (team_id, league_id)
    references public.teams (id, league_id) on delete cascade
);

create index draft_team_state_league_idx on public.draft_team_state (league_id);
alter table public.draft_team_state enable row level security;
create policy draft_team_state_lettura on public.draft_team_state
  for select to authenticated
  using ((select private.e_membro(league_id)));
grant select on public.draft_team_state to authenticated;
grant select, insert, update, delete on public.draft_team_state to service_role;

-- ------------------------------------------------------------

create or replace function private.draft_payload(
  p_league_id bigint,
  p_team_id bigint,
  p_club text
)
returns jsonb
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
  v_goalkeepers integer;
  v_speso bigint;
  v_players jsonb;
begin
  select * into v_league from public.leagues where id = p_league_id;
  select * into v_team from public.teams where id = p_team_id and league_id = p_league_id;
  select * into v_state from public.draft_team_state where team_id = p_team_id and league_id = p_league_id;

  select count(*)::integer, count(*) filter (where p.posizioni[1] = 'GK')::integer
    into v_picked, v_goalkeepers
  from public.player_instances pi
  join public.players p on p.id = pi.player_id
  where pi.league_id = p_league_id and pi.team_id = p_team_id;
  v_speso := v_league.budget_iniziale - v_team.budget;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', p.id, 'nome', p.nome, 'club', p.club, 'campionato', p.campionato,
    'overall', p.overall, 'eta', p.eta, 'posizioni', p.posizioni, 'foto_url', p.foto_url,
    'ingaggio', private.ingaggio_teorico(p.overall, p.eta), 'squadra_id', pi.team_id,
    'selezionabile',
      pi.id is null
      and v_speso + private.ingaggio_teorico(p.overall, p.eta) <= v_league.budget_iniziale * 0.80
      and v_team.budget - private.ingaggio_teorico(p.overall, p.eta) >=
        greatest(0, v_league.slot_rosa - v_picked - 1) * 500000
        + greatest(0, v_league.portieri_minimi - v_goalkeepers
          - case when p.posizioni[1] = 'GK' then 1 else 0 end) * 500000,
    'motivo', case
      when pi.id is not null then 'gia_scelto'
      when v_speso + private.ingaggio_teorico(p.overall, p.eta) > v_league.budget_iniziale * 0.80 then 'tetto_ingaggi'
      when v_team.budget - private.ingaggio_teorico(p.overall, p.eta) <
        greatest(0, v_league.slot_rosa - v_picked - 1) * 500000
        + greatest(0, v_league.portieri_minimi - v_goalkeepers
          - case when p.posizioni[1] = 'GK' then 1 else 0 end) * 500000 then 'non_sostenibile'
      else null
    end
  ) order by p.overall desc, p.nome), '[]'::jsonb) into v_players
  from public.players p
  left join public.player_instances pi on pi.league_id = p_league_id and pi.player_id = p.id
  where p.club = p_club and p.campionato = any(v_league.campionati_attivi);

  return jsonb_build_object(
    'league_id', p_league_id, 'team_id', p_team_id, 'pick_numero', v_state.pick_numero,
    'stato', v_state.stato, 'club', p_club, 'reroll_rimasti', v_team.reroll_rimasti,
    'budget', v_team.budget, 'slot_occupati', v_picked, 'giocatori', v_players
  );
end;
$$;

-- ------------------------------------------------------------

create or replace function public.avvia_draft(p_league_id bigint)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_league public.leagues;
  v_team_count integer;
begin
  if v_user_id is null then raise exception using errcode = '42501', message = 'Devi accedere prima di avviare il draft.'; end if;
  select * into v_league from public.leagues where id = p_league_id for update;
  if not found then raise exception using errcode = 'P0002', message = 'Lega non trovata.'; end if;
  if v_league.admin_id <> v_user_id then raise exception using errcode = '42501', message = 'Solo l''admin puo'' avviare il draft.'; end if;
  if v_league.stato <> 'setup' then raise exception using errcode = '55000', message = 'Il draft non e'' disponibile in questo stato.'; end if;
  select count(*) into v_team_count from public.teams where league_id = p_league_id;
  if v_team_count <> v_league.n_squadre then raise exception using errcode = '55000', message = 'Servono tutte le squadre prima di avviare il draft.'; end if;

  insert into public.draft_state (league_id) values (p_league_id);
  insert into public.draft_team_state (team_id, league_id)
  select id, league_id from public.teams where league_id = p_league_id;
  update public.leagues set stato = 'draft' where id = p_league_id;
  return jsonb_build_object('league_id', p_league_id, 'stato', 'draft');
exception when unique_violation then
  raise exception using errcode = '55000', message = 'Il draft e'' gia'' stato avviato.';
end;
$$;

-- ------------------------------------------------------------

create or replace function public.draft_spin(p_league_id bigint)
returns jsonb
language plpgsql volatile security definer set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_league public.leagues;
  v_team public.teams;
  v_state public.draft_team_state;
  v_club text;
begin
  if v_user_id is null then raise exception using errcode = '42501', message = 'Devi accedere prima di fare SPIN.'; end if;
  select * into v_league from public.leagues where id = p_league_id;
  select * into v_team from public.teams where league_id = p_league_id and user_id = v_user_id;
  if not found then raise exception using errcode = '42501', message = 'Non hai una squadra in questa lega.'; end if;
  select * into v_state from public.draft_team_state where team_id = v_team.id and league_id = p_league_id for update;
  if not found or v_league.stato <> 'draft' or v_state.stato <> 'in_corso' then raise exception using errcode = '55000', message = 'Il tuo draft non e'' attivo.'; end if;
  if v_state.club_corrente is not null then return private.draft_payload(p_league_id, v_team.id, v_state.club_corrente); end if;

  select p.club into v_club
  from public.players p
  where p.campionato = any(v_league.campionati_attivi)
    and not exists (select 1 from public.player_instances pi where pi.league_id = p_league_id and pi.player_id = p.id)
    and v_team.budget - private.ingaggio_teorico(p.overall, p.eta) >= greatest(0, v_league.slot_rosa - (select count(*) from public.player_instances where league_id = p_league_id and team_id = v_team.id) - 1) * 500000
    and v_team.budget - private.ingaggio_teorico(p.overall, p.eta) >= greatest(0, v_league.portieri_minimi - (select count(*) from public.player_instances pi join public.players pg on pg.id = pi.player_id where pi.league_id = p_league_id and pi.team_id = v_team.id and pg.posizioni[1] = 'GK') - case when p.posizioni[1] = 'GK' then 1 else 0 end) * 500000
    and (v_league.budget_iniziale - v_team.budget) + private.ingaggio_teorico(p.overall, p.eta) <= v_league.budget_iniziale * 0.80
  group by p.club order by random() limit 1;
  if v_club is null then raise exception using errcode = '55000', message = 'Non ci sono piu'' giocatori ingaggiabili nel pool attivo.'; end if;
  update public.draft_team_state set club_corrente = v_club, aggiornato_il = now() where team_id = v_team.id;
  return private.draft_payload(p_league_id, v_team.id, v_club);
end;
$$;

-- ------------------------------------------------------------

create or replace function public.draft_reroll(p_league_id bigint)
returns jsonb
language plpgsql volatile security definer set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_team public.teams;
  v_state public.draft_team_state;
begin
  select * into v_team from public.teams where league_id = p_league_id and user_id = v_user_id;
  select * into v_state from public.draft_team_state where team_id = v_team.id and league_id = p_league_id for update;
  if not found then raise exception using errcode = '55000', message = 'Il tuo draft non e'' attivo.'; end if;
  if v_state.club_corrente is null then raise exception using errcode = '55000', message = 'Devi fare SPIN prima del reroll.'; end if;
  if v_team.reroll_rimasti <= 0 then raise exception using errcode = '55000', message = 'Non hai piu'' reroll disponibili.'; end if;
  update public.teams set reroll_rimasti = reroll_rimasti - 1 where id = v_team.id;
  update public.draft_team_state set club_corrente = null, aggiornato_il = now() where team_id = v_team.id;
  return public.draft_spin(p_league_id);
end;
$$;

-- ------------------------------------------------------------

create or replace function public.draft_pick(p_league_id bigint, p_player_id bigint)
returns jsonb
language plpgsql volatile security definer set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_league public.leagues;
  v_global public.draft_state;
  v_state public.draft_team_state;
  v_team public.teams;
  v_player public.players;
  v_wage bigint;
  v_picked integer;
  v_goalkeepers integer;
  v_new_budget bigint;
  v_instance public.player_instances;
  v_completed integer;
begin
  select * into v_league from public.leagues where id = p_league_id;
  select * into v_global from public.draft_state where league_id = p_league_id for update;
  if v_user_id is null or not found or v_league.stato <> 'draft' then raise exception using errcode = '55000', message = 'Il draft non e'' attivo.'; end if;
  select * into v_team from public.teams where league_id = p_league_id and user_id = v_user_id;
  if not found then raise exception using errcode = '42501', message = 'Non hai una squadra in questa lega.'; end if;
  select * into v_state from public.draft_team_state where team_id = v_team.id and league_id = p_league_id for update;
  if not found or v_state.stato <> 'in_corso' then raise exception using errcode = '55000', message = 'La tua rosa e'' gia'' completa.'; end if;
  if v_state.club_corrente is null then raise exception using errcode = '55000', message = 'Devi fare SPIN prima di scegliere.'; end if;
  select * into v_player from public.players where id = p_player_id and club = v_state.club_corrente and campionato = any(v_league.campionati_attivi);
  if not found then raise exception using errcode = '22023', message = 'Il giocatore non appartiene al club estratto.'; end if;
  if exists (select 1 from public.player_instances where league_id = p_league_id and player_id = p_player_id) then raise exception using errcode = '23505', message = 'Questo giocatore e'' gia'' stato scelto.'; end if;

  v_wage := private.ingaggio_teorico(v_player.overall, v_player.eta);
  select count(*)::integer, count(*) filter (where p.posizioni[1] = 'GK')::integer into v_picked, v_goalkeepers
  from public.player_instances pi join public.players p on p.id = pi.player_id where pi.league_id = p_league_id and pi.team_id = v_team.id;
  v_new_budget := v_team.budget - v_wage;
  if v_new_budget < greatest(0, v_league.slot_rosa - v_picked - 1) * 500000 + greatest(0, v_league.portieri_minimi - v_goalkeepers - case when v_player.posizioni[1] = 'GK' then 1 else 0 end) * 500000
     or (v_league.budget_iniziale - v_team.budget) + v_wage > v_league.budget_iniziale * 0.80 then raise exception using errcode = '22023', message = 'Questo giocatore non e'' sostenibile per la tua rosa.'; end if;

  insert into public.player_instances (league_id, player_id, team_id, overall_corrente, eta_corrente, ingaggio)
  values (p_league_id, p_player_id, v_team.id, v_player.overall, v_player.eta, v_wage) returning * into v_instance;
  insert into public.draft_picks (league_id, team_id, player_instance_id, pick_numero, club_estratto, ingaggio_pagato)
  values (p_league_id, v_team.id, v_instance.id, v_global.pick_numero, v_state.club_corrente, v_wage);
  update public.teams set budget = v_new_budget where id = v_team.id;
  insert into public.transactions (league_id, team_id, tipo, importo, descrizione, saldo_dopo)
  values (p_league_id, v_team.id, 'draft_pick', -v_wage, 'Ingaggio draft: ' || v_player.nome, v_new_budget);

  update public.draft_team_state set pick_numero = pick_numero + 1, club_corrente = null, stato = case when pick_numero + 1 >= v_league.slot_rosa then 'concluso' else 'in_corso' end, aggiornato_il = now() where team_id = v_team.id;
  update public.draft_state set pick_numero = pick_numero + 1, aggiornato_il = now() where league_id = p_league_id;
  select count(*) into v_completed from public.draft_team_state where league_id = p_league_id and stato = 'concluso';
  if v_completed >= v_league.n_squadre then
    update public.draft_state set stato = 'concluso' where league_id = p_league_id;
    update public.leagues set stato = 'stagione' where id = p_league_id;
  end if;
  return jsonb_build_object('league_id', p_league_id, 'team_id', v_team.id, 'pick_numero', v_state.pick_numero, 'player_instance_id', v_instance.id, 'ingaggio', v_wage, 'budget', v_new_budget, 'draft_concluso', v_completed >= v_league.n_squadre);
end;
$$;

revoke all on function public.avvia_draft(bigint) from public, anon;
revoke all on function public.draft_spin(bigint) from public, anon;
revoke all on function public.draft_reroll(bigint) from public, anon;
revoke all on function public.draft_pick(bigint, bigint) from public, anon;
grant execute on function public.avvia_draft(bigint) to authenticated;
grant execute on function public.draft_spin(bigint) to authenticated;
grant execute on function public.draft_reroll(bigint) to authenticated;
grant execute on function public.draft_pick(bigint, bigint) to authenticated;
