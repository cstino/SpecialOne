-- ============================================================
--  TRAINING: I DUE FRONTI SI ALTERNANO PER LIVELLO
--  Deciso il 1 settembre 2026, in conversazione con l'utente. Stesso
--  ragionamento gia' applicato al reparto medico in 20260901030000.
--
--  Prima ogni livello alzava insieme moltiplicatore di crescita e
--  riduzione dei tempi di cambio ruolo. Ora si alternano:
--    dispari (1,3,5,7,9) -> moltiplicatore di crescita
--    pari    (2,4,6,8,10) -> tempi di cambio ruolo
--
--  Traguardi finali a 10/10 invariati (moltiplicatore x1.50, tempi di
--  ruolo -40%): cambia solo quando si sbloccano. 5 passi a testa, ogni
--  passo vale il doppio di prima (+0.10 invece di +0.05 sul
--  moltiplicatore, -8% invece di -4% sui tempi).
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
      -- Ampiezza della forbice di potenziale mostrata sul giovane: 15 punti
      -- di incertezza a livello 0 (es. "71-86"), zero a 10 (valore esatto).
      'ampiezza_range', round(15.0 * (10 - p_livello) / 10.0)::int
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
