-- Mercato chiuso dall'inizio dei playoff fino alla nuova stagione (27/10/2026, committente): scambi, svincolati e under.
-- Il mercato SCAMBI riapre all'apertura dell'off-season; svincolati e under solo con la nuova stagione.
-- Fasi (private.fase_mercato): 'stagione' (stagione regolare) · 'playoff' (tabelloni creati per la stagione in corso) ·
-- 'fine_stagione' (lega conclusa, off-season non ancora aperta) · 'offseason'.
-- Le RPC di offerta e di scambio passano da due controlli nuovi che, a fase chiusa, rifiutano con un messaggio chiaro e
-- altrimenti applicano la regola di sempre (private.mercato_aperto_lega). Le estrazioni giornaliere di svincolati e under
-- (e con loro le mosse di mercato delle squadre del computer) girano solo in 'stagione'. Funzioni riscritte dalla
-- definizione viva.

create or replace function private.fase_mercato(p_league_id bigint)
 returns text language sql stable security definer set search_path to ''
as $function$
  select case
    when l.fase_carriera = 'offseason' or exists (select 1 from public.offseasons o where o.league_id = l.id and o.stato = 'aperta') then 'offseason'
    when l.stato = 'conclusa' then 'fine_stagione'
    when exists (select 1 from public.brackets b join public.seasons s on s.id = b.season_id
                  where s.league_id = l.id and s.numero = l.stagione_corrente and s.stato = 'in_corso') then 'playoff'
    else 'stagione' end
  from public.leagues l where l.id = p_league_id
$function$;

-- Svincolati e under: solo in stagione regolare.
create or replace function private.mercato_giocatori_aperto(p_league_id bigint)
 returns boolean language plpgsql stable security definer set search_path to ''
as $function$
begin
  if private.fase_mercato(p_league_id) <> 'stagione' then
    raise exception using errcode = '55000',
      message = 'Il mercato di svincolati e under è chiuso dall''inizio dei playoff fino all''inizio della nuova stagione.';
  end if;
  return private.mercato_aperto_lega(p_league_id);
end $function$;

-- Scambi: chiusi durante i playoff e a stagione finita, riaprono con l'off-season.
create or replace function private.mercato_scambi_aperto(p_league_id bigint)
 returns boolean language plpgsql stable security definer set search_path to ''
as $function$
begin
  if private.fase_mercato(p_league_id) in ('playoff', 'fine_stagione') then
    raise exception using errcode = '55000',
      message = 'Il mercato degli scambi è chiuso durante i playoff: riapre con l''apertura dell''off-season.';
  end if;
  return private.mercato_aperto_lega(p_league_id);
end $function$;

-- Per l'app: in che fase e' il mercato.
create or replace function public.stato_mercato(p_league_id bigint)
 returns jsonb language sql stable security definer set search_path to ''
as $function$
  select jsonb_build_object('fase', f.fase,
    'giocatori_chiuso_per_fase', f.fase <> 'stagione',
    'scambi_chiuso_per_fase', f.fase in ('playoff', 'fine_stagione'))
  from (select private.fase_mercato(p_league_id) as fase) f
  where (select private.e_membro(p_league_id))
$function$;
revoke all on function public.stato_mercato(bigint) from public, anon;
grant execute on function public.stato_mercato(bigint) to authenticated;

-- public.offri_per_svincolato(bigint,bigint): controllo del mercato per fase (giocatori), 1 punto/i
CREATE OR REPLACE FUNCTION public.offri_per_svincolato(p_auction_id bigint, p_ingaggio bigint)
 RETURNS free_agent_bids
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_utente     uuid := (select auth.uid());
  v_asta       public.free_agent_auctions;
  v_squadra    public.teams;
  v_rosa       integer;
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
  -- In off-season gli svincolati non si trattano: si muovono solo scambi e
  -- rinnovi. Il mercato degli svincolati riapre con la nuova stagione.
  if exists (select 1 from public.leagues l where l.id = v_asta.league_id and l.fase_carriera = 'offseason') then
    raise exception using errcode = '55000',
      message = 'In off-season il mercato degli svincolati è chiuso: riapre con la nuova stagione.';
  end if;
  if not private.mercato_giocatori_aperto(v_asta.league_id) then
    raise exception using errcode = '55000',
      message = 'Il mercato è chiuso: si offre dalle 23:30 alle 21:00 o quando l''admin lo apre.';
  end if;

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

  perform private.verifica_capienza(
    v_squadra.id,
    p_ingaggio,
    private.stagione_contratto(v_asta.league_id),
    p_auction_id);

  insert into public.free_agent_bids (auction_id, league_id, team_id, ingaggio_offerto)
  values (p_auction_id, v_asta.league_id, v_squadra.id, p_ingaggio)
  on conflict (auction_id, team_id) do update
    set ingaggio_offerto = excluded.ingaggio_offerto, aggiornata_il = now()
  returning * into v_offerta;
  return v_offerta;
