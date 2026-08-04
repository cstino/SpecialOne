-- ============================================================
--  RITIRO DEI GIOCATORI
--  Decisione dell'utente, 4 agosto 2026.
--
--  Sostituisce il ritiro "a evento unico" di prepara_offseason (tirato e
--  eseguito nello stesso istante, design §10.3 vecchia versione) con un
--  meccanismo a due fasi:
--
--  1. ANNUNCIO, a inizio stagione (finalizza_offseason): si tira il dado per
--     ogni giocatore di rosa >= 34 anni con la nuova tabella di probabilita'.
--     Chi lo annuncia gioca comunque tutta la stagione appena iniziata, ma
--     non puo' piu' essere ceduto in trattativa.
--  2. USCITA, a fine stagione (prepara_offseason della stagione successiva):
--     chi aveva annunciato viene rimosso per davvero.
--
--  Stesso calcolo anche per i giocatori mai scelti da nessuno: non hanno un
--  player_instances a cui appendere lo stato, quindi l'esito va in una
--  tabella dedicata (retired_players) che funge da lista di esclusione
--  permanente per questa lega. La loro eta' e' derivata (eta_catalogo +
--  stagioni passate in questa lega), perche' il pool degli svincolati non fa
--  mai invecchiare le istanze: pesca sempre fresco dal catalogo.
--
--  Bug di rimbalzo sistemato qui: oggi un giocatore gia' ritirato puo'
--  ricomparire nel mercato, perche' le query di estrazione controllano solo
--  "e' posseduto da qualcuno?", mai ritirato. retired_players diventa il
--  controllo unico, usato ovunque si peschi un pool (draft, estrazione,
--  archivio, spin off-season).
-- ============================================================

-- ------------------------------------------------------------
--  1. Schema
-- ------------------------------------------------------------

alter table public.player_instances
  add column if not exists ritiro_annunciato boolean not null default false;

create table if not exists public.retired_players (
  league_id  bigint  not null references public.leagues (id) on delete cascade,
  player_id  bigint  not null references public.players (id) on delete cascade,
  stagione   integer not null,
  creato_il  timestamptz not null default now(),
  primary key (league_id, player_id)
);

alter table public.retired_players enable row level security;

create policy retired_players_lettura on public.retired_players
  for select to authenticated
  using ((select private.e_membro(league_id)));

-- La RLS filtra le righe, ma senza il GRANT di base authenticated non
-- arriva nemmeno a valutarla (stesso schema di offseasons/contract_renewals).
grant select on public.retired_players to authenticated;

-- ------------------------------------------------------------
--  2. Tabella di probabilita' (sostituisce max(0,(eta-33)*0.12))
-- ------------------------------------------------------------

create or replace function private.probabilita_ritiro(p_eta smallint)
returns numeric
language sql
immutable
set search_path = ''
as $$
  select case
    when p_eta < 34 then 0
    when p_eta = 34 then 0.10
    when p_eta = 35 then 0.20
    when p_eta = 36 then 0.35
    when p_eta = 37 then 0.50
    when p_eta = 38 then 0.65
    when p_eta = 39 then 0.80
    when p_eta = 40 then 0.95
    when p_eta = 41 then 0.99
    else 1.0
  end;
$$;

revoke all on function private.probabilita_ritiro(smallint) from public, anon, authenticated;
grant execute on function private.probabilita_ritiro(smallint) to service_role;

-- ------------------------------------------------------------
--  3. prepara_offseason (fine stagione): finalizza chi aveva annunciato,
--     poi invecchia i sopravvissuti SENZA piu' tirare il dado qui.
-- ------------------------------------------------------------

