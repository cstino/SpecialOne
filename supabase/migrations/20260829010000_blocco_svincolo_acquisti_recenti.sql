-- ============================================================
--  BLOCCO SVINCOLO SU ACQUISTI RECENTI
--  Deciso il 29 agosto 2026, in conversazione con l'utente.
--
--  Una squadra non puo' comprare un giocatore (asta svincolati o
--  scambio) e svincolarlo subito dopo: serve a impedire un giro
--  "compra e scarta" per manipolare la coda dei rilasci o il pool
--  svincolati. Un giocatore acquisito da una squadra non puo' essere
--  svincolato da QUELLA squadra prima che siano passate 10 giornate
--  dall'acquisizione.
--
--  Non tocca il mercato a scelte (draft picks, docs/decisioni-draft-
--  picks.md): la richiesta dell'utente parlava solo di mercato e
--  scambi. Se in futuro si vuole includere anche li', va aggiunto un
--  aggiornamento analogo a private.risolvi_finestra_scelte.
--
--  Non e' retroattivo: giornata_acquisizione parte NULL per tutte le
--  istanze esistenti (draft compreso), quindi nessuna rosa attuale si
--  ritrova bloccata da una regola che non esisteva quando l'ha
--  costruita.
-- ============================================================

alter table public.player_instances
  add column giornata_acquisizione smallint;

comment on column public.player_instances.giornata_acquisizione is
  'Giornata (fixtures.giornata) in cui la squadra attuale ha preso questo giocatore via asta svincolati o scambio. NULL = nessun vincolo (draft, rose iniziali, offseason). Usata per bloccare lo svincolo prima di 10 giornate.';

-- ------------------------------------------------------------
--  risolvi_aste_giorno: segna la giornata di acquisizione quando
--  un'asta viene assegnata.
-- ------------------------------------------------------------
create or replace function private.risolvi_aste_giorno(p_giorno date, p_league_id bigint default null)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_asta              record;
  v_soglia            bigint;
  v_vincitore         record;
  v_stagione          smallint;
  v_prossima          integer;
  v_nome              text;
  v_assegnate         integer := 0;
  v_istanze_assegnate integer;
  v_off               record;
