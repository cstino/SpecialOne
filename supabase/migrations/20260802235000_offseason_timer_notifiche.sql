-- ============================================================
--  OFF-SEASON A TEMPO, CALCIO D'INIZIO ALLE 23 E AVVISI ELIMINABILI
--
--  L'off-season dura almeno 24 ore reali: la scadenza e' salvata come
--  timestamptz e non puo' essere anticipata dall'admin. Alla scadenza il
--  server completa le rose corte fino a 21 con gli svincolati piu'
--  economici, chiude i rinnovi e crea il calendario automaticamente.
-- ============================================================

create index if not exists offseasons_scadenza_aperte_idx
  on public.offseasons (scade_il, league_id)
  where stato = 'aperta';

-- Una notifica puo' essere rimossa soltanto dal suo destinatario. La tabella
-- resta senza policy DELETE: il browser passa da questa RPC verificabile.
create or replace function public.elimina_notifica(p_notifica_id bigint)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
  v_eliminate integer;
begin
  if v_user is null then
    raise exception using errcode = '42501', message = 'Devi accedere per eliminare una notifica.';
  end if;

  delete from public.notifications
  where id = p_notifica_id
    and user_id = v_user;

  get diagnostics v_eliminate = row_count;
  return v_eliminate = 1;
end;
$$;

revoke all on function public.elimina_notifica(bigint) from public, anon, authenticated;
grant execute on function public.elimina_notifica(bigint) to authenticated;

-- Il primo calcio d'inizio e' il primo 23:00 di Roma strettamente successivo
-- alla scadenza. Alle 22:59 si gioca lo stesso giorno; alle 23:00 esatte si
-- passa al giorno seguente. I timestamptz attraversano correttamente l'ora
-- legale, mentre l'orario civile viene costruito esplicitamente a Roma.
create or replace function private.primo_calcio_dopo(p_scadenza timestamptz)
returns timestamptz
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_locale timestamp := p_scadenza at time zone 'Europe/Rome';
  v_calcio timestamp;
begin
  v_calcio := date_trunc('day', v_locale) + interval '23 hours';
  if v_locale >= v_calcio then
    v_calcio := v_calcio + interval '1 day';
  end if;
  return v_calcio at time zone 'Europe/Rome';
end;
$$;

revoke all on function private.primo_calcio_dopo(timestamptz) from public, anon, authenticated;

-- Stessa generazione a metodo del cerchio gia' in produzione, ma le fixture
-- ricevono un istante preciso alle 23:00 invece della mezzanotte implicita.
create or replace function private.inizializza_stagione(p_league_id bigint)
returns bigint
language plpgsql
volatile
security invoker
set search_path = ''
as $$
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
begin
  select * into v_league from public.leagues where id = p_league_id for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Lega non trovata.';
  end if;

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

  -- Per la prima stagione, che non ha un'off-season precedente, si usa il
  -- prossimo 23:00 utile a partire dall'istante di creazione del calendario.
  v_prima_giornata := private.primo_calcio_dopo(coalesce(v_scadenza, clock_timestamp()));
  v_start := (v_prima_giornata at time zone 'Europe/Rome')::date;

  insert into public.seasons(league_id, numero, stato, data_inizio, data_fine)
  values (p_league_id, v_league.stagione_corrente, 'in_corso', v_start,
          v_start + (v_league.giornate_totali - 1))
  returning id into v_season_id;

  insert into public.standings(season_id, league_id, team_id, posizione)
  select v_season_id, p_league_id, t.id,
         row_number() over(order by t.nome, t.id)::smallint
  from public.teams t
  where t.league_id = p_league_id and t.attiva;

  v_slot_count := v_team_count + (v_team_count % 2);
  v_rounds := v_slot_count - 1;
  for v_leg in 1..v_league.n_gironi loop
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
        if mod(v_round + v_pair, 2) = 0 then
          v_swap := v_home; v_home := v_away; v_away := v_swap;
        end if;
        if mod(v_leg, 2) = 0 then
          v_swap := v_home; v_home := v_away; v_away := v_swap;
        end if;
        insert into public.fixtures(season_id, league_id, giornata, home_team_id, away_team_id, data_sim)
        values (v_season_id, p_league_id, v_giornata, v_home, v_away,
                v_prima_giornata + ((v_giornata - 1) * interval '1 day'));
      end loop;
      v_next := array[v_rotation[1], v_rotation[v_slot_count]];
      for v_index in 2..(v_slot_count - 1) loop
        v_next := array_append(v_next, v_rotation[v_index]);
      end loop;
      v_rotation := v_next;
    end loop;
  end loop;
  return v_season_id;
end;
$$;

