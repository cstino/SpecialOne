-- ============================================================
--  QUALI ATTRIBUTI POSSONO REGGERE UNA SCELTA TATTICA
--  Sola lettura. Eseguire con:
--    supabase db query --linked -f tools/validazione/leve-tattiche.sql
--
--  PERCHE' ESISTE
--  Il sistema tattico in progetto (settembre 2026) si regge sull'idea che
--  scegliere gli interpreti giusti sia una bravura. Perche' lo sia davvero,
--  l'attributo su cui una tattica si appoggia deve avere due proprieta':
--
--    1. essere DISPERSO dentro una fascia stretta di overall — altrimenti
--       tutti i giocatori di quel livello sono uguali e non c'e' scelta;
--    2. essere INDIPENDENTE dall'overall — altrimenti "prendi chi ha
--       l'attributo alto" e "prendi chi e' piu' forte" sono la stessa frase,
--       e la tattica non aggiunge nessuna decisione.
--
--  La seconda e' la piu' importante e la meno ovvia. Un attributo con
--  correlazione 0.7 sull'overall e' overall travestito: costruirci sopra una
--  tattica significa scrivere "abbi giocatori migliori".
--
--  ATTENZIONE ALLA LETTURA: la seconda query mette insieme tutti i ruoli, e
--  li' ampiezze enormi (contrasti in scivolata, intercetti, posizionamento)
--  sono gonfiate dalla differenza FRA ruoli, non dalla dispersione dentro un
--  ruolo. Un attaccante ha 20 di intercetti e un difensore 76: sembra una
--  leva formidabile e non lo e'. Per un giudizio corretto conta la prima
--  query, che tiene i reparti separati.
-- ============================================================

-- ------------------------------------------------------------
--  1. DENTRO CIASCUN REPARTO — e' questa che conta
-- ------------------------------------------------------------
with pop as (
  select private.macro_ruolo(p.posizioni) as reparto, p.overall, p.attributi as a
  from public.players p
  where p.disponibile_estrazione
    and p.overall between 70 and 80          -- la fascia in cui girano le leghe
    and not p.origine_vivaio
    and p.attributi ? 'movement_sprint_speed'
), lunga as (
  select reparto, overall, k as attributo, (a->>k)::numeric as v
  from pop, lateral (values
    ('movement_sprint_speed'), ('power_strength'), ('stamina'),
    ('mentality_aggression'), ('movement_agility'),
    ('short_passing'), ('skill_long_passing'),
    ('mentality_composure'), ('defending_marking_awareness')
  ) as t(k)
)
select reparto, attributo, count(*) as n,
       round(percentile_cont(0.10) within group (order by v)::numeric, 0) as p10,
       round(percentile_cont(0.90) within group (order by v)::numeric, 0) as p90,
       round((percentile_cont(0.90) within group (order by v)
            - percentile_cont(0.10) within group (order by v))::numeric, 0) as ampiezza,
       round(corr(v, overall)::numeric, 2) as corr_overall,
       case
         when abs(coalesce(corr(v, overall), 0)) < 0.20
          and percentile_cont(0.90) within group (order by v)
            - percentile_cont(0.10) within group (order by v) >= 20 then 'LEVA VERA'
         when abs(coalesce(corr(v, overall), 0)) < 0.35 then 'usabile'
         else 'overall travestito'
       end as giudizio
from lunga
where reparto in ('DEF', 'MID', 'ATT') and v is not null
group by reparto, attributo
order by reparto, abs(coalesce(corr(v, overall), 0));
