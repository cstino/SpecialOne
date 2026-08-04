-- Riapertura manuale del mercato: una nuova tornata nello stesso giorno.
-- Le aste deserte tornano disponibili e si aggiunge una nuova estrazione.
-- Le aste assegnate restano chiuse: il giocatore e' gia' sotto contratto.

create or replace function private.estrai_svincolati_lega(
  p_league_id bigint,
  p_giorno    date
)
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_lega    public.leagues;
  v_per_ruolo integer;
  v_creati  integer := 0;
  v_asta    record;
begin
  select * into v_lega from public.leagues where id = p_league_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Lega inesistente.';
  end if;

  -- Nessuna guardia "gia' estratto oggi": questa funzione puo' essere
  -- richiamata dall'admin per aprire una nuova tornata manuale.
  v_per_ruolo := private.svincolati_per_ruolo(p_league_id);

  with disponibili as (
    select p.id, p.overall, p.eta, private.macro_ruolo(p.posizioni) as macro
    from public.players p
    where p.campionato = any(v_lega.campionati_attivi)
      and private.macro_ruolo(p.posizioni) in ('GK', 'DEF', 'MID', 'ATT')
      and not exists (
        select 1 from public.player_instances pi
        where pi.league_id = p_league_id
          and pi.player_id = p.id
          and pi.team_id is not null
      )
      and not exists (
        select 1 from public.retired_players rp
        where rp.league_id = p_league_id and rp.player_id = p.id
      )
      and not exists (
        select 1 from public.free_agent_auctions a
        where a.league_id = p_league_id
          and a.giorno = p_giorno
          and a.player_id = p.id
      )
      and not exists (
        select 1 from public.offseason_spins s
        where s.league_id = p_league_id
          and s.player_id = p.id
          and s.stato = 'proposto'
      )
  ),
  ranked as (
    select id, macro,
           row_number() over (partition by macro order by random()) as rn
    from disponibili
  ),
  scelti as (
    select id from ranked where rn <= v_per_ruolo
  )
  insert into public.free_agent_auctions
    (league_id, giorno, player_id, ingaggio_teorico, origine)
  select p_league_id, p_giorno, p.id,
         private.ingaggio_teorico(p.overall, p.eta), 'estrazione'
  from public.players p join scelti s on s.id = p.id;

  get diagnostics v_creati = row_count;

  for v_asta in
    select a.id, a.ingaggio_teorico
    from public.free_agent_auctions a
    where a.league_id = p_league_id and a.giorno = p_giorno
  loop
    insert into private.auction_thresholds (auction_id, soglia)
    values (v_asta.id,
            round(v_asta.ingaggio_teorico * (0.90 + random() * 0.20)))
    on conflict (auction_id) do nothing;
  end loop;

  return v_creati;
end;
$$;

revoke all on function private.estrai_svincolati_lega(bigint, date)
  from public, anon, authenticated;
grant execute on function private.estrai_svincolati_lega(bigint, date)
  to service_role;

drop function if exists public.admin_apri_mercato(bigint);

create function public.admin_apri_mercato(p_league_id bigint)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_utente uuid := (select auth.uid());
  v_league public.leagues;
  v_giorno date := (now() at time zone 'Europe/Rome')::date;
  v_riaperte integer := 0;
  v_estratti integer := 0;
begin
  if v_utente is null then
    raise exception using errcode = '42501',
      message = 'Devi accedere per usare il pannello admin.';
  end if;

  select * into v_league from public.leagues where id = p_league_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Lega non trovata.';
  end if;
  if v_league.admin_id <> v_utente then
    raise exception using errcode = '42501',
      message = 'Solo l''amministratore puo'' aprire il mercato.';
  end if;
  if v_league.stato <> 'stagione' then
    raise exception using errcode = '55000',
      message = 'Il mercato e'' disponibile solo a stagione avviata.';
  end if;

  update public.free_agent_auctions
  set stato = 'aperta', risolta_il = null
  where league_id = p_league_id
    and giorno = v_giorno
    and origine = 'estrazione'
    and stato = 'deserta'
    and not exists (
      select 1 from public.player_instances pi
      where pi.league_id = p_league_id
        and pi.player_id = free_agent_auctions.player_id
        and pi.team_id is not null
    );
  get diagnostics v_riaperte = row_count;

  v_estratti := private.estrai_svincolati_lega(p_league_id, v_giorno);

  return jsonb_build_object(
    'riaperte', v_riaperte,
    'estratti', v_estratti,
    'totale_aperto', v_riaperte + v_estratti
  );
