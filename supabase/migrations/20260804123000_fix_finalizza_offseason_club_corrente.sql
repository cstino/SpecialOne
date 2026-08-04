-- Difetto preesistente scoperto con `supabase db lint` mentre si sistemava il
-- mercato, non causato da questo lavoro: la migrazione del draft a pacchetti
-- (20260803120000) ha droppato draft_team_state.club_corrente, ma
-- private.finalizza_offseason (20260802235000) la scrive ancora a fine
-- off-season. La funzione e' chiamata ogni minuto dal cron
-- finalizza_offseason_scadute per ogni off-season scaduta; l'errore viene
-- incassato da un blocco exception-when-others che si limita a un
-- `raise warning`, quindi non fa fallire il cron ma **nessuna** off-season
-- puo' mai concludersi automaticamente da quando e' stato applicato il draft
-- a pacchetti. Nessuna lega in produzione e' ancora arrivata a
-- quel punto, quindi non ha ancora perso dati: si ripara ora, prima che
-- succeda davvero.

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
    set stato = 'concluso', aggiornato_il = clock_timestamp()
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
