-- ============================================================
--  INGAGGI A RATE PER GIORNATA
--
--  Il budget e' la liquidita' effettiva; budget_ingaggi_riservato e' la
--  parte gia' promessa ai contratti della stagione. Il loro scarto e' cio'
--  che puo' essere usato per mercato e nuovi contratti.
-- ============================================================

alter table public.teams
  add column if not exists budget_ingaggi_riservato bigint not null default 0
  check (budget_ingaggi_riservato >= 0);

comment on column public.teams.budget_ingaggi_riservato is
  'Quota degli ingaggi della stagione ancora da pagare. Non e'' liquidita'' disponibile.';

create table if not exists private.pagamenti_ingaggi_giornata (
  league_id bigint not null references public.leagues(id) on delete cascade,
  giornata integer not null check (giornata > 0),
  team_id bigint not null references public.teams(id) on delete cascade,
  player_instance_id bigint not null references public.player_instances(id) on delete restrict,
  importo bigint not null check (importo > 0),
  creato_il timestamptz not null default now(),
  primary key (league_id, giornata, player_instance_id)
);

-- Rata esatta: la somma delle giornate e' sempre precisamente l'ingaggio
-- annuale, anche quando non e' divisibile per il numero di giornate.
create or replace function private.quota_ingaggio_giornata(
  p_ingaggio bigint,
  p_giornata integer,
  p_giornate_totali integer
) returns bigint
language sql
immutable
parallel safe
set search_path = ''
as $$
  select floor(p_ingaggio::numeric * p_giornata / greatest(p_giornate_totali, 1))::bigint
       - floor(p_ingaggio::numeric * greatest(p_giornata - 1, 0) / greatest(p_giornate_totali, 1))::bigint
$$;

create or replace function private.ingaggio_residuo_stagione(
  p_ingaggio bigint,
  p_giornate_giocate integer,
  p_giornate_totali integer
) returns bigint
language sql
immutable
parallel safe
set search_path = ''
as $$
  select p_ingaggio - floor(p_ingaggio::numeric * greatest(p_giornate_giocate, 0) / greatest(p_giornate_totali, 1))::bigint
$$;

create or replace function public.budget_disponibile(p_league_id bigint)
returns jsonb
language plpgsql
stable security definer
set search_path = ''
as $$
declare
  v_team public.teams;
  v_impegnato bigint;
  v_rosa integer;
begin
  select * into v_team from public.teams
  where league_id = p_league_id and user_id = (select auth.uid());
  if not found then
    raise exception using errcode = '42501', message = 'Non partecipi a questa lega.';
  end if;
  v_impegnato := private.budget_impegnato(v_team.id);
  select count(*) into v_rosa from public.player_instances where team_id = v_team.id;
  return jsonb_build_object(
    'budget', v_team.budget,
    'ingaggi_riservati', v_team.budget_ingaggi_riservato,
    'impegnato', v_impegnato,
    'offerte_impegnate', v_impegnato,
    'disponibile', v_team.budget - v_team.budget_ingaggi_riservato - v_impegnato,
    'rosa', v_rosa,
    'slot_impegnati', private.slot_impegnati(v_team.id),
    'slot_liberi', private.rosa_massima() - v_rosa - private.slot_impegnati(v_team.id)
  );
end;
$$;

-- Converte la contabilita' precedente delle leghe gia' in corso: la quota
-- non ancora maturata torna liquidita' e viene bloccata nella nuova riserva.
do $$
declare
  v_league public.leagues;
  v_giocate integer;
  v_team public.teams;
  v_residuo bigint;
begin
  for v_league in select * from public.leagues where stato = 'stagione'
  loop
    select count(distinct giornata)::integer into v_giocate
    from public.fixtures
    where league_id = v_league.id and stato = 'simulata';
    for v_team in select * from public.teams where league_id = v_league.id and attiva
    loop
      select coalesce(sum(private.ingaggio_residuo_stagione(pi.ingaggio, v_giocate, v_league.giornate_totali)), 0)::bigint
      into v_residuo
      from public.player_instances pi
      where pi.team_id = v_team.id and not pi.ritirato;
      if v_residuo > 0 then
        update public.teams
        set budget = budget + v_residuo,
            budget_ingaggi_riservato = v_residuo
        where id = v_team.id;
        insert into public.transactions(league_id, team_id, tipo, importo, descrizione, saldo_dopo)
        values (v_league.id, v_team.id, 'conversione_riserva_ingaggi', v_residuo,
                'Conversione quota ingaggi residua in riserva', v_team.budget + v_residuo);
      end if;
    end loop;
  end loop;
