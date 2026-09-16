-- ============================================================
--  GLI ATTRIBUTI SEGUONO L'OVERALL
--
--  In SpecialOne overall e attributi erano scollegati: la progressione
--  scriveva solo overall_corrente e gli attributi restavano quelli
--  dell'importazione. Verificato leggendo private.progressione_giornaliera, che
--  fa "set overall_corrente = ..., progressione_residuo = ..." e non nomina mai
--  attributi.
--
--  Segnalato dall'utente il 16 settembre 2026, e ha ragione: in EA FC l'overall
--  e' CALCOLATO dagli attributi, in Football Manager la current ability e' un
--  budget distribuito su di essi. In nessuno dei due possono divergere. Qui
--  divergevano, e la distanza cresceva ogni stagione: misurata sui tesserati,
--  +1.2 di media sul catalogo e +3.5 sul vivaio, con 69 giocatori gia' oltre i
--  5 punti di scarto. Peggio proprio dove conta di piu': i giovani, che sono
--  quelli che crescono e quelli su cui si fanno i training.
--
--  Finche' gli attributi non li leggeva nessuno non importava. Da quando ci
--  sono specializzazioni, schede dettagliate e il sistema tattico in arrivo,
--  importa.
--
--  DERIVATI, NON CONSERVATI. Deciso con l'utente fra due strade: accumulare la
--  crescita in attributi_override con un trigger, oppure calcolarla al momento.
--  La prima ha un difetto concreto — completa_specializzazioni RISCRIVE quel
--  campo partendo dal catalogo, quindi la prima specializzazione avrebbe
--  cancellato tutta la crescita accumulata — e in generale crea uno stato
--  duplicato che puo' divergere da quello vero. Si calcola al momento:
--
--     attributo = catalogo + pendenza(reparto, attributo) x delta_overall
--                 + eventuale specializzazione
--
--  Cosi' il valore e' sempre coerente con l'overall di adesso, anche se domani
--  cambiano le regole di progressione, e non c'e' niente da tenere allineato.
--
--  LA CRESCITA NON PUO' TOCCARE public.players: 49 giocatori esistono in piu'
--  leghe contemporaneamente e hanno progressioni diverse in ciascuna. Il
--  catalogo resta il punto di partenza condiviso, il delta e' per-istanza.
--
--  LE PENDENZE SONO MISURATE. Per ogni reparto e ogni attributo e' la pendenza
--  della regressione fra attributo e overall sui giocatori veri del catalogo:
--  quanto quell'attributo cresce, in media, per ogni punto di overall in piu'.
--  Rifare la misura:
--
--    with pop as (select private.macro_ruolo(p.posizioni) as rep, p.overall,
--                        p.attributi as a
--                 from public.players p
--                 where not p.origine_vivaio and p.attributi ? 'movement_sprint_speed'),
--         lunga as (select rep, overall, k, (a->>k)::numeric as v
--                   from pop, lateral jsonb_object_keys(a) as k
--                   where (a->>k) ~ '^[0-9]+$')
--    select rep, k, regr_slope(v, overall) from lunga group by rep, k;
--
--  Quello che dicono e' sensato da solo: un portiere che cresce di 10 guadagna
--  9.5 in tuffo e 1 in contrasti, un attaccante 10 in finalizzazione e 5.9 in
--  contrasti. E la velocita' cresce poco per tutti (0.25-0.43): e' piu' innata
--  dell'abilita'. Le poche pendenze negative sono rumore statistico e valgono
--  zero.
-- ============================================================

create table if not exists private.pendenze_attributi (
  reparto   text not null check (reparto in ('GK','DEF','MID','ATT')),
  attributo text not null,
  pendenza  numeric(4,2) not null check (pendenza >= 0),
  primary key (reparto, attributo)
);

comment on table private.pendenze_attributi is
  'Quanto ogni attributo cresce per punto di overall, per reparto. Misurato sul catalogo: vedi la query nella migrazione 20260916140000.';

