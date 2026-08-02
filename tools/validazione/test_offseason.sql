begin;

create temporary table esiti (
  n integer,
  verifica text,
  misurato text,
  esito text
) on commit drop;
grant select, insert on esiti to authenticated;
create temporary table rosa_prima as
select id, team_id from public.player_instances where league_id = 3 and team_id is not null;

set local role authenticated;
select set_config(
  'request.jwt.claims',
  json_build_object('sub', '5ef47be9-3b4f-40c3-86e4-03a7bb3ec266', 'role', 'authenticated')::text,
  true
);

select public.prepara_offseason(3::bigint, '{}'::bigint[], 0::smallint);

insert into esiti
select 1, 'fase lega', fase_carriera, case when stato = 'stagione' and fase_carriera = 'offseason' then 'OK' else 'KO' end
from public.leagues where id = 3;

insert into esiti
select 2, 'off-season creata', count(*)::text, case when count(*) = 1 then 'OK' else 'KO' end
from public.offseasons where league_id = 3 and stato = 'aperta';

insert into esiti
select 3, 'rinnovi visibili alla mia squadra', count(*)::text, case when count(*) between 21 and 25 then 'OK' else 'KO' end
from public.contract_renewals where league_id = 3;

insert into esiti
select 4, 'rose dopo i possibili ritiri', count(*)::text, case when count(*) between 80 and 100 then 'OK' else 'KO' end
from public.player_instances where league_id = 3 and team_id is not null and not ritirato;

select public.rispondi_rinnovo(
  cr.id,
  cr.richiesta_max,
  1::smallint
)
from public.contract_renewals cr
where cr.team_id = (select id from public.teams where league_id = 3 and user_id = auth.uid())
order by cr.id limit 1;

insert into esiti
select 5, 'rinnovo alla richiesta massima', stato, case when stato = 'accettato' then 'OK' else 'KO' end
from public.contract_renewals
where team_id = (select id from public.teams where league_id = 3 and user_id = auth.uid())
order by id limit 1;

reset role;
update public.player_instances pi set team_id = rp.team_id, ritirato = false
from rosa_prima rp where rp.id = pi.id and pi.team_id is null;
update public.player_instances set contratto_scadenza = 2 where league_id = 3 and team_id is not null;
update public.contract_renewals set stato = 'accettato', offerta = richiesta_max, durata = 1, risolta_il = now()
where league_id = 3 and stato = 'in_attesa';
update public.teams set budget = 1000000000 where league_id = 3;

set local role authenticated;
select set_config(
  'request.jwt.claims',
  json_build_object('sub', '5ef47be9-3b4f-40c3-86e4-03a7bb3ec266', 'role', 'authenticated')::text,
  true
);
select public.avvia_prossima_stagione(3::bigint);
insert into esiti
select 6, 'nuova stagione', l.stagione_corrente::text,
       case when l.stagione_corrente = 2 and l.fase_carriera = 'normale' then 'OK' else 'KO' end
from public.leagues l where l.id = 3;
insert into esiti
select 7, 'calendario nuove squadre', count(*)::text, case when count(*) = 4 then 'OK' else 'KO' end
from public.standings s join public.seasons se on se.id = s.season_id
where se.league_id = 3 and se.numero = 2;
reset role;
select verifica, misurato, esito from esiti order by n;
rollback;
