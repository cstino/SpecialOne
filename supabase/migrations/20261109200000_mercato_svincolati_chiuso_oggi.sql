-- Serie F, 9/11/2026 (decisione del committente): il mercato svincolati di oggi si chiude subito. Le 128 aste ancora
-- aperte della giornata di mercato 8/11 (la vecchia vetrina con tutti gli svincolati insieme) si chiudono senza
-- assegnazioni e tutte le offerte fatte si annullano; chi aveva offerto riceve una notifica. Gli ex giocatori di
-- squadre restano nella coda (20261109090000) e i non scelti nella vetrina fissa: tornano un po' alla volta, 10 al
-- giorno, dall'estrazione di stasera dopo le partite (22:30), insieme all'estrazione normale per ruolo e agli
-- svincolati ancora pagati. Queste aste chiuse non sono "dalla coda": nessuno viene bruciato.

begin;

create temp table aste_chiuse on commit drop as
select a.id from public.free_agent_auctions a
where a.league_id = 63 and a.giorno = '2026-11-08' and a.stato = 'aperta';

select private.notifica(t.user_id, 63, 'mercato_asta', 'Offerte sugli svincolati annullate',
  'Il mercato svincolati di oggi è chiuso e le ' || x.n || case when x.n = 1 then ' offerta che avevi fatto è stata annullata.' else ' offerte che avevi fatto sono state annullate.' end
  || ' Riapre stasera dopo le partite, col nuovo sistema: 10 svincolati estratti al giorno.',
  jsonb_build_object('view', 'mercato'))
from (select b.team_id, count(*) n from public.free_agent_bids b where b.auction_id in (select id from aste_chiuse) group by b.team_id) x
join public.teams t on t.id = x.team_id where t.user_id is not null;

delete from public.free_agent_bids where auction_id in (select id from aste_chiuse);

update public.free_agent_auctions set stato = 'deserta', risolta_il = now() where id in (select id from aste_chiuse);

do $$
begin
  if exists (select 1 from public.free_agent_auctions where league_id = 63 and stato = 'aperta') then
    raise exception 'restano aste aperte';
  end if;
end $$;

commit;
