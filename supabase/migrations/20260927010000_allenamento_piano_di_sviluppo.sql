-- ============================================================
--  L'ALLENAMENTO DIVENTA UN PIANO DI SVILUPPO, COME IN EA FC
--
--  Segnalato dall'utente il 26 settembre 2026: allenando un giovane la
--  scheda prometteva "Dribbling 90 → 98", e alcuni ragazzi toccavano 99 in
--  meno di una stagione. Misurato sui 270 giocatori allenati:
--
--  - l'allenamento aggiungeva in media +1,8 sopra il valore che il
--    giocatore avrebbe avuto comunque (massimo +8): i 99 venivano da chi
--    partiva gia' da 92. Il salto enorme era soprattutto un effetto della
--    scheda, che mostrava catalogo + allenamento e nascondeva la crescita
--    quotidiana, cosi' tutta la crescita accumulata sembrava arrivare
--    dall'allenamento;
--  - il valore allenato era scritto come NUMERO FISSO in attributi_override,
--    e da quel momento quei tre attributi smettevano di crescere: 17
--    attributi erano gia' piu' bassi che senza allenamento;
--  - ogni specializzazione toccava sempre le stesse 3 abilita' con +8/+5/+3,
--    piu' un bonus all'overall.
--
--  IL MODELLO NUOVO (deciso con l'utente, riferimento EA FC 26: i "piani di
--  sviluppo" legati a un ruolo). L'allenamento non regala punti: sceglie
--  DOVE va la crescita che il giocatore fa comunque (eta', potenziale,
--  minuti: private.applica_progressione, invariata).
--
--  Oggi un attributo vale:
--      catalogo + pendenza(reparto, attributo) × (overall attuale − overall catalogo)
--  e resta cosi'. Il piano aggiunge uno scostamento proporzionale alla
--  crescita avvenuta DA QUANDO il piano e' attivo:
--      attributo del piano:   + FORZA × peso × pendenza × |Δ|
--      tutti gli altri:       − β × pendenza × |Δ|
--  dove Δ = overall attuale − overall all'attivazione del piano, e β e'
--  calcolato perche' la somma pesata sulle pendenze faccia ZERO: l'overall
--  non cambia, cambia solo la forma del giocatore. Con FORZA = 0,5 e pesi
--  1,0 / 0,6 / 0,4 le abilita' del piano crescono del 50% / 30% / 20% in
--  piu', le altre circa il 7% in meno.
--
--  Il valore assoluto |Δ| e' voluto: quando un veterano cala, le abilita'
--  del piano calano MENO e le altre di piu'. Il piano protegge quello che
--  hai scelto anche nel declino.
--
--  Cambiare piano non cancella nulla: lo scostamento maturato col piano
--  vecchio viene congelato in piano_scostamenti, e il nuovo riparte da zero.
--  Un 99 arriva solo se il giocatore cresce davvero: non c'e' piu' un bonus
--  che si somma a un numero gia' alto.
-- ============================================================

alter table public.player_instances
  add column if not exists piano_scostamenti jsonb not null default '{}'::jsonb,
  add column if not exists piano_overall_rif smallint;

comment on column public.player_instances.piano_scostamenti is
  'Scostamenti (anche negativi, non arrotondati) maturati con i piani di sviluppo precedenti. Si sommano agli attributi cresciuti. Vedi private.attributi_istanza.';
comment on column public.player_instances.piano_overall_rif is
  'Overall del giocatore quando il piano attuale (specializzazione_attiva) e'' entrato in vigore. Null = nessun piano.';


-- I piani, uno per chiave. Le chiavi erano gia' uniche nel significato
-- (ala_di_fascia e' la stessa per LM e RM, falso_nueve per ST e CF...),
-- quindi il peso dipende dal solo piano: un cambio di ruolo non lo rompe.
-- Sei abilita' per piano invece di tre, con pesi 1,0 / 0,6 / 0,4 che
-- sommano sempre a 4: nessun piano e' piu' "grosso" di un altro. La prima
-- abilita' e' la stessa che prima prendeva il +8.
create or replace function private.piano_pesi(p_piano text)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select case p_piano
    when 'marcatore' then '{"standing_tackle":1.0,"defending_marking_awareness":1.0,"power_strength":0.6,"stamina":0.6,"defending_sliding_tackle":0.4,"mentality_aggression":0.4}'
    when 'libero' then '{"short_passing":1.0,"skill_long_passing":1.0,"mentality_vision":0.6,"standing_tackle":0.6,"mentality_interceptions":0.4,"skill_ball_control":0.4}'
    when 'terzino_difensivo' then '{"standing_tackle":1.0,"defending_marking_awareness":1.0,"stamina":0.6,"defending_sliding_tackle":0.6,"mentality_interceptions":0.4,"movement_sprint_speed":0.4}'
    when 'terzino_offensivo' then '{"dribbling":1.0,"attacking_crossing":1.0,"stamina":0.6,"movement_sprint_speed":0.6,"short_passing":0.4,"movement_acceleration":0.4}'
    when 'regista_basso' then '{"short_passing":1.0,"skill_long_passing":1.0,"mentality_vision":0.6,"standing_tackle":0.6,"skill_ball_control":0.4,"dribbling":0.4}'
    when 'schermo_difensivo' then '{"standing_tackle":1.0,"mentality_interceptions":1.0,"stamina":0.6,"defending_marking_awareness":0.6,"power_strength":0.4,"short_passing":0.4}'
    when 'regista_arretrato' then '{"short_passing":1.0,"skill_long_passing":1.0,"mentality_vision":0.6,"standing_tackle":0.6,"stamina":0.4,"mentality_composure":0.4}'
    when 'regista' then '{"short_passing":1.0,"mentality_vision":1.0,"skill_long_passing":0.6,"dribbling":0.6,"skill_ball_control":0.4,"stamina":0.4}'
    when 'box_to_box' then '{"stamina":1.0,"standing_tackle":1.0,"short_passing":0.6,"power_strength":0.6,"mentality_interceptions":0.4,"power_long_shots":0.4}'
    when 'recupera_palloni' then '{"standing_tackle":1.0,"mentality_interceptions":1.0,"stamina":0.6,"mentality_aggression":0.6,"defending_marking_awareness":0.4,"power_strength":0.4}'
    when 'mezzala_inserimento' then '{"finishing":1.0,"mentality_positioning":1.0,"dribbling":0.6,"power_long_shots":0.6,"stamina":0.4,"skill_ball_control":0.4}'
    when 'rifinitore' then '{"short_passing":1.0,"mentality_vision":1.0,"dribbling":0.6,"skill_ball_control":0.6,"skill_curve":0.4,"finishing":0.4}'
    when 'ala_di_fascia' then '{"dribbling":1.0,"attacking_crossing":1.0,"stamina":0.6,"movement_sprint_speed":0.6,"short_passing":0.4,"movement_acceleration":0.4}'
    when 'mezzala_di_fascia' then '{"standing_tackle":1.0,"stamina":1.0,"mentality_interceptions":0.6,"dribbling":0.6,"short_passing":0.4,"defending_marking_awareness":0.4}'
    when 'ala_rapida' then '{"dribbling":1.0,"movement_sprint_speed":1.0,"movement_acceleration":0.6,"movement_agility":0.6,"stamina":0.4,"finishing":0.4}'
    when 'rifinitore_esterno' then '{"short_passing":1.0,"attacking_crossing":1.0,"mentality_vision":0.6,"dribbling":0.6,"skill_curve":0.4,"finishing":0.4}'
    when 'ala_realizzatrice' then '{"finishing":1.0,"mentality_positioning":1.0,"dribbling":0.6,"power_shot_power":0.6,"skill_curve":0.4,"short_passing":0.4}'
    when 'rapace_area' then '{"finishing":1.0,"mentality_positioning":1.0,"movement_reactions":0.6,"dribbling":0.6,"attacking_volleys":0.4,"mentality_composure":0.4}'
    when 'bomber_fisico' then '{"power_strength":1.0,"attacking_heading_accuracy":1.0,"stamina":0.6,"finishing":0.6,"power_jumping":0.4,"power_shot_power":0.4}'
    when 'falso_nueve' then '{"short_passing":1.0,"mentality_vision":1.0,"dribbling":0.6,"skill_ball_control":0.6,"finishing":0.4,"movement_agility":0.4}'
    when 'fuori_dai_pali' then '{"goalkeeping_speed":1.0,"gk_positioning":1.0,"gk_reflexes":0.6,"gk_kicking":0.6,"movement_reactions":0.4,"gk_handling":0.4}'
    when 'para_rigori' then '{"gk_diving":1.0,"gk_reflexes":1.0,"gk_handling":0.6,"movement_reactions":0.6,"mentality_composure":0.4,"gk_positioning":0.4}'
  end::jsonb
$$;


-- Quali piani vede ogni ruolo: stesse strade di prima, stesse etichette.
-- La chiave 'deltas' non c'e' piu': c'e' 'pesi', letta da piano_pesi.
create or replace function private.specializzazioni_ruolo(p_posizione text)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select coalesce(jsonb_object_agg(x.chiave, jsonb_build_object('etichetta', x.etichetta, 'pesi', private.piano_pesi(x.chiave))), '{}'::jsonb)
  from (values
    ('CB', 'marcatore', 'Marcatore'), ('CB', 'libero', 'Libero'),
    ('LB', 'terzino_difensivo', 'Terzino difensivo'), ('LB', 'terzino_offensivo', 'Terzino offensivo'), ('LB', 'regista_basso', 'Regista basso'),
    ('RB', 'terzino_difensivo', 'Terzino difensivo'), ('RB', 'terzino_offensivo', 'Terzino offensivo'), ('RB', 'regista_basso', 'Regista basso'),
    ('CDM', 'schermo_difensivo', 'Schermo difensivo'), ('CDM', 'regista_arretrato', 'Regista arretrato'),
    ('CM', 'regista', 'Regista'), ('CM', 'box_to_box', 'Box-to-box'), ('CM', 'recupera_palloni', 'Recupera palloni'), ('CM', 'mezzala_inserimento', 'Mezz''ala d''inserimento'),
    ('CAM', 'rifinitore', 'Rifinitore'), ('CAM', 'mezzala_inserimento', 'Mezz''ala d''inserimento'),
    ('LM', 'ala_di_fascia', 'Ala di fascia'), ('LM', 'mezzala_di_fascia', 'Mezzala di fascia'),
    ('RM', 'ala_di_fascia', 'Ala di fascia'), ('RM', 'mezzala_di_fascia', 'Mezzala di fascia'),
    ('LW', 'ala_rapida', 'Ala rapida'), ('LW', 'rifinitore_esterno', 'Rifinitore esterno'), ('LW', 'ala_realizzatrice', 'Ala realizzatrice'),
    ('RW', 'ala_rapida', 'Ala rapida'), ('RW', 'rifinitore_esterno', 'Rifinitore esterno'), ('RW', 'ala_realizzatrice', 'Ala realizzatrice'),
    ('ST', 'rapace_area', 'Rapace d''area'), ('ST', 'bomber_fisico', 'Bomber fisico'), ('ST', 'falso_nueve', 'Falso nueve'),
    ('CF', 'falso_nueve', 'Falso nueve'), ('CF', 'rapace_area', 'Rapace d''area'),
    -- Portiere: il motore usa di lui solo l'overall, che il piano non
    -- tocca. "Para rigori" conserva il suo bonus dal dischetto
    -- (engine/rigori.js, invariato).
    ('GK', 'fuori_dai_pali', 'Fuori dai pali'), ('GK', 'para_rigori', 'Para rigori')
  ) as x(ruolo, chiave, etichetta)
  where x.ruolo = p_posizione
$$;


-- La forza del piano e la quota tolta alle altre abilita' per un reparto.
-- "Altre" = gli attributi di dettaglio (non i sei voti macro della card),
-- e per chi non e' portiere senza quelli da portiere, che non contano.
create or replace function private.piano_beta(p_piano text, p_reparto text)
returns numeric
language sql
stable
set search_path = ''
as $$
  with pesi as (
    select k as attributo, (private.piano_pesi(p_piano)->>k)::numeric as peso
    from jsonb_object_keys(coalesce(private.piano_pesi(p_piano), '{}'::jsonb)) k
  ), pend as (
    select pe.attributo, greatest(pe.pendenza, 0) as pendenza
    from private.pendenze_attributi pe
    where pe.reparto = p_reparto
      and pe.attributo not in ('pace', 'shooting', 'passing', 'dribbling_generale', 'defending', 'physic', 'gk')
      and (p_reparto = 'GK' or (pe.attributo not like 'gk\_%' and pe.attributo <> 'goalkeeping_speed'))
  )
  select case when coalesce(sum(pend.pendenza) filter (where pesi.attributo is null), 0) = 0 then 0
    else 0.5 * coalesce(sum(pesi.peso * pend.pendenza) filter (where pesi.attributo is not null), 0)
             / sum(pend.pendenza) filter (where pesi.attributo is null)
  end
  from pend left join pesi on pesi.attributo = pend.attributo
$$;


-- Lo scostamento di un piano per |Δ| punti di overall. Valori non
-- arrotondati: l'arrotondamento si fa una volta sola, sul totale.
-- I sei voti macro (quelli del radar) seguono la media dei loro attributi
-- di dettaglio, cosi' la card resta coerente con l'elenco.
create or replace function private.scostamenti_piano(p_piano text, p_reparto text, p_delta numeric)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
declare
  v_pesi jsonb := private.piano_pesi(p_piano);
  v_beta numeric;
  v_dettaglio jsonb;
  v_macro jsonb;
begin
  if v_pesi is null or coalesce(p_delta, 0) = 0 then
    return '{}'::jsonb;
  end if;
  v_beta := private.piano_beta(p_piano, p_reparto);

  select coalesce(jsonb_object_agg(pe.attributo,
    case when v_pesi ? pe.attributo
      then 0.5 * (v_pesi->>pe.attributo)::numeric * greatest(pe.pendenza, 0) * abs(p_delta)
      else -v_beta * greatest(pe.pendenza, 0) * abs(p_delta)
    end), '{}'::jsonb)
  into v_dettaglio
  from private.pendenze_attributi pe
  where pe.reparto = p_reparto
    and pe.attributo not in ('pace', 'shooting', 'passing', 'dribbling_generale', 'defending', 'physic', 'gk')
    and (p_reparto = 'GK' or v_pesi ? pe.attributo or (pe.attributo not like 'gk\_%' and pe.attributo <> 'goalkeeping_speed'));

  select coalesce(jsonb_object_agg(g.macro,
    (select avg(coalesce((v_dettaglio->>a)::numeric, 0)) from unnest(g.attributi) a)), '{}'::jsonb)
  into v_macro
  from (values
    ('pace', array['movement_acceleration', 'movement_sprint_speed']),
    ('shooting', array['finishing', 'power_shot_power', 'power_long_shots', 'attacking_volleys', 'mentality_penalties', 'mentality_positioning']),
    ('passing', array['short_passing', 'skill_long_passing', 'attacking_crossing', 'skill_curve', 'skill_fk_accuracy', 'mentality_vision']),
    ('dribbling_generale', array['dribbling', 'skill_ball_control', 'movement_agility', 'movement_balance', 'movement_reactions', 'mentality_composure']),
    ('defending', array['standing_tackle', 'defending_sliding_tackle', 'defending_marking_awareness', 'mentality_interceptions', 'attacking_heading_accuracy']),
    ('physic', array['stamina', 'power_strength', 'power_jumping', 'mentality_aggression']),
    ('gk', array['gk_diving', 'gk_handling', 'gk_kicking', 'gk_positioning', 'gk_reflexes', 'goalkeeping_speed'])
  ) as g(macro, attributi);

  return v_dettaglio || v_macro;
end;
$$;


-- Gli attributi VERI di un giocatore: catalogo + crescita + piani passati
-- + piano attuale. E' l'unica formula: la usano il motore (via
-- public.attributi_correnti), le schede e l'allenamento.
create or replace function private.attributi_istanza(
  p_attributi jsonb, p_posizioni text[], p_overall_corrente integer, p_overall_catalogo integer,
  p_scostamenti jsonb, p_piano text, p_overall_rif integer)
returns jsonb
language sql
stable
set search_path = ''
as $$
  with base as (
    select private.macro_ruolo(p_posizioni) as reparto
  ), piano as (
    select private.scostamenti_piano(
      p_piano, base.reparto,
      case when p_overall_rif is null then 0 else p_overall_corrente - p_overall_rif end) as s
    from base
  )
  select coalesce(jsonb_object_agg(k,
    greatest(1, least(99, round(
      (p_attributi->>k)::numeric
      + coalesce(pe.pendenza, 0) * coalesce(p_overall_corrente - p_overall_catalogo, 0)
      + coalesce((p_scostamenti->>k)::numeric, 0)
      + coalesce((piano.s->>k)::numeric, 0)
    )))::int), '{}'::jsonb)
  from base cross join piano
  cross join lateral jsonb_object_keys(coalesce(p_attributi, '{}'::jsonb)) as k
  left join private.pendenze_attributi pe on pe.reparto = base.reparto and pe.attributo = k
  where (p_attributi->>k) ~ '^[0-9]+$'
$$;


-- Varco pubblico per schede e motore. Gli attributi non sono segreti (la
-- scheda di un avversario li mostra gia'), e la funzione restituisce solo
-- quelli: niente formazioni, niente ingaggi.
create or replace function public.attributi_correnti(p_instance_ids bigint[])
returns table (instance_id bigint, attributi jsonb)
language sql
stable
security definer
set search_path = ''
as $$
  select pi.id, private.attributi_istanza(
    p.attributi, coalesce(pi.posizioni_override, p.posizioni), pi.overall_corrente, p.overall,
    pi.piano_scostamenti, pi.specializzazione_attiva, pi.piano_overall_rif)
  from public.player_instances pi
  join public.players p on p.id = pi.player_id
  where pi.id = any(p_instance_ids)
$$;

revoke all on function public.attributi_correnti(bigint[]) from public, anon;
grant execute on function public.attributi_correnti(bigint[]) to authenticated, service_role;


-- L'anteprima dell'allenamento: non piu' "90 → 98", ma quanto cresce in
-- piu' (o in meno) ogni abilita' da qui in avanti.
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
  v_pesi jsonb;
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

  for v_chiave in select jsonb_object_keys(v_catalogo) loop
    v_pesi := v_catalogo -> v_chiave -> 'pesi';
    select jsonb_object_agg(k, round(50 * (v_pesi->>k)::numeric)::int) into v_crescita
    from jsonb_object_keys(v_pesi) k;
    v_risultato := v_risultato || jsonb_build_object(v_chiave, jsonb_build_object(
      'etichetta', v_catalogo -> v_chiave ->> 'etichetta',
      'crescita_pct', v_crescita,
      'altre_pct', -round(100 * private.piano_beta(v_chiave, v_reparto))::int,
      'attivo', v_chiave is not distinct from v_attiva
    ));
  end loop;

  return v_risultato;
end;
$$;


-- Avvio: identica alla versione viva (ricostruita dal database), piu' un
-- controllo. Riavviare il piano che il giocatore segue gia' non cambierebbe
-- nulla: congelerebbe e ripartirebbe dallo stesso punto, sprecando dieci
-- giornate di training.
create or replace function public.avvia_specializzazione(p_instance_id bigint, p_specializzazione text)
returns public.specializzazioni_giocatore
language plpgsql
security definer
set search_path = ''
as $$
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

  if v_istanza.specializzazione_attiva is not distinct from p_specializzazione then
    raise exception using errcode = '55000', message = 'Questo giocatore segue già questo piano di sviluppo.';
  end if;

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
$$;


-- Fine allenamento: il piano nuovo entra in vigore. Niente override, niente
-- bonus overall. Lo scostamento maturato col piano vecchio si congela.
create or replace function private.completa_specializzazioni()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_lega record;
  v_prossima integer;
  v_riga record;
  v_posizioni text[];
  v_maturato jsonb;
  v_congelati jsonb;
  v_chiave text;
  v_etichetta text;
  v_completati integer := 0;
begin
  for v_lega in select id, giornate_totali from public.leagues where stato = 'stagione' loop
    select coalesce(min(f.giornata), v_lega.giornate_totali + 1) into v_prossima
    from public.fixtures f where f.league_id = v_lega.id and f.stato = 'programmata';

    for v_riga in
      select s.*, pi.posizioni_override, pi.overall_corrente, pi.specializzazione_attiva,
        pi.piano_scostamenti, pi.piano_overall_rif,
        p.posizioni as posizioni_catalogo, p.nome as nome_giocatore
      from public.specializzazioni_giocatore s
      join public.player_instances pi on pi.id = s.player_instance_id
      join public.players p on p.id = pi.player_id
      where s.league_id = v_lega.id and s.completato_il is null and s.completa_giornata <= v_prossima
      order by s.id
      for update of s
    loop
      v_posizioni := coalesce(v_riga.posizioni_override, v_riga.posizioni_catalogo);
      v_etichetta := coalesce(
        private.specializzazioni_ruolo(v_posizioni[1]) -> v_riga.specializzazione_target ->> 'etichetta',
        v_riga.specializzazione_target);

      -- Quello che il piano uscente ha gia' spostato resta al giocatore.
      v_maturato := private.scostamenti_piano(
        v_riga.specializzazione_attiva, private.macro_ruolo(v_posizioni),
        case when v_riga.piano_overall_rif is null then 0 else v_riga.overall_corrente - v_riga.piano_overall_rif end);
      v_congelati := coalesce(v_riga.piano_scostamenti, '{}'::jsonb);
      for v_chiave in select jsonb_object_keys(v_maturato) loop
        v_congelati := v_congelati || jsonb_build_object(v_chiave,
          round(coalesce((v_congelati->>v_chiave)::numeric, 0) + (v_maturato->>v_chiave)::numeric, 3));
      end loop;

      update public.player_instances
      set piano_scostamenti = v_congelati,
          specializzazione_attiva = v_riga.specializzazione_target,
          piano_overall_rif = overall_corrente
      where id = v_riga.player_instance_id;

      update public.specializzazioni_giocatore set completato_il = now() where id = v_riga.id;

      perform private.notifica(
        t.user_id, v_lega.id, 'sistema', 'Allenamento completato',
        coalesce(v_riga.nome_giocatore, 'Un giocatore') || ' segue ora il piano ' || v_etichetta
          || ': da qui in avanti la sua crescita si concentra sulle abilità di quel ruolo.',
        jsonb_build_object('view', 'team', 'player_instance_id', v_riga.player_instance_id)
      )
      from public.teams t where t.id = v_riga.team_id;

      v_completati := v_completati + 1;
    end loop;
  end loop;
  return v_completati;
end;
$$;


-- ------------------------------------------------------------
-- Passaggio dei giocatori gia' allenati al modello nuovo.
--
-- Chi aveva un override tiene il vantaggio che l'allenamento gli dava
-- SOPRA gli attributi cresciuti di oggi (scostamento positivo), e nient'altro:
-- chi era finito sotto (override congelato mentre cresceva) torna al valore
-- giusto, perche' lo scostamento negativo non si porta. I bonus overall gia'
-- dati restano. Il piano in corso (specializzazione_attiva) riparte da oggi.
-- ------------------------------------------------------------
with vecchi as (
  select pi.id,
    pi.attributi_override as ovr,
    private.attributi_istanza(p.attributi, coalesce(pi.posizioni_override, p.posizioni),
      pi.overall_corrente, p.overall, '{}'::jsonb, null, null) as base
  from public.player_instances pi
  join public.players p on p.id = pi.player_id
  where pi.attributi_override is not null and pi.attributi_override <> '{}'::jsonb
)
update public.player_instances pi
set piano_scostamenti = coalesce((
  select jsonb_object_agg(k, (v.ovr->>k)::int - (v.base->>k)::int)
  from jsonb_object_keys(v.ovr) k
  where (v.ovr->>k)::int > coalesce((v.base->>k)::int, 0)), '{}'::jsonb)
from vecchi v
where v.id = pi.id;

update public.player_instances
set piano_overall_rif = overall_corrente
where specializzazione_attiva is not null;

update public.player_instances
set attributi_override = null
where attributi_override is not null;

comment on column public.player_instances.attributi_override is
  'DISMESSA il 27 settembre 2026 (piano di sviluppo): sempre null. Vedi piano_scostamenti e private.attributi_istanza.';
