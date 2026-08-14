-- Alcune versioni della Edge Function hanno salvato i tiri della cronaca
-- estesa senza `minuto` e `blocco`. Nel client `null <= minutoCorrente` e'
-- vero e la partita mostra quindi subito tutti quei tiri.
--
-- Non esiste un minuto storico da recuperare: per ogni partita coinvolta gli
-- eventi mancanti vengono distribuiti in modo deterministico lungo i 90',
-- mantenendo l'ordine con cui erano stati salvati. I gol e ogni evento gia'
-- valido non vengono modificati.
with eventi_invalidi as (
  select
    m.id as match_id,
    evento.ordinalita,
    row_number() over (partition by m.id order by evento.ordinalita) as posizione,
    count(*) over (partition by m.id) as totale
  from public.matches m
  cross join lateral jsonb_array_elements(m.blocchi) with ordinality
    as evento(valore, ordinalita)
  where coalesce(jsonb_typeof(evento.valore->'minuto'), 'null') <> 'number'
     or coalesce(evento.valore->>'minuto', '') !~ '^[0-9]+$'
     or (evento.valore->>'minuto')::integer not between 1 and 90
), minuti_riparati as (
  select
    match_id,
    ordinalita,
    least(90, greatest(1, ceil(90.0 * posizione / (totale + 1))::integer)) as minuto
  from eventi_invalidi
), cronache_riparate as (
  select
    m.id as match_id,
    jsonb_agg(
      case
        when riparato.minuto is null then evento.valore
        else jsonb_set(
          jsonb_set(evento.valore, '{minuto}', to_jsonb(riparato.minuto), true),
          '{blocco}', to_jsonb(ceil(riparato.minuto / 15.0)::integer), true
        )
      end
      order by evento.ordinalita
    ) as blocchi
  from public.matches m
  cross join lateral jsonb_array_elements(m.blocchi) with ordinality
    as evento(valore, ordinalita)
  left join minuti_riparati riparato
    on riparato.match_id = m.id
   and riparato.ordinalita = evento.ordinalita
  group by m.id
)
update public.matches m
set blocchi = cronache_riparate.blocchi
from cronache_riparate
where m.id = cronache_riparate.match_id
  and m.blocchi is distinct from cronache_riparate.blocchi;