end $$;

-- Al termine del draft (o dell'off-season) il vecchio flusso aveva gia'
-- scalato il monte ingaggi. Lo restituiamo una sola volta e lo trasformiamo
-- in riserva prima della prima giornata: nessuna modifica alle RPC del draft.
create or replace function private.attiva_riserva_ingaggi_stagione()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_team public.teams;
  v_totale bigint;
begin
  if new.stato <> 'stagione' or old.stato = 'stagione' then return new; end if;
  for v_team in select * from public.teams where league_id = new.id and attiva for update
  loop
    select coalesce(sum(ingaggio), 0)::bigint into v_totale
    from public.player_instances where team_id = v_team.id and not ritirato;
    update public.teams
    set budget = budget + v_totale,
        budget_ingaggi_riservato = v_totale
    where id = v_team.id;
    if v_totale > 0 then
      insert into public.transactions(league_id, team_id, tipo, importo, descrizione, saldo_dopo)
      values (new.id, v_team.id, 'conversione_riserva_ingaggi', v_totale,
              'Ingaggi stagione convertiti in riserva', v_team.budget + v_totale);
    end if;
  end loop;
  return new;
end;
$$;

drop trigger if exists leagues_attiva_riserva_ingaggi on public.leagues;
create trigger leagues_attiva_riserva_ingaggi
after update of stato on public.leagues
for each row execute function private.attiva_riserva_ingaggi_stagione();

-- Chiamata dal cron dopo che tutte le partite della giornata sono registrate.
-- La chiave primaria della tabella privata rende sicuro ogni ritentativo.
create or replace function private.addebita_ingaggi_giornata(
  p_league_id bigint,
  p_giornata integer
) returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_lega public.leagues;
  v_riga record;
  v_contatore integer := 0;
  v_saldo bigint;
begin
  select * into v_lega from public.leagues where id = p_league_id for update;
  if not found or v_lega.stato <> 'stagione' then return 0; end if;
  if exists (select 1 from public.fixtures where league_id = p_league_id and giornata = p_giornata and stato <> 'simulata') then
    raise exception using errcode = '55000', message = 'Non tutte le partite della giornata sono state simulate.';
  end if;
  for v_riga in
    select pi.id as instance_id, pi.team_id, pi.ingaggio, p.nome,
           private.quota_ingaggio_giornata(pi.ingaggio, p_giornata, v_lega.giornate_totali) as quota
    from public.player_instances pi
    join public.players p on p.id = pi.player_id
    join public.teams t on t.id = pi.team_id
    where pi.league_id = p_league_id and pi.team_id is not null
      and t.attiva and not pi.ritirato
  loop
    insert into private.pagamenti_ingaggi_giornata(league_id, giornata, team_id, player_instance_id, importo)
    values (p_league_id, p_giornata, v_riga.team_id, v_riga.instance_id, v_riga.quota)
    on conflict do nothing;
    if not found then continue; end if;
    update public.teams
    set budget = budget - v_riga.quota,
        budget_ingaggi_riservato = greatest(0, budget_ingaggi_riservato - v_riga.quota)
    where id = v_riga.team_id
    returning budget into v_saldo;
    insert into public.transactions(league_id, team_id, tipo, importo, descrizione, saldo_dopo)
    values (p_league_id, v_riga.team_id, 'stipendio_giornata', -v_riga.quota,
            'Stipendio giornata ' || p_giornata || ': ' || v_riga.nome, v_saldo);
    v_contatore := v_contatore + 1;
  end loop;
  return v_contatore;
end;
$$;

revoke all on function private.addebita_ingaggi_giornata(bigint, integer) from public, anon, authenticated;
grant execute on function private.addebita_ingaggi_giornata(bigint, integer) to service_role;

-- La vecchia RPC contabilizzava il pro-rata come denaro immediato. La
-- manteniamo come esecutore delle verifiche di rosa e dei trasferimenti, ma
-- la incapsuliamo: prima controlliamo la vera disponibilita', poi annulliamo
-- soltanto il movimento fittizio di cassa e trasferiamo la riserva residua.
alter function public.rispondi_a_proposta(bigint, boolean)
  rename to rispondi_a_proposta_legacy;

create or replace function public.rispondi_a_proposta(p_proposta_id bigint, p_accetta boolean)
returns public.trade_proposals
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_p public.trade_proposals;
  v_lega public.leagues;
  v_da public.teams;
  v_a public.teams;
  v_giocate integer;
  v_offerto bigint;
  v_richiesto bigint;
  v_correzione_da bigint;
  v_correzione_a bigint;
  v_esito public.trade_proposals;
  v_saldo bigint;
begin
  if not coalesce(p_accetta, false) then
    return public.rispondi_a_proposta_legacy(p_proposta_id, false);
  end if;
  select * into v_p from public.trade_proposals where id = p_proposta_id;
  if not found then raise exception using errcode = 'P0002', message = 'Proposta inesistente.'; end if;
  select * into v_lega from public.leagues where id = v_p.league_id;
  select * into v_da from public.teams where id = v_p.da_team_id;
  select * into v_a from public.teams where id = v_p.a_team_id;
  select count(distinct giornata)::integer into v_giocate
  from public.fixtures where league_id = v_lega.id and stato = 'simulata';
  select coalesce(sum(private.ingaggio_residuo_stagione(pi.ingaggio, v_giocate, v_lega.giornate_totali)), 0)::bigint
  into v_offerto from public.player_instances pi where pi.id = any(v_p.giocatori_offerti);
  select coalesce(sum(private.ingaggio_residuo_stagione(pi.ingaggio, v_giocate, v_lega.giornate_totali)), 0)::bigint
  into v_richiesto from public.player_instances pi where pi.id = any(v_p.giocatori_richiesti);

  if v_da.budget - v_p.conguaglio - (v_da.budget_ingaggi_riservato - v_offerto + v_richiesto) < 0
     or v_a.budget + v_p.conguaglio - (v_a.budget_ingaggi_riservato - v_richiesto + v_offerto) < 0 then
    raise exception using errcode = '22023', message = 'Budget disponibile insufficiente per coprire il trasferimento e gli ingaggi residui.';
  end if;

  v_esito := public.rispondi_a_proposta_legacy(p_proposta_id, true);
  v_correzione_da := -v_offerto + v_richiesto;
  v_correzione_a := -v_correzione_da;
  update public.teams
  set budget = budget + v_correzione_da,
      budget_ingaggi_riservato = budget_ingaggi_riservato - v_offerto + v_richiesto
  where id = v_da.id returning budget into v_saldo;
  if v_correzione_da <> 0 then
    insert into public.transactions(league_id, team_id, tipo, importo, descrizione, saldo_dopo)
    values (v_lega.id, v_da.id, 'rettifica_riserva_ingaggi', v_correzione_da,
            'Quota ingaggio residua trasferita', v_saldo);
  end if;
  update public.teams
  set budget = budget + v_correzione_a,
      budget_ingaggi_riservato = budget_ingaggi_riservato - v_richiesto + v_offerto
  where id = v_a.id returning budget into v_saldo;
  if v_correzione_a <> 0 then
    insert into public.transactions(league_id, team_id, tipo, importo, descrizione, saldo_dopo)
    values (v_lega.id, v_a.id, 'rettifica_riserva_ingaggi', v_correzione_a,
            'Quota ingaggio residua trasferita', v_saldo);
  end if;
  return v_esito;
end;
$$;

revoke all on function public.rispondi_a_proposta_legacy(bigint, boolean) from public, anon, authenticated;
grant execute on function public.rispondi_a_proposta(bigint, boolean) to authenticated;
