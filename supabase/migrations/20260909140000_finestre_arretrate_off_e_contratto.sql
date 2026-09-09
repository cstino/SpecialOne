-- ============================================================
--  SEGUITO DI 20260909130000: due tasselli mancanti.
--
--  1. Chiudere una finestra ON arretrata non bastava: la catena che apre la
--     OFF della stessa stagione vive nell'altro ciclo, che filtra
--     "risolta_il is null" e quindi non la vedeva piu'. La OFF non sarebbe
--     mai stata aperta. Ora la si apre nello stesso punto, con scadenza a
--     due giorni: la finestra e' in ritardo, ma i partecipanti devono
--     comunque avere il tempo di comporre la lista.
--
--  2. risolvi_finestra_scelte scriveva contratto_scadenza = p_stagione.
--     Giusto quando la finestra si risolve nella sua stagione; sbagliato
--     quando si risolve in ritardo, a stagione gia' voltata: il giocatore
--     entrerebbe in rosa con un contratto GIA' SCADUTO — fuori dal monte
--     ingaggi (private.monte_ingaggi filtra contratto_scadenza >= stagione)
--     e da rinnovare all'istante. Ora si prende la piu' avanti fra la
--     stagione della finestra e quella corrente della lega.
--
--  Entrambe ottenute per sostituzione mirata sul testo live: il diff mostra
--  una sola riga rimossa, quella dell'insert.
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
      -- Stessa catena del percorso normale: chiusa la ON si apre la OFF.
      -- Qui pero' la scadenza naturale (offseason_fine) non esiste piu',
      -- quindi si fissa a due giorni: la finestra e' in ritardo, ma i
      -- partecipanti devono comunque avere il tempo di comporre la lista.
      if v_finestra.finestra = 'on' and not exists (
        select 1 from public.finestre_scelte
        where league_id = v_finestra.league_id and stagione = v_finestra.stagione and finestra = 'off'
      ) then
        perform private.svela_finestra_scelte(
          v_finestra.league_id, v_finestra.stagione, 'off', now() + interval '2 days');
      end if;
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

CREATE OR REPLACE FUNCTION private.risolvi_finestra_scelte(p_league_id bigint, p_stagione smallint, p_finestra text, p_forza boolean DEFAULT false)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
  v_scadenza   smallint;
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

  -- Il contratto scade a fine della stagione della finestra. Se pero' la
  -- finestra viene risolta in ritardo, a stagione gia' voltata, quella
  -- scadenza sarebbe gia' passata: il giocatore entrerebbe in rosa con un
  -- contratto scaduto, fuori dal monte ingaggi e da rinnovare subito.
  -- Si prende quindi la piu' avanti fra le due.
  select greatest(p_stagione, l.stagione_corrente) into v_scadenza
  from public.leagues l where l.id = p_league_id;

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
           v_ingaggio, v_scadenza, v_prossima
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
           0;

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
$function$
;

commit;
