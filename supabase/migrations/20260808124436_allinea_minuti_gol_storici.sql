-- Prima della cronaca estesa il minuto del gol era un dato di presentazione
-- indipendente dai minuti giocati. L'animazione lo corregge gia' al volo;
-- questo backfill rende coerente anche la fonte salvata e tutti i riepiloghi.
with partite_legacy as (
  select m.id, m.titolari_home, m.titolari_away,
         f.home_team_id, f.away_team_id
  from public.matches m
  join public.fixtures f on f.id = m.fixture_id
  where jsonb_array_length(m.blocchi) > 0
    and not exists (
      select 1
      from jsonb_array_elements(m.blocchi) elemento
      where not (elemento ? 'marcatore')
    )
), eventi_correggibili as (
  select m.id as match_id, evento.ordinalita, evento.valore,
         ms.minuti,
         (evento.valore->>'minuto')::integer as minuto_vecchio,
         (evento.valore->>'marcatore')::bigint = any(
           case
             when (evento.valore->>'team_id')::bigint = m.home_team_id then m.titolari_home
             when (evento.valore->>'team_id')::bigint = m.away_team_id then m.titolari_away
             else '{}'::bigint[]
           end
         ) as titolare
  from partite_legacy m
  join public.matches partita on partita.id = m.id
  cross join lateral jsonb_array_elements(partita.blocchi) with ordinality
    as evento(valore, ordinalita)
  left join public.match_stats ms
    on ms.match_id = m.id
   and ms.player_instance_id = (evento.valore->>'marcatore')::bigint
), eventi_normalizzati as (
  select match_id, ordinalita, valore,
         case
           when minuti is null or minuti <= 0 then minuto_vecchio
           when titolare then greatest(1, least(minuto_vecchio, minuti))
           else greatest(greatest(1, 90 - minuti), least(minuto_vecchio, 90))
         end as minuto_nuovo
  from eventi_correggibili
), cronache as (
  select match_id,
         jsonb_agg(
           jsonb_set(
             jsonb_set(valore, '{minuto}', to_jsonb(minuto_nuovo), false),
             '{blocco}', to_jsonb(ceil(minuto_nuovo / 15.0)::integer), false
           )
           order by ordinalita
         ) as blocchi
  from eventi_normalizzati
  group by match_id
)
update public.matches m
set blocchi = c.blocchi
from cronache c
where m.id = c.match_id
  and m.blocchi is distinct from c.blocchi;
