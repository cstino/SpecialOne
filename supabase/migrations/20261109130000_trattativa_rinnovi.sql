-- Trattativa dei rinnovi (decisioni del committente, 9/11/2026). Prima lo sconto che un giocatore concede sulla sua
-- richiesta era stretto (bandiera 7,6% in media, economia 4,1%) e la "squadra vincente" era la posizione nella
-- classifica della stagione in corso (alla 1a giornata non dice niente). Da ora:
--   - la bandiera conta 4 volte di piu' (b/250), l'economia frena il doppio (e/500), tetto 35% (era 25%);
--   - chi ama vincere guarda le VITTORIE RECENTI della squadra: ultime 20 partite ufficiali a cavallo delle stagioni,
--     le ultime 5 contano doppio; sotto le 10 partite si completa con la media della lega (40%); il campione in
--     carica ha +15 punti. Sopra il 40% concede, sotto chiede di piu';
--   - niente pavimento: una bandiera in una squadra che vince puo' rinnovare a meno di quanto prende;
--   - nella trattativa l'app mostra una barra di soddisfazione con una zona sfumata di 10 punti dove cade la soglia;
--   - i 92 rinnovi fatti in Serie F dall'inizio della Season 3 si annullano (ingaggio, scadenza, opzione, tentativi
--     come prima; storno nel registro movimenti; notifica alle squadre) e si rifanno con le regole nuove. Esclusi i
--     rinnovi d'ufficio della Doomsday (Season 2). Gradino di minutaggio e morale restano come sono.

begin;

-- Vittorie recenti di una squadra (frazione 0-1, bonus del campione in carica compreso).
create or replace function private.vittorie_recenti(p_team_id bigint)
 returns numeric
 language sql
 stable security definer
 set search_path to ''
as $function$
  with ultime as (
    select case when (f.home_team_id = p_team_id and m.gol_home > m.gol_away)
                  or (f.away_team_id = p_team_id and m.gol_away > m.gol_home) then 1 else 0 end as vinta,
           row_number() over (order by m.simulata_il desc) as rn
    from public.fixtures f
    join public.matches m on m.fixture_id = f.id
    where p_team_id in (f.home_team_id, f.away_team_id)
    order by m.simulata_il desc
    limit 20
  ), pesate as (
    select coalesce(sum(vinta * case when rn <= 5 then 2 else 1 end), 0) as vinte,
           coalesce(sum(case when rn <= 5 then 2 else 1 end), 0) as peso,
           count(*) as partite
    from ultime
  )
  select (vinte + 0.40 * greatest(0, 10 - partite)) / greatest(1, peso + greatest(0, 10 - partite))
         + case when coalesce((select t.campione_in_carica from public.teams t where t.id = p_team_id), false)
                then 0.15 else 0 end
  from pesate;
$function$;

-- Lo sconto massimo che il giocatore concede sulla sua richiesta (0-0,35).
create or replace function private.tolleranza_trattativa(p_morale smallint, p_bandiera smallint, p_economia smallint,
                                                         p_vittorie smallint, p_team_id bigint)
 returns numeric
 language sql
 stable security definer
 set search_path to ''
