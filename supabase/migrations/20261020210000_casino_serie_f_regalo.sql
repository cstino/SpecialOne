-- Casino': AviatOne e CrazyOne accesi anche in Serie F; 500 crediti in regalo a tutti i giocatori delle leghe con il
-- casino' (Serie F e LegaBot) e notifica "Buon Divertimento!". Chi non ha mai aperto il casino' parte da 1.500
-- (i soliti 1.000 iniziali + i 500 di regalo).
update public.leagues set casino_crazyone = true, casino_aviatone = true where id = 63;

update public.casino_saldi s set crediti = crediti + 500, aggiornato_il = now()
 where s.league_id in (62, 63)
   and exists (select 1 from public.teams t where t.league_id = s.league_id and t.user_id = s.user_id and t.attiva);

insert into public.casino_saldi (league_id, user_id, team_id, crediti, settimana)
select t.league_id, t.user_id, t.id, 1500, private.casino_settimana()
  from public.teams t
 where t.league_id in (62, 63) and t.attiva and t.user_id is not null
   and not exists (select 1 from public.casino_saldi s where s.league_id = t.league_id and s.user_id = t.user_id);

insert into public.notifications (user_id, league_id, tipo, titolo, corpo, dati)
select t.user_id, t.league_id, 'sistema', 'Buon Divertimento!', '500 crediti ti aspettano per provare i nuovi giochi.', '{"view": "betone"}'::jsonb
  from public.teams t
 where t.league_id in (62, 63) and t.attiva and t.user_id is not null;
