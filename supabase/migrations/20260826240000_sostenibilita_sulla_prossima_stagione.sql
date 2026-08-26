-- Il tetto di sostenibilita' introdotto stamattina bloccava rinnovi
-- perfettamente sostenibili. Segnalato dall'utente sulla lega di test
-- LegaBot: squadra Cocacolers, 27 giocatori di cui 26 in scadenza, bloccata
-- al secondo rinnovo con "monte ingaggi 65,9 M€ contro 46,1 M€ coperti".
--
-- Due errori, entrambi di doppio conteggio:
--
-- 1. private.monte_ingaggi_squadra sommava TUTTA la rosa attuale, compresi i
--    giocatori con il contratto in scadenza che a fine off-season se ne
--    vanno. Per Cocacolers il monte della prossima stagione e' 2,2 M€, non
--    65,6: il tetto contava 63 M€ di stipendi che non verranno mai pagati.
--    Un rinnovo, per giunta, SOSTITUISCE uno di quegli stipendi.
--
-- 2. In off-season sommava l'entrata minima garantita al budget, ma
--    prepara_offseason ha gia' accreditato sponsor, premi partita e premio di
--    partecipazione della stagione entrante: quei soldi sono gia' in cassa e
--    venivano contati due volte. E' lo stesso errore trovato nella proiezione
--    della pagina Finanza.
--
-- La formulazione corretta: un impegno e' sostenibile se la cassa
-- disponibile, piu' le entrate garantite NON ancora incassate, copre il monte
-- ingaggi della PROSSIMA stagione — cioe' solo i contratti che la coprono
-- davvero.

-- Il monte che conta e' quello della stagione entrante: i contratti in
-- scadenza non ne fanno parte.
create or replace function private.monte_ingaggi_prossima_stagione(p_team_id bigint)
returns bigint
language sql
stable
set search_path = ''
as $$
  select coalesce(sum(pi.ingaggio), 0)::bigint
  from public.player_instances pi
  join public.teams t on t.id = pi.team_id
  join public.leagues l on l.id = t.league_id
  where pi.team_id = p_team_id
    and not pi.ritirato
    and pi.contratto_scadenza > l.stagione_corrente
$$;

comment on function private.monte_ingaggi_prossima_stagione(bigint) is
  'Somma degli ingaggi dei soli contratti che coprono la stagione successiva. I giocatori in scadenza non contano: lasciano la squadra a fine off-season.';

create or replace function private.verifica_sostenibilita(
  p_team_id bigint,
  p_delta_ingaggio bigint,
  p_escludi_asta bigint default null
)
returns void
language plpgsql
stable
set search_path = ''
as $$
declare
  v_team public.teams;
  v_lega public.leagues;
  v_disponibile bigint;
  v_monte bigint;
  v_garantita bigint;
  v_copertura bigint;
begin
  -- Alleggerire un impegno e' sempre concesso, anche a chi e' gia' oltre il
  -- tetto: altrimenti una squadra in rosso resterebbe incastrata.
  if p_delta_ingaggio <= 0 then
    return;
  end if;

  select * into v_team from public.teams where id = p_team_id;
  select * into v_lega from public.leagues where id = v_team.league_id;

  v_disponibile := v_team.budget - v_team.budget_ingaggi_riservato
                   - private.budget_impegnato(p_team_id, p_escludi_asta);

  -- In off-season sponsor, premi e partecipazione della stagione entrante
  -- sono gia' stati accreditati da prepara_offseason: sono dentro
  -- v_disponibile, aggiungerli di nuovo sarebbe contarli due volte.
  v_garantita := case when v_lega.fase_carriera = 'offseason'
    then 0
    else private.entrata_minima_garantita(v_team.league_id)
  end;

  v_monte := private.monte_ingaggi_prossima_stagione(p_team_id) + p_delta_ingaggio;
  v_copertura := v_disponibile + v_garantita;

  if v_copertura < v_monte then
    raise exception using errcode = '22023', message =
      'Impegno non sostenibile: la prossima stagione la squadra avrebbe '
      || private.in_milioni(v_monte) || ' M€ di ingaggi, ma puo'' coprirne al massimo '
      || private.in_milioni(v_copertura) || ' M€ ('
      || private.in_milioni(v_disponibile) || ' M€ disponibili'
      || case when v_garantita > 0
           then ' piu'' ' || private.in_milioni(v_garantita) || ' M€ di entrate garantite'
           else '' end
      || ').';
  end if;
end;
$$;

revoke all on function private.monte_ingaggi_prossima_stagione(bigint) from public, anon, authenticated;
revoke all on function private.verifica_sostenibilita(bigint, bigint, bigint) from public, anon, authenticated;

