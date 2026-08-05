-- Correzione di 20260805180000: `coalesce(v_posizione, 1)` produce un integer
-- (il letterale 1 non e' smallint), quindi la chiamata a rinnovo_tolleranza
-- non trovava la firma e offri_rinnovo falliva a ogni invocazione. Cast
-- esplicito su posizione e n_squadre. Nessun altro cambiamento.

CREATE OR REPLACE FUNCTION public.offri_rinnovo(p_instance_id bigint, p_ingaggio bigint, p_durata smallint)
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
  v_fattore_durata numeric;
  v_valore numeric;
  v_rapporto numeric;
  v_scadenza smallint;
  v_tentativi smallint;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'Devi accedere prima di trattare un rinnovo.';
  end if;
  if p_ingaggio < 500000 then
    raise exception using errcode = '22023', message = 'L''ingaggio minimo e'' 0,5 M€.';
  end if;
  if p_durata not between 1 and 4 then
    raise exception using errcode = '22023', message = 'La durata deve essere fra 1 e 4 stagioni.';
  end if;

  select * into v_inst from public.player_instances where id = p_instance_id for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Giocatore non trovato.';
  end if;

  select * into v_team from public.teams
  where id = v_inst.team_id and league_id = v_inst.league_id and user_id = v_user_id and attiva;
  if not found then
    raise exception using errcode = '42501', message = 'Questo giocatore non e'' nella tua rosa.';
  end if;

  select * into v_league from public.leagues where id = v_inst.league_id;
  if v_league.stato <> 'stagione' then
    raise exception using errcode = '55000', message = 'I rinnovi si trattano solo a stagione avviata.';
  end if;
  if v_inst.ritirato or v_inst.ritiro_annunciato then
    raise exception using errcode = '55000', message = 'Ha gia'' annunciato il ritiro: non rinnovera'' il contratto.';
  end if;
  if v_inst.rinnovo_tentativi >= 3 then
    raise exception using errcode = '55000',
      message = 'Ha chiuso la trattativa: andra'' a scadenza e lascera'' la squadra.';
  end if;

  select * into v_player from public.players where id = v_inst.player_id;
  select * into v_proposta
  from private.rinnovo_proposta(v_inst.id, v_inst.overall_corrente, v_inst.eta_corrente, v_inst.ingaggio);

  select coalesce(st.posizione, 1) into v_posizione
  from public.seasons se
  join public.standings st on st.season_id = se.id and st.team_id = v_inst.team_id
  where se.league_id = v_inst.league_id and se.numero = v_league.stagione_corrente;

  v_tolleranza := private.rinnovo_tolleranza(
    v_inst.morale, v_player.mentalita_bandiera, v_player.mentalita_economia,
    v_player.mentalita_vittorie, coalesce(v_posizione, 1::smallint), v_league.n_squadre::smallint
  );
  v_soglia := v_proposta.richiesta * (1 - v_tolleranza);

  -- I due assi si compensano: allontanarsi dalla durata voluta svaluta
  -- l'offerta del 7% per stagione di scarto, e va compensato con l'ingaggio.
  v_fattore_durata := 1 - abs(p_durata - v_proposta.durata) * 0.07;
  v_valore := p_ingaggio * v_fattore_durata;
  v_rapporto := v_valore / greatest(1, v_soglia);

  if v_rapporto >= 1 then
    v_scadenza := greatest(v_inst.contratto_scadenza, (v_league.stagione_corrente + p_durata)::smallint);
    update public.player_instances
    set ingaggio = p_ingaggio,
        contratto_scadenza = v_scadenza,
        rinnovo_tentativi = 0        -- firmato: la trattativa riparte pulita
    where id = v_inst.id;

    insert into public.transactions (league_id, team_id, tipo, importo, descrizione, saldo_dopo)
    values (
      v_inst.league_id, v_team.id, 'rinnovo_in_stagione',
      greatest(1, p_ingaggio - v_inst.ingaggio),
      'Rinnovo: ' || coalesce(v_player.nome, 'giocatore') || ' — '
        || round(p_ingaggio / 1000000.0, 1) || ' M€ fino alla stagione ' || v_scadenza,
      v_team.budget
    );

    return jsonb_build_object(
      'esito', 'accettato',
      'ingaggio', p_ingaggio,
      'durata', p_durata,
      'contratto_scadenza', v_scadenza,
      'tentativi_usati', 0,
      'messaggio', 'Ci sto, mister. Grazie della fiducia.'
    );
  end if;

  -- Rifiuto: consuma un tentativo e dice quanto si era lontani, mai la cifra.
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
