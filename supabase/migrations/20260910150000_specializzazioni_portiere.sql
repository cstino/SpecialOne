-- ============================================================
--  SPECIALIZZAZIONI PER I PORTIERI (non il cambio ruolo)
--
--  Richiesta dell'utente il 10 settembre 2026, con tre idee di partenza
--  ("impostare dal basso", "fuori dai pali", "para rigori") e mandato
--  esplicito di riformularle per renderle equilibrate.
--
--  PERCHE' DUE E NON TRE. Verificato riga per riga nel motore: forzeLinee()
--  tiene il portiere FUORI da DEF/MID/ATT (if slot = 'GK' -> continue) e il
--  suo overall entra in un solo punto, "xg *= (1 - (GK - 75) /
--  DIVISORE_PORTIERE)". L'attributo 'gk' non e' mai letto (zero occorrenze
--  in engine.js, config.js, rigori.js). Qualunque specializzazione che alzi
--  l'overall fa quindi esattamente la stessa identica cosa: subire meno
--  gol. Tre strade sarebbero state tre etichette sullo stesso effetto, cioe'
--  una scelta finta. "Impostare dal basso" e' stata scartata per questo:
--  renderla reale richiede dare al portiere un peso nel centrocampo dentro
--  forzeLinee, cioe' toccare il motore validato e rimisurare l'equilibrio di
--  tutte le partite. Discusso con l'utente, che ha scelto di non farlo ora.
--
--  LE DUE STRADE, e perche' la scelta e' vera
--    Fuori dai pali  +2 overall  -> para di piu' in TUTTE le partite
--    Para rigori     +1 overall  -> meno in campionato, ma un vantaggio
--                                   reale e sensibile ai rigori
--  Il compromesso e' autentico: la prima aiuta poco ma sempre, la seconda
--  quasi nulla per 30 giornate e poi puo' decidere un playoff. Chi punta al
--  titolo sceglie diversamente da chi deve salvarsi.
--
--  I NUMERI. Le altre specializzazioni valgono tutte +2 di overall (per
--  esempio CB marcatore: 8*0.30*0.45 + 5*0.30*0.20 + 3*0.35*0.13 = 1.52 ->
--  2). "Fuori dai pali" e' tarata sullo stesso valore, per non fare del
--  portiere un ruolo di serie B. "Para rigori" scende a +1 di proposito:
--  mentality_penalties e' una stat di tiro, non di parata, e nel calcolo
--  pesa quasi zero per un portiere (0.02) — non e' un trucco, e' esattamente
--  il punto: quella specializzazione paga altrove.
--
--  Gli attributi toccati esistono davvero nel catalogo FC 26 e sono gia'
--  visibili sulla scheda giocatore, nel gruppo "Portiere" (Tuffo, Presa,
--  Riflessi, Rapidita' in uscita...). Verificato su Alisson, Donnarumma e
--  Courtois prima di sceglierli.
--
--  Il vantaggio ai rigori vive in engine/rigori.js, che si dichiara in testa
--  FUORI dal nucleo validato in Fase 0 ("la suite di tools/validazione non lo
--  importa e nessuna formula di engine.js viene toccata"): intervenire li'
--  non rimette in discussione la taratura del motore.
--
--  Le tre funzioni sono state modificate per sostituzione mirata sul testo
--  live, verificata con diff: nessuna riga persa oltre a quelle sostituite.
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
      'para_rigori', jsonb_build_object('etichetta', 'Para rigori',
        'deltas', jsonb_build_object('mentality_penalties', 8, 'gk_diving', 5, 'gk_reflexes', 3))
    )
    else '{}'::jsonb
  end
$function$
;

CREATE OR REPLACE FUNCTION private.bonus_overall_specializzazione(p_macro_ruolo text, p_deltas jsonb)
 RETURNS integer
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO ''
AS $function$
declare
  v_pesi_ruolo jsonb := case p_macro_ruolo
    when 'DEF' then '{"shooting":0.02,"passing":0.13,"dribbling":0.10,"defending":0.45,"physic":0.20,"pace":0.10}'::jsonb
    when 'ATT' then '{"shooting":0.35,"passing":0.10,"dribbling":0.22,"defending":0.02,"physic":0.13,"pace":0.18}'::jsonb
    -- GK aggiunto il 10 settembre 2026. Prima cadeva nel ramo MID, con
    -- pesi che per un portiere non significano nulla. Il macro
    -- "goalkeeping" esiste solo qui: e' cio' che il portiere fa davvero.
    when 'GK'  then '{"goalkeeping":0.55,"shooting":0.02,"passing":0.05,"dribbling":0.03,"defending":0.05,"physic":0.10,"pace":0.05}'::jsonb
    else          '{"shooting":0.12,"passing":0.28,"dribbling":0.25,"defending":0.10,"physic":0.15,"pace":0.10}'::jsonb -- MID
  end;
  v_contributo constant jsonb := '{
    "finishing":       {"macro": "shooting",   "peso": 0.45},
    "short_passing":   {"macro": "passing",    "peso": 0.35},
    "standing_tackle": {"macro": "defending",  "peso": 0.30},
    "dribbling":       {"macro": "dribbling",  "peso": 0.40},
    "stamina":         {"macro": "physic",     "peso": 0.30},
    "gk_reflexes":       {"macro": "goalkeeping", "peso": 0.25},
    "gk_diving":         {"macro": "goalkeeping", "peso": 0.25},
    "gk_handling":       {"macro": "goalkeeping", "peso": 0.25},
    "gk_positioning":    {"macro": "goalkeeping", "peso": 0.25},
    "goalkeeping_speed": {"macro": "goalkeeping", "peso": 0.25},
    "mentality_penalties": {"macro": "shooting",  "peso": 0.45}
  }'::jsonb;
  v_chiave text;
  v_macro text;
  v_peso_contributo numeric;
  v_totale numeric := 0;
