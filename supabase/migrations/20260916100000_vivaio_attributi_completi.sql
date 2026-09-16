-- ============================================================
--  I GIOCATORI DEL VIVAIO NASCONO CON TUTTI GLI ATTRIBUTI
--
--  Segnalato il 16 settembre 2026 aprendo la scheda di un portiere promosso
--  dal vivaio: mostrava cinque statistiche invece di un profilo.
--
--  private.genera_prospetto_vivaio scriveva esattamente sei attributi —
--  stamina, finishing, short_passing, standing_tackle, dribbling, gk — cioe'
--  precisamente quelli che consuma il motore di simulazione. All'epoca era una
--  scelta sensata: generare solo il necessario. Nel frattempo pero' sono
--  arrivati tre sistemi che leggono gli altri, e per tutti e tre un giocatore
--  del vivaio e' un buco:
--
--    - la SCHEDA mostra cinque voci invece del profilo completo;
--    - le SPECIALIZZAZIONI calcolano il nuovo valore come
--      coalesce(base, 0) + delta: su un attributo che non esiste partono da
--      zero, e un portiere finirebbe con gk_diving a 4 invece che a ~58.
--      Otto allenamenti erano gia' avviati su giocatori del vivaio, il primo
--      in scadenza fra quattro giornate: nessuno era ancora arrivato a
--      completamento, quindi nessun danno fatto;
--    - il SISTEMA TATTICO in lavorazione calcola i profili dagli attributi, e
--      senza quelli restituisce null: il vivaio sarebbe stato immune
--      all'effetto "interprete" (punto aperto C di docs/decisioni-tattiche.md).
--
--  GLI SCARTI SONO MISURATI, NON INVENTATI
--  Per ciascun attributo e ciascun reparto, lo scostamento medio dall'overall
--  e' stato calcolato sui giocatori VERI del catalogo nella fascia 45-75, che
--  contiene per intero quella del vivaio (40-60). Un difensore ha
--  defending_marking_awareness circa uguale al suo overall (-3), un attaccante
--  ce l'ha quaranta punti sotto (-40): sono i numeri del catalogo, non una mia
--  stima.
--
--  LA FORMA PER REPARTO E' RIPRODOTTA ESATTAMENTE. Verificato sui 5.992
--  giocatori del catalogo, senza una sola eccezione: i portieri hanno
--  goalkeeping_speed e NON hanno i sei compositi (pace, physic, passing,
--  shooting, defending, dribbling_generale); i giocatori di movimento il
--  contrario. Le celle a null qui sotto sono quelle assenze.
--
--  ATTRIBUTI COERENTI CON L'OVERALL DI ADESSO, deciso con l'utente: un
--  quindicenne da 46 avra' numeri bassi ovunque, e sara' il training a
--  decidere dove portarlo. Non si semina nessun indizio sul potenziale, che
--  resta quello che VIVAIO svela col tempo.
-- ============================================================

create or replace function private.attributi_vivaio(p_rep text, p_overall smallint)
returns jsonb
language sql
volatile
security definer
set search_path = ''
as $$
  select coalesce(jsonb_object_agg(
           t.attributo,
           -- overall + scarto del reparto + rumore, come gia' faceva il
           -- generatore per i sei attributi originali. Il pavimento a 4 non e'
           -- arbitrario: su un quindicenne da 46 uno scarto di -54 darebbe un
           -- numero negativo, e nel catalogo vero quegli attributi sono
           -- semplicemente appoggiati al minimo.
           greatest(4, least(95, p_overall + t.scarto + round((random() - 0.5) * 14)))::int
         ), '{}'::jsonb)
  from (
    values
      ('attacking_crossing', -52, -15, -8, -16),
      ('attacking_heading_accuracy', -52, -6, -15, -5),
      ('attacking_volleys', -55, -32, -16, -7),
      ('defending', null, -2, -16, -36),
      ('defending_marking_awareness', -54, -3, -17, -40),
      ('defending_sliding_tackle', -52, -2, -17, -41),
      ('dribbling', -52, -10, 1, -1),
      ('dribbling_generale', null, -8, 1, -1),
      ('finishing', -55, -30, -9, 0),
      ('gk', -1, -58, -58, -58),
      ('gk_diving', 1, -57, -58, -58),
      ('gk_handling', -2, -58, -58, -57),
      ('gk_kicking', -2, -58, -58, -57),
      ('gk_positioning', -1, -58, -58, -57),
      ('gk_reflexes', 1, -58, -58, -58),
      ('goalkeeping_speed', -30, null, null, null),
      ('mentality_aggression', -41, -1, -9, -13),
      ('mentality_composure', -26, -8, -4, -5),
      ('mentality_interceptions', -52, -2, -16, -40),
      ('mentality_penalties', -48, -25, -13, -5),
      ('mentality_positioning', -57, -21, -6, 0),
      ('mentality_vision', -26, -18, -3, -9),
      ('movement_acceleration', -31, -1, 3, 4),
      ('movement_agility', -28, -6, 4, 1),
      ('movement_balance', -27, -5, 4, -1),
      ('movement_reactions', -6, -4, -3, -3),
      ('movement_sprint_speed', -30, 0, 1, 5),
      ('pace', null, 0, 2, 5),
      ('passing', null, -12, -4, -11),
      ('physic', null, 1, -6, -3),
      ('power_jumping', -10, 4, -4, 5),
      ('power_long_shots', -55, -28, -8, -6),
      ('power_shot_power', -18, -16, -3, 1),
      ('power_strength', -6, 2, -7, 0),
      ('shooting', null, -26, -8, -1),
      ('short_passing', -36, -5, 0, -6),
      ('skill_ball_control', -46, -6, 1, 0),
      ('skill_curve', -51, -20, -8, -12),
      ('skill_fk_accuracy', -52, -29, -15, -19),
      ('skill_long_passing', -36, -11, -4, -17),
      ('stamina', -37, 0, 0, -4),
      ('standing_tackle', -52, 0, -14, -38)  ) as v(attributo, gk, def, mid, att)
  cross join lateral (
    select v.attributo,
           case p_rep when 'GK' then v.gk when 'DEF' then v.def
                      when 'MID' then v.mid else v.att end as scarto
  ) as t(attributo, scarto)
  where t.scarto is not null
