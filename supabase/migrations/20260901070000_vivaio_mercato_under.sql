-- ============================================================
--  VIVAIO: MERCATO UNDER, SLOT, PROMOZIONE
--  Deciso il 1 settembre 2026, in conversazione con l'utente.
--
--  Scelte confermate dall'utente:
--    - gli slot vivaio sono FUORI dal conteggio rosa (21-30), ma
--      l'ingaggio offerto impegna SUBITO capienza sotto il tetto,
--      come un'asta normale — minimo 0,1 M€ invece di 0,5 M€.
--    - alla promozione in prima squadra vale il blocco delle 10
--      giornate prima di poter svincolare (come draft/asta/scambio).
--    - un giovane non promosso entro la fine dell'off-season si
--      svincola in automatico all'inizio della stagione successiva,
--      tornando nel mercato UNDER (sweep aggiunto in una migrazione
--      successiva, dentro private.finalizza_offseason).
--
--  Scoperto durante l'indagine: il catalogo non ha quindicenni (eta'
--  minima 16, solo 89 under-18 in tutto il gioco): i prospetti UNDER
--  sono generati (nome/nazionalita'/attributi inventati, ma coerenti),
--  non pescati dal dataset FC 26. Confermato dall'utente.
--
--  Scelta architetturale presa in autonomia: chi e' in vivaio vive in
--  una tabella SEPARATA (vivaio_prospetti), non in player_instances.
--  L'alternativa — un flag in_vivaio su player_instances — avrebbe
--  richiesto escludere i vivaio da OGNI conteggio rosa gia' esistente
--  (aste, scambi, draft, offseason: almeno 8 funzioni live), con alto
--  rischio di dimenticarne una. Con una tabella separata i vivaio non
--  compaiono MAI in player_instances finche' non promossi: zero
--  modifiche al conteggio rosa. L'unico punto che li deve "vedere" e'
--  il tetto ingaggi (private.monte_ingaggi/capienza_residua/
--  verifica_capienza, estese qui in modo additivo — un parametro in
--  piu' in coda con default null, non cambia nessuna chiamata
--  esistente. Le vecchie firme vengono DROPpate esplicitamente prima:
--  altrimenti CREATE OR REPLACE con piu' parametri crea un secondo
--  overload invece di sostituire, e le chiamate posizionali esistenti
--  diventerebbero ambigue — lo stesso errore gia' capitato con
--  crea_lega in questa sessione).
--
--  Quota di estrazione giornaliera (2 per macro-ruolo, 8 al giorno):
--  numero scelto da me, piu' basso dei 5/ruolo del mercato svincolati
--  perche' e' un mercato accessorio, non quello principale. Facile da
--  cambiare (private.under_per_ruolo).
-- ============================================================

begin;

-- ------------------------------------------------------------
--  Origine "vivaio" sui giocatori generati: DISTINTA da is_regen.
--  is_regen (20260731120200_catalogo_giocatori.sql) e' riservata al
--  meccanismo di ripopolamento del pool svincolati di design.md §2.4,
--  esplicitamente rimandato alla stagione 5. Sono due funzionalita'
--  diverse che capitano a usare la stessa tecnica (generazione
--  procedurale): tenerle distinte evita che l'una interferisca
--  sull'altra quando "vero" regen verra' costruito.
-- ------------------------------------------------------------
alter table public.players add column origine_vivaio boolean not null default false;
comment on column public.players.origine_vivaio is
  'true per i prospetti generati dal mercato UNDER del vivaio. Non e'' is_regen: quello resta riservato al ripopolamento pool di design.md §2.4 (stagione 5).';

-- Namespace di fc_id riservato ai generati, ben sopra il massimo reale
-- osservato (280142): nessuna collisione possibile con l'import FC 26.
create sequence private.vivaio_fc_id_seq start with 900000000;

create table public.vivaio_prospetti (
  id bigint generated always as identity primary key,
  league_id bigint not null references public.leagues(id) on delete cascade,
  team_id bigint not null references public.teams(id) on delete cascade,
  player_id bigint not null references public.players(id),
  ingaggio bigint not null check (ingaggio >= 100000),
  entrata_stagione smallint not null,
  creato_il timestamptz not null default now(),
  unique (league_id, player_id)
);
comment on table public.vivaio_prospetti is
  'Prospetti UNDER vinti all''asta, in cantiera fuori dal conteggio rosa. entrata_stagione serve allo svincolo automatico a fine off-season se non promossi.';
create index vivaio_prospetti_team_idx on public.vivaio_prospetti(team_id);

create table public.under_auctions (
  id bigint generated always as identity primary key,
  league_id bigint not null references public.leagues(id) on delete cascade,
  player_id bigint not null references public.players(id),
  giorno date not null,
  tornata integer not null default 1,
  origine text not null default 'estrazione' check (origine in ('estrazione')),
  stato text not null default 'aperta' check (stato in ('aperta', 'assegnata', 'deserta')),
  vincitore_team_id bigint references public.teams(id),
  ingaggio_finale bigint,
  risolta_il timestamptz,
  creata_il timestamptz not null default now(),
  -- Scoperto testando: (league_id, player_id) da solo bloccherebbe per
  -- sempre un prospetto gia' passato in asta una volta, anche se
  -- rilasciato e rimesso sul mercato un altro giorno. Lo scoping giusto
  -- e' per giorno, esattamente come free_agent_auctions
  -- (free_agent_auctions_league_id_giorno_player_id_key).
  unique (league_id, giorno, player_id)
);
create index under_auctions_aperte_idx on public.under_auctions(league_id, giorno) where stato = 'aperta';

create table public.under_bids (
  id bigint generated always as identity primary key,
  auction_id bigint not null references public.under_auctions(id) on delete cascade,
  league_id bigint not null references public.leagues(id) on delete cascade,
  team_id bigint not null references public.teams(id) on delete cascade,
  ingaggio_offerto bigint not null check (ingaggio_offerto >= 100000),
  aggiornata_il timestamptz not null default now(),
  unique (auction_id, team_id)
);

create table private.under_auction_thresholds (
  auction_id bigint primary key references public.under_auctions(id) on delete cascade,
  soglia bigint not null
);

create table private.rilasci_vivaio_in_coda (
  league_id bigint not null references public.leagues(id) on delete cascade,
  player_id bigint not null references public.players(id),
  primary key (league_id, player_id)
);

alter table public.vivaio_prospetti enable row level security;
create policy vivaio_prospetti_lettura on public.vivaio_prospetti
  for select using ((select private.e_membro(league_id)));

alter table public.under_auctions enable row level security;
create policy under_auctions_lettura on public.under_auctions
  for select using ((select private.e_membro(league_id)));

alter table public.under_bids enable row level security;
create policy under_bids_lettura on public.under_bids
  for select using ((select private.e_mia_squadra(team_id)));

grant select on public.vivaio_prospetti to authenticated;
grant select on public.under_auctions to authenticated;
grant select on public.under_bids to authenticated;

-- ------------------------------------------------------------
--  Tetto ingaggi: estensione additiva. Le vecchie firme vanno tolte
--  esplicitamente prima di ricrearle con un parametro in piu', per non
--  lasciare due overload ambigui (vedi nota in testa al file).
-- ------------------------------------------------------------
create or replace function private.ingaggi_impegnati_vivaio(p_team_id bigint, p_escludi bigint default null)
returns bigint
language sql
stable
set search_path = ''
as $$
  select coalesce(sum(b.ingaggio_offerto), 0)::bigint
  from public.under_bids b
  join public.under_auctions a on a.id = b.auction_id
  where b.team_id = p_team_id
    and a.stato = 'aperta'
    and (p_escludi is null or b.auction_id <> p_escludi)
$$;

create or replace function private.monte_ingaggi(p_team_id bigint, p_stagione smallint)
returns bigint
language sql
stable
set search_path = ''
as $$
  select coalesce((
    select sum(ingaggio) from public.player_instances
    where team_id = p_team_id and not ritirato and contratto_scadenza >= p_stagione
  ), 0)::bigint
  + coalesce((
    select sum(ingaggio) from public.vivaio_prospetti where team_id = p_team_id
  ), 0)::bigint
$$;

drop function if exists private.capienza_residua(bigint, smallint, bigint);
create function private.capienza_residua(
  p_team_id bigint, p_stagione smallint,
  p_escludi_asta bigint default null, p_escludi_under bigint default null
)
returns bigint
language sql
stable
set search_path = ''
as $$
  select l.tetto_ingaggi
         - private.monte_ingaggi(p_team_id, p_stagione)
         - private.ingaggi_impegnati_aste(p_team_id, p_escludi_asta)
         - private.ingaggi_impegnati_vivaio(p_team_id, p_escludi_under)
  from public.teams t
  join public.leagues l on l.id = t.league_id
  where t.id = p_team_id
$$;

drop function if exists private.verifica_capienza(bigint, bigint, smallint, bigint);
create function private.verifica_capienza(
  p_team_id bigint, p_ingaggio bigint, p_stagione smallint,
  p_escludi_asta bigint default null, p_escludi_under bigint default null
)
returns void
language plpgsql
stable
set search_path = ''
as $$
declare
  v_residua bigint;
begin
  if p_ingaggio <= 0 then
    return;
  end if;

  v_residua := private.capienza_residua(p_team_id, p_stagione, p_escludi_asta, p_escludi_under);

  if v_residua < p_ingaggio then
    raise exception using errcode = '22023', message =
      'Fuori dal tetto ingaggi: servono ' || private.in_milioni(p_ingaggio)
      || ' M€ di spazio salariale per la stagione ' || p_stagione
      || ', ma ne restano ' || private.in_milioni(greatest(v_residua, 0)) || ' M€.';
  end if;
end;
$$;

-- ------------------------------------------------------------
--  Generatore di un prospetto UNDER: 15 anni, nome/nazionalita'
--  inventati, attributi coerenti con l'overall e il ruolo (stessa
--  logica a bias per reparto di tools/validazione/roster.js, non
--  copiata 1:1 perche' quella e' JS di test, qui serve SQL di
--  produzione).
-- ------------------------------------------------------------
create or replace function private.genera_prospetto_vivaio(p_macro_ruolo text)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_posizione text;
  v_overall smallint;
  v_potential smallint;
  v_nomi constant text[] := array['Liam','Noah','Mateo','Diego','Kai','Yusuf','Amir','Leon','Enzo','Theo',
    'Rayan','Elias','Adam','Milo','Nils','Ivo','Bruno','Mihail','Kofi','Chidi','Sami','Idris','Aron','Bram',
    'Jonas','Mats','Pablo','Rui','Tiago','Kwame'];
  v_cognomi constant text[] := array['Berg','Novak','Costa','Rossi','Diaby','Traore','Kovac','Larsen','Mendes',
    'Haddad','Silva','Krause','Petrov','Okafor','Sorensen','Almeida','Bakker','Lindqvist','Duarte','Ferreira',
    'Vukovic','Adeyemi','Marchetti','Hansen','Ribeiro','Sorland','Nakamura','Osei','Correia','Weiss'];
  v_nazionalita text;
  v_nome text;
  v_rep text;
  v_stamina smallint;
  v_finishing smallint;
  v_passing smallint;
  v_tackle smallint;
  v_dribbling smallint;
  v_gk smallint;
  v_id bigint;
