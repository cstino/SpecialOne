-- ============================================================
--  REPARTO MEDICO: GUARIGIONE PIU' VELOCE (18 ottobre 2026, deciso con l'utente).
--  Prima il medico riduceva solo il rischio di infortunarsi e il calo di condizione: un infortunio in corso seguiva il
--  suo conto alla rovescia (-1 a giornata) qualunque fosse il livello. Ora, a ogni giornata, un infortunato ha una
--  probabilita' pari a 3% x livello medico (fino al 30% al livello 10) di rientrare una giornata prima. Vale anche
--  per gli infortuni gia' in corso, dalla prossima giornata; non per quelli nuovi nel momento in cui avvengono.
--  Niente modifiche al motore: l'effetto e' in aggiorna_condizione_rosa, che aggiorna il database dopo ogni partita.
--  Funzioni riscritte dalla definizione viva.
-- ============================================================
begin;
CREATE OR REPLACE FUNCTION private.effetti_ramo(p_ramo text, p_livello smallint)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select case p_ramo
    when 'vivaio' then jsonb_build_object(
      'livello', p_livello,
      -- Si parte con uno slot e si arriva a cinque: +1 ai livelli 3, 5, 7 e 10.
      'slot', 1 + (p_livello >= 3)::int + (p_livello >= 5)::int
                + (p_livello >= 7)::int + (p_livello >= 10)::int,
      -- Ampiezza della forbice di potenziale mostrata sul giovane: 20 punti
      -- di incertezza a livello 0 (es. "68-88"), zero a 10 (valore esatto).
      'ampiezza_range', round(20.0 * (10 - p_livello) / 10.0)::int
    )
    when 'training' then jsonb_build_object(
      'livello', p_livello,
      -- Fronte dispari: sale ai livelli 1, 3, 5, 7, 9. Max 1.0 + 5*0.10 = 1.50.
      'moltiplicatore_crescita', round(1.0 + ((p_livello + 1) / 2) * 0.10, 2),
      -- Fronte pari: sale ai livelli 2, 4, 6, 8, 10. Max 5*8 = 40%.
      'riduzione_tempi_ruolo_pct', (p_livello / 2) * 8
    )
    when 'medico' then jsonb_build_object(
      'livello', p_livello,
      -- Fronte pari: sale ai livelli 2, 4, 6, 8, 10. Max 5*6 = 30%.
      'riduzione_infortuni_pct', (p_livello / 2) * 6,
      -- Fronte dispari: sale ai livelli 1, 3, 5, 7, 9. Max 5*8 = 40%.
      -- Stessa semantica di prima (attenua il calo non riassorbito dal
      -- recupero post-partita del motore, non tocca il consumo in gara).
      'riduzione_calo_residuo_pct', ((p_livello + 1) / 2) * 8,
      -- Guarigione (18 ottobre 2026, deciso con l'utente): a ogni giornata un infortunato ha questa probabilita'
      -- (in %) di rientrare UNA giornata prima. 3% per livello, fino al 30%.
      'recupero_infortuni_pct', p_livello * 3
    )
  end
$function$;

CREATE OR REPLACE FUNCTION public.aggiorna_condizione_rosa(p_league_id bigint, p_valori jsonb)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_aggiornati integer;
begin
  if jsonb_typeof(p_valori) <> 'array' then
    raise exception using errcode = '22023', message = 'Payload condizione non valido.';
  end if;

  with valori as (
    select *
    from jsonb_to_recordset(p_valori) as x(
      id                 bigint,
      condizione         smallint,
      infortunato_fino_a smallint
    )
  ), riduzioni as (
    select
      v.id,
      v.condizione as grezza,
      v.infortunato_fino_a,
      pi.infortunato_fino_a as inf_prima,
      coalesce((
        select (private.effetti_ramo('medico', tr.livello_medico)->>'recupero_infortuni_pct')::numeric
        from public.team_risorse tr
        where tr.team_id = pi.team_id
      ), 0) as recupero_pct,
      pi.condizione as prima,
      coalesce((
        select (private.effetti_ramo('medico', tr.livello_medico)->>'riduzione_calo_residuo_pct')::numeric
        from public.team_risorse tr
        where tr.team_id = pi.team_id
      ), 0) as riduzione_pct
    from valori v
    join public.player_instances pi on pi.id = v.id and pi.league_id = p_league_id
  )
  update public.player_instances pi
  set condizione = least(100, greatest(0, round(
        case when r.grezza < r.prima
          then r.prima - (r.prima - r.grezza) * (1 - r.riduzione_pct / 100.0)
          else r.grezza
        end
      )::int)),
      -- Reparto medico: un infortunio GIA' IN CORSO (il valore e' sceso rispetto a prima) puo' chiudersi una giornata prima.
      -- Un infortunio nuovo (valore salito) non si accorcia mai.
      infortunato_fino_a = greatest(0, r.infortunato_fino_a
        - case when r.infortunato_fino_a > 0 and r.infortunato_fino_a < r.inf_prima and random() < r.recupero_pct / 100.0 then 1 else 0 end)
  from riduzioni r
  where pi.id = r.id;

  get diagnostics v_aggiornati = row_count;
  return v_aggiornati;
end;
$function$;

commit;
