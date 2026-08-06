-- ============================================================
--  MERCATO: apertura spostata da 07:00 a 23:30 (design §9.1)
--
--  Richiesta dell'utente, 7 agosto 2026: il mercato deve aprire subito dopo
--  le partite (simulate alle 23:00, non a mezzanotte come si potrebbe
--  pensare) invece che aspettare fino al mattino dopo. Nuovo ciclo
--  giornaliero: chiusura 21:00 -> partite 23:00 -> apertura 23:30.
--
--  In piu', tre bug reali trovati mentre si toccava questa parte:
--
--  1. svincola_giocatore, proponi_scambio e rispondi_a_proposta chiamavano
--     tutte private.mercato_aperto() (solo l'orario fisso), non
--     private.mercato_aperto_lega(league_id) (che considera anche
--     l'apertura manuale dell'admin, private.mercato_override_admin). Solo
--     offri_per_svincolato/offri_per_svincolato_archivio/ritira_offerta
--     usavano gia' la versione corretta. Effetto pratico segnalato
--     dall'utente: l'admin apre il mercato a mano, e le aste sugli
--     svincolati si sbloccano ma svincolare un giocatore o proporre uno
--     scambio no -- stesso identico bug, tre punti diversi.
--
--  2. L'estrazione di nuovi svincolati (private.estrai_svincolati) era
--     agganciata all'apertura vecchia (ora=7 esatta, un solo controllo
--     l'ora nel cron orario). Ora segue la stessa apertura delle 23:30.
--     Con un cron che gira una volta all'ora non si puo' intercettare un
--     confine a mezz'ora: il job passa a girare 4 volte l'ora (ogni 15
--     minuti) e la guardia diventa una finestra di 15 minuti (23:30-23:45)
--     anziche' un'ora esatta, cosi' scatta una volta sola al giorno anche
--     col fuso che scivola con l'ora legale (CLAUDE.md §2).
--
--  La chiusura resta 21:00, invariata su richiesta esplicita dell'utente.
-- ============================================================

-- ------------------------------------------------------------
--  Finestra di trattativa: aperta da 23:30 a 21:00 del giorno dopo.
--  L'intervallo scavalca la mezzanotte, quindi il confronto e' un OR:
--  aperto se l'ora e' oltre le 23:30 OPPURE prima delle 21:00 (che insieme
--  coprono tutto tranne i 90 minuti fra 21:00 e 22:30... anzi 23:30).
--  Chiuso solo nella finestra 21:00-23:30, le due ore e mezza in cui si
--  chiude il mercato, si vedono i risultati e si sistema la formazione.
-- ------------------------------------------------------------

create or replace function private.mercato_aperto()
returns boolean
language sql
stable
set search_path = ''
as $$
  select (now() at time zone 'Europe/Rome')::time >= time '23:30'
      or (now() at time zone 'Europe/Rome')::time <  time '21:00';
$$;

create or replace function private.mercato_aperto_lega(p_league_id bigint)
returns boolean
language sql
stable security definer
set search_path = ''
as $$
  select (
    (
      (now() at time zone 'Europe/Rome')::time >= time '23:30'
      or (now() at time zone 'Europe/Rome')::time <  time '21:00'
    )
    or exists (
      select 1 from private.mercato_override_admin o
      where o.league_id = p_league_id
        and o.giorno = (now() at time zone 'Europe/Rome')::date
    )
  );
$$;

-- ------------------------------------------------------------
--  Estrazione: stessa apertura, finestra di 15 minuti per il nuovo cron
--  a quattro giri l'ora (vedi fondo file).
-- ------------------------------------------------------------

create or replace function private.estrai_svincolati()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_oggi     date;
  v_ora      time;
  v_lega     bigint;
  v_estratti integer := 0;
begin
  v_ora := (now() at time zone 'Europe/Rome')::time;
  if not (v_ora >= time '23:30' and v_ora < time '23:45') then
    return 0;
  end if;

  v_oggi := (now() at time zone 'Europe/Rome')::date;

  for v_lega in select l.id from public.leagues l where l.stato = 'stagione'
  loop
    v_estratti := v_estratti + private.estrai_svincolati_lega(v_lega, v_oggi);
  end loop;

  return v_estratti;
end;
$$;

-- ------------------------------------------------------------
--  Fix sistemico: le tre RPC che controllavano il solo orario fisso ora
--  rispettano anche l'apertura manuale dell'admin, come le aste.
-- ------------------------------------------------------------

create or replace function public.svincola_giocatore(p_instance_id bigint)
returns player_instances
language plpgsql
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

  if not private.mercato_aperto_lega(v_lega.id) then
    raise exception using errcode = '55000',
      message = 'Il mercato e'' chiuso: puoi svincolare dalle 23:30 alle 21:00, o quando l''admin lo apre.';
  end if;

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
  set team_id = null,
      ritirato = case when v_istanza.ritiro_annunciato then true else ritirato end
  where id = v_istanza.id
  returning * into v_istanza;

  if v_istanza.ritiro_annunciato then
    insert into public.retired_players(league_id, player_id, stagione)
    values (v_lega.id, v_istanza.player_id, v_lega.stagione_corrente)
    on conflict do nothing;
  end if;

  if v_form_tolte > 0 then
    v_nota := ' La formazione delle prossime giornate va salvata di nuovo.';
  end if;

  perform private.notifica(
    v_utente,
    v_lega.id,
    'mercato_esito',
    'Giocatore svincolato',
    v_giocatore.nome || (case when v_istanza.ritiro_annunciato
      then ' aveva gia'' annunciato il ritiro: la carriera termina qui, non torna disponibile.'
      else ' non fa piu'' parte della tua rosa.' end) || v_nota,
    jsonb_build_object('player_instance_id', v_istanza.id, 'player_id', v_istanza.player_id)
  );

  return v_istanza;
end;
$$;

create or replace function public.proponi_scambio(
  p_a_team_id bigint,
  p_giocatori_offerti bigint[] default '{}'::bigint[],
  p_giocatori_richiesti bigint[] default '{}'::bigint[],
  p_conguaglio bigint default 0,
  p_messaggio text default null::text
) returns trade_proposals
language plpgsql
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
  if not private.mercato_aperto_lega(v_lega.id) then
    raise exception using errcode = '55000',
      message = 'Il mercato e'' chiuso: si tratta dalle 23:30 alle 21:00, o quando l''admin lo apre.';
  end if;

  if cardinality(v_offerti) + cardinality(v_richiesti) = 0 then
    raise exception using errcode = '22023', message = 'Una proposta deve contenere almeno un giocatore.';
  end if;

  if cardinality(array(select distinct unnest(v_offerti))) <> cardinality(v_offerti)
     or cardinality(array(select distinct unnest(v_richiesti))) <> cardinality(v_richiesti)
     or v_offerti && v_richiesti then
    raise exception using errcode = '22023', message = 'Un giocatore compare due volte nella proposta.';
  end if;

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

  if exists (
    select 1 from public.player_instances
    where id = any(v_offerti || v_richiesti) and ritiro_annunciato
  ) then
    raise exception using errcode = '55000',
      message = 'Uno dei giocatori coinvolti ha annunciato il ritiro: non puo'' essere ceduto in questa stagione.';
  end if;

  if p_conguaglio > 0 and v_mia.budget < p_conguaglio then
    raise exception using errcode = '22023', message = 'Non hai il budget per questo conguaglio.';
  end if;

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

create or replace function public.rispondi_a_proposta(p_proposta_id bigint, p_accetta boolean)
returns trade_proposals
language plpgsql
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

  if not private.mercato_aperto_lega(v_p.league_id) then
    raise exception using errcode = '55000',
      message = 'Il mercato e'' chiuso: si conclude dalle 23:30 alle 21:00, o quando l''admin lo apre.';
  end if;

  select * into v_lega from public.leagues where id = v_p.league_id;

  perform 1 from public.teams
  where id in (v_p.da_team_id, v_p.a_team_id)
  order by id
  for update;

  select * into v_da from public.teams where id = v_p.da_team_id;
  select * into v_a  from public.teams where id = v_p.a_team_id;

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

  if exists (
    select 1 from public.player_instances
    where id = any(v_p.giocatori_offerti || v_p.giocatori_richiesti) and ritiro_annunciato
  ) then
    raise exception using errcode = '55000',
      message = 'Uno dei giocatori coinvolti ha annunciato il ritiro: la proposta non e'' piu'' valida.';
  end if;

  v_rimanenti := private.giornate_rimanenti(v_lega.id);

  select coalesce(sum(round(pi.ingaggio::numeric * v_rimanenti
                            / greatest(v_lega.giornate_totali, 1))), 0)::bigint
    into v_prorata_off
  from public.player_instances pi where pi.id = any(v_p.giocatori_offerti);

  select coalesce(sum(round(pi.ingaggio::numeric * v_rimanenti
                            / greatest(v_lega.giornate_totali, 1))), 0)::bigint
    into v_prorata_ric
  from public.player_instances pi where pi.id = any(v_p.giocatori_richiesti);

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
  if v_rosa_da < private.rosa_minima() or v_rosa_a < private.rosa_minima() then
    raise exception using errcode = '22023',
      message = 'Lo scambio lascerebbe una rosa sotto i 21 giocatori.';
  end if;
  if v_gk_da < v_lega.portieri_minimi or v_gk_a < v_lega.portieri_minimi then
    raise exception using errcode = '22023',
      message = 'Lo scambio lascerebbe una squadra sotto il minimo di portieri.';
  end if;

  update public.player_instances set team_id = v_a.id
  where id = any(v_p.giocatori_offerti);
  update public.player_instances set team_id = v_da.id
  where id = any(v_p.giocatori_richiesti);

  update public.teams set budget = budget + v_saldo_da where id = v_da.id;
  update public.teams set budget = budget + v_saldo_a  where id = v_a.id;

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

-- ------------------------------------------------------------
--  Testi degli errori sulle aste: gia' agganciate a mercato_aperto_lega,
--  aggiornano solo l'orario citato.
-- ------------------------------------------------------------

create or replace function public.offri_per_svincolato(p_auction_id bigint, p_ingaggio bigint)
returns free_agent_bids
language plpgsql
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
      message = 'Il mercato e'' chiuso: si offre dalle 23:30 alle 21:00 o quando l''admin lo apre.';
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

create or replace function public.offri_per_svincolato_archivio(p_league_id bigint, p_player_id bigint, p_ingaggio bigint)
returns free_agent_bids
language plpgsql
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
      message = 'Il mercato e'' chiuso: si offre dalle 23:30 alle 21:00 o quando l''admin lo apre.';
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

-- ------------------------------------------------------------
--  Cron dell'estrazione: da un giro l'ora a quattro (ogni 15 minuti), cosi'
--  puo' intercettare il nuovo confine delle 23:30. Gli altri cron (chiusura
--  alle 21:00, simulazione alle 23:00) restano su un'ora esatta e non
--  cambiano: un giro l'ora basta gia' a coglierli.
-- ------------------------------------------------------------

select cron.alter_job(
  (select jobid from cron.job where jobname = 'estrazione-svincolati'),
  schedule => '2,17,32,47 * * * *'
);
