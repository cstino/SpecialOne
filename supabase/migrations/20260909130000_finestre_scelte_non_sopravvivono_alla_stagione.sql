-- ============================================================
--  UNA FINESTRA DEL MERCATO A SCELTE POTEVA SOPRAVVIVERE ALLA SUA STAGIONE
--
--  Segnalato dall'utente il 9 settembre 2026: in LegaBot i giocatori del
--  draft di off-season non erano stati attribuiti a nessuno.
--
--  COSA E' SUCCESSO
--  La finestra OFF di una stagione si apre solo DOPO che si e' risolta la
--  finestra ON della stessa stagione: e' una catena, in
--  private.avanza_finestre_scelte. L'istante dell'estrazione della ON viene
--  fissato quando la finestra si svela, prendendo la data di calendario
--  della giornata di meta' stagione.
--
--  La stagione 3 di LegaBot e' stata pero' giocata piu' in fretta del suo
--  calendario (simulazioni forzate dal pannello admin in una lega di test):
--  le partite erano programmate fino al 10 settembre, l'ultima e' stata
--  simulata il 7. L'estrazione della ON-Season 3 era fissata al 14. La
--  stagione e' finita prima che quell'istante arrivasse: la finestra non si
--  e' mai risolta, non ha mai aperto la OFF-Season 3, e l'off-season 3->4
--  si e' chiusa senza draft. Sono rimaste orfane 16 scelte (8 ON + 8 OFF),
--  tutte 'determinata' e mai usate, e su 8 di quelle i partecipanti avevano
--  gia' espresso 36 righe di preferenze, mai onorate.
--
--  DUE CORREZIONI
--  1. avanza_finestre_scelte chiude subito le finestre la cui stagione e'
--     gia' conclusa, invece di lasciarle scattare settimane dopo. Senza
--     questo, il 14 settembre la ON-Season 3 si sarebbe risolta a stagione
--     4 in corso, e subito dopo avrebbe creato una OFF-Season 3 morta.
--  2. svela_finestra_scelte, per una finestra OFF, accetta un istante
--     esplicito quando quello naturale non esiste piu'. Prima, in quel caso,
--     scriveva NULL: e con estrazione_il NULL la finestra nasce MORTA,
--     perche' sia il cron sia admin_forza_estrazione_scelte filtrano
--     "estrazione_il is not null". Nessuno avrebbe potuto piu' risolverla.
--
--  Entrambe le funzioni sono state ottenute per sostituzione mirata sul
--  testo live (pg_get_functiondef), non riscritte a memoria: il diff
--  mostra solo le righe aggiunte. E' la stessa precauzione che il 9
--  settembre ha evitato di distruggere inizializza_stagione.
--
--  Il recupero dei dati di LegaBot e' in un file separato, applicato a
--  mano: tocca le rose di una lega e non deve rigirare su altri ambienti.
-- ============================================================

begin;

CREATE OR REPLACE FUNCTION private.avanza_finestre_scelte()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_lega record;
  v_giornata_mezza integer;
  v_data_mezza timestamptz;
  v_finestra record;
  v_risolte integer := 0;