begin
  v_posizione := case p_macro_ruolo
    when 'GK' then 'GK'
    when 'DEF' then (array['CB','LB','RB'])[1 + floor(random() * 3)::int]
    when 'MID' then (array['CDM','CM','CAM'])[1 + floor(random() * 3)::int]
    else (array['LW','RW','ST'])[1 + floor(random() * 3)::int]
  end;
  v_rep := case when v_posizione = 'GK' then 'GK'
    when v_posizione in ('CB','LB','RB') then 'DEF'
    when v_posizione in ('CDM','CM','CAM') then 'MID'
    else 'ATT' end;

  -- Quindicenni: overall basso, ancora tutto da dimostrare. Scelta mia,
  -- facile da ritarare: v_overall e' clampato 40-60 (40 e' il minimo
  -- ammesso dal vincolo players_overall_check).
  v_overall := greatest(40, least(60, round(46 + (random() - 0.5) * 18)))::smallint;
  -- Potenziale a coda lunga: la maggioranza resta modesta, pochi
  -- diventano davvero forti. E' quello che VIVAIO svela col tempo.
  v_potential := case
    when random() < 0.55 then round(v_overall + 8 + random() * 14)
    when random() < 0.88 then round(74 + random() * 10)
    else round(85 + random() * 9)
  end;
  v_potential := greatest(v_overall + 5, least(94, v_potential))::smallint;

  select nazionalita into v_nazionalita
  from public.players where nazionalita is not null order by random() limit 1;

  v_nome := v_nomi[1 + floor(random() * array_length(v_nomi, 1))::int]
    || ' ' || v_cognomi[1 + floor(random() * array_length(v_cognomi, 1))::int];

  v_stamina := greatest(35, least(85, round(60 + (random() - 0.5) * 24)))::smallint;
  v_finishing := greatest(15, least(80, round(v_overall + (case v_rep when 'ATT' then 4 when 'MID' then -6 else -20 end) + (random() - 0.5) * 14)))::smallint;
  v_passing := greatest(15, least(80, round(v_overall + (case v_rep when 'MID' then 4 when 'GK' then -22 else -3 end) + (random() - 0.5) * 14)))::smallint;
  v_tackle := greatest(15, least(80, round(v_overall + (case v_rep when 'DEF' then 5 when 'MID' then -3 else -22 end) + (random() - 0.5) * 14)))::smallint;
  v_dribbling := greatest(15, least(80, round(v_overall + (case v_rep when 'ATT' then 4 when 'MID' then 1 else -16 end) + (random() - 0.5) * 14)))::smallint;
  v_gk := case when v_rep = 'GK' then v_overall else 0 end;

  -- mentalita_bandiera/economia/vittorie NON vanno nell'insert: sono
  -- colonne generated (private.mentalita_ramo(id, ramo)), derivate in
  -- automatico dall'id appena assegnato — scoperto testando questa
  -- funzione, non era visibile dal solo information_schema.columns.
  insert into public.players (
    fc_id, nome, nazionalita, club, campionato, foto_url, overall, potential, eta,
    posizioni, piede, altezza, attributi, is_icon, is_regen, origine_vivaio,
    disponibile_estrazione, elite_globale
  ) values (
    nextval('private.vivaio_fc_id_seq'), v_nome, v_nazionalita, 'Vivaio', 'Vivaio', null,
    v_overall, v_potential, 15,
    array[v_posizione], case when random() < 0.78 then 'destro' else 'sinistro' end,
    round(168 + random() * 26)::smallint,
    jsonb_build_object(
      'stamina', v_stamina, 'finishing', v_finishing, 'short_passing', v_passing,
      'standing_tackle', v_tackle, 'dribbling', v_dribbling, 'gk', v_gk
    ),
    false, false, true,
    false, false
  )
  returning id into v_id;

  return v_id;
