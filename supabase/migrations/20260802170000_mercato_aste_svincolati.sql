-- ============================================================
--  MERCATO — ASTE A BUSTA CHIUSA SUGLI SVINCOLATI  (design §9.4)
--
--  Ogni giorno alle 07:00 il sistema estrae N svincolati, con almeno 3 under
--  20. Ogni squadra puo' fare **una** offerta per giocatore, in ingaggio
--  annuale. Alle 21:00 vince l'offerta piu' alta sopra una soglia nascosta;
--  a parita' si sorteggia. Nessuna squadra puo' vincere piu' di 3 aste al
--  giorno.
--
--  LA SOGLIA NON DEVE ESSERE LEGGIBILE. La RLS filtra le righe, non le
--  colonne: se la soglia stesse in `free_agent_auctions` chiunque possa
--  leggere l'asta la leggerebbe, e offrirebbe sempre un euro sopra. Sta
--  quindi in una tabella dello schema `private`, che PostgREST non espone.
--
--  IL NUMERO DI ESTRATTI E' UN PARAMETRO, non un 10 scritto nel codice:
--  durante la settimana di off-season diventa 20 (design §10.6).
-- ============================================================

create table public.free_agent_auctions (
  id                bigint generated always as identity primary key,
  league_id         bigint not null references public.leagues (id) on delete cascade,

  -- Data di Roma, non del server: e' la chiave con cui si riconosce
  -- l'estrazione di oggi e si evita di rifarla due volte.
  giorno            date not null,

  -- Dal catalogo, non da player_instances: un giocatore mai draftato non ha
  -- una riga di istanza, e la riga nasce solo se qualcuno vince l'asta.
  player_id         bigint not null references public.players (id) on delete restrict,
  ingaggio_teorico  bigint not null,

  stato             text not null default 'aperta'
                    check (stato in ('aperta','assegnata','deserta')),
  vincitore_team_id bigint references public.teams (id) on delete set null,
  ingaggio_finale   bigint,
  risolta_il        timestamptz,
  creata_il         timestamptz not null default now(),

  unique (league_id, giorno, player_id)
);

create index free_agent_auctions_giorno_idx
  on public.free_agent_auctions (league_id, giorno desc, id);
create index free_agent_auctions_aperte_idx
  on public.free_agent_auctions (league_id) where stato = 'aperta';

comment on table public.free_agent_auctions is
  'Estrazione giornaliera di svincolati all''asta (design §9.4). La soglia sta in private.';

-- La soglia di accettazione del giocatore. Fuori da `public` di proposito.
create table private.auction_thresholds (
  auction_id bigint primary key
             references public.free_agent_auctions (id) on delete cascade,
  soglia     bigint not null
);

comment on table private.auction_thresholds is
  'Soglia nascosta delle aste. In private perche'' PostgREST espone solo public.';

create table public.free_agent_bids (
  id               bigint generated always as identity primary key,
  auction_id       bigint not null references public.free_agent_auctions (id) on delete cascade,
  league_id        bigint not null,
  team_id          bigint not null,
  -- Floor di design §5.1: nessun ingaggio sotto 0,5 M€.
  ingaggio_offerto bigint not null check (ingaggio_offerto >= 500000),
  creata_il        timestamptz not null default now(),

  -- design §9.4: una offerta per giocatore per squadra.
  unique (auction_id, team_id),

  constraint bids_team_league_fk foreign key (team_id, league_id)
    references public.teams (id, league_id) on delete cascade
);

create index free_agent_bids_asta_idx on public.free_agent_bids (auction_id);
create index free_agent_bids_squadra_idx on public.free_agent_bids (team_id);

-- ------------------------------------------------------------
--  RLS
-- ------------------------------------------------------------

alter table public.free_agent_auctions enable row level security;
alter table public.free_agent_bids     enable row level security;

create policy free_agent_auctions_lettura on public.free_agent_auctions
  for select to authenticated
  using ((select private.e_membro(league_id)));

-- **Busta chiusa**: si vede solo la propria offerta, sempre. Anche dopo la
-- risoluzione: cio' che viene rivelato e' chi ha preso chi, non quanto
-- avevano offerto gli altri.
create policy free_agent_bids_lettura on public.free_agent_bids
  for select to authenticated
  using ((select private.e_mia_squadra(team_id)));

