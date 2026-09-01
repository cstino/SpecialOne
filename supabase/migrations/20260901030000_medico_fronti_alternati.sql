-- ============================================================
--  REPARTO MEDICO: I DUE FRONTI SI ALTERNANO PER LIVELLO
--  Deciso il 1 settembre 2026, in conversazione con l'utente.
--
--  Finora ogni livello alzava insieme sia il recupero post-partita sia
--  la resistenza agli infortuni: un singolo punto muoveva due numeri
--  contemporaneamente, poco leggibile a schermo. Da ora ogni livello
--  fa avanzare UN SOLO fronte alla volta, alternando:
--    dispari (1,3,5,7,9) -> recupero
--    pari    (2,4,6,8,10) -> infortuni
--
--  I traguardi finali a 10/10 restano quelli gia' tarati e verificati
--  in 20260901010000/20260901020000 (recupero -40%, infortuni -30%):
--  cambia solo QUANDO si sbloccano, non quanto valgono al massimo. Con
--  5 passi a testa, ogni passo vale il doppio di prima (recupero +8%
--  invece di +4%, infortuni +6% invece di +3%).
--
--  floor(livello/2) conta i pari raggiunti, ceil(livello/2) i dispari:
--  in SQL su interi non negativi, livello/2 e' floor, (livello+1)/2 e'
--  ceil, senza bisogno di cast a float.
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
      -- Moltiplicatore sulla crescita gia' esistente della progressione
      -- trimestrale: +5% per livello, massimo +50%. Tenuto volutamente
      -- contenuto per non rompere l'equilibrio della progressione.
      'moltiplicatore_crescita', round(1.0 + p_livello * 0.05, 2),
      'riduzione_tempi_ruolo_pct', p_livello * 4
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
