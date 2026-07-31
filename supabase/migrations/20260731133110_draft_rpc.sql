-- ============================================================
--  RPC DEL DRAFT
--
--  Tutte le transizioni passano da qui: il client non riceve privilegi di
--  scrittura sulle tabelle. Il lock su draft_state serializza i pick e rende
--  il vincolo di unicita' globale affidabile anche con due browser aperti.
-- ============================================================

create or replace function private.ingaggio_teorico(
  p_overall smallint,
  p_eta smallint
)
returns bigint
language sql
immutable
parallel safe
set search_path = ''
as $$
  select greatest(
    500000::numeric,
    round((
      case
        when p_overall <= 65 then 0.5
        when p_overall <= 70 then 0.8
        when p_overall <= 74 then 1.2
        when p_overall <= 77 then 2.0
        when p_overall <= 80 then 3.2
        when p_overall <= 83 then 5.0
        when p_overall <= 85 then 7.5
        when p_overall <= 87 then 10.0
        when p_overall <= 89 then 13.0
        else 17.0
      end
      * case
        when p_eta between 16 and 20 then 0.35
        when p_eta between 21 and 23 then 0.65
        when p_eta between 24 and 26 then 0.90
        when p_eta between 27 and 30 then 1.00
        when p_eta between 31 and 32 then 0.90
        when p_eta between 33 and 34 then 0.70
        else 0.50
      end
      * 10
    )) * 100000
  )::bigint;
$$;

revoke all on function private.ingaggio_teorico(smallint, smallint)
  from public, anon, authenticated;
grant execute on function private.ingaggio_teorico(smallint, smallint)
  to service_role;

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
  v_state public.draft_state;
  v_picked integer;
  v_goalkeepers integer;
  v_speso bigint;
  v_players jsonb;
begin
  select * into v_league from public.leagues where id = p_league_id;
  select * into v_team from public.teams where id = p_team_id and league_id = p_league_id;
  select * into v_state from public.draft_state where league_id = p_league_id;

  select count(*)::integer, count(*) filter (where p.posizioni[1] = 'GK')::integer
    into v_picked, v_goalkeepers
  from public.player_instances pi
  join public.players p on p.id = pi.player_id
  where pi.league_id = p_league_id and pi.team_id = p_team_id;

  v_speso := v_league.budget_iniziale - v_team.budget;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', p.id,
    'nome', p.nome,
    'club', p.club,
    'campionato', p.campionato,
    'overall', p.overall,
    'eta', p.eta,
    'posizioni', p.posizioni,
    'foto_url', p.foto_url,
    'ingaggio', private.ingaggio_teorico(p.overall, p.eta),
    'squadra_id', pi.team_id,
    'selezionabile',
      pi.id is null
      and v_speso + private.ingaggio_teorico(p.overall, p.eta)
            <= (v_league.budget_iniziale * 0.80)
      and v_team.budget - private.ingaggio_teorico(p.overall, p.eta)
            >= (
              greatest(0, v_league.slot_rosa - v_picked - 1) * 500000
              + greatest(
                  0,
                  v_league.portieri_minimi - v_goalkeepers
                    - case when p.posizioni[1] = 'GK' then 1 else 0 end
                ) * 500000
            ),
    'motivo', case
      when pi.id is not null then 'gia_scelto'
      when v_speso + private.ingaggio_teorico(p.overall, p.eta)
             > (v_league.budget_iniziale * 0.80) then 'tetto_ingaggi'
      when v_team.budget - private.ingaggio_teorico(p.overall, p.eta)
             < (
               greatest(0, v_league.slot_rosa - v_picked - 1) * 500000
               + greatest(
                   0,
                   v_league.portieri_minimi - v_goalkeepers
                     - case when p.posizioni[1] = 'GK' then 1 else 0 end
                 ) * 500000
             ) then 'non_sostenibile'
      else null
    end
  ) order by p.overall desc, p.nome), '[]'::jsonb)
    into v_players
  from public.players p
  left join public.player_instances pi
    on pi.league_id = p_league_id and pi.player_id = p.id
  where p.club = p_club
    and p.campionato = any(v_league.campionati_attivi);

  return jsonb_build_object(
    'league_id', p_league_id,
    'team_id', p_team_id,
    'pick_numero', v_state.pick_numero,
    'stato', v_state.stato,
    'club', p_club,
    'reroll_rimasti', v_team.reroll_rimasti,
    'budget', v_team.budget,
    'slot_occupati', v_picked,
    'giocatori', v_players
  );
end;
$$;

revoke all on function private.draft_payload(bigint, bigint, text)
  from public, anon, authenticated;
grant execute on function private.draft_payload(bigint, bigint, text)
  to service_role;

-- ------------------------------------------------------------