revoke all on function private.inizializza_stagione(bigint) from public, anon, authenticated;
grant execute on function private.inizializza_stagione(bigint) to service_role;

-- Chiusura interna condivisa fra cron e comando admin. Il lock sulla lega
-- rende l'operazione idempotente anche se cron e admin arrivano insieme.
create or replace function private.finalizza_offseason(p_league_id bigint)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_league public.leagues;
  v_off public.offseasons;
  v_team record;
  v_candidate record;
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

  select count(*)::integer into v_attive
  from public.teams where league_id = p_league_id and attiva;
  if v_attive < 4 then
    raise exception using errcode = '55000', message = 'Servono almeno 4 squadre attive per iniziare la stagione.';
  end if;

  -- I posti di espansione non occupati alla scadenza decadono: il calendario
  -- usa le squadre realmente iscritte, senza tenere bloccata tutta la lega.
  update public.leagues set n_squadre = v_attive where id = p_league_id;

  update public.player_instances pi
  set team_id = null
  from public.contract_renewals cr
  where cr.offseason_id = v_off.id
    and cr.player_instance_id = pi.id
    and cr.stato in ('in_attesa', 'controproposta');

  update public.contract_renewals
  set stato = 'scaduto', risolta_il = clock_timestamp()
  where offseason_id = v_off.id and stato in ('in_attesa', 'controproposta');

  -- Uno spin lasciato senza risposta non resta sospeso per sempre: il
  -- giocatore torna semplicemente nel pool degli svincolati.
  update public.offseason_spins
  set stato = 'asta', risolta_il = clock_timestamp()
  where offseason_id = v_off.id and stato = 'proposto';

  for v_team in
    select * from public.teams
    where league_id = p_league_id and attiva
    order by id for update
  loop
    v_aggiunti := array[]::text[];
    v_rilasciati := 0;

    -- Se la rosa attuale non e' sostenibile, si applica l'insolvenza del
    -- design: escono prima gli ingaggi piu' alti finche' restano finanziabili
    -- anche i posti mancanti al minimo di 21.
    loop
      select count(*)::integer, coalesce(sum(ingaggio), 0)::bigint
      into v_rosa, v_ingaggi
      from public.player_instances
      where team_id = v_team.id and not ritirato;

      exit when v_ingaggi + greatest(21 - v_rosa, 0) * 500000 <= v_team.budget;

      select pi.id into v_candidate
      from public.player_instances pi
      where pi.team_id = v_team.id and not pi.ritirato
      order by pi.ingaggio desc, pi.overall_corrente asc, pi.id
      limit 1;
      if not found then
        raise exception using errcode = '55000', message = 'Budget insufficiente per completare la rosa di ' || v_team.nome || '.';
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
      select p.id as player_id, p.nome, p.overall, p.eta,
             pi.id as instance_id,
             coalesce(pi.ingaggio, private.ingaggio_teorico(p.overall, p.eta))::bigint as ingaggio
      into v_candidate
      from public.players p
      left join public.player_instances pi
        on pi.league_id = p_league_id and pi.player_id = p.id
      where p.campionato = any(v_league.campionati_attivi)
        and (pi.id is null or (pi.team_id is null and not pi.ritirato))
        and coalesce(pi.ingaggio, private.ingaggio_teorico(p.overall, p.eta))
          <= v_team.budget - v_ingaggi - ((v_da_aggiungere - 1) * 500000)
      order by coalesce(pi.ingaggio, private.ingaggio_teorico(p.overall, p.eta)) asc,
               p.overall asc, p.id
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
    if v_team.budget < v_ingaggi then
      raise exception using errcode = '55000', message = 'Budget insufficiente per gli ingaggi di ' || v_team.nome || '.';
    end if;

    update public.draft_team_state
    set stato = 'concluso', club_corrente = null, aggiornato_il = clock_timestamp()
    where league_id = p_league_id and team_id = v_team.id and stato <> 'concluso';

    update public.teams set budget = budget - v_ingaggi where id = v_team.id;
    insert into public.transactions(league_id, team_id, tipo, importo, descrizione, saldo_dopo)
    values (p_league_id, v_team.id, 'ingaggi_stagione', -v_ingaggi,
            'Ingaggi stagione ' || v_off.stagione_a, v_team.budget - v_ingaggi);

    if cardinality(v_aggiunti) > 0 or v_rilasciati > 0 then
      perform private.notifica(
        v_team.user_id, p_league_id, 'sistema', 'Rosa completata automaticamente',
        case when cardinality(v_aggiunti) > 0
          then cardinality(v_aggiunti) || ' svincolati aggiunti per raggiungere il minimo di 21 giocatori.'
          else 'Rosa riequilibrata automaticamente per rispettare il budget.' end,
        jsonb_build_object('view', 'team', 'aggiunti', cardinality(v_aggiunti), 'rilasciati', v_rilasciati)
      );
    end if;
  end loop;

  update public.offseasons
  set stato = 'conclusa', conclusa_il = clock_timestamp()
  where id = v_off.id;
  update public.leagues
  set stagione_corrente = v_off.stagione_a,
      fase_carriera = 'normale',
      offseason_fine = null,
      stato = 'stagione'
  where id = p_league_id;

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
$$;

