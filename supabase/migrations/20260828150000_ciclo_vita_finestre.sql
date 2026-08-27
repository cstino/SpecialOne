-- ============================================================
--  MERCATO A SCELTE: APERTURA DELLA FINESTRA E GUARDRAIL SULLA CHIUSURA
--  docs/decisioni-draft-picks.md §3.1, §4, §6 bis
--
--  Motivo, senza girarci intorno: risolvendo una finestra mai aperta ho
--  marcato 'vuota' tutte le scelte OFF-Season 2 di LegaBot. Nessun
--  giocatore era stato assegnato e ho ripristinato lo stato, ma il punto
--  resta — risolvi_finestra_scelte non aveva NESSUNA condizione
--  d'ingresso, e una chiamata fuori tempo azzera in silenzio le scelte di
--  tutta la lega. Per il gioco e' irreversibile: le scelte 'vuota' non si
--  riesercitano.
--
--  Il ciclo di vita di una finestra ha tre stadi, e ognuno presuppone il
--  precedente:
--
--    1. posizioni assegnate   (§2: dai playoff, o §2.1 per la stagione 1)
--       -> le scelte passano da 'futura' a 'determinata'
--    2. finestra aperta       (§6 bis: pool di 40 estratto, poi immobile)
--       -> le squadre sottomettono le liste di preferenze
--    3. finestra risolta      (§4: scorrimento delle posizioni)
--       -> le scelte diventano 'usata' o 'vuota'
--
--  Questa migrazione rende espliciti i passaggi 1->2 e 2->3, cosi' che
--  saltarne uno sia un errore invece di un danno silenzioso.
-- ============================================================

-- ------------------------------------------------------------
--  Apertura
--
--  Non fa altro che estrarre il pool, ma rifiuta di farlo se le posizioni
--  non sono ancora state assegnate: un pool senza ordine di scelta non
--  serve a nessuno, e lasciarlo estrarre darebbe l'impressione che la
--  finestra sia aperta quando non lo e'.
--
--  L'estrazione e' gia' idempotente (estrai_pool_scelte non ritocca una
--  finestra popolata), quindi ripetere l'apertura e' innocuo.
-- ------------------------------------------------------------

create or replace function private.apri_finestra_scelte(
  p_league_id bigint,
  p_stagione  smallint,
  p_finestra  text
)
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_totali      integer;
  v_determinate integer;
  v_estratti    integer;
begin
  if p_finestra not in ('on', 'off') then
    raise exception using errcode = '22023', message = 'Finestra non valida: ' || p_finestra;
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
                || 'senza ordine di scelta la finestra non puo'' aprirsi.';
  end if;

  v_estratti := private.estrai_pool_scelte(p_league_id, p_stagione, p_finestra);
  return v_estratti;
end;
$$;

comment on function private.apri_finestra_scelte(bigint, smallint, text) is
  'Apre una finestra del mercato a scelte estraendone il pool. Rifiuta se le posizioni non sono ancora assegnate. Idempotente.';

revoke all on function private.apri_finestra_scelte(bigint, smallint, text) from public, anon, authenticated;
grant execute on function private.apri_finestra_scelte(bigint, smallint, text) to service_role;

-- ------------------------------------------------------------
--  Chiusura, con la condizione d'ingresso che mancava
--
--  Unica differenza rispetto a 20260828140000: il controllo sul pool in
--  testa alla funzione. Se il pool non esiste, la finestra non e' mai
--  stata aperta e non c'e' nulla da risolvere — quindi si alza un errore
--  invece di marcare tutto 'vuota'.
--
--  Il resto e' identico, incluso il comportamento confermato dall'utente:
--  una preferenza che non entra sotto il tetto, o che non trova posto in
--  rosa, viene saltata e si passa alla successiva.
-- ------------------------------------------------------------

create or replace function private.risolvi_finestra_scelte(
  p_league_id bigint,
  p_stagione  smallint,
  p_finestra  text
)
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_scelta     record;
  v_pref       record;
  v_assegnate  integer := 0;
  v_player_id  bigint;
  v_ingaggio   bigint;
  v_istanza    bigint;
  v_nome       text;
  v_righe      integer;
