-- ============================================================
--  ECONOMIA A TETTO SALARIALE — passo 3b: i percorsi delle squadre PC
--  docs/decisioni-economia.md §2, §3
--
--  Segnalato nei commenti dei passi 2 e 3a come lasciato a meta': le
--  squadre PC continuavano a ragionare in contanti e potevano sfondare il
--  tetto senza che nessuno se ne accorgesse, perche' nessuna delle loro
--  quattro vie di spesa lo controllava:
--
--    private.offerte_mercato_squadre_pc   offerte su aste svincolati
--    public.gestisci_rinnovi_squadre_pc   rinnovi automatici
--    private.proposte_mercato_squadre_pc  proposte di scambio in uscita
--    private.rispondi_a_proposta_pc       decisione su proposte in entrata
--
--  Le prime due sono percorsi isolati: il controllo sostituisce di netto la
--  logica in contanti che avevano.
--
--  Le ultime due toccano gli scambi (trade_proposals), che restano a cassa
--  fino al passo dedicato agli scambi umani (proponi_scambio/
--  rispondi_a_proposta non sono in questa migrazione). Qui si aggiunge SOLO
--  un cancello preventivo sul lato PC: se accettare sfonderebbe il tetto del
--  PC, la proposta viene rifiutata PRIMA di calcolare il pro-rata in
--  contanti, che resta invariato per la parte che ancora muove budget. Se
--  entrambe le squadre sono PC, il cancello si applica a entrambe: sono
--  comunque due squadre sul nuovo modello, non c'e' ragione di trattarle
--  diversamente solo perche' una delle due sta rispondendo.
-- ============================================================

-- ------------------------------------------------------------
--  1. Offerte su aste svincolati: stessa conversione di offri_per_svincolato
--     (passo 3a), la stessa capienza vale anche per il bot.
-- ------------------------------------------------------------

create or replace function private.offerte_mercato_squadre_pc(p_league_id bigint)
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_lega public.leagues;
  v_asta record;
  v_team public.teams;
  v_offerta bigint;
  v_stagione smallint;
  v_inserite integer := 0;
begin
  select * into v_lega from public.leagues where id = p_league_id;
  if not found or v_lega.stato <> 'stagione' then return 0; end if;
  v_stagione := private.stagione_contratto(p_league_id);

  for v_asta in
    select a.id, a.ingaggio_teorico, p.overall
    from public.free_agent_auctions a
    join public.players p on p.id = a.player_id
    where a.league_id = p_league_id and a.stato = 'aperta'
  loop
    if random() > (case when v_asta.overall >= 80 then 0.72 when v_asta.overall >= 72 then 0.48 else 0.25 end) then
      continue;
    end if;
    select t.* into v_team
    from public.teams t
    where t.league_id = p_league_id and t.controllata_da_pc and t.attiva
      and (select count(*) from public.player_instances pi where pi.team_id = t.id) < private.rosa_massima()
      and not exists (select 1 from public.free_agent_bids b where b.auction_id = v_asta.id and b.team_id = t.id)
    order by random()
    limit 1;
    if not found then continue; end if;

    v_offerta := greatest(500000, round(v_asta.ingaggio_teorico * (0.94 + random() * 0.24))::bigint);
    if private.capienza_residua(v_team.id, v_stagione) < v_offerta then continue; end if;
    insert into public.free_agent_bids(auction_id, league_id, team_id, ingaggio_offerto)
    values (v_asta.id, p_league_id, v_team.id, v_offerta)
    on conflict (auction_id, team_id) do nothing;
    if found then v_inserite := v_inserite + 1; end if;
  end loop;
  return v_inserite;
end;
$$;

revoke all on function private.offerte_mercato_squadre_pc(bigint) from public, anon, authenticated;
grant execute on function private.offerte_mercato_squadre_pc(bigint) to service_role;

