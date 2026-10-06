-- Draft OFF-Season e sorteggio delle conferenze in diretta, uno dopo l'altro.
--
--  * Alla chiusura dell'off-season (con le conferenze accese) le scelte della
--    finestra OFF si risolvono come sempre, subito, ma si RIVELANO una alla volta:
--    30 secondi a scelta (15 di annuncio, 15 di reveal). Le notifiche ai
--    proprietari partono solo quando la scelta e' rivelata.
--  * Il sorteggio East/West parte 3 minuti dopo l'ultima scelta.
--  * public.scelte_live_stato: per ogni scelta, il giocatore solo da quando e' rivelato.
--  * Con le conferenze la prima giornata e' alle 23:00 di almeno 20 ore dopo la fine
--    del sorteggio: chi scopre la propria conferenza ha un giorno per schierarsi.
--  Funzioni ricostruite dalla definizione live (pg_get_functiondef).

create table if not exists public.scelte_live (
  id              bigserial primary key,
  league_id       bigint not null references public.leagues(id) on delete cascade,
  stagione        smallint not null,
  finestra        text not null check (finestra in ('on','off')),
  avviato_il      timestamptz not null,
  passo_secondi   smallint not null default 30,
  intro_secondi   smallint not null default 15,
  totale          smallint not null,
  notificate      smallint not null default 0,
  creato_il       timestamptz not null default now(),
  unique (league_id, stagione, finestra)
);
alter table public.scelte_live enable row level security;
drop policy if exists scelte_live_membri on public.scelte_live;
create policy scelte_live_membri on public.scelte_live for select to authenticated
  using ((select private.e_membro(league_id)));
revoke all on public.scelte_live from public, anon;
grant select on public.scelte_live to authenticated;
-- Le righe le scrive solo il database.

CREATE OR REPLACE FUNCTION private.risolvi_una_scelta(p_scelta_id bigint)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_scelta     public.scelte_draft;
  v_pref       record;
  v_player_id  bigint;
  v_ingaggio   bigint;
  v_istanza    bigint;
  v_nome       text;
  v_righe      integer;
  v_prossima   integer;
  v_scadenza   smallint;
