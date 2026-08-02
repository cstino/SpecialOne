-- ============================================================
--  MERCATO — TRATTATIVE FRA SQUADRE  (design §9.1, §9.2, §9.3, §5.4)
--
--  Le tre forme di proposta di §9.2 stanno in una tabella sola:
--    acquisto secco  → offerti = {},  richiesti = {X}, conguaglio > 0
--    scambio         → offerti = {A}, richiesti = {B}, conguaglio = 0
--    con conguaglio  → offerti = {A}, richiesti = {B}, conguaglio <> 0
--  Il conguaglio e' con segno: positivo = paga il proponente, negativo =
--  paga il destinatario. Serve per «ti do il mio campione, tu dammi una
--  riserva piu' del denaro».
--
--  FINESTRA (design §9.1, chiusura spostata alle 21:00 il 2 agosto 2026).
--  Non c'e' nessuno stato «mercato aperto» sul database e nessun cron che lo
--  apre: e' una funzione che guarda l'ora di Roma. Uno stato memorizzato puo'
--  restare disallineato se un job salta; un orario calcolato no. Il cron
--  delle 21:00 serve solo a far scadere quello che e' rimasto appeso.
-- ============================================================

-- ------------------------------------------------------------
--  Finestra e conti economici
-- ------------------------------------------------------------

create or replace function private.mercato_aperto()
returns boolean
language sql
stable
set search_path = ''
as $$
  -- Europe/Rome esplicito, mai il fuso del server (CLAUDE.md §2).
  select (now() at time zone 'Europe/Rome')::time >= time '07:00'
     and (now() at time zone 'Europe/Rome')::time <  time '21:00';
$$;

comment on function private.mercato_aperto() is
  'Vero fra le 07:00 e le 21:00 ora di Roma (design §9.1).';

-- Quante giornate restano da giocare: e' il moltiplicatore dell'ingaggio
-- pro-rata di design §5.4.
create or replace function private.giornate_rimanenti(p_league_id bigint)
returns integer
language sql
stable
set search_path = ''
as $$
  select count(distinct f.giornata)::integer
  from public.fixtures f
  where f.league_id = p_league_id
    and f.stato = 'programmata';
$$;

-- ------------------------------------------------------------
--  Proposte
-- ------------------------------------------------------------

create table public.trade_proposals (
  id                  bigint generated always as identity primary key,
  league_id           bigint not null references public.leagues (id) on delete cascade,
  da_team_id          bigint not null,
  a_team_id           bigint not null,

  -- id di player_instances, non di players: si scambia l'istanza di lega.
  giocatori_offerti   bigint[] not null default '{}',
  giocatori_richiesti bigint[] not null default '{}',

  conguaglio          bigint not null default 0,
  messaggio           text check (char_length(messaggio) between 1 and 240),

  stato               text not null default 'in_attesa'
                      check (stato in ('in_attesa','accettata','rifiutata','ritirata','scaduta')),

  creata_il           timestamptz not null default now(),
  -- design §9.2: le proposte scadono alla chiusura del mercato del giorno.
  scade_il            timestamptz not null,
  risolta_il          timestamptz,

  constraint trade_squadre_diverse check (da_team_id <> a_team_id),
  constraint trade_non_vuota
    check (cardinality(giocatori_offerti) + cardinality(giocatori_richiesti) > 0),

  -- La coppia (id, league_id) e' unica su teams: cosi' il database garantisce
  -- che le due squadre stiano nella stessa lega, senza fidarsi della RPC.
  constraint trade_da_team_fk foreign key (da_team_id, league_id)
    references public.teams (id, league_id) on delete cascade,
  constraint trade_a_team_fk foreign key (a_team_id, league_id)
    references public.teams (id, league_id) on delete cascade
);

create index trade_proposals_destinatario_idx
  on public.trade_proposals (a_team_id, stato, creata_il desc);
create index trade_proposals_mittente_idx
  on public.trade_proposals (da_team_id, stato, creata_il desc);
create index trade_proposals_lega_idx
  on public.trade_proposals (league_id, stato, risolta_il desc);
-- Il cron delle 21:00 cerca solo le pendenti scadute.
create index trade_proposals_da_scadere_idx
  on public.trade_proposals (scade_il)
  where stato = 'in_attesa';

