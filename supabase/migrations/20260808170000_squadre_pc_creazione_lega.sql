-- Squadre controllate dal PC: condividono schema, budget e draft delle
-- squadre umane, ma non hanno un utente autenticato associato.

alter table public.teams alter column user_id drop not null;
alter table public.teams add column controllata_da_pc boolean not null default false;
alter table public.teams add constraint teams_controllo_coerente check (
  (controllata_da_pc and user_id is null)
  or (not controllata_da_pc and user_id is not null)
);

-- Dichiarazione anticipata: crea_lega la invoca piu' sotto e la definizione
-- completa viene sostituita nella stessa migrazione prima che sia eseguibile.
create or replace function private.completa_draft_squadra_pc(p_league_id bigint, p_team_id bigint)
returns void language plpgsql security definer set search_path = '' as $$
begin
  raise exception 'Inizializzazione draft PC non completata';
end;
$$;

create or replace function public.crea_lega(
  p_nome_lega text, p_nome_squadra text, p_stemma_url text,
  p_n_squadre smallint, p_n_gironi smallint, p_budget_iniziale bigint,
  p_budget_draft bigint, p_reroll_draft smallint, p_slot_rosa smallint,
  p_portieri_minimi smallint, p_campionati_attivi text[], p_squadre_pc smallint
) returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_esito jsonb;
  v_league public.leagues;
  v_team public.teams;
  v_nomi constant text[] := array['Borgo Alce','Stella Verde','Aquila Calcio','Aviatori FC','Genius FC','Real Aquila','Atletico Imperiale','Leoni 1926','Lions United','Lupi FC','Rocca Calcio','Teschio FC','Torres Nuova','Wolves City','Gemini FC','Roseto Calcio','Piramide FC','Fortuna FC','Grand Line FC'];
  v_stemmi constant text[] := array['preset:alci','preset:aliens','preset:aquile','preset:aviator','preset:bigbrain','preset:eagle','preset:generale','preset:leoni','preset:lions','preset:lupo','preset:rocca','preset:skull','preset:torres','preset:wolves','preset:twins','preset:rosa','preset:piramidi','preset:slot','preset:onepiece'];
  i integer;
begin
  if p_squadre_pc not between 0 and p_n_squadre - 1 then
    raise exception using errcode = '22023', message = 'Il numero di squadre PC non e'' valido.';
  end if;

  v_esito := public.crea_lega(p_nome_lega, p_nome_squadra, p_stemma_url,
    p_n_squadre, p_n_gironi, p_budget_iniziale, p_budget_draft,
    p_reroll_draft, p_slot_rosa, p_portieri_minimi, p_campionati_attivi);
  select * into v_league from public.leagues where id = (v_esito->>'league_id')::bigint;

  for i in 1..p_squadre_pc loop
    insert into public.teams (league_id, user_id, controllata_da_pc, nome, stemma_url, budget, reroll_rimasti, ordine_draft)
    values (
      v_league.id, null, true, v_nomi[i], v_stemmi[i],
      v_league.budget_iniziale, v_league.reroll_draft, i
    )
    returning * into v_team;
    insert into public.transactions (league_id, team_id, tipo, importo, descrizione, saldo_dopo)
    values (v_league.id, v_team.id, 'dotazione_iniziale', v_league.budget_iniziale, 'Dotazione iniziale squadra PC', v_league.budget_iniziale);
    insert into public.draft_team_state (team_id, league_id) values (v_team.id, v_league.id);
    perform private.completa_draft_squadra_pc(v_league.id, v_team.id);
  end loop;
  return v_esito;
end;
$$;

revoke all on function public.crea_lega(text,text,text,smallint,smallint,bigint,bigint,smallint,smallint,smallint,text[],smallint) from public, anon;
grant execute on function public.crea_lega(text,text,text,smallint,smallint,bigint,bigint,smallint,smallint,smallint,text[],smallint) to authenticated;