end;
$$;

-- ------------------------------------------------------------
--  Slot vivaio: massimi (dalla curva di gestione risorse) e
--  impegnati (in cantiera + offerte aperte, stessa logica di
--  private.slot_impegnati per gli svincolati).
-- ------------------------------------------------------------
create or replace function private.vivaio_slot_massimi(p_team_id bigint)
returns integer
language sql
stable
set search_path = ''
as $$
  select coalesce((
    select (private.effetti_ramo('vivaio', tr.livello_vivaio)->>'slot')::int
    from public.team_risorse tr where tr.team_id = p_team_id
  ), 1)
$$;

create or replace function private.vivaio_slot_impegnati(p_team_id bigint, p_escludi bigint default null)
returns integer
language sql
stable
set search_path = ''
as $$
  select
    (select count(*)::integer from public.vivaio_prospetti where team_id = p_team_id)
    + (select count(*)::integer from public.under_bids b
         join public.under_auctions a on a.id = b.auction_id
         where b.team_id = p_team_id and a.stato = 'aperta'
           and (p_escludi is null or b.auction_id <> p_escludi))
$$;

-- ------------------------------------------------------------
--  Estrazione giornaliera: 2 prospetti per macro-ruolo (8 al giorno),
--  piu' i rilasci in coda come extra garantiti.
-- ------------------------------------------------------------
create or replace function private.under_per_ruolo()
returns smallint language sql immutable set search_path = '' as $$ select 2::smallint $$;

