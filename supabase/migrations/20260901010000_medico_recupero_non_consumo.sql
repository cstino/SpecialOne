-- ============================================================
--  REPARTO MEDICO: RECUPERO POST-PARTITA, NON CONSUMO IN PARTITA
--  Deciso il 1 settembre 2026, in conversazione con l'utente, come
--  correzione a 20260901000000_gestione_risorse_punti_abilita.sql.
--
--  Ripensamento importante: l'effetto NON deve toccare il consumo di
--  condizione dentro i 90 minuti (quello resta il modello validato in
--  engine/engine.js, invariato). Agisce invece sul recupero registrato
--  a fine partita: attenua quanto e' stato perso, non quanto si
--  perde durante il match.
--
--  Formula (applicata quando arriva il pezzo che collega l'effetto,
--  non ancora in questa migrazione):
--    condizione_finale = prima - (prima - risultato_engine) * (1 - riduzione%)
--  Esempio confermato dall'utente: un calo da 100 a 91 (-9) con
--  REPARTO MEDICO 10/10 diventa 100 - 9*0.60 = 94.6 -> 95.
--
--  Curva precedente (-2%/livello, max -20%) perdeva risoluzione
--  sull'arrotondamento a intero: su un calo tipico di ~9 punti, i
--  livelli 1-2 e 3-8 non si distinguevano mai a schermo (91/91/92/93).
--  Nuova curva -4%/livello, max -40%: lo stesso calo di 9 diventa
--  visibilmente diverso quasi a ogni livello (91/91/92/92/93/93/94/94/94/95).
--
--  Non tocca vivaio ne' training. Non serve validazione con
--  tools/validazione/simulate.js: l'engine non cambia, cambia solo il
--  valore scritto dopo che l'engine ha gia' calcolato il suo.
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
      'riduzione_infortuni_pct', p_livello * 3,
      -- Non e' un taglio al consumo dentro la partita: attenua quanto
      -- della condizione persa NON viene riassorbito dal recupero
      -- post-partita gia' presente nel motore (REC_GIOCATO/PANCHINA/
      -- TRIBUNA in engine/config.js). Vedi la nota in testa al file.
      'riduzione_calo_residuo_pct', p_livello * 4
    )
  end
$$;

comment on function private.effetti_ramo(text, smallint) is
  'Curva effetti per livello dei tre rami (vivaio/training/medico). Unica fonte di verita: letta sia dal backend sia da tabella_risorse() per il frontend.';
