-- Tetto di sostenibilita' sugli stipendi (richiesto dall'utente, 26 agosto
-- 2026, dopo l'incidente di svincolo su McDon's e il rosso di decine di
-- milioni emerso sulle squadre di Real Fampionato).
--
-- Finora l'unica difesa era REATTIVA: l'insolvenza a inizio stagione
-- (design.md §5.5) svincola forzatamente gli ingaggi piu' alti quando il
-- monte ingaggi non e' piu' copribile. Questa migrazione aggiunge una
-- difesa PREVENTIVA sui canali che hanno causato l'indebitamento
-- incontrollato: rinnovi contrattuali, aste sugli svincolati e scambi di
-- mercato. Il draft iniziale ha gia' un vincolo di solvibilita' separato
-- (design §4.4, tetto all'80% del budget) e non viene toccato qui: e' un
-- controllo diverso, testato, e la sua ragion d'essere e' evitare il
-- deadlock del draft (CLAUDE.md §7), non la sostenibilita' pluriennale.
--
-- L'idea: una squadra non puo' impegnarsi su un monte ingaggi che, nel
-- caso peggiore per lei (ultima in classifica, zero vittorie), non
-- riuscirebbe a coprire nemmeno sommando l'intera entrata garantita della
-- stagione. Le tre componenti dell'entrata minima ricalcano esattamente le
-- formule gia' in uso in prepara_offseason, nel caso limite:
--   - sponsor: fisso, 20% del budget_iniziale, non dipende dai risultati
--   - premio partita: tutte sconfitte, il coefficiente vale 0.135
--     (il numero di giornate si semplifica nella formula, quindi il
--     risultato NON dipende da partite_per_squadra: niente rischio di
--     leggere una colonna generata resa stale da un cambio di n_squadre
--     in off-season, lo stesso problema gia' corretto per lo svincolo)
--   - premio posizione: ultimo posto, il peso piu' basso della curva
--     esponenziale (posizione = n_squadre attive)

create or replace function private.entrata_minima_garantita(p_league_id bigint)
returns bigint
language sql
stable
set search_path = ''
as $$
  with att as (
    select count(*)::integer as n from public.teams where league_id = p_league_id and attiva
  ), pesi as (
    select coalesce(sum(power(i::numeric, 1.8)), 1) as tot
    from att, generate_series(1, greatest(att.n, 1)) i
  )
  select
    (round(l.budget_iniziale * 0.20 / 100000)::bigint * 100000)
    + (round(l.budget_iniziale * 0.135 / 100000)::bigint * 100000)
    + (round((0.12 * l.budget_iniziale * att.n) / greatest(pesi.tot, 1) / 100000)::bigint * 100000)
  from public.leagues l, att, pesi
  where l.id = p_league_id
$$;

comment on function private.entrata_minima_garantita(bigint) is
  'Entrata minima che una squadra incassa comunque in una stagione: sponsor + premio partita da ultima (tutte sconfitte) + premio posizione da ultima. Non dipende dal rendimento reale, solo dalle impostazioni della lega.';

create or replace function private.monte_ingaggi_squadra(p_team_id bigint)
returns bigint
language sql
stable
set search_path = ''
as $$
  select coalesce(sum(ingaggio), 0)::bigint
  from public.player_instances
  where team_id = p_team_id and not ritirato
$$;

-- p_escludi_asta: come private.budget_impegnato, serve a non contare due
-- volte la propria offerta gia' piazzata quando la si sta modificando.
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
  v_disponibile bigint;
  v_monte bigint;
  v_garantita bigint;
begin
  -- Una squadra gia' sotto il tetto (rose ereditate da prima di questo
  -- controllo, o insolvenza vera) deve poter sempre ALLEGGERIRE il proprio
  -- impegno: il tetto blocca solo chi lo sta per PEGGIORARE.
  if p_delta_ingaggio <= 0 then
    return;
  end if;
  select * into v_team from public.teams where id = p_team_id;
  v_disponibile := v_team.budget - v_team.budget_ingaggi_riservato - private.budget_impegnato(p_team_id, p_escludi_asta);
  v_garantita := private.entrata_minima_garantita(v_team.league_id);
  v_monte := private.monte_ingaggi_squadra(p_team_id) + p_delta_ingaggio;
  if v_disponibile + v_garantita < v_monte then
    raise exception using errcode = '22023', message =
      'Impegno non sostenibile: nel caso peggiore (ultima in classifica, zero vittorie) la squadra incasserebbe almeno '
      || private.in_milioni(v_garantita) || ' M€ a fine stagione. Con ' || private.in_milioni(v_disponibile)
      || ' M€ disponibili ora, il monte ingaggi coperto al massimo sarebbe '
      || private.in_milioni(v_disponibile + v_garantita) || ' M€, ma salirebbe a '
      || private.in_milioni(v_monte) || ' M€.';
  end if;
end;
$$;

revoke all on function private.entrata_minima_garantita(bigint) from public, anon, authenticated;
revoke all on function private.monte_ingaggi_squadra(bigint) from public, anon, authenticated;
revoke all on function private.verifica_sostenibilita(bigint, bigint, bigint) from public, anon, authenticated;

-- ------------------------------------------------------------
--  Rinnovi: controllo prima di accettare l'offerta del giocatore.
-- ------------------------------------------------------------
create or replace function public.offri_rinnovo(p_instance_id bigint, p_ingaggio bigint, p_durata smallint)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
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
    perform private.verifica_sostenibilita(v_team.id, p_ingaggio - v_inst.ingaggio);

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
$$;

-- CREATE OR REPLACE mantiene i grant gia' presenti sulla funzione: niente
-- revoke/grant qui, per non alterare permessi che non c'entrano con questa
-- modifica.

-- ------------------------------------------------------------
--  Aste sugli svincolati: controllo prima di registrare l'offerta.
-- ------------------------------------------------------------
create or replace function public.offri_per_svincolato(p_auction_id bigint, p_ingaggio bigint)
returns free_agent_bids
language plpgsql
security definer
set search_path = ''
as $$
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
  perform private.verifica_sostenibilita(v_squadra.id, p_ingaggio, p_auction_id);

  insert into public.free_agent_bids (auction_id, league_id, team_id, ingaggio_offerto)
  values (p_auction_id, v_asta.league_id, v_squadra.id, p_ingaggio)
  on conflict (auction_id, team_id) do update
    set ingaggio_offerto = excluded.ingaggio_offerto, aggiornata_il = now()
  returning * into v_offerta;
  return v_offerta;
end;
$$;

-- ------------------------------------------------------------
--  Scambi di mercato: controllo prima di accettare la proposta.
-- ------------------------------------------------------------
create or replace function public.rispondi_a_proposta(p_proposta_id bigint, p_accetta boolean)
returns trade_proposals
language plpgsql
security definer
set search_path = ''
as $$
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
  perform private.verifica_sostenibilita(v_da.id, v_ric_annuo - v_off_annuo);
  perform private.verifica_sostenibilita(v_a.id, v_off_annuo - v_ric_annuo);

  v_esito := public.rispondi_a_proposta_cassa_legacy(p_proposta_id, true);
  update public.teams set budget = budget - v_off + v_ric, budget_ingaggi_riservato = budget_ingaggi_riservato - v_off + v_ric where id = v_da.id returning budget into v_saldo;
  update public.teams set budget = budget - v_ric + v_off, budget_ingaggi_riservato = budget_ingaggi_riservato - v_ric + v_off where id = v_a.id;
  return v_esito;
end;
$$;