$$;

revoke all on function private.attributi_vivaio(text, smallint) from public, anon, authenticated;

-- ------------------------------------------------------------
--  Il generatore usa il profilo completo
--  Definizione ripresa dal database e modificata nel solo punto necessario.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.genera_prospetto_vivaio(p_macro_ruolo text, p_league_id bigint)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_posizione text;
  v_overall smallint;
  v_potential smallint;
  v_nomi constant text[] := array['Liam','Noah','Mateo','Diego','Kai','Yusuf','Amir','Leon','Enzo','Theo',
    'Rayan','Elias','Adam','Milo','Nils','Ivo','Bruno','Mihail','Kofi','Chidi','Sami','Idris','Aron','Bram',
    'Jonas','Mats','Pablo','Rui','Tiago','Kwame',
    'Lucas','Mathis','Hugo','Nico','Sven','Erik','Anders','Magnus','Rasmus','Oskar',
    'Felix','Julian','Lars','Timo','Marek','Tomas','Igor','Pavel','Dario','Marco',
    'Luca','Matteo','Alessio','Gabriel','Rafael','Joao','Andre','Nuno','Vasco','Karim',
    'Hassan','Tariq','Malik','Kwabena','Emeka','Sekou','Moussa','Ibrahim','Kenji','Ren'];
  v_cognomi constant text[] := array['Berg','Novak','Costa','Rossi','Diaby','Traore','Kovac','Larsen','Mendes',
    'Haddad','Silva','Krause','Petrov','Okafor','Sorensen','Almeida','Bakker','Lindqvist','Duarte','Ferreira',
    'Vukovic','Adeyemi','Marchetti','Hansen','Ribeiro','Sorland','Nakamura','Osei','Correia','Weiss',
    'Andersen','Nilsson','Eriksson','Johansson','Muller','Fischer','Schmidt','Wagner','Dubois','Lefevre',
    'Moreau','Girard','Fontana','Bianchi','Conti','Greco','Ferrari','Colombo','Barros','Pinto',
    'Neves','Cardoso','Fonseca','Amaral','Farouk','Mansour','Toure','Camara','Kone','Sylla',
    'Diallo','Coulibaly','Ouedraogo','Suzuki','Tanaka','Sato','Yamamoto','Watanabe','Kallio','Petit'];
  v_nazionalita text;
  v_nome text;
  v_rep text;
  v_stamina smallint;
  v_finishing smallint;
  v_passing smallint;
  v_tackle smallint;
  v_dribbling smallint;
  v_gk smallint;
  v_foto text;
  v_id bigint;