end;
$$;

revoke all on function public.admin_apri_mercato(bigint) from public, anon;
grant execute on function public.admin_apri_mercato(bigint) to authenticated;

-- Override per lega/data: l'apertura manuale abilita davvero le offerte anche
-- fuori dalla finestra automatica 07:00-21:00.
create table if not exists private.mercato_override_admin (
  league_id bigint not null references public.leagues(id) on delete cascade,
  giorno date not null,
  aperto_il timestamptz not null default now(),
  primary key (league_id, giorno)
);

revoke all on table private.mercato_override_admin from public, anon, authenticated;
grant select, insert, update, delete on table private.mercato_override_admin to service_role;

create or replace function private.mercato_aperto_lega(p_league_id bigint)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select (
    (
      (now() at time zone 'Europe/Rome')::time >= time '07:00'
      and (now() at time zone 'Europe/Rome')::time < time '21:00'
    )
    or exists (
      select 1 from private.mercato_override_admin o
      where o.league_id = p_league_id
        and o.giorno = (now() at time zone 'Europe/Rome')::date
    )
  );
$$;

revoke all on function private.mercato_aperto_lega(bigint) from public, anon, authenticated;
grant execute on function private.mercato_aperto_lega(bigint) to service_role;

create or replace function public.offri_per_svincolato(
  p_auction_id bigint,
  p_ingaggio   bigint
)
returns public.free_agent_bids
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_utente     uuid := (select auth.uid());
  v_asta       public.free_agent_auctions;
  v_lega       public.leagues;
  v_squadra    public.teams;
  v_rosa       integer;
  v_prorata    bigint;
  v_impegnato  bigint;
  v_slot_altri integer;
  v_offerta    public.free_agent_bids;
begin
  if v_utente is null then
    raise exception using errcode = '42501', message = 'Devi accedere per usare il mercato.';
  end if;

  select * into v_asta from public.free_agent_auctions where id = p_auction_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Asta inesistente.';
  end if;
  if v_asta.stato <> 'aperta' then
    raise exception using errcode = '55000', message = 'Questa asta e'' gia'' stata risolta.';
  end if;
  if not private.mercato_aperto_lega(v_asta.league_id) then
    raise exception using errcode = '55000',
      message = 'Il mercato e'' chiuso: si offre dalle 07:00 alle 21:00 o quando l''admin lo apre.';
  end if;

  select * into v_lega from public.leagues where id = v_asta.league_id;
  select * into v_squadra from public.teams
  where league_id = v_asta.league_id and user_id = v_utente;
  if not found then
    raise exception using errcode = '42501', message = 'Non partecipi a questa lega.';
  end if;
  if p_ingaggio < 500000 then
    raise exception using errcode = '22023', message = 'L''ingaggio minimo e'' 0,5 Mâ‚¬.';
  end if;

  select count(*) into v_rosa from public.player_instances where team_id = v_squadra.id;
  v_slot_altri := private.slot_impegnati(v_squadra.id, p_auction_id);
  if v_rosa + v_slot_altri + 1 > private.rosa_massima() then
    raise exception using errcode = '22023',
      message = 'Non hai piu'' posti liberi: ' || v_rosa || ' giocatori in rosa e '
                || v_slot_altri || ' offerte gia'' in gioco, su un massimo di ' || private.rosa_massima() || ' giocatori.';
  end if;

  v_prorata := round(p_ingaggio::numeric * private.giornate_rimanenti(v_lega.id)
                     / greatest(v_lega.giornate_totali, 1));
  v_impegnato := private.budget_impegnato(v_squadra.id, p_auction_id);
  if v_squadra.budget - v_impegnato < v_prorata then
    raise exception using errcode = '22023',
      message = 'Budget insufficiente: ' || private.in_milioni(v_impegnato)
                || ' Mâ‚¬ sono gia'' impegnati in altre offerte, te ne restano '
                || private.in_milioni(v_squadra.budget - v_impegnato)
                || ' Mâ‚¬ e questa ne richiede ' || private.in_milioni(v_prorata) || ' Mâ‚¬.';
  end if;

  insert into public.free_agent_bids (auction_id, league_id, team_id, ingaggio_offerto)
  values (p_auction_id, v_asta.league_id, v_squadra.id, p_ingaggio)
  on conflict (auction_id, team_id) do update
    set ingaggio_offerto = excluded.ingaggio_offerto, aggiornata_il = now()
  returning * into v_offerta;
  return v_offerta;
