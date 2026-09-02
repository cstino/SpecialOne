-- ============================================================
--  AMPIEZZA DELLA FASCIA DI POTENZIALE: 20 PUNTI A LIVELLO 0, NON 15
--
--  Deciso dall'utente il 2 settembre 2026: la fascia mostrata sui
--  prospetti vivaio era troppo stretta per nascondere davvero il valore
--  (15 punti, es. "71-86"). Stessa progressione lineare a zero a livello
--  10 (valore esatto), solo il punto di partenza si allarga.
--
--  Nessun'altra colonna di private.effetti_ramo tocca: training e medico
--  restano quelli di 20260901040000_training_fronti_alternati.sql.
--  Nessun dato da correggere a ritroso: l'ampiezza si calcola al volo a
--  ogni chiamata di fascia_potenziale_giocatori, non e' mai salvata.
-- ============================================================

create or replace function private.effetti_ramo(p_ramo text, p_livello smallint)
returns jsonb
language sql
immutable
set search_path = ''
as $$
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
      'riduzione_calo_residuo_pct', ((p_livello + 1) / 2) * 8
    )
  end
$$;
