-- 500 crediti a tutte le squadre della Serie F per il lancio di RoulettOne (richiesta del committente, 9/11/2026).
-- Non contano come vincita. Notifica col "Faites vos jeux": col view del casino' per chi riceve tutte le sezioni,
-- senza view (sezione calcio) per chi ha scelto di ricevere solo le notifiche del calcio.

begin;

select private.casino_saldo(t.league_id, t.user_id)
from public.teams t where t.league_id = 63 and t.attiva and t.user_id is not null;

update public.casino_saldi s set crediti = crediti + 500, aggiornato_il = now()
from public.teams t
where s.league_id = 63 and t.league_id = 63 and t.attiva and t.user_id = s.user_id;

select private.notifica(t.user_id, 63, 'sistema', 'Faites vos jeux! 🎡',
  'Al casinò è arrivata RoulettOne, la roulette live: ti abbiamo regalato 500 crediti per provarla. Faites vos jeux!',
  case when t.notifiche_scelta = 'calcio' then '{}'::jsonb else jsonb_build_object('view', 'casinone') end)
from public.teams t where t.league_id = 63 and t.attiva and t.user_id is not null;

commit;
