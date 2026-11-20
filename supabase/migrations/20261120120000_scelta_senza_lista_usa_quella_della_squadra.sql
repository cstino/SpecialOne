-- Draft a scelte: una scelta senza lista propria usa quella che la squadra ha salvato per le altre scelte della
-- stessa finestra, tagliata alla sua posizione. Caso: The Orange Plague, scelta n.1 presa con uno scambio l'11/11
-- dopo aver salvato la lista il 9/11; l'app mostrava la lista unica, sul server la n.1 era vuota (20/11/2026).

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
  v_lista      bigint;
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

  -- Una lista sola per tutte le scelte di una squadra nella stessa finestra (20/11/2026): se questa scelta non ha
  -- una lista sua (per esempio e' arrivata con uno scambio dopo il salvataggio) usa la piu' lunga salvata dalla
  -- squadra per le altre scelte della finestra, tagliata alla sua posizione come fa l'app quando salva.
  v_lista := v_scelta.id;
  if not exists (select 1 from public.scelte_preferenze where scelta_id = v_scelta.id) then
    select sd.id into v_lista
    from public.scelte_draft sd
    join public.scelte_preferenze pr on pr.scelta_id = sd.id
    where sd.league_id = v_scelta.league_id and sd.stagione = v_scelta.stagione and sd.finestra = v_scelta.finestra
      and sd.team_proprietario_id = v_scelta.team_proprietario_id and sd.id <> v_scelta.id
    group by sd.id
    order by count(*) desc, sd.id
    limit 1;
  end if;

  for v_pref in
    select pr.player_id, sp.ingaggio_teorico
    from public.scelte_preferenze pr
    join public.scelte_pool sp
      on sp.league_id = v_scelta.league_id and sp.stagione = v_scelta.stagione
     and sp.finestra = v_scelta.finestra and sp.player_id = pr.player_id
    where pr.scelta_id = v_lista
      and (v_lista = v_scelta.id or pr.ordine <= coalesce(v_scelta.posizione, 32767))
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
$function$

;