revoke all on function private.finalizza_offseason(bigint) from public, anon, authenticated;

-- Il pulsante admin resta come recupero manuale dopo la scadenza, ma non puo'
-- mai abbreviare le 24 ore. Normalmente arriva prima il cron.
create or replace function public.avvia_prossima_stagione(p_league_id bigint)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
  v_league public.leagues;
begin
  select * into v_league from public.leagues where id = p_league_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Lega non trovata.';
  end if;
  if v_league.admin_id <> v_user then
    raise exception using errcode = '42501', message = 'Solo l''admin puo'' avviare la nuova stagione.';
  end if;
  return private.finalizza_offseason(p_league_id);
end;
$$;

revoke all on function public.avvia_prossima_stagione(bigint) from public, anon, authenticated;
grant execute on function public.avvia_prossima_stagione(bigint) to authenticated;

-- Il cron gira ogni minuto ma lavora solo sulle poche righe aperte e scadute,
-- servite dall'indice parziale. Un errore su una lega non blocca le altre.
create or replace function private.finalizza_offseason_scadute()
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_off record;
  v_finite integer := 0;
begin
  for v_off in
    select o.league_id
    from public.offseasons o
    where o.stato = 'aperta' and o.scade_il <= clock_timestamp()
    order by o.scade_il, o.league_id
  loop
    begin
      perform private.finalizza_offseason(v_off.league_id);
      v_finite := v_finite + 1;
    exception when others then
      -- L'errore resta visibile in cron.job_run_details. La lega rimane aperta
      -- e verra' riprovata al minuto successivo dopo una correzione dei dati.
      raise warning 'Off-season lega % non finalizzata: %', v_off.league_id, sqlerrm;
    end;
  end loop;
  return v_finite;
end;
$$;

revoke all on function private.finalizza_offseason_scadute() from public, anon, authenticated;

select cron.schedule(
  'finalizza-offseason-scadute',
  '* * * * *',
  $cron$select private.finalizza_offseason_scadute();$cron$
);

-- La simulazione si sposta dalle 00:00 alle 23:00 di Roma. La data_sim e'
-- confrontata come istante, quindi una fixture futura non parte in anticipo.
create or replace function private.simula_giornata_notturna()
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_oggi date;
  v_chiave text;
  v_lega bigint;
  v_lanciate integer := 0;
begin
  if extract(hour from (now() at time zone 'Europe/Rome')) <> 23 then
    return 0;
  end if;

  v_oggi := (now() at time zone 'Europe/Rome')::date;
  select decrypted_secret into v_chiave
  from vault.decrypted_secrets
  where name = 'chiave_simulazione';

  if v_chiave is null then
    raise exception using errcode = '55000',
      message = 'Manca il segreto chiave_simulazione nel vault: il cron non puo'' autenticarsi.';
  end if;

  for v_lega in
    select l.id
    from public.leagues l
    where l.stato = 'stagione'
      and l.fase_carriera = 'normale'
      and exists (
        select 1 from public.fixtures f
        where f.league_id = l.id
          and f.stato = 'programmata'
          and f.data_sim <= now()
      )
      and not exists (
        select 1
        from public.matches m
        join public.fixtures f2 on f2.id = m.fixture_id
        where f2.league_id = l.id
          and (m.simulata_il at time zone 'Europe/Rome')::date = v_oggi
      )
    order by l.id
  loop
    perform net.http_post(
      url := 'https://hhvyyjpbsgjcaaaizgwb.supabase.co/functions/v1/simula-giornata',
      body := jsonb_build_object('league_id', v_lega),
      headers := jsonb_build_object('Content-Type', 'application/json', 'apikey', v_chiave),
      timeout_milliseconds := 120000
    );
    v_lanciate := v_lanciate + 1;
  end loop;
  return v_lanciate;
end;
$$;

revoke all on function private.simula_giornata_notturna() from public, anon, authenticated;

comment on function private.simula_giornata_notturna() is
  'Invocata ogni ora dal cron: simula una giornata soltanto alle 23:00 di Europe/Rome.';
