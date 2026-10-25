-- Notifiche: un testo troppo lungo non deve mai far fallire l'operazione che la manda (25/10/2026). Lo svincolo di Paulo
-- Oliveira (BackDoor Invaders) falliva con "notifications_corpo_check": il corpo arrivava a 244 caratteri (limite 240)
-- quando il giocatore era in formazione e si aggiungeva la nota sul sostituto.
-- 1) private.notifica taglia titolo (80) e corpo (240) con i puntini, per tutte le notifiche;
-- 2) il testo dello svincolo e' piu' corto. Funzioni riscritte dalla definizione viva.

CREATE OR REPLACE FUNCTION private.notifica(p_user_id uuid, p_league_id bigint, p_tipo text, p_titolo text, p_corpo text DEFAULT NULL::text, p_dati jsonb DEFAULT '{}'::jsonb)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_id bigint;
begin
  if p_user_id is null then
    return null;
  end if;

  insert into public.notifications (user_id, league_id, tipo, titolo, corpo, dati)
  values (
    p_user_id, p_league_id, p_tipo,
    -- testi oltre i limiti della tabella: si tagliano con i puntini invece di far fallire chi chiama
    case when char_length(btrim(p_titolo)) > 80 then left(btrim(p_titolo), 79) || '…' else btrim(p_titolo) end,
    case when char_length(btrim(coalesce(p_corpo, ''))) > 240 then left(btrim(p_corpo), 239) || '…'
         else nullif(btrim(coalesce(p_corpo, '')), '') end,
    coalesce(p_dati, '{}'::jsonb)
  )
  returning id into v_id;
  return v_id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.svincola_giocatore_cassa_legacy(p_instance_id bigint)
 RETURNS player_instances
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_utente uuid := (select auth.uid());
  v_istanza public.player_instances;
  v_squadra public.teams;
  v_lega public.leagues;
  v_giocatore public.players;
  v_rosa integer;
  v_portieri integer;
  v_prossima integer;
  v_giornate_trascorse integer;
  v_formazione public.lineups;
  v_indice integer;
  v_slot text;
  v_sostituto bigint;
  v_formazioni_aggiornate integer := 0;
  v_nota text := '';