create or replace function private.estrai_under_lega(p_league_id bigint, p_giorno date)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tornata integer;
  v_ruolo text;
  v_i integer;
  v_player_id bigint;
  v_creati integer := 0;
  v_liberato record;
begin
  select coalesce(max(a.tornata), 0) + 1 into v_tornata
  from public.under_auctions a
  where a.league_id = p_league_id and a.giorno = p_giorno;

  foreach v_ruolo in array array['GK','DEF','MID','ATT'] loop
    for v_i in 1..private.under_per_ruolo() loop
      v_player_id := private.genera_prospetto_vivaio(v_ruolo);
      insert into public.under_auctions (league_id, player_id, giorno, tornata)
      values (p_league_id, v_player_id, p_giorno, v_tornata);
      v_creati := v_creati + 1;
    end loop;
  end loop;

  for v_liberato in
    select player_id from private.rilasci_vivaio_in_coda where league_id = p_league_id
  loop
    insert into public.under_auctions (league_id, player_id, giorno, tornata)
    values (p_league_id, v_liberato.player_id, p_giorno, v_tornata)
    on conflict (league_id, giorno, player_id) do nothing;
    delete from private.rilasci_vivaio_in_coda
    where league_id = p_league_id and player_id = v_liberato.player_id;
    v_creati := v_creati + 1;
  end loop;

  return v_creati;