begin
  -- Passaggio di recupero: leghe la cui stagione corrente e' iniziata
  -- PRIMA che questa automazione esistesse (es. LegaBot, stagione 2 gia'
  -- in corso al momento di questa migrazione). inizializza_stagione fa lo
  -- stesso lavoro alla nascita di ogni stagione successiva; qui si
  -- recupera solo chi e' rimasto indietro, ed e' innocuo ripeterlo:
  -- svela_finestra_scelte non ritocca una finestra gia' svelata.
  for v_lega in
    select l.id as league_id, l.stagione_corrente, s.id as season_id, s.giornate_totali
    from public.leagues l
    join public.seasons s on s.league_id = l.id and s.numero = l.stagione_corrente
    where l.stato = 'stagione' and l.fase_carriera = 'normale' and l.stagione_corrente >= 2
      and exists (
        select 1 from public.scelte_draft sd
        where sd.league_id = l.id and sd.stagione = l.stagione_corrente
          and sd.finestra = 'on' and sd.stato = 'determinata'
      )
      and not exists (
        select 1 from public.finestre_scelte f
        where f.league_id = l.id and f.stagione = l.stagione_corrente and f.finestra = 'on'
      )
  loop
    begin
      v_giornata_mezza := v_lega.giornate_totali / 2;
      select f.data_sim into v_data_mezza
      from public.fixtures f
      where f.season_id = v_lega.season_id and f.giornata = v_giornata_mezza and f.bracket_tie_id is null
      limit 1;
      if v_data_mezza is not null then
        perform private.svela_finestra_scelte(
          v_lega.league_id, v_lega.stagione_corrente, 'on', private.alle_13_roma(v_data_mezza)
        );
      end if;
    exception when others then
      raise warning 'mercato a scelte: recupero apertura ON-Season fallito per lega % stagione %: % (%)',
        v_lega.league_id, v_lega.stagione_corrente, sqlerrm, sqlstate;
    end;
  end loop;

  -- Preferenze PC su tutte le finestre ancora aperte, non solo quelle in
  -- scadenza: cosi' una squadra PC non resta "in attesa" per giorni.
  for v_finestra in
    select league_id, stagione, finestra from public.finestre_scelte where risolta_il is null
  loop
    begin
      perform private.preferenze_squadre_pc(v_finestra.league_id, v_finestra.stagione, v_finestra.finestra);
    exception when others then
      raise warning 'mercato a scelte: preferenze PC fallite per lega % stagione % finestra %: % (%)',
        v_finestra.league_id, v_finestra.stagione, v_finestra.finestra, sqlerrm, sqlstate;
    end;
  end loop;

  -- Una finestra non deve sopravvivere alla propria stagione. Se la lega e'
  -- gia' passata alla stagione successiva e la finestra e' ancora aperta,
  -- la sua estrazione non ha piu' senso: va chiusa subito, non alla data
  -- fissata settimane prima. Senza questo blocco succede quanto capitato a
  -- LegaBot: la stagione 3 e' stata giocata piu' in fretta del suo
  -- calendario (simulazioni forzate), la ON-Season 3 aveva l'estrazione al
  -- 14 settembre e la stagione e' finita il 7. Non essendosi mai risolta
  -- non ha mai aperto la OFF-Season 3, e l'off-season si e' chiusa senza
  -- draft. Peggio: quella finestra sarebbe scattata a stagione 4 in corso.
  for v_finestra in
    select f.league_id, f.stagione, f.finestra
    from public.finestre_scelte f
    join public.leagues l on l.id = f.league_id
    where f.risolta_il is null
      and f.estrazione_il is not null
      and f.stagione < l.stagione_corrente
    order by f.league_id, f.stagione, f.finestra
  loop
    begin
      perform private.risolvi_finestra_scelte(v_finestra.league_id, v_finestra.stagione, v_finestra.finestra, true);
      v_risolte := v_risolte + 1;
      raise warning 'mercato a scelte: chiusa in ritardo la finestra % della stagione % (lega %), la stagione era gia'' conclusa',
        v_finestra.finestra, v_finestra.stagione, v_finestra.league_id;
    exception when others then
      raise warning 'mercato a scelte: chiusura tardiva fallita per lega % stagione % finestra %: % (%)',
        v_finestra.league_id, v_finestra.stagione, v_finestra.finestra, sqlerrm, sqlstate;
    end;
  end loop;

  for v_finestra in
    select league_id, stagione, finestra
    from public.finestre_scelte
    where finestra = 'on' and risolta_il is null
      and estrazione_il is not null and estrazione_il <= now()
    order by league_id, stagione
  loop
    begin
      perform private.risolvi_finestra_scelte(v_finestra.league_id, v_finestra.stagione, 'on', true);
      v_risolte := v_risolte + 1;
      if not exists (
        select 1 from public.finestre_scelte
        where league_id = v_finestra.league_id and stagione = v_finestra.stagione and finestra = 'off'
      ) then
        perform private.svela_finestra_scelte(v_finestra.league_id, v_finestra.stagione, 'off');
      end if;
    exception when others then
      raise warning 'mercato a scelte: risoluzione ON-Season fallita per lega % stagione %: % (%)',
        v_finestra.league_id, v_finestra.stagione, sqlerrm, sqlstate;
    end;
  end loop;
  return v_risolte;
end;
$function$
;

CREATE OR REPLACE FUNCTION private.svela_finestra_scelte(p_league_id bigint, p_stagione smallint, p_finestra text, p_estrazione_il timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_lega        public.leagues;
  v_totali      integer;
  v_determinate integer;
  v_quando      timestamptz;
  v_estratti    integer;
begin
  if p_finestra not in ('on', 'off') then
    raise exception using errcode = '22023', message = 'Finestra non valida: ' || p_finestra;
  end if;

  select * into v_lega from public.leagues where id = p_league_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Lega non trovata.';
  end if;

  -- Per la 'off' l'istante non si passa: e' la scadenza dell'off-season
  -- che segue quella stagione. Finche' quell'off-season non e' cominciata
  -- la scadenza non esiste, e l'istante resta ignoto.
  if p_finestra = 'off' then
    -- Di norma l'istante e' la scadenza dell'off-season che segue quella
    -- stagione. Se quella scadenza non c'e' piu' — finestra recuperata a
    -- posteriori, con la stagione gia' chiusa e offseason_fine azzerata —
    -- si accetta l'istante passato da chi chiama, invece di lasciare NULL.
    -- Con NULL la finestra nascerebbe MORTA: sia avanza_finestre_scelte sia
    -- admin_forza_estrazione_scelte filtrano "estrazione_il is not null", e
    -- nessuno potrebbe piu' risolverla. E' esattamente quello che e'
    -- successo a LegaBot con la OFF-Season 3.
    v_quando := coalesce(
      case when p_stagione = v_lega.stagione_corrente
           then v_lega.offseason_fine else null end,
      p_estrazione_il);
  else
    v_quando := p_estrazione_il;
  end if;

  if v_quando is not null and v_quando <= now() then
    raise exception using errcode = '22023',
      message = 'L''estrazione va fissata nel futuro: le preferenze nascerebbero gia'' congelate.';
  end if;

  select count(*), count(*) filter (where stato = 'determinata')
    into v_totali, v_determinate
  from public.scelte_draft
  where league_id = p_league_id and stagione = p_stagione and finestra = p_finestra;

  if v_totali = 0 then
    raise exception using errcode = 'P0002',
      message = 'Nessuna scelta esiste per questa finestra: vanno generate prima.';
  end if;

  if v_determinate = 0 then
    raise exception using errcode = '55000',
      message = 'Le posizioni di questa finestra non sono ancora state assegnate: '
                || 'senza ordine di scelta la finestra non puo'' essere svelata.';
  end if;

  insert into public.finestre_scelte (league_id, stagione, finestra, estrazione_il)
  values (p_league_id, p_stagione, p_finestra, v_quando)
  on conflict (league_id, stagione, finestra) do nothing;

  v_estratti := private.estrai_pool_scelte(p_league_id, p_stagione, p_finestra);
  return v_estratti;
end;
$function$
;

commit;
