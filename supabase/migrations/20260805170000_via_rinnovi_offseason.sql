-- ============================================================
--  I RINNOVI DI OFF-SEASON SPARISCONO — IL RINNOVO È SOLO IN STAGIONE
--
--  Decisione dell'utente, 5 agosto 2026. Fino a ieri esistevano due canali
--  di rinnovo: quello di off-season (§10.4, con richiesta a range ±12% e
--  soglia di accettazione al 90%) e quello a stagione in corso aggiunto
--  stamattina (§10.4 bis). Il primo viene rimosso: resta solo il secondo.
--
--  Conseguenza voluta: chi non è stato rinnovato *durante* la stagione,
--  alla chiusura dell'off-season lascia semplicemente la squadra ed entra
--  nel pool degli svincolati, pescabile dal mercato come tutti gli altri.
--  Niente più trattativa di giugno.
--
--  Effetto collaterale positivo, segnalato ieri come problema aperto: la
--  regola "esauriti i tre tentativi il giocatore va a scadenza" diventa
--  davvero definitiva. Con i rinnovi di off-season ancora attivi sarebbe
--  bastato aspettare giugno per rinegoziare, aggirando la conseguenza.
--
--  Le tabelle contract_renewals e private.contract_renewal_terms NON
--  vengono droppate: contengono 195 righe di una lega reale e restano come
--  archivio storico. Semplicemente non ci si scrive più. Anche
--  public.rispondi_rinnovo resta in piedi ma non ha più nulla da leggere:
--  droppare una funzione ancora referenziata dal frontend darebbe un errore
--  peggiore di una lista vuota. Il frontend smette di chiamarla.
--
--  Le due funzioni sotto sono le versioni correnti lette da
--  pg_get_functiondef, con due sole modifiche chirurgiche:
--   · prepara_offseason: rimosso il ciclo che generava contract_renewals
--     (e le cinque variabili rimaste orfane, che darebbero warning al lint);
--   · finalizza_offseason: il rilascio dei non rinnovati non legge più
--     contract_renewals ma direttamente contratto_scadenza.
-- ============================================================