comment on table public.trade_proposals is
  'Proposte di mercato fra squadre (design §9.2). Concluse = pubbliche (design §9.3).';

alter table public.trade_proposals enable row level security;

-- Le pendenti le vedono solo le due squadre coinvolte: sapere che un
-- avversario sta trattando per un giocatore e' gia' un vantaggio.
-- Le concluse le vedono tutti, ed e' voluto (design §9.3): in un gruppo di
-- amici la collusione e' inevitabile e l'unico deterrente e' la visibilita'.
create policy trade_proposals_lettura on public.trade_proposals
  for select to authenticated
  using (
    (select private.e_mia_squadra(da_team_id))
    or (select private.e_mia_squadra(a_team_id))
    or (stato = 'accettata' and (select private.e_membro(league_id)))
  );

grant select on table public.trade_proposals to authenticated;
grant select, insert, update, delete on table public.trade_proposals to service_role;

-- ============================================================
--  PROPORRE
-- ============================================================

create or replace function public.proponi_scambio(
  p_a_team_id           bigint,
  p_giocatori_offerti   bigint[] default '{}',
  p_giocatori_richiesti bigint[] default '{}',
  p_conguaglio          bigint   default 0,
  p_messaggio           text     default null
)
returns public.trade_proposals
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_utente     uuid := (select auth.uid());
  v_dest       public.teams;
  v_mia        public.teams;
  v_lega       public.leagues;
  v_offerti    bigint[] := coalesce(p_giocatori_offerti, '{}');
  v_richiesti  bigint[] := coalesce(p_giocatori_richiesti, '{}');
  v_n          integer;
  v_scadenza   timestamptz;
  v_proposta   public.trade_proposals;
  v_utente_dest uuid;
begin
  if v_utente is null then
    raise exception using errcode = '42501', message = 'Devi accedere per usare il mercato.';
  end if;

  select * into v_dest from public.teams where id = p_a_team_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Squadra destinataria inesistente.';
  end if;

  select * into v_mia from public.teams
  where league_id = v_dest.league_id and user_id = v_utente;
  if not found then
    raise exception using errcode = '42501', message = 'Non partecipi a questa lega.';
  end if;
  if v_mia.id = v_dest.id then
    raise exception using errcode = '22023', message = 'Non puoi proporre uno scambio a te stesso.';
  end if;

  select * into v_lega from public.leagues where id = v_dest.league_id;
  if v_lega.stato <> 'stagione' then
    raise exception using errcode = '55000', message = 'Il mercato apre a stagione iniziata.';
  end if;
  if not private.mercato_aperto() then
    raise exception using errcode = '55000',
      message = 'Il mercato e'' chiuso: si tratta dalle 07:00 alle 21:00.';
  end if;

  if cardinality(v_offerti) + cardinality(v_richiesti) = 0 then
    raise exception using errcode = '22023', message = 'Una proposta deve contenere almeno un giocatore.';
  end if;

  -- Nessun doppione dentro la stessa lista, e nessun giocatore su entrambe.
  if cardinality(array(select distinct unnest(v_offerti))) <> cardinality(v_offerti)
     or cardinality(array(select distinct unnest(v_richiesti))) <> cardinality(v_richiesti)
     or v_offerti && v_richiesti then
    raise exception using errcode = '22023', message = 'Un giocatore compare due volte nella proposta.';
  end if;

  -- I giocatori offerti devono essere miei, quelli richiesti suoi. Il
  -- controllo si rifa' identico all'accettazione: fra le due cose possono
  -- passare ore e un altro scambio.
  select count(*) into v_n from public.player_instances
  where id = any(v_offerti) and team_id = v_mia.id and league_id = v_lega.id;
  if v_n <> cardinality(v_offerti) then
    raise exception using errcode = '22023', message = 'Stai offrendo un giocatore che non e'' tuo.';
  end if;

  select count(*) into v_n from public.player_instances
  where id = any(v_richiesti) and team_id = v_dest.id and league_id = v_lega.id;
  if v_n <> cardinality(v_richiesti) then
    raise exception using errcode = '22023', message = 'Stai chiedendo un giocatore che non e'' di quella squadra.';
  end if;

  -- Verifica di cortesia: se gia' ora non puoi coprire il conguaglio, la
  -- proposta non ha senso. Quella che conta e' comunque all'accettazione.
  if p_conguaglio > 0 and v_mia.budget < p_conguaglio then
    raise exception using errcode = '22023', message = 'Non hai il budget per questo conguaglio.';
  end if;

  -- Scadenza: le 21:00 di oggi a Roma. Calcolata cosi' l'ora legale non la
  -- sposta, perche' il fuso e' applicato alla data locale e non a un offset.
  v_scadenza := (date_trunc('day', now() at time zone 'Europe/Rome') + interval '21 hours')
                at time zone 'Europe/Rome';

  insert into public.trade_proposals
    (league_id, da_team_id, a_team_id, giocatori_offerti, giocatori_richiesti,
     conguaglio, messaggio, scade_il)
  values
    (v_lega.id, v_mia.id, v_dest.id, v_offerti, v_richiesti,
     coalesce(p_conguaglio, 0), nullif(btrim(coalesce(p_messaggio, '')), ''), v_scadenza)
  returning * into v_proposta;

  select user_id into v_utente_dest from public.teams where id = v_dest.id;
  perform private.notifica(
    v_utente_dest, v_lega.id, 'mercato_proposta',
    'Proposta di mercato da ' || v_mia.nome,
    case
      when cardinality(v_offerti) = 0 then 'Offerta d''acquisto. Scade alle 21:00.'
      when cardinality(v_richiesti) = 0 then 'Ti offre giocatori. Scade alle 21:00.'
      else 'Proposta di scambio. Scade alle 21:00.'
    end,
    jsonb_build_object('proposta_id', v_proposta.id)
  );

  return v_proposta;
