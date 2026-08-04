-- Decisione dell'utente, 4 agosto 2026.
--
-- 1) La richiesta di rinnovo non riparte piu' da zero dal solo OVR/eta':
--    un giocatore aggiudicato a un ingaggio piu' alto del suo valore teorico
--    (es. asta vinta a 15 M€ per un giocatore che "valeva" 10 M€) non torna a
--    chiedere 10 M€ al rinnovo successivo. La richiesta esatta diventa il
--    massimo fra il valore teorico di oggi e l'ingaggio che sta gia' percependo.
--    Il range mostrato (+-12%) e la soglia di accettazione (90% della
--    richiesta esatta) restano quelli di sempre: e' li' che sta il "posso
--    scendere un pochetto" chiesto dall'utente, applicato sopra il nuovo
--    pavimento invece che sopra il valore teorico.
-- 2) Vocabolario: la durata dei contratti si esprime in "stagioni", non in
--    "anni" (il gioco scandisce il tempo in stagioni, non in anni solari).
--    Aggiornati i messaggi generati dal server; l'interfaccia era gia' stata
--    aggiornata lato frontend.

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
  v_prob_ritiro numeric;
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

  -- Invecchiamento, crescita/declino e ritiri avvengono una volta sola: la
  -- UNIQUE sull'off-season rende questa funzione non ripetibile.
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
    v_prob_ritiro := greatest(0, (v_eta - 33) * 0.12);

    if v_eta >= 42 or random() < v_prob_ritiro then
      update public.player_instances
      set eta_corrente = v_eta, overall_corrente = v_ovr, team_id = null,
          ritirato = true, condizione = 100, infortunato_fino_a = 0
      where id = v_player.id;
      v_ritirati := v_ritirati + 1;
      perform private.notifica(v_player.user_id, p_league_id, 'sistema',
        v_player.nome || ' si ritira', 'Il giocatore ha concluso la carriera al termine della stagione.',
        jsonb_build_object('player_instance_id', v_player.id));
    else
      update public.player_instances
      set eta_corrente = v_eta, overall_corrente = v_ovr,
          condizione = 100, infortunato_fino_a = 0
      where id = v_player.id;
    end if;
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
--  Vocabolario: "stagioni" al posto di "anni" nei messaggi generati
-- ------------------------------------------------------------

