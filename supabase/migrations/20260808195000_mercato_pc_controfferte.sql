-- Nomi calcistici per le squadre PC, mercato fra bot e controfferte.
-- La logica segue il mercato fra squadre descritto in docs/design.md §9.2.

create or replace function private.nome_calcistico_squadra_pc(
  p_stemma_url text,
  p_indice integer default 1
) returns text
language sql
immutable
set search_path = ''
as $$
  select case coalesce(p_stemma_url, '')
    when 'preset:alci' then 'Atletico Selva'
    when 'preset:aliens' then 'Aurora United'
    when 'preset:aquile' then 'Aquila Reale'
    when 'preset:aviator' then 'Aviatori Calcio'
    when 'preset:bigbrain' then 'Accademia 1908'
    when 'preset:eagle' then 'Sporting Ardea'
    when 'preset:generale' then 'Atletico Imperiale'
    when 'preset:leoni' then 'Leonessa 1926'
    when 'preset:lions' then 'Real Leonis'
    when 'preset:lupo' then 'Lupi d''Abruzzo'
    when 'preset:rocca' then 'Rocca Calcio'
    when 'preset:skull' then 'Corsari Tirrenici'
    when 'preset:torres' then 'Torres Nuova'
    when 'preset:wolves' then 'Wolveria Calcio'
    when 'preset:twins' then 'Gemini Sportiva'
    when 'preset:rosa' then 'Roseto Calcio'
    when 'preset:piramidi' then 'Piramide Athletic'
    when 'preset:slot' then 'Fortuna 1919'
    when 'preset:onepiece' then 'Grand Line Calcio'
    else (array[
      'Virtus Marina', 'Racing Emilia', 'Monteverde Calcio',
      'Stella del Sud', 'Pro Sannio', 'Audace Riviera'
    ])[1 + mod(greatest(coalesce(p_indice, 1), 1) - 1, 6)]
  end;
$$;

create or replace function private.normalizza_nome_squadra_pc()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_base text;
begin
  if not coalesce(new.controllata_da_pc, false) then return new; end if;

  v_base := private.nome_calcistico_squadra_pc(new.stemma_url, new.ordine_draft);
  new.nome := v_base;
  if exists (
    select 1 from public.teams t
    where t.league_id = new.league_id
      and t.id is distinct from new.id
      and lower(t.nome) = lower(v_base)
  ) then
    new.nome := v_base || ' ' || coalesce(new.ordine_draft, new.id, 1)::text;
  end if;
  return new;
end;
$$;

drop trigger if exists teams_nome_calcistico_pc on public.teams;
create trigger teams_nome_calcistico_pc
before insert or update of nome, stemma_url, controllata_da_pc on public.teams
for each row execute function private.normalizza_nome_squadra_pc();

-- Corregge anche le leghe di test già create con nomi tecnici.
update public.teams set nome = nome where controllata_da_pc;

revoke all on function private.nome_calcistico_squadra_pc(text, integer) from public, anon, authenticated;
revoke all on function private.normalizza_nome_squadra_pc() from public, anon, authenticated;

-- Valutazione economica comune per offerte generate e decisioni dei bot.
-- L'ingaggio resta la base; l'overall applica un moltiplicatore limitato,
-- così i club non attribuiscono centinaia di milioni a ogni calciatore.
create or replace function private.valore_mercato_pc(
  p_overall smallint,
  p_ingaggio bigint
) returns bigint
language sql
immutable
set search_path = ''
as $$
  select greatest(
    500000::bigint,
    round(
      greatest(coalesce(p_ingaggio, 0), 250000)::numeric
      * (1.25 + greatest(0, least(20, coalesce(p_overall, 65)::integer - 65)) * 0.035)
    )::bigint
  );
$$;

revoke all on function private.valore_mercato_pc(smallint, bigint) from public, anon, authenticated;
grant execute on function private.valore_mercato_pc(smallint, bigint) to service_role;

-- Ogni club PC può avviare una trattativa. Il destinatario può essere sia
-- umano sia PC; in quest'ultimo caso il trigger già presente decide subito.
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
  v_inserite integer := 0;
begin
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
    -- In una lega numerosa si muovono più direttori sportivi, senza
    -- trasformare ogni apertura di mercato in decine di trasferimenti.
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

-- Allinea la decisione del destinatario PC alla stessa valutazione usata
-- per generare l'offerta. Il resto della procedura mantiene i controlli su
-- proprietà, dimensione rosa, budget, pro-rata e registro economico.
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

alter table public.trade_proposals
  add column if not exists controproposta_di bigint references public.trade_proposals(id) on delete set null;

create index if not exists trade_proposals_controproposta_di_idx
  on public.trade_proposals(controproposta_di)
  where controproposta_di is not null;

create or replace function public.controproponi(
  p_proposta_id bigint,
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
  v_originale public.trade_proposals;
  v_nuova public.trade_proposals;
begin
  select * into v_originale
  from public.trade_proposals
  where id = p_proposta_id
  for update;

  if not found then raise exception 'Proposta non trovata'; end if;
  if not private.e_mia_squadra(v_originale.a_team_id) then raise exception 'Non autorizzato'; end if;
  if v_originale.stato <> 'in_attesa' then raise exception 'La proposta non è più in attesa'; end if;
  if v_originale.scade_il <= now() then raise exception 'La proposta è scaduta'; end if;

  update public.trade_proposals
  set stato = 'rifiutata', risolta_il = now()
  where id = v_originale.id;

  select * into v_nuova
  from public.proponi_scambio(
    v_originale.da_team_id,
    coalesce(p_giocatori_offerti, '{}'),
    coalesce(p_giocatori_richiesti, '{}'),
    p_conguaglio,
    p_messaggio
  );

  update public.trade_proposals
  set controproposta_di = v_originale.id
  where id = v_nuova.id
  returning * into v_nuova;

  return v_nuova;
end;
$$;

revoke all on function public.controproponi(bigint, bigint[], bigint[], bigint, text) from public, anon;
grant execute on function public.controproponi(bigint, bigint[], bigint[], bigint, text) to authenticated;
