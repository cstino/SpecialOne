-- ============================================================
--  COUNTDOWN IN GIORNATE PER LA PROMOZIONE DEI PROSPETTI VIVAIO.
--
--  Deciso con l'utente il 4 settembre 2026: la regola precedente
--  ("promuovi entro la fine dell'off-season", applicata da
--  private.finalizza_offseason confrontando entrata_stagione con la
--  stagione appena chiusa) dava una finestra di durata VARIABILE a
--  seconda di QUANDO nella stagione veniva comprato il prospetto —
--  comprarlo a ridosso della fine stagione lasciava pochissimo margine
--  reale prima della chiusura dell'off-season successiva.
--
--  Nuova regola: ogni prospetto ha un conto alla rovescia in giornate
--  (public.vivaio_prospetti.giornate_rimanenti), impostato alla nascita
--  al numero di giornate della stagione regolare in cui entra in cantera,
--  e decrementato di 1 a ogni giornata REALMENTE simulata della lega
--  (quindi fermo durante l'off-season, che non ha giornate). Arrivato a
--  zero, il prospetto torna sul mercato UNDER — stessa strada del
--  rilascio manuale, stesso registro rilasci_vivaio_in_coda.
--
--  Idempotenza: public.decrementa_vivaio_giornate viene chiamata una
--  volta per giornata dall'edge function simula-giornata (stesso punto
--  dei quattro checkpoint gia' esistenti). Una tabella di controllo
--  (league_id, giornata) con lo stesso schema idempotente gia' visto per
--  gli altri checkpoint garantisce che un ritentativo del cron non
--  decrementi due volte la stessa giornata.
-- ============================================================

begin;

alter table public.vivaio_prospetti
  add column giornate_rimanenti smallint not null default 0 check (giornate_rimanenti >= 0);

comment on column public.vivaio_prospetti.giornate_rimanenti is
  'Conto alla rovescia in giornate REALMENTE simulate prima del rilascio automatico sul mercato UNDER; fermo durante l''off-season.';

create table private.vivaio_countdown_giornate (
  league_id bigint not null references public.leagues(id) on delete cascade,
  giornata smallint not null,
  eseguito_il timestamptz not null default now(),
  primary key (league_id, giornata)
);
comment on table private.vivaio_countdown_giornate is
  'Registro delle giornate in cui il countdown vivaio e'' gia'' stato decrementato: rende decrementa_vivaio_giornate idempotente se il cron ritenta.';

create function public.decrementa_vivaio_giornate(p_league_id bigint, p_giornata smallint)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_scaduto record;
  v_nome text;
  v_rilasciati integer := 0;
begin
  insert into private.vivaio_countdown_giornate (league_id, giornata)
  values (p_league_id, p_giornata)
  on conflict (league_id, giornata) do nothing;
  if not found then
    return jsonb_build_object('gia_eseguito', true, 'rilasciati', 0);
  end if;

  update public.vivaio_prospetti
  set giornate_rimanenti = giornate_rimanenti - 1
  where league_id = p_league_id;

  for v_scaduto in
    select vp.id, vp.league_id, vp.team_id, vp.player_id
    from public.vivaio_prospetti vp
    where vp.league_id = p_league_id and vp.giornate_rimanenti <= 0
    for update
  loop
    select p.nome into v_nome from public.players p where p.id = v_scaduto.player_id;
    delete from public.vivaio_prospetti where id = v_scaduto.id;
    insert into private.rilasci_vivaio_in_coda (league_id, player_id)
    values (v_scaduto.league_id, v_scaduto.player_id)
    on conflict (league_id, player_id) do nothing;
    perform private.notifica(
      (select user_id from public.teams where id = v_scaduto.team_id),
      v_scaduto.league_id, 'mercato_esito', 'Prospetto scaduto: ' || coalesce(v_nome, 'vivaio'),
      'Non è stato promosso in tempo: torna sul mercato UNDER.',
      jsonb_build_object('vivaio', true)
    );
    v_rilasciati := v_rilasciati + 1;
  end loop;

  return jsonb_build_object('gia_eseguito', false, 'rilasciati', v_rilasciati);
end;
$$;

revoke all on function public.decrementa_vivaio_giornate(bigint, smallint) from public, anon, authenticated;
grant execute on function public.decrementa_vivaio_giornate(bigint, smallint) to service_role;

CREATE OR REPLACE FUNCTION private.risolvi_aste_under_giorno(p_giorno date, p_league_id bigint DEFAULT NULL::bigint)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_asta record;
  v_offerente record;
  v_soglia bigint;
  v_vincitore record;
  v_stagione smallint;
  v_giornate_totali smallint;
  v_nome text;
  v_assegnate integer := 0;
begin
  for v_asta in
    select a.* from public.under_auctions a
    where a.giorno = p_giorno and a.stato = 'aperta'
      and (p_league_id is null or a.league_id = p_league_id)
    order by a.id
    for update
  loop
    v_stagione := private.stagione_contratto(v_asta.league_id);
    select soglia into v_soglia from private.under_auction_thresholds where auction_id = v_asta.id;
    select p.nome into v_nome from public.players p where p.id = v_asta.player_id;

    v_vincitore := null;

    select b.* into v_vincitore
    from public.under_bids b
    where b.auction_id = v_asta.id
      and b.ingaggio_offerto >= v_soglia
      and private.vivaio_slot_impegnati(b.team_id, v_asta.id) < private.vivaio_slot_massimi(b.team_id)
      and private.capienza_residua(b.team_id, v_stagione, null, v_asta.id) >= b.ingaggio_offerto
    order by b.ingaggio_offerto desc, b.aggiornata_il asc, b.id asc
    limit 1;

    if v_vincitore.id is null then
      update public.under_auctions set stato = 'deserta', risolta_il = now() where id = v_asta.id;
    else
      -- Quante giornate ha per essere promosso: tante quante la stagione
      -- regolare in cui entra in cantera (deciso con l'utente il 4
      -- settembre 2026, sostituisce il vecchio limite "entro l'off-season").
      -- Se la stagione non esiste ancora come riga (si e' in off-season e
      -- v_stagione punta gia' alla prossima) si scende sul valore di lega.
      select coalesce(
        (select s.giornate_totali from public.seasons s
          where s.league_id = v_asta.league_id and s.numero = v_stagione),
        (select l.giornate_totali from public.leagues l where l.id = v_asta.league_id)
      ) into v_giornate_totali;

      insert into public.vivaio_prospetti (league_id, team_id, player_id, ingaggio, entrata_stagione, giornate_rimanenti)
      values (v_asta.league_id, v_vincitore.team_id, v_asta.player_id, v_vincitore.ingaggio_offerto, v_stagione, v_giornate_totali);

      update public.under_auctions
      set stato = 'assegnata', vincitore_team_id = v_vincitore.team_id,
          ingaggio_finale = v_vincitore.ingaggio_offerto, risolta_il = now()
      where id = v_asta.id;

      perform private.notifica(
        (select user_id from public.teams where id = v_vincitore.team_id),
        v_asta.league_id, 'mercato_esito', 'Prospetto UNDER assegnato: ' || v_nome,
        'Entra in vivaio. Hai ' || v_giornate_totali || ' giornate per promuoverlo in prima squadra, o tornerà sul mercato.',
        jsonb_build_object('vivaio', true)
      );
      v_assegnate := v_assegnate + 1;
    end if;

    for v_offerente in
      select b.team_id, t.user_id from public.under_bids b
      join public.teams t on t.id = b.team_id where b.auction_id = v_asta.id
    loop
      if v_vincitore.id is null or v_offerente.team_id <> v_vincitore.team_id then
        perform private.notifica(v_offerente.user_id, v_asta.league_id, 'mercato_asta',
          'Prospetto UNDER: ' || v_nome,
          case when v_vincitore.id is null then 'Nessuna offerta ha raggiunto la richiesta.'
          else 'Se l''è aggiudicato un''altra squadra.' end,
          jsonb_build_object('auction_id', v_asta.id));
      end if;
    end loop;
  end loop;
  return v_assegnate;
end;
$function$;

CREATE OR REPLACE FUNCTION private.finalizza_offseason(p_league_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_league public.leagues;
  v_off public.offseasons;
  v_team record;
  v_candidate record;
  v_player record;
  v_rosa integer;
  v_ingaggi bigint;
  v_da_aggiungere integer;
  v_wage bigint;
  v_season bigint;
  v_aggiunti text[];
  v_rilasciati integer;
  v_attive integer;
begin
  select * into v_league from public.leagues where id = p_league_id for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Lega non trovata.';
  end if;
  if v_league.fase_carriera <> 'offseason' then
    raise exception using errcode = '55000', message = 'L''off-season non e'' attiva.';
  end if;

  select * into v_off
  from public.offseasons
  where league_id = p_league_id and stato = 'aperta'
  order by stagione_a desc limit 1
  for update;
  if not found then
    raise exception using errcode = '55000', message = 'Off-season aperta non trovata.';
  end if;
  if clock_timestamp() < v_off.scade_il then
    raise exception using errcode = '55000',
      message = 'L''off-season dura 24 ore e non puo'' essere chiusa prima della scadenza.';
  end if;

  if exists (
    select 1 from public.finestre_scelte
    where league_id = p_league_id and stagione = v_off.stagione_da and finestra = 'off'
      and risolta_il is null
  ) then
    begin
      perform private.risolvi_finestra_scelte(p_league_id, v_off.stagione_da, 'off', true);
    exception when others then
      raise warning 'mercato a scelte: risoluzione OFF-Season fallita per lega % stagione %: % (%)',
        p_league_id, v_off.stagione_da, sqlerrm, sqlstate;
    end;
  end if;

  select count(*)::integer into v_attive
  from public.teams where league_id = p_league_id and attiva;
  if v_attive < 4 then
    raise exception using errcode = '55000', message = 'Servono almeno 4 squadre attive per iniziare la stagione.';
  end if;

  update public.leagues set n_squadre = v_attive where id = p_league_id;

  update public.player_instances
  set team_id = null
  where league_id = p_league_id
    and team_id is not null
    and not ritirato
    and contratto_scadenza <= v_league.stagione_corrente;

  for v_team in
    select * from public.teams
    where league_id = p_league_id and attiva
    order by id for update
  loop
    v_aggiunti := array[]::text[];
    v_rilasciati := 0;

    -- Se la rosa attuale non e' sostenibile sotto il tetto, si applica
    -- l'insolvenza del design: escono prima gli ingaggi piu' alti finche'
    -- restano finanziabili anche i posti mancanti al minimo di 21. Sotto
    -- il tetto questo non dovrebbe piu' accadere per una rosa costruita
    -- interamente dopo la migrazione (ogni acquisizione verifica gia' la
    -- capienza), ma resta il paracadute per le rose ereditate dal vecchio
    -- modello a cassa (v. private.capienza_residua).
    loop
      select count(*)::integer, coalesce(sum(ingaggio), 0)::bigint
      into v_rosa, v_ingaggi
      from public.player_instances
      where team_id = v_team.id and not ritirato;

      exit when v_ingaggi + greatest(21 - v_rosa, 0) * 500000 <= v_league.tetto_ingaggi;

      select pi.id into v_candidate
      from public.player_instances pi
      where pi.team_id = v_team.id and not pi.ritirato
      order by pi.ingaggio desc, pi.overall_corrente asc, pi.id
      limit 1;
      if not found then
        raise exception using errcode = '55000', message = 'Tetto ingaggi insufficiente per completare la rosa di ' || v_team.nome || '.';
      end if;
      update public.player_instances set team_id = null where id = v_candidate.id;
      v_rilasciati := v_rilasciati + 1;
    end loop;

    select count(*)::integer, coalesce(sum(ingaggio), 0)::bigint
    into v_rosa, v_ingaggi
    from public.player_instances
    where team_id = v_team.id and not ritirato;
    v_da_aggiungere := greatest(21 - v_rosa, 0);

    while v_da_aggiungere > 0 loop
      select p.id as player_id, p.nome,
             coalesce(fap.overall_corrente, p.overall) as overall, coalesce(fap.eta_corrente, p.eta) as eta,
             pi.id as instance_id,
             coalesce(pi.ingaggio, private.ingaggio_teorico(coalesce(fap.overall_corrente, p.overall), coalesce(fap.eta_corrente, p.eta)))::bigint as ingaggio
      into v_candidate
      from public.players p
      left join public.player_instances pi
        on pi.league_id = p_league_id and pi.player_id = p.id
      left join public.free_agent_progression fap
        on fap.league_id = p_league_id and fap.player_id = p.id
      where p.campionato = any(v_league.campionati_attivi)
        and (pi.id is null or (pi.team_id is null and not pi.ritirato))
        and not exists (select 1 from public.retired_players rp where rp.league_id = p_league_id and rp.player_id = p.id)
        and coalesce(pi.ingaggio, private.ingaggio_teorico(coalesce(fap.overall_corrente, p.overall), coalesce(fap.eta_corrente, p.eta)))
          <= v_league.tetto_ingaggi - v_ingaggi - ((v_da_aggiungere - 1) * 500000)
      order by coalesce(pi.ingaggio, private.ingaggio_teorico(coalesce(fap.overall_corrente, p.overall), coalesce(fap.eta_corrente, p.eta))) asc,
               coalesce(fap.overall_corrente, p.overall) asc, p.id
      limit 1;

      if not found then
        raise exception using errcode = '55000', message = 'Non ci sono svincolati sostenibili per completare la rosa di ' || v_team.nome || '.';
      end if;

      v_wage := greatest(500000, v_candidate.ingaggio);
      if v_candidate.instance_id is null then
        insert into public.player_instances(
          league_id, player_id, team_id, overall_corrente, eta_corrente, ingaggio,
          condizione, infortunato_fino_a, contratto_scadenza
        ) values (
          p_league_id, v_candidate.player_id, v_team.id, v_candidate.overall,
          v_candidate.eta, v_wage, 100, 0, v_off.stagione_a
        );
        delete from public.free_agent_progression
        where league_id = p_league_id and player_id = v_candidate.player_id;
      else
        update public.player_instances
        set team_id = v_team.id,
            ingaggio = v_wage,
            contratto_scadenza = v_off.stagione_a,
            condizione = 100,
            infortunato_fino_a = 0
        where id = v_candidate.instance_id and team_id is null;
      end if;

      v_ingaggi := v_ingaggi + v_wage;
      v_da_aggiungere := v_da_aggiungere - 1;
      v_aggiunti := array_append(v_aggiunti, v_candidate.nome);
    end loop;

    select count(*)::integer, coalesce(sum(ingaggio), 0)::bigint
    into v_rosa, v_ingaggi
    from public.player_instances
    where team_id = v_team.id and not ritirato;

    if v_rosa not between 21 and 30 then
      raise exception using errcode = '55000', message = 'La rosa di ' || v_team.nome || ' non rispetta il limite 21-30.';
    end if;
    if v_league.tetto_ingaggi < v_ingaggi then
      raise exception using errcode = '55000', message = 'Tetto ingaggi insufficiente per gli ingaggi di ' || v_team.nome || '.';
    end if;

    update public.draft_team_state
    set stato = 'concluso', aggiornato_il = clock_timestamp()
    where league_id = p_league_id and team_id = v_team.id and stato <> 'concluso';

    if cardinality(v_aggiunti) > 0 or v_rilasciati > 0 then
      perform private.notifica(
        v_team.user_id, p_league_id, 'sistema', 'Rosa completata automaticamente',
        case when cardinality(v_aggiunti) > 0
          then cardinality(v_aggiunti) || ' svincolati aggiunti per raggiungere il minimo di 21 giocatori.'
          else 'Rosa riequilibrata automaticamente per rispettare il tetto ingaggi.' end,
        jsonb_build_object('view', 'team', 'aggiunti', cardinality(v_aggiunti), 'rilasciati', v_rilasciati)
      );
    end if;
  end loop;

  -- Il rilascio automatico dei prospetti non promossi in tempo non e' piu'
  -- legato alla chiusura dell'off-season (deciso con l'utente il 4
  -- settembre 2026: comprare un giovane a ridosso della fine stagione non
  -- deve costringere a promuoverlo quasi subito). Ora e' un conto alla
  -- rovescia in giornate dal momento dell'acquisto, decrementato ogni
  -- giornata simulata da public.decrementa_vivaio_giornate — qui non
  -- resta piu' nulla da fare.

  update public.offseasons
  set stato = 'conclusa', conclusa_il = clock_timestamp()
  where id = v_off.id;
  update public.leagues
  set stagione_corrente = v_off.stagione_a,
      fase_carriera = 'normale',
      offseason_fine = null,
      stato = 'stagione'
  where id = p_league_id;

  for v_player in
    select pi.id, pi.eta_corrente, p.nome, t.user_id
    from public.player_instances pi
    join public.players p on p.id = pi.player_id
    join public.teams t on t.id = pi.team_id and t.attiva
    where pi.league_id = p_league_id and not pi.ritirato and not pi.ritiro_annunciato
      and pi.eta_corrente >= 34
      and random() < private.probabilita_ritiro(pi.eta_corrente)
  loop
    update public.player_instances set ritiro_annunciato = true where id = v_player.id;
    perform private.notifica(v_player.user_id, p_league_id, 'sistema',
      v_player.nome || ' annuncia il ritiro',
      'Giochera'' ancora questa stagione, poi lascera'' la carriera: non puo'' essere ceduto in trattativa.',
      jsonb_build_object('player_instance_id', v_player.id));
  end loop;

  -- Ritiro dei mai-scelti: legge l'eta' vera tracciata in
  -- free_agent_progression (non piu' un'eta' ipotetica ricalcolata),
  -- e ripulisce la riga tracciata quando il giocatore esce dal pool.
  insert into public.retired_players(league_id, player_id, stagione)
  select p_league_id, fap.player_id, v_off.stagione_a
  from public.free_agent_progression fap
  where fap.league_id = p_league_id
    and not exists (
      select 1 from public.player_instances pi
      where pi.league_id = p_league_id and pi.player_id = fap.player_id and pi.team_id is not null
    )
    and not exists (
      select 1 from public.retired_players rp
      where rp.league_id = p_league_id and rp.player_id = fap.player_id
    )
    and fap.eta_corrente >= 34
    and random() < private.probabilita_ritiro(fap.eta_corrente)
  on conflict do nothing;

  delete from public.free_agent_progression fap
  using public.retired_players rp
  where fap.league_id = p_league_id and rp.league_id = p_league_id and rp.player_id = fap.player_id;

  v_season := private.inizializza_stagione(p_league_id);

  perform private.notifica(
    t.user_id, p_league_id, 'sistema', 'La nuova stagione e'' iniziata',
    'La prima giornata si giochera'' alle 23:00. Prepara la formazione.',
    jsonb_build_object('view', 'overview', 'season_id', v_season)
  )
  from public.teams t
  where t.league_id = p_league_id and t.attiva;

  return jsonb_build_object(
    'league_id', p_league_id,
    'season_id', v_season,
    'stagione', v_off.stagione_a,
    'prima_giornata', private.primo_calcio_dopo(v_off.scade_il)
  );
end;
$function$

;

-- Backfill: i prospetti gia' in cantera (comprati sotto la vecchia regola)
-- ripartono con un countdown pieno da oggi invece di ereditare una
-- scadenza calcolata a ritroso che nessuno ha mai visto arrivare — non e'
-- corretto sorprendere chi ha comprato un prospetto ieri con un rilascio
-- imminente per una regola che non esisteva ancora quando l'ha comprato.
update public.vivaio_prospetti vp
set giornate_rimanenti = coalesce(
  (select s.giornate_totali from public.seasons s
    where s.league_id = vp.league_id and s.numero = private.stagione_contratto(vp.league_id)),
  (select l.giornate_totali from public.leagues l where l.id = vp.league_id)
)
where giornate_rimanenti = 0;

commit;