create or replace function public.prepara_offseason(
  p_league_id bigint,
  p_squadre_rimosse bigint[] default '{}'::bigint[],
  p_posti_nuovi smallint default 0
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
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
  v_ovr smallint;
  v_delta numeric;
  v_richiesta bigint;
  v_min bigint;
  v_max bigint;
  v_renewal_id bigint;
  v_ambizione numeric;
  v_sponsor bigint;
  v_premi_partita bigint;
  v_premio_posizione bigint;
  v_pool numeric;
  v_pesi numeric;
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

  -- Le squadre uscite restano nello storico, ma rosa e mercato vengono chiusi.
  if v_rimosse > 0 then
    update public.trade_proposals
    set stato = 'scaduta', risolta_il = now()
    where league_id = p_league_id and stato = 'in_attesa'
      and (da_team_id = any(p_squadre_rimosse) or a_team_id = any(p_squadre_rimosse));

    update public.player_instances
    set team_id = null
    where league_id = p_league_id and team_id = any(p_squadre_rimosse);

    update public.teams
    set attiva = false, uscita_stagione = v_lega.stagione_corrente
    where league_id = p_league_id and id = any(p_squadre_rimosse);
  end if;

  -- Premi mancanti della stagione appena finita, premio posizione e sponsor
  -- della nuova stagione: servono prima dei rinnovi, quando il budget conta.
  v_sponsor := round((v_lega.budget_iniziale * 0.20)::numeric / 100000) * 100000;
  v_pool := 0.12 * v_lega.budget_iniziale * (v_attive - v_rimosse);
  select sum(power((v_attive - v_rimosse - s.posizione + 1)::numeric, 1.8))
    into v_pesi
  from public.standings s
  join public.seasons se on se.id = s.season_id
  join public.teams t on t.id = s.team_id and t.attiva
  where se.league_id = p_league_id and se.numero = v_lega.stagione_corrente;

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
    v_premio_posizione := case when coalesce(v_pesi, 0) > 0
      then round((v_pool * power((v_attive - v_rimosse - v_team.posizione + 1)::numeric, 1.8) / v_pesi) / 100000) * 100000
      else 0 end;
    v_accreditato := v_sponsor + v_premi_partita + v_premio_posizione;

    update public.teams set budget = budget + v_accreditato where id = v_team.id;
    if v_premi_partita <> 0 then
      insert into public.transactions(league_id, team_id, tipo, importo, descrizione, saldo_dopo)
      values (p_league_id, v_team.id, 'premi_partite', v_premi_partita,
              'Premi partita stagione ' || v_lega.stagione_corrente,
              (select budget from public.teams where id = v_team.id));
    end if;
    if v_premio_posizione <> 0 then
      insert into public.transactions(league_id, team_id, tipo, importo, descrizione, saldo_dopo)
      values (p_league_id, v_team.id, 'premio_classifica', v_premio_posizione,
              'Premio ' || v_team.posizione || '° posto',
              (select budget from public.teams where id = v_team.id));
    end if;
    if v_sponsor <> 0 then
      insert into public.transactions(league_id, team_id, tipo, importo, descrizione, saldo_dopo)
      values (p_league_id, v_team.id, 'sponsor', v_sponsor,
              'Sponsor stagione ' || v_offseason.stagione_a,
              (select budget from public.teams where id = v_team.id));
    end if;
  end loop;

  -- Chi aveva annunciato il ritiro l'anno scorso ha giocato tutta questa
  -- stagione: la carriera finisce davvero adesso, prima di invecchiare
  -- chiunque altro.
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

  -- Invecchiamento e crescita/declino dei sopravvissuti: la UNIQUE
  -- sull'off-season rende questa funzione non ripetibile. Il ritiro non si
  -- decide piu' qui: si annuncia a inizio stagione (finalizza_offseason).
  for v_player in
    select pi.*, p.potential, p.nome, t.user_id
    from public.player_instances pi
    join public.players p on p.id = pi.player_id
    join public.teams t on t.id = pi.team_id and t.attiva
    where pi.league_id = p_league_id and not pi.ritirato
    order by pi.id
    for update of pi
  loop
    v_eta := least(45, v_player.eta_corrente + 1);
    if v_eta <= 22 then
      v_delta := (greatest(v_player.potential, v_player.overall_corrente) - v_player.overall_corrente) * (0.15 + random() * 0.30);
    elsif v_eta <= 26 then
      v_delta := (greatest(v_player.potential, v_player.overall_corrente) - v_player.overall_corrente) * (0.05 + random() * 0.20);
    elsif v_eta <= 31 then
      v_delta := -1 + random() * 2;
    elsif v_eta <= 35 then
      v_delta := -(0.5 + random() * 2);
    else
      v_delta := -(1.5 + random() * 2.5);
    end if;
    v_ovr := greatest(40, least(greatest(v_player.potential, v_player.overall_corrente), round(v_player.overall_corrente + v_delta)))::smallint;

    update public.player_instances
    set eta_corrente = v_eta, overall_corrente = v_ovr,
        condizione = 100, infortunato_fino_a = 0
    where id = v_player.id;
  end loop;

  -- Rendimento relativo nel reparto: percent_rank 0..1 trasformato nel
  -- moltiplicatore 0,85..1,35 previsto dal design.
  for v_player in
    with numeri as (
      select pi.id, pi.team_id, pi.overall_corrente, pi.eta_corrente, pi.ingaggio,
             p.nome, p.posizioni[1] ruolo,
             coalesce(sum(ms.gol * 5 + ms.assist * 3 + ms.minuti::numeric / 900), 0) rendimento
      from public.player_instances pi
      join public.players p on p.id = pi.player_id
      join public.teams t on t.id = pi.team_id and t.attiva
      left join public.match_stats ms on ms.player_instance_id = pi.id
      where pi.league_id = p_league_id and not pi.ritirato
        and pi.contratto_scadenza <= v_lega.stagione_corrente
      group by pi.id, p.nome, p.posizioni[1]
    ), ordinati as (
      select n.*, percent_rank() over (partition by ruolo order by rendimento) percentile
      from numeri n
    )
    select o.*, coalesce(s.posizione, v_attive) posizione
    from ordinati o
    left join public.seasons se on se.league_id = p_league_id and se.numero = v_lega.stagione_corrente
    left join public.standings s on s.season_id = se.id and s.team_id = o.team_id
    order by o.id
  loop
    v_ambizione := case
      when v_player.posizione <= 3 then 0.90
      when v_player.posizione > ceil((v_attive - v_rimosse) * 2.0 / 3.0) then 1.15
      else 1.00 end;
    -- Pavimento: non richiede mai meno di quanto gia' percepisce. Un giocatore
    -- pagato sopra il suo valore teorico (es. aggiudicato caro all'asta) parte
    -- dal suo ingaggio attuale, non dal teorico piu' basso.
    v_richiesta := greatest(500000, v_player.ingaggio, round((private.ingaggio_teorico(v_player.overall_corrente, v_player.eta_corrente)
      * (0.85 + 0.50 * v_player.percentile) * v_ambizione * (0.95 + random() * 0.10)) / 100000) * 100000);
    v_min := greatest(500000, round((v_richiesta * 0.88)::numeric / 100000) * 100000);
    v_max := greatest(v_min, round((v_richiesta * 1.12)::numeric / 100000) * 100000);

    insert into public.contract_renewals(
      offseason_id, league_id, team_id, player_instance_id, richiesta_min, richiesta_max
    ) values (v_offseason.id, p_league_id, v_player.team_id, v_player.id, v_min, v_max)
    returning id into v_renewal_id;
    insert into private.contract_renewal_terms(renewal_id, richiesta_esatta)
    values (v_renewal_id, v_richiesta);
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
$$;

revoke all on function public.prepara_offseason(bigint, bigint[], smallint) from public, anon, authenticated;
grant execute on function public.prepara_offseason(bigint, bigint[], smallint) to authenticated;

-- ------------------------------------------------------------
--  4. finalizza_offseason (inizio stagione): annuncia i nuovi ritiri, sia
--     per la rosa che per i catalogati mai scelti da nessuno.
-- ------------------------------------------------------------

create or replace function private.finalizza_offseason(p_league_id bigint)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
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

  select count(*)::integer into v_attive
  from public.teams where league_id = p_league_id and attiva;
  if v_attive < 4 then
    raise exception using errcode = '55000', message = 'Servono almeno 4 squadre attive per iniziare la stagione.';
  end if;

  -- I posti di espansione non occupati alla scadenza decadono: il calendario
  -- usa le squadre realmente iscritte, senza tenere bloccata tutta la lega.
  update public.leagues set n_squadre = v_attive where id = p_league_id;

  update public.player_instances pi
  set team_id = null
  from public.contract_renewals cr
  where cr.offseason_id = v_off.id
    and cr.player_instance_id = pi.id
    and cr.stato in ('in_attesa', 'controproposta');

  update public.contract_renewals
  set stato = 'scaduto', risolta_il = clock_timestamp()
  where offseason_id = v_off.id and stato in ('in_attesa', 'controproposta');

  -- Uno spin lasciato senza risposta non resta sospeso per sempre: il
  -- giocatore torna semplicemente nel pool degli svincolati.
  update public.offseason_spins
  set stato = 'asta', risolta_il = clock_timestamp()
  where offseason_id = v_off.id and stato = 'proposto';

  for v_team in
    select * from public.teams
    where league_id = p_league_id and attiva
    order by id for update
  loop
    v_aggiunti := array[]::text[];
    v_rilasciati := 0;

    -- Se la rosa attuale non e' sostenibile, si applica l'insolvenza del
    -- design: escono prima gli ingaggi piu' alti finche' restano finanziabili
    -- anche i posti mancanti al minimo di 21.
    loop
      select count(*)::integer, coalesce(sum(ingaggio), 0)::bigint
      into v_rosa, v_ingaggi
      from public.player_instances
      where team_id = v_team.id and not ritirato;

      exit when v_ingaggi + greatest(21 - v_rosa, 0) * 500000 <= v_team.budget;

      select pi.id into v_candidate
      from public.player_instances pi
      where pi.team_id = v_team.id and not pi.ritirato
      order by pi.ingaggio desc, pi.overall_corrente asc, pi.id
      limit 1;
      if not found then
        raise exception using errcode = '55000', message = 'Budget insufficiente per completare la rosa di ' || v_team.nome || '.';
      end if;
      update public.player_instances set team_id = null where id = v_candidate.id;
      v_rilasciati := v_rilasciati + 1;
    end loop;

    select count(*)::integer, coalesce(sum(ingaggio), 0)::bigint
    into v_rosa, v_ingaggi
    from public.player_instances
    where team_id = v_team.id and not ritirato;
    v_da_aggiungere := greatest(21 - v_rosa, 0);

    while v_da_aggiungere > 0 loop
      select p.id as player_id, p.nome, p.overall, p.eta,
             pi.id as instance_id,
             coalesce(pi.ingaggio, private.ingaggio_teorico(p.overall, p.eta))::bigint as ingaggio
      into v_candidate
      from public.players p
      left join public.player_instances pi
        on pi.league_id = p_league_id and pi.player_id = p.id
      where p.campionato = any(v_league.campionati_attivi)
        and (pi.id is null or (pi.team_id is null and not pi.ritirato))
        and not exists (select 1 from public.retired_players rp where rp.league_id = p_league_id and rp.player_id = p.id)
        and coalesce(pi.ingaggio, private.ingaggio_teorico(p.overall, p.eta))
          <= v_team.budget - v_ingaggi - ((v_da_aggiungere - 1) * 500000)
      order by coalesce(pi.ingaggio, private.ingaggio_teorico(p.overall, p.eta)) asc,
               p.overall asc, p.id
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
    if v_team.budget < v_ingaggi then
      raise exception using errcode = '55000', message = 'Budget insufficiente per gli ingaggi di ' || v_team.nome || '.';
    end if;

    update public.draft_team_state
    set stato = 'concluso', aggiornato_il = clock_timestamp()
    where league_id = p_league_id and team_id = v_team.id and stato <> 'concluso';

    update public.teams set budget = budget - v_ingaggi where id = v_team.id;
    insert into public.transactions(league_id, team_id, tipo, importo, descrizione, saldo_dopo)
    values (p_league_id, v_team.id, 'ingaggi_stagione', -v_ingaggi,
            'Ingaggi stagione ' || v_off.stagione_a, v_team.budget - v_ingaggi);

    if cardinality(v_aggiunti) > 0 or v_rilasciati > 0 then
      perform private.notifica(
        v_team.user_id, p_league_id, 'sistema', 'Rosa completata automaticamente',
        case when cardinality(v_aggiunti) > 0
          then cardinality(v_aggiunti) || ' svincolati aggiunti per raggiungere il minimo di 21 giocatori.'
          else 'Rosa riequilibrata automaticamente per rispettare il budget.' end,
        jsonb_build_object('view', 'team', 'aggiunti', cardinality(v_aggiunti), 'rilasciati', v_rilasciati)
      );
    end if;
  end loop;

  update public.offseasons
  set stato = 'conclusa', conclusa_il = clock_timestamp()
  where id = v_off.id;
  update public.leagues
  set stagione_corrente = v_off.stagione_a,
      fase_carriera = 'normale',
      offseason_fine = null,
      stato = 'stagione'
  where id = p_league_id;

  -- Annuncio del ritiro: a inizio stagione (qui), non a fine. Chi lo annuncia
  -- gioca comunque tutta la nuova stagione — la rimozione vera avviene alla
  -- prossima prepara_offseason, non qui.
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

  -- Stesso calcolo per chi non e' mai stato scelto da nessuno: niente
  -- player_instances a cui appendere lo stato, quindi l'esito va nella
  -- tabella dedicata. Eta' derivata: il pool degli svincolati pesca sempre
  -- fresco dal catalogo, non fa mai invecchiare le istanze non possedute.
  insert into public.retired_players(league_id, player_id, stagione)
  select p_league_id, p.id, v_off.stagione_a
  from public.players p
  where p.campionato = any(v_league.campionati_attivi)
    and not exists (
      select 1 from public.player_instances pi
      where pi.league_id = p_league_id and pi.player_id = p.id and pi.team_id is not null
    )
    and not exists (
      select 1 from public.retired_players rp
      where rp.league_id = p_league_id and rp.player_id = p.id
    )
    and (p.eta + (v_off.stagione_a - 1)) >= 34
    and random() < private.probabilita_ritiro(least(45, p.eta + (v_off.stagione_a - 1))::smallint)
  on conflict do nothing;

  v_season := private.inizializza_stagione(p_league_id);

  perform private.notifica(
    t.user_id, p_league_id, 'sistema', 'La nuova stagione e'' iniziata',
    'La prima giornata si giochera'' alle 23:00. Prepara la formazione.',
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
$$;

revoke all on function private.finalizza_offseason(bigint) from public, anon, authenticated;

-- ------------------------------------------------------------
--  5. svincola_giocatore: se aveva gia' annunciato il ritiro, l'uscita e'
--     definitiva (non torna disponibile), non un semplice svincolo.
-- ------------------------------------------------------------

create or replace function public.svincola_giocatore(p_instance_id bigint)
returns public.player_instances
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_utente      uuid := (select auth.uid());
  v_istanza     public.player_instances;
  v_squadra     public.teams;
  v_lega        public.leagues;
  v_giocatore   public.players;
  v_rosa        integer;
  v_portieri    integer;
  v_prossima    integer;
  v_form_tolte  integer := 0;
  v_nota        text := '';
begin
  if v_utente is null then
    raise exception using errcode = '42501', message = 'Devi accedere per svincolare un giocatore.';
  end if;

  -- Prima lettura per individuare la squadra. La riga viene ricontrollata
  -- dopo il lock: fra le due operazioni uno scambio potrebbe averla mossa.
  select * into v_istanza
  from public.player_instances
  where id = p_instance_id;

  if not found then
    raise exception using errcode = 'P0002', message = 'Giocatore inesistente.';
  end if;

  select * into v_squadra
  from public.teams
  where id = v_istanza.team_id
    and user_id = v_utente;

  if not found then
    raise exception using errcode = '42501', message = 'Questo giocatore non appartiene alla tua squadra.';
  end if;

  -- Tutte le operazioni che cambiano una rosa serializzano sulla squadra.
  -- Dopo il lock si ricontrolla la proprieta' dell'istanza.
  perform 1 from public.teams where id = v_squadra.id for update;
  select * into v_istanza
  from public.player_instances
  where id = p_instance_id
    and team_id = v_squadra.id
  for update;

  if not found then
    raise exception using errcode = '55000', message = 'Il giocatore non e'' piu'' nella tua rosa.';
  end if;

  select * into v_lega from public.leagues where id = v_istanza.league_id;
  if v_lega.stato <> 'stagione' then
    raise exception using errcode = '55000', message = 'Puoi svincolare giocatori solo durante la stagione.';
  end if;

  if not private.mercato_aperto() then
    raise exception using errcode = '55000',
      message = 'Il mercato e'' chiuso: puoi svincolare dalle 07:00 alle 21:00.';
  end if;

  -- Si contano direttamente i giocatori che resterebbero, cosi' il controllo
  -- non dipende dal ruolo del giocatore svincolato calcolato a parte.
  select count(*), count(*) filter (where p.posizioni[1] = 'GK')
    into v_rosa, v_portieri
  from public.player_instances pi
  join public.players p on p.id = pi.player_id
  where pi.team_id = v_squadra.id
    and pi.id <> v_istanza.id;

  if v_rosa < private.rosa_minima() then
    raise exception using errcode = '22023',
      message = 'Non puoi scendere sotto i 21 giocatori in rosa.';
  end if;
  if v_portieri < v_lega.portieri_minimi then
    raise exception using errcode = '22023',
      message = 'Non puoi scendere sotto il minimo di portieri della lega.';
  end if;

  select * into v_giocatore from public.players where id = v_istanza.player_id;

  -- Una formazione che contiene il giocatore non rappresenta piu' una scelta
  -- valida dell'utente. Si cancellano solo le giornate ancora da simulare.
  select min(f.giornata) into v_prossima
  from public.fixtures f
  where f.league_id = v_lega.id
    and f.stato = 'programmata';

  if v_prossima is not null then
    delete from public.lineups
    where league_id = v_lega.id
      and team_id = v_squadra.id
      and giornata >= v_prossima
      and (
        titolari && array[v_istanza.id]::bigint[]
        or panchina && array[v_istanza.id]::bigint[]
        or tribuna && array[v_istanza.id]::bigint[]
      );
    get diagnostics v_form_tolte = row_count;
  end if;

  -- Se aveva gia' annunciato il ritiro, lo svincolo non lo rimanda al
  -- mercato: la carriera finisce qui, definitivamente.
  update public.player_instances
  set team_id = null,
      ritirato = case when v_istanza.ritiro_annunciato then true else ritirato end
  where id = v_istanza.id
  returning * into v_istanza;

  if v_istanza.ritiro_annunciato then
    insert into public.retired_players(league_id, player_id, stagione)
    values (v_lega.id, v_istanza.player_id, v_lega.stagione_corrente)
    on conflict do nothing;
  end if;

  if v_form_tolte > 0 then
    v_nota := ' La formazione delle prossime giornate va salvata di nuovo.';
  end if;

  perform private.notifica(
    v_utente,
    v_lega.id,
    'mercato_esito',
    'Giocatore svincolato',
    v_giocatore.nome || (case when v_istanza.ritiro_annunciato
      then ' aveva gia'' annunciato il ritiro: la carriera termina qui, non torna disponibile.'
      else ' non fa piu'' parte della tua rosa.' end) || v_nota,
    jsonb_build_object('player_instance_id', v_istanza.id, 'player_id', v_istanza.player_id)
  );

  return v_istanza;
end;
$$;

revoke all on function public.svincola_giocatore(bigint) from public, anon;
grant execute on function public.svincola_giocatore(bigint) to authenticated;

-- ------------------------------------------------------------
--  6. proponi_scambio / rispondi_a_proposta: chi ha annunciato il ritiro
--     non puo' essere ceduto in nessuna delle due direzioni.
-- ------------------------------------------------------------

create or replace function public.proponi_scambio(
  p_a_team_id           bigint,
  p_giocatori_offerti   bigint[] default '{}',
  p_giocatori_richiesti bigint[] default '{}',
  p_conguaglio          bigint   default 0,
  p_messaggio           text     default null
)
returns public.trade_proposals
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_utente     uuid := (select auth.uid());
  v_dest       public.teams;
  v_mia        public.teams;
  v_lega       public.leagues;
  v_offerti    bigint[] := coalesce(p_giocatori_offerti, '{}');
  v_richiesti  bigint[] := coalesce(p_giocatori_richiesti, '{}');
  v_n          integer;
  v_scadenza   timestamptz;
  v_proposta   public.trade_proposals;
  v_utente_dest uuid;
begin
  if v_utente is null then
    raise exception using errcode = '42501', message = 'Devi accedere per usare il mercato.';
  end if;

  select * into v_dest from public.teams where id = p_a_team_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Squadra destinataria inesistente.';
  end if;

  select * into v_mia from public.teams
  where league_id = v_dest.league_id and user_id = v_utente;
  if not found then
    raise exception using errcode = '42501', message = 'Non partecipi a questa lega.';
  end if;
  if v_mia.id = v_dest.id then
    raise exception using errcode = '22023', message = 'Non puoi proporre uno scambio a te stesso.';
  end if;

  select * into v_lega from public.leagues where id = v_dest.league_id;
  if v_lega.stato <> 'stagione' then
    raise exception using errcode = '55000', message = 'Il mercato apre a stagione iniziata.';
  end if;
  if not private.mercato_aperto() then
    raise exception using errcode = '55000',
      message = 'Il mercato e'' chiuso: si tratta dalle 07:00 alle 21:00.';
  end if;

  if cardinality(v_offerti) + cardinality(v_richiesti) = 0 then
    raise exception using errcode = '22023', message = 'Una proposta deve contenere almeno un giocatore.';
  end if;

  -- Nessun doppione dentro la stessa lista, e nessun giocatore su entrambe.
  if cardinality(array(select distinct unnest(v_offerti))) <> cardinality(v_offerti)
     or cardinality(array(select distinct unnest(v_richiesti))) <> cardinality(v_richiesti)
     or v_offerti && v_richiesti then
    raise exception using errcode = '22023', message = 'Un giocatore compare due volte nella proposta.';
  end if;

  -- I giocatori offerti devono essere miei, quelli richiesti suoi. Il
  -- controllo si rifa' identico all'accettazione: fra le due cose possono
  -- passare ore e un altro scambio.
  select count(*) into v_n from public.player_instances
  where id = any(v_offerti) and team_id = v_mia.id and league_id = v_lega.id;
  if v_n <> cardinality(v_offerti) then
    raise exception using errcode = '22023', message = 'Stai offrendo un giocatore che non e'' tuo.';
  end if;

  select count(*) into v_n from public.player_instances
  where id = any(v_richiesti) and team_id = v_dest.id and league_id = v_lega.id;
  if v_n <> cardinality(v_richiesti) then
    raise exception using errcode = '22023', message = 'Stai chiedendo un giocatore che non e'' di quella squadra.';
  end if;

  -- Chi ha annunciato il ritiro non si cede piu': ne' in offerta ne' in
  -- richiesta, in nessuna delle due rose coinvolte.
  if exists (
    select 1 from public.player_instances
    where id = any(v_offerti || v_richiesti) and ritiro_annunciato
  ) then
    raise exception using errcode = '55000',
      message = 'Uno dei giocatori coinvolti ha annunciato il ritiro: non puo'' essere ceduto in questa stagione.';
  end if;

  -- Verifica di cortesia: se gia' ora non puoi coprire il conguaglio, la
  -- proposta non ha senso. Quella che conta e' comunque all'accettazione.
  if p_conguaglio > 0 and v_mia.budget < p_conguaglio then
    raise exception using errcode = '22023', message = 'Non hai il budget per questo conguaglio.';
  end if;

  -- Scadenza: le 21:00 di oggi a Roma. Calcolata cosi' l'ora legale non la
  -- sposta, perche' il fuso e' applicato alla data locale e non a un offset.
  v_scadenza := (date_trunc('day', now() at time zone 'Europe/Rome') + interval '21 hours')
                at time zone 'Europe/Rome';

  insert into public.trade_proposals
    (league_id, da_team_id, a_team_id, giocatori_offerti, giocatori_richiesti,
     conguaglio, messaggio, scade_il)
  values
    (v_lega.id, v_mia.id, v_dest.id, v_offerti, v_richiesti,
     coalesce(p_conguaglio, 0), nullif(btrim(coalesce(p_messaggio, '')), ''), v_scadenza)
  returning * into v_proposta;

  select user_id into v_utente_dest from public.teams where id = v_dest.id;
  perform private.notifica(
    v_utente_dest, v_lega.id, 'mercato_proposta',
    'Proposta di mercato da ' || v_mia.nome,
    case
      when cardinality(v_offerti) = 0 then 'Offerta d''acquisto. Scade alle 21:00.'
      when cardinality(v_richiesti) = 0 then 'Ti offre giocatori. Scade alle 21:00.'
      else 'Proposta di scambio. Scade alle 21:00.'
    end,
    jsonb_build_object('proposta_id', v_proposta.id)
  );

  return v_proposta;
end;
$$;

revoke all on function public.proponi_scambio(bigint, bigint[], bigint[], bigint, text)
  from public, anon;
grant execute on function public.proponi_scambio(bigint, bigint[], bigint[], bigint, text)
  to authenticated;

create or replace function public.rispondi_a_proposta(
  p_proposta_id bigint,
  p_accetta     boolean
)
returns public.trade_proposals
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_utente      uuid := (select auth.uid());
  v_p           public.trade_proposals;
  v_lega        public.leagues;
  v_da          public.teams;
  v_a           public.teams;
  v_rimanenti   integer;
  v_prorata_off bigint;
  v_prorata_ric bigint;
  v_saldo_da    bigint;
  v_saldo_a     bigint;
  v_n           integer;
  v_rosa_da     integer;
  v_rosa_a      integer;
  v_gk_da       integer;
  v_gk_a        integer;
  v_prossima    integer;
  v_tutti       bigint[];
  v_form_tolte  integer := 0;
  v_nota        text := '';
begin
  if v_utente is null then
    raise exception using errcode = '42501', message = 'Devi accedere per usare il mercato.';
  end if;

  -- Lock sulla proposta: due tocchi sul pulsante non devono eseguirla due volte.
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

  -- Rifiuto: nessun conto da fare.
  if not coalesce(p_accetta, false) then
    update public.trade_proposals
    set stato = 'rifiutata', risolta_il = now()
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

  if not private.mercato_aperto() then
    raise exception using errcode = '55000',
      message = 'Il mercato e'' chiuso: si conclude dalle 07:00 alle 21:00.';
  end if;

  select * into v_lega from public.leagues where id = v_p.league_id;

  -- Lock sulle due squadre in ordine di id: due scambi incrociati simultanei
  -- che prendessero i lock in ordine opposto si bloccherebbero a vicenda.
  perform 1 from public.teams
  where id in (v_p.da_team_id, v_p.a_team_id)
  order by id
  for update;

  select * into v_da from public.teams where id = v_p.da_team_id;
  select * into v_a  from public.teams where id = v_p.a_team_id;

  -- Ricontrollo della proprieta': fra proposta e accettazione uno dei
  -- giocatori puo' essere finito in un altro scambio.
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

  -- Ricontrollo del ritiro: fra proposta e accettazione uno dei coinvolti
  -- potrebbe averlo annunciato (inizio di una nuova stagione).
  if exists (
    select 1 from public.player_instances
    where id = any(v_p.giocatori_offerti || v_p.giocatori_richiesti) and ritiro_annunciato
  ) then
    raise exception using errcode = '55000',
      message = 'Uno dei giocatori coinvolti ha annunciato il ritiro: la proposta non e'' piu'' valida.';
  end if;

  -- --- Conti (design §5.4, corretto per la somma zero di §5.3) ---
  v_rimanenti := private.giornate_rimanenti(v_lega.id);

  select coalesce(sum(round(pi.ingaggio::numeric * v_rimanenti
                            / greatest(v_lega.giornate_totali, 1))), 0)::bigint
    into v_prorata_off
  from public.player_instances pi where pi.id = any(v_p.giocatori_offerti);

  select coalesce(sum(round(pi.ingaggio::numeric * v_rimanenti
                            / greatest(v_lega.giornate_totali, 1))), 0)::bigint
    into v_prorata_ric
  from public.player_instances pi where pi.id = any(v_p.giocatori_richiesti);

  -- Chi cede incassa il pro-rata che non dovra' piu' sostenere, chi riceve
  -- lo paga. Piu' il conguaglio, che e' un trasferimento puro.
  v_saldo_da := -v_p.conguaglio + v_prorata_off - v_prorata_ric;
  v_saldo_a  :=  v_p.conguaglio + v_prorata_ric - v_prorata_off;

  if v_saldo_da + v_saldo_a <> 0 then
    raise exception using errcode = 'XX000',
      message = 'Errore interno: lo scambio non e'' a somma zero.';
  end if;

  if v_da.budget + v_saldo_da < 0 then
    raise exception using errcode = '22023',
      message = 'La squadra proponente non ha budget sufficiente.';
  end if;
  if v_a.budget + v_saldo_a < 0 then
    raise exception using errcode = '22023',
      message = 'Non hai budget sufficiente per questo scambio.';
  end if;

  -- --- Vincoli di rosa (design §4.5, §9.2): validi per ENTRAMBE ---
  select count(*), count(*) filter (where p.posizioni[1] = 'GK')
    into v_rosa_da, v_gk_da
  from public.player_instances pi join public.players p on p.id = pi.player_id
  where pi.team_id = v_da.id;

  select count(*), count(*) filter (where p.posizioni[1] = 'GK')
    into v_rosa_a, v_gk_a
  from public.player_instances pi join public.players p on p.id = pi.player_id
  where pi.team_id = v_a.id;

  v_rosa_da := v_rosa_da - cardinality(v_p.giocatori_offerti) + cardinality(v_p.giocatori_richiesti);
  v_rosa_a  := v_rosa_a  - cardinality(v_p.giocatori_richiesti) + cardinality(v_p.giocatori_offerti);

  select v_gk_da
       - (select count(*) from public.player_instances pi join public.players p on p.id = pi.player_id
          where pi.id = any(v_p.giocatori_offerti) and p.posizioni[1] = 'GK')
       + (select count(*) from public.player_instances pi join public.players p on p.id = pi.player_id
          where pi.id = any(v_p.giocatori_richiesti) and p.posizioni[1] = 'GK')
    into v_gk_da;

  select v_gk_a
       - (select count(*) from public.player_instances pi join public.players p on p.id = pi.player_id
          where pi.id = any(v_p.giocatori_richiesti) and p.posizioni[1] = 'GK')
       + (select count(*) from public.player_instances pi join public.players p on p.id = pi.player_id
          where pi.id = any(v_p.giocatori_offerti) and p.posizioni[1] = 'GK')
    into v_gk_a;

  if v_rosa_da > private.rosa_massima() or v_rosa_a > private.rosa_massima() then
    raise exception using errcode = '22023',
      message = 'Lo scambio porterebbe una rosa oltre i 30 giocatori.';
  end if;
  -- Il mercato non puo' lasciare nessuna delle due squadre sotto il
  -- minimo permanente di rosa.
  if v_rosa_da < private.rosa_minima() or v_rosa_a < private.rosa_minima() then
    raise exception using errcode = '22023',
      message = 'Lo scambio lascerebbe una rosa sotto i 21 giocatori.';
  end if;
  if v_gk_da < v_lega.portieri_minimi or v_gk_a < v_lega.portieri_minimi then
    raise exception using errcode = '22023',
      message = 'Lo scambio lascerebbe una squadra sotto il minimo di portieri.';
  end if;

  -- --- Esecuzione ---
  update public.player_instances set team_id = v_a.id
  where id = any(v_p.giocatori_offerti);
  update public.player_instances set team_id = v_da.id
  where id = any(v_p.giocatori_richiesti);

  update public.teams set budget = budget + v_saldo_da where id = v_da.id;
  update public.teams set budget = budget + v_saldo_a  where id = v_a.id;

  -- Registro append-only. `importo <> 0` e' un CHECK: uno scambio alla pari
  -- fra giocatori di pari ingaggio non produce movimento e non va scritto.
  if v_saldo_da <> 0 then
    insert into public.transactions (league_id, team_id, tipo, importo, descrizione, saldo_dopo)
    values (v_lega.id, v_da.id, 'mercato_scambio', v_saldo_da,
            'Scambio con ' || v_a.nome, v_da.budget + v_saldo_da);
  end if;
  if v_saldo_a <> 0 then
    insert into public.transactions (league_id, team_id, tipo, importo, descrizione, saldo_dopo)
    values (v_lega.id, v_a.id, 'mercato_scambio', v_saldo_a,
            'Scambio con ' || v_da.nome, v_a.budget + v_saldo_a);
  end if;

  -- Le formazioni gia' salvate che contengono un giocatore appena passato di
  -- mano vanno rifatte. La Edge Function sa rimpiazzare un ceduto, ma
  -- schiererebbe una scelta del computer al posto di una scelta dell'utente.
  select min(f.giornata) into v_prossima
  from public.fixtures f where f.league_id = v_lega.id and f.stato = 'programmata';

  v_tutti := v_p.giocatori_offerti || v_p.giocatori_richiesti;
  if v_prossima is not null then
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

  update public.trade_proposals
  set stato = 'accettata', risolta_il = now()
  where id = v_p.id
  returning * into v_p;

  perform private.notifica(
    v_da.user_id, v_lega.id, 'mercato_esito', 'Scambio concluso con ' || v_a.nome,
    'La tua proposta e'' stata accettata.' || v_nota,
    jsonb_build_object('proposta_id', v_p.id)
  );
  perform private.notifica(
    v_a.user_id, v_lega.id, 'mercato_esito', 'Scambio concluso con ' || v_da.nome,
    'Hai accettato la proposta.' || v_nota,
    jsonb_build_object('proposta_id', v_p.id)
  );

  return v_p;
end;
$$;

revoke all on function public.rispondi_a_proposta(bigint, boolean) from public, anon;
grant execute on function public.rispondi_a_proposta(bigint, boolean) to authenticated;

-- ------------------------------------------------------------
--  7. Pool di svincolati/draft/spin: escludono retired_players.
-- ------------------------------------------------------------

create or replace function private.estrai_svincolati_lega(
  p_league_id bigint,
  p_giorno    date
)
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_lega    public.leagues;
  v_per_ruolo integer;
  v_creati  integer := 0;
  v_asta    record;
begin
  select * into v_lega from public.leagues where id = p_league_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Lega inesistente.';
  end if;

  if exists (
    select 1 from public.free_agent_auctions a
    where a.league_id = p_league_id
      and a.giorno = p_giorno
      and a.origine = 'estrazione'
  ) then
    return 0;
  end if;

  v_per_ruolo := private.svincolati_per_ruolo(p_league_id);

  with disponibili as (
    select p.id, p.overall, p.eta, private.macro_ruolo(p.posizioni) as macro
    from public.players p
    where p.campionato = any(v_lega.campionati_attivi)
      and private.macro_ruolo(p.posizioni) in ('GK', 'DEF', 'MID', 'ATT')
      and not exists (
        select 1 from public.player_instances pi
        where pi.league_id = p_league_id
          and pi.player_id = p.id
          and pi.team_id is not null
      )
      and not exists (
        select 1 from public.retired_players rp
        where rp.league_id = p_league_id
          and rp.player_id = p.id
      )
      and not exists (
        select 1 from public.free_agent_auctions a
        where a.league_id = p_league_id
          and a.giorno = p_giorno
          and a.player_id = p.id
      )
      and not exists (
        select 1 from public.offseason_spins s
        where s.league_id = p_league_id
          and s.player_id = p.id
          and s.stato = 'proposto'
      )
  ),
  ranked as (
    select id, macro,
           row_number() over (partition by macro order by random()) as rn
    from disponibili
  ),
  scelti as (
    select id
    from ranked
    where rn <= v_per_ruolo
  )
  insert into public.free_agent_auctions (league_id, giorno, player_id, ingaggio_teorico, origine)
  select p_league_id, p_giorno, p.id, private.ingaggio_teorico(p.overall, p.eta), 'estrazione'
  from public.players p
  join scelti s on s.id = p.id;

  get diagnostics v_creati = row_count;

  for v_asta in
    select a.id, a.ingaggio_teorico
    from public.free_agent_auctions a
    where a.league_id = p_league_id and a.giorno = p_giorno
  loop
    insert into private.auction_thresholds (auction_id, soglia)
    values (v_asta.id, round(v_asta.ingaggio_teorico * (0.90 + random() * 0.20)))
    on conflict (auction_id) do nothing;
  end loop;

  return v_creati;
end;
$$;

revoke all on function private.estrai_svincolati_lega(bigint, date) from public, anon, authenticated;
grant execute on function private.estrai_svincolati_lega(bigint, date) to service_role;

create or replace function public.offri_per_svincolato_archivio(
  p_league_id bigint,
  p_player_id bigint,
  p_ingaggio  bigint
)
returns public.free_agent_bids
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
  v_lega public.leagues;
  v_player public.players;
  v_squadra public.teams;
  v_giorno date := (now() at time zone 'Europe/Rome')::date;
  v_asta_id bigint;
begin
  if v_user is null then
    raise exception using errcode = '42501', message = 'Devi accedere per usare il mercato.';
  end if;

  if not private.mercato_aperto() then
    raise exception using errcode = '55000',
      message = 'Il mercato e'' chiuso: si offre dalle 07:00 alle 21:00.';
  end if;

  select * into v_lega
  from public.leagues
  where id = p_league_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Lega inesistente.';
  end if;

  select * into v_squadra
  from public.teams
  where league_id = p_league_id
    and user_id = v_user
    and attiva;
  if not found then
    raise exception using errcode = '42501', message = 'Non partecipi a questa lega.';
  end if;

  select * into v_player
  from public.players
  where id = p_player_id
    and campionato = any(v_lega.campionati_attivi);
  if not found then
    raise exception using errcode = 'P0002', message = 'Giocatore non disponibile in questa lega.';
  end if;

  if exists (
    select 1
    from public.player_instances pi
    where pi.league_id = p_league_id
      and pi.player_id = p_player_id
      and pi.team_id is not null
  ) then
    raise exception using errcode = '23505', message = 'Questo giocatore e'' gia'' sotto contratto.';
  end if;

  if exists (
    select 1 from public.retired_players rp
    where rp.league_id = p_league_id and rp.player_id = p_player_id
  ) then
    raise exception using errcode = '23505', message = 'Questo giocatore si e'' ritirato.';
  end if;

  select id into v_asta_id
  from public.free_agent_auctions
  where league_id = p_league_id
    and giorno = v_giorno
    and player_id = p_player_id
    and stato = 'aperta'
  limit 1;

  if v_asta_id is null then
    insert into public.free_agent_auctions(league_id, giorno, player_id, ingaggio_teorico, origine)
    values (p_league_id, v_giorno, p_player_id, private.ingaggio_teorico(v_player.overall, v_player.eta), 'archivio')
    on conflict (league_id, giorno, player_id) do update
      set stato = case
            when public.free_agent_auctions.stato = 'aperta' then public.free_agent_auctions.stato
            else public.free_agent_auctions.stato
          end
    returning id into v_asta_id;

    if not exists (select 1 from public.free_agent_auctions where id = v_asta_id and stato = 'aperta') then
      raise exception using errcode = '55000', message = 'Questo giocatore ha gia'' un esito oggi.';
    end if;

    insert into private.auction_thresholds(auction_id, soglia)
    select v_asta_id, round(private.ingaggio_teorico(v_player.overall, v_player.eta) * (0.90 + random() * 0.20))
    where not exists (select 1 from private.auction_thresholds where auction_id = v_asta_id);
  end if;

  return public.offri_per_svincolato(v_asta_id, p_ingaggio);
end;
$$;

revoke all on function public.offri_per_svincolato_archivio(bigint, bigint, bigint) from public, anon, authenticated;
grant execute on function public.offri_per_svincolato_archivio(bigint, bigint, bigint) to authenticated;

create or replace function private.pesca_carta_ruolo(
  p_league public.leagues,
  p_ruolo text
) returns bigint
language sql
stable
set search_path = ''
as $$
  select p.id
  from public.players p
  where p.campionato = any(p_league.campionati_attivi)
    and private.macro_ruolo(p.posizioni) = p_ruolo
    and not exists (
      select 1 from public.player_instances pi
      where pi.league_id = p_league.id and pi.player_id = p.id
    )
    and not exists (
      select 1 from public.retired_players rp
      where rp.league_id = p_league.id and rp.player_id = p.id
    )
  order by random()
  limit 1;
$$;

revoke all on function private.pesca_carta_ruolo(public.leagues, text)
  from public, anon, authenticated;
grant execute on function private.pesca_carta_ruolo(public.leagues, text)
  to service_role;

create or replace function public.spin_offseason(p_league_id bigint)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
  v_ctx record;
  v_usati integer;
  v_rosa integer;
  v_impegnati integer;
  v_budget_disponibile bigint;
  v_player public.players;
  v_ingaggio bigint;
begin
  if v_user is null then
    raise exception using errcode = '42501', message = 'Devi accedere per usare gli spin off-season.';
  end if;

  select * into v_ctx from private.offseason_spin_corrente(p_league_id, v_user);
  if not found then
    raise exception using errcode = '55000', message = 'Gli spin off-season non sono attivi.';
  end if;

  if exists (
    select 1 from public.offseason_spins
    where offseason_id = (v_ctx.v_offseason).id
      and team_id = (v_ctx.v_team).id
      and stato = 'proposto'
  ) then
    raise exception using errcode = '55000', message = 'Hai gia'' uno spin aperto: ingaggialo o mandalo al mercato.';
  end if;

  select count(*)::integer into v_usati
  from public.offseason_spins
  where offseason_id = (v_ctx.v_offseason).id
    and team_id = (v_ctx.v_team).id;
  if v_usati >= 5 then
    raise exception using errcode = '54000', message = 'Hai gia'' usato tutti e 5 gli spin off-season.';
  end if;

  select count(*)::integer into v_rosa
  from public.player_instances
  where team_id = (v_ctx.v_team).id;
  v_impegnati := private.slot_impegnati((v_ctx.v_team).id);
  if v_rosa + v_impegnati + 1 > private.rosa_massima() then
    raise exception using errcode = '22023', message = 'Non hai posti liberi per usare uno spin.';
  end if;

  v_budget_disponibile := (v_ctx.v_team).budget - private.budget_impegnato((v_ctx.v_team).id);

  select p.* into v_player
  from public.players p
  where p.campionato = any((v_ctx.v_league).campionati_attivi)
    and v_budget_disponibile >= private.ingaggio_teorico(p.overall, p.eta)
    and not exists (
      select 1 from public.player_instances pi
      where pi.league_id = p_league_id
        and pi.player_id = p.id
        and pi.team_id is not null
    )
    and not exists (
      select 1 from public.retired_players rp
      where rp.league_id = p_league_id
        and rp.player_id = p.id
    )
    and not exists (
      select 1 from public.free_agent_auctions a
      where a.league_id = p_league_id
        and a.player_id = p.id
        and a.stato = 'aperta'
    )
    and not exists (
      select 1 from public.offseason_spins s
      where s.league_id = p_league_id
        and s.player_id = p.id
    )
  order by random()
  limit 1;

  if not found then
    raise exception using errcode = '55000', message = 'Non ci sono giocatori sostenibili disponibili per gli spin.';
  end if;

  v_ingaggio := private.ingaggio_teorico(v_player.overall, v_player.eta);
  insert into public.offseason_spins(offseason_id, league_id, team_id, player_id, ingaggio)
  values ((v_ctx.v_offseason).id, p_league_id, (v_ctx.v_team).id, v_player.id, v_ingaggio);

  return public.stato_spin_offseason(p_league_id);
end;
$$;

revoke all on function public.spin_offseason(bigint) from public, anon, authenticated;
grant execute on function public.spin_offseason(bigint) to authenticated;