end;
$$;

revoke all on function public.proponi_scambio(bigint, bigint[], bigint[], bigint, text)
  from public, anon;
grant execute on function public.proponi_scambio(bigint, bigint[], bigint[], bigint, text)
  to authenticated;

-- ============================================================
--  RISPONDERE
--
--  Il cuore economico. Design §5.4 vuole che chi acquista a stagione in corso
--  paghi «costo trasferimento + ingaggio pro-rata sulle giornate rimanenti».
--  Preso alla lettera, pero', quel pro-rata sparirebbe dalla lega: il
--  venditore l'ingaggio pieno l'ha gia' pagato al draft, e §5.3 dice che i
--  trasferimenti sono a somma zero e non alterano la massa monetaria.
--
--  Qui si applica l'unica lettura coerente con entrambe: chi riceve un
--  giocatore ne paga il pro-rata, chi lo cede se lo vede **accreditato**.
--  La somma dei due saldi e' esattamente zero, verificato piu' sotto.
-- ============================================================

create or replace function public.rispondi_a_proposta(
  p_proposta_id bigint,
  p_accetta     boolean
)
returns public.trade_proposals
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_utente      uuid := (select auth.uid());
  v_p           public.trade_proposals;
  v_lega        public.leagues;
  v_da          public.teams;
  v_a           public.teams;
  v_rimanenti   integer;
  v_prorata_off bigint;
  v_prorata_ric bigint;
  v_saldo_da    bigint;
  v_saldo_a     bigint;
  v_n           integer;
  v_rosa_da     integer;
  v_rosa_a      integer;
  v_gk_da       integer;
  v_gk_a        integer;
  v_prossima    integer;
  v_tutti       bigint[];
  v_form_tolte  integer := 0;
  v_nota        text := '';