as $function$
  select greatest(0.00, least(0.35,
    0.05                                    -- base: un 5% lo concede chiunque
    + (p_morale - 50) / 500.0                -- morale 100 -> +0,10 · morale 0 -> -0,10
    + p_bandiera / 250.0                     -- chi ama la maglia fa uno sconto
    - p_economia / 500.0                     -- chi guarda i soldi non lo fa
    -- chi ama vincere: piu' la squadra vince, piu' concede (fino a +/- meta' della sua quota di vittorie / 150)
    + greatest(-0.5, least(0.5, (private.vittorie_recenti(p_team_id) - 0.40) / 0.5)) * (p_vittorie / 150.0)
  ))::numeric;
$function$;

CREATE OR REPLACE FUNCTION public.offri_rinnovo(p_instance_id bigint, p_ingaggio bigint, p_durata smallint, p_minutaggio text DEFAULT NULL::text, p_opzione text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_user_id uuid := (select auth.uid());
  v_inst public.player_instances;
  v_league public.leagues;
  v_team public.teams;
  v_player public.players;
  v_proposta record;
  v_posizione smallint;
  v_tolleranza numeric;
  v_soglia numeric;
  v_valore numeric;
  v_rapporto numeric;
  v_scadenza smallint;
  v_tentativi smallint;
  v_gradino text;
  v_media numeric;
  v_rifiuto text;
  v_richiesta bigint;
  v_richiesto text;
  v_pluri boolean;
  v_molt numeric;
  v_fine integer;
  v_s integer;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'Devi accedere prima di trattare un rinnovo.';
  end if;
  if p_ingaggio < 500000 then
    raise exception using errcode = '22023', message = 'L''ingaggio minimo è 0,5 M€.';
  end if;
  if p_ingaggio > private.ingaggio_massimo() then
    raise exception using errcode = '22023',
      message = 'L''ingaggio massimo è ' || replace(round(private.ingaggio_massimo() / 1000000.0, 1)::text, '.', ',') || ' M€.';
  end if;
  if p_durata is null or p_durata not between 1 and 3 then
    raise exception using errcode = '22023', message = 'Il contratto dura da 1 a 3 stagioni.';
  end if;
  if p_opzione is not null and p_opzione not in ('squadra', 'giocatore') then
    raise exception using errcode = '22023', message = 'Opzione non valida.';
  end if;
  if p_minutaggio is not null and p_minutaggio not in ('titolare', 'turnover', 'sporadico', 'promessa') then
    raise exception using errcode = '22023', message = 'Minutaggio non valido.';
  end if;

  select * into v_inst from public.player_instances where id = p_instance_id for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Giocatore non trovato.';
  end if;

  select * into v_team from public.teams
  where id = v_inst.team_id and league_id = v_inst.league_id and user_id = v_user_id and attiva;
  if not found then
    raise exception using errcode = '42501', message = 'Questo giocatore non è nella tua rosa.';
  end if;

  select * into v_league from public.leagues where id = v_inst.league_id;
  if v_league.stato <> 'stagione' then
    raise exception using errcode = '55000', message = 'I rinnovi si trattano solo a stagione avviata.';
  end if;

  -- Contratti pluriennali (diario Season 3 §12): 1-3 stagioni + opzione, solo nell'ultima stagione del contratto.
  v_pluri := private.pluriennali_attivi(v_league.id);
  if not v_pluri and (p_durata <> 1 or p_opzione is not null) then
    raise exception using errcode = '22023',
      message = 'In questa stagione i contratti durano un anno: il rinnovo estende di una stagione.';
  end if;
  if v_pluri and v_inst.opzione_contratto = 'squadra' then
    raise exception using errcode = '55000',
      message = 'Ha un''opzione a favore della squadra: prima decidi se esercitarla o rinunciarci.';
  end if;
  if v_pluri and v_inst.opzione_contratto = 'giocatore' then
    raise exception using errcode = '55000',
      message = 'Ha un''opzione a suo favore: a fine stagione decide lui se restare un altro anno.';
  end if;
  if v_pluri and v_inst.contratto_scadenza > v_league.stagione_corrente then
    raise exception using errcode = '55000',
      message = 'Ha un contratto fino alla stagione ' || v_inst.contratto_scadenza || ': si rinnova nella sua ultima stagione.';
  end if;
  if v_inst.ritirato or v_inst.ritiro_annunciato then
    raise exception using errcode = '55000', message = 'Ha già annunciato il ritiro: non rinnoverà il contratto.';
  end if;
  if v_league.tattiche_attive and v_inst.richiesta_cessione_stagione is not null then
    raise exception using errcode = '55000', message = 'Ha chiesto la cessione: non rinnoverà il contratto.';
  end if;
  if v_inst.rinnovo_stagione is not null and v_inst.rinnovo_stagione = v_league.stagione_corrente then
    raise exception using errcode = '55000',
      message = 'Ha già rinnovato in questa stagione: se ne riparla dalla prossima.';
  end if;
  if v_inst.rinnovo_tentativi >= 3 then
    raise exception using errcode = '55000',
      message = 'Ha chiuso la trattativa: andrà a scadenza e lascerà la squadra.';
  end if;

  select * into v_player from public.players where id = v_inst.player_id;
  select * into v_proposta
  from private.rinnovo_proposta(
    v_inst.id, v_inst.overall_corrente, v_inst.eta_corrente, v_inst.ingaggio,
    v_player.mentalita_bandiera, v_player.mentalita_economia
  );

  -- Il gradino: quello offerto, o (senza sceglierlo) quello che ha gia'. Un
  -- gradino non alla sua altezza lo rifiuta senza consumare un tentativo.
  v_richiesta := v_proposta.richiesta;
  if v_league.tattiche_attive then
    v_richiesto := private.gradino_richiesto_istanza(v_inst.id);
    v_gradino := coalesce(p_minutaggio, private.gradino_effettivo(v_inst.id));
    if p_minutaggio is not null then
      select avg(x.overall_corrente) into v_media
      from public.player_instances x where x.team_id = v_inst.team_id and not x.ritirato;
      v_rifiuto := private.gradino_rifiutato(p_minutaggio, v_richiesto, v_inst.eta_corrente, v_inst.overall_corrente, v_media);
      if v_rifiuto is not null then
        return jsonb_build_object(
          'esito', 'gradino_rifiutato',
          'tentativi_usati', v_inst.rinnovo_tentativi,
          'tentativi_totali', 3,
          'messaggio', case
            when p_minutaggio = 'promessa' and v_inst.eta_corrente >= 21 then 'Mister, non sono più un ragazzino.'
            else 'Con tutto il rispetto, mister: non sono venuto qui per fare panchina.' end,
          'motivo', v_rifiuto
        );
      end if;
    end if;
    v_richiesta := private.richiesta_per_gradino(v_proposta.richiesta, v_gradino, v_richiesto);
  end if;

  -- Durata e opzione spostano la richiesta (private.moltiplicatore_durata). Chi e' molto scontento firma solo per un
  -- anno: la proposta lunga la rifiuta senza consumare un tentativo, come un gradino fuori misura.
  if v_pluri then
    if v_inst.morale < 30 and (p_durata > 1 or p_opzione is not null) then
      return jsonb_build_object(
        'esito', 'durata_rifiutata',
        'tentativi_usati', v_inst.rinnovo_tentativi,
        'tentativi_totali', 3,
        'messaggio', 'Mister, come sto adesso non mi lego per più di un anno.',
        'motivo', 'Con il morale sotto 30 firma solo per una stagione, senza opzione.'
      );
    end if;
    v_molt := private.moltiplicatore_durata(v_inst.eta_corrente, v_inst.overall_corrente, v_player.potential,
                                            v_inst.morale, p_durata, p_opzione);
    v_richiesta := least(private.ingaggio_massimo(), greatest(500000, round(v_richiesta * v_molt / 100000) * 100000))::bigint;
  end if;

  select coalesce(st.posizione, 1) into v_posizione
  from public.seasons se
  join public.standings st on st.season_id = se.id and st.team_id = v_inst.team_id
  where se.league_id = v_inst.league_id and se.numero = v_league.stagione_corrente;

  v_tolleranza := private.tolleranza_trattativa(
    v_inst.morale, v_player.mentalita_bandiera, v_player.mentalita_economia, v_player.mentalita_vittorie, v_inst.team_id
  );
  v_soglia := v_richiesta * (1 - v_tolleranza);

  v_valore := p_ingaggio;
  v_rapporto := v_valore / greatest(1, v_soglia);

  if v_rapporto >= 1 then
    -- Le due verifiche sono sotto lo stesso lock di squadra: due rinnovi
    -- contemporanei non possono consumare la medesima capienza.
    perform 1 from public.teams where id = v_team.id for update;
    perform private.verifica_capienza(
      v_team.id, p_ingaggio - v_inst.ingaggio, v_league.stagione_corrente
    );
    -- Ogni stagione coperta dal nuovo contratto, compresa quella dell'opzione del giocatore (puo' esercitarla lui).
    -- L'opzione della squadra si verifica quando la squadra la esercita.
    v_fine := v_league.stagione_corrente + case when v_pluri then p_durata + case when p_opzione = 'giocatore' then 1 else 0 end
                                                 else 1 end;
    for v_s in (v_league.stagione_corrente + 1)..v_fine loop
      perform private.verifica_capienza(
        v_team.id,
        p_ingaggio - case when v_inst.contratto_scadenza >= v_s then v_inst.ingaggio else 0 end,
        v_s::smallint
      );
    end loop;

    v_scadenza := case when v_pluri then (v_league.stagione_corrente + p_durata)::smallint
                       else greatest(v_inst.contratto_scadenza, (v_league.stagione_corrente + 1)::smallint) end;
    update public.player_instances
    set ingaggio = p_ingaggio,
        contratto_scadenza = v_scadenza,
        rinnovo_tentativi = 0,
        rinnovo_stagione = v_league.stagione_corrente,
        opzione_contratto = case when v_pluri then p_opzione else opzione_contratto end,
        -- Il gradino trattato diventa parte del contratto; senza sceglierlo
        -- resta com'era (anche automatico).
        minutaggio_promesso = case when v_league.tattiche_attive and p_minutaggio is not null
                                   then p_minutaggio else minutaggio_promesso end,
        richiamo_stagione = case when v_league.tattiche_attive and p_minutaggio is not null
                                 then null else richiamo_stagione end,
        richiamo_giornata = case when v_league.tattiche_attive and p_minutaggio is not null
                                 then null else richiamo_giornata end
    where id = v_inst.id;
    perform private.spinta_morale_rinnovo(v_inst.id);

    insert into public.transactions (league_id, team_id, tipo, importo, descrizione, saldo_dopo)
    values (
      v_inst.league_id, v_team.id, 'rinnovo_in_stagione',
      coalesce(nullif(v_inst.ingaggio - p_ingaggio, 0), 1),
      'Rinnovo: ' || coalesce(v_player.nome, 'giocatore') || ' — '
        || round(p_ingaggio / 1000000.0, 1) || ' M€ fino alla stagione ' || v_scadenza
        || case p_opzione when 'squadra' then ' (+1 opzione squadra)' when 'giocatore' then ' (+1 opzione giocatore)' else '' end,
      0
    );

    return jsonb_build_object(
      'esito', 'accettato',
      'ingaggio', p_ingaggio,
      'durata', p_durata,
      'opzione', p_opzione,
      'contratto_scadenza', v_scadenza,
      'tentativi_usati', 0,
      'minutaggio', v_gradino,
      'messaggio', 'Ci sto, mister. Grazie della fiducia.'
    );
  end if;

  v_tentativi := (v_inst.rinnovo_tentativi + 1)::smallint;
  update public.player_instances set rinnovo_tentativi = v_tentativi where id = v_inst.id;

  return jsonb_build_object(
    'esito', case when v_tentativi >= 3 then 'chiusa' else 'rifiutato' end,
    'tentativi_usati', v_tentativi,
    'tentativi_totali', 3,
    'messaggio', case
      when v_tentativi >= 3 then 'Basta così, mister. Andrò a scadenza.'
      when v_rapporto >= 0.95 then 'Ci siamo quasi, ma non ancora.'
      when v_rapporto >= 0.85 then 'È troppo poco per quello che valgo.'
      else 'Non se ne parla nemmeno, mister.'
    end
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.offri_promozione(p_vivaio_id bigint, p_ingaggio bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_user_id uuid := (select auth.uid());
  v_prospetto public.vivaio_prospetti;
  v_squadra public.teams;
  v_league public.leagues;
  v_player public.players;
  v_proposta record;
  v_posizione smallint;
  v_tolleranza numeric;
  v_soglia numeric;
  v_rapporto numeric;
  v_tentativi smallint;
  v_rosa integer;
  v_prossima integer;
  v_istanza public.player_instances;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'Devi accedere prima di trattare una promozione.';
  end if;
  if p_ingaggio < 500000 then
    raise exception using errcode = '22023', message = 'L''ingaggio minimo è 0,5 M€.';
  end if;

  select * into v_prospetto from public.vivaio_prospetti where id = p_vivaio_id for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Prospetto non trovato.';
  end if;

  select * into v_squadra from public.teams where id = v_prospetto.team_id and user_id = v_user_id;
  if not found then
    raise exception using errcode = '42501', message = 'Questo prospetto non è tuo.';
  end if;

  select * into v_league from public.leagues where id = v_prospetto.league_id;
  if v_league.stato <> 'stagione' then
    raise exception using errcode = '55000', message = 'La promozione si tratta solo a stagione avviata.';
  end if;
  if v_prospetto.promozione_tentativi >= 3 then
    raise exception using errcode = '55000',
      message = 'Ha chiuso la trattativa: resterà in cantera finché non scade il countdown.';
  end if;

  select count(*)::integer into v_rosa
  from public.player_instances where team_id = v_squadra.id and not ritirato;
  if v_rosa >= private.rosa_massima() then
    raise exception using errcode = '22023',
      message = 'La rosa è già al completo (' || private.rosa_massima() || '): libera un posto prima di promuovere.';
  end if;

  select * into v_player from public.players where id = v_prospetto.player_id;
  select * into v_proposta
  from private.rinnovo_proposta(
    v_prospetto.id, v_player.overall, v_player.eta, v_prospetto.ingaggio,
    coalesce(v_player.mentalita_bandiera, 33::smallint), coalesce(v_player.mentalita_economia, 33::smallint)
  );

  select coalesce(st.posizione, 1) into v_posizione
  from public.seasons se
  join public.standings st on st.season_id = se.id and st.team_id = v_squadra.id
  where se.league_id = v_prospetto.league_id and se.numero = v_league.stagione_corrente;

  v_tolleranza := private.tolleranza_trattativa(
    50::smallint, coalesce(v_player.mentalita_bandiera, 33::smallint), coalesce(v_player.mentalita_economia, 33::smallint),
    coalesce(v_player.mentalita_vittorie, 34::smallint), v_squadra.id
  );
  v_soglia := v_proposta.richiesta * (1 - v_tolleranza);
  v_rapporto := p_ingaggio / greatest(1, v_soglia);

  if v_rapporto >= 1 then
    perform private.verifica_capienza(v_squadra.id, p_ingaggio, private.stagione_contratto(v_prospetto.league_id));

    select min(f.giornata) into v_prossima
    from public.fixtures f where f.league_id = v_league.id and f.stato = 'programmata';

    -- Il training fatto nel vivaio passa con lui: ruoli, piano di sviluppo, attributi gia' spostati, cambio ruolo in corso.
    insert into public.player_instances
      (league_id, player_id, team_id, overall_corrente, eta_corrente, ingaggio, giornata_acquisizione,
       posizioni_override, specializzazione_attiva, piano_scostamenti, piano_overall_rif)
    values
      (v_prospetto.league_id, v_prospetto.player_id, v_squadra.id,
       v_player.overall, v_player.eta, p_ingaggio, v_prossima,
       v_prospetto.posizioni_override, v_prospetto.specializzazione_attiva, coalesce(v_prospetto.piano_scostamenti, '{}'::jsonb), v_prospetto.piano_overall_rif)
    returning * into v_istanza;

    update public.cambi_ruolo set player_instance_id = v_istanza.id, vivaio_id = null where vivaio_id = v_prospetto.id;
    update public.specializzazioni_giocatore set player_instance_id = v_istanza.id, vivaio_id = null where vivaio_id = v_prospetto.id;

    delete from public.vivaio_prospetti where id = v_prospetto.id;

    perform private.notifica(v_user_id, v_league.id, 'sistema', 'Prospetto promosso in prima squadra',
      v_player.nome || ' firma il primo contratto: ' || private.in_milioni(p_ingaggio) || ' M€ a stagione.',
      jsonb_build_object('player_instance_id', v_istanza.id));

    return jsonb_build_object(
      'esito', 'accettato',
      'ingaggio', p_ingaggio,
      'tentativi_usati', 0,
      'messaggio', 'Ci sto, mister. Non vedo l''ora di debuttare.'
    );
  end if;

  v_tentativi := (v_prospetto.promozione_tentativi + 1)::smallint;
  update public.vivaio_prospetti set promozione_tentativi = v_tentativi where id = v_prospetto.id;

  return jsonb_build_object(
    'esito', case when v_tentativi >= 3 then 'chiusa' else 'rifiutato' end,
    'tentativi_usati', v_tentativi,
    'tentativi_totali', 3,
    'messaggio', case
      when v_tentativi >= 3 then 'No, mister: così non firmo. Resto in cantera finché non scade il mio tempo.'
      when v_rapporto >= 0.95 then 'Ci siamo quasi, ma non ancora.'
      when v_rapporto >= 0.85 then 'È troppo poco per quello che valgo.'
      else 'Non se ne parla nemmeno, mister.'
    end
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.proposta_rinnovo(p_instance_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_user_id uuid := (select auth.uid());
  v_inst public.player_instances;
  v_league public.leagues;
  v_player public.players;
  v_proposta record;
  v_media numeric;
  v_gradini jsonb := '[]'::jsonb;
  v_g text;
  v_richiesto text;
  v_pluri boolean;
  v_molt jsonb := '[]'::jsonb;
  v_d integer;
  v_o text;
  v_soglia numeric;
  v_scarto numeric;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'Devi accedere prima di trattare un rinnovo.';
  end if;

  select * into v_inst from public.player_instances where id = p_instance_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Giocatore non trovato.';
  end if;

  if not exists (
    select 1 from public.teams
    where id = v_inst.team_id and league_id = v_inst.league_id and user_id = v_user_id
  ) then
    raise exception using errcode = '42501', message = 'Questo giocatore non e'' nella tua rosa.';
  end if;

  select * into v_league from public.leagues where id = v_inst.league_id;
  if v_league.stato <> 'stagione' then
    raise exception using errcode = '55000', message = 'I rinnovi si trattano solo a stagione avviata.';
  end if;
  if v_inst.ritirato or v_inst.ritiro_annunciato then
    raise exception using errcode = '55000', message = 'Ha gia'' annunciato il ritiro: non rinnovera'' il contratto.';
  end if;
  if v_league.tattiche_attive and v_inst.richiesta_cessione_stagione is not null then
    raise exception using errcode = '55000', message = 'Ha chiesto la cessione: non rinnovera'' il contratto.';
  end if;

  select * into v_player from public.players where id = v_inst.player_id;
  select * into v_proposta
  from private.rinnovo_proposta(
    v_inst.id, v_inst.overall_corrente, v_inst.eta_corrente, v_inst.ingaggio,
    v_player.mentalita_bandiera, v_player.mentalita_economia
  );

  if v_league.tattiche_attive then
    select avg(x.overall_corrente) into v_media
    from public.player_instances x where x.team_id = v_inst.team_id and not x.ritirato;
    v_richiesto := private.gradino_richiesto_istanza(v_inst.id);
    foreach v_g in array array['titolare', 'turnover', 'sporadico', 'promessa'] loop
      v_gradini := v_gradini || jsonb_build_object(
        'chiave', v_g,
        'richiesta', private.richiesta_per_gradino(v_proposta.richiesta, v_g, v_richiesto),
        'rifiuto', private.gradino_rifiutato(v_g, v_richiesto, v_inst.eta_corrente, v_inst.overall_corrente, v_media)
      );
    end loop;
  end if;

  -- Contratti pluriennali: moltiplicatore della richiesta per ogni durata e opzione (l'app lo applica al gradino scelto).
  v_pluri := private.pluriennali_attivi(v_league.id);
  if v_pluri then
    foreach v_o in array array['', 'squadra', 'giocatore'] loop
      for v_d in 1..3 loop
        v_molt := v_molt || jsonb_build_object(
          'durata', v_d, 'opzione', nullif(v_o, ''),
          'moltiplicatore', private.moltiplicatore_durata(v_inst.eta_corrente, v_inst.overall_corrente, v_player.potential,
                                                          v_inst.morale, v_d::smallint, nullif(v_o, '')));
      end loop;
    end loop;
  end if;

  -- La barra di soddisfazione (9/11/2026): l'app mostra una zona larga 10 punti (in frazione della richiesta) dentro
  -- cui cade la soglia di accettazione, non la soglia esatta. Dove cade la soglia dentro la zona e' fisso per
  -- giocatore e stagione: riaprire la trattativa non la rivela.
  v_soglia := 1 - private.tolleranza_trattativa(v_inst.morale, v_player.mentalita_bandiera, v_player.mentalita_economia,
                                                 v_player.mentalita_vittorie, v_inst.team_id);
  v_scarto := (abs(hashtext('zona:' || v_inst.id || ':' || v_league.stagione_corrente)) % 1000) / 1000.0;

  return jsonb_build_object(
    'player_instance_id', v_inst.id,
    'zona_accettazione', jsonb_build_object('da', round(greatest(0, v_soglia - v_scarto * 0.10), 3),
                                            'a', round(least(1, v_soglia + (1 - v_scarto) * 0.10), 3)),
    'ingaggio_attuale', v_inst.ingaggio,
    'scadenza_attuale', v_inst.contratto_scadenza,
    'stagione_corrente', v_league.stagione_corrente,
    'richiesta', v_proposta.richiesta,
    'durata', v_proposta.durata,
    'nuova_scadenza', greatest(v_inst.contratto_scadenza, (v_league.stagione_corrente + v_proposta.durata)::smallint),
    'tentativi_usati', v_inst.rinnovo_tentativi,
    'tentativi_totali', 3,
    'trattativa_chiusa', v_inst.rinnovo_tentativi >= 3,
    'gia_rinnovato', v_inst.rinnovo_stagione is not null and v_inst.rinnovo_stagione = v_league.stagione_corrente,
    'morale', v_inst.morale,
    'mentalita', jsonb_build_object(
      'bandiera', v_player.mentalita_bandiera,
      'economia', v_player.mentalita_economia,
      'vittorie', v_player.mentalita_vittorie
    ),
    -- Minutaggio (docs/decisioni-minutaggio.md): vuoto nelle leghe senza tattiche.
    'gradino_attuale', case when v_league.tattiche_attive then private.gradino_effettivo(v_inst.id) end,
    'gradino_richiesto', v_richiesto,
    'gradino_trattato', v_inst.minutaggio_promesso is not null,
    'gradini', case when v_league.tattiche_attive then v_gradini end,
    'pluriennali', v_pluri,
    'ultima_stagione', v_inst.contratto_scadenza <= v_league.stagione_corrente,
    'opzione', v_inst.opzione_contratto,
    'solo_un_anno', v_pluri and v_inst.morale < 30,
    'moltiplicatori', case when v_pluri then v_molt end,
    'ingaggio_massimo', private.ingaggio_massimo()
  );
end;
$function$;


-- Annullamento dei rinnovi della Season 3 (Serie F).
create temp table rinnovi_annullati on commit drop as
select t.id as tid, t.team_id, t.importo, t.descrizione, pi.id as pi_id, pi.ingaggio as nuovo,
       case when t.importo = 1 then pi.ingaggio else pi.ingaggio + t.importo end as vecchio
from public.transactions t
join public.players p on p.nome = substring(t.descrizione from '^Rinnovo: (.*) — ')
join public.player_instances pi on pi.player_id = p.id and pi.league_id = 63
where t.league_id = 63 and t.tipo = 'rinnovo_in_stagione' and t.creata_il > '2026-11-08 11:00'
  and t.descrizione like 'Rinnovo: %'
  and pi.team_id = t.team_id and pi.rinnovo_stagione = 3
  and pi.ingaggio = (substring(t.descrizione from '— ([0-9.]+) M€')::numeric * 1000000)::bigint;

do $$
begin
  if (select count(*) from rinnovi_annullati) <> 92 or (select count(distinct pi_id) from rinnovi_annullati) <> 92 then
    raise exception 'attesi 92 rinnovi da annullare, trovati %', (select count(*) from rinnovi_annullati);
  end if;
end $$;

update public.player_instances pi
set ingaggio = r.vecchio, contratto_scadenza = 3, opzione_contratto = null,
    rinnovo_stagione = null, rinnovo_tentativi = 0
from rinnovi_annullati r where pi.id = r.pi_id;

insert into public.transactions (league_id, team_id, tipo, importo, descrizione, saldo_dopo)
select 63, r.team_id, 'rinnovo_in_stagione', case when r.importo = 1 then 1 else -r.importo end,
       'Rinnovo annullato (nuove regole della trattativa): ' || substring(r.descrizione from '^Rinnovo: (.*)$'), 0
from rinnovi_annullati r order by r.tid;

select private.notifica(t.user_id, 63, 'sistema', 'Rinnovi annullati',
  'Le regole della trattativa sono cambiate: chi ama la maglia, e chi ama vincere in una squadra che vince, ora è disposto a scendere molto di più. '
  || 'I ' || n || ' rinnovi che avevi fatto in questa stagione sono stati annullati: i giocatori tornano al contratto di prima, in scadenza a fine stagione, e puoi rinnovarli di nuovo.',
  jsonb_build_object('view', 'squad'))
from (select team_id, count(*) n from rinnovi_annullati group by team_id) x
join public.teams t on t.id = x.team_id where t.user_id is not null;

commit;
