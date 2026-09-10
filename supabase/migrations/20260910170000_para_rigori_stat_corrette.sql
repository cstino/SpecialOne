-- ============================================================
--  "PARA RIGORI" ALZAVA LA STAT PER CALCIARE I RIGORI
--
--  Segnalato dall'utente il 10 settembre 2026, guardando la scheda di un
--  portiere in allenamento: "ma gli aumenta anche il tiro dei rigori?".
--  Si', e non doveva. Avevo scelto mentality_penalties, che in FC 26 e' la
--  precisione di chi CALCIA un rigore, non di chi lo para. Sulla scheda si
--  vedeva salire dentro il gruppo "Tiro", accanto a Finalizzazione e Volee:
--  su un portiere e' un controsenso evidente.
--
--  Nessun effetto meccanico, verificato prima di correggere: il motore non
--  legge mai quell'attributo (zero occorrenze in engine/ e nella Edge
--  Function) e tiratoriDaLineup() esclude sempre il portiere dai rigoristi.
--  Era quindi rumore puramente estetico — ma sbagliato, e sotto gli occhi
--  di chiunque apra la scheda.
--
--  Ora "Para rigori" alza le tre stat che un rigore lo parano davvero:
--  Tuffo, Riflessi, Presa. Valori piu' bassi di "Fuori dai pali" (10 punti
--  totali contro 16) per tenere il bonus overall a +1 invece di +2:
--  l'equilibrio deciso con l'utente non cambia, resta una specializzazione
--  piu' stretta che si paga in campionato e si riscuote ai rigori.
--  Verificato dal vivo: bonus_overall_specializzazione('GK', nuovi deltas)
--  restituisce +1.
--
--  Il vantaggio vero ai rigori non passa da qui: vive in engine/rigori.js
--  (BONUS_PARA_RIGORI) ed e' legato al nome della specializzazione, non ai
--  suoi attributi. Resta quindi invariato.
-- ============================================================

begin;

