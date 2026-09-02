-- ============================================================
--  Due sole stat toccate (+7/+4) sembrava un miglioramento inutile,
--  segnalato dall'utente il 2 settembre 2026. Ogni specializzazione ora
--  tocca TRE attributi reali (+8/+5/+3, sempre clampati a 99
--  nell'applicazione), stessa filosofia di prima: solo le stat che il
--  motore legge davvero (finishing, short_passing, standing_tackle,
--  dribbling, stamina), niente attributi cosmetici (pace/shooting/
--  passing/defending/physic) che il motore ignora e che avrebbero reso
--  la fascia "migliorata" finta.
-- ============================================================

begin;

create or replace function private.specializzazioni_ruolo(p_posizione text)
returns jsonb
language sql
immutable
set search_path = ''
as $$
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
    when 'LWB' then jsonb_build_object(
      'corsia_offensiva', jsonb_build_object('etichetta', 'Corsia offensiva',
        'deltas', jsonb_build_object('dribbling', 8, 'stamina', 5, 'short_passing', 3)),
      'corsia_equilibrata', jsonb_build_object('etichetta', 'Corsia equilibrata',
        'deltas', jsonb_build_object('standing_tackle', 8, 'stamina', 5, 'dribbling', 3))
    )
    when 'RWB' then jsonb_build_object(
      'corsia_offensiva', jsonb_build_object('etichetta', 'Corsia offensiva',
        'deltas', jsonb_build_object('dribbling', 8, 'stamina', 5, 'short_passing', 3)),
      'corsia_equilibrata', jsonb_build_object('etichetta', 'Corsia equilibrata',
        'deltas', jsonb_build_object('standing_tackle', 8, 'stamina', 5, 'dribbling', 3))
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
    else '{}'::jsonb
  end
$$;

commit;
