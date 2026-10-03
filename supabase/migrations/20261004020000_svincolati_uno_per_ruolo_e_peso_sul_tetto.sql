-- ============================================================
--  MERCATO SVINCOLATI: UNO PER RUOLO E INGAGGIO A CARICO DI CHI SVINCOLA
--  Deciso dal committente il 4 ottobre 2026, per spingere gli scambi.
--
--  1. L'estrazione giornaliera passa da 5 a 1 giocatore per ruolo.
--  2. Chi svincola libera subito il posto in rosa, ma l'ingaggio resta nel suo
--     monte (player_instances.peso_team_id) fino a scadenza del contratto o
--     finche' un'altra squadra non prende il giocatore. Smentisce "Lo svincolo
--     libera lo spazio, senza penalita'" di docs/decisioni-economia.md.
--  3. Gli svincolati ancora a carico di un club compaiono nel mercato ogni
--     giorno, oltre all'estrazione, fino a firma o scadenza; poi tornano nel
--     pool generico.
--  Non retroattiva: vale per gli svincoli da questa migrazione in poi.
-- ============================================================

alter table public.player_instances
  add column if not exists peso_team_id bigint references public.teams(id) on delete set null;
comment on column public.player_instances.peso_team_id is
  'Club che paga ancora l''ingaggio dopo averlo svincolato. Pesa sul suo tetto finche'' team_id e'' nullo e il contratto non e'' scaduto.';
create index if not exists player_instances_peso_team_idx on public.player_instances (peso_team_id) where peso_team_id is not null;

-- Appena il giocatore firma con qualcuno (asta, scelta, qualunque strada),
-- il vecchio club smette di pagarlo.
create or replace function private.azzera_peso_alla_firma()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.team_id is not null and old.team_id is null then
    new.peso_team_id := null;
  end if;
  return new;
end;
$$;

drop trigger if exists player_instances_azzera_peso on public.player_instances;
create trigger player_instances_azzera_peso
  before update of team_id on public.player_instances
  for each row execute function private.azzera_peso_alla_firma();

CREATE OR REPLACE FUNCTION private.monte_ingaggi(p_team_id bigint, p_stagione smallint)
 RETURNS bigint
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select coalesce((
    select sum(ingaggio) from public.player_instances
    where team_id = p_team_id and not ritirato and contratto_scadenza >= p_stagione
  ), 0)::bigint
  + coalesce((
    select sum(ingaggio) from public.vivaio_prospetti where team_id = p_team_id
  ), 0)::bigint
  -- Svincolati che il club paga ancora: contano fino alla scadenza del loro
  -- contratto o finche' un'altra squadra non li prende (team_id torna valorizzato).
  + coalesce((
    select sum(ingaggio) from public.player_instances
    where peso_team_id = p_team_id and team_id is null and not ritirato and contratto_scadenza >= p_stagione
  ), 0)::bigint
$function$
;