begin
  if p_finestra not in ('on', 'off') then
    raise exception using errcode = '22023', message = 'Finestra sconosciuta: ' || p_finestra;
  end if;

  -- Condizione d'ingresso: la finestra dev'essere stata aperta.
  if not exists (
    select 1 from public.scelte_pool
    where league_id = p_league_id and stagione = p_stagione and finestra = p_finestra
  ) then
    raise exception using errcode = '55000',
      message = 'Questa finestra non e'' mai stata aperta: nessun pool estratto, '
                || 'non c''e'' nulla da risolvere.';
  end if;

  for v_scelta in
    select sd.*
    from public.scelte_draft sd
    where sd.league_id = p_league_id
      and sd.stagione  = p_stagione
      and sd.finestra  = p_finestra
      and sd.stato     = 'determinata'
    order by sd.posizione
    for update
  loop
    v_player_id := null;

    -- prima preferenza ancora disponibile che la squadra puo' permettersi
    for v_pref in
      select pr.player_id, sp.ingaggio_teorico
      from public.scelte_preferenze pr
      join public.scelte_pool sp
        on sp.league_id = p_league_id and sp.stagione = p_stagione
       and sp.finestra = p_finestra and sp.player_id = pr.player_id
      where pr.scelta_id = v_scelta.id
      order by pr.ordine
    loop
      -- gia' preso da chi ha scelto prima, in questa finestra o altrove?
      if exists (
        select 1 from public.player_instances pi
        where pi.league_id = p_league_id and pi.player_id = v_pref.player_id
          and pi.team_id is not null
      ) then
        continue;
      end if;

      if (select count(*) from public.player_instances pi
          where pi.team_id = v_scelta.team_proprietario_id) >= private.rosa_massima() then
        exit;  -- rosa piena: nessuna preferenza potra' entrare
      end if;

      if private.capienza_residua(v_scelta.team_proprietario_id, p_stagione, null)
         < v_pref.ingaggio_teorico then
        continue;  -- non ci sta sotto il tetto: prova la prossima
      end if;

      v_player_id := v_pref.player_id;
      v_ingaggio  := v_pref.ingaggio_teorico;
      exit;
    end loop;

    if v_player_id is null then
      update public.scelte_draft set stato = 'vuota', aggiornata_il = now()
      where id = v_scelta.id;
      continue;
    end if;

    select p.nome into v_nome from public.players p where p.id = v_player_id;

    insert into public.player_instances as pi
      (league_id, player_id, team_id, overall_corrente, eta_corrente, ingaggio, contratto_scadenza)
    select p_league_id, p.id, v_scelta.team_proprietario_id, p.overall, p.eta,
           v_ingaggio, p_stagione
    from public.players p where p.id = v_player_id
    on conflict (league_id, player_id) do update
      set team_id = excluded.team_id,
          ingaggio = excluded.ingaggio,
          contratto_scadenza = excluded.contratto_scadenza
      where pi.team_id is null
    returning pi.id into v_istanza;

    get diagnostics v_righe = row_count;
    if v_righe <> 1 then
      -- qualcuno se l'e' preso nel frattempo: questa scelta resta vuota,
      -- non fa fallire l'intera finestra.
      update public.scelte_draft set stato = 'vuota', aggiornata_il = now()
      where id = v_scelta.id;
      continue;
    end if;

    update public.scelte_draft
    set stato = 'usata', player_instance_id = v_istanza, aggiornata_il = now()
    where id = v_scelta.id;

    insert into public.transactions
      (league_id, team_id, tipo, importo, descrizione, saldo_dopo)
    select p_league_id, v_scelta.team_proprietario_id, 'scelta_draft', -v_ingaggio,
           'Scelta ' || v_scelta.posizione || 'ª (' || p_finestra || '-Season '
             || p_stagione || '): ' || coalesce(v_nome, 'giocatore'),
           (select budget from public.teams where id = v_scelta.team_proprietario_id);

    perform private.notifica(
      (select user_id from public.teams where id = v_scelta.team_proprietario_id),
      -- 'mercato_esito' e non un tipo nuovo: notifications_tipo_check
      -- ammette solo sette valori.
      p_league_id, 'mercato_esito',
      'Scelta esercitata: ' || coalesce(v_nome, 'giocatore'),
      'Entra in rosa con un contratto di una stagione a '
        || private.in_milioni(v_ingaggio) || ' M€.',
      jsonb_build_object('scelta_id', v_scelta.id)
    );

    v_assegnate := v_assegnate + 1;
  end loop;

  return v_assegnate;
end;
$$;

comment on function private.risolvi_finestra_scelte(bigint, smallint, text) is
  'Risolve una finestra del mercato a scelte. Rifiuta se la finestra non e'' mai stata aperta. Nessun ripiego automatico: chi esaurisce la lista resta a mani vuote (docs/decisioni-draft-picks.md §4).';

revoke all on function private.risolvi_finestra_scelte(bigint, smallint, text) from public, anon, authenticated;
grant execute on function private.risolvi_finestra_scelte(bigint, smallint, text) to service_role;
