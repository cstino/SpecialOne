-- Barra dei rinnovi senza la zona di accettazione (decisione del committente, 9/11/2026): aiutava troppo e rendeva
-- inutili i tre tentativi. La proposta non manda piu' la zona: la soglia resta nascosta anche nei dati dell'app.
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
