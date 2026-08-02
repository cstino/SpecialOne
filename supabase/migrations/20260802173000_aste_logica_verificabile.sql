-- ============================================================
--  ASTE: LA GUARDIA SULL'ORA SEPARATA DALLA LOGICA
--
--  Nella migrazione precedente estrazione e risoluzione avevano il controllo
--  «sono le 07:00 / le 21:00 a Roma?» dentro il corpo. Corretto come
--  comportamento, ma rende il codice **non verificabile**: a qualunque altra
--  ora la funzione restituisce 0 senza fare nulla, e l'unico modo di provarla
--  sarebbe aspettare l'orario giusto in produzione.
--
--  Qui la guardia resta nel job schedulato e la logica passa in funzioni che
--  prendono il giorno come parametro. Il comportamento in produzione non
--  cambia; cambia che ora si puo' provare dentro un rollback.
-- ============================================================

-- ------------------------------------------------------------
--  Estrazione di una singola lega
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
  v_quanti  integer;
  v_creati  integer := 0;
  v_asta    record;
begin
  select * into v_lega from public.leagues where id = p_league_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Lega inesistente.';
  end if;

  -- Guardia contro la doppia estrazione: il job gira ogni ora.
  if exists (select 1 from public.free_agent_auctions a
             where a.league_id = p_league_id and a.giorno = p_giorno) then
    return 0;
  end if;

  v_quanti := private.svincolati_da_estrarre(p_league_id);

  with disponibili as (
    select p.id, p.eta
    from public.players p
    where p.campionato = any(v_lega.campionati_attivi)
      and not exists (
        select 1 from public.player_instances pi
        where pi.league_id = p_league_id
          and pi.player_id = p.id
          and pi.team_id is not null
      )
  ),
  -- design §9.4: almeno 3 under 20, presi per primi. Un sorteggio uniforme
  -- su migliaia di nomi non ne pescherebbe quasi mai tre.
  giovani as (
    select id from disponibili where eta < 20 order by random() limit 3
  ),
  resto as (
    select id from disponibili
    where id not in (select id from giovani)
    order by random()
    limit greatest(v_quanti - (select count(*) from giovani), 0)
  ),
  scelti as (
    select id from giovani union all select id from resto
  )
  insert into public.free_agent_auctions (league_id, giorno, player_id, ingaggio_teorico)
  select p_league_id, p_giorno, p.id, private.ingaggio_teorico(p.overall, p.eta)
  from public.players p join scelti s on s.id = p.id;

  get diagnostics v_creati = row_count;

  -- Soglia nascosta: ingaggio teorico per uniform(0.90, 1.10), design §9.4.
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

revoke all on function private.estrai_svincolati_lega(bigint, date)
  from public, anon, authenticated;
grant execute on function private.estrai_svincolati_lega(bigint, date) to service_role;

create or replace function private.estrai_svincolati()
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_oggi     date;
  v_lega     bigint;
  v_estratti integer := 0;
begin
  if extract(hour from (now() at time zone 'Europe/Rome')) <> 7 then
    return 0;
  end if;

  v_oggi := (now() at time zone 'Europe/Rome')::date;

  for v_lega in select l.id from public.leagues l where l.stato = 'stagione'
  loop
    v_estratti := v_estratti + private.estrai_svincolati_lega(v_lega, v_oggi);
  end loop;

  return v_estratti;
end;
$$;

-- ------------------------------------------------------------
--  Risoluzione di un giorno
-- ------------------------------------------------------------

create or replace function private.risolvi_aste_giorno(p_giorno date)
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
      -- design §9.4: non piu' di 3 aste vinte nello stesso giorno.
      and (select count(*) from public.free_agent_auctions a2
           where a2.league_id = v_asta.league_id and a2.giorno = p_giorno
             and a2.vincitore_team_id = b.team_id) < 3
      and (select count(*) from public.player_instances pi where pi.team_id = b.team_id)
          < v_lega.slot_rosa
      and t.budget >= round(b.ingaggio_offerto::numeric
                            * private.giornate_rimanenti(v_lega.id)
                            / greatest(v_lega.giornate_totali, 1))
    -- A parita' di offerta si sorteggia (design §9.4).
    order by b.ingaggio_offerto desc, random()
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
          when v_off.team_id = v_vincitore.team_id then 'Entra in rosa con un contratto di un anno.'
          else 'Se l''e'' aggiudicato ' ||
               (select nome from public.teams where id = v_vincitore.team_id) || '.'
        end,
        jsonb_build_object('asta_id', v_asta.id)
      );
    end loop;
  end loop;

  return v_assegnate;
end;
$$;

revoke all on function private.risolvi_aste_giorno(date) from public, anon, authenticated;
grant execute on function private.risolvi_aste_giorno(date) to service_role;

create or replace function private.risolvi_aste()
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  if extract(hour from (now() at time zone 'Europe/Rome')) <> 21 then
    return 0;
  end if;
  return private.risolvi_aste_giorno((now() at time zone 'Europe/Rome')::date);
end;
$$;