begin
  if v_utente is null then
    raise exception using errcode = '42501', message = 'Devi accedere per usare il mercato.';
  end if;

  -- Lock sulla proposta: due tocchi sul pulsante non devono eseguirla due volte.
  select * into v_p from public.trade_proposals where id = p_proposta_id for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Proposta inesistente.';
  end if;

  if not (select private.e_mia_squadra(v_p.a_team_id)) then
    raise exception using errcode = '42501', message = 'Questa proposta non e'' indirizzata a te.';
  end if;
  if v_p.stato <> 'in_attesa' then
    raise exception using errcode = '55000', message = 'Questa proposta e'' gia'' stata risolta.';
  end if;
  if now() >= v_p.scade_il then
    raise exception using errcode = '55000', message = 'Questa proposta e'' scaduta.';
  end if;

  -- Rifiuto: nessun conto da fare.
  if not coalesce(p_accetta, false) then
    update public.trade_proposals
    set stato = 'rifiutata', risolta_il = now()
    where id = v_p.id
    returning * into v_p;

    perform private.notifica(
      (select user_id from public.teams where id = v_p.da_team_id),
      v_p.league_id, 'mercato_esito', 'Proposta rifiutata',
      (select nome from public.teams where id = v_p.a_team_id) || ' ha rifiutato la tua proposta.',
      jsonb_build_object('proposta_id', v_p.id)
    );
    return v_p;
  end if;

  if not private.mercato_aperto() then
    raise exception using errcode = '55000',
      message = 'Il mercato e'' chiuso: si conclude dalle 07:00 alle 21:00.';
  end if;

  select * into v_lega from public.leagues where id = v_p.league_id;

  -- Lock sulle due squadre in ordine di id: due scambi incrociati simultanei
  -- che prendessero i lock in ordine opposto si bloccherebbero a vicenda.
  perform 1 from public.teams
  where id in (v_p.da_team_id, v_p.a_team_id)
  order by id
  for update;

  select * into v_da from public.teams where id = v_p.da_team_id;
  select * into v_a  from public.teams where id = v_p.a_team_id;

  -- Ricontrollo della proprieta': fra proposta e accettazione uno dei
  -- giocatori puo' essere finito in un altro scambio.
  select count(*) into v_n from public.player_instances
  where id = any(v_p.giocatori_offerti) and team_id = v_da.id;
  if v_n <> cardinality(v_p.giocatori_offerti) then
    raise exception using errcode = '55000',
      message = 'Un giocatore offerto non e'' piu'' in quella rosa: la proposta non e'' piu'' valida.';
  end if;

  select count(*) into v_n from public.player_instances
  where id = any(v_p.giocatori_richiesti) and team_id = v_a.id;
  if v_n <> cardinality(v_p.giocatori_richiesti) then
    raise exception using errcode = '55000',
      message = 'Un giocatore richiesto non e'' piu'' nella tua rosa: la proposta non e'' piu'' valida.';
  end if;

  -- --- Conti (design §5.4, corretto per la somma zero di §5.3) ---
  v_rimanenti := private.giornate_rimanenti(v_lega.id);

  select coalesce(sum(round(pi.ingaggio::numeric * v_rimanenti
                            / greatest(v_lega.giornate_totali, 1))), 0)::bigint
    into v_prorata_off
  from public.player_instances pi where pi.id = any(v_p.giocatori_offerti);

  select coalesce(sum(round(pi.ingaggio::numeric * v_rimanenti
                            / greatest(v_lega.giornate_totali, 1))), 0)::bigint
    into v_prorata_ric
  from public.player_instances pi where pi.id = any(v_p.giocatori_richiesti);

  -- Chi cede incassa il pro-rata che non dovra' piu' sostenere, chi riceve
  -- lo paga. Piu' il conguaglio, che e' un trasferimento puro.
  v_saldo_da := -v_p.conguaglio + v_prorata_off - v_prorata_ric;
  v_saldo_a  :=  v_p.conguaglio + v_prorata_ric - v_prorata_off;

  if v_saldo_da + v_saldo_a <> 0 then
    raise exception using errcode = 'XX000',
      message = 'Errore interno: lo scambio non e'' a somma zero.';
  end if;

  if v_da.budget + v_saldo_da < 0 then
    raise exception using errcode = '22023',
      message = 'La squadra proponente non ha budget sufficiente.';
  end if;
  if v_a.budget + v_saldo_a < 0 then
    raise exception using errcode = '22023',
      message = 'Non hai budget sufficiente per questo scambio.';
  end if;

  -- --- Vincoli di rosa (design §4.5, §9.2): validi per ENTRAMBE ---
  select count(*), count(*) filter (where p.posizioni[1] = 'GK')
    into v_rosa_da, v_gk_da
  from public.player_instances pi join public.players p on p.id = pi.player_id
  where pi.team_id = v_da.id;

  select count(*), count(*) filter (where p.posizioni[1] = 'GK')
    into v_rosa_a, v_gk_a
  from public.player_instances pi join public.players p on p.id = pi.player_id
  where pi.team_id = v_a.id;

  v_rosa_da := v_rosa_da - cardinality(v_p.giocatori_offerti) + cardinality(v_p.giocatori_richiesti);
  v_rosa_a  := v_rosa_a  - cardinality(v_p.giocatori_richiesti) + cardinality(v_p.giocatori_offerti);

  select v_gk_da
       - (select count(*) from public.player_instances pi join public.players p on p.id = pi.player_id
          where pi.id = any(v_p.giocatori_offerti) and p.posizioni[1] = 'GK')
       + (select count(*) from public.player_instances pi join public.players p on p.id = pi.player_id
          where pi.id = any(v_p.giocatori_richiesti) and p.posizioni[1] = 'GK')
    into v_gk_da;

  select v_gk_a
       - (select count(*) from public.player_instances pi join public.players p on p.id = pi.player_id
          where pi.id = any(v_p.giocatori_richiesti) and p.posizioni[1] = 'GK')
       + (select count(*) from public.player_instances pi join public.players p on p.id = pi.player_id
          where pi.id = any(v_p.giocatori_offerti) and p.posizioni[1] = 'GK')
    into v_gk_a;

  if v_rosa_da > v_lega.slot_rosa or v_rosa_a > v_lega.slot_rosa then
    raise exception using errcode = '22023',
      message = 'Lo scambio porterebbe una rosa oltre il numero di slot.';
  end if;
  -- Sotto gli undici non si scende: il motore non sa schierare una rosa
  -- incompleta e la giornata fallirebbe.
  if v_rosa_da < 11 or v_rosa_a < 11 then
    raise exception using errcode = '22023',
      message = 'Lo scambio lascerebbe una rosa sotto gli undici giocatori.';
  end if;
  if v_gk_da < v_lega.portieri_minimi or v_gk_a < v_lega.portieri_minimi then
    raise exception using errcode = '22023',
      message = 'Lo scambio lascerebbe una squadra sotto il minimo di portieri.';
  end if;

  -- --- Esecuzione ---
  update public.player_instances set team_id = v_a.id
  where id = any(v_p.giocatori_offerti);
  update public.player_instances set team_id = v_da.id
  where id = any(v_p.giocatori_richiesti);

  update public.teams set budget = budget + v_saldo_da where id = v_da.id;
  update public.teams set budget = budget + v_saldo_a  where id = v_a.id;

  -- Registro append-only. `importo <> 0` e' un CHECK: uno scambio alla pari
  -- fra giocatori di pari ingaggio non produce movimento e non va scritto.
  if v_saldo_da <> 0 then
    insert into public.transactions (league_id, team_id, tipo, importo, descrizione, saldo_dopo)
    values (v_lega.id, v_da.id, 'mercato_scambio', v_saldo_da,
            'Scambio con ' || v_a.nome, v_da.budget + v_saldo_da);
  end if;
  if v_saldo_a <> 0 then
    insert into public.transactions (league_id, team_id, tipo, importo, descrizione, saldo_dopo)
    values (v_lega.id, v_a.id, 'mercato_scambio', v_saldo_a,
            'Scambio con ' || v_da.nome, v_a.budget + v_saldo_a);
  end if;

  -- Le formazioni gia' salvate che contengono un giocatore appena passato di
  -- mano vanno rifatte. La Edge Function sa rimpiazzare un ceduto, ma
  -- schiererebbe una scelta del computer al posto di una scelta dell'utente.
  select min(f.giornata) into v_prossima
  from public.fixtures f where f.league_id = v_lega.id and f.stato = 'programmata';

  v_tutti := v_p.giocatori_offerti || v_p.giocatori_richiesti;
  if v_prossima is not null then
    delete from public.lineups
    where league_id = v_lega.id
      and team_id in (v_da.id, v_a.id)
      and giornata >= v_prossima
      and (titolari && v_tutti or panchina && v_tutti or tribuna && v_tutti);
    get diagnostics v_form_tolte = row_count;
  end if;
  if v_form_tolte > 0 then
    v_nota := ' Controlla la formazione: era schierato un giocatore coinvolto.';
  end if;

  update public.trade_proposals
  set stato = 'accettata', risolta_il = now()
  where id = v_p.id
  returning * into v_p;

  perform private.notifica(
    v_da.user_id, v_lega.id, 'mercato_esito', 'Scambio concluso con ' || v_a.nome,
    'La tua proposta e'' stata accettata.' || v_nota,
    jsonb_build_object('proposta_id', v_p.id)
  );
  perform private.notifica(
    v_a.user_id, v_lega.id, 'mercato_esito', 'Scambio concluso con ' || v_da.nome,
    'Hai accettato la proposta.' || v_nota,
    jsonb_build_object('proposta_id', v_p.id)
  );

  return v_p;