-- Il PC costruisce subito la sua rosa. I giocatori restano unici nella lega,
-- lo stesso tetto draft viene controllato ad ogni scelta e il risultato passa
-- dalle stesse tabelle (istanze, pick e registro economico) delle squadre umane.
create or replace function private.completa_draft_squadra_pc(
  p_league_id bigint,
  p_team_id bigint
) returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_league public.leagues;
  v_team public.teams;
  v_player public.players;
  v_ruolo text;
  v_presi integer;
  v_speso bigint;
  v_ingaggio bigint;
  v_pick bigint;
begin
  select * into v_league from public.leagues where id = p_league_id for update;
  select * into v_team from public.teams
  where id = p_team_id and league_id = p_league_id and controllata_da_pc and attiva
  for update;
  if not found then
    raise exception using errcode = '22023', message = 'La squadra indicata non e'' controllata dal PC.';
  end if;

  loop
    select count(*) into v_presi from public.player_instances
    where league_id = p_league_id and team_id = p_team_id;
    exit when v_presi >= v_league.slot_rosa;

    -- Ruoli alternati: evita che portieri e difensori consumino tutto il
    -- budget prima che il PC arrivi a centrocampo e attacco (2/8/8/6).
    v_ruolo := (array[
      'GK','DEF','MID','ATT','DEF','MID','ATT','DEF',
      'MID','ATT','DEF','MID','GK','DEF','MID','ATT',
      'DEF','MID','ATT','DEF','MID','DEF','MID','ATT'
    ])[v_presi + 1];

    v_speso := v_league.budget_iniziale - v_team.budget;
    select p.* into v_player
    from public.players p
    where p.campionato = any(v_league.campionati_attivi)
      and private.macro_ruolo(p.posizioni) = v_ruolo
      and not exists (
        select 1 from public.player_instances pi
        where pi.league_id = p_league_id and pi.player_id = p.id
      )
      and private.pick_sostenibile(
        v_team.budget, v_league.budget_draft, v_speso, v_league.slot_rosa,
        v_presi, p.overall, p.eta
      )
    -- Priorita' alla qualità, ma con una piccola componente casuale: le squadre
    -- PC non producono rose identiche e non scelgono sempre il primo nome assoluto.
    order by abs(
      private.ingaggio_teorico(p.overall, p.eta)
      - least(3500000, (v_league.budget_draft - v_speso) / greatest(v_league.slot_rosa - v_presi, 1))
    ) + random() * 250000
    limit 1;
    if not found then
      raise exception using errcode = '55000', message = 'Il pool non contiene giocatori PC sostenibili per il draft.';
    end if;

    v_ingaggio := private.ingaggio_teorico(v_player.overall, v_player.eta);
    insert into public.player_instances (league_id, player_id, team_id, overall_corrente, eta_corrente, ingaggio)
    values (p_league_id, v_player.id, p_team_id, v_player.overall, v_player.eta, v_ingaggio);

    select pick_numero into v_pick from public.draft_state where league_id = p_league_id for update;
    insert into public.draft_picks (league_id, team_id, player_instance_id, pick_numero, club_estratto, ingaggio_pagato)
    select p_league_id, p_team_id, id, v_pick, v_ruolo, v_ingaggio
    from public.player_instances
    where league_id = p_league_id and player_id = v_player.id;

    v_team.budget := v_team.budget - v_ingaggio;
    update public.teams set budget = v_team.budget where id = p_team_id;
    update public.draft_state set pick_numero = pick_numero + 1, aggiornato_il = now()
    where league_id = p_league_id;
    insert into public.transactions (league_id, team_id, tipo, importo, descrizione, saldo_dopo)
    values (p_league_id, p_team_id, 'draft_pick', -v_ingaggio, 'Ingaggio draft PC: ' || v_player.nome, v_team.budget);
  end loop;

  update public.draft_team_state
  set pick_numero = v_league.slot_rosa, stato = 'concluso',
      carta_gk = null, carta_def = null, carta_mid = null, carta_att = null, aggiornato_il = now()
  where league_id = p_league_id and team_id = p_team_id;
end;
$$;

revoke all on function private.completa_draft_squadra_pc(bigint, bigint) from public, anon, authenticated;
grant execute on function private.completa_draft_squadra_pc(bigint, bigint) to service_role;