delete from private.pendenze_attributi;
insert into private.pendenze_attributi (reparto, attributo, pendenza) values
  ('GK', 'attacking_crossing', 0.08),
  ('DEF', 'attacking_crossing', 0.94),
  ('MID', 'attacking_crossing', 1.08),
  ('ATT', 'attacking_crossing', 1.07),
  ('GK', 'attacking_heading_accuracy', 0.09),
  ('DEF', 'attacking_heading_accuracy', 1.03),
  ('MID', 'attacking_heading_accuracy', 0.64),
  ('ATT', 'attacking_heading_accuracy', 0.84),
  ('GK', 'attacking_volleys', 0.19),
  ('DEF', 'attacking_volleys', 0.69),
  ('MID', 'attacking_volleys', 1.05),
  ('ATT', 'attacking_volleys', 1.17),
  ('DEF', 'defending', 1.03),
  ('MID', 'defending', 0.85),
  ('ATT', 'defending', 0.64),
  ('GK', 'defending_marking_awareness', 0.31),
  ('DEF', 'defending_marking_awareness', 1.10),
  ('MID', 'defending_marking_awareness', 0.89),
  ('ATT', 'defending_marking_awareness', 0.67),
  ('GK', 'defending_sliding_tackle', 0.10),
  ('DEF', 'defending_sliding_tackle', 0.96),
  ('MID', 'defending_sliding_tackle', 0.70),
  ('ATT', 'defending_sliding_tackle', 0.37),
  ('GK', 'dribbling', 0.27),
  ('DEF', 'dribbling', 1.03),
  ('MID', 'dribbling', 0.94),
  ('ATT', 'dribbling', 0.96),
  ('DEF', 'dribbling_generale', 0.95),
  ('MID', 'dribbling_generale', 0.89),
  ('ATT', 'dribbling_generale', 0.93),
  ('GK', 'finishing', 0.17),
  ('DEF', 'finishing', 0.82),
  ('MID', 'finishing', 1.09),
  ('ATT', 'finishing', 1.01),
  ('GK', 'gk', 0.96),
  ('DEF', 'gk', 0.02),
  ('MID', 'gk', 0.01),
  ('ATT', 'gk', 0.01),
  ('GK', 'gk_diving', 0.95),
  ('DEF', 'gk_diving', 0.00),
  ('MID', 'gk_diving', 0.00),
  ('ATT', 'gk_diving', 0.00),
  ('GK', 'gk_handling', 0.96),
  ('DEF', 'gk_handling', 0.01),
  ('MID', 'gk_handling', 0.02),
  ('ATT', 'gk_handling', 0.01),
  ('GK', 'gk_kicking', 0.88),
  ('DEF', 'gk_kicking', 0.03),
  ('MID', 'gk_kicking', 0.01),
  ('ATT', 'gk_kicking', 0.00),
  ('GK', 'gk_positioning', 1.04),
  ('DEF', 'gk_positioning', 0.01),
  ('MID', 'gk_positioning', 0.01),
  ('ATT', 'gk_positioning', 0.02),
  ('GK', 'gk_reflexes', 0.99),
  ('DEF', 'gk_reflexes', 0.03),
  ('MID', 'gk_reflexes', 0.00),
  ('ATT', 'gk_reflexes', 0.01),
  ('GK', 'goalkeeping_speed', 0.68),
  ('GK', 'mentality_aggression', 0.24),
  ('DEF', 'mentality_aggression', 1.04),
  ('MID', 'mentality_aggression', 0.82),
  ('ATT', 'mentality_aggression', 1.08),
  ('GK', 'mentality_composure', 0.92),
  ('DEF', 'mentality_composure', 1.29),
  ('MID', 'mentality_composure', 1.17),
  ('ATT', 'mentality_composure', 1.25),
  ('GK', 'mentality_interceptions', 0.27),
  ('DEF', 'mentality_interceptions', 1.05),
  ('MID', 'mentality_interceptions', 0.99),
  ('ATT', 'mentality_interceptions', 0.69),
  ('GK', 'mentality_penalties', 0.30),
  ('DEF', 'mentality_penalties', 0.48),
  ('MID', 'mentality_penalties', 0.79),
  ('ATT', 'mentality_penalties', 0.85),
  ('GK', 'mentality_positioning', 0.19),
  ('DEF', 'mentality_positioning', 0.88),
  ('MID', 'mentality_positioning', 1.10),
  ('ATT', 'mentality_positioning', 1.14),
  ('GK', 'mentality_vision', 0.88),
  ('DEF', 'mentality_vision', 1.19),
  ('MID', 'mentality_vision', 1.09),
  ('ATT', 'mentality_vision', 1.12),
  ('GK', 'movement_acceleration', 0.68),
  ('DEF', 'movement_acceleration', 0.26),
  ('MID', 'movement_acceleration', 0.30),
  ('ATT', 'movement_acceleration', 0.42),
  ('GK', 'movement_agility', 0.60),
  ('DEF', 'movement_agility', 0.35),
  ('MID', 'movement_agility', 0.52),
  ('ATT', 'movement_agility', 0.53),
  ('GK', 'movement_balance', 0.18),
  ('DEF', 'movement_balance', 0.09),
  ('MID', 'movement_balance', 0.31),
  ('ATT', 'movement_balance', 0.29),
  ('GK', 'movement_reactions', 1.14),
  ('DEF', 'movement_reactions', 1.14),
  ('MID', 'movement_reactions', 1.12),
  ('ATT', 'movement_reactions', 1.21),
  ('GK', 'movement_sprint_speed', 0.68),
  ('DEF', 'movement_sprint_speed', 0.43),
  ('MID', 'movement_sprint_speed', 0.25),
  ('ATT', 'movement_sprint_speed', 0.41),
  ('DEF', 'pace', 0.35),
  ('MID', 'pace', 0.27),
  ('ATT', 'pace', 0.42),
  ('DEF', 'passing', 1.11),
  ('MID', 'passing', 1.02),
  ('ATT', 'passing', 1.11),
  ('DEF', 'physic', 0.78),
  ('MID', 'physic', 0.78),
  ('ATT', 'physic', 0.82),
  ('GK', 'power_jumping', 0.81),
  ('DEF', 'power_jumping', 0.96),
  ('MID', 'power_jumping', 0.88),
  ('ATT', 'power_jumping', 0.92),
  ('GK', 'power_long_shots', 0.19),
  ('DEF', 'power_long_shots', 0.96),
  ('MID', 'power_long_shots', 1.25),
  ('ATT', 'power_long_shots', 1.08),
  ('GK', 'power_shot_power', 0.66),
  ('DEF', 'power_shot_power', 1.09),
  ('MID', 'power_shot_power', 1.05),
  ('ATT', 'power_shot_power', 1.01),
  ('GK', 'power_strength', 0.55),
  ('DEF', 'power_strength', 0.69),
  ('MID', 'power_strength', 0.62),
  ('ATT', 'power_strength', 0.66),
  ('DEF', 'shooting', 0.88),
  ('MID', 'shooting', 1.10),
  ('ATT', 'shooting', 1.03),
  ('GK', 'short_passing', 0.63),
  ('DEF', 'short_passing', 1.18),
  ('MID', 'short_passing', 0.95),
  ('ATT', 'short_passing', 1.11),
  ('GK', 'skill_ball_control', 0.43),
  ('DEF', 'skill_ball_control', 1.10),
  ('MID', 'skill_ball_control', 0.97),
  ('ATT', 'skill_ball_control', 1.02),
  ('GK', 'skill_curve', 0.15),
  ('DEF', 'skill_curve', 0.99),
  ('MID', 'skill_curve', 1.17),
  ('ATT', 'skill_curve', 1.23),
  ('GK', 'skill_fk_accuracy', 0.08),
  ('DEF', 'skill_fk_accuracy', 0.64),
  ('MID', 'skill_fk_accuracy', 1.01),
  ('ATT', 'skill_fk_accuracy', 1.10),
  ('GK', 'skill_long_passing', 0.67),
  ('DEF', 'skill_long_passing', 1.28),
  ('MID', 'skill_long_passing', 0.99),
  ('ATT', 'skill_long_passing', 1.12),
  ('GK', 'stamina', 0.46),
  ('DEF', 'stamina', 0.72),
  ('MID', 'stamina', 1.05),
  ('ATT', 'stamina', 0.90),
  ('GK', 'standing_tackle', 0.10),
  ('DEF', 'standing_tackle', 0.98),
  ('MID', 'standing_tackle', 0.83),
  ('ATT', 'standing_tackle', 0.59);