create or replace function public.avvia_draft(p_league_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_league public.leagues;
  v_team_count integer;
  v_team record;
  v_state public.draft_state;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'Devi accedere prima di avviare il draft.';
  end if;

  select * into v_league from public.leagues where id = p_league_id for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Lega non trovata.';
  end if;
  if v_league.admin_id <> v_user_id then
    raise exception using errcode = '42501', message = 'Solo l''admin puo'' avviare il draft.';
  end if;
  if v_league.stato <> 'setup' then
    raise exception using errcode = '55000', message = 'Il draft non e'' disponibile in questo stato.';
  end if;

  select count(*) into v_team_count from public.teams where league_id = p_league_id;
  if v_team_count <> v_league.n_squadre then
    raise exception using errcode = '55000', message = 'Servono tutte le squadre prima di avviare il draft.';
  end if;

  update public.teams t
  set ordine_draft = x.posizione
  from (
    select id, row_number() over (order by creata_il, id)::smallint - 1 as posizione
    from public.teams
    where league_id = p_league_id
  ) x
  where t.id = x.id;

  insert into public.draft_state (league_id)
  values (p_league_id)
  returning * into v_state;

  update public.leagues set stato = 'draft' where id = p_league_id;

  return jsonb_build_object(
    'league_id', p_league_id,
    'stato', 'draft',
    'pick_numero', v_state.pick_numero,
    'team_id', (select id from public.teams where league_id = p_league_id and ordine_draft = 0)
  );
exception when unique_violation then
  raise exception using errcode = '55000', message = 'Il draft e'' gia'' stato avviato.';
end;
$$;

-- ------------------------------------------------------------

create or replace function public.draft_spin(p_league_id bigint)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_league public.leagues;
  v_state public.draft_state;
  v_team public.teams;
  v_club text;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'Devi accedere prima di fare SPIN.';
  end if;
  select * into v_league from public.leagues where id = p_league_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Lega non trovata.';
  end if;
  select * into v_state from public.draft_state where league_id = p_league_id for update;
  if not found or v_league.stato <> 'draft' or v_state.stato <> 'in_corso' then
    raise exception using errcode = '55000', message = 'Il draft non e'' attivo.';
  end if;
  select * into v_team from public.teams
  where league_id = p_league_id
    and ordine_draft = private.turno_serpentina(v_league.n_squadre, v_state.pick_numero);
  if not found then
    raise exception using errcode = '55000', message = 'Squadra del turno non trovata.';
  end if;
  if v_team.user_id <> v_user_id then
    raise exception using errcode = '42501', message = 'Non e'' il tuo turno.';
  end if;
  if v_state.club_corrente is not null then
    return private.draft_payload(p_league_id, v_team.id, v_state.club_corrente);
  end if;

  select p.club into v_club
  from public.players p
  where p.campionato = any(v_league.campionati_attivi)
    and not exists (
      select 1 from public.player_instances pi
      where pi.league_id = p_league_id and pi.player_id = p.id
    )
    and v_team.budget - private.ingaggio_teorico(p.overall, p.eta)
          >= greatest(0, v_league.slot_rosa -
                (select count(*) from public.player_instances pi2 where pi2.league_id = p_league_id and pi2.team_id = v_team.id) - 1) * 500000
    and v_team.budget - private.ingaggio_teorico(p.overall, p.eta)
          >= greatest(0, v_league.portieri_minimi -
                (select count(*) from public.player_instances pi3 join public.players p3 on p3.id = pi3.player_id
                 where pi3.league_id = p_league_id and pi3.team_id = v_team.id and p3.posizioni[1] = 'GK') -
                case when p.posizioni[1] = 'GK' then 1 else 0 end) * 500000
    and (v_league.budget_iniziale - v_team.budget) + private.ingaggio_teorico(p.overall, p.eta)
          <= v_league.budget_iniziale * 0.80
  group by p.club
  order by random()
  limit 1;

  if v_club is null then
    raise exception using errcode = '55000', message = 'Non ci sono piu'' giocatori ingaggiabili nel pool attivo.';
  end if;

  update public.draft_state
  set club_corrente = v_club, aggiornato_il = now()
  where league_id = p_league_id;

  return private.draft_payload(p_league_id, v_team.id, v_club);
end;
$$;

-- ------------------------------------------------------------

create or replace function public.draft_reroll(p_league_id bigint)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_team public.teams;
  v_state public.draft_state;
  v_user_id uuid := (select auth.uid());
  v_result jsonb;
begin
  select * into v_state from public.draft_state where league_id = p_league_id for update;
  if not found then raise exception using errcode = '55000', message = 'Il draft non e'' attivo.'; end if;
  select t.* into v_team from public.teams t join public.leagues l on l.id = t.league_id
  where t.league_id = p_league_id and t.ordine_draft = private.turno_serpentina(l.n_squadre, v_state.pick_numero);
  if not found then raise exception using errcode = '55000', message = 'Squadra del turno non trovata.'; end if;
  if v_team.user_id <> v_user_id then raise exception using errcode = '42501', message = 'Non e'' il tuo turno.'; end if;
  if v_state.club_corrente is null then raise exception using errcode = '55000', message = 'Devi fare SPIN prima del reroll.'; end if;
  if v_team.reroll_rimasti <= 0 then raise exception using errcode = '55000', message = 'Non hai piu'' reroll disponibili.'; end if;

  update public.teams set reroll_rimasti = reroll_rimasti - 1 where id = v_team.id;
  update public.draft_state set club_corrente = null, aggiornato_il = now() where league_id = p_league_id;
  v_result := public.draft_spin(p_league_id);
  return v_result;
end;
$$;

-- ------------------------------------------------------------

create or replace function public.draft_pick(
  p_league_id bigint,
  p_player_id bigint
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_league public.leagues;
  v_state public.draft_state;
  v_team public.teams;
  v_player public.players;
  v_wage bigint;
  v_picked integer;
  v_goalkeepers integer;
  v_new_budget bigint;
  v_next_pick integer;
  v_instance public.player_instances;
begin
  select * into v_league from public.leagues where id = p_league_id;
  if not found then raise exception using errcode = 'P0002', message = 'Lega non trovata.'; end if;
  select * into v_state from public.draft_state where league_id = p_league_id for update;
  if v_user_id is null then raise exception using errcode = '42501', message = 'Devi accedere prima di scegliere.'; end if;
  if not found or v_league.stato <> 'draft' or v_state.stato <> 'in_corso' then
    raise exception using errcode = '55000', message = 'Il draft non e'' attivo.';
  end if;
  select * into v_team from public.teams
  where league_id = p_league_id and ordine_draft = private.turno_serpentina(v_league.n_squadre, v_state.pick_numero);
  if not found then raise exception using errcode = '55000', message = 'Squadra del turno non trovata.'; end if;
  if v_team.user_id <> v_user_id then raise exception using errcode = '42501', message = 'Non e'' il tuo turno.'; end if;
  if v_state.club_corrente is null then raise exception using errcode = '55000', message = 'Devi fare SPIN prima di scegliere.'; end if;

  select * into v_player from public.players
  where id = p_player_id and club = v_state.club_corrente and campionato = any(v_league.campionati_attivi);
  if not found then raise exception using errcode = '22023', message = 'Il giocatore non appartiene al club estratto.'; end if;
  if exists (select 1 from public.player_instances where league_id = p_league_id and player_id = p_player_id) then
    raise exception using errcode = '23505', message = 'Questo giocatore e'' gia'' stato scelto.';
  end if;

  v_wage := private.ingaggio_teorico(v_player.overall, v_player.eta);
  select count(*)::integer, count(*) filter (where p.posizioni[1] = 'GK')::integer
    into v_picked, v_goalkeepers
  from public.player_instances pi join public.players p on p.id = pi.player_id
  where pi.league_id = p_league_id and pi.team_id = v_team.id;
  v_new_budget := v_team.budget - v_wage;
  if v_team.budget - v_wage < greatest(0, v_league.slot_rosa - v_picked - 1) * 500000
    + greatest(0, v_league.portieri_minimi - v_goalkeepers - case when v_player.posizioni[1] = 'GK' then 1 else 0 end) * 500000
    or (v_league.budget_iniziale - v_team.budget) + v_wage > v_league.budget_iniziale * 0.80 then
    raise exception using errcode = '22023', message = 'Questo giocatore non e'' sostenibile per la tua rosa.';
  end if;

  insert into public.player_instances (league_id, player_id, team_id, overall_corrente, eta_corrente, ingaggio)
  values (p_league_id, p_player_id, v_team.id, v_player.overall, v_player.eta, v_wage)
  returning * into v_instance;

  insert into public.draft_picks (league_id, team_id, player_instance_id, pick_numero, club_estratto, ingaggio_pagato)
  values (p_league_id, v_team.id, v_instance.id, v_state.pick_numero, v_state.club_corrente, v_wage);

  update public.teams set budget = v_new_budget where id = v_team.id;
  insert into public.transactions (league_id, team_id, tipo, importo, descrizione, saldo_dopo)
  values (p_league_id, v_team.id, 'draft_pick', -v_wage, 'Ingaggio draft: ' || v_player.nome, v_new_budget);

  v_next_pick := v_state.pick_numero + 1;
  update public.draft_state
  set pick_numero = v_next_pick, club_corrente = null,
      stato = case when v_next_pick >= v_league.n_squadre * v_league.slot_rosa then 'concluso' else 'in_corso' end,
      aggiornato_il = now()
  where league_id = p_league_id;
  if v_next_pick >= v_league.n_squadre * v_league.slot_rosa then
    update public.leagues set stato = 'stagione' where id = p_league_id;
  end if;

  return jsonb_build_object(
    'league_id', p_league_id,
    'pick_numero', v_state.pick_numero,
    'player_instance_id', v_instance.id,
    'team_id', v_team.id,
    'ingaggio', v_wage,
    'budget', v_new_budget,
    'draft_concluso', v_next_pick >= v_league.n_squadre * v_league.slot_rosa
  );
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

comment on function public.avvia_draft(bigint) is 'Avvia il draft quando la lega ha tutte le squadre.';
comment on function public.draft_spin(bigint) is 'Estrae il club del turno corrente senza consumare reroll.';
comment on function public.draft_reroll(bigint) is 'Consuma un reroll e sostituisce il club estratto.';
comment on function public.draft_pick(bigint, bigint) is 'Valida e registra atomicamente un pick del draft.';
