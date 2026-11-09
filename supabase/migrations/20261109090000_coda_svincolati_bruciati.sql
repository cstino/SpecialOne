-- Mercato svincolati: la coda (decisione del committente, 9/11/2026). In Serie F c'erano 121 giocatori in vetrina:
-- 67 contratti scaduti entrati tutti insieme alla chiusura dell'off-season, 31 svincolati sopra 75 e 8 non scelti
-- del draft in vetrina ogni giorno (fino a 30 comparse), solo 4 dall'estrazione normale.
-- Da ora:
--   - rilasciati dalle squadre e non scelti dei draft stanno in una coda; ogni giorno se ne estraggono 10 a caso,
--     almeno uno per ruolo, oltre all'estrazione normale;
--   - chi esce dalla coda e non viene preso entro la chiusura del mercato SPARISCE dalla lega (retired_players,
--     che estrazioni, draft e pool delle scelte escludono gia');
--   - gli svincolati ancora pagati dal vecchio club non si estraggono: sono in vetrina tutti i giorni, senza piu'
--     il limite delle 30 comparse.
-- I 76 rilasci "sospesi" di Serie F fermi in coda dal 4-7 ottobre (mai comparsi nel mercato: nessuno li sbloccava a
-- fine off-season) si tolgono subito, come bruciati.

begin;

alter table public.free_agent_auctions add column if not exists dalla_coda boolean not null default false;

-- 1) I sospesi: spariscono.
do $$
begin
  if (select count(*) from private.rilasci_in_coda where sospeso) <> 76 then
    raise exception 'attesi 76 rilasci sospesi, trovati %', (select count(*) from private.rilasci_in_coda where sospeso);
  end if;
end $$;
insert into public.retired_players (league_id, player_id, stagione)
select rc.league_id, rc.player_id, l.stagione_corrente
from private.rilasci_in_coda rc join public.leagues l on l.id = rc.league_id
where rc.sospeso
on conflict do nothing;
delete from private.rilasci_in_coda where sospeso;

-- 2) Chi e' in vetrina nella giornata di mercato in corso ed e' un ex giocatore di una squadra (contratto scaduto,
--    tagliato, sopra 75), senza piu' un club che lo paga: entra in coda. I non scelti dei draft ci sono gia'
--    (private.vetrina_fissa); quelli dell'estrazione normale restano fuori, come sempre.
insert into private.rilasci_in_coda (league_id, player_id)
select distinct a.league_id, a.player_id
from public.free_agent_auctions a
join public.player_instances pi on pi.league_id = a.league_id and pi.player_id = a.player_id
where a.giorno = (select max(a2.giorno) from public.free_agent_auctions a2 where a2.league_id = a.league_id)
  and pi.team_id is null and not pi.ritirato
  and not (pi.peso_team_id is not null and pi.contratto_scadenza >= private.stagione_contratto(a.league_id))
  and not exists (select 1 from public.retired_players rp where rp.league_id = a.league_id and rp.player_id = a.player_id)
on conflict do nothing;

