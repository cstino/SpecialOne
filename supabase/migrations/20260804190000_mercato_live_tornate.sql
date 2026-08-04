-- Ogni apertura manuale e' una nuova tornata dello stesso giorno. Il live
-- mostra solo l'ultima; le aste deserte delle tornate precedenti restano
-- nell'archivio degli svincolati.

alter table public.free_agent_auctions
  add column if not exists tornata integer not null default 1
  check (tornata >= 0);

-- Le estrazioni gia' esistenti vengono separate per istante di creazione:
-- le righe create nella stessa chiamata hanno lo stesso now().
with tornate_esistenti as (
  select id,
         dense_rank() over (
           partition by league_id, giorno
           order by creata_il
         ) as tornata
  from public.free_agent_auctions
  where origine = 'estrazione'
)
update public.free_agent_auctions a
set tornata = t.tornata
from tornate_esistenti t
where a.id = t.id;

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
  v_lega      public.leagues;
  v_per_ruolo integer;
  v_tornata   integer;
  v_creati    integer := 0;
  v_asta      record;
begin
  select * into v_lega from public.leagues where id = p_league_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Lega inesistente.';
  end if;

  select coalesce(max(a.tornata), 0) + 1 into v_tornata
  from public.free_agent_auctions a
  where a.league_id = p_league_id
    and a.giorno = p_giorno
    and a.origine = 'estrazione';

  v_per_ruolo := private.svincolati_per_ruolo(p_league_id);

  with disponibili as (
    select p.id, p.overall, p.eta, private.macro_ruolo(p.posizioni) as macro
    from public.players p
    where p.campionato = any(v_lega.campionati_attivi)
      and private.macro_ruolo(p.posizioni) in ('GK', 'DEF', 'MID', 'ATT')
      and not exists (
        select 1 from public.player_instances pi
        where pi.league_id = p_league_id and pi.player_id = p.id and pi.team_id is not null
      )
      and not exists (
        select 1 from public.retired_players rp
        where rp.league_id = p_league_id and rp.player_id = p.id
      )
      and not exists (
        select 1 from public.free_agent_auctions a
        where a.league_id = p_league_id and a.giorno = p_giorno and a.player_id = p.id
      )
      and not exists (
        select 1 from public.offseason_spins s
        where s.league_id = p_league_id and s.player_id = p.id and s.stato = 'proposto'
      )
  ),
  ranked as (
    select id, macro, row_number() over (partition by macro order by random()) as rn
    from disponibili
  ),
  scelti as (
    select id from ranked where rn <= v_per_ruolo
  )
  insert into public.free_agent_auctions
    (league_id, giorno, player_id, ingaggio_teorico, origine, tornata)
  select p_league_id, p_giorno, p.id,
         private.ingaggio_teorico(p.overall, p.eta), 'estrazione', v_tornata
  from public.players p join scelti s on s.id = p.id;

  get diagnostics v_creati = row_count;

  for v_asta in
    select a.id, a.ingaggio_teorico
    from public.free_agent_auctions a
    where a.league_id = p_league_id and a.giorno = p_giorno
  loop
    insert into private.auction_thresholds (auction_id, soglia)
    values (v_asta.id, round(v_asta.ingaggio_teorico * (0.90 + random() * 0.20)))
    on conflict (auction_id) do nothing;
  end loop;

  return v_creati;
end;
$$;

revoke all on function private.estrai_svincolati_lega(bigint, date)
  from public, anon, authenticated;
grant execute on function private.estrai_svincolati_lega(bigint, date)
  to service_role;

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
  v_tornata integer;
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

  v_estratti := private.estrai_svincolati_lega(p_league_id, v_giorno);
  select max(tornata) into v_tornata
  from public.free_agent_auctions
  where league_id = p_league_id and giorno = v_giorno and origine = 'estrazione';

  return jsonb_build_object('estratti', v_estratti, 'tornata', v_tornata);
end;
$$;