begin
  v_posizione := case p_macro_ruolo
    when 'GK' then 'GK'
    when 'DEF' then (array['CB','LB','RB'])[1 + floor(random() * 3)::int]
    when 'MID' then (array['CDM','CM','CAM'])[1 + floor(random() * 3)::int]
    else (array['LW','RW','ST'])[1 + floor(random() * 3)::int]
  end;
  v_rep := case when v_posizione = 'GK' then 'GK'
    when v_posizione in ('CB','LB','RB') then 'DEF'
    when v_posizione in ('CDM','CM','CAM') then 'MID'
    else 'ATT' end;

  v_overall := greatest(40, least(60, round(46 + (random() - 0.5) * 18)))::smallint;
  v_potential := case
    when random() < 0.55 then round(v_overall + 8 + random() * 14)
    when random() < 0.88 then round(74 + random() * 10)
    else round(85 + random() * 9)
  end;
  v_potential := greatest(v_overall + 5, least(94, v_potential))::smallint;

  select nazionalita into v_nazionalita
  from public.players where nazionalita is not null order by random() limit 1;

  v_nome := v_nomi[1 + floor(random() * array_length(v_nomi, 1))::int]
    || ' ' || v_cognomi[1 + floor(random() * array_length(v_cognomi, 1))::int];

  v_stamina := greatest(35, least(85, round(60 + (random() - 0.5) * 24)))::smallint;
  v_finishing := greatest(15, least(80, round(v_overall + (case v_rep when 'ATT' then 4 when 'MID' then -6 else -20 end) + (random() - 0.5) * 14)))::smallint;
  v_passing := greatest(15, least(80, round(v_overall + (case v_rep when 'MID' then 4 when 'GK' then -22 else -3 end) + (random() - 0.5) * 14)))::smallint;
  v_tackle := greatest(15, least(80, round(v_overall + (case v_rep when 'DEF' then 5 when 'MID' then -3 else -22 end) + (random() - 0.5) * 14)))::smallint;
  v_dribbling := greatest(15, least(80, round(v_overall + (case v_rep when 'ATT' then 4 when 'MID' then 1 else -16 end) + (random() - 0.5) * 14)))::smallint;
  v_gk := case when v_rep = 'GK' then v_overall else 0 end;

  -- Foto in prestito: un U23 vero il cui campionato non e' fra quelli
  -- attivi di questa lega, quindi non puo' mai comparirci come carta
  -- vera. order by random() accetta un rarissimo doppione fra due
  -- prospetti generati: non e' un problema per una lega privata fra
  -- amici, lo sarebbe stato solo pescare dal pool dei campionati attivi.
  select foto_url into v_foto
  from public.players p
  join public.leagues l on l.id = p_league_id
  where p.eta <= 23 and p.foto_url is not null and not p.origine_vivaio
    and not (p.campionato = any(coalesce(l.campionati_attivi, array[]::text[])))
  order by random() limit 1;

  insert into public.players (
    fc_id, nome, nazionalita, club, campionato, foto_url, overall, potential, eta,
    posizioni, piede, altezza, attributi, is_icon, is_regen, origine_vivaio,
    disponibile_estrazione, elite_globale
  ) values (
    nextval('private.vivaio_fc_id_seq'), v_nome, v_nazionalita, 'Vivaio', 'Vivaio', v_foto,
    v_overall, v_potential, 15,
    array[v_posizione], case when random() < 0.78 then 'destro' else 'sinistro' end,
    round(168 + random() * 26)::smallint,
    -- Profilo completo dal catalogo vero (private.attributi_vivaio), POI i sei
    -- storici che lo sovrascrivono. L'ordine conta: quei sei sono gli unici che
    -- il motore legge, sono calcolati qui sotto con le formule di sempre, e
    -- lasciarli vincere garantisce che le partite si giochino esattamente come
    -- prima di questa migrazione. Gli altri trentacinque servono a scheda,
    -- specializzazioni e profili tattici.
    private.attributi_vivaio(v_rep, v_overall) || jsonb_build_object(
      'stamina', v_stamina, 'finishing', v_finishing, 'short_passing', v_passing,
      'standing_tackle', v_tackle, 'dribbling', v_dribbling, 'gk', v_gk
    ),
    false, false, true,
    false, false
  )
  returning id into v_id;

  return v_id;
end;
$function$
;

-- ------------------------------------------------------------
--  I 274 gia' in catalogo
--
--  Stessa regola del generatore: profilo completo, ma gli attributi che il
--  giocatore ha GIA' restano intatti. Non e' prudenza generica — dieci di loro
--  sono tesserati e scendono in campo, e quei sei valori sono gli unici che il
--  motore legge: riscriverli cambierebbe i risultati delle partite di squadre
--  che non hanno chiesto niente.
-- ------------------------------------------------------------
update public.players p
set attributi = private.attributi_vivaio(private.macro_ruolo(p.posizioni), p.overall) || p.attributi
where p.origine_vivaio
  and (select count(*) from jsonb_object_keys(p.attributi)) < 20;
