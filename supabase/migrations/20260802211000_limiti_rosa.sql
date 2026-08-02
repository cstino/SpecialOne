-- ============================================================
--  LIMITI PERMANENTI DELLA ROSA
--
--  slot_rosa resta l'obiettivo del draft iniziale. Durante la stagione
--  svincoli, scambi e aste possono far variare la rosa, ma mai fuori
--  dall'intervallo fisso 21-30 giocatori.
-- ============================================================

create or replace function private.rosa_minima()
returns integer
language sql
immutable
set search_path = ''
as $$
  select 21;
$$;

create or replace function private.rosa_massima()
returns integer
language sql
immutable
set search_path = ''
as $$
  select 30;
$$;

revoke all on function private.rosa_minima() from public, anon, authenticated;
revoke all on function private.rosa_massima() from public, anon, authenticated;

-- Le leghe storiche eventualmente configurate a 20 adottano il nuovo minimo
-- anche come obiettivo del draft. Le leghe gia' a 21-30 restano invariate.
update public.leagues
set slot_rosa = private.rosa_minima()
where slot_rosa < private.rosa_minima();

alter table public.leagues
  drop constraint if exists leagues_slot_rosa_check;

alter table public.leagues
  add constraint leagues_slot_rosa_check
  check (slot_rosa between 21 and 30);

comment on column public.leagues.slot_rosa is
  'Obiettivo del draft iniziale, configurabile tra 21 e 30. In stagione la rosa puo'' variare tra 21 e 30 giocatori.';