-- ------------------------------------------------------------
--  Gli attributi di un'istanza, com'e' adesso
--
--  Prende gli argomenti sciolti invece dell'id: cosi' la stessa funzione serve
--  sia per un giocatore singolo sia dentro una query che ne elabora migliaia,
--  senza una sottoquery per riga.
--
--  L'override della specializzazione vince sempre, e non viene scalato: e' un
--  valore assoluto gia' calcolato da completa_specializzazioni.
-- ------------------------------------------------------------
create or replace function private.attributi_effettivi(
  p_attributi      jsonb,
  p_posizioni      text[],
  p_delta_overall  integer,
  p_override       jsonb default null
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (select jsonb_object_agg(
       k,
       greatest(1, least(99,
         round((p_attributi->>k)::numeric
               + coalesce(pe.pendenza, 0) * coalesce(p_delta_overall, 0))
       ))::int
     )
     from jsonb_object_keys(coalesce(p_attributi, '{}'::jsonb)) as k
     left join private.pendenze_attributi pe
       on pe.reparto = private.macro_ruolo(p_posizioni) and pe.attributo = k
     where (p_attributi->>k) ~ '^[0-9]+$'),
    '{}'::jsonb
  ) || coalesce(p_override, '{}'::jsonb)
$$;

revoke all on function private.attributi_effettivi(jsonb, text[], integer, jsonb) from public, anon, authenticated;