-- private.monte_ingaggi_squadra non serve piu' a nessuno: era usata solo dal
-- vecchio tetto. La lascio in piedi (e' innocua e qualcuno potrebbe volerla
-- per una schermata) ma il commento dice a cosa NON serve.
comment on function private.monte_ingaggi_squadra(bigint) is
  'Monte ingaggi della rosa ATTUALE, contratti in scadenza inclusi. NON usarla per la sostenibilita'': per quella serve monte_ingaggi_prossima_stagione.';

-- ------------------------------------------------------------
--  I tre chiamanti passano ora il delta misurato sul monte della
--  prossima stagione, non sulla rosa attuale.
-- ------------------------------------------------------------

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
    raise exception using errcode = '22023', message = 'L''ingaggio minimo è 0,5 M€.';
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
    raise exception using errcode = '42501', message = 'Questo giocatore non è nella tua rosa.';
  end if;

  select * into v_league from public.leagues where id = v_inst.league_id;
  if v_league.stato <> 'stagione' then
    raise exception using errcode = '55000', message = 'I rinnovi si trattano solo a stagione avviata.';
  end if;
  if v_inst.ritirato or v_inst.ritiro_annunciato then
    raise exception using errcode = '55000', message = 'Ha già annunciato il ritiro: non rinnoverà il contratto.';
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

  select coalesce(st.posizione, 1) into v_posizione
  from public.seasons se
  join public.standings st on st.season_id = se.id and st.team_id = v_inst.team_id
  where se.league_id = v_inst.league_id and se.numero = v_league.stagione_corrente;

  v_tolleranza := private.rinnovo_tolleranza(
    v_inst.morale, v_player.mentalita_bandiera, v_player.mentalita_economia,
    v_player.mentalita_vittorie, coalesce(v_posizione, 1::smallint), v_league.n_squadre::smallint
  );
  v_soglia := v_proposta.richiesta * (1 - v_tolleranza);

  v_fattore_durata := 1 - abs(p_durata - v_proposta.durata) * 0.07;
  v_valore := p_ingaggio * v_fattore_durata;
  v_rapporto := v_valore / greatest(1, v_soglia);

  if v_rapporto >= 1 then
    -- Il delta va misurato sul monte della PROSSIMA stagione: se il contratto
    -- era in scadenza il vecchio ingaggio non ne fa parte, quindi il rinnovo
    -- aggiunge l'intero nuovo importo, non la differenza.
    perform private.verifica_sostenibilita(v_team.id, p_ingaggio - case
      when v_inst.contratto_scadenza > v_league.stagione_corrente then v_inst.ingaggio
      else 0 end);

    v_scadenza := greatest(v_inst.contratto_scadenza, (v_league.stagione_corrente + p_durata)::smallint);
    update public.player_instances
    set ingaggio = p_ingaggio,
        contratto_scadenza = v_scadenza,
        rinnovo_tentativi = 0,
        rinnovo_stagione = v_league.stagione_corrente
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

CREATE OR REPLACE FUNCTION public.offri_per_svincolato(p_auction_id bigint, p_ingaggio bigint)
 RETURNS free_agent_bids
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_utente     uuid := (select auth.uid());
  v_asta       public.free_agent_auctions;
  v_lega       public.leagues;
  v_squadra    public.teams;
  v_rosa       integer;
  v_prorata    bigint;
  v_impegnato  bigint;
  v_slot_altri integer;
  v_offerta    public.free_agent_bids;
begin
  if v_utente is null then
    raise exception using errcode = '42501', message = 'Devi accedere per usare il mercato.';
  end if;

  select * into v_asta from public.free_agent_auctions where id = p_auction_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Asta inesistente.';
  end if;
  if v_asta.stato <> 'aperta' then
    raise exception using errcode = '55000', message = 'Questa asta è già stata risolta.';
  end if;
  if not private.mercato_aperto_lega(v_asta.league_id) then
    raise exception using errcode = '55000',
      message = 'Il mercato è chiuso: si offre dalle 23:30 alle 21:00 o quando l''admin lo apre.';
  end if;

  select * into v_lega from public.leagues where id = v_asta.league_id;
  select * into v_squadra from public.teams
  where league_id = v_asta.league_id and user_id = v_utente;
  if not found then
    raise exception using errcode = '42501', message = 'Non partecipi a questa lega.';
  end if;
  if p_ingaggio < 500000 then
    raise exception using errcode = '22023', message = 'L''ingaggio minimo è 0,5 M€.';
  end if;

  select count(*) into v_rosa from public.player_instances where team_id = v_squadra.id;
  v_slot_altri := private.slot_impegnati(v_squadra.id, p_auction_id);
  if v_rosa + v_slot_altri + 1 > private.rosa_massima() then
    raise exception using errcode = '22023',
      message = 'Non hai più posti liberi: ' || v_rosa || ' giocatori in rosa e '
                || v_slot_altri || ' offerte già in gioco, su un massimo di ' || private.rosa_massima() || ' giocatori.';
  end if;

  v_prorata := round(p_ingaggio::numeric * private.giornate_rimanenti(v_lega.id)
                     / greatest(v_lega.giornate_totali, 1));
  v_impegnato := private.budget_impegnato(v_squadra.id, p_auction_id);
  if v_squadra.budget - v_impegnato < v_prorata then
    raise exception using errcode = '22023',
      message = 'Budget insufficiente: ' || private.in_milioni(v_impegnato)
                || ' M€ sono già impegnati in altre offerte, te ne restano '
                || private.in_milioni(v_squadra.budget - v_impegnato)
                || ' M€ e questa ne richiede ' || private.in_milioni(v_prorata) || ' M€.';
  end if;
  -- Un'asta vinta a stagione in corso da' un contratto che scade con la
  -- stagione stessa: non impegna nulla dell'anno prossimo, e la copertura di
  -- quest'anno e' gia' garantita dal controllo pro-rata qui sopra. In
  -- off-season invece il contratto copre la stagione entrante.
  perform private.verifica_sostenibilita(
    v_squadra.id,
    case when v_lega.fase_carriera = 'offseason' then p_ingaggio else 0 end,
    p_auction_id);

  insert into public.free_agent_bids (auction_id, league_id, team_id, ingaggio_offerto)
  values (p_auction_id, v_asta.league_id, v_squadra.id, p_ingaggio)
  on conflict (auction_id, team_id) do update
    set ingaggio_offerto = excluded.ingaggio_offerto, aggiornata_il = now()
  returning * into v_offerta;
  return v_offerta;
