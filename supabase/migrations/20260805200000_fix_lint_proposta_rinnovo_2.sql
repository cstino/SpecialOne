-- Pulizia di un warning introdotto da 20260805180000: proposta_rinnovo
-- calcolava v_posizione senza usarla (serve solo a offri_rinnovo, per la
-- tolleranza). La posizione in classifica NON va esposta qui: la tolleranza
-- resta nascosta, altrimenti si ricava la soglia esatta e la trattativa
-- diventa un calcolo invece che una scommessa.

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

  select * into v_player from public.players where id = v_inst.player_id;
  select * into v_proposta
  from private.rinnovo_proposta(v_inst.id, v_inst.overall_corrente, v_inst.eta_corrente, v_inst.ingaggio);

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
    'morale', v_inst.morale,
    'mentalita', jsonb_build_object(
      'bandiera', v_player.mentalita_bandiera,
      'economia', v_player.mentalita_economia,
      'vittorie', v_player.mentalita_vittorie
    )
  );
end;
$function$;