-- ------------------------------------------------------------
--  2. Rinnovi automatici: nessun controllo esisteva prima. I giocatori
--     considerati hanno gia' contratto_scadenza = stagione_corrente, quindi
--     non coprono ancora la prossima stagione: la capienza richiesta e'
--     l'intero nuovo ingaggio, stessa logica di offri_rinnovo (passo 2).
-- ------------------------------------------------------------

create or replace function public.gestisci_rinnovi_squadre_pc(p_league_id bigint)
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_lega public.leagues;
  v_riga record;
  v_proposta record;
  v_ingaggio bigint;
  v_scadenza smallint;
  v_rinnovati integer := 0;
begin
  select * into v_lega from public.leagues where id = p_league_id;
  if not found or v_lega.stato <> 'stagione' then return 0; end if;

  for v_riga in
    select pi.*, p.nome, p.mentalita_bandiera, p.mentalita_economia
    from public.player_instances pi
    join public.teams t on t.id = pi.team_id
    join public.players p on p.id = pi.player_id
    where pi.league_id = p_league_id and t.controllata_da_pc and t.attiva
      and pi.contratto_scadenza = v_lega.stagione_corrente
      and not pi.ritirato and not pi.ritiro_annunciato
      and (pi.rinnovo_stagione is null or pi.rinnovo_stagione <> v_lega.stagione_corrente)
  loop
    if v_riga.eta_corrente >= 34 and v_riga.ingaggio > 5000000 and random() < 0.18 then continue; end if;
    select * into v_proposta from private.rinnovo_proposta(
      v_riga.id, v_riga.overall_corrente, v_riga.eta_corrente, v_riga.ingaggio,
      v_riga.mentalita_bandiera, v_riga.mentalita_economia
    );
    v_ingaggio := greatest(v_riga.ingaggio, round(v_proposta.richiesta * (1.01 + random() * 0.08))::bigint);
    if private.capienza_residua(v_riga.team_id, (v_lega.stagione_corrente + 1)::smallint) < v_ingaggio then
      continue;
    end if;
    v_scadenza := greatest(v_riga.contratto_scadenza, (v_lega.stagione_corrente + v_proposta.durata)::smallint);
    update public.player_instances
    set ingaggio = v_ingaggio, contratto_scadenza = v_scadenza,
        rinnovo_tentativi = 0, rinnovo_stagione = v_lega.stagione_corrente
    where id = v_riga.id;
    insert into public.transactions(league_id, team_id, tipo, importo, descrizione, saldo_dopo)
    values (p_league_id, v_riga.team_id, 'rinnovo_in_stagione', greatest(1, v_ingaggio - v_riga.ingaggio),
            'Rinnovo PC: ' || v_riga.nome || ' fino alla stagione ' || v_scadenza,
            (select budget from public.teams where id = v_riga.team_id));
    v_rinnovati := v_rinnovati + 1;
  end loop;
  return v_rinnovati;
end;
$$;

revoke all on function public.gestisci_rinnovi_squadre_pc(bigint) from public, anon, authenticated;
grant execute on function public.gestisci_rinnovi_squadre_pc(bigint) to service_role;

-- ------------------------------------------------------------
--  3. Proposte in uscita: prima di aprire una trattativa, il PC verifica di
--     avere spazio per il giocatore che vuole acquisire. Non tocca il
--     conguaglio in contanti, che resta la valuta di scambio finche' gli
--     scambi umani non passano al tetto.
-- ------------------------------------------------------------

create or replace function private.proposte_mercato_squadre_pc(p_league_id bigint)
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_pc public.teams;
  v_bersaglio record;
  v_ruolo text;
  v_offerta bigint;
  v_scadenza timestamptz;
  v_preferisce_pc boolean;
  v_stagione smallint;
  v_inserite integer := 0;
