-- ============================================================
--  MERCATO A SCELTE: I TRE PUNTI APERTI DI §7
--  docs/decisioni-draft-picks.md §7, deciso il 28 agosto 2026
--
--  1. Squadre PC: partecipano con una logica automatica (non sofisticata,
--     stesso spirito di proposte_mercato_squadre_pc — "il migliore overall
--     disponibile", non una strategia raffinata).
--  2. Squadra rimossa: una sua scelta 'futura' (posizione non ancora
--     assegnata) si annulla, non nasce mai.
--  3. Regola Stepien in stile NBA: non si puo' cedere la propria scelta
--     d'origine per due stagioni consecutive nella stessa finestra.
-- ============================================================

-- ------------------------------------------------------------
--  1. Preferenze automatiche delle squadre PC
--
--  Per ogni scelta 'determinata' di proprieta' di una squadra PC in una
--  finestra ancora aperta, senza preferenze gia' sottomesse: prende i
--  migliori N overall del pool (N = la propria posizione). Scrive
--  direttamente la tabella invece di richiamare
--  public.salva_preferenze_scelta, che pretende un utente autenticato
--  (auth.uid()) — qui e' il sistema ad agire, non c'e' nessuno loggato.
-- ------------------------------------------------------------
create or replace function private.preferenze_squadre_pc(
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
  v_scelta record;
  v_lista bigint[];
  v_fatte integer := 0;
begin
  for v_scelta in
    select sd.id, sd.posizione
    from public.scelte_draft sd
    join public.teams t on t.id = sd.team_proprietario_id
    where sd.league_id = p_league_id and sd.stagione = p_stagione and sd.finestra = p_finestra
      and sd.stato = 'determinata' and t.controllata_da_pc
      and not exists (select 1 from public.scelte_preferenze pr where pr.scelta_id = sd.id)
  loop
    select array_agg(x.player_id) into v_lista
    from (
      select sp.player_id
      from public.scelte_pool sp
      join public.players p on p.id = sp.player_id
      where sp.league_id = p_league_id and sp.stagione = p_stagione and sp.finestra = p_finestra
      order by p.overall desc, sp.player_id
      limit v_scelta.posizione
    ) x;

    if v_lista is not null then
      insert into public.scelte_preferenze (scelta_id, ordine, player_id)
      select v_scelta.id, i::smallint, v_lista[i]
      from generate_series(1, cardinality(v_lista)) as i
      on conflict do nothing;
      v_fatte := v_fatte + 1;
    end if;
  end loop;
  return v_fatte;
end;
$$;

comment on function private.preferenze_squadre_pc(bigint, smallint, text) is
  'Preferenze automatiche delle squadre PC per una finestra: i migliori overall del pool, fino alla propria posizione. Non e'' una strategia raffinata (docs/decisioni-draft-picks.md §7).';

revoke all on function private.preferenze_squadre_pc(bigint, smallint, text) from public, anon, authenticated;
grant execute on function private.preferenze_squadre_pc(bigint, smallint, text) to service_role;

-- Aggancio nel cron: ad ogni giro, riempie le preferenze PC mancanti per
-- tutte le finestre ancora aperte (svelate, non risolte) — non solo quelle
-- appena svelate, cosi' recupera anche le finestre gia' in corso.
create or replace function private.avanza_finestre_scelte()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
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
$$;

-- ------------------------------------------------------------
--  2. Squadra rimossa: le sue scelte 'futura' si annullano
--
--  Solo 'futura' (posizione non ancora assegnata): una scelta
--  'determinata' e' gia' un impegno reale della stagione in corso, non e'
--  "non ancora nata". Stesso blocco che gia' gestisce gli altri effetti
--  della rimozione (trade_proposals, player_instances, teams.attiva).
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.prepara_offseason(p_league_id bigint, p_squadre_rimosse bigint[] DEFAULT '{}'::bigint[], p_posti_nuovi smallint DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_user uuid := (select auth.uid());
  v_lega public.leagues;
  v_offseason public.offseasons;
  v_attive integer;
  v_rimosse integer;
  v_target integer;
  v_team record;
  v_player record;
  v_eta smallint;
  v_sponsor bigint;
  v_premi_partita bigint;
  v_partecipazione bigint;
  v_accreditato bigint;
  v_ritirati integer := 0;
begin
  if v_user is null then
    raise exception using errcode = '42501', message = 'Devi accedere per aprire l''off-season.';
  end if;

  select * into v_lega from public.leagues where id = p_league_id for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Lega non trovata.';
  end if;
  if v_lega.admin_id <> v_user then
    raise exception using errcode = '42501', message = 'Solo l''admin può aprire l''off-season.';
  end if;
  if v_lega.stato <> 'conclusa' or v_lega.fase_carriera <> 'normale' then
    raise exception using errcode = '55000', message = 'L''off-season è disponibile soltanto dopo una stagione conclusa.';
  end if;
  if coalesce(p_posti_nuovi, 0) not between 0 and 16 then
    raise exception using errcode = '22023', message = 'Numero di nuovi posti non valido.';
  end if;
  if cardinality(coalesce(p_squadre_rimosse, '{}'::bigint[])) <>
     (select count(distinct id) from unnest(coalesce(p_squadre_rimosse, '{}'::bigint[])) x(id)) then
    raise exception using errcode = '22023', message = 'La lista delle squadre rimosse contiene duplicati.';
  end if;
  if exists (
    select 1 from unnest(coalesce(p_squadre_rimosse, '{}'::bigint[])) x(id)
    left join public.teams t on t.id = x.id and t.league_id = p_league_id and t.attiva
    where t.id is null
  ) then
    raise exception using errcode = '22023', message = 'Una squadra da rimuovere non appartiene alla lega o è già inattiva.';
  end if;
  if exists (
    select 1 from public.teams
    where id = any(coalesce(p_squadre_rimosse, '{}'::bigint[])) and user_id = v_lega.admin_id
  ) then
    raise exception using errcode = '22023', message = 'L''admin non può rimuovere la propria squadra.';
  end if;

  select count(*) into v_attive from public.teams where league_id = p_league_id and attiva;
  v_rimosse := cardinality(coalesce(p_squadre_rimosse, '{}'::bigint[]));
  v_target := v_attive - v_rimosse + coalesce(p_posti_nuovi, 0);
  if v_target not between 4 and 20 then
    raise exception using errcode = '22023', message = 'La prossima stagione deve avere da 4 a 20 squadre.';
  end if;

  insert into public.offseasons (league_id, stagione_da, stagione_a, scade_il, posti_nuovi)
  values (p_league_id, v_lega.stagione_corrente, v_lega.stagione_corrente + 1,
          ((now() at time zone 'Europe/Rome') + interval '7 days') at time zone 'Europe/Rome',
          coalesce(p_posti_nuovi, 0))
  returning * into v_offseason;

  if v_rimosse > 0 then
    update public.trade_proposals
    set stato = 'scaduta', risolta_il = now()
    where league_id = p_league_id and stato = 'in_attesa'
      and (da_team_id = any(p_squadre_rimosse) or a_team_id = any(p_squadre_rimosse));

    update public.player_instances
    set team_id = null
    where league_id = p_league_id and team_id = any(p_squadre_rimosse);

    -- Mercato a scelte: le scelte non ancora "nate" di chi esce dalla lega
    -- si annullano, non hanno piu' senso senza una squadra che le abbia
    -- guadagnate (docs/decisioni-draft-picks.md §7, deciso il 28 agosto).
    -- Solo 'futura': una 'determinata' e' gia' un impegno di questa
    -- transizione, non viene toccata qui.
    delete from public.scelte_draft
    where league_id = p_league_id
      and team_origine_id = any(p_squadre_rimosse)
      and stato = 'futura';

    update public.teams
    set attiva = false, uscita_stagione = v_lega.stagione_corrente
    where league_id = p_league_id and id = any(p_squadre_rimosse);
  end if;

  v_sponsor := round((v_lega.budget_iniziale * 0.20)::numeric / 100000) * 100000;
  -- Premio di partecipazione (design §10.7): uguale per tutte, la posizione
  -- finale non lo tocca piu'. Il denaro differenziato si vince nel playout.
  v_partecipazione := round((v_lega.budget_iniziale * 0.15)::numeric / 100000) * 100000;

  for v_team in
    select t.id, t.user_id, t.nome, t.budget,
           coalesce(s.vittorie, 0) vittorie, coalesce(s.pareggi, 0) pareggi,
           coalesce(s.sconfitte, 0) sconfitte, coalesce(s.posizione, v_attive) posizione
    from public.teams t
    left join public.seasons se on se.league_id = t.league_id and se.numero = v_lega.stagione_corrente
    left join public.standings s on s.season_id = se.id and s.team_id = t.id
    where t.league_id = p_league_id and t.attiva
    order by t.id
    for update of t
  loop
    v_premi_partita := round((v_lega.budget_iniziale::numeric
      * (0.54 * v_team.vittorie + 0.27 * v_team.pareggi + 0.135 * v_team.sconfitte)
      / greatest(v_lega.partite_per_squadra, 1)) / 100000) * 100000;
    v_accreditato := v_sponsor + v_premi_partita + v_partecipazione;

    update public.teams set budget = budget + v_accreditato where id = v_team.id;
    if v_premi_partita <> 0 then
      insert into public.transactions(league_id, team_id, tipo, importo, descrizione, saldo_dopo)
      values (p_league_id, v_team.id, 'premi_partite', v_premi_partita,
              'Premi partita stagione ' || v_lega.stagione_corrente,
              (select budget from public.teams where id = v_team.id));
    end if;
    if v_partecipazione <> 0 then
      insert into public.transactions(league_id, team_id, tipo, importo, descrizione, saldo_dopo)
      values (p_league_id, v_team.id, 'premio_partecipazione', v_partecipazione,
              'Premio di partecipazione stagione ' || v_lega.stagione_corrente,
              (select budget from public.teams where id = v_team.id));
    end if;
    if v_sponsor <> 0 then
      insert into public.transactions(league_id, team_id, tipo, importo, descrizione, saldo_dopo)
      values (p_league_id, v_team.id, 'sponsor', v_sponsor,
              'Sponsor stagione ' || v_offseason.stagione_a,
              (select budget from public.teams where id = v_team.id));
    end if;
  end loop;

  for v_player in
    select pi.id, pi.player_id, p.nome, t.user_id
    from public.player_instances pi
    join public.players p on p.id = pi.player_id
    join public.teams t on t.id = pi.team_id and t.attiva
    where pi.league_id = p_league_id and pi.ritiro_annunciato and not pi.ritirato
  loop
    update public.player_instances
    set team_id = null, ritirato = true, ritiro_annunciato = false
    where id = v_player.id;
    insert into public.retired_players(league_id, player_id, stagione)
    values (p_league_id, v_player.player_id, v_lega.stagione_corrente)
    on conflict do nothing;
    v_ritirati := v_ritirati + 1;
    perform private.notifica(v_player.user_id, p_league_id, 'sistema',
      v_player.nome || ' si ritira',
      'Il ritiro annunciato a inizio stagione e'' ora effettivo: la carriera termina qui.',
      jsonb_build_object('player_instance_id', v_player.id));
  end loop;

  -- La progressione OVR è stata applicata ai quattro checkpoint; qui età e
  -- recupero vengono portati alla nuova stagione senza un quinto aggiornamento.
  for v_player in
    select pi.id, pi.eta_corrente
    from public.player_instances pi
    join public.teams t on t.id = pi.team_id and t.attiva
    where pi.league_id = p_league_id and not pi.ritirato
    order by pi.id
    for update of pi
  loop
    v_eta := least(45, v_player.eta_corrente + 1);
    update public.player_instances
    set eta_corrente = v_eta,
        condizione = 100,
        infortunato_fino_a = 0,
        progressione_residuo = 0
    where id = v_player.id;
  end loop;


  update public.leagues
  set n_squadre = v_target,
      stato = 'stagione',
      fase_carriera = 'offseason',
      offseason_fine = v_offseason.scade_il
  where id = p_league_id;

  return jsonb_build_object(
    'league_id', p_league_id,
    'offseason_id', v_offseason.id,
    'stagione_a', v_offseason.stagione_a,
    'scade_il', v_offseason.scade_il,
    'squadre_attese', v_target,
    'posti_nuovi', p_posti_nuovi,
    'ritirati', v_ritirati
  );
end;
$function$;

-- ------------------------------------------------------------
--  3. Regola Stepien in stile NBA
--
--  Non si puo' cedere la propria scelta d'origine (team_origine_id =
--  se stessi) per due stagioni consecutive nella stessa finestra.
--  Guarda solo le scelte ancora "vive" (futura o determinata): una gia'
--  esercitata o andata a vuoto e' storia, non lascia piu' un buco da
--  evitare.
-- ------------------------------------------------------------
create or replace function private.viola_regola_stepien(
  p_team_id bigint,
  p_scelte_cedute bigint[]
)
returns boolean
language sql
stable
set search_path = ''
as $$
  with proprie as (
    select stagione, finestra,
      (team_proprietario_id <> team_origine_id or id = any(p_scelte_cedute)) as ceduta
    from public.scelte_draft
    where team_origine_id = p_team_id
      and stato in ('futura', 'determinata')
  ), coppie as (
    select a.finestra, a.ceduta as ceduta_a, b.ceduta as ceduta_b
    from proprie a
    join proprie b on b.finestra = a.finestra and b.stagione = a.stagione + 1
  )
  select coalesce(bool_or(ceduta_a and ceduta_b), false) from coppie
$$;

comment on function private.viola_regola_stepien(bigint, bigint[]) is
  'Vero se, dopo aver ceduto p_scelte_cedute, la squadra resterebbe senza la propria scelta d''origine in due stagioni consecutive nella stessa finestra (regola Stepien, docs/decisioni-draft-picks.md §7).';

revoke all on function private.viola_regola_stepien(bigint, bigint[]) from public, anon;
grant execute on function private.viola_regola_stepien(bigint, bigint[]) to authenticated, service_role;

-- proponi_scambio: controllo su chi propone (v_mia cede v_s_off)
create or replace function public.proponi_scambio(
  p_a_team_id bigint,
  p_giocatori_offerti bigint[] default '{}'::bigint[],
  p_giocatori_richiesti bigint[] default '{}'::bigint[],
  p_scelte_offerte bigint[] default '{}'::bigint[],
  p_scelte_richieste bigint[] default '{}'::bigint[],
  p_messaggio text default null::text
) returns public.trade_proposals
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_utente uuid := (select auth.uid());
  v_dest public.teams;
  v_mia public.teams;
  v_lega public.leagues;
  v_g_off bigint[] := coalesce(p_giocatori_offerti, '{}');
  v_g_ric bigint[] := coalesce(p_giocatori_richiesti, '{}');
  v_s_off bigint[] := coalesce(p_scelte_offerte, '{}');
  v_s_ric bigint[] := coalesce(p_scelte_richieste, '{}');
  v_n integer;
  v_scadenza timestamptz;
  v_proposta public.trade_proposals;
  v_utente_dest uuid;
begin
  if v_utente is null then
    raise exception using errcode = '42501', message = 'Devi accedere per usare il mercato.';
  end if;
  select * into v_dest from public.teams where id = p_a_team_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Squadra destinataria inesistente.';
  end if;
  select * into v_mia from public.teams where league_id = v_dest.league_id and user_id = v_utente;
  if not found then
    raise exception using errcode = '42501', message = 'Non partecipi a questa lega.';
  end if;
  if v_mia.id = v_dest.id then
    raise exception using errcode = '22023', message = 'Non puoi proporre uno scambio a te stesso.';
  end if;
  select * into v_lega from public.leagues where id = v_dest.league_id;
  if v_lega.stato <> 'stagione' or not private.mercato_aperto_lega(v_lega.id) then
    raise exception using errcode = '55000', message = 'Il mercato e'' chiuso.';
  end if;

  if cardinality(v_g_off) + cardinality(v_g_ric) + cardinality(v_s_off) + cardinality(v_s_ric) = 0 then
    raise exception using errcode = '22023', message = 'Una proposta deve contenere almeno un giocatore o una scelta.';
  end if;

  if cardinality(array(select distinct unnest(v_g_off))) <> cardinality(v_g_off)
     or cardinality(array(select distinct unnest(v_g_ric))) <> cardinality(v_g_ric)
     or v_g_off && v_g_ric then
    raise exception using errcode = '22023', message = 'Un giocatore compare due volte nella proposta.';
  end if;
  if cardinality(array(select distinct unnest(v_s_off))) <> cardinality(v_s_off)
     or cardinality(array(select distinct unnest(v_s_ric))) <> cardinality(v_s_ric)
     or v_s_off && v_s_ric then
    raise exception using errcode = '22023', message = 'Una scelta compare due volte nella proposta.';
  end if;

  select count(*) into v_n from public.player_instances
  where id = any(v_g_off) and team_id = v_mia.id and league_id = v_lega.id;
  if v_n <> cardinality(v_g_off) then
    raise exception using errcode = '22023', message = 'Stai offrendo un giocatore che non e'' tuo.';
  end if;
  select count(*) into v_n from public.player_instances
  where id = any(v_g_ric) and team_id = v_dest.id and league_id = v_lega.id;
  if v_n <> cardinality(v_g_ric) then
    raise exception using errcode = '22023', message = 'Stai chiedendo un giocatore che non e'' di quella squadra.';
  end if;
  if exists (select 1 from public.player_instances where id = any(v_g_off || v_g_ric) and ritiro_annunciato) then
    raise exception using errcode = '55000', message = 'Uno dei giocatori coinvolti ha annunciato il ritiro.';
  end if;

  -- Una scelta si offre solo finche' non e' stata esercitata: 'usata' e
  -- 'vuota' sono gia' storia, non piu' un asset.
  select count(*) into v_n from public.scelte_draft
  where id = any(v_s_off) and team_proprietario_id = v_mia.id and league_id = v_lega.id
    and stato in ('futura', 'determinata');
  if v_n <> cardinality(v_s_off) then
    raise exception using errcode = '22023', message = 'Stai offrendo una scelta che non possiedi o gia'' esercitata.';
  end if;
  select count(*) into v_n from public.scelte_draft
  where id = any(v_s_ric) and team_proprietario_id = v_dest.id and league_id = v_lega.id
    and stato in ('futura', 'determinata');
  if v_n <> cardinality(v_s_ric) then
    raise exception using errcode = '22023', message = 'Stai chiedendo una scelta che quella squadra non possiede o gia'' esercitata.';
  end if;

  -- Regola Stepien: nessuna delle due squadre puo' restare senza la
  -- propria scelta d'origine in due stagioni consecutive della stessa
  -- finestra (docs/decisioni-draft-picks.md §7).
  if cardinality(v_s_off) > 0 and private.viola_regola_stepien(v_mia.id, v_s_off) then
    raise exception using errcode = '22023',
      message = 'Questo scambio ti lascerebbe senza una tua scelta d''origine per due stagioni consecutive nella stessa finestra (regola Stepien).';
  end if;
  if cardinality(v_s_ric) > 0 and private.viola_regola_stepien(v_dest.id, v_s_ric) then
    raise exception using errcode = '22023',
      message = 'Questo scambio lascerebbe ' || v_dest.nome || ' senza una propria scelta d''origine per due stagioni consecutive nella stessa finestra (regola Stepien).';
  end if;

  v_scadenza := (date_trunc('day', now() at time zone 'Europe/Rome') + interval '21 hours') at time zone 'Europe/Rome';
  if v_scadenza <= now() then v_scadenza := v_scadenza + interval '1 day'; end if;

  insert into public.trade_proposals(
    league_id, da_team_id, a_team_id,
    giocatori_offerti, giocatori_richiesti, scelte_offerte, scelte_richieste,
    messaggio, scade_il
  ) values (
    v_lega.id, v_mia.id, v_dest.id,
    v_g_off, v_g_ric, v_s_off, v_s_ric,
    nullif(btrim(coalesce(p_messaggio, '')), ''), v_scadenza
  ) returning * into v_proposta;

  select user_id into v_utente_dest from public.teams where id = v_dest.id;
  if v_utente_dest is not null then
    perform private.notifica(v_utente_dest, v_lega.id, 'mercato_proposta', 'Proposta di mercato da ' || v_mia.nome,
      'Proposta di mercato: scade alle 21:00.', jsonb_build_object('proposta_id', v_proposta.id));
  end if;
  return v_proposta;
end;
$$;

-- rispondi_a_proposta: stesso controllo, su entrambi i lati, all'accettazione
create or replace function public.rispondi_a_proposta(p_proposta_id bigint, p_accetta boolean)
returns public.trade_proposals
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_utente     uuid := (select auth.uid());
  v_p          public.trade_proposals;
  v_lega       public.leagues;
  v_da         public.teams;
  v_a          public.teams;
  v_stagione   smallint;
  v_n          integer;
  v_rosa_da    integer;
  v_rosa_a     integer;
  v_prossima   integer;
  v_tutti      bigint[];
  v_form_tolte integer := 0;
  v_nota       text := '';
  v_delta_da   bigint;
  v_delta_a    bigint;
begin
  if v_utente is null then
    raise exception using errcode = '42501', message = 'Devi accedere per usare il mercato.';
  end if;

  select * into v_p from public.trade_proposals where id = p_proposta_id for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Proposta inesistente.';
  end if;
  if not (select private.e_mia_squadra(v_p.a_team_id)) then
    raise exception using errcode = '42501', message = 'Questa proposta non e'' indirizzata a te.';
  end if;
  if v_p.stato <> 'in_attesa' then
    raise exception using errcode = '55000', message = 'Questa proposta e'' gia'' stata risolta.';
  end if;
  if now() >= v_p.scade_il then
    raise exception using errcode = '55000', message = 'Questa proposta e'' scaduta.';
  end if;

  if not coalesce(p_accetta, false) then
    update public.trade_proposals set stato = 'rifiutata', risolta_il = now()
    where id = v_p.id
    returning * into v_p;

    perform private.notifica(
      (select user_id from public.teams where id = v_p.da_team_id),
      v_p.league_id, 'mercato_esito', 'Proposta rifiutata',
      (select nome from public.teams where id = v_p.a_team_id) || ' ha rifiutato la tua proposta.',
      jsonb_build_object('proposta_id', v_p.id)
    );
    return v_p;
  end if;

  if not private.mercato_aperto_lega(v_p.league_id) then
    raise exception using errcode = '55000',
      message = 'Il mercato e'' chiuso: si conclude dalle 23:30 alle 21:00, o quando l''admin lo apre.';
  end if;

  select * into v_lega from public.leagues where id = v_p.league_id;

  -- Lock deterministico sulle due squadre: evita deadlock fra due
  -- accettazioni concorrenti che coinvolgono la stessa coppia.
  perform 1 from public.teams where id in (v_p.da_team_id, v_p.a_team_id) order by id for update;
  select * into v_da from public.teams where id = v_p.da_team_id;
  select * into v_a  from public.teams where id = v_p.a_team_id;

  select count(*) into v_n from public.player_instances
  where id = any(v_p.giocatori_offerti) and team_id = v_da.id;
  if v_n <> cardinality(v_p.giocatori_offerti) then
    raise exception using errcode = '55000',
      message = 'Un giocatore offerto non e'' piu'' in quella rosa: la proposta non e'' piu'' valida.';
  end if;
  select count(*) into v_n from public.player_instances
  where id = any(v_p.giocatori_richiesti) and team_id = v_a.id;
  if v_n <> cardinality(v_p.giocatori_richiesti) then
    raise exception using errcode = '55000',
      message = 'Un giocatore richiesto non e'' piu'' nella tua rosa: la proposta non e'' piu'' valida.';
  end if;
  if exists (
    select 1 from public.player_instances
    where id = any(v_p.giocatori_offerti || v_p.giocatori_richiesti) and ritiro_annunciato
  ) then
    raise exception using errcode = '55000',
      message = 'Uno dei giocatori coinvolti ha annunciato il ritiro: la proposta non e'' piu'' valida.';
  end if;

  -- Stesso controllo per le scelte: puo' essere stata gia' esercitata, o
  -- rigirata altrove, nel tempo fra la proposta e questa risposta.
  select count(*) into v_n from public.scelte_draft
  where id = any(v_p.scelte_offerte) and team_proprietario_id = v_da.id and stato in ('futura', 'determinata');
  if v_n <> cardinality(v_p.scelte_offerte) then
    raise exception using errcode = '55000',
      message = 'Una scelta offerta non e'' piu'' disponibile: la proposta non e'' piu'' valida.';
  end if;
  select count(*) into v_n from public.scelte_draft
  where id = any(v_p.scelte_richieste) and team_proprietario_id = v_a.id and stato in ('futura', 'determinata');
  if v_n <> cardinality(v_p.scelte_richieste) then
    raise exception using errcode = '55000',
      message = 'Una scelta richiesta non e'' piu'' disponibile: la proposta non e'' piu'' valida.';
  end if;

  -- Regola Stepien, ricontrollata: lo stato delle scelte puo'' essere
  -- cambiato fra la proposta e questa risposta (altri scambi nel
  -- frattempo).
  if cardinality(v_p.scelte_offerte) > 0 and private.viola_regola_stepien(v_da.id, v_p.scelte_offerte) then
    raise exception using errcode = '22023',
      message = 'Questo scambio lascerebbe ' || v_da.nome || ' senza una propria scelta d''origine per due stagioni consecutive nella stessa finestra (regola Stepien): la proposta non e'' piu'' valida.';
  end if;
  if cardinality(v_p.scelte_richieste) > 0 and private.viola_regola_stepien(v_a.id, v_p.scelte_richieste) then
    raise exception using errcode = '22023',
      message = 'Questo scambio ti lascerebbe senza una tua scelta d''origine per due stagioni consecutive nella stessa finestra (regola Stepien).';
  end if;

  select count(*) into v_rosa_da from public.player_instances where team_id = v_da.id;
  select count(*) into v_rosa_a  from public.player_instances where team_id = v_a.id;
  v_rosa_da := v_rosa_da - cardinality(v_p.giocatori_offerti) + cardinality(v_p.giocatori_richiesti);
  v_rosa_a  := v_rosa_a  - cardinality(v_p.giocatori_richiesti) + cardinality(v_p.giocatori_offerti);
  if v_rosa_da > private.rosa_massima() or v_rosa_a > private.rosa_massima() then
    raise exception using errcode = '22023', message = 'Lo scambio porterebbe una rosa oltre i 30 giocatori.';
  end if;
  if v_rosa_da < private.rosa_minima() or v_rosa_a < private.rosa_minima() then
    raise exception using errcode = '22023', message = 'Lo scambio lascerebbe una rosa sotto i 21 giocatori.';
  end if;

  -- Trasferimenti: prima i giocatori (i trigger su player_instances
  -- gestiscono liste e rinnovi in corso), poi le scelte.
  update public.player_instances set team_id = v_a.id  where id = any(v_p.giocatori_offerti);
  update public.player_instances set team_id = v_da.id where id = any(v_p.giocatori_richiesti);
  update public.scelte_draft set team_proprietario_id = v_a.id,  aggiornata_il = now() where id = any(v_p.scelte_offerte);
  update public.scelte_draft set team_proprietario_id = v_da.id, aggiornata_il = now() where id = any(v_p.scelte_richieste);

  -- Capienza: dopo aver spostato i giocatori, il monte di ciascuna
  -- squadra include gia' l'effetto dello scambio. Le scelte non vi
  -- contribuiscono: non hanno un ingaggio proprio finche' non si
  -- esercitano.
  v_stagione := private.stagione_contratto(v_p.league_id);
  if private.monte_ingaggi(v_da.id, v_stagione) + private.ingaggi_impegnati_aste(v_da.id, null) > v_lega.tetto_ingaggi then
    raise exception using errcode = '22023',
      message = 'Questo scambio porterebbe ' || v_da.nome || ' oltre il tetto ingaggi.';
  end if;
  if private.monte_ingaggi(v_a.id, v_stagione) + private.ingaggi_impegnati_aste(v_a.id, null) > v_lega.tetto_ingaggi then
    raise exception using errcode = '22023',
      message = 'Questo scambio ti porterebbe oltre il tetto ingaggi.';
  end if;

  select min(f.giornata) into v_prossima
  from public.fixtures f where f.league_id = v_lega.id and f.stato = 'programmata';
  v_tutti := v_p.giocatori_offerti || v_p.giocatori_richiesti;
  if v_prossima is not null and cardinality(v_tutti) > 0 then
    delete from public.lineups
    where league_id = v_lega.id
      and team_id in (v_da.id, v_a.id)
      and giornata >= v_prossima
      and (titolari && v_tutti or panchina && v_tutti or tribuna && v_tutti);
    get diagnostics v_form_tolte = row_count;
  end if;
  if v_form_tolte > 0 then
    v_nota := ' Controlla la formazione: era schierato un giocatore coinvolto.';
  end if;

  -- Registro: non piu' movimento di cassa, ma di spazio salariale. Zero
  -- e' un esito legittimo (scambio di picks pure, o pari valore) e non
  -- genera riga: importo <> 0 e' un vincolo della tabella.
  select coalesce(sum(ingaggio), 0) into v_delta_da
  from public.player_instances where id = any(v_p.giocatori_richiesti);
  v_delta_da := v_delta_da - coalesce((select sum(ingaggio) from public.player_instances where id = any(v_p.giocatori_offerti)), 0);
  v_delta_a := -v_delta_da;

  if v_delta_da <> 0 then
    insert into public.transactions (league_id, team_id, tipo, importo, descrizione, saldo_dopo)
    values (v_lega.id, v_da.id, 'mercato_scambio', v_delta_da, 'Scambio con ' || v_a.nome, v_da.budget);
  end if;
  if v_delta_a <> 0 then
    insert into public.transactions (league_id, team_id, tipo, importo, descrizione, saldo_dopo)
    values (v_lega.id, v_a.id, 'mercato_scambio', v_delta_a, 'Scambio con ' || v_da.nome, v_a.budget);
  end if;

  update public.trade_proposals set stato = 'accettata', risolta_il = now()
  where id = v_p.id
  returning * into v_p;

  perform private.notifica(v_da.user_id, v_lega.id, 'mercato_esito', 'Scambio concluso con ' || v_a.nome,
    'La tua proposta e'' stata accettata.' || v_nota, jsonb_build_object('proposta_id', v_p.id));
  perform private.notifica(v_a.user_id, v_lega.id, 'mercato_esito', 'Scambio concluso con ' || v_da.nome,
    'Hai accettato la proposta.' || v_nota, jsonb_build_object('proposta_id', v_p.id));

  return v_p;
end;
$$;