CREATE OR REPLACE FUNCTION private.specializzazioni_ruolo(p_posizione text)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select case p_posizione
    when 'CB' then jsonb_build_object(
      'marcatore', jsonb_build_object('etichetta', 'Marcatore',
        'deltas', jsonb_build_object('standing_tackle', 8, 'stamina', 5, 'short_passing', 3)),
      'libero', jsonb_build_object('etichetta', 'Libero',
        'deltas', jsonb_build_object('short_passing', 8, 'standing_tackle', 5, 'dribbling', 3))
    )
    when 'LB' then jsonb_build_object(
      'terzino_difensivo', jsonb_build_object('etichetta', 'Terzino difensivo',
        'deltas', jsonb_build_object('standing_tackle', 8, 'stamina', 5, 'short_passing', 3)),
      'terzino_offensivo', jsonb_build_object('etichetta', 'Terzino offensivo',
        'deltas', jsonb_build_object('dribbling', 8, 'stamina', 5, 'short_passing', 3)),
      'regista_basso', jsonb_build_object('etichetta', 'Regista basso',
        'deltas', jsonb_build_object('short_passing', 8, 'standing_tackle', 5, 'dribbling', 3))
    )
    when 'RB' then jsonb_build_object(
      'terzino_difensivo', jsonb_build_object('etichetta', 'Terzino difensivo',
        'deltas', jsonb_build_object('standing_tackle', 8, 'stamina', 5, 'short_passing', 3)),
      'terzino_offensivo', jsonb_build_object('etichetta', 'Terzino offensivo',
        'deltas', jsonb_build_object('dribbling', 8, 'stamina', 5, 'short_passing', 3)),
      'regista_basso', jsonb_build_object('etichetta', 'Regista basso',
        'deltas', jsonb_build_object('short_passing', 8, 'standing_tackle', 5, 'dribbling', 3))
    )
    when 'CDM' then jsonb_build_object(
      'schermo_difensivo', jsonb_build_object('etichetta', 'Schermo difensivo',
        'deltas', jsonb_build_object('standing_tackle', 8, 'stamina', 5, 'short_passing', 3)),
      'regista_arretrato', jsonb_build_object('etichetta', 'Regista arretrato',
        'deltas', jsonb_build_object('short_passing', 8, 'standing_tackle', 5, 'stamina', 3))
    )
    when 'CM' then jsonb_build_object(
      'regista', jsonb_build_object('etichetta', 'Regista',
        'deltas', jsonb_build_object('short_passing', 8, 'dribbling', 5, 'stamina', 3)),
      'box_to_box', jsonb_build_object('etichetta', 'Box-to-box',
        'deltas', jsonb_build_object('stamina', 8, 'standing_tackle', 5, 'short_passing', 3)),
      'recupera_palloni', jsonb_build_object('etichetta', 'Recupera palloni',
        'deltas', jsonb_build_object('standing_tackle', 8, 'stamina', 5, 'dribbling', 3)),
      'mezzala_inserimento', jsonb_build_object('etichetta', 'Mezz''ala d''inserimento',
        'deltas', jsonb_build_object('finishing', 8, 'dribbling', 5, 'stamina', 3))
    )
    when 'CAM' then jsonb_build_object(
      'rifinitore', jsonb_build_object('etichetta', 'Rifinitore',
        'deltas', jsonb_build_object('short_passing', 8, 'dribbling', 5, 'finishing', 3)),
      'mezzala_inserimento', jsonb_build_object('etichetta', 'Mezz''ala d''inserimento',
        'deltas', jsonb_build_object('finishing', 8, 'dribbling', 5, 'short_passing', 3))
    )
    when 'LM' then jsonb_build_object(
      'ala_di_fascia', jsonb_build_object('etichetta', 'Ala di fascia',
        'deltas', jsonb_build_object('dribbling', 8, 'stamina', 5, 'short_passing', 3)),
      'mezzala_di_fascia', jsonb_build_object('etichetta', 'Mezzala di fascia',
        'deltas', jsonb_build_object('standing_tackle', 8, 'stamina', 5, 'dribbling', 3))
    )
    when 'RM' then jsonb_build_object(
      'ala_di_fascia', jsonb_build_object('etichetta', 'Ala di fascia',
        'deltas', jsonb_build_object('dribbling', 8, 'stamina', 5, 'short_passing', 3)),
      'mezzala_di_fascia', jsonb_build_object('etichetta', 'Mezzala di fascia',
        'deltas', jsonb_build_object('standing_tackle', 8, 'stamina', 5, 'dribbling', 3))
    )
    when 'LW' then jsonb_build_object(
      'ala_rapida', jsonb_build_object('etichetta', 'Ala rapida',
        'deltas', jsonb_build_object('dribbling', 8, 'stamina', 5, 'finishing', 3)),
      'rifinitore_esterno', jsonb_build_object('etichetta', 'Rifinitore esterno',
        'deltas', jsonb_build_object('short_passing', 8, 'dribbling', 5, 'finishing', 3)),
      'ala_realizzatrice', jsonb_build_object('etichetta', 'Ala realizzatrice',
        'deltas', jsonb_build_object('finishing', 8, 'dribbling', 5, 'short_passing', 3))
    )
    when 'RW' then jsonb_build_object(
      'ala_rapida', jsonb_build_object('etichetta', 'Ala rapida',
        'deltas', jsonb_build_object('dribbling', 8, 'stamina', 5, 'finishing', 3)),
      'rifinitore_esterno', jsonb_build_object('etichetta', 'Rifinitore esterno',
        'deltas', jsonb_build_object('short_passing', 8, 'dribbling', 5, 'finishing', 3)),
      'ala_realizzatrice', jsonb_build_object('etichetta', 'Ala realizzatrice',
        'deltas', jsonb_build_object('finishing', 8, 'dribbling', 5, 'short_passing', 3))
    )
    when 'ST' then jsonb_build_object(
      'rapace_area', jsonb_build_object('etichetta', 'Rapace d''area',
        'deltas', jsonb_build_object('finishing', 8, 'dribbling', 5, 'stamina', 3)),
      'bomber_fisico', jsonb_build_object('etichetta', 'Bomber fisico',
        'deltas', jsonb_build_object('stamina', 8, 'finishing', 5, 'dribbling', 3)),
      'falso_nueve', jsonb_build_object('etichetta', 'Falso nueve',
        'deltas', jsonb_build_object('short_passing', 8, 'dribbling', 5, 'finishing', 3))
    )
    when 'CF' then jsonb_build_object(
      'falso_nueve', jsonb_build_object('etichetta', 'Falso nueve',
        'deltas', jsonb_build_object('short_passing', 8, 'dribbling', 5, 'finishing', 3)),
      'rapace_area', jsonb_build_object('etichetta', 'Rapace d''area',
        'deltas', jsonb_build_object('finishing', 8, 'dribbling', 5, 'stamina', 3))
    )
    -- 10 settembre 2026: il portiere entra nel training. Non il cambio
    -- ruolo (resta escluso), solo la specializzazione.
    --
    -- Perche' solo DUE strade e non tre. Il motore usa del portiere un
    -- unico numero: forzeLinee() lo tiene fuori da DEF/MID/ATT e il suo
    -- overall entra solo in "xg *= (1 - (GK - 75) / DIVISORE_PORTIERE)".
    -- Qualunque specializzazione che alzi l'overall fa quindi esattamente
    -- la stessa cosa: parare di piu'. Tre strade sarebbero state tre
    -- etichette sullo stesso effetto. L'unica leva davvero separata che
    -- esiste sono i rigori (engine/rigori.js, che si dichiara fuori dal
    -- nucleo validato in Fase 0), ed e' li' che si differenzia la seconda.
    when 'GK' then jsonb_build_object(
      'fuori_dai_pali', jsonb_build_object('etichetta', 'Fuori dai pali',
        'deltas', jsonb_build_object('gk_reflexes', 8, 'goalkeeping_speed', 5, 'gk_positioning', 3)),
      -- Correzione del 10 settembre 2026, segnalata dall'utente: prima qui
      -- c'era mentality_penalties, che e' la stat per CALCIARE un rigore, non
      -- per pararlo. Su un portiere non ha senso, e si vedeva: la scheda la
      -- mostrava salire nel gruppo "Tiro". Nessun effetto meccanico (il
      -- motore non legge mai quell'attributo e tiratoriDaLineup esclude
      -- sempre il portiere), ma era rumore sbagliato sotto gli occhi di
      -- tutti. Sostituita con le tre stat che un rigore lo parano davvero.
      -- I valori sono piu' bassi di "Fuori dai pali" (10 punti totali contro
      -- 16) per tenere il bonus overall a +1 invece di +2: e' una
      -- specializzazione piu' stretta, che si paga in campionato e si
      -- riscuote ai rigori.
      'para_rigori', jsonb_build_object('etichetta', 'Para rigori',
        'deltas', jsonb_build_object('gk_diving', 5, 'gk_reflexes', 3, 'gk_handling', 2))
    )
    else '{}'::jsonb
  end
$function$
;

commit;