end;
$function$;

-- public.offri_per_under(bigint,bigint): controllo del mercato per fase (giocatori), 1 punto/i
CREATE OR REPLACE FUNCTION public.offri_per_under(p_auction_id bigint, p_ingaggio bigint)
 RETURNS under_bids
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_utente uuid := (select auth.uid());
  v_asta public.under_auctions;
  v_squadra public.teams;
  v_slot_max integer;
  v_slot_impegnati integer;
  v_offerta public.under_bids;
begin
  if v_utente is null then
    raise exception using errcode = '42501', message = 'Devi accedere per usare il mercato.';
  end if;

  select * into v_asta from public.under_auctions where id = p_auction_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Asta inesistente.';
  end if;
  if v_asta.stato <> 'aperta' then
    raise exception using errcode = '55000', message = 'Questa asta è già stata risolta.';
  end if;
  if not private.mercato_giocatori_aperto(v_asta.league_id) then
    raise exception using errcode = '55000',
      message = 'Il mercato è chiuso: si offre dalle 23:30 alle 21:00 o quando l''admin lo apre.';
  end if;

  select * into v_squadra from public.teams
  where league_id = v_asta.league_id and user_id = v_utente;
  if not found then
    raise exception using errcode = '42501', message = 'Non partecipi a questa lega.';
  end if;
  if p_ingaggio < 100000 then
    raise exception using errcode = '22023', message = 'L''ingaggio minimo per un prospetto UNDER è 0,1 M€.';
  end if;

  v_slot_max := private.vivaio_slot_massimi(v_squadra.id);
  v_slot_impegnati := private.vivaio_slot_impegnati(v_squadra.id, p_auction_id);
  if v_slot_impegnati + 1 > v_slot_max then
    raise exception using errcode = '22023',
      message = 'Non hai più slot vivaio liberi: ' || v_slot_impegnati || ' su ' || v_slot_max
                || '. Promuovi o libera un prospetto prima di offrire per un altro.';
  end if;

  perform private.verifica_capienza(
    v_squadra.id, p_ingaggio, private.stagione_contratto(v_asta.league_id),
    null, p_auction_id);

  insert into public.under_bids (auction_id, league_id, team_id, ingaggio_offerto)
  values (p_auction_id, v_asta.league_id, v_squadra.id, p_ingaggio)
  on conflict (auction_id, team_id) do update
    set ingaggio_offerto = excluded.ingaggio_offerto, aggiornata_il = now()
  returning * into v_offerta;
  return v_offerta;
end;
$function$;

-- public.richiama_svincolato(bigint): controllo del mercato per fase (giocatori), 1 punto/i
CREATE OR REPLACE FUNCTION public.richiama_svincolato(p_instance_id bigint)
 RETURNS player_instances
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_utente uuid := (select auth.uid());
  v_istanza public.player_instances;
  v_squadra public.teams;
  v_lega public.leagues;
  v_nome text;
  v_rosa integer;
  v_asta record;