-- I GRANT vanno scritti a mano: dal 2 agosto le default privileges di questo
-- schema non concedono piu' nulla, e una tabella nuova nasce chiusa.
grant select on table public.free_agent_auctions to authenticated;
grant select on table public.free_agent_bids     to authenticated;
grant select, insert, update, delete on table public.free_agent_auctions to service_role;
grant select, insert, update, delete on table public.free_agent_bids     to service_role;

-- ============================================================
--  QUANTI SE NE ESTRAGGONO
-- ============================================================

create or replace function private.svincolati_da_estrarre(p_league_id bigint)
returns integer
language sql
stable
set search_path = ''
as $$
  -- design §9.4: dieci al giorno. design §10.6: venti nella settimana di
  -- off-season. Lo stato 'offseason' non esiste ancora nel CHECK di
  -- `leagues.stato`: il ramo e' scritto ora perche' la regola e' gia' decisa
  -- e perche' cosi' non resta un 10 sparso nel codice da ritrovare.
  select case when l.stato = 'offseason' then 20 else 10 end
  from public.leagues l where l.id = p_league_id;
$$;

revoke all on function private.svincolati_da_estrarre(bigint) from public, anon, authenticated;
grant execute on function private.svincolati_da_estrarre(bigint) to service_role;

-- ============================================================
--  ESTRAZIONE DELLE 07:00
-- ============================================================

create or replace function private.estrai_svincolati()
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_oggi    date;
  v_lega    record;
  v_quanti  integer;
  v_estratti integer := 0;
  v_asta    record;
begin
  if extract(hour from (now() at time zone 'Europe/Rome')) <> 7 then
    return 0;
  end if;

  v_oggi := (now() at time zone 'Europe/Rome')::date;

  for v_lega in
    select l.id, l.campionati_attivi
    from public.leagues l
    where l.stato = 'stagione'
      -- Guardia contro la doppia estrazione: il job gira ogni ora.
      and not exists (
        select 1 from public.free_agent_auctions a
        where a.league_id = l.id and a.giorno = v_oggi
      )
  loop
    v_quanti := private.svincolati_da_estrarre(v_lega.id);

    -- Pool: chi non ha un'istanza in questa lega, piu' chi ce l'ha ma e'
    -- svincolato. Le istanze nascono solo al pick o alla vittoria di un'asta,
    -- quindi la stragrande maggioranza del catalogo non ha alcuna riga.
    with disponibili as (
      select p.id, p.eta
      from public.players p
      where p.campionato = any(v_lega.campionati_attivi)
        and not exists (
          select 1 from public.player_instances pi
          where pi.league_id = v_lega.id
            and pi.player_id = p.id
            and pi.team_id is not null
        )
    ),
    -- design §9.4: almeno 3 under 20. Si prendono prima quelli, poi il resto,
    -- altrimenti un sorteggio uniforme su 5.000 nomi non ne pescherebbe quasi
    -- mai tre giovani.
    giovani as (
      select id from disponibili where eta < 20 order by random() limit 3
    ),
    resto as (
      select id from disponibili
      where id not in (select id from giovani)
      order by random()
      limit greatest(v_quanti - (select count(*) from giovani), 0)
    ),
    scelti as (
      select id from giovani union all select id from resto
    )
    insert into public.free_agent_auctions (league_id, giorno, player_id, ingaggio_teorico)
    select v_lega.id, v_oggi, p.id, private.ingaggio_teorico(p.overall, p.eta)
    from public.players p join scelti s on s.id = p.id;

    -- Soglia nascosta: ingaggio teorico per uniform(0.90, 1.10), design §9.4.
    for v_asta in
      select a.id, a.ingaggio_teorico
      from public.free_agent_auctions a
      where a.league_id = v_lega.id and a.giorno = v_oggi
    loop
      insert into private.auction_thresholds (auction_id, soglia)
      values (v_asta.id, round(v_asta.ingaggio_teorico * (0.90 + random() * 0.20)))
      on conflict (auction_id) do nothing;
      v_estratti := v_estratti + 1;
    end loop;
  end loop;

  return v_estratti;
end;
$$;

revoke all on function private.estrai_svincolati() from public, anon, authenticated;
grant execute on function private.estrai_svincolati() to service_role;

