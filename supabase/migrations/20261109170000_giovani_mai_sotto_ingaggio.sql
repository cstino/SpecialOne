-- Trattativa dei giovani che crescono ancora (fino a 23 anni, almeno 3 punti di margine sul potenziale), primo contratto
-- e rinnovo (decisione del committente, 9/11/2026): non accettano mai meno di quanto prendono gia', e il sovrapprezzo
-- per gli anni in piu' si conta su quella cifra. Prima lo sconto (fino al 35%) portava un prodigio del vivaio che
-- prende 1,0 M a firmare 0,9 M per tre stagioni. Chi chiede gia' molto piu' di quanto prende non cambia.

begin;

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
  -- Chi cresce ancora (fino a 23 anni, almeno 3 punti di margine) non scende mai sotto quanto prende gia', e il
  -- sovrapprezzo per gli anni in piu' si conta su quella cifra (9/11/2026, decisione del committente).
  if v_inst.eta_corrente <= 23 and coalesce(v_player.potential, v_inst.overall_corrente) - v_inst.overall_corrente >= 3 then
    v_soglia := least(v_richiesta, greatest(v_soglia, v_inst.ingaggio * coalesce(v_molt, 1)));
  end if;

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

CREATE OR REPLACE FUNCTION public.offri_promozione(p_vivaio_id bigint, p_ingaggio bigint, p_durata smallint DEFAULT 1, p_opzione text DEFAULT NULL::text)
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
  v_pluri boolean;
  v_richiesta bigint;
  v_fine integer;
  v_s integer;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'Devi accedere prima di trattare una promozione.';
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

  -- Contratti pluriennali (9/11/2026): la durata e l'opzione spostano la richiesta come nel rinnovo.
  v_pluri := private.pluriennali_attivi(v_league.id);
  if not v_pluri and (p_durata <> 1 or p_opzione is not null) then
    raise exception using errcode = '22023', message = 'In questa stagione il primo contratto dura fino a fine stagione.';
  end if;
  v_richiesta := v_proposta.richiesta;
  if v_pluri then
    v_richiesta := least(private.ingaggio_massimo(), greatest(500000, round(v_richiesta
      * private.moltiplicatore_durata(v_player.eta, v_player.overall, v_player.potential, 50::smallint, p_durata, p_opzione)
      / 100000) * 100000))::bigint;
  end if;

  select coalesce(st.posizione, 1) into v_posizione
  from public.seasons se
  join public.standings st on st.season_id = se.id and st.team_id = v_squadra.id
  where se.league_id = v_prospetto.league_id and se.numero = v_league.stagione_corrente;

  v_tolleranza := private.tolleranza_trattativa(
    50::smallint, coalesce(v_player.mentalita_bandiera, 33::smallint), coalesce(v_player.mentalita_economia, 33::smallint),
    coalesce(v_player.mentalita_vittorie, 34::smallint), v_squadra.id
  );
  v_soglia := v_richiesta * (1 - v_tolleranza);
  -- Chi cresce ancora (fino a 23 anni, almeno 3 punti di margine) non scende mai sotto quanto prende in cantera, e il
  -- sovrapprezzo per gli anni in piu' si conta su quella cifra (9/11/2026, decisione del committente).
  if v_player.eta <= 23 and coalesce(v_player.potential, v_player.overall) - v_player.overall >= 3 then
    v_soglia := least(v_richiesta, greatest(v_soglia, v_prospetto.ingaggio * case when v_pluri
      then private.moltiplicatore_durata(v_player.eta, v_player.overall, v_player.potential, 50::smallint, p_durata, p_opzione) else 1 end));
  end if;
  v_rapporto := p_ingaggio / greatest(1, v_soglia);

  if v_rapporto >= 1 then
    perform private.verifica_capienza(v_squadra.id, p_ingaggio, private.stagione_contratto(v_prospetto.league_id));
    -- Ogni stagione coperta dal contratto, compresa quella dell'opzione del giocatore (puo' esercitarla lui).
    v_fine := private.stagione_contratto(v_prospetto.league_id) + p_durata - 1 + case when p_opzione = 'giocatore' then 1 else 0 end;
    for v_s in (private.stagione_contratto(v_prospetto.league_id) + 1)..v_fine loop
      perform private.verifica_capienza(v_squadra.id, p_ingaggio, v_s::smallint);
    end loop;

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
    -- Il trigger fissa la scadenza alla stagione in corso: il contratto dura p_durata stagioni contando questa.
    if p_durata > 1 or p_opzione is not null then
      update public.player_instances
      set contratto_scadenza = v_istanza.contratto_scadenza + p_durata - 1, opzione_contratto = p_opzione
      where id = v_istanza.id returning * into v_istanza;
    end if;

    update public.cambi_ruolo set player_instance_id = v_istanza.id, vivaio_id = null where vivaio_id = v_prospetto.id;
    update public.specializzazioni_giocatore set player_instance_id = v_istanza.id, vivaio_id = null where vivaio_id = v_prospetto.id;

    delete from public.vivaio_prospetti where id = v_prospetto.id;

    perform private.notifica(v_user_id, v_league.id, 'sistema', 'Prospetto promosso in prima squadra',
      v_player.nome || ' firma il primo contratto: ' || private.in_milioni(p_ingaggio) || ' M€ a stagione fino alla stagione '
        || v_istanza.contratto_scadenza
        || case p_opzione when 'squadra' then ' (+1 opzione squadra)' when 'giocatore' then ' (+1 opzione giocatore)' else '' end || '.',
      jsonb_build_object('player_instance_id', v_istanza.id));

    return jsonb_build_object(
      'esito', 'accettato',
      'ingaggio', p_ingaggio,
      'durata', p_durata,
      'opzione', p_opzione,
      'contratto_scadenza', v_istanza.contratto_scadenza,
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

commit;
