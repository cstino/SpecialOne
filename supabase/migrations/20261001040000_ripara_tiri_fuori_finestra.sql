-- ============================================================
--  CRONACA: TIRI ATTRIBUITI A CHI NON ERA ANCORA (O NON ERA PIU') IN CAMPO
--
--  Causa: nella Edge Function il generatore creaRng() riceveva il seme
--  `seed ^ 0x9e3779b9`, che in JavaScript e' un intero a 32 bit con segno.
--  Con seme negativo restituiva numeri negativi (circa meta' delle partite):
--  blocchi e minuti dei tiri uscivano dall'intervallo, gli eventi senza
--  minuto valido venivano ridistribuiti per posizione e i tiri finivano
--  prima dell'ingresso del giocatore. Corretto nella Edge Function (>>> 0).
--
--  Qui si riparano i tiri delle partite degli ultimi 3 giorni: ogni tiro
--  fuori dalla finestra di presenza del tiratore viene spostato, in modo
--  deterministico, dentro la sua finestra e nella stessa fase (90' o
--  supplementari). Totali, marcatori e statistiche individuali non cambiano:
--  cambia solo QUANDO la cronaca mostra il tiro.
-- ============================================================

with ev as (
  select m.id as mid, t.ord, t.e
  from public.matches m
  cross join lateral jsonb_array_elements(m.blocchi) with ordinality as t(e, ord)
  where jsonb_typeof(m.blocchi) = 'array'
    and m.simulata_il >= now() - interval '3 days'
), ingresso as (
  select mid, (e->>'entra')::bigint as pl, min((e->>'minuto')::int) as min_in
  from ev where e->>'tipo' in ('sostituzione', 'infortunio') group by 1, 2
), uscita as (
  select mid, pl, min(mn) as min_out from (
    select mid, (e->>'esce')::bigint as pl, (e->>'minuto')::int as mn
      from ev where e->>'tipo' in ('sostituzione', 'infortunio')
    union all
    select mid, (e->>'giocatore')::bigint, (e->>'minuto')::int
      from ev where e->>'tipo' = 'cartellino' and e->>'colore' <> 'giallo'
  ) x group by 1, 2
), tiri as (
  select ev.mid, ev.ord, (ev.e->>'minuto')::int as mn,
         coalesce(i.min_in, 0) as lo, coalesce(u.min_out, 120) as hi
  from ev
  left join ingresso i on i.mid = ev.mid and i.pl = (ev.e->>'giocatore')::bigint
  left join uscita u on u.mid = ev.mid and u.pl = (ev.e->>'giocatore')::bigint
  where ev.e->>'tipo' in ('tiro_parato', 'tiro_fuori')
), finestre as (
  select mid, ord, mn, lo, hi,
         case when mn <= 90 then lo + 1 else greatest(lo + 1, 91) end as da,
         case when mn <= 90 then least(hi, 90) else hi end as a
  from tiri
), spostati as (
  select mid, ord,
         da + (abs(hashtext(mid::text || '-' || ord::text)) % (a - da + 1)) as nuovo
  from finestre
  where (mn <= lo or mn > hi) and da <= a
), ricostruite as (
  select ev.mid,
         jsonb_agg(
           case when s.nuovo is null then ev.e
                else ev.e || jsonb_build_object('minuto', s.nuovo, 'blocco', ceil(s.nuovo / 15.0)::int) end
           order by coalesce(s.nuovo, (ev.e->>'minuto')::int), (ev.e->>'team_id')::bigint, ev.ord
         ) as blocchi
  from ev
  left join spostati s on s.mid = ev.mid and s.ord = ev.ord
  where ev.mid in (select mid from spostati)
  group by ev.mid
)
update public.matches m
set blocchi = r.blocchi
from ricostruite r
where m.id = r.mid;