CREATE OR REPLACE FUNCTION private.svincolati_per_ruolo(p_league_id bigint)
 RETURNS integer
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_fase text;
begin
  select fase_carriera into v_fase
  from public.leagues
  where id = p_league_id;

  if not found then
    raise exception using errcode = 'P0002', message = 'Lega inesistente.';
  end if;

  -- Dal 4 ottobre 2026 uno per ruolo (prima 5, 10 in off-season, dove ora il
  -- mercato svincolati e' chiuso): piu' spazio agli scambi. Gli svincolati
  -- dalle squadre si aggiungono a parte, tutti, in estrai_svincolati_lega.
  return 1;
end;
$function$
;

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
    v_giornate_trascorse := coalesce(v_prossima, v_lega.giornate_totali + 1) - v_istanza.giornata_acquisizione;
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
          when '3-5-2' then array['GK','CB','CB','CB','LWB','CM','CM','CM','RWB','ST','ST']
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
    peso_team_id = case when v_istanza.ritiro_annunciato then null else v_squadra.id end
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

  if v_formazioni_aggiornate > 0 then v_nota := ' Formazione aggiornata automaticamente con un sostituto.'; end if;
  perform private.notifica(
    v_utente, v_lega.id, 'mercato_esito', 'Giocatore svincolato',
    v_giocatore.nome || (case
      when v_istanza.ritiro_annunciato then ' aveva gia'' annunciato il ritiro: la carriera termina qui, non torna disponibile.'
      else ' non fa piu'' parte della tua rosa. Torna nel mercato degli svincolati, ma il suo ingaggio resta sul tuo tetto finche'' il contratto non scade o un''altra squadra non lo prende.' end) || v_nota,
    jsonb_build_object('player_instance_id', v_istanza.id, 'player_id', v_istanza.player_id)
  );
  return v_istanza;
end;
$function$
;

CREATE OR REPLACE FUNCTION private.estrai_svincolati_lega(p_league_id bigint, p_giorno date)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_lega       public.leagues;
  v_per_ruolo  integer;
  v_tornata    integer;
  v_creati     integer := 0;
  v_dalla_coda integer := 0;
  v_asta       record;
begin
  select * into v_lega from public.leagues where id = p_league_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Lega inesistente.';
  end if;
  select coalesce(max(a.tornata), 0) + 1 into v_tornata
  from public.free_agent_auctions a
  where a.league_id = p_league_id and a.giorno = p_giorno and a.origine = 'estrazione';
  v_per_ruolo := private.svincolati_per_ruolo(p_league_id);

  with disponibili as (
    select p.id, private.macro_ruolo(p.posizioni) as macro,
           coalesce(oi.overall_corrente, fap.overall_corrente, p.overall) as overall_attuale,
           coalesce(oi.eta_corrente, fap.eta_corrente, p.eta) as eta_attuale
    from public.players p
    left join public.player_instances oi
      on oi.league_id = p_league_id and oi.player_id = p.id and oi.team_id is null
    left join public.free_agent_progression fap
      on fap.league_id = p_league_id and fap.player_id = p.id
    where p.disponibile_estrazione
      -- decisioni-draft-picks §3.3: sopra 75 si passa dal mercato a scelte
      and coalesce(oi.overall_corrente, fap.overall_corrente, p.overall) <= 75
      and (p.elite_globale or p.campionato = any(v_lega.campionati_attivi))
      and private.macro_ruolo(p.posizioni) in ('GK', 'DEF', 'MID', 'ATT')
      and not exists (
        select 1 from public.player_instances pi
        where pi.league_id = p_league_id and pi.player_id = p.id and pi.team_id is not null
      )
      and not exists (
        select 1 from public.retired_players rp
        where rp.league_id = p_league_id and rp.player_id = p.id
      )
      and not exists (
        select 1 from public.free_agent_auctions a
        where a.league_id = p_league_id and a.giorno = p_giorno and a.player_id = p.id
      )
      -- Gli svincolati che un club paga ancora entrano a parte, tutti.
      and not exists (
        select 1 from public.player_instances pp
        where pp.league_id = p_league_id and pp.player_id = p.id
          and pp.team_id is null and pp.peso_team_id is not null
          and pp.contratto_scadenza >= private.stagione_contratto(p_league_id)
      )
      -- I rilasci in coda non concorrono ai posti del sorteggio: entrano
      -- extra piu' sotto, garantiti.
      and not exists (
        select 1 from private.rilasci_in_coda rc
        where rc.league_id = p_league_id and rc.player_id = p.id
      )
  ), ranked as (
    select id, macro, overall_attuale, eta_attuale,
           row_number() over (partition by macro order by random()) as rn
    from disponibili
  ), scelti as (
    select id, overall_attuale, eta_attuale from ranked where rn <= v_per_ruolo
  )
  insert into public.free_agent_auctions
    (league_id, giorno, player_id, ingaggio_teorico, origine, tornata)
  select p_league_id, p_giorno, s.id,
         private.ingaggio_teorico(s.overall_attuale, s.eta_attuale), 'estrazione', v_tornata
  from scelti s;

  get diagnostics v_creati = row_count;

  -- Rilasci in coda: entrano nella STESSA tornata appena creata, in piu'
  -- rispetto alla quota per ruolo. Solo chi e' ancora davvero libero — nel
  -- frattempo puo' essere stato ripreso da un'asta o uno scambio.
  with liberi as (
    select rc.player_id
    from private.rilasci_in_coda rc
    join public.player_instances pi
      on pi.league_id = rc.league_id and pi.player_id = rc.player_id
    where rc.league_id = p_league_id and pi.team_id is null and not pi.ritirato
  ), inseriti as (
    insert into public.free_agent_auctions
      (league_id, giorno, player_id, ingaggio_teorico, origine, tornata)
    select p_league_id, p_giorno, pi.player_id,
           private.ingaggio_teorico(pi.overall_corrente, pi.eta_corrente), 'estrazione', v_tornata
    from liberi l
    join public.player_instances pi on pi.league_id = p_league_id and pi.player_id = l.player_id
    returning player_id
  )
  delete from private.rilasci_in_coda
  where league_id = p_league_id and player_id in (select player_id from inseriti);
  get diagnostics v_dalla_coda = row_count;
  v_creati := v_creati + v_dalla_coda;

  -- Svincolati dalle squadre ancora a carico del vecchio club: ogni giorno,
  -- finche' qualcuno li prende o il contratto scade (poi tornano nel pool
  -- generico come tutti).
  insert into public.free_agent_auctions
    (league_id, giorno, player_id, ingaggio_teorico, origine, tornata)
  select p_league_id, p_giorno, pi.player_id,
         private.ingaggio_teorico(pi.overall_corrente, pi.eta_corrente), 'estrazione', v_tornata
  from public.player_instances pi
  where pi.league_id = p_league_id and pi.team_id is null and not pi.ritirato
    and pi.peso_team_id is not null
    and pi.contratto_scadenza >= private.stagione_contratto(p_league_id)
    and not exists (
      select 1 from public.free_agent_auctions a
      where a.league_id = p_league_id and a.giorno = p_giorno and a.player_id = pi.player_id
    );
  get diagnostics v_dalla_coda = row_count;
  v_creati := v_creati + v_dalla_coda;

  for v_asta in
    select a.id, a.ingaggio_teorico from public.free_agent_auctions a
    where a.league_id = p_league_id and a.giorno = p_giorno
  loop
    insert into private.auction_thresholds (auction_id, soglia)
    values (v_asta.id, round(v_asta.ingaggio_teorico * (0.90 + random() * 0.20)))
    on conflict (auction_id) do nothing;
  end loop;
  return v_creati;
end;
$function$
;

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
      select sum(ingaggio) from public.player_instances
      where peso_team_id = v_team.id and team_id is null and not ritirato and contratto_scadenza >= v_stagione
    ), 0)::bigint
  );
end;
$function$
;

notify pgrst, 'reload schema';
