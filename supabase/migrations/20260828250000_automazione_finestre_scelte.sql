-- ============================================================
--  MERCATO A SCELTE: AUTOMAZIONE COMPLETA
--  docs/decisioni-draft-picks.md §2.1, §3.1, §3.1 bis, §4
--
--  Tutti i pezzi del mercato a scelte esistevano ma nessuno partiva da
--  solo: genera_scelte_draft, assegna_posizioni_transizione,
--  svela_finestra_scelte e risolvi_finestra_scelte erano tutte funzioni
--  service_role senza nessun chiamante automatico. Verificato prima di
--  questa migrazione: zero cron job le invocano (select su cron.job) e
--  zero migrazioni le chiamano da un trigger o da un'altra funzione.
--
--  Questa migrazione aggancia le quattro fasi al ciclo di vita reale
--  della lega:
--
--   1. inizio stagione (private.inizializza_stagione) ->
--      genera l'inventario 4 stagioni avanti, assegna le posizioni di
--      transizione se e' la stagione 2, svela la finestra ON-Season se
--      le posizioni sono pronte
--   2. scadenza dell'estrazione ON-Season -> nuovo cron, risolve e
--      subito svela la finestra OFF-Season della stessa stagione
--   3. fine dell'off-season (private.finalizza_offseason) -> risolve la
--      finestra OFF-Season PRIMA di completare le rose, cosi' i
--      giocatori scelti contano nel minimo di 21
--
--  Tutta la logica nuova e' avvolta in blocchi che intercettano
--  qualunque eccezione e non la rilanciano MAI: inizializza_stagione e
--  finalizza_offseason sono funzioni critiche gia' corrette due volte
--  oggi per blocchi in produzione (20260828230000, 20260828240000). Un
--  bug in questa automazione non deve MAI poter impedire a una stagione
--  di iniziare o a un'off-season di chiudersi — nel peggiore dei casi,
--  quella finestra resta da sistemare a mano, esattamente come oggi.
-- ============================================================

-- ------------------------------------------------------------
--  Le 13:00 di Roma dello stesso giorno solare di un istante, DST-safe:
--  si prende il giorno civile a Roma e ci si aggiungono 13 ore lette
--  come orario locale di Roma, non UTC.
-- ------------------------------------------------------------
create or replace function private.alle_13_roma(p_istante timestamptz)
returns timestamptz
language sql
immutable
set search_path = ''
as $$
  select (date_trunc('day', p_istante at time zone 'Europe/Rome') + interval '13 hours')
         at time zone 'Europe/Rome'
$$;

comment on function private.alle_13_roma(timestamptz) is
  'Le 13:00 di Roma dello stesso giorno solare dell''istante dato, robusto al cambio ora legale.';

-- ------------------------------------------------------------
--  private.inizializza_stagione: tre aggiunte in coda, tutte
--  best-effort. Corpo identico a prima fino al return, che diventa
--  l'ultima riga del blocco protetto.
-- ------------------------------------------------------------
create or replace function private.inizializza_stagione(p_league_id bigint)
returns bigint
language plpgsql
set search_path = ''
as $function$
declare
  v_league public.leagues;
  v_season_id bigint;
  v_teams bigint[];
  v_rotation bigint[];
  v_next bigint[];
  v_team_count integer;
  v_slot_count integer;
  v_rounds integer;
  v_giornata integer;
  v_home bigint;
  v_away bigint;
  v_swap bigint;
  v_scadenza timestamptz;
  v_prima_giornata timestamptz;
  v_start date;
  v_campo_neutro boolean;
  v_giornata_mezza integer;
  v_data_mezza timestamptz;
  v_gia_assegnate integer;
