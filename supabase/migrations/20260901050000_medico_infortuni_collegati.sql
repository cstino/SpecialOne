-- ============================================================
--  REPARTO MEDICO: EFFETTO VERO SULLA RESISTENZA AGLI INFORTUNI
--  Deciso il 1 settembre 2026, in conversazione con l'utente.
--
--  Chiude il ramo REPARTO MEDICO: dopo il recupero post-partita
--  (20260901020000), collega anche l'altro fronte. A differenza del
--  recupero, questo TOCCA l'engine (engine/engine.js, gia' modificato
--  e validato con tools/validazione/simulate.js: le due sole
--  deviazioni accettate in docs/risultati-fase0.txt restano identiche,
--  nessuna nuova).
--
--  L'engine non riceve una formula nuova: legge un moltiplicatore
--  facoltativo (rosa.moltiplicatoreInfortuni) che di default e' 1
--  (nessun effetto) e che qui popoliamo con
--    1 - riduzione_infortuni_pct / 100
--  usando la stessa curva alternata di private.effetti_ramo (unica
--  fonte di verita', non duplicata qui).
--
--  private.effetti_ramo non e' esposta da PostgREST (schema privato):
--  questo wrapper pubblico e' il solo modo per l'edge function di
--  leggerla, in un'unica chiamata per tutte le squadre della giornata
--  invece di una query per squadra.
-- ============================================================

create or replace function public.moltiplicatori_infortuni_squadre(p_team_ids bigint[])
returns table(team_id bigint, moltiplicatore numeric)
language sql
stable
set search_path = ''
as $$
  select
    t.id,
    1 - coalesce(
      (private.effetti_ramo('medico', coalesce(tr.livello_medico, 0::smallint))->>'riduzione_infortuni_pct')::numeric,
      0
    ) / 100.0
  from public.teams t
  left join public.team_risorse tr on tr.team_id = t.id
  where t.id = any(p_team_ids)
$$;

grant execute on function public.moltiplicatori_infortuni_squadre(bigint[]) to authenticated;
