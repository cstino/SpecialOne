-- ============================================================
--  ECONOMIA A TETTO SALARIALE — svincolo: coda immediata nel mercato, e
--  niente piu' quota in contanti a stagione in corso
--  docs/decisioni-economia.md §2, §4
--
--  Due correzioni richieste dall'utente dopo aver visto il comportamento
--  reale dello svincolo:
--
--  1. Un giocatore appena svincolato tornava nel pool generico e doveva
--     aspettare di essere ripescato a caso dal sorteggio giornaliero, in
--     concorrenza con tutti gli altri per i soliti 5 (o 10) posti per
--     ruolo — poteva non ricomparire per giorni, e se ricompariva
--     occupava uno slot che sarebbe toccato a qualcun altro. Ora entra in
--     una coda (private.rilasci_in_coda) e la prossima estrazione lo
--     inserisce SEMPRE, IN PIU' rispetto alla quota normale: se escono 5
--     centrocampisti e una squadra ne svincola uno, la prossima tornata ne
--     ha 6. Se il mercato e' gia' aperto (una tornata e' in corso) non si
--     aggiunge a quella — chi ha gia' fatto offerte non lo saprebbe —
--     aspetta la prossima, che e' comunque la primissima occasione utile.
--
--  2. public.svincola_giocatore addebitava ancora una quota in contanti
--     per le giornate rimanenti della stagione (private.
--     ingaggio_residuo_stagione), pensata per il vecchio modello a rate.
--     In un'economia a tetto salariale svincolare libera spazio
--     immediatamente, punto: non c'e' nessuna "quota da non rimborsare"
--     perche' non c'e' nessuna cassa a cui riferirla.
-- ============================================================

create table if not exists private.rilasci_in_coda (
  league_id  bigint not null references public.leagues(id) on delete cascade,
  player_id  bigint not null references public.players(id),
  creato_il  timestamptz not null default now(),
  primary key (league_id, player_id)
);

comment on table private.rilasci_in_coda is
  'Giocatori appena svincolati in attesa della prossima estrazione: entrano garantiti, in piu'' rispetto alla quota per ruolo (docs/decisioni-economia.md).';

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

  select min(f.giornata) into v_prossima from public.fixtures f
  where f.league_id = v_lega.id and f.stato = 'programmata';

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

  update public.player_instances set team_id = null,
    ritirato = case when v_istanza.ritiro_annunciato then true else ritirato end
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
      else ' non fa piu'' parte della tua rosa. Torna nel mercato degli svincolati.' end) || v_nota,
    jsonb_build_object('player_instance_id', v_istanza.id, 'player_id', v_istanza.player_id)
  );
  return v_istanza;
end;
$function$;

CREATE OR REPLACE FUNCTION private.estrai_svincolati_lega(p_league_id bigint, p_giorno date)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_lega      public.leagues;
  v_per_ruolo integer;
  v_tornata   integer;
  v_creati    integer := 0;
  v_dalla_coda integer := 0;
  v_asta      record;
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
    select p.id, private.macro_ruolo(p.posizioni) as macro
    from public.players p
    where p.disponibile_estrazione
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
      and not exists (
        select 1 from public.offseason_spins s
        where s.league_id = p_league_id and s.player_id = p.id and s.stato = 'proposto'
      )
      -- I rilasci in coda non concorrono ai posti del sorteggio: entrano
      -- extra piu' sotto, garantiti.
      and not exists (
        select 1 from private.rilasci_in_coda rc
        where rc.league_id = p_league_id and rc.player_id = p.id
      )
  ), ranked as (
    select id, macro, row_number() over (partition by macro order by random()) as rn from disponibili
  ), scelti as (
    select id from ranked where rn <= v_per_ruolo
  )
  insert into public.free_agent_auctions
    (league_id, giorno, player_id, ingaggio_teorico, origine, tornata)
  select p_league_id, p_giorno, p.id,
         private.ingaggio_teorico(p.overall, p.eta), 'estrazione', v_tornata
  from public.players p join scelti s on s.id = p.id;

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
$function$;

create or replace function public.svincola_giocatore(p_instance_id bigint)
returns public.player_instances
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- Economia a tetto salariale (docs/decisioni-economia.md §2, §4): non
  -- esiste piu' nessuna quota da "non rimborsare". Svincolare, in qualsiasi
  -- momento della stagione, libera immediatamente lo spazio salariale del
  -- contratto: e' l'intero punto di avere un tetto invece di una cassa.
  -- Prima di questa modifica la funzione calcolava una quota residua in
  -- contanti (private.ingaggio_residuo_stagione) pensata per il vecchio
  -- modello a rate: qui non ha piu' senso, ne' come addebito ne' come
  -- concetto.
  --
  -- La funzione resta come wrapper — non e' stata fusa con
  -- svincola_giocatore_cassa_legacy — solo per non dover cambiare il nome
  -- dell'RPC che il frontend gia' chiama.
  return public.svincola_giocatore_cassa_legacy(p_instance_id);
end;
$$;

revoke all on function public.svincola_giocatore(bigint) from public, anon;
grant execute on function public.svincola_giocatore(bigint) to authenticated;
