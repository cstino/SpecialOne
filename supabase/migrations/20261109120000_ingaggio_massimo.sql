-- Ingaggio massimo 16 M€ (decisione del committente, 9/11/2026): il 20% del tetto della Serie F. Vale per tutto il
-- gioco: la curva degli ingaggi (draft, scelte, aste, morale), la richiesta di rinnovo (anche chi prende gia' di piu'
-- al rinnovo scende a 16), i ritocchi per minutaggio e durata, e l'offerta dell'allenatore. I contratti in corso non
-- si toccano. Oggi in Serie F lo supererebbero al rinnovo solo Doue' (chiedeva 20,8) e Mbappe' (16,8).

begin;

create or replace function private.ingaggio_massimo()
 returns bigint
 language sql
 immutable parallel safe
 set search_path to ''
as $function$ select 16000000::bigint $function$;

CREATE OR REPLACE FUNCTION private.ingaggio_teorico(p_overall smallint, p_eta smallint)
 RETURNS bigint
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
 SET search_path TO ''
AS $function$
  -- Massimale (9/11/2026): nessun ingaggio teorico oltre private.ingaggio_massimo().
  select least(private.ingaggio_massimo()::numeric, greatest(
    500000::numeric,
    round((
      case
        when p_overall <= 65 then 0.5
        when p_overall <= 70 then 0.8
        when p_overall <= 74 then 1.2
        when p_overall <= 77 then 2.0
        when p_overall <= 80 then 3.2
        when p_overall <= 83 then 5.0
        when p_overall <= 85 then 7.5
        when p_overall <= 87 then 10.0
        when p_overall <= 89 then 13.0
        else 17.0
      end
      * case
        when p_eta between 16 and 20 then 1.25
        when p_eta between 21 and 23 then 1.10
        when p_eta between 24 and 26 then 1.00
        when p_eta between 27 and 30 then 0.95
        when p_eta between 31 and 32 then 0.80
        when p_eta between 33 and 34 then 0.60
        else 0.40
      end
      * 10
    )) * 100000
  ))::bigint;
$function$;

CREATE OR REPLACE FUNCTION private.rinnovo_proposta(p_instance_id bigint, p_overall smallint, p_eta smallint, p_ingaggio bigint, p_bandiera smallint, p_economia smallint)
 RETURNS TABLE(richiesta bigint, durata smallint)
 LANGUAGE sql
 STABLE PARALLEL SAFE
 SET search_path TO ''
AS $function$
  with seme as (
    select
      (abs(hashtext('ing:' || p_instance_id || ':' || p_overall || ':' || p_eta || ':' || p_ingaggio)) % 1000) / 1000.0 as r_ing
  ), centro as (
    select 1.06 + (p_economia - p_bandiera) / 500.0 as valore
  )
  select
    -- Massimale (9/11/2026): anche chi prende gia' di piu' al rinnovo scende al massimo.
    least(private.ingaggio_massimo(), greatest(
      500000::bigint,
      p_ingaggio,
      (round(
        private.ingaggio_teorico(p_overall, p_eta)
        * greatest(0.75, least(1.35, centro.valore + (seme.r_ing - 0.5) * 0.12))
        / 100000
      ) * 100000)::bigint
    )) as richiesta,
    1::smallint as durata
  from seme, centro;
$function$;

CREATE OR REPLACE FUNCTION private.richiesta_per_gradino(p_richiesta bigint, p_gradino text, p_richiesto text)
 RETURNS bigint
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
 SET search_path TO ''
AS $function$
  select least(private.ingaggio_massimo(), greatest(500000::bigint, (round(p_richiesta * case
    when private.livello_gradino(p_gradino) > private.livello_gradino(p_richiesto)
      then 1 - 0.08 * (private.livello_gradino(p_gradino) - private.livello_gradino(p_richiesto))
    when private.livello_gradino(p_gradino) < private.livello_gradino(p_richiesto) then 1.12
    else 1.00
  end / 100000) * 100000)::bigint));
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

  v_tolleranza := private.rinnovo_tolleranza(
    v_inst.morale, v_player.mentalita_bandiera, v_player.mentalita_economia,
    v_player.mentalita_vittorie, coalesce(v_posizione, 1::smallint),
    coalesce(private.squadre_nel_gruppo((select se.id from public.seasons se where se.league_id = v_inst.league_id and se.numero = v_league.stagione_corrente), v_inst.team_id), v_league.n_squadre)::smallint
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

  return jsonb_build_object(
    'player_instance_id', v_inst.id,
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

commit;
