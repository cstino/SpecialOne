-- Serie F, 9/11/2026: con le nuove regole della trattativa (20261109130000) si erano annullati i rinnovi firmati ma
-- non riaperte le trattative chiuse (3 rifiuti) con le regole vecchie: quei giocatori restavano "in rottura". Si
-- riaprono quelli in scadenza con la trattativa chiusa e nessuna offerta nel registro (che esiste dalle 14:38: chi
-- ha offerte registrate e' stato chiuso con le regole nuove e resta chiuso). Notifica alle squadre.

begin;

create temp table riaperte on commit drop as
select pi.id, pi.team_id, p.nome
from public.player_instances pi join public.players p on p.id = pi.player_id join public.teams t on t.id = pi.team_id
where t.league_id = 63 and pi.rinnovo_tentativi >= 3 and pi.contratto_scadenza = 3 and not pi.ritirato
  and not exists (select 1 from private.registro_trattative r where r.player_instance_id = pi.id);

update public.player_instances set rinnovo_tentativi = 0 where id in (select id from riaperte);

select private.notifica(t.user_id, 63, 'sistema', 'Trattative riaperte',
  'Con le nuove regole dei rinnovi puoi riprovare a rinnovare ' || x.nomi || ': i tentativi ripartono da zero.',
  jsonb_build_object('view', 'squad'))
from (select team_id, string_agg(nome, ', ' order by nome) nomi from riaperte group by team_id) x
join public.teams t on t.id = x.team_id where t.user_id is not null;

select t.nome, r.nome from riaperte r join public.teams t on t.id = r.team_id order by 1, 2;

commit;