end;
$function$;

CREATE OR REPLACE FUNCTION public.rispondi_a_proposta(p_proposta_id bigint, p_accetta boolean)
 RETURNS trade_proposals
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_p public.trade_proposals; v_l public.leagues; v_da public.teams; v_a public.teams;
  v_g integer; v_off bigint; v_ric bigint; v_off_annuo bigint; v_ric_annuo bigint;
  v_esito public.trade_proposals; v_saldo bigint;
begin
  if not coalesce(p_accetta, false) then return public.rispondi_a_proposta_cassa_legacy(p_proposta_id, false); end if;
  select * into v_p from public.trade_proposals where id = p_proposta_id;
  select * into v_l from public.leagues where id = v_p.league_id;
  select * into v_da from public.teams where id = v_p.da_team_id;
  select * into v_a from public.teams where id = v_p.a_team_id;
  select count(distinct giornata)::integer into v_g from public.fixtures where league_id = v_l.id and stato = 'simulata';
  select coalesce(sum(private.ingaggio_residuo_stagione(ingaggio, v_g, v_l.giornate_totali)), 0) into v_off from public.player_instances where id = any(v_p.giocatori_offerti);
  select coalesce(sum(private.ingaggio_residuo_stagione(ingaggio, v_g, v_l.giornate_totali)), 0) into v_ric from public.player_instances where id = any(v_p.giocatori_richiesti);
  if v_da.budget - v_p.conguaglio - (v_da.budget_ingaggi_riservato - v_off + v_ric) < 0 or v_a.budget + v_p.conguaglio - (v_a.budget_ingaggi_riservato - v_ric + v_off) < 0 then
    raise exception using errcode = '22023', message = 'Budget disponibile insufficiente per coprire il trasferimento e gli ingaggi residui.';
  end if;

  select coalesce(sum(ingaggio), 0) into v_off_annuo from public.player_instances where id = any(v_p.giocatori_offerti);
  select coalesce(sum(ingaggio), 0) into v_ric_annuo from public.player_instances where id = any(v_p.giocatori_richiesti);
  -- Contano solo i giocatori il cui contratto copre la prossima stagione:
  -- scambiarsi contratti in scadenza non sposta nulla dell'anno prossimo.
  select coalesce(sum(pi.ingaggio),0) into v_off_annuo from public.player_instances pi
  where pi.id = any(v_p.giocatori_offerti) and pi.contratto_scadenza > v_l.stagione_corrente;
  select coalesce(sum(pi.ingaggio),0) into v_ric_annuo from public.player_instances pi
  where pi.id = any(v_p.giocatori_richiesti) and pi.contratto_scadenza > v_l.stagione_corrente;
  perform private.verifica_sostenibilita(v_da.id, v_ric_annuo - v_off_annuo);
  perform private.verifica_sostenibilita(v_a.id, v_off_annuo - v_ric_annuo);

  v_esito := public.rispondi_a_proposta_cassa_legacy(p_proposta_id, true);
  update public.teams set budget = budget - v_off + v_ric, budget_ingaggi_riservato = budget_ingaggi_riservato - v_off + v_ric where id = v_da.id returning budget into v_saldo;
  update public.teams set budget = budget - v_ric + v_off, budget_ingaggi_riservato = budget_ingaggi_riservato - v_ric + v_off where id = v_a.id;
  return v_esito;
end;
$function$;
