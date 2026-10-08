-- Il rinnovo alza subito il morale (8 ottobre 2026, scelta del committente). Prima contava solo al ricalcolo
-- successivo (4 volte a stagione) come voce «economia», e un giocatore appena rinnovato restava in rotta con la squadra.
-- Spinta: +20 fissi, piu' fino a +15 se il nuovo ingaggio supera il suo valore (ingaggio_teorico), pesato da quanto
-- tiene ai soldi (mentalita_economia, 33 = peso normale). Vale per i rinnovi in stagione, in off-season e del PC.
create or replace function private.spinta_morale_rinnovo(p_instance_id bigint)
returns void
language sql
security definer
set search_path = ''
as $$
  update public.player_instances pi
  set morale = least(100, pi.morale + 20 + round(least(15, greatest(0,
        (pi.ingaggio::numeric / greatest(1, private.ingaggio_teorico(pi.overall_corrente, pi.eta_corrente)) - 1) * 40
      ) * (p.mentalita_economia / 33.0))))::smallint
  from public.players p
  where pi.id = p_instance_id and p.id = pi.player_id;
$$;
revoke all on function private.spinta_morale_rinnovo(bigint) from public;

create or replace function public.offri_rinnovo(p_instance_id bigint, p_ingaggio bigint, p_durata smallint, p_minutaggio text DEFAULT NULL::text)
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
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'Devi accedere prima di trattare un rinnovo.';
  end if;
  if p_ingaggio < 500000 then
    raise exception using errcode = '22023', message = 'L''ingaggio minimo è 0,5 M€.';
  end if;
  if p_durata <> 1 then
    raise exception using errcode = '22023',
      message = 'I contratti durano una stagione: il rinnovo estende di un anno.';
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

  select coalesce(st.posizione, 1) into v_posizione
  from public.seasons se
  join public.standings st on st.season_id = se.id and st.team_id = v_inst.team_id
  where se.league_id = v_inst.league_id and se.numero = v_league.stagione_corrente;

  v_tolleranza := private.rinnovo_tolleranza(
    v_inst.morale, v_player.mentalita_bandiera, v_player.mentalita_economia,
    v_player.mentalita_vittorie, coalesce(v_posizione, 1::smallint), v_league.n_squadre::smallint
  );
  v_soglia := v_richiesta * (1 - v_tolleranza);

  v_valore := p_ingaggio;
  v_rapporto := v_valore / greatest(1, v_soglia);

  if v_rapporto >= 1 then
    perform private.verifica_capienza(
      v_team.id,
      p_ingaggio - case
        when v_inst.contratto_scadenza > v_league.stagione_corrente then v_inst.ingaggio
        else 0 end,
      (v_league.stagione_corrente + 1)::smallint
    );

    v_scadenza := greatest(v_inst.contratto_scadenza, (v_league.stagione_corrente + 1)::smallint);
    update public.player_instances
    set ingaggio = p_ingaggio,
        contratto_scadenza = v_scadenza,
        rinnovo_tentativi = 0,
        rinnovo_stagione = v_league.stagione_corrente,
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
      greatest(1, p_ingaggio - v_inst.ingaggio),
      'Rinnovo: ' || coalesce(v_player.nome, 'giocatore') || ' — '
        || round(p_ingaggio / 1000000.0, 1) || ' M€ fino alla stagione ' || v_scadenza,
      0
    );

    return jsonb_build_object(
      'esito', 'accettato',
      'ingaggio', p_ingaggio,
      'durata', 1,
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
$function$

;

create or replace function public.rispondi_rinnovo(p_rinnovo_id bigint, p_offerta bigint, p_durata smallint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_user uuid := (select auth.uid());
  v_rinnovo public.contract_renewals;
  v_offseason public.offseasons;
  v_richiesta bigint;
  v_accetta boolean := false;
  v_controproposta boolean := false;
  v_ingaggio bigint;
  v_nome text;
begin
  if v_user is null then
    raise exception using errcode = '42501', message = 'Devi accedere per rispondere al rinnovo.';
  end if;
  if p_offerta < 500000 or p_offerta % 100000 <> 0 then
    raise exception using errcode = '22023', message = 'L''offerta deve essere almeno 0,5 M€ e a scatti di 0,1 M€.';
  end if;
  if p_durata not between 1 and 4 then
    raise exception using errcode = '22023', message = 'La durata deve essere fra 1 e 4 stagioni.';
  end if;

  select * into v_rinnovo from public.contract_renewals where id = p_rinnovo_id for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Rinnovo non trovato.';
  end if;
  if not (select private.e_mia_squadra(v_rinnovo.team_id)) then
    raise exception using errcode = '42501', message = 'Questo rinnovo non appartiene alla tua squadra.';
  end if;
  if v_rinnovo.stato not in ('in_attesa', 'controproposta') then
    raise exception using errcode = '55000', message = 'Questo rinnovo è già stato risolto.';
  end if;

  select * into v_offseason from public.offseasons where id = v_rinnovo.offseason_id;
  if v_offseason.stato <> 'aperta' or now() >= v_offseason.scade_il then
    raise exception using errcode = '55000', message = 'La finestra dei rinnovi è terminata.';
  end if;

  select richiesta_esatta into v_richiesta
  from private.contract_renewal_terms
  where renewal_id = v_rinnovo.id;

  select p.nome into v_nome
  from public.player_instances pi
  join public.players p on p.id = pi.player_id
  where pi.id = v_rinnovo.player_instance_id;

  if p_offerta >= v_richiesta then
    v_accetta := true;
  elsif v_rinnovo.stato = 'in_attesa' then
    v_controproposta := true;
  end if;

  if v_accetta then
    v_ingaggio := p_offerta;
    update public.player_instances
    set ingaggio = v_ingaggio,
        contratto_scadenza = v_offseason.stagione_a + p_durata - 1
    where id = v_rinnovo.player_instance_id and team_id = v_rinnovo.team_id;
    perform private.spinta_morale_rinnovo(v_rinnovo.player_instance_id);

    update public.contract_renewals
    set offerta = p_offerta,
        durata = p_durata,
        stato = 'accettato',
        risolta_il = now()
    where id = v_rinnovo.id;

    perform private.notifica(v_user, v_rinnovo.league_id, 'sistema',
      'Rinnovo accettato',
      v_nome || ' ha firmato per ' || p_durata || case when p_durata = 1 then ' stagione.' else ' stagioni.' end,
      jsonb_build_object('player_instance_id', v_rinnovo.player_instance_id, 'rinnovo_id', v_rinnovo.id));

  elsif v_controproposta then
    update public.contract_renewals
    set offerta = p_offerta,
        durata = p_durata,
        richiesta_min = v_richiesta,
        richiesta_max = v_richiesta,
        stato = 'controproposta',
        risolta_il = null
    where id = v_rinnovo.id;

    perform private.notifica(v_user, v_rinnovo.league_id, 'sistema',
      'Controproposta rinnovo',
      v_nome || ' chiede l''ultima offerta prima di liberarsi.',
      jsonb_build_object('player_instance_id', v_rinnovo.player_instance_id, 'rinnovo_id', v_rinnovo.id, 'richiesta', v_richiesta));

  else
    update public.player_instances
    set team_id = null
    where id = v_rinnovo.player_instance_id and team_id = v_rinnovo.team_id;

    update public.contract_renewals
    set offerta = p_offerta,
        durata = p_durata,
        stato = 'rifiutato',
        risolta_il = now()
    where id = v_rinnovo.id;

    perform private.notifica(v_user, v_rinnovo.league_id, 'sistema',
      'Rinnovo rifiutato',
      v_nome || ' non ha accettato l''ultima offerta ed è ora svincolato.',
      jsonb_build_object('player_instance_id', v_rinnovo.player_instance_id, 'rinnovo_id', v_rinnovo.id));
  end if;

  return jsonb_build_object(
    'id', v_rinnovo.id,
    'accettato', v_accetta,
    'controproposta', v_controproposta,
    'ingaggio', case when v_accetta then v_ingaggio else null end,
    'richiesta', case when v_controproposta then v_richiesta else null end
  );
end;
$function$

;

create or replace function public.gestisci_rinnovi_squadre_pc(p_league_id bigint)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_lega public.leagues;
  v_riga record;
  v_proposta record;
  v_ingaggio bigint;
  v_scadenza smallint;
  v_rinnovati integer := 0;
begin
  select * into v_lega from public.leagues where id = p_league_id;
  if not found or v_lega.stato <> 'stagione' then return 0; end if;

  for v_riga in
    select pi.*, p.nome, p.mentalita_bandiera, p.mentalita_economia
    from public.player_instances pi
    join public.teams t on t.id = pi.team_id
    join public.players p on p.id = pi.player_id
    where pi.league_id = p_league_id and t.controllata_da_pc and t.attiva
      and pi.contratto_scadenza = v_lega.stagione_corrente
      and not pi.ritirato and not pi.ritiro_annunciato
      and (pi.rinnovo_stagione is null or pi.rinnovo_stagione <> v_lega.stagione_corrente)
  loop
    if v_riga.eta_corrente >= 34 and v_riga.ingaggio > 5000000 and random() < 0.18 then continue; end if;
    select * into v_proposta from private.rinnovo_proposta(
      v_riga.id, v_riga.overall_corrente, v_riga.eta_corrente, v_riga.ingaggio,
      v_riga.mentalita_bandiera, v_riga.mentalita_economia
    );
    v_ingaggio := greatest(v_riga.ingaggio, round(v_proposta.richiesta * (1.01 + random() * 0.08))::bigint);
    if private.capienza_residua(v_riga.team_id, (v_lega.stagione_corrente + 1)::smallint) < v_ingaggio then
      continue;
    end if;
    v_scadenza := greatest(v_riga.contratto_scadenza, (v_lega.stagione_corrente + v_proposta.durata)::smallint);
    update public.player_instances
    set ingaggio = v_ingaggio, contratto_scadenza = v_scadenza,
        rinnovo_tentativi = 0, rinnovo_stagione = v_lega.stagione_corrente
    where id = v_riga.id;
    perform private.spinta_morale_rinnovo(v_riga.id);
    insert into public.transactions(league_id, team_id, tipo, importo, descrizione, saldo_dopo)
    values (p_league_id, v_riga.team_id, 'rinnovo_in_stagione', greatest(1, v_ingaggio - v_riga.ingaggio),
            'Rinnovo PC: ' || v_riga.nome || ' fino alla stagione ' || v_scadenza,
            (select budget from public.teams where id = v_riga.team_id));
    v_rinnovati := v_rinnovati + 1;
  end loop;
  return v_rinnovati;
end;
$function$

;
