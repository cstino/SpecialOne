-- Contratti pluriennali con opzione +1 (diario Season 3 §12, deciso col committente il 6/11/2026). Supera la regola
-- dei contratti annuali di docs/decisioni-economia.md §2 dalle stagioni indicate in leagues.contratti_pluriennali_dalla
-- (Serie F dalla 3, LegaBot dalla 6, leghe nuove dalla 1; Real Fampionato mai).
-- * Si rinnova solo nell'ultima stagione del contratto: da 1 a 3 stagioni fisse, piu' un'eventuale opzione +1 a favore
--   della squadra o del giocatore. Ingaggio fisso per tutta la durata.
-- * Prezzo: per ogni stagione oltre la prima il giocatore chiede di piu' se giovane con margine di crescita, di meno se
--   over 30; il morale alto fa sconto, quello basso fa chiedere di piu'; sotto 30 di morale firma solo per un anno.
--   Opzione squadra +8%, opzione giocatore -5% (private.moltiplicatore_durata).
-- * Tetto: si verifica ogni stagione coperta (resta un controllo esatto). L'anno dell'opzione del giocatore conta nel
--   monte; quello dell'opzione della squadra si verifica quando la squadra la esercita.
-- * Opzione squadra: la decide l'allenatore durante l'ultima stagione; non decisa all'ingresso in off-season =
--   rifiutata. Opzione giocatore: decisa in automatico all'ingresso in off-season (rinuncia se ora vale piu' del 10%
--   sopra il suo ingaggio o se ha il morale sotto 40). Rifiutata un'opzione, il contratto scade e si puo' rinnovare.
-- * Svincolo: l'ingaggio pesa per intero fino a fine della stagione dello svincolo, poi a meta' fino a scadenza.

alter table public.leagues add column if not exists contratti_pluriennali_dalla smallint not null default 1;
update public.leagues set contratti_pluriennali_dalla = 3 where id = 63;
update public.leagues set contratti_pluriennali_dalla = 6 where id = 62;
update public.leagues set contratti_pluriennali_dalla = 99 where id = 37;

alter table public.player_instances add column if not exists opzione_contratto text;
alter table public.player_instances drop constraint if exists player_instances_opzione_contratto_check;
alter table public.player_instances add constraint player_instances_opzione_contratto_check
  check (opzione_contratto is null or opzione_contratto in ('squadra', 'giocatore'));
alter table public.player_instances add column if not exists peso_stagione smallint;

create or replace function private.pluriennali_attivi(p_league_id bigint)
returns boolean
language sql
stable
set search_path to ''
as $$
  select coalesce((select l.stagione_corrente >= l.contratti_pluriennali_dalla from public.leagues l where l.id = p_league_id), false)
$$;

-- Moltiplicatore dell'ingaggio richiesto per durata e opzione.
create or replace function private.moltiplicatore_durata(p_eta smallint, p_overall smallint, p_potenziale smallint,
                                                         p_morale smallint, p_durata smallint, p_opzione text)
returns numeric
language sql
immutable parallel safe
set search_path to ''
as $$
  select round(greatest(0.75,
    (1 + (p_durata - 1) * (
      -- eta' e margine di crescita: il giovane che sa di crescere vuole essere pagato per gli anni in cui varra' di piu'
      -- (fino a 23 anni con 3+ punti di margine: +5% a stagione, +1% per ogni punto oltre i 3, al massimo +15%)
      case
        when p_eta <= 23 then case when coalesce(p_potenziale, p_overall) - p_overall >= 3
                                   then least(0.15, 0.05 + 0.01 * (coalesce(p_potenziale, p_overall) - p_overall - 3))
                                   else 0.02 end
        when p_eta <= 29 then least(0.03, 0.004 * greatest(0, coalesce(p_potenziale, p_overall) - p_overall))
        when p_eta <= 31 then -0.04
        else -0.08
      end
      -- morale: chi sta bene resta volentieri, chi e' scontento si fa pagare per restare
      + case when p_morale >= 70 then -0.03 when p_morale < 40 then 0.05 else 0 end
    ))
    * case p_opzione when 'squadra' then 1.08 when 'giocatore' then 0.95 else 1 end
  ), 4)
$$;

-- Quanto pesa sul tetto della stagione p_stagione un giocatore svincolato nella stagione p_peso_stagione: per intero
-- quella stagione, a meta' dalle successive (fino a scadenza, come prima).
create or replace function private.peso_svincolato(p_ingaggio bigint, p_peso_stagione smallint, p_stagione smallint)
returns bigint
language sql
immutable parallel safe
set search_path to ''
as $$
  select case when p_peso_stagione is null or p_stagione <= p_peso_stagione then p_ingaggio
              else round(p_ingaggio / 2.0)::bigint end
$$;