-- Creazione lega: anche il server accetta soltanto un draft da 21-30.
create or replace function public.crea_lega(
  p_nome_lega text,
  p_nome_squadra text,
  p_stemma_url text,
  p_n_squadre smallint,
  p_n_gironi smallint,
  p_budget_iniziale bigint,
  p_reroll_draft smallint,
  p_slot_rosa smallint,
  p_portieri_minimi smallint,
  p_campionati_attivi text[]
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_league public.leagues;
  v_team public.teams;
  v_codice text;
  v_campionati_validi constant text[] := array[
    'Premier League', 'La Liga', 'Serie A', 'Bundesliga', 'Ligue 1',
    'Eredivisie', 'Liga Portugal', 'Süper Lig', 'Saudi Pro League',
    'EFL Championship'
  ];
  v_tentativi smallint := 0;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'Devi accedere prima di creare una lega.';
  end if;

  p_nome_lega := trim(p_nome_lega);
  p_nome_squadra := trim(p_nome_squadra);

  if length(p_nome_lega) not between 3 and 60 then
    raise exception using errcode = '22023', message = 'Il nome della lega deve avere da 3 a 60 caratteri.';
  end if;
  if length(p_nome_squadra) not between 2 and 40 then
    raise exception using errcode = '22023', message = 'Il nome della squadra deve avere da 2 a 40 caratteri.';
  end if;
  if p_n_squadre not between 4 and 20
    or p_n_gironi not between 2 and 6
    or p_budget_iniziale not between 50000000 and 200000000
    or p_reroll_draft not between 0 and 30
    or p_slot_rosa not between private.rosa_minima() and private.rosa_massima()
    or p_portieri_minimi not between 2 and 4 then
    raise exception using errcode = '22023', message = 'Una o più impostazioni della lega non sono valide.';
  end if;
  if p_portieri_minimi > p_slot_rosa then
    raise exception using errcode = '22023', message = 'I portieri minimi superano gli slot rosa.';
  end if;
  if coalesce(cardinality(p_campionati_attivi), 0) = 0
    or not (p_campionati_attivi <@ v_campionati_validi)
    or cardinality(p_campionati_attivi) <> cardinality(array(select distinct unnest(p_campionati_attivi))) then
    raise exception using errcode = '22023', message = 'Seleziona almeno un campionato valido, senza duplicati.';
  end if;
  if not private.stemma_valido(p_stemma_url, v_user_id) then
    raise exception using errcode = '22023', message = 'Lo stemma selezionato non è valido.';
  end if;

  loop
    v_tentativi := v_tentativi + 1;
    v_codice := private.genera_codice_invito();
    begin
      insert into public.leagues (
        nome, admin_id, codice_invito, n_squadre, n_gironi,
        budget_iniziale, reroll_draft, slot_rosa, portieri_minimi,
        campionati_attivi
      ) values (
        p_nome_lega, v_user_id, v_codice, p_n_squadre, p_n_gironi,
        p_budget_iniziale, p_reroll_draft, p_slot_rosa, p_portieri_minimi,
        p_campionati_attivi
      ) returning * into v_league;
      exit;
    exception when unique_violation then
      if v_tentativi >= 10 then
        raise exception 'Impossibile generare un codice invito univoco.';
      end if;
    end;
  end loop;

  insert into public.teams (
    league_id, user_id, nome, stemma_url, budget, reroll_rimasti
  ) values (
    v_league.id, v_user_id, p_nome_squadra, p_stemma_url,
    v_league.budget_iniziale, v_league.reroll_draft
  ) returning * into v_team;

  insert into public.transactions (
    league_id, team_id, tipo, importo, descrizione, saldo_dopo
  ) values (
    v_league.id, v_team.id, 'dotazione_iniziale', v_league.budget_iniziale,
    'Dotazione iniziale della lega', v_league.budget_iniziale
  );

  return jsonb_build_object(
    'league_id', v_league.id,
    'team_id', v_team.id,
    'codice_invito', v_league.codice_invito
  );
end;
$$;

revoke all on function public.crea_lega(text, text, text, smallint, smallint, bigint, smallint, smallint, smallint, text[]) from public, anon, authenticated;
grant execute on function public.crea_lega(text, text, text, smallint, smallint, bigint, smallint, smallint, smallint, text[]) to authenticated;

-- Scambi: entrambe le rose devono restare tra 21 e 30.
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

  if v_rosa_da > private.rosa_massima() or v_rosa_a > private.rosa_massima() then
    raise exception using errcode = '22023',
      message = 'Lo scambio porterebbe una rosa oltre i 30 giocatori.';
  end if;
  -- Il mercato non puo' lasciare nessuna delle due squadre sotto il
  -- minimo permanente di rosa.
  if v_rosa_da < private.rosa_minima() or v_rosa_a < private.rosa_minima() then
    raise exception using errcode = '22023',
      message = 'Lo scambio lascerebbe una rosa sotto i 21 giocatori.';
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

-- Contatore mercato: gli slot liberi sono calcolati sul massimo permanente.
create or replace function public.budget_disponibile(p_league_id bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_squadra public.teams;
  v_lega    public.leagues;
  v_rosa    integer;
begin
  select * into v_squadra from public.teams
  where league_id = p_league_id and user_id = (select auth.uid());
  if not found then
    raise exception using errcode = '42501', message = 'Non partecipi a questa lega.';
  end if;

  select * into v_lega from public.leagues where id = p_league_id;
  select count(*) into v_rosa from public.player_instances where team_id = v_squadra.id;

  return jsonb_build_object(
    'budget',            v_squadra.budget,
    'impegnato',         private.budget_impegnato(v_squadra.id),
    'disponibile',       v_squadra.budget - private.budget_impegnato(v_squadra.id),
    'rosa',              v_rosa,
    'slot_impegnati',    private.slot_impegnati(v_squadra.id),
    'slot_liberi',       private.rosa_massima() - v_rosa - private.slot_impegnati(v_squadra.id)
  );
end;
$$;

revoke all on function public.budget_disponibile(bigint) from public, anon;
grant execute on function public.budget_disponibile(bigint) to authenticated;

-- Aste: anche le offerte aperte prenotano uno dei 30 posti.
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
                || ' M€ sono gia'' impegnati in altre offerte, te ne restano '
                || private.in_milioni(v_squadra.budget - v_impegnato)
                || ' M€ e questa ne richiede ' || private.in_milioni(v_prorata) || ' M€.';
  end if;

  insert into public.free_agent_bids (auction_id, league_id, team_id, ingaggio_offerto)
  values (p_auction_id, v_asta.league_id, v_squadra.id, p_ingaggio)
  on conflict (auction_id, team_id) do update
    set ingaggio_offerto = excluded.ingaggio_offerto, aggiornata_il = now()
  returning * into v_offerta;

  return v_offerta;
end;
$$;

-- Stessa cura nelle notifiche d'asta persa, che avevano la stessa divisione.

revoke all on function public.offri_per_svincolato(bigint, bigint) from public, anon, authenticated;
grant execute on function public.offri_per_svincolato(bigint, bigint) to authenticated;

-- Svincolo: la rosa residua non puo' scendere sotto 21.
create or replace function public.svincola_giocatore(p_instance_id bigint)
returns public.player_instances
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_utente      uuid := (select auth.uid());
  v_istanza     public.player_instances;
  v_squadra     public.teams;
  v_lega        public.leagues;
  v_giocatore   public.players;
  v_rosa        integer;
  v_portieri    integer;
  v_prossima    integer;
  v_form_tolte  integer := 0;
  v_nota        text := '';
begin
  if v_utente is null then
    raise exception using errcode = '42501', message = 'Devi accedere per svincolare un giocatore.';
  end if;

  -- Prima lettura per individuare la squadra. La riga viene ricontrollata
  -- dopo il lock: fra le due operazioni uno scambio potrebbe averla mossa.
  select * into v_istanza
  from public.player_instances
  where id = p_instance_id;

  if not found then
    raise exception using errcode = 'P0002', message = 'Giocatore inesistente.';
  end if;

  select * into v_squadra
  from public.teams
  where id = v_istanza.team_id
    and user_id = v_utente;

  if not found then
    raise exception using errcode = '42501', message = 'Questo giocatore non appartiene alla tua squadra.';
  end if;

  -- Tutte le operazioni che cambiano una rosa serializzano sulla squadra.
  -- Dopo il lock si ricontrolla la proprieta' dell'istanza.
  perform 1 from public.teams where id = v_squadra.id for update;
  select * into v_istanza
  from public.player_instances
  where id = p_instance_id
    and team_id = v_squadra.id
  for update;

  if not found then
    raise exception using errcode = '55000', message = 'Il giocatore non e'' piu'' nella tua rosa.';
  end if;

  select * into v_lega from public.leagues where id = v_istanza.league_id;
  if v_lega.stato <> 'stagione' then
    raise exception using errcode = '55000', message = 'Puoi svincolare giocatori solo durante la stagione.';
  end if;

  if not private.mercato_aperto() then
    raise exception using errcode = '55000',
      message = 'Il mercato e'' chiuso: puoi svincolare dalle 07:00 alle 21:00.';
  end if;

  -- Si contano direttamente i giocatori che resterebbero, cosi' il controllo
  -- non dipende dal ruolo del giocatore svincolato calcolato a parte.
  select count(*), count(*) filter (where p.posizioni[1] = 'GK')
    into v_rosa, v_portieri
  from public.player_instances pi
  join public.players p on p.id = pi.player_id
  where pi.team_id = v_squadra.id
    and pi.id <> v_istanza.id;

  if v_rosa < private.rosa_minima() then
    raise exception using errcode = '22023',
      message = 'Non puoi scendere sotto i 21 giocatori in rosa.';
  end if;
  if v_portieri < v_lega.portieri_minimi then
    raise exception using errcode = '22023',
      message = 'Non puoi scendere sotto il minimo di portieri della lega.';
  end if;

  select * into v_giocatore from public.players where id = v_istanza.player_id;

  -- Una formazione che contiene il giocatore non rappresenta piu' una scelta
  -- valida dell'utente. Si cancellano solo le giornate ancora da simulare.
  select min(f.giornata) into v_prossima
  from public.fixtures f
  where f.league_id = v_lega.id
    and f.stato = 'programmata';

  if v_prossima is not null then
    delete from public.lineups
    where league_id = v_lega.id
      and team_id = v_squadra.id
      and giornata >= v_prossima
      and (
        titolari && array[v_istanza.id]::bigint[]
        or panchina && array[v_istanza.id]::bigint[]
        or tribuna && array[v_istanza.id]::bigint[]
      );
    get diagnostics v_form_tolte = row_count;
  end if;

  update public.player_instances
  set team_id = null
  where id = v_istanza.id
  returning * into v_istanza;

  if v_form_tolte > 0 then
    v_nota := ' La formazione delle prossime giornate va salvata di nuovo.';
  end if;

  perform private.notifica(
    v_utente,
    v_lega.id,
    'mercato_esito',
    'Giocatore svincolato',
    v_giocatore.nome || ' non fa piu'' parte della tua rosa.' || v_nota,
    jsonb_build_object('player_instance_id', v_istanza.id, 'player_id', v_istanza.player_id)
  );

  return v_istanza;
end;
$$;

comment on function public.svincola_giocatore(bigint) is
  'Svincola un proprio giocatore senza rimborso, preservando i minimi di rosa e portieri (design §9.5).';

revoke all on function public.svincola_giocatore(bigint) from public, anon, authenticated;
grant execute on function public.svincola_giocatore(bigint) to authenticated;

-- ------------------------------------------------------------
--  Rientro dello svincolato tramite asta
--
--  Un giocatore svincolato conserva la propria istanza di lega. Il resolver
--  precedente provava sempre a inserirne una nuova e urtava il vincolo
--  unique (league_id, player_id). L'upsert riusa l'istanza solo se e'
--  ancora libera; se nel frattempo e' stata assegnata, l'intera risoluzione
--  fallisce senza addebitare budget o segnare l'asta come conclusa.
-- ------------------------------------------------------------


-- Resolver aste: ricontrollo finale del massimo prima dell'assegnazione.
create or replace function private.risolvi_aste_giorno(p_giorno date)
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_asta              record;
  v_soglia            bigint;
  v_vincitore         record;
  v_lega              public.leagues;
  v_prorata           bigint;
  v_nome              text;
  v_assegnate         integer := 0;
  v_istanze_assegnate integer;
  v_off               record;
begin
  for v_asta in
    select a.* from public.free_agent_auctions a
    where a.giorno = p_giorno and a.stato = 'aperta'
    order by a.id
    for update
  loop
    select * into v_lega from public.leagues where id = v_asta.league_id;
    select soglia into v_soglia from private.auction_thresholds where auction_id = v_asta.id;
    select p.nome into v_nome from public.players p where p.id = v_asta.player_id;

    v_vincitore := null;

    select b.* into v_vincitore
    from public.free_agent_bids b
    join public.teams t on t.id = b.team_id
    where b.auction_id = v_asta.id
      and b.ingaggio_offerto >= v_soglia
      and (select count(*) from public.player_instances pi where pi.team_id = b.team_id)
          < private.rosa_massima()
      and t.budget >= round(b.ingaggio_offerto::numeric
                            * private.giornate_rimanenti(v_lega.id)
                            / greatest(v_lega.giornate_totali, 1))
    order by b.ingaggio_offerto desc, b.aggiornata_il asc, b.id asc
    limit 1;

    if v_vincitore.id is null then
      update public.free_agent_auctions
      set stato = 'deserta', risolta_il = now()
      where id = v_asta.id;
    else
      v_prorata := round(v_vincitore.ingaggio_offerto::numeric
                         * private.giornate_rimanenti(v_lega.id)
                         / greatest(v_lega.giornate_totali, 1));

      insert into public.player_instances as pi
        (league_id, player_id, team_id, overall_corrente, eta_corrente, ingaggio)
      select v_asta.league_id, p.id, v_vincitore.team_id, p.overall, p.eta,
             v_vincitore.ingaggio_offerto
      from public.players p where p.id = v_asta.player_id
      on conflict (league_id, player_id) do update
        set team_id = excluded.team_id,
            ingaggio = excluded.ingaggio
        where pi.team_id is null;
      get diagnostics v_istanze_assegnate = row_count;

      if v_istanze_assegnate <> 1 then
        raise exception using errcode = '55000',
          message = 'Il giocatore non e'' piu'' disponibile per questa asta.';
      end if;

      update public.teams set budget = budget - v_prorata where id = v_vincitore.team_id;

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
               (select nome from public.teams where id = v_vincitore.team_id) ||
               ' per ' || private.in_milioni(v_vincitore.ingaggio_offerto) || ' M€.'
        end,
        jsonb_build_object('asta_id', v_asta.id)
      );
    end loop;
  end loop;

  return v_assegnate;
end;
$$;

revoke all on function private.risolvi_aste_giorno(date) from public, anon, authenticated;
grant execute on function private.risolvi_aste_giorno(date) to service_role;
