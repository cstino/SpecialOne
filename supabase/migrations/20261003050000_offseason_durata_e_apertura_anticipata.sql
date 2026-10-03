-- ============================================================
--  OFF-SEASON: DURATA PER LEGA, APERTURA ANTICIPATA, SVINCOLATI CHIUSI
--  Deciso con il committente il 3 ottobre 2026 (Serie F, fine stagione 1).
--
--  1. leagues.durata_offseason_ore: quanto dura l'off-season (prima fisso a
--     7 giorni). Default 168 ore, invariato per le altre leghe; Serie F 48.
--     La scadenza fissa anche l'estrazione del draft OFF (svela_finestra_scelte
--     la ricava da offseason_fine), quindi segue la stessa durata.
--  2. leagues.offseason_apribile_dal: se valorizzata anticipa lo sblocco delle
--     24 ore dopo l'ultima partita. Serie F: subito.
--  3. In off-season il mercato degli svincolati e' chiuso (offri_per_svincolato
--     rifiuta); scambi, UNDER e rinnovi restano aperti come prima.
-- ============================================================

alter table public.leagues
  add column if not exists durata_offseason_ore smallint not null default 168
    check (durata_offseason_ore between 1 and 720),
  add column if not exists offseason_apribile_dal timestamptz;

comment on column public.leagues.durata_offseason_ore is 'Durata dell''off-season in ore (da prepara_offseason alla chiusura).';
comment on column public.leagues.offseason_apribile_dal is 'Se valorizzata, l''off-season si puo'' aprire da questo istante invece che 24 ore dopo l''ultima partita.';

CREATE OR REPLACE FUNCTION private.sblocco_offseason(p_league_id bigint)
 RETURNS timestamp with time zone
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select least(
    (select max(m.simulata_il) + interval '24 hours' from public.matches m where m.league_id = p_league_id),
    (select l.offseason_apribile_dal from public.leagues l where l.id = p_league_id)
  );
$function$;