end;
$$;

revoke all on function public.rispondi_a_proposta(bigint, boolean) from public, anon;
grant execute on function public.rispondi_a_proposta(bigint, boolean) to authenticated;

-- ============================================================
--  RITIRARE
-- ============================================================

create or replace function public.ritira_proposta(p_proposta_id bigint)
returns public.trade_proposals
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_p public.trade_proposals;
begin
  if (select auth.uid()) is null then
    raise exception using errcode = '42501', message = 'Devi accedere per usare il mercato.';
  end if;

  select * into v_p from public.trade_proposals where id = p_proposta_id for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Proposta inesistente.';
  end if;
  if not (select private.e_mia_squadra(v_p.da_team_id)) then
    raise exception using errcode = '42501', message = 'Non e'' una tua proposta.';
  end if;
  if v_p.stato <> 'in_attesa' then
    raise exception using errcode = '55000', message = 'Questa proposta e'' gia'' stata risolta.';
  end if;

  update public.trade_proposals
  set stato = 'ritirata', risolta_il = now()
  where id = v_p.id
  returning * into v_p;

  perform private.notifica(
    (select user_id from public.teams where id = v_p.a_team_id),
    v_p.league_id, 'mercato_esito', 'Proposta ritirata',
    (select nome from public.teams where id = v_p.da_team_id) || ' ha ritirato la sua proposta.',
    jsonb_build_object('proposta_id', v_p.id)
  );

  return v_p;