-- Una squadra PC partecipa alle aste aperte quando ha spazio in rosa. Il
-- valore dell'offerta nasce dall'ingaggio teorico, dall'overall e da un
-- piccolo errore casuale: non conosce le buste degli altri concorrenti.
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
  v_inserite integer := 0;
begin
  select * into v_lega from public.leagues where id = p_league_id;
  if not found or v_lega.stato <> 'stagione' then return 0; end if;

  for v_asta in
    select a.id, a.ingaggio_teorico, p.overall
    from public.free_agent_auctions a
    join public.players p on p.id = a.player_id
    where a.league_id = p_league_id and a.stato = 'aperta'
  loop
    -- Non tutte le squadre inseguono ogni carta: 75+ interessa di piu', ma
    -- una parte delle decisioni resta volutamente imperfetta.
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
    if v_team.budget < round(v_offerta::numeric * private.giornate_rimanenti(p_league_id) / greatest(v_lega.giornate_totali, 1)) then
      continue;
    end if;
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

-- Ogni tanto il PC cerca di rinforzarsi anche presso le squadre umane. Fa una
-- sola proposta al giorno, privilegiando il ruolo meno coperto e senza mai
-- impegnare oltre un quarto della liquidità disponibile.
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
begin
  if random() > 0.32 then return 0; end if;
  select t.* into v_pc from public.teams t
  where t.league_id = p_league_id and t.controllata_da_pc and t.attiva
    and not exists (
      select 1 from public.trade_proposals tp
      where tp.league_id = p_league_id and tp.da_team_id = t.id and tp.stato = 'in_attesa'
    )
  order by random() limit 1;
  if not found then return 0; end if;

  select private.macro_ruolo(p.posizioni) into v_ruolo
  from public.player_instances pi join public.players p on p.id = pi.player_id
  where pi.team_id = v_pc.id
  group by private.macro_ruolo(p.posizioni)
  order by count(*), avg(pi.overall_corrente)
  limit 1;
  select pi.id, pi.team_id, pi.ingaggio, pi.overall_corrente
    into v_bersaglio
  from public.player_instances pi
  join public.players p on p.id = pi.player_id
  join public.teams t on t.id = pi.team_id
  where pi.league_id = p_league_id and t.attiva and not t.controllata_da_pc
    and not pi.ritiro_annunciato and private.macro_ruolo(p.posizioni) = coalesce(v_ruolo, 'MID')
  order by pi.overall_corrente desc, random()
  limit 1;
  if not found then return 0; end if;

  v_offerta := least(round(v_bersaglio.ingaggio * (1.35 + random() * 0.85))::bigint, v_pc.budget / 4);
  if v_offerta < 500000 then return 0; end if;
  v_scadenza := (date_trunc('day', now() at time zone 'Europe/Rome') + interval '21 hours') at time zone 'Europe/Rome';
  insert into public.trade_proposals(league_id, da_team_id, a_team_id, giocatori_offerti, giocatori_richiesti, conguaglio, messaggio, scade_il)
  values (p_league_id, v_pc.id, v_bersaglio.team_id, '{}', array[v_bersaglio.id], v_offerta,
          'Offerta del direttore sportivo.', v_scadenza);
  perform private.notifica((select user_id from public.teams where id = v_bersaglio.team_id), p_league_id,
    'mercato_proposta', 'Offerta da ' || v_pc.nome, 'Il club PC vuole acquistare un tuo giocatore.',
    jsonb_build_object('team_id', v_pc.id));
  return 1;
end;
$$;

revoke all on function private.proposte_mercato_squadre_pc(bigint) from public, anon, authenticated;
grant execute on function private.proposte_mercato_squadre_pc(bigint) to service_role;

-- L'estrazione automatica delle 23:30 e' il punto comune ad ogni lega.
-- Dopo aver creato le carte, le squadre PC presentano le loro buste senza
-- attendere un'azione dal browser.
create or replace function private.estrai_svincolati()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_oggi date;
  v_ora time;
  v_lega bigint;
  v_estratti integer := 0;
