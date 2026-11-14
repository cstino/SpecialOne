-- Primo contratto dal vivaio: il minutaggio promesso si vede e si tratta, come al rinnovo (richiesta del committente,
-- 14/11/2026). Prima lo assegnava in silenzio il trigger della firma: il gradino che il ragazzo chiede (di solito
-- «promessa futura», ma «titolare fisso» se e' gia' da titolare). Ora la proposta elenca i gradini con la loro
-- richiesta e l'offerta puo' sceglierne uno; senza sceglierlo resta tutto com'era.
-- Formule: private.richiesta_per_gradino e private.gradino_rifiutato, le stesse del rinnovo (docs/decisioni-minutaggio.md).

begin;

drop function public.offri_promozione(bigint, bigint, smallint, text);

CREATE OR REPLACE FUNCTION public.offri_promozione(p_vivaio_id bigint, p_ingaggio bigint, p_durata smallint DEFAULT 1, p_opzione text DEFAULT NULL::text, p_minutaggio text DEFAULT NULL::text)
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
  v_richiesto text;
  v_media numeric;
  v_rifiuto text;
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
  if p_minutaggio is not null and p_minutaggio not in ('titolare', 'turnover', 'sporadico', 'promessa') then
    raise exception using errcode = '22023', message = 'Minutaggio non valido.';
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
  -- Minutaggio promesso (14/11/2026): si tratta come al rinnovo. Il gradino offerto sposta la richiesta; uno non alla
  -- sua altezza lo rifiuta senza consumare un tentativo. Senza sceglierlo vale quello che chiede (come prima).
  if v_league.tattiche_attive then
    v_richiesto := private.gradino_richiesto(v_league.id, v_player.overall::smallint, v_player.eta::smallint,
                     (coalesce(v_prospetto.posizioni_override, v_player.posizioni))[1]);
    if p_minutaggio is not null and v_richiesto is not null then
      select avg(x.overall_corrente) into v_media
      from public.player_instances x where x.team_id = v_squadra.id and not x.ritirato;
      v_rifiuto := private.gradino_rifiutato(p_minutaggio, v_richiesto, v_player.eta::smallint, v_player.overall::smallint, v_media);
      if v_rifiuto is not null then
        return jsonb_build_object(
          'esito', 'gradino_rifiutato',
          'tentativi_usati', v_prospetto.promozione_tentativi,
          'tentativi_totali', 3,
          'messaggio', case
            when p_minutaggio = 'promessa' and v_player.eta >= 21 then 'Mister, non sono più un ragazzino.'
            else 'Con tutto il rispetto, mister: non salgo in prima squadra per fare panchina.' end,
          'motivo', v_rifiuto
        );
      end if;
      v_richiesta := private.richiesta_per_gradino(v_richiesta, p_minutaggio, v_richiesto);
    end if;
  end if;
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

    -- Il trigger della firma ha gia' messo il gradino che chiede (e la stagione d'arrivo): quello trattato lo sostituisce.
    if v_league.tattiche_attive and p_minutaggio is not null and v_richiesto is not null then
      update public.player_instances set minutaggio_promesso = p_minutaggio
      where id = v_istanza.id returning * into v_istanza;
    end if;

    update public.cambi_ruolo set player_instance_id = v_istanza.id, vivaio_id = null where vivaio_id = v_prospetto.id;
    update public.specializzazioni_giocatore set player_instance_id = v_istanza.id, vivaio_id = null where vivaio_id = v_prospetto.id;

    insert into private.registro_trattative (league_id, team_id, tipo, player_id, vivaio_id, offerta, richiesta, soglia,
    tolleranza, morale, durata, opzione, gradino, esito)
  values (v_prospetto.league_id, v_squadra.id, 'primo_contratto', v_prospetto.player_id, v_prospetto.id, p_ingaggio, v_richiesta, round(v_soglia),
    v_tolleranza, 50, p_durata, p_opzione, coalesce(p_minutaggio, v_richiesto), 'accettato');
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
      'minutaggio', v_istanza.minutaggio_promesso,
      'tentativi_usati', 0,
      'messaggio', 'Ci sto, mister. Non vedo l''ora di debuttare.'
    );
  end if;

  v_tentativi := (v_prospetto.promozione_tentativi + 1)::smallint;
  update public.vivaio_prospetti set promozione_tentativi = v_tentativi where id = v_prospetto.id;
  insert into private.registro_trattative (league_id, team_id, tipo, player_id, vivaio_id, offerta, richiesta, soglia,
    tolleranza, morale, durata, opzione, gradino, esito)
  values (v_prospetto.league_id, v_squadra.id, 'primo_contratto', v_prospetto.player_id, v_prospetto.id, p_ingaggio, v_richiesta, round(v_soglia),
    v_tolleranza, 50, p_durata, p_opzione, coalesce(p_minutaggio, v_richiesto), case when v_tentativi >= 3 then 'chiusa' else 'rifiutato' end);

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