create or replace function public.rispondi_rinnovo(
  p_rinnovo_id bigint,
  p_offerta bigint,
  p_durata smallint
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
  v_rinnovo public.contract_renewals;
  v_offseason public.offseasons;
  v_richiesta bigint;
  v_accetta boolean := false;
  v_controproposta boolean := false;
  v_ingaggio bigint;
  v_nome text;
begin
  if v_user is null then
    raise exception using errcode = '42501', message = 'Devi accedere per rispondere al rinnovo.';
  end if;
  if p_offerta < 500000 or p_offerta % 100000 <> 0 then
    raise exception using errcode = '22023', message = 'L''offerta deve essere almeno 0,5 M€ e a scatti di 0,1 M€.';
  end if;
  if p_durata not between 1 and 4 then
    raise exception using errcode = '22023', message = 'La durata deve essere fra 1 e 4 stagioni.';
  end if;

  select * into v_rinnovo from public.contract_renewals where id = p_rinnovo_id for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Rinnovo non trovato.';
  end if;
  if not (select private.e_mia_squadra(v_rinnovo.team_id)) then
    raise exception using errcode = '42501', message = 'Questo rinnovo non appartiene alla tua squadra.';
  end if;
  if v_rinnovo.stato not in ('in_attesa', 'controproposta') then
    raise exception using errcode = '55000', message = 'Questo rinnovo è già stato risolto.';
  end if;

  select * into v_offseason from public.offseasons where id = v_rinnovo.offseason_id;
  if v_offseason.stato <> 'aperta' or now() >= v_offseason.scade_il then
    raise exception using errcode = '55000', message = 'La finestra dei rinnovi è terminata.';
  end if;

  select richiesta_esatta into v_richiesta
  from private.contract_renewal_terms
  where renewal_id = v_rinnovo.id;

  select p.nome into v_nome
  from public.player_instances pi
  join public.players p on p.id = pi.player_id
  where pi.id = v_rinnovo.player_instance_id;

  if p_offerta >= v_richiesta then
    v_accetta := true;
  elsif v_rinnovo.stato = 'in_attesa' then
    v_controproposta := true;
  end if;

  if v_accetta then
    v_ingaggio := p_offerta;
    update public.player_instances
    set ingaggio = v_ingaggio,
        contratto_scadenza = v_offseason.stagione_a + p_durata - 1
    where id = v_rinnovo.player_instance_id and team_id = v_rinnovo.team_id;

    update public.contract_renewals
    set offerta = p_offerta,
        durata = p_durata,
        stato = 'accettato',
        risolta_il = now()
    where id = v_rinnovo.id;

    perform private.notifica(v_user, v_rinnovo.league_id, 'sistema',
      'Rinnovo accettato',
      v_nome || ' ha firmato per ' || p_durata || case when p_durata = 1 then ' stagione.' else ' stagioni.' end,
      jsonb_build_object('player_instance_id', v_rinnovo.player_instance_id, 'rinnovo_id', v_rinnovo.id));

  elsif v_controproposta then
    update public.contract_renewals
    set offerta = p_offerta,
        durata = p_durata,
        richiesta_min = v_richiesta,
        richiesta_max = v_richiesta,
        stato = 'controproposta',
        risolta_il = null
    where id = v_rinnovo.id;

    perform private.notifica(v_user, v_rinnovo.league_id, 'sistema',
      'Controproposta rinnovo',
      v_nome || ' chiede l''ultima offerta prima di liberarsi.',
      jsonb_build_object('player_instance_id', v_rinnovo.player_instance_id, 'rinnovo_id', v_rinnovo.id, 'richiesta', v_richiesta));

  else
    update public.player_instances
    set team_id = null
    where id = v_rinnovo.player_instance_id and team_id = v_rinnovo.team_id;

    update public.contract_renewals
    set offerta = p_offerta,
        durata = p_durata,
        stato = 'rifiutato',
        risolta_il = now()
    where id = v_rinnovo.id;

    perform private.notifica(v_user, v_rinnovo.league_id, 'sistema',
      'Rinnovo rifiutato',
      v_nome || ' non ha accettato l''ultima offerta ed è ora svincolato.',
      jsonb_build_object('player_instance_id', v_rinnovo.player_instance_id, 'rinnovo_id', v_rinnovo.id));
  end if;

  return jsonb_build_object(
    'id', v_rinnovo.id,
    'accettato', v_accetta,
    'controproposta', v_controproposta,
    'ingaggio', case when v_accetta then v_ingaggio else null end,
    'richiesta', case when v_controproposta then v_richiesta else null end
  );
end;
$$;

revoke all on function public.rispondi_rinnovo(bigint, bigint, smallint) from public, anon, authenticated;
grant execute on function public.rispondi_rinnovo(bigint, bigint, smallint) to authenticated;

-- Difetto preesistente scoperto con `supabase db lint` mentre si toccava
-- questa funzione, non causato da questa migrazione: la 20260803190000 ha
-- introdotto risolvi_aste_giorno(date, bigint default null) come overload
-- SENZA droppare la vecchia risolvi_aste_giorno(date) (l'ultima di una lunga
-- serie di create-or-replace su quella firma). Le due firme coesistono, e
-- private.risolvi_aste() -- il cron delle 21:00 -- le chiama con un solo
-- argomento: ambiguo, "could not choose a best candidate function". Il cron
-- di risoluzione aste e' rotto in produzione dal 3 agosto. Si ripara qui.
drop function if exists private.risolvi_aste_giorno(date);

create or replace function private.risolvi_aste_giorno(
  p_giorno date,
  p_league_id bigint default null
)
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_asta      record;
  v_soglia    bigint;
  v_vincitore record;
  v_lega      public.leagues;
  v_prorata   bigint;
  v_nome      text;
  v_assegnate integer := 0;
  v_off       record;
begin
  for v_asta in
    select a.* from public.free_agent_auctions a
    where a.giorno = p_giorno and a.stato = 'aperta'
      and (p_league_id is null or a.league_id = p_league_id)
    order by a.id
    for update
  loop
    select * into v_lega from public.leagues where id = v_asta.league_id;
    select soglia into v_soglia from private.auction_thresholds where auction_id = v_asta.id;
    select p.nome into v_nome from public.players p where p.id = v_asta.player_id;

    v_vincitore := null;

    select b.* into v_vincitore
    from public.free_agent_bids b
    join public.teams t on t.id = b.team_id
    where b.auction_id = v_asta.id
      and b.ingaggio_offerto >= v_soglia
      and (select count(*) from public.player_instances pi where pi.team_id = b.team_id)
          < v_lega.slot_rosa
      and t.budget >= round(b.ingaggio_offerto::numeric
                            * private.giornate_rimanenti(v_lega.id)
                            / greatest(v_lega.giornate_totali, 1))
    order by b.ingaggio_offerto desc, b.aggiornata_il asc, b.id asc
    limit 1;

    if v_vincitore.id is null then
      update public.free_agent_auctions
      set stato = 'deserta', risolta_il = now()
      where id = v_asta.id;
    else
      v_prorata := round(v_vincitore.ingaggio_offerto::numeric
                         * private.giornate_rimanenti(v_lega.id)
                         / greatest(v_lega.giornate_totali, 1));

      insert into public.player_instances
        (league_id, player_id, team_id, overall_corrente, eta_corrente, ingaggio)
      select v_asta.league_id, p.id, v_vincitore.team_id, p.overall, p.eta,
             v_vincitore.ingaggio_offerto
      from public.players p where p.id = v_asta.player_id;

      update public.teams set budget = budget - v_prorata where id = v_vincitore.team_id;

      if v_prorata <> 0 then
        insert into public.transactions
          (league_id, team_id, tipo, importo, descrizione, saldo_dopo)
        select v_asta.league_id, v_vincitore.team_id, 'asta_svincolato', -v_prorata,
               'Asta vinta: ' || v_nome,
               (select budget from public.teams where id = v_vincitore.team_id);
      end if;

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