CREATE OR REPLACE FUNCTION public.prepara_offseason(p_league_id bigint, p_squadre_rimosse bigint[] DEFAULT '{}'::bigint[], p_posti_nuovi smallint DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_user uuid := (select auth.uid());
  v_lega public.leagues;
  v_offseason public.offseasons;
  v_attive integer;
  v_rimosse integer;
  v_target integer;
  v_player record;
  v_ritirati integer := 0;
begin
  if v_user is null then
    raise exception using errcode = '42501', message = 'Devi accedere per aprire l''off-season.';
  end if;

  select * into v_lega from public.leagues where id = p_league_id for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Lega non trovata.';
  end if;
  if v_lega.admin_id <> v_user then
    raise exception using errcode = '42501', message = 'Solo l''admin può aprire l''off-season.';
  end if;
  if v_lega.stato <> 'conclusa' or v_lega.fase_carriera <> 'normale' then
    raise exception using errcode = '55000', message = 'L''off-season è disponibile soltanto dopo una stagione conclusa.';
  end if;
  if clock_timestamp() < private.sblocco_offseason(p_league_id) then
    raise exception using errcode = '55000', message = format(
      'L''off-season si apre 24 ore dopo l''ultima giornata: da %s, così tutti possono rivedere i risultati.',
      to_char(private.sblocco_offseason(p_league_id) at time zone 'Europe/Rome', 'DD/MM "alle" HH24:MI'));
  end if;
  if coalesce(p_posti_nuovi, 0) not between 0 and 16 then
    raise exception using errcode = '22023', message = 'Numero di nuovi posti non valido.';
  end if;
  if cardinality(coalesce(p_squadre_rimosse, '{}'::bigint[])) <>
     (select count(distinct id) from unnest(coalesce(p_squadre_rimosse, '{}'::bigint[])) x(id)) then
    raise exception using errcode = '22023', message = 'La lista delle squadre rimosse contiene duplicati.';
  end if;
  if exists (
    select 1 from unnest(coalesce(p_squadre_rimosse, '{}'::bigint[])) x(id)
    left join public.teams t on t.id = x.id and t.league_id = p_league_id and t.attiva
    where t.id is null
  ) then
    raise exception using errcode = '22023', message = 'Una squadra da rimuovere non appartiene alla lega o è già inattiva.';
  end if;
  if exists (
    select 1 from public.teams
    where id = any(coalesce(p_squadre_rimosse, '{}'::bigint[])) and user_id = v_lega.admin_id
  ) then
    raise exception using errcode = '22023', message = 'L''admin non può rimuovere la propria squadra.';
  end if;

  select count(*) into v_attive from public.teams where league_id = p_league_id and attiva;
  v_rimosse := cardinality(coalesce(p_squadre_rimosse, '{}'::bigint[]));
  v_target := v_attive - v_rimosse + coalesce(p_posti_nuovi, 0);
  if v_target not between 4 and 20 then
    raise exception using errcode = '22023', message = 'La prossima stagione deve avere da 4 a 20 squadre.';
  end if;

  insert into public.offseasons (league_id, stagione_da, stagione_a, scade_il, posti_nuovi)
  values (p_league_id, v_lega.stagione_corrente, v_lega.stagione_corrente + 1,
          ((now() at time zone 'Europe/Rome') + make_interval(hours => v_lega.durata_offseason_ore)) at time zone 'Europe/Rome',
          coalesce(p_posti_nuovi, 0))
  returning * into v_offseason;

  if v_rimosse > 0 then
    update public.trade_proposals
    set stato = 'scaduta', risolta_il = now()
    where league_id = p_league_id and stato = 'in_attesa'
      and (da_team_id = any(p_squadre_rimosse) or a_team_id = any(p_squadre_rimosse));

    update public.player_instances
    set team_id = null
    where league_id = p_league_id and team_id = any(p_squadre_rimosse);

    delete from public.scelte_draft
    where league_id = p_league_id
      and team_origine_id = any(p_squadre_rimosse)
      and stato = 'futura';

    update public.teams
    set attiva = false, uscita_stagione = v_lega.stagione_corrente
    where league_id = p_league_id and id = any(p_squadre_rimosse);
  end if;

  for v_player in
    select pi.id, pi.player_id, p.nome, t.user_id
    from public.player_instances pi
    join public.players p on p.id = pi.player_id
    join public.teams t on t.id = pi.team_id and t.attiva
    where pi.league_id = p_league_id and pi.ritiro_annunciato and not pi.ritirato
  loop
    update public.player_instances
    set team_id = null, ritirato = true, ritiro_annunciato = false
    where id = v_player.id;
    insert into public.retired_players(league_id, player_id, stagione)
    values (p_league_id, v_player.player_id, v_lega.stagione_corrente)
    on conflict do nothing;
    v_ritirati := v_ritirati + 1;
    perform private.notifica(v_player.user_id, p_league_id, 'sistema',
      v_player.nome || ' si ritira',
      'Il ritiro annunciato a inizio stagione e'' ora effettivo: la carriera termina qui.',
      jsonb_build_object('player_instance_id', v_player.id));
  end loop;

  -- Invecchiamento di fine stagione: il join sulla squadra attiva e'
  -- stato tolto (deciso il 30 agosto 2026), cosi' uno svincolato reale
  -- invecchia esattamente come chi e' in rosa.
  for v_player in
    select pi.id, pi.eta_corrente, pi.infortunato_fino_a
    from public.player_instances pi
    where pi.league_id = p_league_id and not pi.ritirato
    order by pi.id
    for update of pi
  loop
    update public.player_instances
    set eta_corrente = least(45, v_player.eta_corrente + 1),
        condizione = 100,
        -- La pausa fra due stagioni vale 6 giornate di recupero, non una
        -- guarigione completa (deciso con l'utente l'11 settembre 2026).
        -- Prima qui si azzerava: chi si rompeva per 10 giornate all'ultima
        -- di playoff ripartiva sano, e un infortunio grave di fine stagione
        -- non costava niente. Ora se ne porta dietro 4.
        infortunato_fino_a = greatest(0, v_player.infortunato_fino_a - 6),
        -- Fedina pulita a ogni nuova stagione, come all'inizio dei playoff:
        -- ne' il conto delle ammonizioni ne' una squalifica gia' maturata
        -- attraversano il confine fra due stagioni.
        ammonizioni_stagione = 0,
        squalificato_fino_a = 0,
        progressione_residuo = 0
    where id = v_player.id;
  end loop;

  -- Stesso invecchiamento per chi non e' mai stato scelto in questa lega,
  -- residuo azzerato come per player_instances.
  update public.free_agent_progression
  set eta_corrente = least(45, eta_corrente + 1), progressione_residuo = 0, aggiornato_il = now()
  where league_id = p_league_id;

  update public.leagues
  set n_squadre = v_target,
      stato = 'stagione',
      fase_carriera = 'offseason',
      offseason_fine = v_offseason.scade_il
  where id = p_league_id;

  return jsonb_build_object(
    'league_id', p_league_id,
    'offseason_id', v_offseason.id,
    'stagione_a', v_offseason.stagione_a,
    'scade_il', v_offseason.scade_il,
    'squadre_attese', v_target,
    'posti_nuovi', p_posti_nuovi,
    'ritirati', v_ritirati
  );
end;
$function$
;

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
  if not private.mercato_aperto_lega(v_asta.league_id) then
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
$function$
;

update public.leagues set durata_offseason_ore = 48, offseason_apribile_dal = now() where id = 63;

notify pgrst, 'reload schema';