revoke all on function public.offri_promozione(bigint, bigint, smallint, text, text) from public, anon;
grant execute on function public.offri_promozione(bigint, bigint, smallint, text, text) to authenticated, service_role;

CREATE OR REPLACE FUNCTION public.proposta_promozione(p_vivaio_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_user_id uuid := (select auth.uid());
  v_prospetto public.vivaio_prospetti;
  v_league public.leagues;
  v_player public.players;
  v_proposta record;
  v_pluri boolean;
  v_molt jsonb := '[]'::jsonb;
  v_d integer;
  v_o text;
  v_gradini jsonb := '[]'::jsonb;
  v_g text;
  v_richiesto text;
  v_media numeric;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'Devi accedere prima di trattare una promozione.';
  end if;

  select * into v_prospetto from public.vivaio_prospetti where id = p_vivaio_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Prospetto non trovato.';
  end if;
  if not exists (
    select 1 from public.teams where id = v_prospetto.team_id and user_id = v_user_id
  ) then
    raise exception using errcode = '42501', message = 'Questo prospetto non è tuo.';
  end if;

  select * into v_league from public.leagues where id = v_prospetto.league_id;
  if v_league.stato <> 'stagione' then
    raise exception using errcode = '55000', message = 'La promozione si tratta solo a stagione avviata.';
  end if;

  select * into v_player from public.players where id = v_prospetto.player_id;
  select * into v_proposta
  from private.rinnovo_proposta(
    v_prospetto.id, v_player.overall, v_player.eta, v_prospetto.ingaggio,
    coalesce(v_player.mentalita_bandiera, 33::smallint), coalesce(v_player.mentalita_economia, 33::smallint)
  );

  -- Minutaggio promesso (14/11/2026): gli stessi gradini del rinnovo, ognuno con la sua richiesta o col motivo del no.
  if v_league.tattiche_attive then
    v_richiesto := private.gradino_richiesto(v_league.id, v_player.overall::smallint, v_player.eta::smallint,
                     (coalesce(v_prospetto.posizioni_override, v_player.posizioni))[1]);
    if v_richiesto is not null then
      select avg(x.overall_corrente) into v_media
      from public.player_instances x where x.team_id = v_prospetto.team_id and not x.ritirato;
      foreach v_g in array array['titolare', 'turnover', 'sporadico', 'promessa'] loop
        v_gradini := v_gradini || jsonb_build_object(
          'chiave', v_g,
          'richiesta', private.richiesta_per_gradino(v_proposta.richiesta, v_g, v_richiesto),
          'rifiuto', private.gradino_rifiutato(v_g, v_richiesto, v_player.eta::smallint, v_player.overall::smallint, v_media)
        );
      end loop;
    end if;
  end if;

  -- Contratti pluriennali anche per il primo contratto (9/11/2026): 1-3 stagioni + opzione, stessi moltiplicatori
  -- del rinnovo (il giovane che sa di crescere chiede di piu' per legarsi a lungo), morale neutro.
  v_pluri := private.pluriennali_attivi(v_league.id);
  if v_pluri then
    foreach v_o in array array['', 'squadra', 'giocatore'] loop
      for v_d in 1..3 loop
        v_molt := v_molt || jsonb_build_object(
          'durata', v_d, 'opzione', nullif(v_o, ''),
          'moltiplicatore', private.moltiplicatore_durata(v_player.eta, v_player.overall, v_player.potential,
                                                          50::smallint, v_d::smallint, nullif(v_o, '')));
      end loop;
    end loop;
  end if;

  return jsonb_build_object(
    'pluriennali', v_pluri,
    'stagione_corrente', v_league.stagione_corrente,
    'moltiplicatori', case when v_pluri then v_molt end,
    'ingaggio_massimo', private.ingaggio_massimo(),
    'ingaggio_attuale', v_prospetto.ingaggio,
    'richiesta', v_proposta.richiesta,
    'gradino_richiesto', v_richiesto,
    'gradini', case when v_richiesto is not null then v_gradini end,
    'tentativi_usati', v_prospetto.promozione_tentativi,
    'tentativi_totali', 3,
    'trattativa_chiusa', v_prospetto.promozione_tentativi >= 3
  );
end;
$function$;

commit;