-- ============================================================
--  OFFRIRE
-- ============================================================

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
  v_utente    uuid := (select auth.uid());
  v_asta      public.free_agent_auctions;
  v_lega      public.leagues;
  v_squadra   public.teams;
  v_rosa      integer;
  v_prorata   bigint;
  v_offerta   public.free_agent_bids;
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
  if not private.mercato_aperto() then
    raise exception using errcode = '55000',
      message = 'Il mercato e'' chiuso: si offre dalle 07:00 alle 21:00.';
  end if;

  select * into v_lega from public.leagues where id = v_asta.league_id;
  select * into v_squadra from public.teams
  where league_id = v_asta.league_id and user_id = v_utente;
  if not found then
    raise exception using errcode = '42501', message = 'Non partecipi a questa lega.';
  end if;

  if p_ingaggio < 500000 then
    raise exception using errcode = '22023', message = 'L''ingaggio minimo e'' 0,5 M€.';
  end if;

  -- Slot: non si offre per un giocatore che non entrerebbe in rosa.
  select count(*) into v_rosa
  from public.player_instances where team_id = v_squadra.id;
  if v_rosa >= v_lega.slot_rosa then
    raise exception using errcode = '22023', message = 'La tua rosa e'' gia'' al completo.';
  end if;

  -- Solvibilita' sul pro-rata, come per gli acquisti (design §5.4).
  v_prorata := round(p_ingaggio::numeric * private.giornate_rimanenti(v_lega.id)
                     / greatest(v_lega.giornate_totali, 1));
  if v_squadra.budget < v_prorata then
    raise exception using errcode = '22023',
      message = 'Non hai budget per sostenere questo ingaggio fino a fine stagione.';
  end if;

  -- Si puo' correggere la propria offerta fino alla chiusura: e' pur sempre
  -- una busta chiusa, perche' nessuno vede quelle altrui.
  insert into public.free_agent_bids (auction_id, league_id, team_id, ingaggio_offerto)
  values (p_auction_id, v_asta.league_id, v_squadra.id, p_ingaggio)
  on conflict (auction_id, team_id) do update
    set ingaggio_offerto = excluded.ingaggio_offerto, creata_il = now()
  returning * into v_offerta;

  return v_offerta;
end;
$$;

revoke all on function public.offri_per_svincolato(bigint, bigint) from public, anon;
grant execute on function public.offri_per_svincolato(bigint, bigint) to authenticated;

create or replace function public.ritira_offerta(p_auction_id bigint)
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_squadra bigint;
  v_tolte   integer;
begin
  select t.id into v_squadra
  from public.teams t
  join public.free_agent_auctions a on a.league_id = t.league_id
  where a.id = p_auction_id and t.user_id = (select auth.uid());
  if v_squadra is null then
    raise exception using errcode = '42501', message = 'Non partecipi a questa lega.';
  end if;
  if not private.mercato_aperto() then
    raise exception using errcode = '55000', message = 'Il mercato e'' chiuso.';
  end if;

  delete from public.free_agent_bids
  where auction_id = p_auction_id and team_id = v_squadra;
  get diagnostics v_tolte = row_count;
  return v_tolte;
end;
$$;

revoke all on function public.ritira_offerta(bigint) from public, anon;
grant execute on function public.ritira_offerta(bigint) to authenticated;

-- ============================================================
--  RISOLUZIONE DELLE 21:00
--
--  Il vincolo «massimo 3 aste al giorno per squadra» rende l'assegnazione
--  sequenziale: chi ha gia' vinto tre volte esce dalla contesa per le aste
--  successive. Si procede quindi asta per asta, in ordine di id.
-- ============================================================

create or replace function private.risolvi_aste()
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_oggi      date;
  v_asta      record;
  v_soglia    bigint;
  v_vincitore record;
  v_lega      public.leagues;
  v_prorata   bigint;
  v_nome      text;
  v_assegnate integer := 0;
  v_off       record;