CREATE OR REPLACE FUNCTION public.prepara_offseason(p_league_id bigint, p_squadre_rimosse bigint[] DEFAULT '{}'::bigint[], p_posti_nuovi smallint DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_user uuid := (select auth.uid());
  v_lega public.leagues;
  v_offseason public.offseasons;
  v_attive integer;
  v_rimosse integer;
  v_target integer;
  v_team record;
  v_player record;
  v_eta smallint;
  v_sponsor bigint;
  v_premi_partita bigint;
  v_premio_posizione bigint;
  v_pool numeric;
  v_pesi numeric;
  v_accreditato bigint;
  v_ritirati integer := 0;
begin
  if v_user is null then
    raise exception using errcode = '42501', message = 'Devi accedere per aprire l''off-season.';
  end if;

  select * into v_lega from public.leagues where id = p_league_id for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Lega non trovata.';
  end if;
  if v_lega.admin_id <> v_user then
    raise exception using errcode = '42501', message = 'Solo l''admin può aprire l''off-season.';
  end if;
  if v_lega.stato <> 'conclusa' or v_lega.fase_carriera <> 'normale' then
    raise exception using errcode = '55000', message = 'L''off-season è disponibile soltanto dopo una stagione conclusa.';
  end if;
  if coalesce(p_posti_nuovi, 0) not between 0 and 16 then
    raise exception using errcode = '22023', message = 'Numero di nuovi posti non valido.';
  end if;
  if cardinality(coalesce(p_squadre_rimosse, '{}'::bigint[])) <>
     (select count(distinct id) from unnest(coalesce(p_squadre_rimosse, '{}'::bigint[])) x(id)) then
    raise exception using errcode = '22023', message = 'La lista delle squadre rimosse contiene duplicati.';
  end if;
  if exists (
    select 1 from unnest(coalesce(p_squadre_rimosse, '{}'::bigint[])) x(id)
    left join public.teams t on t.id = x.id and t.league_id = p_league_id and t.attiva
    where t.id is null
  ) then
    raise exception using errcode = '22023', message = 'Una squadra da rimuovere non appartiene alla lega o è già inattiva.';
  end if;
  if exists (
    select 1 from public.teams
    where id = any(coalesce(p_squadre_rimosse, '{}'::bigint[])) and user_id = v_lega.admin_id
  ) then
    raise exception using errcode = '22023', message = 'L''admin non può rimuovere la propria squadra.';
  end if;

  select count(*) into v_attive from public.teams where league_id = p_league_id and attiva;
  v_rimosse := cardinality(coalesce(p_squadre_rimosse, '{}'::bigint[]));
  v_target := v_attive - v_rimosse + coalesce(p_posti_nuovi, 0);
  if v_target not between 4 and 20 then
    raise exception using errcode = '22023', message = 'La prossima stagione deve avere da 4 a 20 squadre.';
  end if;

  insert into public.offseasons (league_id, stagione_da, stagione_a, scade_il, posti_nuovi)
  values (p_league_id, v_lega.stagione_corrente, v_lega.stagione_corrente + 1,
          ((now() at time zone 'Europe/Rome') + interval '7 days') at time zone 'Europe/Rome',
          coalesce(p_posti_nuovi, 0))
  returning * into v_offseason;

  if v_rimosse > 0 then
    update public.trade_proposals
    set stato = 'scaduta', risolta_il = now()
    where league_id = p_league_id and stato = 'in_attesa'
      and (da_team_id = any(p_squadre_rimosse) or a_team_id = any(p_squadre_rimosse));

    update public.player_instances
    set team_id = null
    where league_id = p_league_id and team_id = any(p_squadre_rimosse);

    update public.teams
    set attiva = false, uscita_stagione = v_lega.stagione_corrente
    where league_id = p_league_id and id = any(p_squadre_rimosse);
  end if;

  v_sponsor := round((v_lega.budget_iniziale * 0.20)::numeric / 100000) * 100000;
  v_pool := 0.12 * v_lega.budget_iniziale * (v_attive - v_rimosse);
  select sum(power((v_attive - v_rimosse - s.posizione + 1)::numeric, 1.8))
    into v_pesi
  from public.standings s
  join public.seasons se on se.id = s.season_id
  join public.teams t on t.id = s.team_id and t.attiva
  where se.league_id = p_league_id and se.numero = v_lega.stagione_corrente;

  for v_team in
    select t.id, t.user_id, t.nome, t.budget,
           coalesce(s.vittorie, 0) vittorie, coalesce(s.pareggi, 0) pareggi,
           coalesce(s.sconfitte, 0) sconfitte, coalesce(s.posizione, v_attive) posizione
    from public.teams t
    left join public.seasons se on se.league_id = t.league_id and se.numero = v_lega.stagione_corrente
    left join public.standings s on s.season_id = se.id and s.team_id = t.id
    where t.league_id = p_league_id and t.attiva
    order by t.id
    for update of t
  loop
    v_premi_partita := round((v_lega.budget_iniziale::numeric
      * (0.54 * v_team.vittorie + 0.27 * v_team.pareggi + 0.135 * v_team.sconfitte)
      / greatest(v_lega.partite_per_squadra, 1)) / 100000) * 100000;
    v_premio_posizione := case when coalesce(v_pesi, 0) > 0
      then round((v_pool * power((v_attive - v_rimosse - v_team.posizione + 1)::numeric, 1.8) / v_pesi) / 100000) * 100000
      else 0 end;
    v_accreditato := v_sponsor + v_premi_partita + v_premio_posizione;

    update public.teams set budget = budget + v_accreditato where id = v_team.id;
    if v_premi_partita <> 0 then
      insert into public.transactions(league_id, team_id, tipo, importo, descrizione, saldo_dopo)
      values (p_league_id, v_team.id, 'premi_partite', v_premi_partita,
              'Premi partita stagione ' || v_lega.stagione_corrente,
              (select budget from public.teams where id = v_team.id));
    end if;
    if v_premio_posizione <> 0 then
      insert into public.transactions(league_id, team_id, tipo, importo, descrizione, saldo_dopo)
      values (p_league_id, v_team.id, 'premio_classifica', v_premio_posizione,
              'Premio ' || v_team.posizione || '° posto',
              (select budget from public.teams where id = v_team.id));
    end if;
    if v_sponsor <> 0 then
      insert into public.transactions(league_id, team_id, tipo, importo, descrizione, saldo_dopo)
      values (p_league_id, v_team.id, 'sponsor', v_sponsor,
              'Sponsor stagione ' || v_offseason.stagione_a,
              (select budget from public.teams where id = v_team.id));
    end if;
  end loop;

  for v_player in
    select pi.id, pi.player_id, p.nome, t.user_id
    from public.player_instances pi
    join public.players p on p.id = pi.player_id
    join public.teams t on t.id = pi.team_id and t.attiva
    where pi.league_id = p_league_id and pi.ritiro_annunciato and not pi.ritirato
  loop
    update public.player_instances
    set team_id = null, ritirato = true, ritiro_annunciato = false
    where id = v_player.id;
    insert into public.retired_players(league_id, player_id, stagione)
    values (p_league_id, v_player.player_id, v_lega.stagione_corrente)
    on conflict do nothing;
    v_ritirati := v_ritirati + 1;
    perform private.notifica(v_player.user_id, p_league_id, 'sistema',
      v_player.nome || ' si ritira',
      'Il ritiro annunciato a inizio stagione e'' ora effettivo: la carriera termina qui.',
      jsonb_build_object('player_instance_id', v_player.id));
  end loop;

  -- La progressione OVR è stata applicata ai quattro checkpoint; qui età e
  -- recupero vengono portati alla nuova stagione senza un quinto aggiornamento.
  for v_player in
    select pi.id, pi.eta_corrente
    from public.player_instances pi
    join public.teams t on t.id = pi.team_id and t.attiva
    where pi.league_id = p_league_id and not pi.ritirato
    order by pi.id
    for update of pi
  loop
    v_eta := least(45, v_player.eta_corrente + 1);
    update public.player_instances
    set eta_corrente = v_eta,
        condizione = 100,
        infortunato_fino_a = 0,
        progressione_residuo = 0
    where id = v_player.id;
  end loop;


  update public.leagues
  set n_squadre = v_target,
      stato = 'stagione',
      fase_carriera = 'offseason',
      offseason_fine = v_offseason.scade_il
  where id = p_league_id;

  return jsonb_build_object(
    'league_id', p_league_id,
    'offseason_id', v_offseason.id,
    'stagione_a', v_offseason.stagione_a,
    'scade_il', v_offseason.scade_il,
    'squadre_attese', v_target,
    'posti_nuovi', p_posti_nuovi,
    'ritirati', v_ritirati
  );
end;
$function$;

CREATE OR REPLACE FUNCTION private.finalizza_offseason(p_league_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_league public.leagues;
  v_off public.offseasons;
  v_team record;
  v_candidate record;
  v_player record;
  v_rosa integer;
  v_ingaggi bigint;
  v_da_aggiungere integer;
  v_wage bigint;
  v_season bigint;
  v_aggiunti text[];
  v_rilasciati integer;
  v_attive integer;
begin
  select * into v_league from public.leagues where id = p_league_id for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Lega non trovata.';
  end if;
  if v_league.fase_carriera <> 'offseason' then
    raise exception using errcode = '55000', message = 'L''off-season non e'' attiva.';
  end if;

  select * into v_off
  from public.offseasons
  where league_id = p_league_id and stato = 'aperta'
  order by stagione_a desc limit 1
  for update;
  if not found then
    raise exception using errcode = '55000', message = 'Off-season aperta non trovata.';
  end if;
  if clock_timestamp() < v_off.scade_il then
    raise exception using errcode = '55000',
      message = 'L''off-season dura 24 ore e non puo'' essere chiusa prima della scadenza.';
  end if;

  select count(*)::integer into v_attive
  from public.teams where league_id = p_league_id and attiva;
  if v_attive < 4 then
    raise exception using errcode = '55000', message = 'Servono almeno 4 squadre attive per iniziare la stagione.';
  end if;

  -- I posti di espansione non occupati alla scadenza decadono: il calendario
  -- usa le squadre realmente iscritte, senza tenere bloccata tutta la lega.
  update public.leagues set n_squadre = v_attive where id = p_league_id;

  -- Contratti scaduti: chi non e' stato rinnovato durante la stagione (unico
  -- canale di rinnovo, design §10.4 bis) lascia la squadra ed entra nel pool
  -- degli svincolati. Prima questo passaggio leggeva contract_renewals, cioe'
  -- le trattative aperte in off-season: quel canale non esiste piu'.
  update public.player_instances
  set team_id = null
  where league_id = p_league_id
    and team_id is not null
    and not ritirato
    and contratto_scadenza <= v_league.stagione_corrente;

  -- Uno spin lasciato senza risposta non resta sospeso per sempre: il
  -- giocatore torna semplicemente nel pool degli svincolati.
  update public.offseason_spins
  set stato = 'asta', risolta_il = clock_timestamp()
  where offseason_id = v_off.id and stato = 'proposto';

  for v_team in
    select * from public.teams
    where league_id = p_league_id and attiva
    order by id for update
  loop
    v_aggiunti := array[]::text[];
    v_rilasciati := 0;

    -- Se la rosa attuale non e' sostenibile, si applica l'insolvenza del
    -- design: escono prima gli ingaggi piu' alti finche' restano finanziabili
    -- anche i posti mancanti al minimo di 21.
    loop
      select count(*)::integer, coalesce(sum(ingaggio), 0)::bigint
      into v_rosa, v_ingaggi
      from public.player_instances
      where team_id = v_team.id and not ritirato;

      exit when v_ingaggi + greatest(21 - v_rosa, 0) * 500000 <= v_team.budget;

      select pi.id into v_candidate
      from public.player_instances pi
      where pi.team_id = v_team.id and not pi.ritirato
      order by pi.ingaggio desc, pi.overall_corrente asc, pi.id
      limit 1;
      if not found then
        raise exception using errcode = '55000', message = 'Budget insufficiente per completare la rosa di ' || v_team.nome || '.';
      end if;
      update public.player_instances set team_id = null where id = v_candidate.id;
      v_rilasciati := v_rilasciati + 1;
    end loop;

    select count(*)::integer, coalesce(sum(ingaggio), 0)::bigint
    into v_rosa, v_ingaggi
    from public.player_instances
    where team_id = v_team.id and not ritirato;
    v_da_aggiungere := greatest(21 - v_rosa, 0);

    while v_da_aggiungere > 0 loop
      select p.id as player_id, p.nome, p.overall, p.eta,
             pi.id as instance_id,
             coalesce(pi.ingaggio, private.ingaggio_teorico(p.overall, p.eta))::bigint as ingaggio
      into v_candidate
      from public.players p
      left join public.player_instances pi
        on pi.league_id = p_league_id and pi.player_id = p.id
      where p.campionato = any(v_league.campionati_attivi)
        and (pi.id is null or (pi.team_id is null and not pi.ritirato))
        and not exists (select 1 from public.retired_players rp where rp.league_id = p_league_id and rp.player_id = p.id)
        and coalesce(pi.ingaggio, private.ingaggio_teorico(p.overall, p.eta))
          <= v_team.budget - v_ingaggi - ((v_da_aggiungere - 1) * 500000)
      order by coalesce(pi.ingaggio, private.ingaggio_teorico(p.overall, p.eta)) asc,
               p.overall asc, p.id
      limit 1;

      if not found then
        raise exception using errcode = '55000', message = 'Non ci sono svincolati sostenibili per completare la rosa di ' || v_team.nome || '.';
      end if;

      v_wage := greatest(500000, v_candidate.ingaggio);
      if v_candidate.instance_id is null then
        insert into public.player_instances(
          league_id, player_id, team_id, overall_corrente, eta_corrente, ingaggio,
          condizione, infortunato_fino_a, contratto_scadenza
        ) values (
          p_league_id, v_candidate.player_id, v_team.id, v_candidate.overall,
          v_candidate.eta, v_wage, 100, 0, v_off.stagione_a
        );
      else
        update public.player_instances
        set team_id = v_team.id,
            ingaggio = v_wage,
            contratto_scadenza = v_off.stagione_a,
            condizione = 100,
            infortunato_fino_a = 0
        where id = v_candidate.instance_id and team_id is null;
      end if;

      v_ingaggi := v_ingaggi + v_wage;
      v_da_aggiungere := v_da_aggiungere - 1;
      v_aggiunti := array_append(v_aggiunti, v_candidate.nome);
    end loop;

    select count(*)::integer, coalesce(sum(ingaggio), 0)::bigint
    into v_rosa, v_ingaggi
    from public.player_instances
    where team_id = v_team.id and not ritirato;

    if v_rosa not between 21 and 30 then
      raise exception using errcode = '55000', message = 'La rosa di ' || v_team.nome || ' non rispetta il limite 21-30.';
    end if;
    if v_team.budget < v_ingaggi then
      raise exception using errcode = '55000', message = 'Budget insufficiente per gli ingaggi di ' || v_team.nome || '.';
    end if;

    update public.draft_team_state
    set stato = 'concluso', aggiornato_il = clock_timestamp()
    where league_id = p_league_id and team_id = v_team.id and stato <> 'concluso';

    update public.teams set budget = budget - v_ingaggi where id = v_team.id;
    insert into public.transactions(league_id, team_id, tipo, importo, descrizione, saldo_dopo)
    values (p_league_id, v_team.id, 'ingaggi_stagione', -v_ingaggi,
            'Ingaggi stagione ' || v_off.stagione_a, v_team.budget - v_ingaggi);

    if cardinality(v_aggiunti) > 0 or v_rilasciati > 0 then
      perform private.notifica(
        v_team.user_id, p_league_id, 'sistema', 'Rosa completata automaticamente',
        case when cardinality(v_aggiunti) > 0
          then cardinality(v_aggiunti) || ' svincolati aggiunti per raggiungere il minimo di 21 giocatori.'
          else 'Rosa riequilibrata automaticamente per rispettare il budget.' end,
        jsonb_build_object('view', 'team', 'aggiunti', cardinality(v_aggiunti), 'rilasciati', v_rilasciati)
      );
    end if;
  end loop;

  update public.offseasons
  set stato = 'conclusa', conclusa_il = clock_timestamp()
  where id = v_off.id;
  update public.leagues
  set stagione_corrente = v_off.stagione_a,
      fase_carriera = 'normale',
      offseason_fine = null,
      stato = 'stagione'
  where id = p_league_id;

  -- Annuncio del ritiro: a inizio stagione (qui), non a fine. Chi lo annuncia
  -- gioca comunque tutta la nuova stagione — la rimozione vera avviene alla
  -- prossima prepara_offseason, non qui.
  for v_player in
    select pi.id, pi.eta_corrente, p.nome, t.user_id
    from public.player_instances pi
    join public.players p on p.id = pi.player_id
    join public.teams t on t.id = pi.team_id and t.attiva
    where pi.league_id = p_league_id and not pi.ritirato and not pi.ritiro_annunciato
      and pi.eta_corrente >= 34
      and random() < private.probabilita_ritiro(pi.eta_corrente)
  loop
    update public.player_instances set ritiro_annunciato = true where id = v_player.id;
    perform private.notifica(v_player.user_id, p_league_id, 'sistema',
      v_player.nome || ' annuncia il ritiro',
      'Giochera'' ancora questa stagione, poi lascera'' la carriera: non puo'' essere ceduto in trattativa.',
      jsonb_build_object('player_instance_id', v_player.id));
  end loop;

  -- Stesso calcolo per chi non e' mai stato scelto da nessuno: niente
  -- player_instances a cui appendere lo stato, quindi l'esito va nella
  -- tabella dedicata. Eta' derivata: il pool degli svincolati pesca sempre
  -- fresco dal catalogo, non fa mai invecchiare le istanze non possedute.
  insert into public.retired_players(league_id, player_id, stagione)
  select p_league_id, p.id, v_off.stagione_a
  from public.players p
  where p.campionato = any(v_league.campionati_attivi)
    and not exists (
      select 1 from public.player_instances pi
      where pi.league_id = p_league_id and pi.player_id = p.id and pi.team_id is not null
    )
    and not exists (
      select 1 from public.retired_players rp
      where rp.league_id = p_league_id and rp.player_id = p.id
    )
    and (p.eta + (v_off.stagione_a - 1)) >= 34
    and random() < private.probabilita_ritiro(least(45, p.eta + (v_off.stagione_a - 1))::smallint)
  on conflict do nothing;

  v_season := private.inizializza_stagione(p_league_id);

  perform private.notifica(
    t.user_id, p_league_id, 'sistema', 'La nuova stagione e'' iniziata',
    'La prima giornata si giochera'' alle 23:00. Prepara la formazione.',
    jsonb_build_object('view', 'overview', 'season_id', v_season)
  )
  from public.teams t
  where t.league_id = p_league_id and t.attiva;

  return jsonb_build_object(
    'league_id', p_league_id,
    'season_id', v_season,
    'stagione', v_off.stagione_a,
    'prima_giornata', private.primo_calcio_dopo(v_off.scade_il)
  );
end;
$function$;
