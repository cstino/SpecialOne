-- Attributi correnti: il piano di specializzazione si calcola una volta per
-- piano e reparto, non una volta per giocatore.
--
-- La sera del 10/11/2026 la Serie F non si e' simulata: 398 giocatori con un
-- piano attivo erano cresciuti dopo le giornate 1 e 2, e per ognuno
-- scostamenti_piano ripartiva da capo (circa 50 ms a testa). La funzione
-- arrivava a 20 secondi contro gli 8 concessi alle chiamate del server, e
-- peggiorava a ogni giornata.
--
-- Lo scostamento del piano e' proporzionale alla crescita: scostamenti_piano
-- (piano, reparto, delta) = |delta| x scostamenti_piano(piano, reparto, 1).
-- Quindi si calcola il valore unitario per ogni coppia piano-reparto presente
-- (una quarantina) e lo si moltiplica. Il resto del conto e' quello di
-- private.attributi_istanza, che resta com'e' per gli altri usi.
-- Verificato prima di applicarla: risultato identico su tutti i 2.121
-- giocatori di Serie F e LegaBot, 0,4 secondi invece di 20.

create or replace function public.attributi_correnti(p_instance_ids bigint[])
returns table (instance_id bigint, attributi jsonb)
language sql
stable
security definer
set search_path = ''
as $$
  with ist as (
    select pi.id, p.attributi as attr, private.macro_ruolo(coalesce(pi.posizioni_override, p.posizioni)) as reparto,
      pi.overall_corrente, p.overall as overall_catalogo, pi.piano_scostamenti, pi.specializzazione_attiva as piano,
      case when pi.piano_overall_rif is null then 0 else pi.overall_corrente - pi.piano_overall_rif end as delta
    from public.player_instances pi
    join public.players p on p.id = pi.player_id
    where pi.id = any(p_instance_ids)
  ), unita as (
    select x.piano, x.reparto, private.scostamenti_piano(x.piano, x.reparto, 1) as u
    from (select distinct i.piano, i.reparto from ist i where i.piano is not null and i.delta <> 0) x
  )
  select ist.id, (
    select coalesce(jsonb_object_agg(k,
      greatest(1, least(99, round(
        (ist.attr->>k)::numeric
        + coalesce(pe.pendenza, 0) * coalesce(ist.overall_corrente - ist.overall_catalogo, 0)
        + coalesce((ist.piano_scostamenti->>k)::numeric, 0)
        + coalesce((un.u->>k)::numeric * abs(ist.delta), 0)
      )))::int), '{}'::jsonb)
    from jsonb_object_keys(coalesce(ist.attr, '{}'::jsonb)) as k
    left join private.pendenze_attributi pe on pe.reparto = ist.reparto and pe.attributo = k
    where (ist.attr->>k) ~ '^[0-9]+$'
  )
  from ist
  left join unita un on un.piano = ist.piano and un.reparto = ist.reparto
$$;