begin
  v_stagione := private.stagione_contratto(p_league_id);

  for v_pc in
    select t.* from public.teams t
    where t.league_id = p_league_id and t.controllata_da_pc and t.attiva
      and (select count(*) from public.player_instances pi where pi.team_id = t.id) < private.rosa_massima()
      and not exists (
        select 1 from public.trade_proposals tp
        where tp.league_id = p_league_id and tp.da_team_id = t.id and tp.stato = 'in_attesa'
      )
    order by random()
  loop
    if random() > 0.34 then continue; end if;

    select ruoli.ruolo into v_ruolo
    from (values ('GK'), ('DEF'), ('MID'), ('ATT')) as ruoli(ruolo)
    left join (
      select private.macro_ruolo(p.posizioni) as ruolo,
             count(*) as quanti,
             avg(pi.overall_corrente) as media
      from public.player_instances pi
      join public.players p on p.id = pi.player_id
      where pi.team_id = v_pc.id
      group by private.macro_ruolo(p.posizioni)
    ) rosa using (ruolo)
    order by coalesce(rosa.quanti, 0), coalesce(rosa.media, 0), random()
    limit 1;

    v_preferisce_pc := random() < 0.60;
    select pi.id, pi.team_id, pi.ingaggio, pi.overall_corrente, t.controllata_da_pc
      into v_bersaglio
    from public.player_instances pi
    join public.players p on p.id = pi.player_id
    join public.teams t on t.id = pi.team_id
    where pi.league_id = p_league_id
      and t.id <> v_pc.id and t.attiva
      and not pi.ritiro_annunciato
      and private.macro_ruolo(p.posizioni) = coalesce(v_ruolo, 'MID')
      and (select count(*) from public.player_instances x where x.team_id = t.id) > private.rosa_minima()
      and not exists (
        select 1 from public.trade_proposals tp
        where tp.league_id = p_league_id and tp.stato = 'in_attesa'
          and pi.id = any(tp.giocatori_richiesti)
      )
    order by (t.controllata_da_pc = v_preferisce_pc) desc,
             abs(pi.overall_corrente - 74 + floor(random() * 9)::integer), random()
    limit 1;
    if not found then continue; end if;

    -- Nuovo: senza spazio salariale per il bersaglio, il direttore sportivo
    -- non apre nemmeno la trattativa.
    if private.capienza_residua(v_pc.id, v_stagione) < v_bersaglio.ingaggio then continue; end if;

    v_offerta := round(
      private.valore_mercato_pc(v_bersaglio.overall_corrente, v_bersaglio.ingaggio)
      * (0.92 + random() * 0.20)
    )::bigint;
    v_offerta := least(v_offerta, v_pc.budget / 4);
    if v_offerta < 500000 then continue; end if;

    v_scadenza := (date_trunc('day', now() at time zone 'Europe/Rome') + interval '21 hours') at time zone 'Europe/Rome';
    if v_scadenza <= now() then v_scadenza := v_scadenza + interval '1 day'; end if;

    insert into public.trade_proposals(
      league_id, da_team_id, a_team_id, giocatori_offerti,
      giocatori_richiesti, conguaglio, messaggio, scade_il
    ) values (
      p_league_id, v_pc.id, v_bersaglio.team_id, '{}',
      array[v_bersaglio.id], v_offerta, 'Offerta del direttore sportivo.', v_scadenza
    );

    if not v_bersaglio.controllata_da_pc then
      perform private.notifica(
        (select user_id from public.teams where id = v_bersaglio.team_id),
        p_league_id, 'mercato_proposta', 'Offerta da ' || v_pc.nome,
        'Il club vuole acquistare un tuo giocatore.', jsonb_build_object('team_id', v_pc.id)
      );
    end if;
    v_inserite := v_inserite + 1;
  end loop;
  return v_inserite;
end;
$$;

revoke all on function private.proposte_mercato_squadre_pc(bigint) from public, anon, authenticated;
grant execute on function private.proposte_mercato_squadre_pc(bigint) to service_role;

