begin;

create temporary table esiti_timer (
  n integer primary key,
  verifica text not null,
  misurato text,
  esito text not null
) on commit drop;
grant select, insert on esiti_timer to authenticated;

-- sdsDas e l'utente admin reali, ma ogni modifica viene annullata.
update public.leagues set stato = 'conclusa', fase_carriera = 'normale' where id = 3;
update public.seasons set stato = 'conclusa' where league_id = 3 and numero = (select stagione_corrente from public.leagues where id = 3);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  json_build_object('sub', '5ef47be9-3b4f-40c3-86e4-03a7bb3ec266', 'role', 'authenticated')::text,
  true
);

select public.prepara_offseason(3::bigint, '{}'::bigint[], 0::smallint);

insert into esiti_timer
select 1, 'durata off-season', round(extract(epoch from (o.scade_il - o.creata_il)) / 3600, 2)::text || ' ore',
       case when o.scade_il between o.creata_il + interval '23 hours 59 minutes'
                                   and o.creata_il + interval '24 hours 1 minute' then 'OK' else 'KO' end
from public.offseasons o
where o.league_id = 3 and o.stato = 'aperta';

do $$
declare v_msg text;
begin
  perform public.avvia_prossima_stagione(3::bigint);
  insert into esiti_timer values (2, 'blocco avvio anticipato', 'nessun errore', 'KO');
exception when others then
  get stacked diagnostics v_msg = message_text;
  insert into esiti_timer values (
    2, 'blocco avvio anticipato', v_msg,
    case when v_msg ilike '%24 ore%' then 'OK' else 'KO' end
  );
end $$;

reset role;

-- Il test porta ogni squadra sotto soglia lasciando solo 18 giocatori. I
-- rinnovi aperti vengono accettati, cosi' si esercita esclusivamente il
-- completamento automatico e non il rilascio per mancata risposta.
with ordinati as (
  select pi.id, row_number() over(partition by pi.team_id order by pi.overall_corrente desc, pi.id) posizione
  from public.player_instances pi
  join public.teams t on t.id = pi.team_id
  where t.league_id = 3 and t.attiva and not pi.ritirato
)
update public.player_instances pi
set team_id = null
from ordinati o
where o.id = pi.id and o.posizione > 18;

update public.contract_renewals cr
set stato = 'accettato', offerta = richiesta_max, durata = 1, risolta_il = clock_timestamp()
where cr.offseason_id = (select id from public.offseasons where league_id = 3 and stato = 'aperta');

update public.player_instances
set contratto_scadenza = (select stagione_a from public.offseasons where league_id = 3 and stato = 'aperta')
where team_id in (select id from public.teams where league_id = 3 and attiva);

update public.teams set budget = 1000000000 where league_id = 3 and attiva;
update public.offseasons set scade_il = clock_timestamp() - interval '1 minute' where league_id = 3 and stato = 'aperta';
update public.leagues set offseason_fine = clock_timestamp() - interval '1 minute' where id = 3;

set local role authenticated;
select set_config(
  'request.jwt.claims',
  json_build_object('sub', '5ef47be9-3b4f-40c3-86e4-03a7bb3ec266', 'role', 'authenticated')::text,
  true
);
select public.avvia_prossima_stagione(3::bigint);
reset role;

insert into esiti_timer
select 3, 'completamento automatico rose', string_agg(t.nome || ': ' || coalesce(r.numero, 0), ', ' order by t.id),
       case when min(coalesce(r.numero, 0)) = 21 and max(coalesce(r.numero, 0)) = 21 then 'OK' else 'KO' end
from public.teams t
left join lateral (
  select count(*)::integer numero from public.player_instances pi where pi.team_id = t.id and not pi.ritirato
) r on true
where t.league_id = 3 and t.attiva;

insert into esiti_timer
select 4, 'prima giornata alle 23 Roma', min(f.data_sim)::text,
       case when extract(hour from (min(f.data_sim) at time zone 'Europe/Rome')) = 23 then 'OK' else 'KO' end
from public.fixtures f
join public.seasons s on s.id = f.season_id
where s.league_id = 3 and s.numero = (select stagione_corrente from public.leagues where id = 3);

insert into esiti_timer
select 5, 'regola limite delle 23:00',
       private.primo_calcio_dopo('2026-08-02 20:59:00+00'::timestamptz)::text || ' / ' ||
       private.primo_calcio_dopo('2026-08-02 21:00:00+00'::timestamptz)::text,
       case
         when private.primo_calcio_dopo('2026-08-02 20:59:00+00'::timestamptz) = '2026-08-02 21:00:00+00'::timestamptz
          and private.primo_calcio_dopo('2026-08-02 21:00:00+00'::timestamptz) = '2026-08-03 21:00:00+00'::timestamptz
         then 'OK' else 'KO'
       end;

insert into public.notifications(user_id, league_id, tipo, titolo, corpo)
values ('5ef47be9-3b4f-40c3-86e4-03a7bb3ec266', 3, 'sistema', 'Notifica eliminabile', 'Test con rollback');

set local role authenticated;
select set_config(
  'request.jwt.claims',
  json_build_object('sub', '5ef47be9-3b4f-40c3-86e4-03a7bb3ec266', 'role', 'authenticated')::text,
  true
);
select public.elimina_notifica((select id from public.notifications where titolo = 'Notifica eliminabile' order by id desc limit 1));
reset role;

insert into esiti_timer
select 6, 'eliminazione propria notifica', count(*)::text,
       case when count(*) = 0 then 'OK' else 'KO' end
from public.notifications where titolo = 'Notifica eliminabile';

select verifica, misurato, esito from esiti_timer order by n;
rollback;