end;
$$;

create or replace function private.estrai_under()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ora time;
  v_oggi date;
  v_lega bigint;
  v_totale integer := 0;
begin
  v_ora := (now() at time zone 'Europe/Rome')::time;
  if not (v_ora >= time '23:30' and v_ora < time '23:45') then return 0; end if;
  v_oggi := (now() at time zone 'Europe/Rome')::date;
  for v_lega in select id from public.leagues where stato = 'stagione' and not mercato_bloccato loop
    v_totale := v_totale + private.estrai_under_lega(v_lega, v_oggi);
  end loop;
  return v_totale;
end;
$$;

-- ------------------------------------------------------------
--  Offerta, ritiro, risoluzione: stessa forma delle omologhe sul
--  mercato svincolati, con due differenze — minimo 0,1 M€ e verifica
--  sugli slot vivaio invece che sulla rosa massima.
-- ------------------------------------------------------------
create or replace function public.offri_per_under(p_auction_id bigint, p_ingaggio bigint)
returns public.under_bids
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_utente uuid := (select auth.uid());
  v_asta public.under_auctions;
  v_squadra public.teams;
  v_slot_max integer;
  v_slot_impegnati integer;
  v_offerta public.under_bids;
begin
  if v_utente is null then
    raise exception using errcode = '42501', message = 'Devi accedere per usare il mercato.';
  end if;

  select * into v_asta from public.under_auctions where id = p_auction_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Asta inesistente.';
  end if;
  if v_asta.stato <> 'aperta' then
    raise exception using errcode = '55000', message = 'Questa asta è già stata risolta.';
  end if;
  if not private.mercato_aperto_lega(v_asta.league_id) then
    raise exception using errcode = '55000',
      message = 'Il mercato è chiuso: si offre dalle 23:30 alle 21:00 o quando l''admin lo apre.';
  end if;

  select * into v_squadra from public.teams
  where league_id = v_asta.league_id and user_id = v_utente;
  if not found then
    raise exception using errcode = '42501', message = 'Non partecipi a questa lega.';
  end if;
  if p_ingaggio < 100000 then
    raise exception using errcode = '22023', message = 'L''ingaggio minimo per un prospetto UNDER è 0,1 M€.';
  end if;

  v_slot_max := private.vivaio_slot_massimi(v_squadra.id);
  v_slot_impegnati := private.vivaio_slot_impegnati(v_squadra.id, p_auction_id);
  if v_slot_impegnati + 1 > v_slot_max then
    raise exception using errcode = '22023',
      message = 'Non hai più slot vivaio liberi: ' || v_slot_impegnati || ' su ' || v_slot_max
                || '. Promuovi o libera un prospetto prima di offrire per un altro.';
  end if;

  perform private.verifica_capienza(
    v_squadra.id, p_ingaggio, private.stagione_contratto(v_asta.league_id),
    null, p_auction_id);

  insert into public.under_bids (auction_id, league_id, team_id, ingaggio_offerto)
  values (p_auction_id, v_asta.league_id, v_squadra.id, p_ingaggio)
  on conflict (auction_id, team_id) do update
    set ingaggio_offerto = excluded.ingaggio_offerto, aggiornata_il = now()
  returning * into v_offerta;
  return v_offerta;