begin
  if extract(hour from (now() at time zone 'Europe/Rome')) <> 21 then
    return 0;
  end if;

  v_oggi := (now() at time zone 'Europe/Rome')::date;

  for v_asta in
    select a.* from public.free_agent_auctions a
    where a.giorno = v_oggi and a.stato = 'aperta'
    order by a.id
    for update
  loop
    select * into v_lega from public.leagues where id = v_asta.league_id;
    select soglia into v_soglia from private.auction_thresholds where auction_id = v_asta.id;
    select p.nome into v_nome from public.players p where p.id = v_asta.player_id;

    v_prorata := 0;

    -- L'offerta piu' alta sopra soglia, fra le squadre ancora ammissibili.
    -- A parita' si sorteggia (design §9.4), da cui il random() nell'ordine.
    select b.* into v_vincitore
    from public.free_agent_bids b
    join public.teams t on t.id = b.team_id
    where b.auction_id = v_asta.id
      and b.ingaggio_offerto >= v_soglia
      -- design §9.4: non piu' di 3 aste vinte nello stesso giorno.
      and (select count(*) from public.free_agent_auctions a2
           where a2.league_id = v_asta.league_id and a2.giorno = v_oggi
             and a2.vincitore_team_id = b.team_id) < 3
      -- La rosa deve poterlo accogliere, e il budget sostenerlo: fra
      -- l'offerta e adesso la squadra puo' aver comprato altrove.
      and (select count(*) from public.player_instances pi where pi.team_id = b.team_id)
          < v_lega.slot_rosa
      and t.budget >= round(b.ingaggio_offerto::numeric
                            * private.giornate_rimanenti(v_lega.id)
                            / greatest(v_lega.giornate_totali, 1))
    order by b.ingaggio_offerto desc, random()
    limit 1;

    if v_vincitore.id is null then
      -- design §9.4: se nessuna offerta supera la soglia il giocatore torna
      -- nel pool, cioe' potra' essere riestratto un altro giorno.
      update public.free_agent_auctions
      set stato = 'deserta', risolta_il = now()
      where id = v_asta.id;
    else
      v_prorata := round(v_vincitore.ingaggio_offerto::numeric
                         * private.giornate_rimanenti(v_lega.id)
                         / greatest(v_lega.giornate_totali, 1));

      insert into public.player_instances
        (league_id, player_id, team_id, overall_corrente, eta_corrente, ingaggio)
      select v_asta.league_id, p.id, v_vincitore.team_id, p.overall, p.eta,
             v_vincitore.ingaggio_offerto
      from public.players p where p.id = v_asta.player_id;

      update public.teams set budget = budget - v_prorata
      where id = v_vincitore.team_id;

      if v_prorata <> 0 then
        insert into public.transactions
          (league_id, team_id, tipo, importo, descrizione, saldo_dopo)
        select v_asta.league_id, v_vincitore.team_id, 'asta_svincolato', -v_prorata,
               'Asta vinta: ' || v_nome,
               (select budget from public.teams where id = v_vincitore.team_id);
      end if;

      update public.free_agent_auctions
      set stato = 'assegnata', vincitore_team_id = v_vincitore.team_id,
          ingaggio_finale = v_vincitore.ingaggio_offerto, risolta_il = now()
      where id = v_asta.id;

      v_assegnate := v_assegnate + 1;
    end if;

    -- Chi ha offerto viene avvisato comunque: sapere di aver perso e' meta'
    -- dell'informazione che serve per l'asta del giorno dopo.
    for v_off in
      select b.team_id, t.user_id from public.free_agent_bids b
      join public.teams t on t.id = b.team_id
      where b.auction_id = v_asta.id
    loop
      perform private.notifica(
        v_off.user_id, v_asta.league_id, 'mercato_asta',
        case when v_vincitore.id is not null and v_off.team_id = v_vincitore.team_id
             then 'Asta vinta: ' || v_nome
             else 'Asta persa: ' || v_nome end,
        case
          when v_vincitore.id is null then 'Nessuna offerta ha raggiunto la richiesta del giocatore.'
          when v_off.team_id = v_vincitore.team_id then 'Entra in rosa con un contratto di un anno.'
          else 'Se l''e'' aggiudicato ' ||
               (select nome from public.teams where id = v_vincitore.team_id) || '.'
        end,
        jsonb_build_object('asta_id', v_asta.id)
      );
    end loop;
  end loop;

  return v_assegnate;
end;
$$;

revoke all on function private.risolvi_aste() from public, anon, authenticated;
grant execute on function private.risolvi_aste() to service_role;

-- ============================================================
--  Pianificazione: stessa forma degli altri job, ogni ora, e' la funzione
--  a decidere se a Roma e' l'ora giusta.
-- ============================================================

select cron.schedule(
  'estrazione-svincolati',
  '2 * * * *',
  $cron$select private.estrai_svincolati();$cron$
);

select cron.schedule(
  'risoluzione-aste',
  '3 * * * *',
  $cron$select private.risolvi_aste();$cron$
);