begin
  for v_asta in
    select a.* from public.free_agent_auctions a
    where a.giorno = p_giorno and a.stato = 'aperta'
      and (p_league_id is null or a.league_id = p_league_id)
    order by a.id
    for update
  loop
    v_stagione := private.stagione_contratto(v_asta.league_id);
    select min(f.giornata) into v_prossima
    from public.fixtures f where f.league_id = v_asta.league_id and f.stato = 'programmata';
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
      and private.capienza_residua(b.team_id, v_stagione, v_asta.id) >= b.ingaggio_offerto
    order by b.ingaggio_offerto desc, b.aggiornata_il asc, b.id asc
    limit 1;

    if v_vincitore.id is null then
      update public.free_agent_auctions
      set stato = 'deserta', risolta_il = now()
      where id = v_asta.id;
    else
      -- Un giocatore svincolato conserva la propria istanza di lega: un
      -- insert semplice urterebbe unique(league_id, player_id). L'upsert
      -- riusa l'istanza solo se e' ancora libera; se nel frattempo e' stata
      -- assegnata altrove, questa sola asta fallisce senza segnarsi come
      -- conclusa (non l'intera risoluzione).
      insert into public.player_instances as pi
        (league_id, player_id, team_id, overall_corrente, eta_corrente, ingaggio, contratto_scadenza, giornata_acquisizione)
      select v_asta.league_id, p.id, v_vincitore.team_id, p.overall, p.eta,
             v_vincitore.ingaggio_offerto, v_stagione, v_prossima
      from public.players p where p.id = v_asta.player_id
      on conflict (league_id, player_id) do update
        set team_id = excluded.team_id,
            ingaggio = excluded.ingaggio,
            contratto_scadenza = excluded.contratto_scadenza,
            giornata_acquisizione = excluded.giornata_acquisizione
        where pi.team_id is null;
      get diagnostics v_istanze_assegnate = row_count;

      if v_istanze_assegnate <> 1 then
        raise exception using errcode = '55000',
          message = 'Il giocatore non e'' piu'' disponibile per questa asta.';
      end if;

      insert into public.transactions
        (league_id, team_id, tipo, importo, descrizione, saldo_dopo)
      select v_asta.league_id, v_vincitore.team_id, 'asta_svincolato',
             -v_vincitore.ingaggio_offerto,
             'Asta vinta: ' || v_nome || ' — ' ||
             private.in_milioni(v_vincitore.ingaggio_offerto) ||
             ' M€ di ingaggio fino alla stagione ' || v_stagione,
             (select budget from public.teams where id = v_vincitore.team_id);

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
          when v_off.team_id = v_vincitore.team_id then 'Entra in rosa con un contratto di una stagione.'
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

-- ------------------------------------------------------------
--  rispondi_a_proposta: segna la giornata di acquisizione per
--  entrambi i lati dello scambio quando viene accettato.
-- ------------------------------------------------------------
create or replace function public.rispondi_a_proposta(p_proposta_id bigint, p_accetta boolean)
returns trade_proposals
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_utente     uuid := (select auth.uid());
  v_p          public.trade_proposals;
  v_lega       public.leagues;
  v_da         public.teams;
  v_a          public.teams;
  v_stagione   smallint;
  v_n          integer;
  v_rosa_da    integer;
  v_rosa_a     integer;
  v_prossima   integer;
  v_tutti      bigint[];
  v_form_tolte integer := 0;
  v_nota       text := '';
  v_delta_da   bigint;
  v_delta_a    bigint;
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
    update public.trade_proposals set stato = 'rifiutata', risolta_il = now()
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

  -- Lock deterministico sulle due squadre: evita deadlock fra due
  -- accettazioni concorrenti che coinvolgono la stessa coppia.
  perform 1 from public.teams where id in (v_p.da_team_id, v_p.a_team_id) order by id for update;
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

  -- Stesso controllo per le scelte: puo' essere stata gia' esercitata, o
  -- rigirata altrove, nel tempo fra la proposta e questa risposta.
  select count(*) into v_n from public.scelte_draft
  where id = any(v_p.scelte_offerte) and team_proprietario_id = v_da.id and stato in ('futura', 'determinata');
  if v_n <> cardinality(v_p.scelte_offerte) then
    raise exception using errcode = '55000',
      message = 'Una scelta offerta non e'' piu'' disponibile: la proposta non e'' piu'' valida.';
  end if;
  select count(*) into v_n from public.scelte_draft
  where id = any(v_p.scelte_richieste) and team_proprietario_id = v_a.id and stato in ('futura', 'determinata');
  if v_n <> cardinality(v_p.scelte_richieste) then
    raise exception using errcode = '55000',
      message = 'Una scelta richiesta non e'' piu'' disponibile: la proposta non e'' piu'' valida.';
  end if;

  -- Regola Stepien, ricontrollata: lo stato delle scelte puo'' essere
  -- cambiato fra la proposta e questa risposta (altri scambi nel
  -- frattempo).
  if cardinality(v_p.scelte_offerte) > 0 and private.viola_regola_stepien(v_da.id, v_p.scelte_offerte) then
    raise exception using errcode = '22023',
      message = 'Questo scambio lascerebbe ' || v_da.nome || ' senza una propria scelta d''origine per due stagioni consecutive nella stessa finestra (regola Stepien): la proposta non e'' piu'' valida.';
  end if;
  if cardinality(v_p.scelte_richieste) > 0 and private.viola_regola_stepien(v_a.id, v_p.scelte_richieste) then
    raise exception using errcode = '22023',
      message = 'Questo scambio ti lascerebbe senza una tua scelta d''origine per due stagioni consecutive nella stessa finestra (regola Stepien).';
  end if;

  select count(*) into v_rosa_da from public.player_instances where team_id = v_da.id;
  select count(*) into v_rosa_a  from public.player_instances where team_id = v_a.id;
  v_rosa_da := v_rosa_da - cardinality(v_p.giocatori_offerti) + cardinality(v_p.giocatori_richiesti);
  v_rosa_a  := v_rosa_a  - cardinality(v_p.giocatori_richiesti) + cardinality(v_p.giocatori_offerti);
  if v_rosa_da > private.rosa_massima() or v_rosa_a > private.rosa_massima() then
    raise exception using errcode = '22023', message = 'Lo scambio porterebbe una rosa oltre i 30 giocatori.';
  end if;
  if v_rosa_da < private.rosa_minima() or v_rosa_a < private.rosa_minima() then
    raise exception using errcode = '22023', message = 'Lo scambio lascerebbe una rosa sotto i 21 giocatori.';
  end if;

  select min(f.giornata) into v_prossima
  from public.fixtures f where f.league_id = v_lega.id and f.stato = 'programmata';

  -- Trasferimenti: prima i giocatori (i trigger su player_instances
  -- gestiscono liste e rinnovi in corso), poi le scelte. giornata_acquisizione
  -- riparte da qui per entrambi i lati (docs/decisioni-economia.md non
  -- copriva questo caso: deciso il 29 agosto 2026, blocco svincolo 10
  -- giornate su acquisti via mercato o scambio).
  update public.player_instances set team_id = v_a.id,  giornata_acquisizione = v_prossima where id = any(v_p.giocatori_offerti);
  update public.player_instances set team_id = v_da.id, giornata_acquisizione = v_prossima where id = any(v_p.giocatori_richiesti);
  update public.scelte_draft set team_proprietario_id = v_a.id,  aggiornata_il = now() where id = any(v_p.scelte_offerte);
  update public.scelte_draft set team_proprietario_id = v_da.id, aggiornata_il = now() where id = any(v_p.scelte_richieste);

  -- Capienza: dopo aver spostato i giocatori, il monte di ciascuna
  -- squadra include gia' l'effetto dello scambio. Le scelte non vi
  -- contribuiscono: non hanno un ingaggio proprio finche' non si
  -- esercitano.
  v_stagione := private.stagione_contratto(v_p.league_id);
  if private.monte_ingaggi(v_da.id, v_stagione) + private.ingaggi_impegnati_aste(v_da.id, null) > v_lega.tetto_ingaggi then
    raise exception using errcode = '22023',
      message = 'Questo scambio porterebbe ' || v_da.nome || ' oltre il tetto ingaggi.';
  end if;
  if private.monte_ingaggi(v_a.id, v_stagione) + private.ingaggi_impegnati_aste(v_a.id, null) > v_lega.tetto_ingaggi then
    raise exception using errcode = '22023',
      message = 'Questo scambio ti porterebbe oltre il tetto ingaggi.';
  end if;

  v_tutti := v_p.giocatori_offerti || v_p.giocatori_richiesti;
  if v_prossima is not null and cardinality(v_tutti) > 0 then
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

  -- Registro: non piu' movimento di cassa, ma di spazio salariale. Zero
  -- e' un esito legittimo (scambio di picks pure, o pari valore) e non
  -- genera riga: importo <> 0 e' un vincolo della tabella.
  select coalesce(sum(ingaggio), 0) into v_delta_da
  from public.player_instances where id = any(v_p.giocatori_richiesti);
  v_delta_da := v_delta_da - coalesce((select sum(ingaggio) from public.player_instances where id = any(v_p.giocatori_offerti)), 0);
  v_delta_a := -v_delta_da;

  if v_delta_da <> 0 then
    insert into public.transactions (league_id, team_id, tipo, importo, descrizione, saldo_dopo)
    values (v_lega.id, v_da.id, 'mercato_scambio', v_delta_da, 'Scambio con ' || v_a.nome, v_da.budget);
  end if;
  if v_delta_a <> 0 then
    insert into public.transactions (league_id, team_id, tipo, importo, descrizione, saldo_dopo)
    values (v_lega.id, v_a.id, 'mercato_scambio', v_delta_a, 'Scambio con ' || v_da.nome, v_a.budget);
  end if;

  update public.trade_proposals set stato = 'accettata', risolta_il = now()
  where id = v_p.id
  returning * into v_p;

  perform private.notifica(v_da.user_id, v_lega.id, 'mercato_esito', 'Scambio concluso con ' || v_a.nome,
    'La tua proposta e'' stata accettata.' || v_nota, jsonb_build_object('proposta_id', v_p.id));
  perform private.notifica(v_a.user_id, v_lega.id, 'mercato_esito', 'Scambio concluso con ' || v_da.nome,
    'Hai accettato la proposta.' || v_nota, jsonb_build_object('proposta_id', v_p.id));

  return v_p;
end;
$$;

-- ------------------------------------------------------------
--  svincola_giocatore_cassa_legacy: blocca lo svincolo prima di 10
--  giornate dall'acquisizione via mercato o scambio.
-- ------------------------------------------------------------
create or replace function public.svincola_giocatore_cassa_legacy(p_instance_id bigint)
returns player_instances
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_utente uuid := (select auth.uid());
  v_istanza public.player_instances;
  v_squadra public.teams;
  v_lega public.leagues;
  v_giocatore public.players;
  v_rosa integer;
  v_portieri integer;
  v_prossima integer;
  v_giornate_trascorse integer;
  v_formazione public.lineups;
  v_indice integer;
  v_slot text;
  v_sostituto bigint;
  v_formazioni_aggiornate integer := 0;
  v_nota text := '';
begin
  if v_utente is null then
    raise exception using errcode = '42501', message = 'Devi accedere per svincolare un giocatore.';
  end if;

  select * into v_istanza from public.player_instances where id = p_instance_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Giocatore inesistente.';
  end if;

  select * into v_squadra from public.teams where id = v_istanza.team_id and user_id = v_utente;
  if not found then
    raise exception using errcode = '42501', message = 'Questo giocatore non appartiene alla tua squadra.';
  end if;

  perform 1 from public.teams where id = v_squadra.id for update;
  select * into v_istanza from public.player_instances
  where id = p_instance_id and team_id = v_squadra.id for update;
  if not found then
    raise exception using errcode = '55000', message = 'Il giocatore non e'' piu'' nella tua rosa.';
  end if;

  select * into v_lega from public.leagues where id = v_istanza.league_id;
  if v_lega.stato <> 'stagione' then
    raise exception using errcode = '55000', message = 'Puoi svincolare giocatori solo durante la stagione.';
  end if;
  if not private.mercato_aperto_lega(v_lega.id) then
    raise exception using errcode = '55000', message = 'Il mercato e'' chiuso: puoi svincolare dalle 23:30 alle 21:00, o quando l''admin lo apre.';
  end if;

  select min(f.giornata) into v_prossima from public.fixtures f
  where f.league_id = v_lega.id and f.stato = 'programmata';

  -- Blocco svincolo su acquisti recenti (deciso il 29 agosto 2026): un
  -- giocatore preso via asta svincolati o scambio non puo' essere
  -- svincolato dalla stessa squadra prima di 10 giornate. NULL (draft, rose
  -- iniziali, offseason) non e' mai bloccato. coalesce su giornate_totali+1
  -- copre il caso limite di fine campionato senza altre giornate
  -- programmate, cosi' il conteggio non resta "in sospeso" a stagione finita.
  if v_istanza.giornata_acquisizione is not null then
    v_giornate_trascorse := coalesce(v_prossima, v_lega.giornate_totali + 1) - v_istanza.giornata_acquisizione;
    if v_giornate_trascorse < 10 then
      raise exception using errcode = '22023',
        message = 'Questo giocatore e'' arrivato da meno di 10 giornate (mercato o scambio): non puoi ancora svincolarlo. Mancano ' ||
          (10 - v_giornate_trascorse) || ' giornate.';
    end if;
  end if;

  select count(*), count(*) filter (where p.posizioni[1] = 'GK') into v_rosa, v_portieri
  from public.player_instances pi join public.players p on p.id = pi.player_id
  where pi.team_id = v_squadra.id and pi.id <> v_istanza.id;
  if v_rosa < private.rosa_minima() then
    raise exception using errcode = '22023', message = 'Non puoi scendere sotto i 21 giocatori in rosa.';
  end if;
  if v_portieri < v_lega.portieri_minimi then
    raise exception using errcode = '22023', message = 'Non puoi scendere sotto il minimo di portieri della lega.';
  end if;

  -- Economia a tetto salariale (docs/decisioni-economia.md par 2 e par 4): lo
  -- svincolo libera spazio senza penalita' in contanti. Il vecchio addebito
  -- esisteva per impedire di firmare lungo e tagliare a piacere; con i
  -- contratti annuali quell'impegno non esiste piu'. Era anche una trappola
  -- concreta: le squadre col monte ingaggi piu' alto (quelle che piu'
  -- avevano bisogno di liberare spazio) erano spesso proprio quelle senza
  -- abbastanza cassa per pagarsela, e restavano bloccate.
  select * into v_giocatore from public.players where id = v_istanza.player_id;

  if v_prossima is not null then
    for v_formazione in
      select * from public.lineups
      where league_id = v_lega.id
        and team_id = v_squadra.id
        and giornata >= v_prossima
        and (titolari && array[v_istanza.id]::bigint[] or panchina && array[v_istanza.id]::bigint[] or tribuna && array[v_istanza.id]::bigint[])
      for update
    loop
      v_sostituto := null;
      v_indice := array_position(v_formazione.titolari, v_istanza.id);

      if v_indice is not null then
        v_slot := (case v_formazione.modulo
          when '4-3-3' then array['GK','LB','CB','CB','RB','CM','CM','CM','LW','ST','RW']
          when '4-3-3 offensivo' then array['GK','LB','CB','CB','RB','CM','CM','CAM','LW','ST','RW']
          when '4-3-3 difensivo' then array['GK','LB','CB','CB','RB','CM','CM','CDM','LW','ST','RW']
          when '4-4-2' then array['GK','LB','CB','CB','RB','LM','CM','CM','RM','ST','ST']
          when '4-2-3-1' then array['GK','LB','CB','CB','RB','CDM','CDM','CAM','LW','RW','ST']
          when '3-5-2' then array['GK','CB','CB','CB','LWB','CM','CM','CM','RWB','ST','ST']
          when '3-4-3' then array['GK','CB','CB','CB','LM','CM','CM','RM','LW','ST','RW']
          when '5-3-2' then array['GK','LB','CB','CB','CB','RB','CM','CM','CM','ST','ST']
          when '4-2-4' then array['GK','LB','CB','CB','RB','CM','CM','LW','ST','ST','RW']
        end)[v_indice];

        select pi.id into v_sostituto
        from public.player_instances pi join public.players p on p.id = pi.player_id
        where pi.league_id = v_lega.id and pi.team_id = v_squadra.id and pi.id <> v_istanza.id
          and not (pi.id = any(v_formazione.titolari || coalesce(v_formazione.panchina, '{}'::bigint[])))
        order by
          case
            when v_slot = any(p.posizioni) then 0
            when v_slot in ('CB','LB','RB','LWB','RWB') and p.posizioni && array['CB','LB','RB','LWB','RWB']::text[] then 1
            when v_slot in ('CDM','CM','CAM','LM','RM') and p.posizioni && array['CDM','CM','CAM','LM','RM']::text[] then 1
            when v_slot in ('LW','RW','ST','CF') and p.posizioni && array['LW','RW','ST','CF']::text[] then 1
            when v_slot = 'GK' or p.posizioni && array['GK']::text[] then 3
            else 2
          end,
          case when pi.infortunato_fino_a <= 0 then 0 else 1 end,
          pi.overall_corrente desc, pi.id
        limit 1;

        update public.lineups
        set titolari = array_replace(titolari, v_istanza.id, v_sostituto),
            tribuna = array_remove(tribuna, v_sostituto)
        where id = v_formazione.id;
        v_formazioni_aggiornate := v_formazioni_aggiornate + 1;

      elsif array_position(v_formazione.panchina, v_istanza.id) is not null then
        select pi.id into v_sostituto
        from public.player_instances pi
        where pi.league_id = v_lega.id and pi.team_id = v_squadra.id and pi.id <> v_istanza.id
          and not (pi.id = any(v_formazione.titolari || coalesce(v_formazione.panchina, '{}'::bigint[])))
        order by case when pi.infortunato_fino_a <= 0 then 0 else 1 end, pi.overall_corrente desc, pi.id
        limit 1;

        update public.lineups
        set panchina = array_replace(panchina, v_istanza.id, v_sostituto),
            tribuna = array_remove(tribuna, v_sostituto)
        where id = v_formazione.id;
        v_formazioni_aggiornate := v_formazioni_aggiornate + 1;

      else
        update public.lineups set tribuna = array_remove(tribuna, v_istanza.id) where id = v_formazione.id;
      end if;
    end loop;
  end if;

  update public.player_instances set team_id = null,
    ritirato = case when v_istanza.ritiro_annunciato then true else ritirato end
  where id = v_istanza.id returning * into v_istanza;
  if v_istanza.ritiro_annunciato then
    insert into public.retired_players(league_id, player_id, stagione)
    values (v_lega.id, v_istanza.player_id, v_lega.stagione_corrente) on conflict do nothing;
  else
    -- Entra subito nella coda dei rilasci (docs/decisioni-economia.md): se il
    -- mercato e' gia' aperto non puo' aggiungersi alla tornata in corso (chi
    -- ha gia' fatto offerte non lo saprebbe), quindi aspetta la prossima
    -- estrazione. Li' si aggiunge IN PIU' rispetto alle 5 (o 10) per ruolo
    -- gia' previste, non al loro posto: private.estrai_svincolati_lega lo
    -- consuma e lo inserisce nella stessa tornata, extra quota.
    insert into private.rilasci_in_coda(league_id, player_id)
    values (v_lega.id, v_istanza.player_id)
    on conflict (league_id, player_id) do nothing;
  end if;

  if v_formazioni_aggiornate > 0 then v_nota := ' Formazione aggiornata automaticamente con un sostituto.'; end if;
  perform private.notifica(
    v_utente, v_lega.id, 'mercato_esito', 'Giocatore svincolato',
    v_giocatore.nome || (case
      when v_istanza.ritiro_annunciato then ' aveva gia'' annunciato il ritiro: la carriera termina qui, non torna disponibile.'
      else ' non fa piu'' parte della tua rosa. Torna nel mercato degli svincolati.' end) || v_nota,
    jsonb_build_object('player_instance_id', v_istanza.id, 'player_id', v_istanza.player_id)
  );
  return v_istanza;
end;
$$;
