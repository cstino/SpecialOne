-- ============================================================
--  RINNOVO CONTRATTUALE A STAGIONE IN CORSO (design §10.4 bis)
--
--  Richiesta dell'utente, 5 agosto 2026: finora un contratto si poteva
--  rinnovare solo in off-season (public.rispondi_rinnovo, legata a
--  contract_renewals.offseason_id NOT NULL). Ora si puo' anche a stagione
--  in corso, dalla scheda giocatore.
--
--  Differenze volute rispetto al rinnovo di off-season:
--
--  1. E' il GIOCATORE a proporre, non la squadra a offrire: una cifra secca
--     e una durata, da prendere o lasciare. Niente range ±12% ne' soglia di
--     accettazione al 90% — quella meccanica esiste perche' in off-season il
--     contratto e' SCADUTO e la squadra ha leva. Qui il contratto e' ancora
--     in corso: la leva ce l'ha il giocatore, quindi non si tratta.
--
--  2. La proposta e' DETERMINISTICA su (istanza, overall, eta, ingaggio):
--     riaprire la scheda mostra sempre la stessa cifra. Senza questo, con
--     un random() vero basterebbe chiudere e riaprire finche' non esce un
--     numero comodo. Cambia solo quando cambia il giocatore — cioe' ai
--     checkpoint di progressione del 25% (§10.2) o dopo un altro rinnovo.
--     Per questo non serve nessuna tabella di stato: la proposta si
--     ricalcola identica ogni volta, e rinnovare scrive direttamente su
--     player_instances.
--
--  3. Il nuovo ingaggio decorre dalle stagioni SUCCESSIVE: quella corrente
--     e' gia' stata addebitata per intero a inizio stagione (§5.4), quindi
--     rinnovare oggi non muove denaro oggi. Il costo e' l'impegno futuro.
--     player_instances.ingaggio viene comunque aggiornato subito, cosi' il
--     monte ingaggi mostrato riflette quello che si pagera'.
--
--  4. Chi ha annunciato il ritiro non rinnova (§10.3): sta per smettere.
-- ============================================================

-- ------------------------------------------------------------
--  Proposta del giocatore: cifra + durata, entrambe deterministiche.
--  hashtext() al posto di random(): stabile a parita' di input, e diverso
--  fra ingaggio e durata (stringhe seminate diverse) per non correlarle.
-- ------------------------------------------------------------

create or replace function private.rinnovo_proposta(
  p_instance_id bigint,
  p_overall smallint,
  p_eta smallint,
  p_ingaggio bigint
) returns table (richiesta bigint, durata smallint)
language sql
stable
parallel safe
set search_path = ''
as $$
  with seme as (
    select
      (abs(hashtext('ing:' || p_instance_id || ':' || p_overall || ':' || p_eta || ':' || p_ingaggio)) % 1000) / 1000.0 as r_ing,
      (abs(hashtext('dur:' || p_instance_id || ':' || p_overall || ':' || p_eta || ':' || p_ingaggio)) % 1000) / 1000.0 as r_dur
  )
  select
    -- Pavimento all'ingaggio attuale, come il rinnovo di off-season (§10.4):
    -- nessuno chiede meno di quanto sta gia' percependo. Sopra il pavimento,
    -- una maggiorazione dello 0-12%: e' il giocatore ad avere la leva.
    greatest(
      500000::bigint,
      p_ingaggio,
      (round(private.ingaggio_teorico(p_overall, p_eta) * (1.00 + seme.r_ing * 0.12) / 100000) * 100000)::bigint
    ) as richiesta,
    -- Durata coerente con l'eta': a 36 anni nessuno chiede quattro stagioni.
    (case
      when p_eta <= 23 then 4
      when p_eta <= 29 then 3 + (case when seme.r_dur < 0.5 then 0 else 1 end)
      when p_eta <= 31 then 2 + (case when seme.r_dur < 0.5 then 0 else 1 end)
      when p_eta <= 33 then 2
      when p_eta <= 35 then 1 + (case when seme.r_dur < 0.5 then 0 else 1 end)
      else 1
    end)::smallint as durata
  from seme;
$$;

revoke all on function private.rinnovo_proposta(bigint, smallint, smallint, bigint)
  from public, anon, authenticated;
grant execute on function private.rinnovo_proposta(bigint, smallint, smallint, bigint)
  to service_role;

-- ------------------------------------------------------------
--  Lettura della proposta: quello che la scheda giocatore mostra.
-- ------------------------------------------------------------