begin
  if v_utente is null then
    raise exception using errcode = '42501', message = 'Devi accedere per richiamare un giocatore.';
  end if;

  select * into v_istanza from public.player_instances where id = p_instance_id for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Giocatore inesistente.';
  end if;
  select * into v_squadra from public.teams where id = v_istanza.peso_team_id and user_id = v_utente for update;
  if not found or v_istanza.team_id is not null then
    raise exception using errcode = '42501', message = 'Puoi richiamare solo un giocatore che hai svincolato e che nessuno ha ancora preso.';
  end if;

  select * into v_lega from public.leagues where id = v_istanza.league_id;
  select nome into v_nome from public.players where id = v_istanza.player_id;
  if v_lega.stato <> 'stagione' or v_lega.fase_carriera = 'offseason' then
    raise exception using errcode = '55000', message = 'Puoi richiamare un giocatore solo durante la stagione.';
  end if;
  if not private.mercato_giocatori_aperto(v_lega.id) then
    raise exception using errcode = '55000', message = 'Il mercato e'' chiuso: puoi richiamare dalle 23:30 alle 21:00, o quando l''admin lo apre.';
  end if;
  if v_istanza.ritirato or v_istanza.contratto_scadenza < private.stagione_contratto(v_lega.id) then
    raise exception using errcode = '22023', message = v_nome || ' non e'' piu'' sotto contratto con te: non puoi richiamarlo.';
  end if;
  if v_istanza.richiamato_stagione = v_lega.stagione_corrente then
    raise exception using errcode = '22023', message = v_nome || ' e'' gia'' stato richiamato una volta in questa stagione: non si puo'' richiamare di nuovo.';
  end if;
  select count(*) into v_rosa from public.player_instances where team_id = v_squadra.id;
  if v_rosa >= private.rosa_massima() then
    raise exception using errcode = '22023', message = 'La rosa e'' piena (' || private.rosa_massima() || ' giocatori): libera un posto per richiamare ' || v_nome || '.';
  end if;

  -- Le aste aperte su di lui decadono: chi aveva offerto lo viene a sapere.
  for v_asta in
    select a.id from public.free_agent_auctions a
    where a.league_id = v_lega.id and a.player_id = v_istanza.player_id and a.stato = 'aperta'
    for update
  loop
    perform private.notifica(t.user_id, v_lega.id, 'mercato_esito', 'Asta annullata',
      v_nome || ' e'' stato richiamato dalla sua squadra: l''asta e'' annullata e la tua offerta non vale piu''.',
      jsonb_build_object('player_id', v_istanza.player_id))
    from public.free_agent_bids b join public.teams t on t.id = b.team_id
    where b.auction_id = v_asta.id and t.user_id is not null and t.id <> v_squadra.id;
    delete from public.free_agent_bids where auction_id = v_asta.id;
    update public.free_agent_auctions set stato = 'deserta', risolta_il = now() where id = v_asta.id;
  end loop;
  delete from private.rilasci_in_coda where league_id = v_lega.id and player_id = v_istanza.player_id;

  -- Torna in rosa con il suo contratto (il trigger azzera peso_team_id: l'ingaggio torna a pesare come titolare in rosa).
  update public.player_instances
  set team_id = v_squadra.id, richiamato_stagione = v_lega.stagione_corrente, sul_mercato = false
  where id = v_istanza.id returning * into v_istanza;

  perform private.notifica(v_utente, v_lega.id, 'mercato_esito', 'Giocatore richiamato',
    v_nome || ' torna nella tua rosa con il suo contratto. Non potrai richiamarlo di nuovo in questa stagione.',
    jsonb_build_object('player_instance_id', v_istanza.id, 'player_id', v_istanza.player_id));
  return v_istanza;
end;
$function$;

-- public.proponi_scambio(bigint,bigint[],bigint[],bigint[],bigint[],text,bigint[],bigint[]): controllo del mercato per fase (scambi), 1 punto/i
CREATE OR REPLACE FUNCTION public.proponi_scambio(p_a_team_id bigint, p_giocatori_offerti bigint[] DEFAULT '{}'::bigint[], p_giocatori_richiesti bigint[] DEFAULT '{}'::bigint[], p_scelte_offerte bigint[] DEFAULT '{}'::bigint[], p_scelte_richieste bigint[] DEFAULT '{}'::bigint[], p_messaggio text DEFAULT NULL::text, p_vivaio_offerti bigint[] DEFAULT '{}'::bigint[], p_vivaio_richiesti bigint[] DEFAULT '{}'::bigint[])
 RETURNS trade_proposals
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_utente uuid := (select auth.uid());
  v_dest public.teams;
  v_mia public.teams;
  v_lega public.leagues;
  v_g_off bigint[] := coalesce(p_giocatori_offerti, '{}');
  v_g_ric bigint[] := coalesce(p_giocatori_richiesti, '{}');
  v_s_off bigint[] := coalesce(p_scelte_offerte, '{}');
  v_s_ric bigint[] := coalesce(p_scelte_richieste, '{}');
  v_v_off bigint[] := coalesce(p_vivaio_offerti, '{}');
  v_v_ric bigint[] := coalesce(p_vivaio_richiesti, '{}');
  v_n integer;
  v_scadenza timestamptz;
  v_proposta public.trade_proposals;
  v_utente_dest uuid;
begin
  if v_utente is null then
    raise exception using errcode = '42501', message = 'Devi accedere per usare il mercato.';
  end if;
  select * into v_dest from public.teams where id = p_a_team_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Squadra destinataria inesistente.';
  end if;
  select * into v_mia from public.teams where league_id = v_dest.league_id and user_id = v_utente;
  if not found then
    raise exception using errcode = '42501', message = 'Non partecipi a questa lega.';
  end if;
  if v_mia.id = v_dest.id then
    raise exception using errcode = '22023', message = 'Non puoi proporre uno scambio a te stesso.';
  end if;
  select * into v_lega from public.leagues where id = v_dest.league_id;
  if v_lega.stato <> 'stagione' or not private.mercato_scambi_aperto(v_lega.id) then
    raise exception using errcode = '55000', message = 'Il mercato e'' chiuso.';
  end if;

  -- Niente regali (19/10/2026): entrambe le squadre devono cedere almeno qualcosa (giocatore, prospetto o scelta).
  if cardinality(v_g_off) + cardinality(v_s_off) + cardinality(v_v_off) = 0 then
    raise exception using errcode = '22023', message = 'Devi offrire almeno un giocatore, un prospetto o una scelta: non si cedono asset senza niente in cambio.';
  end if;
  if cardinality(v_g_ric) + cardinality(v_s_ric) + cardinality(v_v_ric) = 0 then
    raise exception using errcode = '22023', message = 'Devi chiedere almeno un giocatore, un prospetto o una scelta: non si regalano asset.';
  end if;
  if cardinality(v_g_off) + cardinality(v_g_ric) + cardinality(v_s_off) + cardinality(v_s_ric) + cardinality(v_v_off) + cardinality(v_v_ric) = 0 then
    raise exception using errcode = '22023', message = 'Una proposta deve contenere almeno un giocatore o una scelta.';
  end if;

  if cardinality(array(select distinct unnest(v_g_off))) <> cardinality(v_g_off)
     or cardinality(array(select distinct unnest(v_g_ric))) <> cardinality(v_g_ric)
     or v_g_off && v_g_ric then
    raise exception using errcode = '22023', message = 'Un giocatore compare due volte nella proposta.';
  end if;
  if cardinality(array(select distinct unnest(v_s_off))) <> cardinality(v_s_off)
     or cardinality(array(select distinct unnest(v_s_ric))) <> cardinality(v_s_ric)
     or v_s_off && v_s_ric then
    raise exception using errcode = '22023', message = 'Una scelta compare due volte nella proposta.';
  end if;

  select count(*) into v_n from public.player_instances
  where id = any(v_g_off) and team_id = v_mia.id and league_id = v_lega.id;
  if v_n <> cardinality(v_g_off) then
    raise exception using errcode = '22023', message = 'Stai offrendo un giocatore che non e'' tuo.';
  end if;
  select count(*) into v_n from public.player_instances
  where id = any(v_g_ric) and team_id = v_dest.id and league_id = v_lega.id;
  if v_n <> cardinality(v_g_ric) then
    raise exception using errcode = '22023', message = 'Stai chiedendo un giocatore che non e'' di quella squadra.';
  end if;
  if exists (select 1 from public.player_instances where id = any(v_g_off || v_g_ric) and ritiro_annunciato) then
    raise exception using errcode = '55000', message = 'Uno dei giocatori coinvolti ha annunciato il ritiro.';
  end if;

  -- Prospetti del vivaio (19/10/2026): passano nel VIVAIO di chi li riceve, che deve avere slot liberi. Le squadre del
  -- PC non li trattano. Mantengono le giornate rimaste per la promozione e l'ingaggio (che pesa sul tetto).
  if cardinality(v_v_off) + cardinality(v_v_ric) > 0 then
    if v_dest.controllata_da_pc then
      raise exception using errcode = '22023', message = v_dest.nome || ' non tratta i giocatori del vivaio.';
    end if;
    if cardinality(array(select distinct unnest(v_v_off))) <> cardinality(v_v_off)
       or cardinality(array(select distinct unnest(v_v_ric))) <> cardinality(v_v_ric) or v_v_off && v_v_ric then
      raise exception using errcode = '22023', message = 'Un giocatore del vivaio compare due volte nella proposta.';
    end if;
    select count(*) into v_n from public.vivaio_prospetti where id = any(v_v_off) and team_id = v_mia.id and league_id = v_lega.id;
    if v_n <> cardinality(v_v_off) then
      raise exception using errcode = '22023', message = 'Stai offrendo un giocatore del vivaio che non e'' tuo.';
    end if;
    select count(*) into v_n from public.vivaio_prospetti where id = any(v_v_ric) and team_id = v_dest.id and league_id = v_lega.id;
    if v_n <> cardinality(v_v_ric) then
      raise exception using errcode = '22023', message = 'Stai chiedendo un giocatore del vivaio che non e'' di quella squadra.';
    end if;
    if (select count(*) from public.vivaio_prospetti where team_id = v_dest.id) - cardinality(v_v_ric) + cardinality(v_v_off) > private.vivaio_slot_massimi(v_dest.id) then
      raise exception using errcode = '22023', message = v_dest.nome || ' non ha slot liberi nel vivaio per ricevere questo giocatore.';
    end if;
    if (select count(*) from public.vivaio_prospetti where team_id = v_mia.id) - cardinality(v_v_off) + cardinality(v_v_ric) > private.vivaio_slot_massimi(v_mia.id) then
      raise exception using errcode = '22023', message = 'Non hai slot liberi nel vivaio per ricevere questo giocatore.';
    end if;
  end if;

  -- Una scelta si offre solo finche' non e' stata esercitata: 'usata' e
  -- 'vuota' sono gia' storia, non piu' un asset.
  select count(*) into v_n from public.scelte_draft
  where id = any(v_s_off) and team_proprietario_id = v_mia.id and league_id = v_lega.id
    and stato in ('futura', 'determinata');
  if v_n <> cardinality(v_s_off) then
    raise exception using errcode = '22023', message = 'Stai offrendo una scelta che non possiedi o gia'' esercitata.';
  end if;
  select count(*) into v_n from public.scelte_draft
  where id = any(v_s_ric) and team_proprietario_id = v_dest.id and league_id = v_lega.id
    and stato in ('futura', 'determinata');
  if v_n <> cardinality(v_s_ric) then
    raise exception using errcode = '22023', message = 'Stai chiedendo una scelta che quella squadra non possiede o gia'' esercitata.';
  end if;

  -- Regola Stepien: nessuna delle due squadre puo' restare senza la
  -- propria scelta d'origine in due stagioni consecutive della stessa
  -- finestra (docs/decisioni-draft-picks.md §7).
  if cardinality(v_s_off) > 0 and private.viola_regola_stepien(v_mia.id, v_s_off) then
    raise exception using errcode = '22023',
      message = 'Regola Stepien: non puoi cedere due tue scelte consecutive (la ON e la OFF della stessa stagione, oppure la OFF di una stagione e la ON della successiva).';
  end if;
  if cardinality(v_s_ric) > 0 and private.viola_regola_stepien(v_dest.id, v_s_ric) then
    raise exception using errcode = '22023',
      message = 'Regola Stepien: ' || v_dest.nome || ' non puo'' cedere due proprie scelte consecutive (la ON e la OFF della stessa stagione, oppure la OFF di una stagione e la ON della successiva).';
  end if;

  v_scadenza := (date_trunc('day', now() at time zone 'Europe/Rome') + interval '21 hours') at time zone 'Europe/Rome';
  if v_scadenza <= now() then v_scadenza := v_scadenza + interval '1 day'; end if;

  insert into public.trade_proposals(
    league_id, da_team_id, a_team_id,
    giocatori_offerti, giocatori_richiesti, scelte_offerte, scelte_richieste, vivaio_offerti, vivaio_richiesti,
    messaggio, scade_il
  ) values (
    v_lega.id, v_mia.id, v_dest.id,
    v_g_off, v_g_ric, v_s_off, v_s_ric, v_v_off, v_v_ric,
    nullif(btrim(coalesce(p_messaggio, '')), ''), v_scadenza
  ) returning * into v_proposta;

  select user_id into v_utente_dest from public.teams where id = v_dest.id;
  if v_utente_dest is not null then
    perform private.notifica(v_utente_dest, v_lega.id, 'mercato_proposta', 'Proposta di mercato da ' || v_mia.nome,
      'Proposta di mercato: scade alle 21:00.', jsonb_build_object('proposta_id', v_proposta.id));
  end if;
  return v_proposta;
end;
$function$;

-- public.rispondi_a_proposta(bigint,boolean): controllo del mercato per fase (scambi), 1 punto/i
CREATE OR REPLACE FUNCTION public.rispondi_a_proposta(p_proposta_id bigint, p_accetta boolean)
 RETURNS trade_proposals
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_utente     uuid := (select auth.uid());
  v_p          public.trade_proposals;
  v_lega       public.leagues;
  v_da         public.teams;
  v_a          public.teams;
  v_stagione   smallint;
  v_n          integer;
  v_rosa_da    integer;
  v_rosa_a     integer;
  v_prossima   integer;
  v_tutti      bigint[];
  v_form_tolte integer := 0;
  v_nota       text := '';
  v_delta_da   bigint;
  v_delta_a    bigint;
begin
  if v_utente is null then
    raise exception using errcode = '42501', message = 'Devi accedere per usare il mercato.';
  end if;

  select * into v_p from public.trade_proposals where id = p_proposta_id for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Proposta inesistente.';
  end if;
  if not (select private.e_mia_squadra(v_p.a_team_id)) then
    raise exception using errcode = '42501', message = 'Questa proposta non e'' indirizzata a te.';
  end if;
  if v_p.stato <> 'in_attesa' then
    raise exception using errcode = '55000', message = 'Questa proposta e'' gia'' stata risolta.';
  end if;
  if now() >= v_p.scade_il then
    raise exception using errcode = '55000', message = 'Questa proposta e'' scaduta.';
  end if;

  if not coalesce(p_accetta, false) then
    update public.trade_proposals set stato = 'rifiutata', risolta_il = now()
    where id = v_p.id
    returning * into v_p;

    perform private.notifica(
      (select user_id from public.teams where id = v_p.da_team_id),
      v_p.league_id, 'mercato_esito', 'Proposta rifiutata',
      (select nome from public.teams where id = v_p.a_team_id) || ' ha rifiutato la tua proposta.',
      jsonb_build_object('proposta_id', v_p.id)
    );
    return v_p;
  end if;

  if cardinality(v_p.giocatori_offerti) + cardinality(v_p.scelte_offerte) + cardinality(v_p.vivaio_offerti) = 0
     or cardinality(v_p.giocatori_richiesti) + cardinality(v_p.scelte_richieste) + cardinality(v_p.vivaio_richiesti) = 0 then
    raise exception using errcode = '22023', message = 'Uno scambio deve avere qualcosa da entrambe le parti: questa proposta non e'' piu'' valida.';
  end if;

  if not private.mercato_scambi_aperto(v_p.league_id) then
    raise exception using errcode = '55000',
      message = 'Il mercato e'' chiuso: si conclude dalle 23:30 alle 21:00, o quando l''admin lo apre.';
  end if;

  select * into v_lega from public.leagues where id = v_p.league_id;

  perform 1 from public.teams where id in (v_p.da_team_id, v_p.a_team_id) order by id for update;
  select * into v_da from public.teams where id = v_p.da_team_id;
  select * into v_a  from public.teams where id = v_p.a_team_id;

  select count(*) into v_n from public.player_instances
  where id = any(v_p.giocatori_offerti) and team_id = v_da.id;
  if v_n <> cardinality(v_p.giocatori_offerti) then
    raise exception using errcode = '55000',
      message = 'Un giocatore offerto non e'' piu'' in quella rosa: la proposta non e'' piu'' valida.';
  end if;
  select count(*) into v_n from public.player_instances
  where id = any(v_p.giocatori_richiesti) and team_id = v_a.id;
  if v_n <> cardinality(v_p.giocatori_richiesti) then
    raise exception using errcode = '55000',
      message = 'Un giocatore richiesto non e'' piu'' nella tua rosa: la proposta non e'' piu'' valida.';
  end if;
  if exists (
    select 1 from public.player_instances
    where id = any(v_p.giocatori_offerti || v_p.giocatori_richiesti) and ritiro_annunciato
  ) then
    raise exception using errcode = '55000',
      message = 'Uno dei giocatori coinvolti ha annunciato il ritiro: la proposta non e'' piu'' valida.';
  end if;

  select count(*) into v_n from public.scelte_draft
  where id = any(v_p.scelte_offerte) and team_proprietario_id = v_da.id and stato in ('futura', 'determinata');
  if v_n <> cardinality(v_p.scelte_offerte) then
    raise exception using errcode = '55000',
      message = 'Una scelta offerta non e'' piu'' disponibile: la proposta non e'' piu'' valida.';
  end if;
  select count(*) into v_n from public.scelte_draft
  where id = any(v_p.scelte_richieste) and team_proprietario_id = v_a.id and stato in ('futura', 'determinata');
  if v_n <> cardinality(v_p.scelte_richieste) then
    raise exception using errcode = '55000',
      message = 'Una scelta richiesta non e'' piu'' disponibile: la proposta non e'' piu'' valida.';
  end if;

  if cardinality(v_p.scelte_offerte) > 0 and private.viola_regola_stepien(v_da.id, v_p.scelte_offerte) then
    raise exception using errcode = '22023',
      message = 'Regola Stepien: ' || v_da.nome || ' non puo'' cedere due proprie scelte consecutive (la ON e la OFF della stessa stagione, oppure la OFF di una stagione e la ON della successiva). La proposta non e'' piu'' valida.';
  end if;
  if cardinality(v_p.scelte_richieste) > 0 and private.viola_regola_stepien(v_a.id, v_p.scelte_richieste) then
    raise exception using errcode = '22023',
      message = 'Regola Stepien: non puoi cedere due tue scelte consecutive (la ON e la OFF della stessa stagione, oppure la OFF di una stagione e la ON della successiva).';
  end if;

  -- Prospetti del vivaio: ancora nei vivai giusti e posto libero in quello di chi li riceve.
  if cardinality(v_p.vivaio_offerti) + cardinality(v_p.vivaio_richiesti) > 0 then
    select count(*) into v_n from public.vivaio_prospetti where id = any(v_p.vivaio_offerti) and team_id = v_da.id;
    if v_n <> cardinality(v_p.vivaio_offerti) then
      raise exception using errcode = '55000', message = 'Un giocatore del vivaio offerto non e'' piu'' disponibile: la proposta non e'' piu'' valida.';
    end if;
    select count(*) into v_n from public.vivaio_prospetti where id = any(v_p.vivaio_richiesti) and team_id = v_a.id;
    if v_n <> cardinality(v_p.vivaio_richiesti) then
      raise exception using errcode = '55000', message = 'Un giocatore del tuo vivaio richiesto non e'' piu'' disponibile: la proposta non e'' piu'' valida.';
    end if;
    if (select count(*) from public.vivaio_prospetti where team_id = v_a.id) - cardinality(v_p.vivaio_richiesti) + cardinality(v_p.vivaio_offerti) > private.vivaio_slot_massimi(v_a.id) then
      raise exception using errcode = '22023', message = 'Non hai slot liberi nel vivaio per ricevere questo giocatore.';
    end if;
    if (select count(*) from public.vivaio_prospetti where team_id = v_da.id) - cardinality(v_p.vivaio_offerti) + cardinality(v_p.vivaio_richiesti) > private.vivaio_slot_massimi(v_da.id) then
      raise exception using errcode = '22023', message = v_da.nome || ' non ha piu'' slot liberi nel vivaio per ricevere questo giocatore.';
    end if;
  end if;

  select count(*) into v_rosa_da from public.player_instances where team_id = v_da.id;
  select count(*) into v_rosa_a  from public.player_instances where team_id = v_a.id;
  v_rosa_da := v_rosa_da - cardinality(v_p.giocatori_offerti) + cardinality(v_p.giocatori_richiesti);
  v_rosa_a  := v_rosa_a  - cardinality(v_p.giocatori_richiesti) + cardinality(v_p.giocatori_offerti);
  if v_rosa_da > private.rosa_massima() or v_rosa_a > private.rosa_massima() then
    raise exception using errcode = '22023', message = 'Lo scambio porterebbe una rosa oltre i 30 giocatori.';
  end if;
  if v_rosa_da < private.rosa_minima() or v_rosa_a < private.rosa_minima() then
    raise exception using errcode = '22023', message = 'Lo scambio lascerebbe una rosa sotto i 21 giocatori.';
  end if;

  select min(f.giornata) into v_prossima
  from public.fixtures f where f.league_id = v_lega.id and f.stato = 'programmata';

  update public.player_instances set team_id = v_a.id,  giornata_acquisizione = v_prossima where id = any(v_p.giocatori_offerti);
  update public.player_instances set team_id = v_da.id, giornata_acquisizione = v_prossima where id = any(v_p.giocatori_richiesti);
  update public.scelte_draft set team_proprietario_id = v_a.id,  aggiornata_il = now() where id = any(v_p.scelte_offerte);
  update public.scelte_draft set team_proprietario_id = v_da.id, aggiornata_il = now() where id = any(v_p.scelte_richieste);
  update public.vivaio_prospetti set team_id = v_a.id  where id = any(v_p.vivaio_offerti);
  update public.vivaio_prospetti set team_id = v_da.id where id = any(v_p.vivaio_richiesti);

  v_stagione := private.stagione_contratto(v_p.league_id);
  if private.monte_ingaggi(v_da.id, v_stagione) + private.ingaggi_impegnati_aste(v_da.id, null) > v_lega.tetto_ingaggi then
    raise exception using errcode = '22023',
      message = 'Questo scambio porterebbe ' || v_da.nome || ' oltre il tetto ingaggi.';
  end if;
  if private.monte_ingaggi(v_a.id, v_stagione) + private.ingaggi_impegnati_aste(v_a.id, null) > v_lega.tetto_ingaggi then
    raise exception using errcode = '22023',
      message = 'Questo scambio ti porterebbe oltre il tetto ingaggi.';
  end if;

  v_tutti := v_p.giocatori_offerti || v_p.giocatori_richiesti;
  if v_prossima is not null and cardinality(v_tutti) > 0 then
    -- Le formazioni NON si cancellano piu' (8 ottobre 2026): si tolgono solo i giocatori ceduti, e il resto
    -- (modulo, stile, ruoli, compiti, schieramento, panchina) resta com'era. Il posto lasciato libero in campo
    -- lo riempie la formazione automatica alla simulazione, o l'allenatore prima.
    v_form_tolte := private.togli_giocatori_dalle_formazioni(v_lega.id, array[v_da.id, v_a.id], v_tutti, v_prossima);
  end if;
  if v_form_tolte > 0 then
    v_nota := ' Controlla la formazione: era schierato un giocatore coinvolto.';
  end if;

  select coalesce(sum(ingaggio), 0) into v_delta_da
  from public.player_instances where id = any(v_p.giocatori_richiesti);
  v_delta_da := v_delta_da - coalesce((select sum(ingaggio) from public.player_instances where id = any(v_p.giocatori_offerti)), 0);
  v_delta_da := v_delta_da + coalesce((select sum(ingaggio) from public.vivaio_prospetti where id = any(v_p.vivaio_richiesti)), 0)
                           - coalesce((select sum(ingaggio) from public.vivaio_prospetti where id = any(v_p.vivaio_offerti)), 0);
  v_delta_a := -v_delta_da;

  if v_delta_da <> 0 then
    insert into public.transactions (league_id, team_id, tipo, importo, descrizione, saldo_dopo)
    values (v_lega.id, v_da.id, 'mercato_scambio', v_delta_da, 'Scambio con ' || v_a.nome, 0);
  end if;
  if v_delta_a <> 0 then
    insert into public.transactions (league_id, team_id, tipo, importo, descrizione, saldo_dopo)
    values (v_lega.id, v_a.id, 'mercato_scambio', v_delta_a, 'Scambio con ' || v_da.nome, 0);
  end if;

  update public.trade_proposals set stato = 'accettata', risolta_il = now()
  where id = v_p.id
  returning * into v_p;

  perform private.notifica(v_da.user_id, v_lega.id, 'mercato_esito', 'Scambio concluso con ' || v_a.nome,
    'La tua proposta e'' stata accettata.' || v_nota, jsonb_build_object('proposta_id', v_p.id));
  perform private.notifica(v_a.user_id, v_lega.id, 'mercato_esito', 'Scambio concluso con ' || v_da.nome,
    'Hai accettato la proposta.' || v_nota, jsonb_build_object('proposta_id', v_p.id));
  perform private.notifica_scambio_ufficiale(v_lega.id, v_da.id, v_a.id, v_p.id);

  return v_p;
end;
$function$;

-- private.estrai_svincolati(): niente estrazioni (ne' mosse dei bot) fuori dalla stagione regolare
CREATE OR REPLACE FUNCTION private.estrai_svincolati()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_oggi date;
  v_ora time;
  v_inizio_finestra timestamptz;
  v_lega bigint;
  v_estratti integer := 0;
begin
  v_ora := (now() at time zone 'Europe/Rome')::time;
  if not (v_ora >= time '23:30' and v_ora < time '23:45') then return 0; end if;
  v_oggi := (now() at time zone 'Europe/Rome')::date;

  -- Le 23:30 di stasera, ora di Roma: tutto cio' che e' stato estratto
  -- prima appartiene a un'apertura manuale dell'admin, non a questo giro.
  v_inizio_finestra := (v_oggi + time '23:30') at time zone 'Europe/Rome';

  for v_lega in select id from public.leagues where stato = 'stagione' and private.fase_mercato(id) = 'stagione' and fase_carriera <> 'offseason' and not mercato_bloccato loop
    -- Con la schedule a ogni minuto questa funzione rigira fino alle
    -- 23:45: senza questa guardia creerebbe una tornata nuova ogni volta.
    -- Le riesecuzioni servono da rete se il primo giro fallisce.
    if exists (
      select 1 from public.free_agent_auctions a
      where a.league_id = v_lega
        and a.giorno = v_oggi
        and a.origine = 'estrazione'
        and a.creata_il >= v_inizio_finestra
    ) then
      continue;
    end if;

    v_estratti := v_estratti + private.estrai_svincolati_lega(v_lega, v_oggi);
    perform private.offerte_mercato_squadre_pc(v_lega);
    perform private.proposte_mercato_squadre_pc(v_lega);
  end loop;
  return v_estratti;
end;
$function$;

-- private.estrai_under(): niente estrazioni (ne' mosse dei bot) fuori dalla stagione regolare
CREATE OR REPLACE FUNCTION private.estrai_under()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_ora time;
  v_oggi date;
  v_lega bigint;
  v_totale integer := 0;
begin
  v_ora := (now() at time zone 'Europe/Rome')::time;
  if not (v_ora >= time '23:30' and v_ora < time '23:45') then return 0; end if;
  v_oggi := (now() at time zone 'Europe/Rome')::date;
  for v_lega in select id from public.leagues where stato = 'stagione' and private.fase_mercato(id) = 'stagione' and not mercato_bloccato loop
    v_totale := v_totale + private.estrai_under_lega(v_lega, v_oggi);
  end loop;
  return v_totale;
end;
$function$;