-- 3) L'estrazione giornaliera.
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

  -- Bruciati (9/11/2026, decisione del committente): chi e' uscito dalla coda in una giornata precedente e nessuno
  -- ha preso sparisce dalla lega. Va fra i ritirati, che ogni estrazione, draft e pool delle scelte esclude gia'.
  insert into public.retired_players (league_id, player_id, stagione)
  select distinct a.league_id, a.player_id, v_lega.stagione_corrente
  from public.free_agent_auctions a
  where a.league_id = p_league_id and a.dalla_coda and a.giorno < p_giorno
    and not exists (select 1 from public.player_instances pi
                     where pi.league_id = a.league_id and pi.player_id = a.player_id and pi.team_id is not null)
    and not exists (select 1 from public.retired_players rp
                     where rp.league_id = a.league_id and rp.player_id = a.player_id);
  -- Il conto delle comparse riparte quando un giocatore trova squadra (Season 3, 8/11/2026).
  delete from private.vetrina_comparse vc
   where vc.league_id = p_league_id
     and exists (select 1 from public.player_instances pi
                  where pi.league_id = vc.league_id and pi.player_id = vc.player_id and pi.team_id is not null);

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

  -- LA CODA (9/11/2026, decisione del committente): rilasciati dalle squadre (contratti scaduti, tagli) e non scelti
  -- dei draft non entrano piu' tutti insieme ne' ogni giorno. Ogni giorno se ne estraggono 10 a caso, almeno uno per
  -- ruolo; chi non viene preso entro la chiusura del mercato sparisce (vedi i bruciati in cima). Gli svincolati
  -- ancora pagati dal vecchio club non passano di qui: sono in vetrina tutti i giorni (blocco sopra).
  delete from private.vetrina_fissa vf
   where vf.league_id = p_league_id
     and exists (select 1 from public.player_instances pi
                  where pi.league_id = vf.league_id and pi.player_id = vf.player_id and pi.team_id is not null);
  delete from private.rilasci_in_coda rc
   where rc.league_id = p_league_id
     and exists (select 1 from public.player_instances pi
                  where pi.league_id = rc.league_id and pi.player_id = rc.player_id and (pi.team_id is not null or pi.ritirato));

  with coda as (
    select rc.player_id
    from private.rilasci_in_coda rc
    join public.player_instances pi on pi.league_id = rc.league_id and pi.player_id = rc.player_id
    where rc.league_id = p_league_id and pi.team_id is null and not pi.ritirato
      and not rc.sospeso  -- svincolati in off-season: fermi in coda
      and not (pi.peso_team_id is not null and pi.contratto_scadenza >= private.stagione_contratto(p_league_id))
    union
    select vf.player_id from private.vetrina_fissa vf where vf.league_id = p_league_id
  ), candidati as (
    select c.player_id, private.macro_ruolo(p.posizioni) as macro,
           coalesce(oi.overall_corrente, fap.overall_corrente, p.overall) as overall_attuale,
           coalesce(oi.eta_corrente, fap.eta_corrente, p.eta) as eta_attuale
    from coda c
    join public.players p on p.id = c.player_id
    left join public.player_instances oi
      on oi.league_id = p_league_id and oi.player_id = p.id and oi.team_id is null
    left join public.free_agent_progression fap
      on fap.league_id = p_league_id and fap.player_id = p.id
    where not private.giocatore_in_pool_aperto(p_league_id, p.id)
      and not exists (select 1 from public.player_instances pt
                       where pt.league_id = p_league_id and pt.player_id = p.id and pt.team_id is not null)
      and not exists (select 1 from public.retired_players rp where rp.league_id = p_league_id and rp.player_id = p.id)
      and not exists (select 1 from public.free_agent_auctions a
                       where a.league_id = p_league_id and a.giorno = p_giorno and a.player_id = p.id)
  ), ordinati as (
    select *, row_number() over (partition by macro order by random()) as rn_ruolo, random() as sorte
    from candidati
  ), scelti as (
    -- Prima il primo estratto di ogni ruolo, poi tutti gli altri a caso.
    select * from ordinati
    order by (rn_ruolo = 1 and macro in ('GK', 'DEF', 'MID', 'ATT')) desc, sorte
    limit 10
  ), inseriti as (
    insert into public.free_agent_auctions
      (league_id, giorno, player_id, ingaggio_teorico, origine, tornata, dalla_coda)
    select p_league_id, p_giorno, s.player_id,
           private.ingaggio_teorico(s.overall_attuale, s.eta_attuale), 'estrazione', v_tornata, true
    from scelti s
    returning player_id
  ), fuori_dai_rilasci as (
    delete from private.rilasci_in_coda
    where league_id = p_league_id and player_id in (select player_id from inseriti)
  )
  delete from private.vetrina_fissa
  where league_id = p_league_id and player_id in (select player_id from inseriti);

  select count(*) into v_dalla_coda from public.free_agent_auctions a
   where a.league_id = p_league_id and a.giorno = p_giorno and a.tornata = v_tornata and a.dalla_coda;
  v_creati := v_creati + v_dalla_coda;

  -- Una comparsa in piu' per tutti quelli in vetrina oggi: dopo 30 giorni di mercato svincolati e non scelti escono
  -- dalla vetrina fissa (restano nel gioco: chi e' fino a 75 puo' tornare a sorte, i non scelti in un draft futuro).
  insert into private.vetrina_comparse (league_id, player_id, comparse)
  select a.league_id, a.player_id, 1 from public.free_agent_auctions a
   where a.league_id = p_league_id and a.giorno = p_giorno and a.tornata = v_tornata
  on conflict (league_id, player_id) do update set comparse = private.vetrina_comparse.comparse + 1, aggiornato_il = now();

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

commit;
