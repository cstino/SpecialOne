-- Richiesta diretta dell'admin sulla lega 37 (Real Fampionato): bloccare
-- l'off-season in corso e annullare il mercato fatto finora, per poterlo
-- rifare. Tocca SOLO le 6 squadre originali (entrata_stagione=1) che hanno
-- usato spin: le due squadre entranti (Fonald Fump, FC Rocazz) restano
-- intatte, come richiesto esplicitamente.
--
-- Inventario verificato prima di scrivere questa migrazione:
--   - 22 spin finiti in asta, tutti andati deserti (nessun giocatore o
--     soldo coinvolto)
--   - 8 spin ingaggiati direttamente, tutti ancora presso la squadra che
--     li aveva presi (nessuno ri-scambiato o risvincolato nel frattempo)
--   - 4 aste normali (non-spin) vinte durante l'off-season, anch'esse
--     ancora presso il vincitore. Curiosita': nessuna delle quattro ha mai
--     addebitato budget (zero transazioni asta_svincolato nel registro),
--     quindi il ripristino non prevede nessun rimborso per quelle.
--   - zero scambi accettati durante questa off-season
--
-- Applicata gia' verificata in transazione con rollback prima di questa
-- esecuzione reale.
-- 1. Blocco off-season: scadenza spostata di un anno avanti
update public.offseasons set scade_il = scade_il + interval '365 days'
where league_id = 37 and stato = 'aperta';
update public.leagues set offseason_fine = (
  select scade_il from public.offseasons where league_id = 37 and stato = 'aperta'
) where id = 37;

-- 2. Spin andati in asta (deserti) delle squadre originali (entrata_stagione=1)
create temporary table tmp_spin_asta on commit drop as
select os.id as spin_id, a.id as auction_id
from public.offseason_spins os
join public.teams t on t.id = os.team_id
join public.free_agent_auctions a on a.league_id = os.league_id and a.player_id = os.player_id and a.origine = 'spin_offseason'
where os.offseason_id = 13 and os.stato = 'asta' and t.entrata_stagione = 1;

select count(*) as spin_asta_da_annullare from tmp_spin_asta;

delete from public.free_agent_auctions where id in (select auction_id from tmp_spin_asta);
delete from public.offseason_spins where id in (select spin_id from tmp_spin_asta);

-- 3. Spin ingaggiati delle squadre originali: rilascia, rimborsa, storna
create temporary table tmp_spin_ingaggiato on commit drop as
select os.id as spin_id, os.team_id, os.player_id, os.ingaggio
from public.offseason_spins os
join public.teams t on t.id = os.team_id
where os.offseason_id = 13 and os.stato = 'ingaggiato' and t.entrata_stagione = 1;

select count(*) as spin_ingaggiati_da_annullare from tmp_spin_ingaggiato;

update public.player_instances pi
set team_id = null
from tmp_spin_ingaggiato tsi
where pi.league_id = 37 and pi.player_id = tsi.player_id and pi.team_id = tsi.team_id;

do $$
declare r record; v_saldo bigint;
begin
  for r in select * from tmp_spin_ingaggiato loop
    update public.teams set budget = budget + r.ingaggio where id = r.team_id returning budget into v_saldo;
    insert into public.transactions(league_id, team_id, tipo, importo, descrizione, saldo_dopo)
    values (37, r.team_id, 'annullamento_spin_offseason', r.ingaggio,
      'Annullamento spin off-season: ' || (select nome from public.players where id = r.player_id), v_saldo);
  end loop;
end $$;

delete from public.offseason_spins where id in (select spin_id from tmp_spin_ingaggiato);

-- 4. Le 4 aste normali vinte durante l'off-season: rilascia, nessun rimborso
--    (nessun addebito risulta mai registrato per queste)
create temporary table tmp_aste_normali on commit drop as
select a.id as auction_id, a.player_id, a.vincitore_team_id as team_id
from public.free_agent_auctions a
where a.id in (1180, 1184, 1186, 1199);

update public.player_instances pi
set team_id = null
from tmp_aste_normali tan
where pi.league_id = 37 and pi.player_id = tan.player_id and pi.team_id = tan.team_id;

delete from public.free_agent_auctions where id in (select auction_id from tmp_aste_normali);