revoke all on function private.pluriennali_attivi(bigint) from public, anon;
revoke all on function private.moltiplicatore_durata(smallint, smallint, smallint, smallint, smallint, text) from public, anon;
revoke all on function private.peso_svincolato(bigint, smallint, smallint) from public, anon;
grant execute on function private.pluriennali_attivi(bigint) to authenticated, service_role;
grant execute on function private.moltiplicatore_durata(smallint, smallint, smallint, smallint, smallint, text) to authenticated, service_role;
grant execute on function private.peso_svincolato(bigint, smallint, smallint) to authenticated, service_role;

CREATE OR REPLACE FUNCTION private.monte_ingaggi(p_team_id bigint, p_stagione smallint)
 RETURNS bigint
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select coalesce((
    select sum(ingaggio) from public.player_instances
    where team_id = p_team_id and not ritirato
      -- l'anno dell'opzione del giocatore conta: puo' esercitarla lui (quella della squadra conta se esercitata)
      and contratto_scadenza + case when opzione_contratto = 'giocatore' then 1 else 0 end >= p_stagione
  ), 0)::bigint
  + coalesce((
    select sum(ingaggio) from public.vivaio_prospetti where team_id = p_team_id
  ), 0)::bigint
  -- Svincolati che il club paga ancora: contano fino alla scadenza del loro
  -- contratto o finche' un'altra squadra non li prende (team_id torna valorizzato).
  -- Dalla stagione dopo lo svincolo pesano a meta' (contratti pluriennali, diario Season 3 §12).
  + coalesce((
    select sum(private.peso_svincolato(ingaggio, peso_stagione, p_stagione)) from public.player_instances
    where peso_team_id = p_team_id and team_id is null and not ritirato and contratto_scadenza >= p_stagione
  ), 0)::bigint
$function$;

CREATE OR REPLACE FUNCTION public.capienza_squadra(p_league_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_team public.teams;
  v_stagione smallint;
  v_monte bigint;
  v_tetto bigint;
  v_rosa integer;
begin
  select * into v_team from public.teams
  where league_id = p_league_id and user_id = (select auth.uid());
  if not found then
    raise exception using errcode = '42501', message = 'Non partecipi a questa lega.';
  end if;

  select tetto_ingaggi into v_tetto from public.leagues where id = p_league_id;
  v_stagione := private.stagione_contratto(p_league_id);
  v_monte := private.monte_ingaggi(v_team.id, v_stagione);
  select count(*) into v_rosa from public.player_instances where team_id = v_team.id;

  return jsonb_build_object(
    'stagione', v_stagione,
    'tetto', v_tetto,
    'monte', v_monte,
    'capienza', v_tetto - v_monte - private.ingaggi_impegnati_aste(v_team.id, null),
    'rosa', v_rosa,
    'slot_liberi', private.rosa_massima() - v_rosa,
    'peso_svincolati', coalesce((
      select sum(private.peso_svincolato(ingaggio, peso_stagione, v_stagione)) from public.player_instances
      where peso_team_id = v_team.id and team_id is null and not ritirato and contratto_scadenza >= v_stagione
    ), 0)::bigint
  );
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
    raise exception using errcode = '55000', message = 'Il mercato e'' chiuso: puoi svincolare dalle 22:30 alle 20:00, o quando l''admin lo apre.';
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
                        else v_squadra.id end,
    -- stagione in cui pesa per intero: dalle successive pesa a meta' (private.peso_svincolato)
    peso_stagione = v_lega.stagione_corrente
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
    (case
      when v_istanza.ritiro_annunciato then 'Il giocatore aveva già annunciato il ritiro: la carriera termina qui e non torna disponibile.'
      else 'Il giocatore non fa più parte della tua rosa e torna tra gli svincolati. Il suo ingaggio resta sul tuo tetto finché il contratto non scade o un''altra squadra non lo prende.' end) || v_nota,
    jsonb_build_object('player_instance_id', v_istanza.id, 'player_id', v_istanza.player_id)
  );
  return v_istanza;
end;
$function$;

