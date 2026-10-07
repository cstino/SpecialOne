-- Gli svincolati dell'off-season (rilasci a mano, contratti non rinnovati, tagli per il tetto) restano fermi nella
-- coda dei rilasci e non vanno nel mercato free agent, per il momento (7 ottobre 2026). Entrano in vetrina solo gli
-- svincolati della stagione 2 e le estrazioni giornaliere. Per liberarli basta: update private.rilasci_in_coda set sospeso = false.
alter table private.rilasci_in_coda add column if not exists sospeso boolean not null default false;
update private.rilasci_in_coda set sospeso = true where creato_il < timestamptz '2026-10-07 14:00:00+02';

create or replace function private.estrai_svincolati_lega(p_league_id bigint, p_giorno date)
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
    and not private.giocatore_in_pool_aperto(p_league_id, p.id)
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
      and not rc.sospeso  -- svincolati in off-season: fermi in coda, non vanno in vetrina
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
      select 1 from private.rilasci_in_coda rc
      where rc.league_id = p_league_id and rc.player_id = pi.player_id and rc.sospeso
    )
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
;