begin
  select * into v_league from public.leagues where id = p_league_id for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Lega non trovata.';
  end if;

  select id into v_season_id
  from public.seasons
  where league_id = p_league_id and numero = v_league.stagione_corrente;
  if found then return v_season_id; end if;

  if v_league.stato <> 'stagione' or v_league.fase_carriera <> 'normale' then
    raise exception using errcode = '55000', message = 'La lega non e'' pronta per iniziare la stagione.';
  end if;

  select coalesce(array_agg(t.id order by t.ordine_draft nulls last, t.id), array[]::bigint[]), count(*)::integer
  into v_teams, v_team_count
  from public.teams t
  where t.league_id = p_league_id and t.attiva;

  if v_team_count <> v_league.n_squadre then
    raise exception using errcode = '55000', message = 'Il numero di squadre attive non coincide con le impostazioni.';
  end if;

  select o.scade_il into v_scadenza
  from public.offseasons o
  where o.league_id = p_league_id and o.stagione_a = v_league.stagione_corrente
  order by o.id desc limit 1;

  v_prima_giornata := private.primo_calcio_dopo(coalesce(v_scadenza, clock_timestamp()));
  v_start := (v_prima_giornata at time zone 'Europe/Rome')::date;

  -- Il numero di giornate viene FISSATO qui e non si tocca piu'.
  -- leagues.giornate_totali e' una colonna generata da n_squadre e n_gironi:
  -- se l'admin aggiunge squadre o cambia i gironi cambia anche per le stagioni
  -- gia' giocate, che si ritrovano "21 giornate su 33". Da qui in poi la
  -- verita' sulla durata di una stagione sta nella stagione stessa.
  insert into public.seasons(league_id, numero, stato, data_inizio, data_fine, giornate_totali)
  values (p_league_id, v_league.stagione_corrente, 'in_corso', v_start,
          v_start + (v_league.giornate_totali - 1), v_league.giornate_totali)
  returning id into v_season_id;

  insert into public.standings(season_id, league_id, team_id, posizione)
  select v_season_id, p_league_id, t.id,
         row_number() over(order by t.nome, t.id)::smallint
  from public.teams t
  where t.league_id = p_league_id and t.attiva;

  v_slot_count := v_team_count + (v_team_count % 2);
  v_rounds := v_slot_count - 1;
  for v_leg in 1..v_league.n_gironi loop
    v_campo_neutro := (v_league.n_gironi % 2 = 1 and v_leg = v_league.n_gironi);
    v_rotation := v_teams;
    if v_team_count % 2 = 1 then
      v_rotation := array_append(v_rotation, null::bigint);
    end if;
    for v_round in 1..v_rounds loop
      v_giornata := (v_leg - 1) * v_rounds + v_round;
      for v_pair in 1..(v_slot_count / 2) loop
        v_home := v_rotation[v_pair];
        v_away := v_rotation[v_slot_count - v_pair + 1];
        if v_home is null or v_away is null then continue; end if;
        -- Il lato casa/trasferta dipende SOLO dalla parita' della giornata.
        -- Prima entrava nel conto anche l'indice della coppia: siccome nel
        -- metodo del cerchio una squadra che ruota cambia coppia di +/-1 a
        -- ogni giornata, quella somma manteneva la stessa parita' per mezzo
        -- giro e la squadra restava inchiodata in casa o in trasferta.
        -- Verificato per 4-20 squadre e 2-4 gironi: al massimo 2 partite
        -- consecutive nello stesso campo (3 a squadre dispari, per via dei
        -- turni di riposo) e bilanciamento esatto.
        if mod(v_round, 2) = 0 then
          v_swap := v_home; v_home := v_away; v_away := v_swap;
        end if;
        if mod(v_leg, 2) = 0 then
          v_swap := v_home; v_home := v_away; v_away := v_swap;
        end if;
        insert into public.fixtures(season_id, league_id, giornata, home_team_id, away_team_id, data_sim, campo_neutro)
        values (v_season_id, p_league_id, v_giornata, v_home, v_away,
                v_prima_giornata + ((v_giornata - 1) * interval '1 day'), v_campo_neutro);
      end loop;
      v_next := array[v_rotation[1], v_rotation[v_slot_count]];
      for v_index in 2..(v_slot_count - 1) loop
        v_next := array_append(v_next, v_rotation[v_index]);
      end loop;
      v_rotation := v_next;
    end loop;
  end loop;

  -- ------------------------------------------------------------
  --  Mercato a scelte: inventario, posizioni di transizione, apertura
  --  ON-Season. Tutto best-effort — non deve mai impedire alla stagione
  --  di iniziare (docs/decisioni-draft-picks.md §2.1, §3.1).
  -- ------------------------------------------------------------
  begin
    perform private.genera_scelte_draft(p_league_id);

    if v_league.stagione_corrente = 2 then
      select count(*) into v_gia_assegnate
      from public.scelte_draft
      where league_id = p_league_id and stagione = 2 and stato <> 'futura';
      if v_gia_assegnate = 0 then
        perform private.assegna_posizioni_transizione(p_league_id, 2::smallint);
      end if;
    end if;

    if v_league.stagione_corrente >= 2 then
      select count(*) into v_gia_assegnate
      from public.scelte_draft
      where league_id = p_league_id and stagione = v_league.stagione_corrente
        and finestra = 'on' and stato = 'determinata';
      if v_gia_assegnate > 0 and not exists (
        select 1 from public.finestre_scelte
        where league_id = p_league_id and stagione = v_league.stagione_corrente and finestra = 'on'
      ) then
        v_giornata_mezza := v_league.giornate_totali / 2;
        select f.data_sim into v_data_mezza
        from public.fixtures f
        where f.season_id = v_season_id and f.giornata = v_giornata_mezza and f.bracket_tie_id is null
        limit 1;
        if v_data_mezza is not null then
          perform private.svela_finestra_scelte(
            p_league_id, v_league.stagione_corrente, 'on', private.alle_13_roma(v_data_mezza)
          );
        end if;
      end if;
    end if;
  exception when others then
    raise warning 'mercato a scelte: inizializzazione fallita per lega %: % (%)', p_league_id, sqlerrm, sqlstate;
  end;

  return v_season_id;
end;
$function$;