-- ------------------------------------------------------------
--  4. Decisione su proposte in entrata: cancello di capienza prima del
--     giudizio economico esistente. v_a e' sempre PC (lo impone la query di
--     lookup); v_da puo' essere umano o PC. Se v_da e' un altro PC, il
--     cancello vale anche per lui: e' comunque una squadra sul tetto.
--
--     Il resto — valutazione sportiva, dimensione rosa, pro-rata in
--     contanti, movimento di budget — resta identico: e' la parte che
--     aspetta lo scambio umano.
-- ------------------------------------------------------------

create or replace function private.rispondi_a_proposta_pc(p_proposta_id bigint)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_p public.trade_proposals;
  v_lega public.leagues;
  v_da public.teams;
  v_a public.teams;
  v_valore_offerto bigint;
  v_valore_richiesto bigint;
  v_rimanenti integer;
  v_prorata_off bigint;
  v_prorata_ric bigint;
  v_saldo_da bigint;
  v_saldo_a bigint;
  v_rosa_da integer;
  v_rosa_a integer;
  v_stagione smallint;
  v_ing_verso_a bigint;
  v_ing_verso_da bigint;
  v_delta_a bigint;
  v_delta_da bigint;
begin
  select * into v_p from public.trade_proposals where id = p_proposta_id for update;
  if not found or v_p.stato <> 'in_attesa' then return; end if;
  select * into v_lega from public.leagues where id = v_p.league_id;
  select * into v_da from public.teams where id = v_p.da_team_id for update;
  select * into v_a from public.teams where id = v_p.a_team_id and controllata_da_pc for update;
  if not found then return; end if;

  if (select count(*) from public.player_instances where id = any(v_p.giocatori_offerti) and team_id = v_da.id) <> cardinality(v_p.giocatori_offerti)
     or (select count(*) from public.player_instances where id = any(v_p.giocatori_richiesti) and team_id = v_a.id) <> cardinality(v_p.giocatori_richiesti) then
    update public.trade_proposals set stato = 'rifiutata', risolta_il = now() where id = v_p.id;
    return;
  end if;

  select coalesce(sum(private.valore_mercato_pc(pi.overall_corrente, pi.ingaggio)), 0)::bigint
    into v_valore_offerto from public.player_instances pi where pi.id = any(v_p.giocatori_offerti);
  select coalesce(sum(private.valore_mercato_pc(pi.overall_corrente, pi.ingaggio)), 0)::bigint
    into v_valore_richiesto from public.player_instances pi where pi.id = any(v_p.giocatori_richiesti);
  v_valore_offerto := greatest(0, v_valore_offerto + v_p.conguaglio);

  if v_valore_offerto < round(v_valore_richiesto * (0.94 + random() * 0.12)) then
    update public.trade_proposals set stato = 'rifiutata', risolta_il = now() where id = v_p.id;
    perform private.notifica(v_da.user_id, v_p.league_id, 'mercato_esito', 'Proposta rifiutata',
      v_a.nome || ' ha rifiutato la tua proposta.', jsonb_build_object('proposta_id', v_p.id));
    return;
  end if;

  select count(*) into v_rosa_da from public.player_instances where team_id = v_da.id;
  select count(*) into v_rosa_a from public.player_instances where team_id = v_a.id;
  v_rosa_da := v_rosa_da - cardinality(v_p.giocatori_offerti) + cardinality(v_p.giocatori_richiesti);
  v_rosa_a := v_rosa_a - cardinality(v_p.giocatori_richiesti) + cardinality(v_p.giocatori_offerti);
  if v_rosa_da not between private.rosa_minima() and private.rosa_massima()
     or v_rosa_a not between private.rosa_minima() and private.rosa_massima() then
    update public.trade_proposals set stato = 'rifiutata', risolta_il = now() where id = v_p.id;
    return;
  end if;

  -- Cancello di capienza: v_a riceve giocatori_offerti e cede
  -- giocatori_richiesti, quindi la variazione del suo monte ingaggi e'
  -- (offerti - richiesti). Un delta negativo (la squadra si alleggerisce) e'
  -- sempre concesso, stessa regola gia' vista per rinnovi e aste.
  v_stagione := private.stagione_contratto(v_p.league_id);
  select coalesce(sum(ingaggio), 0) into v_ing_verso_a from public.player_instances where id = any(v_p.giocatori_offerti);
  select coalesce(sum(ingaggio), 0) into v_ing_verso_da from public.player_instances where id = any(v_p.giocatori_richiesti);
  v_delta_a := v_ing_verso_a - v_ing_verso_da;
  v_delta_da := v_ing_verso_da - v_ing_verso_a;

  if v_delta_a > 0 and private.capienza_residua(v_a.id, v_stagione) < v_delta_a then
    update public.trade_proposals set stato = 'rifiutata', risolta_il = now() where id = v_p.id;
    return;
  end if;
  if v_da.controllata_da_pc and v_delta_da > 0 and private.capienza_residua(v_da.id, v_stagione) < v_delta_da then
    update public.trade_proposals set stato = 'rifiutata', risolta_il = now() where id = v_p.id;
    return;
  end if;

  v_rimanenti := private.giornate_rimanenti(v_p.league_id);
  select coalesce(sum(round(ingaggio::numeric * v_rimanenti / greatest(v_lega.giornate_totali, 1))), 0)::bigint
    into v_prorata_off from public.player_instances where id = any(v_p.giocatori_offerti);
  select coalesce(sum(round(ingaggio::numeric * v_rimanenti / greatest(v_lega.giornate_totali, 1))), 0)::bigint
    into v_prorata_ric from public.player_instances where id = any(v_p.giocatori_richiesti);
  v_saldo_da := -v_p.conguaglio + v_prorata_off - v_prorata_ric;
  v_saldo_a := v_p.conguaglio + v_prorata_ric - v_prorata_off;
  if v_da.budget + v_saldo_da < 0 or v_a.budget + v_saldo_a < 0 then
    update public.trade_proposals set stato = 'rifiutata', risolta_il = now() where id = v_p.id;
    return;
  end if;

  update public.player_instances set team_id = v_a.id where id = any(v_p.giocatori_offerti);
  update public.player_instances set team_id = v_da.id where id = any(v_p.giocatori_richiesti);
  update public.teams set budget = budget + v_saldo_da where id = v_da.id;
  update public.teams set budget = budget + v_saldo_a where id = v_a.id;
  delete from public.lineups where league_id = v_p.league_id and team_id in (v_da.id, v_a.id);

  if v_saldo_da <> 0 then
    insert into public.transactions(league_id, team_id, tipo, importo, descrizione, saldo_dopo)
    values (v_p.league_id, v_da.id, 'mercato_scambio', v_saldo_da, 'Scambio con ' || v_a.nome, v_da.budget + v_saldo_da);
  end if;
  if v_saldo_a <> 0 then
    insert into public.transactions(league_id, team_id, tipo, importo, descrizione, saldo_dopo)
    values (v_p.league_id, v_a.id, 'mercato_scambio', v_saldo_a, 'Scambio con ' || v_da.nome, v_a.budget + v_saldo_a);
  end if;
  update public.trade_proposals set stato = 'accettata', risolta_il = now() where id = v_p.id;
  perform private.notifica(v_da.user_id, v_p.league_id, 'mercato_esito', 'Proposta accettata',
    v_a.nome || ' ha accettato la tua proposta.', jsonb_build_object('proposta_id', v_p.id));
end;
$$;

revoke all on function private.rispondi_a_proposta_pc(bigint) from public, anon, authenticated;
grant execute on function private.rispondi_a_proposta_pc(bigint) to service_role;