begin
  for v_chiave in select jsonb_object_keys(p_deltas) loop
    v_macro := v_contributo -> v_chiave ->> 'macro';
    v_peso_contributo := (v_contributo -> v_chiave ->> 'peso')::numeric;
    if v_macro is not null then
      v_totale := v_totale
        + (p_deltas ->> v_chiave)::numeric * v_peso_contributo * coalesce((v_pesi_ruolo ->> v_macro)::numeric, 0);
    end if;
  end loop;
  return round(v_totale)::int;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.avvia_specializzazione(p_instance_id bigint, p_specializzazione text)
 RETURNS specializzazioni_giocatore
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_utente uuid := (select auth.uid());
  v_istanza public.player_instances;
  v_squadra public.teams;
  v_lega public.leagues;
  v_posizioni_attuali text[];
  v_catalogo jsonb;
  v_livello smallint;
  v_riduzione numeric;
  v_durata integer;
  v_prossima integer;
  v_allenamento public.specializzazioni_giocatore;
begin
  if v_utente is null then
    raise exception using errcode = '42501', message = 'Devi accedere per gestire il training.';
  end if;

  select * into v_istanza from public.player_instances where id = p_instance_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Giocatore inesistente.';
  end if;

  select * into v_squadra from public.teams where id = v_istanza.team_id and user_id = v_utente;
  if not found then
    raise exception using errcode = '42501', message = 'Questo giocatore non appartiene alla tua squadra.';
  end if;

  select * into v_lega from public.leagues where id = v_istanza.league_id;
  if v_lega.stato <> 'stagione' then
    raise exception using errcode = '55000', message = 'Puoi avviare un allenamento solo durante la stagione.';
  end if;

  perform 1 from public.player_instances where id = p_instance_id for update;

  if exists (
    select 1 from public.specializzazioni_giocatore
    where player_instance_id = p_instance_id and completato_il is null
  ) then
    raise exception using errcode = '55000', message = 'Questo giocatore ha già un allenamento in corso.';
  end if;
  if exists (
    select 1 from public.cambi_ruolo
    where player_instance_id = p_instance_id and completato_il is null
  ) then
    raise exception using errcode = '55000',
      message = 'Questo giocatore sta gia'' cambiando ruolo: non puo'' anche allenare una specializzazione insieme.';
  end if;

  select coalesce(pi.posizioni_override, p.posizioni) into v_posizioni_attuali
  from public.player_instances pi
  join public.players p on p.id = pi.player_id
  where pi.id = p_instance_id;

  v_catalogo := private.specializzazioni_ruolo(v_posizioni_attuali[1]);
  -- Il blocco esplicito sui portieri e' caduto il 10 settembre 2026: ora
  -- hanno due specializzazioni (vedi private.specializzazioni_ruolo). Resta
  -- il solo controllo di validita' sul catalogo del ruolo.
  if not (v_catalogo ? p_specializzazione) then
    raise exception using errcode = '22023',
      message = 'Specializzazione non valida per questo ruolo.';
  end if;

  select livello_training into v_livello from public.team_risorse where team_id = v_squadra.id;
  v_riduzione := coalesce(
    (private.effetti_ramo('training', coalesce(v_livello, 0::smallint))->>'riduzione_tempi_ruolo_pct')::numeric, 0);

  v_durata := greatest(3, round(10 * (1 - v_riduzione / 100.0)));

  select coalesce(min(f.giornata), v_lega.giornate_totali + 1) into v_prossima
  from public.fixtures f where f.league_id = v_lega.id and f.stato = 'programmata';

  insert into public.specializzazioni_giocatore (
    league_id, team_id, player_instance_id, specializzazione_precedente, specializzazione_target,
    avviato_giornata, completa_giornata
  ) values (
    v_lega.id, v_squadra.id, p_instance_id, v_istanza.specializzazione_attiva, p_specializzazione,
    v_prossima, v_prossima + v_durata
  ) returning * into v_allenamento;

  return v_allenamento;
end;
$function$
;

commit;