end;
$$;

create or replace function public.ritira_offerta_under(p_auction_id bigint)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_utente uuid := (select auth.uid());
begin
  if v_utente is null then
    raise exception using errcode = '42501', message = 'Devi accedere per usare il mercato.';
  end if;
  delete from public.under_bids b
  using public.teams t
  where b.auction_id = p_auction_id
    and b.team_id = t.id
    and t.user_id = v_utente;
end;
$$;

create or replace function private.risolvi_aste_under_giorno(p_giorno date, p_league_id bigint default null)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_asta record;
  v_offerente record;
  v_soglia bigint;
  v_vincitore record;
  v_stagione smallint;
  v_nome text;
  v_assegnate integer := 0;
begin
  for v_asta in
    select a.* from public.under_auctions a
    where a.giorno = p_giorno and a.stato = 'aperta'
      and (p_league_id is null or a.league_id = p_league_id)
    order by a.id
    for update
  loop
    v_stagione := private.stagione_contratto(v_asta.league_id);
    select soglia into v_soglia from private.under_auction_thresholds where auction_id = v_asta.id;
    select p.nome into v_nome from public.players p where p.id = v_asta.player_id;

    v_vincitore := null;

    select b.* into v_vincitore
    from public.under_bids b
    where b.auction_id = v_asta.id
      and b.ingaggio_offerto >= v_soglia
      and private.vivaio_slot_impegnati(b.team_id, v_asta.id) < private.vivaio_slot_massimi(b.team_id)
      and private.capienza_residua(b.team_id, v_stagione, null, v_asta.id) >= b.ingaggio_offerto
    order by b.ingaggio_offerto desc, b.aggiornata_il asc, b.id asc
    limit 1;

    if v_vincitore.id is null then
      update public.under_auctions set stato = 'deserta', risolta_il = now() where id = v_asta.id;
    else
      insert into public.vivaio_prospetti (league_id, team_id, player_id, ingaggio, entrata_stagione)
      values (v_asta.league_id, v_vincitore.team_id, v_asta.player_id, v_vincitore.ingaggio_offerto, v_stagione);

      update public.under_auctions
      set stato = 'assegnata', vincitore_team_id = v_vincitore.team_id,
          ingaggio_finale = v_vincitore.ingaggio_offerto, risolta_il = now()
      where id = v_asta.id;

      perform private.notifica(
        (select user_id from public.teams where id = v_vincitore.team_id),
        v_asta.league_id, 'mercato_esito', 'Prospetto UNDER assegnato: ' || v_nome,
        'Entra in vivaio. Dovrai promuoverlo in prima squadra entro la fine dell''off-season, o tornerà sul mercato.',
        jsonb_build_object('vivaio', true)
      );
      v_assegnate := v_assegnate + 1;
    end if;

    for v_offerente in
      select b.team_id, t.user_id from public.under_bids b
      join public.teams t on t.id = b.team_id where b.auction_id = v_asta.id
    loop
      if v_vincitore.id is null or v_offerente.team_id <> v_vincitore.team_id then
        perform private.notifica(v_offerente.user_id, v_asta.league_id, 'mercato_asta',
          'Prospetto UNDER: ' || v_nome,
          case when v_vincitore.id is null then 'Nessuna offerta ha raggiunto la richiesta.'
          else 'Se l''è aggiudicato un''altra squadra.' end,
          jsonb_build_object('auction_id', v_asta.id));
      end if;
    end loop;
  end loop;
  return v_assegnate;