CREATE OR REPLACE FUNCTION private.reset_rinnovo_al_trasferimento()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if old.team_id is not null
     and new.team_id is not null
     and old.team_id is distinct from new.team_id then
    new.rinnovo_tentativi := 0;
  end if;

  -- Opzione del contratto: viaggia col giocatore negli scambi, sparisce quando esce dalla rosa.
  if old.team_id is not null and new.team_id is null then
    new.opzione_contratto := null;
  end if;

  -- Minutaggio (docs/decisioni-minutaggio.md §3, §5): a prova di errore.
  begin
    if old.team_id is distinct from new.team_id then
      new.richiamo_stagione := null;
      new.richiamo_giornata := null;
      new.richiesta_cessione_stagione := null;
      if new.team_id is null then
        new.minutaggio_promesso := null;
        new.arrivo_stagione := null;
      else
        new.arrivo_stagione := (select l.stagione_corrente from public.leagues l where l.id = new.league_id);
        if old.team_id is null then
          new.minutaggio_promesso := private.minutaggio_alla_firma(new.league_id, new.overall_corrente, new.eta_corrente, new.player_id, new.posizioni_override);
        end if;
      end if;
    end if;
  exception when others then
    raise warning 'reset_rinnovo_al_trasferimento: minutaggio non aggiornato per il giocatore % (%)', new.id, sqlerrm;
  end;

  return new;
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

  -- Opzioni ancora aperte (di norma gia' chiuse all'ingresso in off-season): si decidono adesso.
  perform private.risolvi_opzioni_contratti(p_league_id);

  -- Contratti scaduti e non rinnovati: i giocatori restano senza squadra E finiscono nella coda dei rilasci, cosi' alla
  -- prima estrazione dopo la riapertura del mercato compaiono tutti fra i free agent (non solo per sorteggio).
  with liberati as (
    update public.player_instances
    set team_id = null
    where league_id = p_league_id
      and team_id is not null
      and not ritirato
      and contratto_scadenza <= v_league.stagione_corrente
    returning player_id
  )
  insert into private.rilasci_in_coda (league_id, player_id)
  select p_league_id, l.player_id from liberati l
  on conflict (league_id, player_id) do nothing;

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
      insert into private.rilasci_in_coda (league_id, player_id)
      select p_league_id, pi.player_id from public.player_instances pi where pi.id = v_candidate.id
      on conflict (league_id, player_id) do nothing;
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

  -- ON-Season della nuova stagione: l'ordine dal monte ingaggi (minore -> maggiore),
  -- misurato ora che draft e rose sono completi.
  perform private.assegna_posizioni_on_per_monte_ingaggi(p_league_id, v_off.stagione_a);

  -- Le formazioni della stagione chiusa non devono sopravvivere nella nuova: lineups non ha la stagione,
  -- quindi una riga "giornata 2" di agosto verrebbe scambiata per quella della giornata 2 di questa
  -- stagione (simulazione, promemoria, pagina Formazione). Si archiviano e si tolgono: restano solo le
  -- formazioni preparate durante l'off-season (giornata 1 salvata dopo l'apertura dell'off-season).
  insert into private.lineups_archivio
  select l.*, v_off.stagione_da::smallint
  from public.lineups l
  where l.league_id = p_league_id and (l.giornata >= 2 or l.salvata_il < v_off.creata_il);
  delete from public.lineups l
  where l.league_id = p_league_id and (l.giornata >= 2 or l.salvata_il < v_off.creata_il);

  update public.offseasons
  set stato = 'conclusa', conclusa_il = clock_timestamp()
  where id = v_off.id;
  update public.leagues
  set stagione_corrente = v_off.stagione_a,
      fase_carriera = case when v_league.conferenze_attive then 'sorteggio' else 'normale' end,
      offseason_fine = null,
      stato = 'stagione',
      stadio_attivo = true
  where id = p_league_id;

  -- Season 3 (diario §2): ogni stagione riparte con morale dei giocatori e pubblico a meta'. Si fa qui, alla
  -- chiusura dell'off-season, perche' durante l'off-season il morale serve ancora ai rinnovi.
  update public.player_instances set morale = 50
  where league_id = p_league_id and not ritirato and morale <> 50;
  update public.teams set pubblico = 50
  where league_id = p_league_id and pubblico <> 50;

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
    case when v_league.conferenze_attive then 'Entra ora: prima il draft dei giocatori, poi il sorteggio delle conferenze Eastern e Western.'
         else 'La prima giornata si giochera'' alle 22:00. Prepara la formazione.' end,
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