begin
  v_ora := (now() at time zone 'Europe/Rome')::time;
  if not (v_ora >= time '23:30' and v_ora < time '23:45') then return 0; end if;
  v_oggi := (now() at time zone 'Europe/Rome')::date;
  for v_lega in select id from public.leagues where stato = 'stagione' loop
    v_estratti := v_estratti + private.estrai_svincolati_lega(v_lega, v_oggi);
    perform private.offerte_mercato_squadre_pc(v_lega);
    perform private.proposte_mercato_squadre_pc(v_lega);
  end loop;
  return v_estratti;
end;
$$;

-- I rinnovi PC usano la stessa proposta individuale (età, overall e
-- mentalità) vista dagli utenti. In rari casi il club lascia andare un
-- veterano costoso: è una scelta imperfetta, non una rosa bloccata per sempre.
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
    -- I 34+ molto costosi hanno una piccola probabilità di non ricevere
    -- proposta: il PC può sbagliare e liberare budget per il mercato.
    if v_riga.eta_corrente >= 34 and v_riga.ingaggio > 5000000 and random() < 0.18 then continue; end if;
    select * into v_proposta from private.rinnovo_proposta(
      v_riga.id, v_riga.overall_corrente, v_riga.eta_corrente, v_riga.ingaggio,
      v_riga.mentalita_bandiera, v_riga.mentalita_economia
    );
    v_ingaggio := greatest(v_riga.ingaggio, round(v_proposta.richiesta * (1.01 + random() * 0.08))::bigint);
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

-- Risposta immediata alle proposte indirizzate a un PC. La valutazione resta
-- volutamente semplice e leggibile: valore sportivo + metà dell'ingaggio,
-- con una tolleranza casuale che permette anche decisioni non perfette.
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
  v_esito text;
begin
  select * into v_p from public.trade_proposals where id = p_proposta_id for update;
  if not found or v_p.stato <> 'in_attesa' then return; end if;
  select * into v_lega from public.leagues where id = v_p.league_id;
  select * into v_da from public.teams where id = v_p.da_team_id for update;
  select * into v_a from public.teams where id = v_p.a_team_id and controllata_da_pc for update;
  if not found then return; end if;

  -- La rosa e i giocatori devono essere ancora quelli fotografati dalla proposta.
  if (select count(*) from public.player_instances where id = any(v_p.giocatori_offerti) and team_id = v_da.id) <> cardinality(v_p.giocatori_offerti)
     or (select count(*) from public.player_instances where id = any(v_p.giocatori_richiesti) and team_id = v_a.id) <> cardinality(v_p.giocatori_richiesti) then
    update public.trade_proposals set stato = 'rifiutata', risolta_il = now() where id = v_p.id;
    return;
  end if;

  select coalesce(sum(pi.overall_corrente::bigint * pi.overall_corrente * 100000 + pi.ingaggio / 2), 0)
    into v_valore_offerto from public.player_instances pi where pi.id = any(v_p.giocatori_offerti);
  select coalesce(sum(pi.overall_corrente::bigint * pi.overall_corrente * 100000 + pi.ingaggio / 2), 0)
    into v_valore_richiesto from public.player_instances pi where pi.id = any(v_p.giocatori_richiesti);
  v_valore_offerto := v_valore_offerto + greatest(v_p.conguaglio, 0);

  -- Un PC non svende quasi mai, ma la soglia oscilla fra il 94% e il 106%:
  -- offerte vicine possono essere accolte o respinte in modo non deterministico.
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

create or replace function private.rispondi_a_proposta_pc_trigger()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if exists (select 1 from public.teams where id = new.a_team_id and controllata_da_pc) then
    perform private.rispondi_a_proposta_pc(new.id);
  end if;
  return new;
end;
$$;

drop trigger if exists trade_proposals_risposta_pc on public.trade_proposals;
create trigger trade_proposals_risposta_pc
after insert on public.trade_proposals
for each row execute function private.rispondi_a_proposta_pc_trigger();

revoke all on function private.rispondi_a_proposta_pc(bigint) from public, anon, authenticated;
revoke all on function private.rispondi_a_proposta_pc_trigger() from public, anon, authenticated;
grant execute on function private.rispondi_a_proposta_pc(bigint) to service_role;

