with rinnovi_da_accettare as (
  select
    cr.id,
    cr.team_id,
    cr.player_instance_id,
    cr.richiesta_min as offerta,
    off.stagione_a
  from public.contract_renewals cr
  join public.offseasons off on off.id = cr.offseason_id
  join public.teams t on t.id = cr.team_id
  join public.leagues l on l.id = cr.league_id
  where lower(l.nome) = lower('sdsDas')
    and t.nome like 'Test Squadra%'
    and t.attiva
    and off.stato = 'aperta'
    and cr.stato in ('in_attesa', 'controproposta')
),
aggiorna_giocatori as (
  update public.player_instances pi
  set ingaggio = r.offerta,
      contratto_scadenza = r.stagione_a
  from rinnovi_da_accettare r
  where pi.id = r.player_instance_id
    and pi.team_id = r.team_id
  returning pi.id, pi.team_id, pi.ingaggio
),
aggiorna_rinnovi as (
  update public.contract_renewals cr
  set offerta = r.offerta,
      durata = 1,
      stato = 'accettato',
      risolta_il = now()
  from rinnovi_da_accettare r
  where cr.id = r.id
  returning cr.id, cr.team_id, cr.offerta
)
select
  t.id as team_id,
  t.nome,
  count(ar.id) as rinnovi_accettati,
  round(coalesce(sum(ar.offerta), 0) / 1000000.0, 1) as monte_rinnovato_m
from public.teams t
left join aggiorna_rinnovi ar on ar.team_id = t.id
join public.leagues l on l.id = t.league_id
where lower(l.nome) = lower('sdsDas')
  and t.nome like 'Test Squadra%'
group by t.id, t.nome
order by t.id;

select
  t.id as team_id,
  t.nome,
  (select count(*) from public.player_instances pi where pi.team_id = t.id and not pi.ritirato) as giocatori,
  (select round(coalesce(sum(pi.ingaggio), 0) / 1000000.0, 1) from public.player_instances pi where pi.team_id = t.id and not pi.ritirato) as monte_ingaggi_m,
  round(t.budget / 1000000.0, 1) as budget_m,
  (select count(*) from public.contract_renewals cr where cr.team_id = t.id and cr.stato in ('in_attesa', 'controproposta')) as rinnovi_aperti,
  (select count(*) from public.contract_renewals cr where cr.team_id = t.id and cr.stato = 'accettato') as rinnovi_accettati
from public.teams t
join public.leagues l on l.id = t.league_id
where lower(l.nome) = lower('sdsDas')
  and t.nome like 'Test Squadra%'
order by t.id;