create or replace function public.proposta_rinnovo(p_instance_id bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_inst public.player_instances;
  v_league public.leagues;
  v_team public.teams;
  v_proposta record;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'Devi accedere prima di trattare un rinnovo.';
  end if;

  select * into v_inst from public.player_instances where id = p_instance_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Giocatore non trovato.';
  end if;

  select * into v_team from public.teams
  where id = v_inst.team_id and league_id = v_inst.league_id and user_id = v_user_id;
  if not found then
    raise exception using errcode = '42501', message = 'Questo giocatore non e'' nella tua rosa.';
  end if;

  select * into v_league from public.leagues where id = v_inst.league_id;
  if v_league.stato <> 'stagione' then
    raise exception using errcode = '55000', message = 'I rinnovi a stagione in corso si trattano solo a stagione avviata.';
  end if;
  if v_inst.ritirato or v_inst.ritiro_annunciato then
    raise exception using errcode = '55000', message = 'Ha gia'' annunciato il ritiro: non rinnovera'' il contratto.';
  end if;

  select * into v_proposta
  from private.rinnovo_proposta(v_inst.id, v_inst.overall_corrente, v_inst.eta_corrente, v_inst.ingaggio);

  return jsonb_build_object(
    'player_instance_id', v_inst.id,
    'ingaggio_attuale', v_inst.ingaggio,
    'scadenza_attuale', v_inst.contratto_scadenza,
    'stagione_corrente', v_league.stagione_corrente,
    'richiesta', v_proposta.richiesta,
    'durata', v_proposta.durata,
    'nuova_scadenza', greatest(v_inst.contratto_scadenza, (v_league.stagione_corrente + v_proposta.durata)::smallint)
  );
end;
$$;

revoke all on function public.proposta_rinnovo(bigint) from public, anon;
grant execute on function public.proposta_rinnovo(bigint) to authenticated;

comment on function public.proposta_rinnovo(bigint) is
  'Proposta di rinnovo del giocatore a stagione in corso: cifra e durata, deterministiche su (istanza, overall, eta, ingaggio).';

-- ------------------------------------------------------------
--  Accettazione: la proposta viene RICALCOLATA lato server e confrontata
--  con quella arrivata dal client. Il browser non decide mai la cifra.
-- ------------------------------------------------------------

create or replace function public.accetta_rinnovo_stagione(
  p_instance_id bigint,
  p_ingaggio bigint,
  p_durata smallint
) returns jsonb
language plpgsql
volatile
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
  v_scadenza smallint;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'Devi accedere prima di firmare un rinnovo.';
  end if;

  select * into v_inst from public.player_instances where id = p_instance_id for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Giocatore non trovato.';
  end if;

  select * into v_team from public.teams
  where id = v_inst.team_id and league_id = v_inst.league_id and user_id = v_user_id and attiva;
  if not found then
    raise exception using errcode = '42501', message = 'Questo giocatore non e'' nella tua rosa.';
  end if;

  select * into v_league from public.leagues where id = v_inst.league_id;
  if v_league.stato <> 'stagione' then
    raise exception using errcode = '55000', message = 'I rinnovi a stagione in corso si firmano solo a stagione avviata.';
  end if;
  if v_inst.ritirato or v_inst.ritiro_annunciato then
    raise exception using errcode = '55000', message = 'Ha gia'' annunciato il ritiro: non rinnovera'' il contratto.';
  end if;

  select * into v_proposta
  from private.rinnovo_proposta(v_inst.id, v_inst.overall_corrente, v_inst.eta_corrente, v_inst.ingaggio);

  -- La proposta e' secca: si accetta quella, non una versione ritoccata.
  if p_ingaggio <> v_proposta.richiesta or p_durata <> v_proposta.durata then
    raise exception using errcode = '22023',
      message = 'La proposta e'' cambiata: riapri la scheda del giocatore.';
  end if;

  v_scadenza := greatest(v_inst.contratto_scadenza, (v_league.stagione_corrente + v_proposta.durata)::smallint);

  update public.player_instances
  set ingaggio = v_proposta.richiesta,
      contratto_scadenza = v_scadenza
  where id = v_inst.id;

  -- Registro append-only: nessun euro si muove ora (la stagione corrente e'
  -- gia' stata addebitata, §5.4), ma l'impegno futuro va tracciato o il primo
  -- monte ingaggi che non torna diventa impossibile da ricostruire.
  select * into v_player from public.players where id = v_inst.player_id;
  insert into public.transactions (league_id, team_id, tipo, importo, descrizione, saldo_dopo)
  values (
    v_inst.league_id, v_team.id, 'rinnovo_in_stagione',
    -- importo <> 0 e' un CHECK della tabella: si registra la variazione di
    -- ingaggio annuo, che e' l'informazione utile (0 se non cambia nulla
    -- non e' un caso possibile: la richiesta ha per pavimento l'attuale e
    -- il rinnovo a parita' di cifra resta comunque un impegno piu' lungo).
    greatest(1, v_proposta.richiesta - v_inst.ingaggio),
    'Rinnovo in stagione: ' || coalesce(v_player.nome, 'giocatore')
      || ' — ' || (v_proposta.richiesta / 1000000.0) || ' M€ fino alla stagione ' || v_scadenza,
    v_team.budget
  );

  return jsonb_build_object(
    'player_instance_id', v_inst.id,
    'ingaggio', v_proposta.richiesta,
    'durata', v_proposta.durata,
    'contratto_scadenza', v_scadenza
  );
end;
$$;

revoke all on function public.accetta_rinnovo_stagione(bigint, bigint, smallint) from public, anon;
grant execute on function public.accetta_rinnovo_stagione(bigint, bigint, smallint) to authenticated;

comment on function public.accetta_rinnovo_stagione(bigint, bigint, smallint) is
  'Firma il rinnovo proposto dal giocatore a stagione in corso: aggiorna ingaggio e contratto_scadenza. La proposta e'' ricalcolata server-side.';
