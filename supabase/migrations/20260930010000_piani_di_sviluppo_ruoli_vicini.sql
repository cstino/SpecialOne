-- ============================================================
--  PIANI DI SVILUPPO: PIU' SCELTA, APERTI AI RUOLI VICINI
--
--  Ogni ruolo vedeva solo i piani del proprio ruolo (2-4) e il piano gia'
--  attivo spariva dall'elenco: un'ala con "Ala di fascia" ne vedeva uno solo.
--  Ora ogni ruolo vede anche i piani dei ruoli vicini (un centrocampista
--  centrale anche quelli da mediano e da trequartista, un terzino anche
--  quelli da laterale di centrocampo, ...).
--
--  Non cambia nessun numero del modello: ogni piano pesa tutte le abilita' e
--  ridistribuisce la crescita a somma zero (private.piano_pesi), quindi un
--  piano "di un altro ruolo" non e' piu' forte o piu' debole degli altri; e'
--  solo un'altra forma per lo stesso giocatore. I pesi sono per abilita', e
--  il reparto (DEF/MID/ATT) decide solo le pendenze.
--
--  L'elenco dei piani e' ora uno solo (private.piani_ruoli): il catalogo
--  di un ruolo e le etichette di un piano ereditato da un ruolo vecchio
--  (cambio ruolo) leggono entrambi da li'.
--
--  specializzazioni_disponibili restituisce sempre anche il piano attivo,
--  anche se il ruolo attuale non lo offre piu' (dopo un cambio di ruolo),
--  cosi' la scheda ne mostra l'etichetta invece della chiave grezza.
-- ============================================================

create or replace function private.piani_ruoli()
returns table (ruolo text, chiave text, etichetta text)
language sql
immutable
set search_path = ''
as $$
  select * from (values
    ('*', 'bilanciato', 'Bilanciato'),

    -- Difensore centrale
    ('CB', 'marcatore', 'Marcatore'), ('CB', 'libero', 'Libero'),
    ('CB', 'terzino_difensivo', 'Terzino difensivo'), ('CB', 'schermo_difensivo', 'Schermo difensivo'),

    -- Terzini
    ('LB', 'terzino_difensivo', 'Terzino difensivo'), ('LB', 'terzino_offensivo', 'Terzino offensivo'), ('LB', 'regista_basso', 'Regista basso'),
    ('LB', 'ala_di_fascia', 'Ala di fascia'), ('LB', 'mezzala_di_fascia', 'Mezzala di fascia'), ('LB', 'marcatore', 'Marcatore'),
    ('RB', 'terzino_difensivo', 'Terzino difensivo'), ('RB', 'terzino_offensivo', 'Terzino offensivo'), ('RB', 'regista_basso', 'Regista basso'),
    ('RB', 'ala_di_fascia', 'Ala di fascia'), ('RB', 'mezzala_di_fascia', 'Mezzala di fascia'), ('RB', 'marcatore', 'Marcatore'),

    -- Mediano
    ('CDM', 'schermo_difensivo', 'Schermo difensivo'), ('CDM', 'regista_arretrato', 'Regista arretrato'),
    ('CDM', 'box_to_box', 'Box-to-box'), ('CDM', 'recupera_palloni', 'Recupera palloni'), ('CDM', 'regista', 'Regista'),

    -- Centrocampista centrale
    ('CM', 'regista', 'Regista'), ('CM', 'box_to_box', 'Box-to-box'), ('CM', 'recupera_palloni', 'Recupera palloni'), ('CM', 'mezzala_inserimento', 'Mezz''ala d''inserimento'),
    ('CM', 'schermo_difensivo', 'Schermo difensivo'), ('CM', 'regista_arretrato', 'Regista arretrato'), ('CM', 'rifinitore', 'Rifinitore'),

    -- Trequartista
    ('CAM', 'rifinitore', 'Rifinitore'), ('CAM', 'mezzala_inserimento', 'Mezz''ala d''inserimento'),
    ('CAM', 'regista', 'Regista'), ('CAM', 'falso_nueve', 'Falso nueve'), ('CAM', 'rifinitore_esterno', 'Rifinitore esterno'),

    -- Laterali di centrocampo
    ('LM', 'ala_di_fascia', 'Ala di fascia'), ('LM', 'mezzala_di_fascia', 'Mezzala di fascia'),
    ('LM', 'ala_rapida', 'Ala rapida'), ('LM', 'rifinitore_esterno', 'Rifinitore esterno'), ('LM', 'ala_realizzatrice', 'Ala realizzatrice'), ('LM', 'terzino_offensivo', 'Terzino offensivo'),
    ('RM', 'ala_di_fascia', 'Ala di fascia'), ('RM', 'mezzala_di_fascia', 'Mezzala di fascia'),
    ('RM', 'ala_rapida', 'Ala rapida'), ('RM', 'rifinitore_esterno', 'Rifinitore esterno'), ('RM', 'ala_realizzatrice', 'Ala realizzatrice'), ('RM', 'terzino_offensivo', 'Terzino offensivo'),

    -- Ali
    ('LW', 'ala_rapida', 'Ala rapida'), ('LW', 'rifinitore_esterno', 'Rifinitore esterno'), ('LW', 'ala_realizzatrice', 'Ala realizzatrice'),
    ('LW', 'ala_di_fascia', 'Ala di fascia'), ('LW', 'rapace_area', 'Rapace d''area'), ('LW', 'falso_nueve', 'Falso nueve'),
    ('RW', 'ala_rapida', 'Ala rapida'), ('RW', 'rifinitore_esterno', 'Rifinitore esterno'), ('RW', 'ala_realizzatrice', 'Ala realizzatrice'),
    ('RW', 'ala_di_fascia', 'Ala di fascia'), ('RW', 'rapace_area', 'Rapace d''area'), ('RW', 'falso_nueve', 'Falso nueve'),

    -- Attaccanti
    ('ST', 'rapace_area', 'Rapace d''area'), ('ST', 'bomber_fisico', 'Bomber fisico'), ('ST', 'falso_nueve', 'Falso nueve'),
    ('ST', 'ala_realizzatrice', 'Ala realizzatrice'), ('ST', 'mezzala_inserimento', 'Mezz''ala d''inserimento'),
    ('CF', 'falso_nueve', 'Falso nueve'), ('CF', 'rapace_area', 'Rapace d''area'),
    ('CF', 'bomber_fisico', 'Bomber fisico'), ('CF', 'rifinitore', 'Rifinitore'), ('CF', 'ala_realizzatrice', 'Ala realizzatrice'),

    -- Portiere: "Para rigori" conserva il suo bonus dal dischetto
    -- (engine/rigori.js, invariato). Nessun ruolo vicino.
    ('GK', 'fuori_dai_pali', 'Fuori dai pali'), ('GK', 'para_rigori', 'Para rigori')
  ) as x(ruolo, chiave, etichetta)