CREATE OR REPLACE FUNCTION public.proposta_rinnovo(p_instance_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_user_id uuid := (select auth.uid());
  v_inst public.player_instances;
  v_league public.leagues;
  v_player public.players;
  v_proposta record;
  v_media numeric;
  v_gradini jsonb := '[]'::jsonb;
  v_g text;
  v_richiesto text;
  v_pluri boolean;
  v_molt jsonb := '[]'::jsonb;
  v_d integer;
  v_o text;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'Devi accedere prima di trattare un rinnovo.';
  end if;

  select * into v_inst from public.player_instances where id = p_instance_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Giocatore non trovato.';
  end if;

  if not exists (
    select 1 from public.teams
    where id = v_inst.team_id and league_id = v_inst.league_id and user_id = v_user_id
  ) then
    raise exception using errcode = '42501', message = 'Questo giocatore non e'' nella tua rosa.';
  end if;

  select * into v_league from public.leagues where id = v_inst.league_id;
  if v_league.stato <> 'stagione' then
    raise exception using errcode = '55000', message = 'I rinnovi si trattano solo a stagione avviata.';
  end if;
  if v_inst.ritirato or v_inst.ritiro_annunciato then
    raise exception using errcode = '55000', message = 'Ha gia'' annunciato il ritiro: non rinnovera'' il contratto.';
  end if;
  if v_league.tattiche_attive and v_inst.richiesta_cessione_stagione is not null then
    raise exception using errcode = '55000', message = 'Ha chiesto la cessione: non rinnovera'' il contratto.';
  end if;

  select * into v_player from public.players where id = v_inst.player_id;
  select * into v_proposta
  from private.rinnovo_proposta(
    v_inst.id, v_inst.overall_corrente, v_inst.eta_corrente, v_inst.ingaggio,
    v_player.mentalita_bandiera, v_player.mentalita_economia
  );

  if v_league.tattiche_attive then
    select avg(x.overall_corrente) into v_media
    from public.player_instances x where x.team_id = v_inst.team_id and not x.ritirato;
    v_richiesto := private.gradino_richiesto_istanza(v_inst.id);
    foreach v_g in array array['titolare', 'turnover', 'sporadico', 'promessa'] loop
      v_gradini := v_gradini || jsonb_build_object(
        'chiave', v_g,
        'richiesta', private.richiesta_per_gradino(v_proposta.richiesta, v_g, v_richiesto),
        'rifiuto', private.gradino_rifiutato(v_g, v_richiesto, v_inst.eta_corrente, v_inst.overall_corrente, v_media)
      );
    end loop;
  end if;

  -- Contratti pluriennali: moltiplicatore della richiesta per ogni durata e opzione (l'app lo applica al gradino scelto).
  v_pluri := private.pluriennali_attivi(v_league.id);
  if v_pluri then
    foreach v_o in array array['', 'squadra', 'giocatore'] loop
      for v_d in 1..3 loop
        v_molt := v_molt || jsonb_build_object(
          'durata', v_d, 'opzione', nullif(v_o, ''),
          'moltiplicatore', private.moltiplicatore_durata(v_inst.eta_corrente, v_inst.overall_corrente, v_player.potential,
                                                          v_inst.morale, v_d::smallint, nullif(v_o, '')));
      end loop;
    end loop;
  end if;

  return jsonb_build_object(
    'player_instance_id', v_inst.id,
    'ingaggio_attuale', v_inst.ingaggio,
    'scadenza_attuale', v_inst.contratto_scadenza,
    'stagione_corrente', v_league.stagione_corrente,
    'richiesta', v_proposta.richiesta,
    'durata', v_proposta.durata,
    'nuova_scadenza', greatest(v_inst.contratto_scadenza, (v_league.stagione_corrente + v_proposta.durata)::smallint),
    'tentativi_usati', v_inst.rinnovo_tentativi,
    'tentativi_totali', 3,
    'trattativa_chiusa', v_inst.rinnovo_tentativi >= 3,
    'gia_rinnovato', v_inst.rinnovo_stagione is not null and v_inst.rinnovo_stagione = v_league.stagione_corrente,
    'morale', v_inst.morale,
    'mentalita', jsonb_build_object(
      'bandiera', v_player.mentalita_bandiera,
      'economia', v_player.mentalita_economia,
      'vittorie', v_player.mentalita_vittorie
    ),
    -- Minutaggio (docs/decisioni-minutaggio.md): vuoto nelle leghe senza tattiche.
    'gradino_attuale', case when v_league.tattiche_attive then private.gradino_effettivo(v_inst.id) end,
    'gradino_richiesto', v_richiesto,
    'gradino_trattato', v_inst.minutaggio_promesso is not null,
    'gradini', case when v_league.tattiche_attive then v_gradini end,
    'pluriennali', v_pluri,
    'ultima_stagione', v_inst.contratto_scadenza <= v_league.stagione_corrente,
    'opzione', v_inst.opzione_contratto,
    'solo_un_anno', v_pluri and v_inst.morale < 30,
    'moltiplicatori', case when v_pluri then v_molt end
  );
end;
$function$;

drop function public.offri_rinnovo(bigint, bigint, smallint, text);
CREATE OR REPLACE FUNCTION public.offri_rinnovo(p_instance_id bigint, p_ingaggio bigint, p_durata smallint, p_minutaggio text DEFAULT NULL::text, p_opzione text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_user_id uuid := (select auth.uid());
  v_inst public.player_instances;
  v_league public.leagues;
  v_team public.teams;
  v_player public.players;
  v_proposta record;
  v_posizione smallint;
  v_tolleranza numeric;
  v_soglia numeric;
  v_valore numeric;
  v_rapporto numeric;
  v_scadenza smallint;
  v_tentativi smallint;
  v_gradino text;
  v_media numeric;
  v_rifiuto text;
  v_richiesta bigint;
  v_richiesto text;
  v_pluri boolean;
  v_molt numeric;
  v_fine integer;
  v_s integer;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'Devi accedere prima di trattare un rinnovo.';
  end if;
  if p_ingaggio < 500000 then
    raise exception using errcode = '22023', message = 'L''ingaggio minimo è 0,5 M€.';
  end if;
  if p_durata is null or p_durata not between 1 and 3 then
    raise exception using errcode = '22023', message = 'Il contratto dura da 1 a 3 stagioni.';
  end if;
  if p_opzione is not null and p_opzione not in ('squadra', 'giocatore') then
    raise exception using errcode = '22023', message = 'Opzione non valida.';
  end if;
  if p_minutaggio is not null and p_minutaggio not in ('titolare', 'turnover', 'sporadico', 'promessa') then
    raise exception using errcode = '22023', message = 'Minutaggio non valido.';
  end if;

  select * into v_inst from public.player_instances where id = p_instance_id for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Giocatore non trovato.';
  end if;

  select * into v_team from public.teams
  where id = v_inst.team_id and league_id = v_inst.league_id and user_id = v_user_id and attiva;
  if not found then
    raise exception using errcode = '42501', message = 'Questo giocatore non è nella tua rosa.';
  end if;

  select * into v_league from public.leagues where id = v_inst.league_id;
  if v_league.stato <> 'stagione' then
    raise exception using errcode = '55000', message = 'I rinnovi si trattano solo a stagione avviata.';
  end if;

  -- Contratti pluriennali (diario Season 3 §12): 1-3 stagioni + opzione, solo nell'ultima stagione del contratto.
  v_pluri := private.pluriennali_attivi(v_league.id);
  if not v_pluri and (p_durata <> 1 or p_opzione is not null) then
    raise exception using errcode = '22023',
      message = 'In questa stagione i contratti durano un anno: il rinnovo estende di una stagione.';
  end if;
  if v_pluri and v_inst.opzione_contratto = 'squadra' then
    raise exception using errcode = '55000',
      message = 'Ha un''opzione a favore della squadra: prima decidi se esercitarla o rinunciarci.';
  end if;
  if v_pluri and v_inst.opzione_contratto = 'giocatore' then
    raise exception using errcode = '55000',
      message = 'Ha un''opzione a suo favore: a fine stagione decide lui se restare un altro anno.';
  end if;
  if v_pluri and v_inst.contratto_scadenza > v_league.stagione_corrente then
    raise exception using errcode = '55000',
      message = 'Ha un contratto fino alla stagione ' || v_inst.contratto_scadenza || ': si rinnova nella sua ultima stagione.';
  end if;
  if v_inst.ritirato or v_inst.ritiro_annunciato then
    raise exception using errcode = '55000', message = 'Ha già annunciato il ritiro: non rinnoverà il contratto.';
  end if;
  if v_league.tattiche_attive and v_inst.richiesta_cessione_stagione is not null then
    raise exception using errcode = '55000', message = 'Ha chiesto la cessione: non rinnoverà il contratto.';
  end if;
  if v_inst.rinnovo_stagione is not null and v_inst.rinnovo_stagione = v_league.stagione_corrente then
    raise exception using errcode = '55000',
      message = 'Ha già rinnovato in questa stagione: se ne riparla dalla prossima.';
  end if;
  if v_inst.rinnovo_tentativi >= 3 then
    raise exception using errcode = '55000',
      message = 'Ha chiuso la trattativa: andrà a scadenza e lascerà la squadra.';
  end if;

  select * into v_player from public.players where id = v_inst.player_id;
  select * into v_proposta
  from private.rinnovo_proposta(
    v_inst.id, v_inst.overall_corrente, v_inst.eta_corrente, v_inst.ingaggio,
    v_player.mentalita_bandiera, v_player.mentalita_economia
  );

  -- Il gradino: quello offerto, o (senza sceglierlo) quello che ha gia'. Un
  -- gradino non alla sua altezza lo rifiuta senza consumare un tentativo.
  v_richiesta := v_proposta.richiesta;
  if v_league.tattiche_attive then
    v_richiesto := private.gradino_richiesto_istanza(v_inst.id);
    v_gradino := coalesce(p_minutaggio, private.gradino_effettivo(v_inst.id));
    if p_minutaggio is not null then
      select avg(x.overall_corrente) into v_media
      from public.player_instances x where x.team_id = v_inst.team_id and not x.ritirato;
      v_rifiuto := private.gradino_rifiutato(p_minutaggio, v_richiesto, v_inst.eta_corrente, v_inst.overall_corrente, v_media);
      if v_rifiuto is not null then
        return jsonb_build_object(
          'esito', 'gradino_rifiutato',
          'tentativi_usati', v_inst.rinnovo_tentativi,
          'tentativi_totali', 3,
          'messaggio', case
            when p_minutaggio = 'promessa' and v_inst.eta_corrente >= 21 then 'Mister, non sono più un ragazzino.'
            else 'Con tutto il rispetto, mister: non sono venuto qui per fare panchina.' end,
          'motivo', v_rifiuto
        );
      end if;
    end if;
    v_richiesta := private.richiesta_per_gradino(v_proposta.richiesta, v_gradino, v_richiesto);
  end if;

  -- Durata e opzione spostano la richiesta (private.moltiplicatore_durata). Chi e' molto scontento firma solo per un
  -- anno: la proposta lunga la rifiuta senza consumare un tentativo, come un gradino fuori misura.
  if v_pluri then
    if v_inst.morale < 30 and (p_durata > 1 or p_opzione is not null) then
      return jsonb_build_object(
        'esito', 'durata_rifiutata',
        'tentativi_usati', v_inst.rinnovo_tentativi,
        'tentativi_totali', 3,
        'messaggio', 'Mister, come sto adesso non mi lego per più di un anno.',
        'motivo', 'Con il morale sotto 30 firma solo per una stagione, senza opzione.'
      );
    end if;
    v_molt := private.moltiplicatore_durata(v_inst.eta_corrente, v_inst.overall_corrente, v_player.potential,
                                            v_inst.morale, p_durata, p_opzione);
    v_richiesta := greatest(500000, round(v_richiesta * v_molt / 100000) * 100000)::bigint;
  end if;

  select coalesce(st.posizione, 1) into v_posizione
  from public.seasons se
  join public.standings st on st.season_id = se.id and st.team_id = v_inst.team_id
  where se.league_id = v_inst.league_id and se.numero = v_league.stagione_corrente;

  v_tolleranza := private.rinnovo_tolleranza(
    v_inst.morale, v_player.mentalita_bandiera, v_player.mentalita_economia,
    v_player.mentalita_vittorie, coalesce(v_posizione, 1::smallint),
    coalesce(private.squadre_nel_gruppo((select se.id from public.seasons se where se.league_id = v_inst.league_id and se.numero = v_league.stagione_corrente), v_inst.team_id), v_league.n_squadre)::smallint
  );
  v_soglia := v_richiesta * (1 - v_tolleranza);

  v_valore := p_ingaggio;
  v_rapporto := v_valore / greatest(1, v_soglia);

  if v_rapporto >= 1 then
    -- Le due verifiche sono sotto lo stesso lock di squadra: due rinnovi
    -- contemporanei non possono consumare la medesima capienza.
    perform 1 from public.teams where id = v_team.id for update;
    perform private.verifica_capienza(
      v_team.id, p_ingaggio - v_inst.ingaggio, v_league.stagione_corrente
    );
    -- Ogni stagione coperta dal nuovo contratto, compresa quella dell'opzione del giocatore (puo' esercitarla lui).
    -- L'opzione della squadra si verifica quando la squadra la esercita.
    v_fine := v_league.stagione_corrente + case when v_pluri then p_durata + case when p_opzione = 'giocatore' then 1 else 0 end
                                                 else 1 end;
    for v_s in (v_league.stagione_corrente + 1)..v_fine loop
      perform private.verifica_capienza(
        v_team.id,
        p_ingaggio - case when v_inst.contratto_scadenza >= v_s then v_inst.ingaggio else 0 end,
        v_s::smallint
      );
    end loop;

    v_scadenza := case when v_pluri then (v_league.stagione_corrente + p_durata)::smallint
                       else greatest(v_inst.contratto_scadenza, (v_league.stagione_corrente + 1)::smallint) end;
    update public.player_instances
    set ingaggio = p_ingaggio,
        contratto_scadenza = v_scadenza,
        rinnovo_tentativi = 0,
        rinnovo_stagione = v_league.stagione_corrente,
        opzione_contratto = case when v_pluri then p_opzione else opzione_contratto end,
        -- Il gradino trattato diventa parte del contratto; senza sceglierlo
        -- resta com'era (anche automatico).
        minutaggio_promesso = case when v_league.tattiche_attive and p_minutaggio is not null
                                   then p_minutaggio else minutaggio_promesso end,
        richiamo_stagione = case when v_league.tattiche_attive and p_minutaggio is not null
                                 then null else richiamo_stagione end,
        richiamo_giornata = case when v_league.tattiche_attive and p_minutaggio is not null
                                 then null else richiamo_giornata end
    where id = v_inst.id;
    perform private.spinta_morale_rinnovo(v_inst.id);

    insert into public.transactions (league_id, team_id, tipo, importo, descrizione, saldo_dopo)
    values (
      v_inst.league_id, v_team.id, 'rinnovo_in_stagione',
      coalesce(nullif(v_inst.ingaggio - p_ingaggio, 0), 1),
      'Rinnovo: ' || coalesce(v_player.nome, 'giocatore') || ' — '
        || round(p_ingaggio / 1000000.0, 1) || ' M€ fino alla stagione ' || v_scadenza
        || case p_opzione when 'squadra' then ' (+1 opzione squadra)' when 'giocatore' then ' (+1 opzione giocatore)' else '' end,
      0
    );

    return jsonb_build_object(
      'esito', 'accettato',
      'ingaggio', p_ingaggio,
      'durata', p_durata,
      'opzione', p_opzione,
      'contratto_scadenza', v_scadenza,
      'tentativi_usati', 0,
      'minutaggio', v_gradino,
      'messaggio', 'Ci sto, mister. Grazie della fiducia.'
    );
  end if;

  v_tentativi := (v_inst.rinnovo_tentativi + 1)::smallint;
  update public.player_instances set rinnovo_tentativi = v_tentativi where id = v_inst.id;

  return jsonb_build_object(
    'esito', case when v_tentativi >= 3 then 'chiusa' else 'rifiutato' end,
    'tentativi_usati', v_tentativi,
    'tentativi_totali', 3,
    'messaggio', case
      when v_tentativi >= 3 then 'Basta così, mister. Andrò a scadenza.'
      when v_rapporto >= 0.95 then 'Ci siamo quasi, ma non ancora.'
      when v_rapporto >= 0.85 then 'È troppo poco per quello che valgo.'
      else 'Non se ne parla nemmeno, mister.'
    end
  );
end;
$function$;
revoke all on function public.offri_rinnovo(bigint, bigint, smallint, text, text) from public, anon;
grant execute on function public.offri_rinnovo(bigint, bigint, smallint, text, text) to authenticated, service_role;

-- L'allenatore decide l'opzione della squadra durante l'ultima stagione del contratto (non in off-season: li' e' gia'
-- scaduta). Esercitata: resta un'altra stagione allo stesso ingaggio, se c'e' spazio sotto il tetto. Rifiutata: il
-- contratto scade a fine stagione e si puo' trattare un rinnovo normale.
create or replace function public.decidi_opzione_squadra(p_instance_id bigint, p_esercita boolean)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_user_id uuid := (select auth.uid());
  v_inst public.player_instances;
  v_league public.leagues;
  v_team public.teams;
  v_nome text;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'Devi accedere per decidere l''opzione.';
  end if;
  select * into v_inst from public.player_instances where id = p_instance_id for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Giocatore non trovato.';
  end if;
  select * into v_team from public.teams
  where id = v_inst.team_id and league_id = v_inst.league_id and user_id = v_user_id and attiva;
  if not found then
    raise exception using errcode = '42501', message = 'Questo giocatore non è nella tua rosa.';
  end if;
  select * into v_league from public.leagues where id = v_inst.league_id;
  if v_inst.opzione_contratto is distinct from 'squadra' then
    raise exception using errcode = '55000', message = 'Il suo contratto non ha un''opzione a favore della squadra.';
  end if;
  if v_inst.contratto_scadenza > v_league.stagione_corrente then
    raise exception using errcode = '55000',
      message = 'L''opzione si decide nell''ultima stagione del contratto (la ' || v_inst.contratto_scadenza || ').';
  end if;
  if v_league.stato <> 'stagione' or v_league.fase_carriera = 'offseason' then
    raise exception using errcode = '55000', message = 'L''opzione si decide entro la fine della stagione.';
  end if;
  select nome into v_nome from public.players where id = v_inst.player_id;

  if not p_esercita then
    update public.player_instances set opzione_contratto = null where id = v_inst.id;
    return jsonb_build_object('esito', 'rifiutata', 'contratto_scadenza', v_inst.contratto_scadenza,
      'messaggio', 'Opzione rifiutata: il contratto scade a fine stagione. Puoi ancora trattare un rinnovo.');
  end if;

  perform 1 from public.teams where id = v_team.id for update;
  perform private.verifica_capienza(v_team.id, v_inst.ingaggio, (v_league.stagione_corrente + 1)::smallint);
  update public.player_instances
  set contratto_scadenza = (v_league.stagione_corrente + 1)::smallint,
      opzione_contratto = null,
      rinnovo_tentativi = 0,
      rinnovo_stagione = v_league.stagione_corrente
  where id = v_inst.id;
  insert into public.transactions (league_id, team_id, tipo, importo, descrizione, saldo_dopo)
  values (v_inst.league_id, v_team.id, 'rinnovo_in_stagione', 1,
          'Opzione esercitata: ' || coalesce(v_nome, 'giocatore') || ' — ' || round(v_inst.ingaggio / 1000000.0, 1)
            || ' M€ fino alla stagione ' || (v_league.stagione_corrente + 1), 0);
  return jsonb_build_object('esito', 'esercitata', 'contratto_scadenza', v_league.stagione_corrente + 1,
    'messaggio', 'Opzione esercitata: resta fino alla stagione ' || (v_league.stagione_corrente + 1) || '.');
end;
$function$;
revoke all on function public.decidi_opzione_squadra(bigint, boolean) from public, anon;
grant execute on function public.decidi_opzione_squadra(bigint, boolean) to authenticated, service_role;

-- Chiude le opzioni dei contratti all'ultima stagione: quelle della squadra non decise sono rifiutate; quelle del
-- giocatore le decide lui (resta se il contratto vale ancora quanto lui e non e' scontento). Avvisa l'allenatore.
-- Si chiama all'ingresso in off-season (trigger) e, per sicurezza, a fine off-season prima dei contratti scaduti.
create or replace function private.risolvi_opzioni_contratti(p_league_id bigint)
returns integer
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_stagione smallint;
  v_riga record;
  v_resta boolean;
  v_n integer := 0;
begin
  select stagione_corrente into v_stagione from public.leagues where id = p_league_id;
  if v_stagione is null then return 0; end if;

  for v_riga in
    select pi.*, p.nome, t.user_id, t.id as squadra
    from public.player_instances pi
    join public.players p on p.id = pi.player_id
    left join public.teams t on t.id = pi.team_id
    where pi.league_id = p_league_id and pi.opzione_contratto is not null and pi.contratto_scadenza <= v_stagione
    order by pi.id
    for update of pi
  loop
    v_n := v_n + 1;
    if v_riga.opzione_contratto = 'squadra' or v_riga.team_id is null or v_riga.ritirato or v_riga.ritiro_annunciato then
      update public.player_instances set opzione_contratto = null where id = v_riga.id;
      if v_riga.opzione_contratto = 'squadra' and v_riga.team_id is not null then
        perform private.notifica(v_riga.user_id, p_league_id, 'sistema', 'Opzione scaduta: ' || v_riga.nome,
          'Non hai deciso l''opzione entro fine stagione: il contratto di ' || v_riga.nome
            || ' scade. Se vuoi tenerlo, trattane il rinnovo prima che finisca l''off-season.',
          jsonb_build_object('view', 'squad', 'player_instance_id', v_riga.id));
      end if;
      continue;
    end if;

    v_resta := v_riga.morale >= 40
      and private.ingaggio_teorico(v_riga.overall_corrente, v_riga.eta_corrente) <= v_riga.ingaggio * 1.10;
    if v_resta then
      update public.player_instances
      set contratto_scadenza = contratto_scadenza + 1, opzione_contratto = null
      where id = v_riga.id;
    else
      update public.player_instances set opzione_contratto = null where id = v_riga.id;
    end if;
    perform private.notifica(v_riga.user_id, p_league_id, 'sistema',
      case when v_resta then v_riga.nome || ' esercita l''opzione' else v_riga.nome || ' rinuncia all''opzione' end,
      case when v_resta
        then 'Resta un''altra stagione allo stesso ingaggio: contratto fino alla stagione ' || (v_riga.contratto_scadenza + 1) || '.'
        else 'Il contratto scade a fine stagione. Se vuoi tenerlo, trattane il rinnovo prima che finisca l''off-season.' end,
      jsonb_build_object('view', 'squad', 'player_instance_id', v_riga.id));
  end loop;
  return v_n;
end;
$function$;
revoke all on function private.risolvi_opzioni_contratti(bigint) from public, anon, authenticated;

create or replace function private.risolvi_opzioni_in_offseason()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  perform private.risolvi_opzioni_contratti(new.id);
  return null;
end;
$function$;
revoke all on function private.risolvi_opzioni_in_offseason() from public, anon, authenticated;

drop trigger if exists leagues_risolvi_opzioni on public.leagues;
create trigger leagues_risolvi_opzioni after update of fase_carriera on public.leagues
for each row when (new.fase_carriera = 'offseason' and old.fase_carriera is distinct from 'offseason')
execute function private.risolvi_opzioni_in_offseason();

-- Promemoria: ogni giorno alle 12 (Roma), quando alla lega restano al massimo 3 partite da giocare, chi ha opzioni
-- della squadra ancora da decidere riceve un avviso (una non decisa vale come rifiutata).
create or replace function private.promemoria_opzioni_squadra()
returns integer
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_riga record;
  v_n integer := 0;
begin
  if extract(hour from (now() at time zone 'Europe/Rome')) <> 12 then
    return 0;
  end if;
  for v_riga in
    select t.user_id, t.league_id, count(*) as quanti, string_agg(p.nome, ', ' order by pi.ingaggio desc) as nomi
    from public.player_instances pi
    join public.players p on p.id = pi.player_id
    join public.teams t on t.id = pi.team_id and t.attiva and t.user_id is not null
    join public.leagues l on l.id = pi.league_id and l.stato = 'stagione' and l.fase_carriera <> 'offseason'
    where pi.opzione_contratto = 'squadra' and pi.contratto_scadenza <= l.stagione_corrente
      -- stagione gia' cominciata (almeno una partita giocata) e al massimo 3 ancora da giocare
      and exists (select 1 from public.fixtures f join public.seasons se on se.id = f.season_id
                  where f.league_id = l.id and se.numero = l.stagione_corrente and f.stato = 'simulata')
      and (select count(*) from public.fixtures f join public.seasons se on se.id = f.season_id
           where f.league_id = l.id and se.numero = l.stagione_corrente and f.stato <> 'simulata') <= 3
    group by t.user_id, t.league_id
  loop
    perform private.notifica(v_riga.user_id, v_riga.league_id, 'sistema',
      case when v_riga.quanti = 1 then 'Un''opzione da decidere' else v_riga.quanti || ' opzioni da decidere' end,
      'Decidi entro fine stagione se tenere ' || v_riga.nomi || ': un''opzione non decisa vale come rifiutata.',
      jsonb_build_object('view', 'squad'));
    v_n := v_n + 1;
  end loop;
  return v_n;
end;
$function$;
revoke all on function private.promemoria_opzioni_squadra() from public, anon, authenticated;

select cron.unschedule('promemoria-opzioni') where exists (select 1 from cron.job where jobname = 'promemoria-opzioni');
select cron.schedule('promemoria-opzioni', '5 * * * *', 'select private.promemoria_opzioni_squadra();');
