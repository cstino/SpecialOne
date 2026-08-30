begin;

-- ============================================================
--  Risoluzione aste e finestre a scelte: l'upsert su player_instances
--  gia' preservava correttamente l'overall di un'istanza orfana
--  ri-firmata (non lo tocca nel DO UPDATE SET), ma il ramo di inserimento
--  per un giocatore mai visto in questa lega leggeva l'overall statico
--  del catalogo invece del pool tracciato.
-- ============================================================

create or replace function private.risolvi_aste_giorno(p_giorno date, p_league_id bigint default null)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_asta              record;
  v_soglia            bigint;
  v_vincitore         record;
  v_stagione          smallint;
  v_prossima          integer;
  v_nome              text;
  v_assegnate         integer := 0;
  v_istanze_assegnate integer;
  v_off               record;
begin
  for v_asta in
    select a.* from public.free_agent_auctions a
    where a.giorno = p_giorno and a.stato = 'aperta'
      and (p_league_id is null or a.league_id = p_league_id)
    order by a.id
    for update
  loop
    v_stagione := private.stagione_contratto(v_asta.league_id);
    select min(f.giornata) into v_prossima
    from public.fixtures f where f.league_id = v_asta.league_id and f.stato = 'programmata';
    select soglia into v_soglia from private.auction_thresholds where auction_id = v_asta.id;
    select p.nome into v_nome from public.players p where p.id = v_asta.player_id;

    v_vincitore := null;

    select b.* into v_vincitore
    from public.free_agent_bids b
    join public.teams t on t.id = b.team_id
    where b.auction_id = v_asta.id
      and b.ingaggio_offerto >= v_soglia
      and (select count(*) from public.player_instances pi where pi.team_id = b.team_id)
          < private.rosa_massima()
      and private.capienza_residua(b.team_id, v_stagione, v_asta.id) >= b.ingaggio_offerto
    order by b.ingaggio_offerto desc, b.aggiornata_il asc, b.id asc
    limit 1;

    if v_vincitore.id is null then
      update public.free_agent_auctions
      set stato = 'deserta', risolta_il = now()
      where id = v_asta.id;
    else
      -- Un giocatore svincolato conserva la propria istanza di lega: un
      -- insert semplice urterebbe unique(league_id, player_id). L'upsert
      -- riusa l'istanza solo se e' ancora libera; se nel frattempo e'
      -- stata assegnata altrove, questa sola asta fallisce senza segnarsi
      -- come conclusa (non l'intera risoluzione). L'overall/eta nel
      -- ramo insert vengono dal pool tracciato se il giocatore non e'
      -- mai stato scelto in questa lega; se invece esisteva gia'
      -- un'istanza (orfana, ri-firmata ora), l'upsert non tocca
      -- overall_corrente/eta_corrente: quelli maturati restano.
      insert into public.player_instances as pi
        (league_id, player_id, team_id, overall_corrente, eta_corrente, ingaggio, contratto_scadenza, giornata_acquisizione)
      select v_asta.league_id, p.id, v_vincitore.team_id,
             coalesce(fap.overall_corrente, p.overall), coalesce(fap.eta_corrente, p.eta),
             v_vincitore.ingaggio_offerto, v_stagione, v_prossima
      from public.players p
      left join public.free_agent_progression fap
        on fap.league_id = v_asta.league_id and fap.player_id = p.id
      where p.id = v_asta.player_id
      on conflict (league_id, player_id) do update
        set team_id = excluded.team_id,
            ingaggio = excluded.ingaggio,
            contratto_scadenza = excluded.contratto_scadenza,
            giornata_acquisizione = excluded.giornata_acquisizione
        where pi.team_id is null;
      get diagnostics v_istanze_assegnate = row_count;

      if v_istanze_assegnate <> 1 then
        raise exception using errcode = '55000',
          message = 'Il giocatore non e'' piu'' disponibile per questa asta.';
      end if;

      delete from public.free_agent_progression
      where league_id = v_asta.league_id and player_id = v_asta.player_id;

      insert into public.transactions
        (league_id, team_id, tipo, importo, descrizione, saldo_dopo)
      select v_asta.league_id, v_vincitore.team_id, 'asta_svincolato',
             -v_vincitore.ingaggio_offerto,
             'Asta vinta: ' || v_nome || ' — ' ||
             private.in_milioni(v_vincitore.ingaggio_offerto) ||
             ' M€ di ingaggio fino alla stagione ' || v_stagione,
             (select budget from public.teams where id = v_vincitore.team_id);

      update public.free_agent_auctions
      set stato = 'assegnata', vincitore_team_id = v_vincitore.team_id,
          ingaggio_finale = v_vincitore.ingaggio_offerto, risolta_il = now()
      where id = v_asta.id;

      v_assegnate := v_assegnate + 1;
    end if;

    for v_off in
      select b.team_id, t.user_id from public.free_agent_bids b
      join public.teams t on t.id = b.team_id
      where b.auction_id = v_asta.id
    loop
      perform private.notifica(
        v_off.user_id, v_asta.league_id, 'mercato_asta',
        case when v_vincitore.id is not null and v_off.team_id = v_vincitore.team_id
             then 'Asta vinta: ' || v_nome
             else 'Asta persa: ' || v_nome end,
        case
          when v_vincitore.id is null then 'Nessuna offerta ha raggiunto la richiesta del giocatore.'
          when v_off.team_id = v_vincitore.team_id then 'Entra in rosa con un contratto di una stagione.'
          else 'Se l''e'' aggiudicato ' ||
               (select nome from public.teams where id = v_vincitore.team_id) ||
               ' per ' || private.in_milioni(v_vincitore.ingaggio_offerto) || ' M€.'
        end,
        jsonb_build_object('asta_id', v_asta.id)
      );
    end loop;
  end loop;

  return v_assegnate;
end;
$$;

-- ------------------------------------------------------------
--  estrai_pool_scelte: il pool di una finestra ON/OFF-Season leggeva
--  l'overall statico del catalogo per calcolare l'ingaggio teorico dei
--  23 giocatori estratti. Ora preferisce il pool tracciato.
-- ------------------------------------------------------------

create or replace function private.estrai_pool_scelte(
  p_league_id bigint,
  p_stagione smallint,
  p_finestra text
)
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_lega public.leagues;
  v_creati integer := 0;
begin
  if p_finestra not in ('on', 'off') then
    raise exception using errcode = '22023', message = 'Finestra non valida.';
  end if;
  select * into v_lega from public.leagues where id = p_league_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Lega non trovata.';
  end if;
  if exists (select 1 from public.scelte_pool where league_id = p_league_id and stagione = p_stagione and finestra = p_finestra) then
    return 0;
  end if;

  with disponibili as (
    select p.id, private.macro_ruolo(p.posizioni) as macro,
           coalesce(fap.overall_corrente, p.overall) as overall_attuale,
           coalesce(fap.eta_corrente, p.eta) as eta_attuale
    from public.players p
    left join public.free_agent_progression fap
      on fap.league_id = p_league_id and fap.player_id = p.id
    where p.disponibile_estrazione
      and coalesce(fap.overall_corrente, p.overall) > 75
      and (p.elite_globale or p.campionato = any(v_lega.campionati_attivi))
      and private.macro_ruolo(p.posizioni) in ('GK', 'DEF', 'MID', 'ATT')
      and not exists (
        select 1 from public.player_instances pi
        where pi.league_id = p_league_id and pi.player_id = p.id
      )
      and not exists (
        select 1 from public.retired_players rp
        where rp.league_id = p_league_id and rp.player_id = p.id
      )
  ), ranked as (
    select id, macro, overall_attuale, eta_attuale,
           row_number() over (partition by macro order by random()) as rn
    from disponibili
  ), scelti as (
    select id, overall_attuale, eta_attuale from ranked
    where (macro = 'GK' and rn <= 5) or (macro <> 'GK' and rn <= 6)
  )
  insert into public.scelte_pool (league_id, stagione, finestra, player_id, ingaggio_teorico)
  select p_league_id, p_stagione, p_finestra, s.id, private.ingaggio_teorico(s.overall_attuale, s.eta_attuale)
  from scelti s;

  get diagnostics v_creati = row_count;
  return v_creati;
end;
$$;

comment on function private.estrai_pool_scelte(bigint, smallint, text) is
  '5 portieri e 6 per ciascun altro ruolo (overall>75 nel pool tracciato o nel catalogo, liberi) per il pool di una finestra ON/OFF-Season: 23 totali. Idempotente: non ritocca una finestra gia'' estratta.';

-- ------------------------------------------------------------
--  risolvi_finestra_scelte: stessa correzione dell'asta — l'upsert gia'
--  preservava l'overall di un'istanza orfana, mancava solo la lettura
--  dal pool tracciato per chi non e' mai stato scelto.
-- ------------------------------------------------------------

create or replace function private.risolvi_finestra_scelte(p_league_id bigint, p_stagione smallint, p_finestra text, p_forza boolean default false)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_finestra   public.finestre_scelte;
  v_scelta     record;
  v_pref       record;
  v_assegnate  integer := 0;
  v_player_id  bigint;
  v_ingaggio   bigint;
  v_istanza    bigint;
  v_nome       text;
  v_righe      integer;
  v_prossima   integer;
begin
  select * into v_finestra from public.finestre_scelte
  where league_id = p_league_id and stagione = p_stagione and finestra = p_finestra
  for update;
  if not found then
    raise exception using errcode = '55000',
      message = 'Questa finestra non e'' mai stata svelata: non c''e'' nulla da risolvere.';
  end if;
  if v_finestra.risolta_il is not null then
    return 0;
  end if;

  -- Istante ignoto: la finestra non e' ancora arrivata a scadenza perche'
  -- una scadenza non ce l'ha. Vale anche con p_forza: forzare l'orario di
  -- un'estrazione che non e' stata fissata non significa niente.
  if v_finestra.estrazione_il is null then
    raise exception using errcode = '55000',
      message = 'L''istante di estrazione di questa finestra non e'' ancora fissato'
                || case when p_finestra = 'off'
                        then ': dipende dalla scadenza dell''off-season, che non e'' ancora stata impostata.'
                        else '.' end;
  end if;

  if not p_forza and now() < v_finestra.estrazione_il then
    raise exception using errcode = '55000',
      message = 'L''estrazione di questa finestra e'' fissata per il '
                || to_char(v_finestra.estrazione_il at time zone 'Europe/Rome', 'DD/MM/YYYY HH24:MI')
                || ': risolvere adesso taglierebbe fuori chi sta ancora componendo la lista.';
  end if;

  select min(f.giornata) into v_prossima
  from public.fixtures f where f.league_id = p_league_id and f.stato = 'programmata';

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

    for v_pref in
      select pr.player_id, sp.ingaggio_teorico
      from public.scelte_preferenze pr
      join public.scelte_pool sp
        on sp.league_id = p_league_id and sp.stagione = p_stagione
       and sp.finestra = p_finestra and sp.player_id = pr.player_id
      where pr.scelta_id = v_scelta.id
      order by pr.ordine
    loop
      if exists (
        select 1 from public.player_instances pi
        where pi.league_id = p_league_id and pi.player_id = v_pref.player_id
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
      if private.capienza_residua(v_scelta.team_proprietario_id, p_stagione, null)
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
      continue;
    end if;

    select p.nome into v_nome from public.players p where p.id = v_player_id;

    insert into public.player_instances as pi
      (league_id, player_id, team_id, overall_corrente, eta_corrente, ingaggio, contratto_scadenza, giornata_acquisizione)
    select p_league_id, p.id, v_scelta.team_proprietario_id,
           coalesce(fap.overall_corrente, p.overall), coalesce(fap.eta_corrente, p.eta),
           v_ingaggio, p_stagione, v_prossima
    from public.players p
    left join public.free_agent_progression fap
      on fap.league_id = p_league_id and fap.player_id = p.id
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
      update public.scelte_draft set stato = 'vuota', aggiornata_il = now()
      where id = v_scelta.id;
      continue;
    end if;

    delete from public.free_agent_progression
    where league_id = p_league_id and player_id = v_player_id;

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
      p_league_id, 'mercato_esito',
      'Scelta esercitata: ' || coalesce(v_nome, 'giocatore'),
      'Entra in rosa con un contratto di una stagione a '
        || private.in_milioni(v_ingaggio) || ' M€.',
      jsonb_build_object('scelta_id', v_scelta.id)
    );

    v_assegnate := v_assegnate + 1;
  end loop;

  update public.finestre_scelte set risolta_il = now()
  where league_id = p_league_id and stagione = p_stagione and finestra = p_finestra;

  return v_assegnate;
end;
$$;

commit;