begin
  select * into v_scelta from public.scelte_draft where id = p_scelta_id for update;
  if not found or v_scelta.stato <> 'determinata' then
    return false;
  end if;

  select min(f.giornata) into v_prossima
  from public.fixtures f
  where f.league_id = v_scelta.league_id and f.stato = 'programmata';

  -- Il contratto scade a fine della stagione della finestra. Se pero' la
  -- finestra viene risolta in ritardo, a stagione gia' voltata, quella
  -- scadenza sarebbe gia' passata: il giocatore entrerebbe in rosa con un
  -- contratto scaduto, fuori dal monte ingaggi e da rinnovare subito.
  -- Si prende quindi la piu' avanti fra le due.
  select greatest(v_scelta.stagione, l.stagione_corrente) into v_scadenza
  from public.leagues l where l.id = v_scelta.league_id;

  for v_pref in
    select pr.player_id, sp.ingaggio_teorico
    from public.scelte_preferenze pr
    join public.scelte_pool sp
      on sp.league_id = v_scelta.league_id and sp.stagione = v_scelta.stagione
     and sp.finestra = v_scelta.finestra and sp.player_id = pr.player_id
    where pr.scelta_id = v_scelta.id
    order by pr.ordine
  loop
    if exists (
      select 1 from public.player_instances pi
      where pi.league_id = v_scelta.league_id and pi.player_id = v_pref.player_id
        and pi.team_id is not null
    ) then
      continue;
    end if;

    if (select count(*) from public.player_instances pi
        where pi.team_id = v_scelta.team_proprietario_id) >= private.rosa_massima() then
      exit;
    end if;

    -- Confermato dall'utente il 28 agosto: un ingaggio che non entra
    -- sotto il tetto non puo' entrare in rosa. Si salta e si passa alla
    -- preferenza successiva.
    if private.capienza_residua(v_scelta.team_proprietario_id, v_scelta.stagione, null)
       < v_pref.ingaggio_teorico then
      continue;
    end if;

    v_player_id := v_pref.player_id;
    v_ingaggio  := v_pref.ingaggio_teorico;
    exit;
  end loop;

  if v_player_id is null then
    update public.scelte_draft set stato = 'vuota', aggiornata_il = now()
    where id = v_scelta.id;
    return false;
  end if;

  select p.nome into v_nome from public.players p where p.id = v_player_id;

  insert into public.player_instances as pi
    (league_id, player_id, team_id, overall_corrente, eta_corrente, ingaggio, contratto_scadenza, giornata_acquisizione)
  select v_scelta.league_id, p.id, v_scelta.team_proprietario_id,
         coalesce(fap.overall_corrente, p.overall), coalesce(fap.eta_corrente, p.eta),
         v_ingaggio, v_scadenza, v_prossima
  from public.players p
  left join public.free_agent_progression fap
    on fap.league_id = v_scelta.league_id and fap.player_id = p.id
  where p.id = v_player_id
  on conflict (league_id, player_id) do update
    set team_id = excluded.team_id,
        ingaggio = excluded.ingaggio,
        contratto_scadenza = excluded.contratto_scadenza,
        giornata_acquisizione = excluded.giornata_acquisizione
    where pi.team_id is null
  returning pi.id into v_istanza;

  get diagnostics v_righe = row_count;
  if v_righe <> 1 then
    -- qualcuno se l'e' preso nel frattempo: questa scelta resta vuota,
    -- non fa fallire niente a valle.
    update public.scelte_draft set stato = 'vuota', aggiornata_il = now()
    where id = v_scelta.id;
    return false;
  end if;

  delete from public.free_agent_progression
  where league_id = v_scelta.league_id and player_id = v_player_id;

  update public.scelte_draft
  set stato = 'usata', player_instance_id = v_istanza, aggiornata_il = now()
  where id = v_scelta.id;

  insert into public.transactions
    (league_id, team_id, tipo, importo, descrizione, saldo_dopo)
  select v_scelta.league_id, v_scelta.team_proprietario_id, 'scelta_draft', -v_ingaggio,
         'Scelta ' || v_scelta.posizione || 'ª (' || v_scelta.finestra || '-Season '
           || v_scelta.stagione || '): ' || coalesce(v_nome, 'giocatore'),
         0;

  -- Nel draft in diretta la notifica parte quando la scelta viene rivelata
  -- (private.notifica_scelte_rivelate), non alla risoluzione.
  if coalesce(current_setting('private.silenzia_scelte', true), '') <> '1' then
    perform private.notifica(
      (select user_id from public.teams where id = v_scelta.team_proprietario_id),
      v_scelta.league_id, 'mercato_esito',
      'Scelta esercitata: ' || coalesce(v_nome, 'giocatore'),
      'Entra in rosa con un contratto di una stagione a '
        || private.in_milioni(v_ingaggio) || ' M€.',
      jsonb_build_object('scelta_id', v_scelta.id)
    );
  end if;

  return true;
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
  v_scelte_live integer;
  v_avvio_live timestamptz;
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
      -- In diretta le notifiche delle scelte partono alla rivelazione.
      if v_league.conferenze_attive then perform set_config('private.silenzia_scelte', '1', true); end if;
      perform private.risolvi_finestra_scelte(p_league_id, v_off.stagione_da, 'off', true);
    exception when others then
      raise warning 'mercato a scelte: risoluzione OFF-Season fallita per lega % stagione %: % (%)',
        p_league_id, v_off.stagione_da, sqlerrm, sqlstate;
    end;
  end if;

  perform set_config('private.silenzia_scelte', '', true);

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
      fase_carriera = case when v_league.conferenze_attive then 'sorteggio' else 'normale' end,
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

  -- Con le conferenze la stagione non parte subito: prima il sorteggio East/West
  -- in diretta, e solo a sorteggio concluso nasce il calendario
  -- (private.completa_sorteggi_scaduti).
  if v_league.conferenze_attive then
    perform private.crea_sorteggio_conferenze(p_league_id, v_off.stagione_a);
    v_season := null;
    -- Draft dei giocatori in diretta (30 s a scelta) e, 3 minuti dopo l'ultima
    -- scelta, il sorteggio. Parte al minuto pieno successivo alla chiusura.
    select count(*)::integer into v_scelte_live
    from public.scelte_draft
    where league_id = p_league_id and stagione = v_off.stagione_da and finestra = 'off' and stato in ('usata', 'vuota');
    if v_scelte_live > 0 then
      v_avvio_live := date_trunc('minute', clock_timestamp()) + interval '1 minute';
      insert into public.scelte_live (league_id, stagione, finestra, avviato_il, totale)
      values (p_league_id, v_off.stagione_da, 'off', v_avvio_live, v_scelte_live)
      on conflict (league_id, stagione, finestra) do nothing;
      update public.sorteggi_conferenze
      set avviato_il = v_avvio_live + (v_scelte_live * 30 + 180) * interval '1 second'
      where league_id = p_league_id and stagione = v_off.stagione_a and completato_il is null;
    end if;
  else
    v_season := private.inizializza_stagione(p_league_id);
  end if;

  perform private.notifica(
    t.user_id, p_league_id, 'sistema',
    case when v_league.conferenze_attive then 'Draft e sorteggio in diretta' else 'La nuova stagione e'' iniziata' end,
    case when v_league.conferenze_attive then 'Entra ora: prima il draft dei giocatori, poi il sorteggio delle conferenze East e West.'
         else 'La prima giornata si giochera'' alle 23:00. Prepara la formazione.' end,
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
$function$;

CREATE OR REPLACE FUNCTION private.inizializza_stagione(p_league_id bigint)
 RETURNS bigint
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  v_league public.leagues;
  v_season_id bigint;
  v_teams bigint[];
  v_rotation bigint[];
  v_next bigint[];
  v_team_count integer;
  v_slot_count integer;
  v_rounds integer;
  v_giornata integer;
  v_home bigint;
  v_away bigint;
  v_swap bigint;
  v_scadenza timestamptz;
  v_prima_giornata timestamptz;
  v_start date;
  v_campo_neutro boolean;
  v_giornata_mezza integer;
  v_data_mezza timestamptz;
  v_gia_assegnate integer;
  v_gruppo text;
  v_conferenze boolean;
begin
  select * into v_league from public.leagues where id = p_league_id for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Lega non trovata.';
  end if;
  v_conferenze := v_league.conferenze_attive;

  select id into v_season_id
  from public.seasons
  where league_id = p_league_id and numero = v_league.stagione_corrente;
  if found then return v_season_id; end if;

  if v_league.stato <> 'stagione' or v_league.fase_carriera <> 'normale' then
    raise exception using errcode = '55000', message = 'La lega non e'' pronta per iniziare la stagione.';
  end if;

  select coalesce(array_agg(t.id order by t.ordine_draft nulls last, t.id), array[]::bigint[]), count(*)::integer
  into v_teams, v_team_count
  from public.teams t
  where t.league_id = p_league_id and t.attiva;

  if v_team_count <> v_league.n_squadre then
    raise exception using errcode = '55000', message = 'Il numero di squadre attive non coincide con le impostazioni.';
  end if;

  select o.scade_il into v_scadenza
  from public.offseasons o
  where o.league_id = p_league_id and o.stagione_a = v_league.stagione_corrente
  order by o.id desc limit 1;

  -- Con le conferenze il calendario nasce a sorteggio concluso, non alla scadenza
  -- dell'off-season: la prima giornata e' alle 23:00 di almeno 20 ore da adesso
  -- (chi scopre la propria conferenza ha un giorno per schierarsi).
  v_prima_giornata := private.primo_calcio_dopo(case when v_conferenze then clock_timestamp() + interval '20 hours' else coalesce(v_scadenza, clock_timestamp()) end);
  v_start := (v_prima_giornata at time zone 'Europe/Rome')::date;

  insert into public.seasons(league_id, numero, stato, data_inizio, data_fine, giornate_totali)
  values (p_league_id, v_league.stagione_corrente, 'in_corso', v_start,
          v_start + (v_league.giornate_totali - 1), v_league.giornate_totali)
  returning id into v_season_id;

  -- Il blocco "non svincolabile per 10 giornate dall'acquisto" confronta
  -- giornata_acquisizione con la prossima giornata in programma, ma
  -- giornata_acquisizione e' un numero di giornata SENZA stagione: a
  -- cavallo di due stagioni il confronto perde senso. Un acquisto alla
  -- giornata 19 della stagione scorsa, letto alla giornata 12 di questa,
  -- dava -7 giornate trascorse — messaggio assurdo ("mancano 17
  -- giornate") e blocco attivo fino alla 29ª di una stagione in cui il
  -- giocatore era in rosa dall'inizio. Un acquisto della stagione
  -- precedente non e' per definizione "recente": si azzera qui, alla
  -- nascita di ogni stagione, dove NULL significa gia' "mai bloccato"
  -- (draft, rose iniziali, off-season).
  update public.player_instances
  set giornata_acquisizione = null
  where league_id = p_league_id and giornata_acquisizione is not null;

  insert into public.standings(season_id, league_id, team_id, posizione, conferenza)
  select v_season_id, p_league_id, t.id,
         row_number() over(partition by c.conferenza order by t.nome, t.id)::smallint,
         c.conferenza
  from public.teams t
  left join (
    select x.team_id, x.conferenza
    from public.sorteggio_estrazioni x
    join public.sorteggi_conferenze s on s.id = x.sorteggio_id
    where s.league_id = p_league_id and s.stagione = v_league.stagione_corrente and v_conferenze
  ) c on c.team_id = t.id
  where t.league_id = p_league_id and t.attiva;

  -- Con le conferenze (East/West) si gioca solo dentro la propria: stesso
  -- metodo del cerchio, applicato a ciascun gruppo, sulle STESSE giornate.
  -- Senza conferenze c'e' un solo gruppo con tutte le squadre.
  foreach v_gruppo in array case when v_conferenze then array['est', 'ovest'] else array[''] end loop
    if v_conferenze then
      select coalesce(array_agg(x.team_id order by x.ordine), array[]::bigint[])
      into v_teams
      from public.sorteggio_estrazioni x
      join public.sorteggi_conferenze s on s.id = x.sorteggio_id
      where s.league_id = p_league_id and s.stagione = v_league.stagione_corrente and x.conferenza = v_gruppo;
      v_team_count := cardinality(v_teams);
    end if;
  v_slot_count := v_team_count + (v_team_count % 2);
  v_rounds := v_slot_count - 1;
  for v_leg in 1..v_league.n_gironi loop
    v_campo_neutro := (v_league.n_gironi % 2 = 1 and v_leg = v_league.n_gironi);
    v_rotation := v_teams;
    if v_team_count % 2 = 1 then
      v_rotation := array_append(v_rotation, null::bigint);
    end if;
    for v_round in 1..v_rounds loop
      v_giornata := (v_leg - 1) * v_rounds + v_round;
      for v_pair in 1..(v_slot_count / 2) loop
        v_home := v_rotation[v_pair];
        v_away := v_rotation[v_slot_count - v_pair + 1];
        if v_home is null or v_away is null then continue; end if;
        if mod(v_round, 2) = 0 then
          v_swap := v_home; v_home := v_away; v_away := v_swap;
        end if;
        if mod(v_leg, 2) = 0 then
          v_swap := v_home; v_home := v_away; v_away := v_swap;
        end if;
        insert into public.fixtures(season_id, league_id, giornata, home_team_id, away_team_id, data_sim, campo_neutro)
        values (v_season_id, p_league_id, v_giornata, v_home, v_away,
                v_prima_giornata + ((v_giornata - 1) * interval '1 day'), v_campo_neutro);
      end loop;
      v_next := array[v_rotation[1], v_rotation[v_slot_count]];
      for v_index in 2..(v_slot_count - 1) loop
        v_next := array_append(v_next, v_rotation[v_index]);
      end loop;
      v_rotation := v_next;
    end loop;
  end loop;
  end loop;

  -- ------------------------------------------------------------
  --  Mercato a scelte: inventario, posizioni di transizione, apertura
  --  ON-Season. Tutto best-effort — non deve mai impedire alla stagione
  --  di iniziare (docs/decisioni-draft-picks.md §2.1, §3.1).
  -- ------------------------------------------------------------
  begin
    -- Bootstrap: solo alla primissima stagione di una lega nuova, che non
    -- ha ne' un draft precedente ne' un playoff precedente da cui
    -- ereditare le scelte 1..4. genera_scelte_draft parte da
    -- stagione_corrente+1 e non tocca mai la stagione 1: la si genera qui,
    -- una tantum, e si assegna subito ON-Season 1 dalla spesa del draft di
    -- creazione (nessun playoff esiste ancora). OFF-Season 1 resta
    -- 'futura' fino ai playoff di questa stessa stagione.
    if v_league.stagione_corrente = 1 then
      insert into public.scelte_draft (league_id, team_origine_id, team_proprietario_id, stagione, finestra)
      select p_league_id, t.id, t.id, 1, f.finestra
      from public.teams t
      cross join (values ('on'), ('off')) as f(finestra)
      where t.league_id = p_league_id and t.attiva
      on conflict (league_id, team_origine_id, stagione, finestra) do nothing;

      perform private.assegna_posizioni_transizione(p_league_id, 1::smallint, 'on');
    end if;

    perform private.genera_scelte_draft(p_league_id);

    if v_league.stagione_corrente = 2 then
      select count(*) into v_gia_assegnate
      from public.scelte_draft
      where league_id = p_league_id and stagione = 2 and stato <> 'futura';
      if v_gia_assegnate = 0 then
        perform private.assegna_posizioni_transizione(p_league_id, 2::smallint);
      end if;
    end if;

    if v_league.stagione_corrente >= 1 then
      select count(*) into v_gia_assegnate
      from public.scelte_draft
      where league_id = p_league_id and stagione = v_league.stagione_corrente
        and finestra = 'on' and stato = 'determinata';
      if v_gia_assegnate > 0 and not exists (
        select 1 from public.finestre_scelte
        where league_id = p_league_id and stagione = v_league.stagione_corrente and finestra = 'on'
      ) then
        v_giornata_mezza := v_league.giornate_totali / 2;
        select f.data_sim into v_data_mezza
        from public.fixtures f
        where f.season_id = v_season_id and f.giornata = v_giornata_mezza and f.bracket_tie_id is null
        limit 1;
        if v_data_mezza is not null then
          perform private.svela_finestra_scelte(
            p_league_id, v_league.stagione_corrente, 'on', private.alle_13_roma(v_data_mezza)
          );
        end if;
      end if;
    end if;
  exception when others then
    raise warning 'mercato a scelte: inizializzazione fallita per lega %: % (%)', p_league_id, sqlerrm, sqlstate;
  end;

  return v_season_id;
end;
$function$;

-- Notifiche delle scelte rivelate + chiusura dei sorteggi, sullo stesso cron.
create or replace function private.notifica_scelte_rivelate()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_d record;
  v_rivelate integer;
  v_p record;
begin
  for v_d in
    select * from public.scelte_live
    where notificate < totale
      and clock_timestamp() >= avviato_il + intro_secondi * interval '1 second'
  loop
    v_rivelate := least(v_d.totale, floor(extract(epoch from (clock_timestamp() - v_d.avviato_il - v_d.intro_secondi * interval '1 second')) / v_d.passo_secondi)::integer + 1);
    for v_p in
      select row_number() over (order by sd.posizione)::integer as n, sd.id as scelta_id, sd.stato, sd.team_proprietario_id,
             pi.ingaggio, p.nome
      from public.scelte_draft sd
      left join public.player_instances pi on pi.id = sd.player_instance_id
      left join public.players p on p.id = pi.player_id
      where sd.league_id = v_d.league_id and sd.stagione = v_d.stagione and sd.finestra = v_d.finestra
        and sd.stato in ('usata', 'vuota')
      order by sd.posizione
    loop
      continue when v_p.n <= v_d.notificate or v_p.n > v_rivelate;
      if v_p.stato = 'usata' then
        perform private.notifica(
          (select user_id from public.teams where id = v_p.team_proprietario_id),
          v_d.league_id, 'mercato_esito',
          'Scelta esercitata: ' || coalesce(v_p.nome, 'giocatore'),
          'Entra in rosa con un contratto di una stagione a ' || private.in_milioni(v_p.ingaggio) || ' M€.',
          jsonb_build_object('scelta_id', v_p.scelta_id)
        );
      end if;
    end loop;
    update public.scelte_live set notificate = v_rivelate where id = v_d.id;
  end loop;
end;
$$;
revoke all on function private.notifica_scelte_rivelate() from public, anon, authenticated;

create or replace function private.completa_sorteggi_scaduti()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_s record;
begin
  perform private.notifica_scelte_rivelate();
  for v_s in
    select s.*
    from public.sorteggi_conferenze s
    join public.leagues l on l.id = s.league_id
    where s.completato_il is null
      and l.fase_carriera = 'sorteggio'
      and l.stagione_corrente = s.stagione
      and clock_timestamp() >= s.avviato_il + (s.totale * s.passo_secondi + 20) * interval '1 second'
    order by s.id
  loop
    begin
      update public.leagues set fase_carriera = 'normale' where id = v_s.league_id;
      perform private.inizializza_stagione(v_s.league_id);
      update public.sorteggi_conferenze set completato_il = clock_timestamp() where id = v_s.id;
      perform private.notifica(
        t.user_id, v_s.league_id, 'sistema', 'Le conferenze sono pronte',
        'La stagione e'' iniziata: la prima giornata si giochera'' alle 23:00. Prepara la formazione.',
        jsonb_build_object('view', 'overview')
      )
      from public.teams t
      where t.league_id = v_s.league_id and t.attiva;
    exception when others then
      raise warning 'sorteggio conferenze: lega % non completata: % (%)', v_s.league_id, sqlerrm, sqlstate;
    end;
  end loop;
end;
$$;

-- Stato del draft in diretta: le scelte con il giocatore solo da quando sono
-- rivelate, e l'ora del server (il client sincronizza l'orologio).
create or replace function public.scelte_live_stato(p_league_id bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_d public.scelte_live;
  v_ora timestamptz := clock_timestamp();
  v_sorteggio timestamptz;
  v_picks jsonb;
begin
  if not (select private.e_membro(p_league_id)) then
    raise exception using errcode = '42501', message = 'Non fai parte di questa lega.';
  end if;
  select * into v_d from public.scelte_live
  where league_id = p_league_id order by stagione desc, id desc limit 1;
  if not found then return null; end if;

  select s.avviato_il into v_sorteggio from public.sorteggi_conferenze s
  where s.league_id = p_league_id order by s.stagione desc limit 1;

  select coalesce(jsonb_agg(jsonb_build_object(
      'n', x.n,
      'posizione', x.posizione,
      'team_id', x.team_proprietario_id,
      'team_origine_id', x.team_origine_id,
      'intro_il', x.intro_il,
      'reveal_il', x.reveal_il,
      'esito', case when v_ora >= x.reveal_il then x.stato end,
      'giocatore', case when v_ora >= x.reveal_il and x.stato = 'usata' then jsonb_build_object(
          'player_id', x.player_id, 'nome', x.nome, 'overall', x.overall, 'eta', x.eta,
          'posizioni', x.posizioni, 'foto_url', x.foto_url, 'ingaggio', x.ingaggio,
          'nazionalita', x.nazionalita, 'club', x.club) end
    ) order by x.n), '[]'::jsonb)
  into v_picks
  from (
    select row_number() over (order by sd.posizione)::integer as n, sd.posizione, sd.team_proprietario_id, sd.team_origine_id, sd.stato,
           v_d.avviato_il + ((row_number() over (order by sd.posizione) - 1) * v_d.passo_secondi) * interval '1 second' as intro_il,
           v_d.avviato_il + ((row_number() over (order by sd.posizione) - 1) * v_d.passo_secondi + v_d.intro_secondi) * interval '1 second' as reveal_il,
           p.id as player_id, p.nome, pi.overall_corrente as overall, pi.eta_corrente as eta, p.posizioni, p.foto_url,
           pi.ingaggio, p.nazionalita, p.club
    from public.scelte_draft sd
    left join public.player_instances pi on pi.id = sd.player_instance_id
    left join public.players p on p.id = pi.player_id
    where sd.league_id = p_league_id and sd.stagione = v_d.stagione and sd.finestra = v_d.finestra
      and sd.stato in ('usata', 'vuota')
  ) x;

  return jsonb_build_object(
    'ora_server', v_ora,
    'stagione', v_d.stagione,
    'finestra', v_d.finestra,
    'avviato_il', v_d.avviato_il,
    'passo_secondi', v_d.passo_secondi,
    'intro_secondi', v_d.intro_secondi,
    'totale', v_d.totale,
    'fine_il', v_d.avviato_il + (v_d.totale * v_d.passo_secondi) * interval '1 second',
    'sorteggio_il', v_sorteggio,
    'picks', v_picks
  );
end;
$$;
revoke all on function public.scelte_live_stato(bigint) from public, anon;
grant execute on function public.scelte_live_stato(bigint) to authenticated;