$$;

create or replace function private.specializzazioni_ruolo(p_posizione text)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select coalesce(jsonb_object_agg(x.chiave, jsonb_build_object('etichetta', x.etichetta, 'pesi', private.piano_pesi(x.chiave))), '{}'::jsonb)
  from private.piani_ruoli() x
  where x.ruolo = p_posizione or (x.ruolo = '*' and p_posizione is not null)
$$;

create or replace function public.specializzazioni_disponibili(p_instance_id bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_posizioni text[];
  v_attiva text;
  v_catalogo jsonb;
  v_reparto text;
  v_chiave text;
  v_etichetta text;
  v_pesi jsonb;
  v_media numeric;
  v_crescita jsonb;
  v_risultato jsonb := '{}'::jsonb;
begin
  select coalesce(pi.posizioni_override, p.posizioni), pi.specializzazione_attiva into v_posizioni, v_attiva
  from public.player_instances pi
  join public.players p on p.id = pi.player_id
  where pi.id = p_instance_id;

  if v_posizioni is null then
    return '{}'::jsonb;
  end if;

  v_catalogo := private.specializzazioni_ruolo(v_posizioni[1]);
  v_reparto := private.macro_ruolo(v_posizioni);

  -- Il piano attivo si vede sempre, anche se il ruolo attuale non lo offre piu'.
  if v_attiva is not null and not (v_catalogo ? v_attiva) then
    select x.etichetta into v_etichetta from private.piani_ruoli() x where x.chiave = v_attiva limit 1;
    v_catalogo := v_catalogo || jsonb_build_object(v_attiva, jsonb_build_object(
      'etichetta', coalesce(v_etichetta, v_attiva), 'pesi', private.piano_pesi(v_attiva)));
  end if;

  for v_chiave in select jsonb_object_keys(v_catalogo) loop
    v_pesi := v_catalogo -> v_chiave -> 'pesi';
    v_media := private.piano_media(v_chiave, v_reparto);
    select jsonb_object_agg(a.attributo,
      round(50 * (coalesce((v_pesi->>a.attributo)::numeric, 4) / v_media - 1))::int) into v_crescita
    from private.attributi_piano(v_reparto) a;
    v_risultato := v_risultato || jsonb_build_object(v_chiave, jsonb_build_object(
      'etichetta', v_catalogo -> v_chiave ->> 'etichetta',
      'crescita_pct', v_crescita,
      'attivo', v_chiave = coalesce(v_attiva, 'bilanciato')
    ));
  end loop;

  return v_risultato;
end;
$$;
