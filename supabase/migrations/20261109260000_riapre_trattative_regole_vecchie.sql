-- Serie F, 9/11/2026 (decisione del committente, verificata sul backup delle 05:00): riaperte le trattative chiuse
-- con le regole vecchie, prima dell'aggiornamento delle 11:56 (20261109130000), che annullava i rinnovi firmati ma
-- non riapriva le trattative chiuse. Alle 05:00 avevano gia' 3 tentativi usati: Talbi (Pro secco), Carnesecchi e
-- Boniface (Cocciaspigola). Gli altri giocatori con la trattativa chiusa l'hanno chiusa dopo e restano chiusi.
update public.player_instances pi set rinnovo_tentativi = 0
from public.players p, public.teams t
where p.id = pi.player_id and t.id = pi.team_id and t.league_id = 63 and pi.rinnovo_tentativi = 3 and pi.contratto_scadenza = 3
  and (t.nome, p.nome) in (('Pro secco', 'C. Talbi'), ('Cocciaspigola', 'M. Carnesecchi'), ('Cocciaspigola', 'V. Boniface'));