-- Una squadra PC non ha un utente destinatario: la proposta viene gia'
-- valutata dal trigger, quindi non va inserita una notifica con user_id nullo.
create or replace function public.proponi_scambio(
  p_a_team_id bigint,
  p_giocatori_offerti bigint[] default '{}'::bigint[],
  p_giocatori_richiesti bigint[] default '{}'::bigint[],
  p_conguaglio bigint default 0,
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
  v_offerti bigint[] := coalesce(p_giocatori_offerti, '{}');
  v_richiesti bigint[] := coalesce(p_giocatori_richiesti, '{}');
  v_n integer;
  v_scadenza timestamptz;
  v_proposta public.trade_proposals;
  v_utente_dest uuid;
begin
  if v_utente is null then raise exception using errcode = '42501', message = 'Devi accedere per usare il mercato.'; end if;
  select * into v_dest from public.teams where id = p_a_team_id;
  if not found then raise exception using errcode = 'P0002', message = 'Squadra destinataria inesistente.'; end if;
  select * into v_mia from public.teams where league_id = v_dest.league_id and user_id = v_utente;
  if not found then raise exception using errcode = '42501', message = 'Non partecipi a questa lega.'; end if;
  if v_mia.id = v_dest.id then raise exception using errcode = '22023', message = 'Non puoi proporre uno scambio a te stesso.'; end if;
  select * into v_lega from public.leagues where id = v_dest.league_id;
  if v_lega.stato <> 'stagione' or not private.mercato_aperto_lega(v_lega.id) then
    raise exception using errcode = '55000', message = 'Il mercato e'' chiuso.';
  end if;
  if cardinality(v_offerti) + cardinality(v_richiesti) = 0 then raise exception using errcode = '22023', message = 'Una proposta deve contenere almeno un giocatore.'; end if;
  if cardinality(array(select distinct unnest(v_offerti))) <> cardinality(v_offerti)
     or cardinality(array(select distinct unnest(v_richiesti))) <> cardinality(v_richiesti)
     or v_offerti && v_richiesti then raise exception using errcode = '22023', message = 'Un giocatore compare due volte nella proposta.'; end if;
  select count(*) into v_n from public.player_instances where id = any(v_offerti) and team_id = v_mia.id and league_id = v_lega.id;
  if v_n <> cardinality(v_offerti) then raise exception using errcode = '22023', message = 'Stai offrendo un giocatore che non e'' tuo.'; end if;
  select count(*) into v_n from public.player_instances where id = any(v_richiesti) and team_id = v_dest.id and league_id = v_lega.id;
  if v_n <> cardinality(v_richiesti) then raise exception using errcode = '22023', message = 'Stai chiedendo un giocatore che non e'' di quella squadra.'; end if;
  if exists (select 1 from public.player_instances where id = any(v_offerti || v_richiesti) and ritiro_annunciato) then
    raise exception using errcode = '55000', message = 'Uno dei giocatori coinvolti ha annunciato il ritiro.';
  end if;
  if p_conguaglio > 0 and v_mia.budget < p_conguaglio then raise exception using errcode = '22023', message = 'Non hai il budget per questo conguaglio.'; end if;
  v_scadenza := (date_trunc('day', now() at time zone 'Europe/Rome') + interval '21 hours') at time zone 'Europe/Rome';
  insert into public.trade_proposals(league_id, da_team_id, a_team_id, giocatori_offerti, giocatori_richiesti, conguaglio, messaggio, scade_il)
  values (v_lega.id, v_mia.id, v_dest.id, v_offerti, v_richiesti, coalesce(p_conguaglio, 0), nullif(btrim(coalesce(p_messaggio, '')), ''), v_scadenza)
  returning * into v_proposta;
  select user_id into v_utente_dest from public.teams where id = v_dest.id;
  if v_utente_dest is not null then
    perform private.notifica(v_utente_dest, v_lega.id, 'mercato_proposta', 'Proposta di mercato da ' || v_mia.nome,
      'Proposta di mercato: scade alle 21:00.', jsonb_build_object('proposta_id', v_proposta.id));
  end if;
  select * into v_proposta from public.trade_proposals where id = v_proposta.id;
  return v_proposta;
end;
$$;