end;
$$;

create or replace function private.risolvi_aste_under()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_oggi date := (now() at time zone 'Europe/Rome')::date;
  v_giorno record;
  v_assegnate integer := 0;
begin
  if extract(hour from (now() at time zone 'Europe/Rome')) <> 21 then
    return 0;
  end if;
  for v_giorno in
    select distinct a.giorno from public.under_auctions a
    where a.stato = 'aperta' and a.giorno <= v_oggi
    order by a.giorno
  loop
    v_assegnate := v_assegnate + private.risolvi_aste_under_giorno(v_giorno.giorno);
  end loop;
  return v_assegnate;
end;
$$;

-- Soglia scoperta testando le aste UNDER: private.ingaggio_teorico ha un
-- pavimento di 0,5 M€ (adulti), che rendeva impossibile aggiudicarsi un
-- quindicenne offrendo il minimo di 0,1 M€. Serviva una formula
-- proporzionata ai giovanissimi, non quella dei professionisti.
create or replace function private.ingaggio_teorico_vivaio(p_overall smallint, p_eta smallint)
returns bigint
language sql
immutable
set search_path = ''
as $$
  -- Stessa forma a scaglioni di private.ingaggio_teorico, ma con un
  -- pavimento di 0,1 M€ e senza il moltiplicatore d'eta' (che parte da
  -- 16 anni e non copre i 15). Scelta mia: uso comunque il fattore piu'
  -- basso della fascia d'eta' originale (0.40), coerente con
  -- "giovanissimo, ancora da dimostrare".
  select greatest(100000::numeric, round((
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
    * 0.40
    * 10
  )) * 100000)::bigint
$$;

create or replace function private.crea_soglie_under()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into private.under_auction_thresholds (auction_id, soglia)
  select new.id, round(private.ingaggio_teorico_vivaio(p.overall, p.eta) * (0.85 + random() * 0.25))
  from public.players p where p.id = new.player_id
  on conflict (auction_id) do nothing;
  return new;
end;
$$;

create trigger under_auctions_soglia
after insert on public.under_auctions
for each row execute function private.crea_soglie_under();

-- ------------------------------------------------------------
--  Promozione in prima squadra e rilascio manuale (per liberare uno
--  slot senza aspettare la promozione).
-- ------------------------------------------------------------
create or replace function public.promuovi_vivaio(p_vivaio_id bigint)
returns public.player_instances
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_utente uuid := (select auth.uid());
  v_prospetto public.vivaio_prospetti;
  v_squadra public.teams;
  v_lega public.leagues;
  v_rosa integer;
  v_prossima integer;
  v_player public.players;
  v_istanza public.player_instances;
  v_ingaggio bigint;
