-- ============================================================
--  RIMOZIONE DEI RUOLI LWB/RWB DALLA TASSONOMIA DI GIOCO.
--
--  Deciso con l'utente il 2 settembre 2026: un quinto di centrocampo/
--  centrocampista basso e' gia' trattato bene dal motore (vedi
--  engine/config.js QUASI_NATURALI, 30 agosto 2026 — LB/LM quasi-naturali
--  in uno slot LWB, penalita' 0.98) senza bisogno che sia una posizione a
--  se stante nel catalogo. Un giocatore con quel ruolo diventa un esterno
--  di centrocampo (ruolo primario) con il terzino della stessa fascia
--  come secondario: LWB -> [LM, LB], RWB -> [RM, RB].
--
--  IMPORTANTE: nessun dato reale da migrare. Verificato prima di questa
--  migrazione: zero giocatori nel catalogo hanno LWB/RWB in posizioni
--  (ne' come primario ne' come secondario — il dataset FC26 ne elenca
--  pochissimi, ed erano gia' tutti fuori dal pool importato), zero
--  player_instances.posizioni_override le usano. E' quindi solo una
--  chiusura della tassonomia per il futuro (nuovi import, cambi ruolo,
--  specializzazioni), non una riscrittura di dati esistenti.
--
--  engine/config.js NON viene toccato: resta con le sue voci LWB/RWB
--  (moduli, pesi, compatibilita'), che restano valide per il modulo
--  3-5-2 (i due slot "LWB"/"RWB" nel modulo sono nomi di POSIZIONE IN
--  CAMPO nella formazione, non richiedono che un giocatore abbia quella
--  stringa esatta fra le sue posizioni naturali — la compatibilita' e i
--  quasi-naturali gestiscono gia' questo caso, come facevano anche
--  prima quando i giocatori LWB/RWB nel dataset erano comunque quasi
--  inesistenti). Il motore validato resta invariato.
-- ============================================================

begin;

create or replace function private.ruoli_validi()
returns text[]
language sql
immutable parallel safe
set search_path = ''
as $$
  select array[
    'GK',
    'CB','LB','RB',
    'CDM','CM','CAM','LM','RM',
    'LW','RW','ST','CF'
  ]::text[];
$$;

create or replace function private.ruoli_target_cambio(p_posizioni_attuali text[])
returns text[]
language sql
immutable
security invoker
set search_path = ''
as $$
  select case p_posizioni_attuali[1]
    when 'CB'  then array['LB', 'RB', 'CDM']
    when 'LB'  then array['CB', 'LM']
    when 'RB'  then array['CB', 'RM']
    when 'CDM' then array['CB', 'CM']
    when 'CM'  then array['CDM', 'CAM', 'LM', 'RM']
    when 'CAM' then array['CM', 'CF', 'LW', 'RW']
    when 'LM'  then array['LB', 'LW', 'CM']
    when 'RM'  then array['RB', 'RW', 'CM']
    when 'LW'  then array['LM', 'CAM', 'ST']
    when 'RW'  then array['RM', 'CAM', 'ST']
    when 'ST'  then array['CF', 'LW', 'RW']
    when 'CF'  then array['CAM', 'ST']
    else array[]::text[]
  end;
$$;
comment on function private.ruoli_target_cambio(text[]) is
  'Ruoli raggiungibili da un cambio di ruolo: grafo esplicito di posizioni '
  'vicine (non reparto/adiacenza). LWB e RWB rimossi dalla tassonomia il 2 '
  'settembre 2026: non compaiono piu'' ne'' come target ne'' come punto di '
  'partenza. Il portiere non ha voce (else vuoto): non si riqualifica.';

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