end;
$$;

revoke all on function public.ritira_proposta(bigint) from public, anon;
grant execute on function public.ritira_proposta(bigint) to authenticated;

-- ============================================================
--  CHIUSURA DELLE 21:00
--
--  Stesso schema del cron notturno: il job gira ogni ora e la funzione
--  decide se a Roma sono davvero le 21:00. pg_cron pianifica in UTC, e un
--  orario fisso in UTC sarebbe l'ora sbagliata per meta' anno.
-- ============================================================

create or replace function private.chiudi_mercato_giornaliero()
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_scadute integer := 0;
  v_p       record;
begin
  if extract(hour from (now() at time zone 'Europe/Rome')) <> 21 then
    return 0;
  end if;

  for v_p in
    select tp.id, tp.league_id, tp.da_team_id, tp.a_team_id
    from public.trade_proposals tp
    where tp.stato = 'in_attesa'
      and tp.scade_il <= now()
    for update
  loop
    update public.trade_proposals
    set stato = 'scaduta', risolta_il = now()
    where id = v_p.id;

    -- Si avvisa solo il proponente: al destinatario e' gia' arrivata la
    -- notifica della proposta, e una seconda per dirgli che non ha risposto
    -- sarebbe rumore.
    perform private.notifica(
      (select user_id from public.teams where id = v_p.da_team_id),
      v_p.league_id, 'mercato_esito', 'Proposta scaduta',
      'Il mercato ha chiuso senza una risposta da '
        || (select nome from public.teams where id = v_p.a_team_id) || '.',
      jsonb_build_object('proposta_id', v_p.id)
    );
    v_scadute := v_scadute + 1;
  end loop;

  return v_scadute;
end;
$$;

revoke all on function private.chiudi_mercato_giornaliero() from public, anon, authenticated;
grant execute on function private.chiudi_mercato_giornaliero() to service_role;

select cron.schedule(
  'chiusura-mercato',
  '5 * * * *',
  $cron$select private.chiudi_mercato_giornaliero();$cron$
);