revoke all on function public.admin_apri_mercato(bigint) from public, anon;
grant execute on function public.admin_apri_mercato(bigint) to authenticated;

-- Un giocatore deserto puo' essere richiamato dall'archivio anche nello
-- stesso giorno: diventa un'asta d'archivio, fuori dalle 12 card Live, con
-- buste e soglia nuove.
create or replace function public.offri_per_svincolato_archivio(
  p_league_id bigint,
  p_player_id bigint,
  p_ingaggio bigint
)
returns public.free_agent_bids
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
  v_lega public.leagues;
  v_player public.players;
  v_squadra public.teams;
  v_giorno date := (now() at time zone 'Europe/Rome')::date;
  v_asta public.free_agent_auctions;
  v_asta_id bigint;
begin
  if v_user is null then
    raise exception using errcode = '42501', message = 'Devi accedere per usare il mercato.';
  end if;
  if not private.mercato_aperto_lega(p_league_id) then
    raise exception using errcode = '55000',
      message = 'Il mercato e'' chiuso: si offre dalle 07:00 alle 21:00 o quando l''admin lo apre.';
  end if;

  select * into v_lega from public.leagues where id = p_league_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Lega inesistente.';
  end if;
  select * into v_squadra
  from public.teams
  where league_id = p_league_id and user_id = v_user and attiva;
  if not found then
    raise exception using errcode = '42501', message = 'Non partecipi a questa lega.';
  end if;
  select * into v_player
  from public.players
  where id = p_player_id and campionato = any(v_lega.campionati_attivi);
  if not found then
    raise exception using errcode = 'P0002', message = 'Giocatore non disponibile in questa lega.';
  end if;
  if exists (
    select 1 from public.player_instances pi
    where pi.league_id = p_league_id and pi.player_id = p_player_id and pi.team_id is not null
  ) then
    raise exception using errcode = '23505', message = 'Questo giocatore e'' gia'' sotto contratto.';
  end if;
  if exists (
    select 1 from public.retired_players rp
    where rp.league_id = p_league_id and rp.player_id = p_player_id
  ) then
    raise exception using errcode = '23505', message = 'Questo giocatore si e'' ritirato.';
  end if;

  select * into v_asta
  from public.free_agent_auctions
  where league_id = p_league_id and giorno = v_giorno and player_id = p_player_id
  for update;

  if found then
    v_asta_id := v_asta.id;
    if v_asta.stato = 'deserta' then
      delete from public.free_agent_bids where auction_id = v_asta_id;
      update public.free_agent_auctions
      set stato = 'aperta', origine = 'archivio', tornata = 0,
          risolta_il = null, vincitore_team_id = null, ingaggio_finale = null
      where id = v_asta_id;
      update private.auction_thresholds
      set soglia = round(private.ingaggio_teorico(v_player.overall, v_player.eta) * (0.90 + random() * 0.20))
      where auction_id = v_asta_id;
    elsif v_asta.stato <> 'aperta' then
      raise exception using errcode = '55000', message = 'Questo giocatore ha gia'' un esito oggi.';
    end if;
  else
    insert into public.free_agent_auctions
      (league_id, giorno, player_id, ingaggio_teorico, origine, tornata)
    values (p_league_id, v_giorno, p_player_id,
            private.ingaggio_teorico(v_player.overall, v_player.eta), 'archivio', 0)
    returning id into v_asta_id;
    insert into private.auction_thresholds(auction_id, soglia)
    values (v_asta_id,
            round(private.ingaggio_teorico(v_player.overall, v_player.eta) * (0.90 + random() * 0.20)));
  end if;

  return public.offri_per_svincolato(v_asta_id, p_ingaggio);
end;
$$;

revoke all on function public.offri_per_svincolato_archivio(bigint, bigint, bigint)
  from public, anon, authenticated;
grant execute on function public.offri_per_svincolato_archivio(bigint, bigint, bigint)
  to authenticated;