end;
$$;

create or replace function public.ritira_offerta(p_auction_id bigint)
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_squadra bigint;
  v_league_id bigint;
  v_tolte integer;
begin
  select t.id, a.league_id into v_squadra, v_league_id
  from public.teams t
  join public.free_agent_auctions a on a.league_id = t.league_id
  where a.id = p_auction_id and t.user_id = (select auth.uid());
  if v_squadra is null then
    raise exception using errcode = '42501', message = 'Non partecipi a questa lega.';
  end if;
  if not private.mercato_aperto_lega(v_league_id) then
    raise exception using errcode = '55000', message = 'Il mercato e'' chiuso.';
  end if;
  delete from public.free_agent_bids
  where auction_id = p_auction_id and team_id = v_squadra;
  get diagnostics v_tolte = row_count;
  return v_tolte;
end;
$$;

revoke all on function public.offri_per_svincolato(bigint, bigint) from public, anon, authenticated;
grant execute on function public.offri_per_svincolato(bigint, bigint) to authenticated;
revoke all on function public.ritira_offerta(bigint) from public, anon;
grant execute on function public.ritira_offerta(bigint) to authenticated;

-- Le RPC admin registrano e rimuovono l'override insieme alla tornata.
create or replace function public.admin_apri_mercato(p_league_id bigint)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_utente uuid := (select auth.uid());
  v_league public.leagues;
  v_giorno date := (now() at time zone 'Europe/Rome')::date;
  v_riaperte integer := 0;
  v_estratti integer := 0;
begin
  if v_utente is null then
    raise exception using errcode = '42501', message = 'Devi accedere per usare il pannello admin.';
  end if;
  select * into v_league from public.leagues where id = p_league_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Lega non trovata.';
  end if;
  if v_league.admin_id <> v_utente then
    raise exception using errcode = '42501', message = 'Solo l''amministratore puo'' aprire il mercato.';
  end if;
  if v_league.stato <> 'stagione' then
    raise exception using errcode = '55000', message = 'Il mercato e'' disponibile solo a stagione avviata.';
  end if;

  insert into private.mercato_override_admin(league_id, giorno)
  values (p_league_id, v_giorno)
  on conflict (league_id, giorno) do update set aperto_il = now();

  update public.free_agent_auctions
  set stato = 'aperta', risolta_il = null
  where league_id = p_league_id
    and giorno = v_giorno
    and origine = 'estrazione'
    and stato = 'deserta'
    and not exists (
      select 1 from public.player_instances pi
      where pi.league_id = p_league_id
        and pi.player_id = free_agent_auctions.player_id
        and pi.team_id is not null
    );
  get diagnostics v_riaperte = row_count;

  v_estratti := private.estrai_svincolati_lega(p_league_id, v_giorno);
  return jsonb_build_object(
    'riaperte', v_riaperte,
    'estratti', v_estratti,
    'totale_aperto', v_riaperte + v_estratti
  );
end;
$$;

create or replace function public.admin_chiudi_mercato(p_league_id bigint)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_utente uuid := (select auth.uid());
  v_league public.leagues;
  v_aste integer;
  v_proposte integer;
  v_giorno date := (now() at time zone 'Europe/Rome')::date;
begin
  if v_utente is null then
    raise exception using errcode = '42501', message = 'Devi accedere per usare il pannello admin.';
  end if;
  select * into v_league from public.leagues where id = p_league_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Lega non trovata.';
  end if;
  if v_league.admin_id <> v_utente then
    raise exception using errcode = '42501', message = 'Solo l''amministratore puo'' chiudere il mercato.';
  end if;
  if v_league.stato <> 'stagione' then
    raise exception using errcode = '55000', message = 'Il mercato e'' disponibile solo a stagione avviata.';
  end if;

  v_aste := private.risolvi_aste_giorno(v_giorno, p_league_id);
  v_proposte := private.scadi_proposte_giorno(p_league_id);
  delete from private.mercato_override_admin
  where league_id = p_league_id and giorno = v_giorno;

  return jsonb_build_object('aste_risolte', v_aste, 'proposte_scadute', v_proposte);
end;
$$;

revoke all on function public.admin_apri_mercato(bigint) from public, anon;
grant execute on function public.admin_apri_mercato(bigint) to authenticated;
revoke all on function public.admin_chiudi_mercato(bigint) from public, anon;
grant execute on function public.admin_chiudi_mercato(bigint) to authenticated;