begin
  if v_utente is null then
    raise exception using errcode = '42501', message = 'Devi accedere per svincolare un giocatore.';
  end if;

  select * into v_istanza from public.player_instances where id = p_instance_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Giocatore inesistente.';
  end if;

  select * into v_squadra from public.teams where id = v_istanza.team_id and user_id = v_utente;
  if not found then
    raise exception using errcode = '42501', message = 'Questo giocatore non appartiene alla tua squadra.';
  end if;

  perform 1 from public.teams where id = v_squadra.id for update;
  select * into v_istanza from public.player_instances
  where id = p_instance_id and team_id = v_squadra.id for update;
  if not found then
    raise exception using errcode = '55000', message = 'Il giocatore non e'' piu'' nella tua rosa.';
  end if;

  select * into v_lega from public.leagues where id = v_istanza.league_id;
  if v_lega.stato <> 'stagione' then
    raise exception using errcode = '55000', message = 'Puoi svincolare giocatori solo durante la stagione.';
  end if;
  if not private.mercato_aperto_lega(v_lega.id) then
    raise exception using errcode = '55000', message = 'Il mercato e'' chiuso: puoi svincolare dalle 23:30 alle 21:00, o quando l''admin lo apre.';
  end if;

  select min(f.giornata) into v_prossima from public.fixtures f
  where f.league_id = v_lega.id and f.stato = 'programmata';

  -- Blocco svincolo su acquisti recenti (deciso il 29 agosto 2026): un
  -- giocatore preso via asta svincolati o scambio non puo' essere
  -- svincolato dalla stessa squadra prima di 10 giornate. NULL (draft, rose
  -- iniziali, offseason) non e' mai bloccato. coalesce su giornate_totali+1
  -- copre il caso limite di fine campionato senza altre giornate
  -- programmate, cosi' il conteggio non resta "in sospeso" a stagione finita.
  if v_istanza.giornata_acquisizione is not null then
    v_giornate_trascorse := coalesce(v_prossima,
        (select max(f.giornata) + 1 from public.fixtures f
           join public.seasons s on s.id = f.season_id
          where s.league_id = v_lega.id and s.numero = v_lega.stagione_corrente and f.stato = 'simulata'),
        v_lega.giornate_totali + 1) - v_istanza.giornata_acquisizione;
    if v_giornate_trascorse < 10 then
      raise exception using errcode = '22023',
        message = 'Questo giocatore e'' arrivato da meno di 10 giornate (mercato o scambio): non puoi ancora svincolarlo. Mancano ' ||
          (10 - v_giornate_trascorse) || ' giornate.';
    end if;
  end if;

  select count(*), count(*) filter (where p.posizioni[1] = 'GK') into v_rosa, v_portieri
  from public.player_instances pi join public.players p on p.id = pi.player_id
  where pi.team_id = v_squadra.id and pi.id <> v_istanza.id;
  if v_rosa < private.rosa_minima() then
    raise exception using errcode = '22023', message = 'Non puoi scendere sotto i 21 giocatori in rosa.';
  end if;
  if v_portieri < v_lega.portieri_minimi then
    raise exception using errcode = '22023', message = 'Non puoi scendere sotto il minimo di portieri della lega.';
  end if;

  -- Economia a tetto salariale (docs/decisioni-economia.md par 2 e par 4): lo
  -- svincolo libera spazio senza penalita' in contanti. Il vecchio addebito
  -- esisteva per impedire di firmare lungo e tagliare a piacere; con i
  -- contratti annuali quell'impegno non esiste piu'. Era anche una trappola
  -- concreta: le squadre col monte ingaggi piu' alto (quelle che piu'
  -- avevano bisogno di liberare spazio) erano spesso proprio quelle senza
  -- abbastanza cassa per pagarsela, e restavano bloccate.
  select * into v_giocatore from public.players where id = v_istanza.player_id;

  if v_prossima is not null then
    for v_formazione in
      select * from public.lineups
      where league_id = v_lega.id
        and team_id = v_squadra.id
        and giornata >= v_prossima
        and (titolari && array[v_istanza.id]::bigint[] or panchina && array[v_istanza.id]::bigint[] or tribuna && array[v_istanza.id]::bigint[])
      for update
    loop
      v_sostituto := null;
      v_indice := array_position(v_formazione.titolari, v_istanza.id);

      if v_indice is not null then
        v_slot := (case v_formazione.modulo
          when '4-3-3' then array['GK','LB','CB','CB','RB','CM','CM','CM','LW','ST','RW']
          when '4-3-3 offensivo' then array['GK','LB','CB','CB','RB','CM','CM','CAM','LW','ST','RW']
          when '4-3-3 difensivo' then array['GK','LB','CB','CB','RB','CM','CM','CDM','LW','ST','RW']
          when '4-4-2' then array['GK','LB','CB','CB','RB','LM','CM','CM','RM','ST','ST']
          when '4-2-3-1' then array['GK','LB','CB','CB','RB','CDM','CDM','CAM','LW','RW','ST']
          when '3-5-2' then array['GK','CB','CB','CB','LM','CM','CDM','CM','RM','ST','ST']
          when '3-4-3' then array['GK','CB','CB','CB','LM','CM','CM','RM','LW','ST','RW']
          when '5-3-2' then array['GK','LB','CB','CB','CB','RB','CM','CM','CM','ST','ST']
          when '4-2-4' then array['GK','LB','CB','CB','RB','CM','CM','LW','ST','ST','RW']
        end)[v_indice];

        select pi.id into v_sostituto
        from public.player_instances pi join public.players p on p.id = pi.player_id
        where pi.league_id = v_lega.id and pi.team_id = v_squadra.id and pi.id <> v_istanza.id
          and not (pi.id = any(v_formazione.titolari || coalesce(v_formazione.panchina, '{}'::bigint[])))
        order by
          case
            when v_slot = any(p.posizioni) then 0
            when v_slot in ('CB','LB','RB','LWB','RWB') and p.posizioni && array['CB','LB','RB','LWB','RWB']::text[] then 1
            when v_slot in ('CDM','CM','CAM','LM','RM') and p.posizioni && array['CDM','CM','CAM','LM','RM']::text[] then 1
            when v_slot in ('LW','RW','ST','CF') and p.posizioni && array['LW','RW','ST','CF']::text[] then 1
            when v_slot = 'GK' or p.posizioni && array['GK']::text[] then 3
            else 2
          end,
          case when pi.infortunato_fino_a <= 0 then 0 else 1 end,
          pi.overall_corrente desc, pi.id
        limit 1;

        update public.lineups
        set titolari = array_replace(titolari, v_istanza.id, v_sostituto),
            tribuna = array_remove(tribuna, v_sostituto)
        where id = v_formazione.id;
        v_formazioni_aggiornate := v_formazioni_aggiornate + 1;

      elsif array_position(v_formazione.panchina, v_istanza.id) is not null then
        select pi.id into v_sostituto
        from public.player_instances pi
        where pi.league_id = v_lega.id and pi.team_id = v_squadra.id and pi.id <> v_istanza.id
          and not (pi.id = any(v_formazione.titolari || coalesce(v_formazione.panchina, '{}'::bigint[])))
        order by case when pi.infortunato_fino_a <= 0 then 0 else 1 end, pi.overall_corrente desc, pi.id
        limit 1;

        update public.lineups
        set panchina = array_replace(panchina, v_istanza.id, v_sostituto),
            tribuna = array_remove(tribuna, v_sostituto)
        where id = v_formazione.id;
        v_formazioni_aggiornate := v_formazioni_aggiornate + 1;

      else
        update public.lineups set tribuna = array_remove(tribuna, v_istanza.id) where id = v_formazione.id;
      end if;
    end loop;
  end if;

  -- Dal 4 ottobre 2026 l'ingaggio resta a carico del club che svincola
  -- (peso_team_id) fino a scadenza del contratto o firma con un'altra squadra.
  -- Chi aveva gia' annunciato il ritiro chiude la carriera: nessun peso.
  update public.player_instances set team_id = null,
    ritirato = case when v_istanza.ritiro_annunciato then true else ritirato end,
    -- In off-season si svincola come prima: il peso vale dalla stagione nuova.
    peso_team_id = case when v_istanza.ritiro_annunciato then null
                        when v_lega.fase_carriera = 'offseason' then null
                        else v_squadra.id end
  where id = v_istanza.id returning * into v_istanza;
  if v_istanza.ritiro_annunciato then
    insert into public.retired_players(league_id, player_id, stagione)
    values (v_lega.id, v_istanza.player_id, v_lega.stagione_corrente) on conflict do nothing;
  else
    -- Entra subito nella coda dei rilasci (docs/decisioni-economia.md): se il
    -- mercato e' gia' aperto non puo' aggiungersi alla tornata in corso (chi
    -- ha gia' fatto offerte non lo saprebbe), quindi aspetta la prossima
    -- estrazione. Li' si aggiunge IN PIU' rispetto alle 5 (o 10) per ruolo
    -- gia' previste, non al loro posto: private.estrai_svincolati_lega lo
    -- consuma e lo inserisce nella stessa tornata, extra quota.
    insert into private.rilasci_in_coda(league_id, player_id)
    values (v_lega.id, v_istanza.player_id)
    on conflict (league_id, player_id) do nothing;
  end if;

  if v_formazioni_aggiornate > 0 then v_nota := ' Formazione aggiornata con un sostituto.'; end if;
  perform private.notifica(
    v_utente, v_lega.id, 'mercato_esito', 'Giocatore svincolato',
    v_giocatore.nome || (case
      when v_istanza.ritiro_annunciato then ' aveva gia'' annunciato il ritiro: la carriera termina qui, non torna disponibile.'
      else ' non è più nella tua rosa e torna tra gli svincolati. Il suo ingaggio resta sul tuo tetto finché il contratto non scade o un''altra squadra non lo prende.' end) || v_nota,
    jsonb_build_object('player_instance_id', v_istanza.id, 'player_id', v_istanza.player_id)
  );
  return v_istanza;
end;
$function$;

-- 3) Lo stesso taglio vale per QUALSIASI scrittura nella tabella (anche quelle dirette, come le notifiche che manda la
--    simulazione notturna): un nome lungo non deve mai far fallire una giornata.
create or replace function private.notifications_taglia_testi()
 returns trigger language plpgsql set search_path to ''
as $function$
begin
  if char_length(btrim(new.titolo)) > 80 then new.titolo := left(btrim(new.titolo), 79) || '…'; end if;
  if new.corpo is not null and char_length(new.corpo) > 240 then new.corpo := left(new.corpo, 239) || '…'; end if;
  return new;
end $function$;
drop trigger if exists notifications_taglia_testi on public.notifications;
create trigger notifications_taglia_testi before insert or update of titolo, corpo on public.notifications
  for each row execute function private.notifications_taglia_testi();