begin
  if v_utente is null then
    raise exception using errcode = '42501', message = 'Devi accedere per gestire il vivaio.';
  end if;

  select * into v_prospetto from public.vivaio_prospetti where id = p_vivaio_id for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Prospetto non trovato.';
  end if;
  select * into v_squadra from public.teams where id = v_prospetto.team_id and user_id = v_utente;
  if not found then
    raise exception using errcode = '42501', message = 'Questo prospetto non è tuo.';
  end if;
  select * into v_lega from public.leagues where id = v_prospetto.league_id;
  if v_lega.stato <> 'stagione' then
    raise exception using errcode = '55000', message = 'Puoi promuovere un prospetto solo a stagione avviata.';
  end if;

  select count(*)::integer into v_rosa
  from public.player_instances where team_id = v_squadra.id and not ritirato;
  if v_rosa >= private.rosa_massima() then
    raise exception using errcode = '22023',
      message = 'La rosa è già al completo (' || private.rosa_massima() || '): libera un posto prima di promuovere.';
  end if;

  select min(f.giornata) into v_prossima
  from public.fixtures f where f.league_id = v_lega.id and f.stato = 'programmata';

  select * into v_player from public.players where id = v_prospetto.player_id;

  -- Il vivaio ha un pavimento di 0,1 M€ (giovanissimi), la rosa vera di
  -- 0,5 M€ (vincolo di database, per tutti): la promozione e' anche il
  -- primo contratto da professionista, si adegua al minimo se serve.
  -- Scoperto testando: senza questo adeguamento l'insert viola
  -- player_instances_ingaggio_check per qualunque prospetto preso vicino
  -- al minimo vivaio.
  v_ingaggio := greatest(500000, v_prospetto.ingaggio);

  -- L'adeguamento al minimo puo' far salire il monte ingaggi: il vivaio
  -- smette di contare per il suo vecchio valore, la rosa vera inizia a
  -- contare per quello nuovo (piu' alto, se c'e' stato l'adeguamento).
  -- Si verifica solo la differenza: il resto era gia' impegnato da
  -- quando l'asta UNDER e' stata vinta.
  perform private.verifica_capienza(
    v_squadra.id, v_ingaggio - v_prospetto.ingaggio, private.stagione_contratto(v_lega.id));

  -- giornata_acquisizione: la promozione vale come un nuovo acquisto ai
  -- fini del blocco 10 giornate (confermato dall'utente), esattamente
  -- come draft/asta/scambio.
  insert into public.player_instances
    (league_id, player_id, team_id, overall_corrente, eta_corrente, ingaggio, giornata_acquisizione)
  values
    (v_prospetto.league_id, v_prospetto.player_id, v_squadra.id,
     v_player.overall, v_player.eta, v_ingaggio, v_prossima)
  returning * into v_istanza;

  delete from public.vivaio_prospetti where id = v_prospetto.id;

  perform private.notifica(v_utente, v_lega.id, 'sistema', 'Prospetto promosso in prima squadra',
    v_player.nome || ' entra ufficialmente in rosa.',
    jsonb_build_object('player_instance_id', v_istanza.id));

  return v_istanza;
end;
$$;

create or replace function public.rilascia_vivaio(p_vivaio_id bigint)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_utente uuid := (select auth.uid());
  v_prospetto public.vivaio_prospetti;
begin
  if v_utente is null then
    raise exception using errcode = '42501', message = 'Devi accedere per gestire il vivaio.';
  end if;
  select * into v_prospetto from public.vivaio_prospetti where id = p_vivaio_id for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Prospetto non trovato.';
  end if;
  if not exists (select 1 from public.teams where id = v_prospetto.team_id and user_id = v_utente) then
    raise exception using errcode = '42501', message = 'Questo prospetto non è tuo.';
  end if;

  delete from public.vivaio_prospetti where id = v_prospetto.id;
  insert into private.rilasci_vivaio_in_coda (league_id, player_id)
  values (v_prospetto.league_id, v_prospetto.player_id)
  on conflict (league_id, player_id) do nothing;
end;
$$;

grant execute on function public.offri_per_under(bigint, bigint) to authenticated;
grant execute on function public.ritira_offerta_under(bigint) to authenticated;
grant execute on function public.promuovi_vivaio(bigint) to authenticated;
grant execute on function public.rilascia_vivaio(bigint) to authenticated;

commit;