-- ------------------------------------------------------------
--  Cron: risolve le finestre ON-Season scadute, poi svela la OFF-Season
--  della stessa stagione. La OFF-Season non si risolve qui: si risolve
--  in finalizza_offseason, perche' la sua scadenza E' offseason_fine e
--  quella funzione gia' gira esattamente a quella scadenza.
-- ------------------------------------------------------------
create or replace function private.avanza_finestre_scelte()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_lega record;
  v_giornata_mezza integer;
  v_data_mezza timestamptz;
  v_finestra record;
  v_risolte integer := 0;
begin
  -- Passaggio di recupero: leghe la cui stagione corrente e' iniziata
  -- PRIMA che questa automazione esistesse (es. LegaBot, stagione 2 gia'
  -- in corso al momento di questa migrazione). inizializza_stagione fa lo
  -- stesso lavoro alla nascita di ogni stagione successiva; qui si
  -- recupera solo chi e' rimasto indietro, ed e' innocuo ripeterlo:
  -- svela_finestra_scelte non ritocca una finestra gia' svelata.
  for v_lega in
    select l.id as league_id, l.stagione_corrente, s.id as season_id, s.giornate_totali
    from public.leagues l
    join public.seasons s on s.league_id = l.id and s.numero = l.stagione_corrente
    where l.stato = 'stagione' and l.fase_carriera = 'normale' and l.stagione_corrente >= 2
      and exists (
        select 1 from public.scelte_draft sd
        where sd.league_id = l.id and sd.stagione = l.stagione_corrente
          and sd.finestra = 'on' and sd.stato = 'determinata'
      )
      and not exists (
        select 1 from public.finestre_scelte f
        where f.league_id = l.id and f.stagione = l.stagione_corrente and f.finestra = 'on'
      )
  loop
    begin
      v_giornata_mezza := v_lega.giornate_totali / 2;
      select f.data_sim into v_data_mezza
      from public.fixtures f
      where f.season_id = v_lega.season_id and f.giornata = v_giornata_mezza and f.bracket_tie_id is null
      limit 1;
      if v_data_mezza is not null then
        perform private.svela_finestra_scelte(
          v_lega.league_id, v_lega.stagione_corrente, 'on', private.alle_13_roma(v_data_mezza)
        );
      end if;
    exception when others then
      raise warning 'mercato a scelte: recupero apertura ON-Season fallito per lega % stagione %: % (%)',
        v_lega.league_id, v_lega.stagione_corrente, sqlerrm, sqlstate;
    end;
  end loop;

  for v_finestra in
    select league_id, stagione, finestra
    from public.finestre_scelte
    where finestra = 'on' and risolta_il is null
      and estrazione_il is not null and estrazione_il <= now()
    order by league_id, stagione
  loop
    begin
      perform private.risolvi_finestra_scelte(v_finestra.league_id, v_finestra.stagione, 'on', true);
      v_risolte := v_risolte + 1;
      if not exists (
        select 1 from public.finestre_scelte
        where league_id = v_finestra.league_id and stagione = v_finestra.stagione and finestra = 'off'
      ) then
        perform private.svela_finestra_scelte(v_finestra.league_id, v_finestra.stagione, 'off');
      end if;
    exception when others then
      raise warning 'mercato a scelte: risoluzione ON-Season fallita per lega % stagione %: % (%)',
        v_finestra.league_id, v_finestra.stagione, sqlerrm, sqlstate;
    end;
  end loop;
  return v_risolte;
end;
$$;

comment on function private.avanza_finestre_scelte() is
  'Recupera l''apertura ON-Season per stagioni gia'' avviate, risolve le finestre ON-Season scadute e svela la OFF-Season successiva. Chiamata dal cron ogni pochi minuti.';

revoke all on function private.avanza_finestre_scelte() from public, anon, authenticated;

select cron.schedule(
  'avanza-finestre-scelte', '*/5 * * * *',
  $$select private.avanza_finestre_scelte();$$
);

-- ------------------------------------------------------------
--  finalizza_offseason: un blocco protetto in testa, prima di toccare
--  qualunque rosa. Se la finestra OFF-Season non e' mai stata svelata
--  (leghe non ancora sul mercato a scelte, o dove l'automazione sopra
--  non e' mai arrivata) non fa nulla: nessuna eccezione, nessun rumore.
-- ------------------------------------------------------------
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

  -- Mercato a scelte: la finestra OFF-Season di questa transizione si
  -- risolve ORA, prima di completare le rose sotto il minimo — cosi' i
  -- giocatori scelti contano gia' come rosa (docs/decisioni-draft-picks.md
  -- §3.1 bis: l'estrazione OFF-Season E' la scadenza dell'off-season).
  -- Best-effort: non deve mai impedire la chiusura dell'off-season.
  if exists (
    select 1 from public.finestre_scelte
    where league_id = p_league_id and stagione = v_off.stagione_a and finestra = 'off'
      and risolta_il is null
  ) then
    begin
      perform private.risolvi_finestra_scelte(p_league_id, v_off.stagione_a, 'off', true);
    exception when others then
      raise warning 'mercato a scelte: risoluzione OFF-Season fallita per lega % stagione %: % (%)',
        p_league_id, v_off.stagione_a, sqlerrm, sqlstate;
    end;
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
