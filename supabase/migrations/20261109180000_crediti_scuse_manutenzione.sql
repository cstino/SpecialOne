-- 500 crediti a tutte le squadre della Serie F per scusarsi della manutenzione del 9/11/2026 (richiesta del committente).
-- Il saldo si crea se manca (come alla prima apertura del casino'); non conta come vincita (totale_vinto invariato).

begin;

select private.casino_saldo(t.league_id, t.user_id)
from public.teams t where t.league_id = 63 and t.attiva and t.user_id is not null;

update public.casino_saldi s set crediti = crediti + 500, aggiornato_il = now()
from public.teams t
where s.league_id = 63 and t.league_id = 63 and t.attiva and t.user_id = s.user_id;

select private.notifica(t.user_id, 63, 'sistema', '500 crediti per te 👉👈',
  'Scusa per il disagio della manutenzione di oggi: ti abbiamo regalato 500 crediti da spendere nel casinò 👉👈',
  jsonb_build_object('view', 'casinone'))
from public.teams t where t.league_id = 63 and t.attiva and t.user_id is not null;

commit;

-- Aggiunta (applicata a parte): 10 allenatori ricevono solo le notifiche del calcio e la notifica col view 'casinone'
-- (sezione betone) era stata scartata. Il messaggio riguarda la manutenzione: a loro va senza view (sezione calcio).
select private.notifica(t.user_id, 63, 'sistema', '500 crediti per te 👉👈',
  'Scusa per il disagio della manutenzione di oggi: ti abbiamo regalato 500 crediti da spendere nel casinò 👉👈', '{}'::jsonb)
from public.teams t where t.league_id = 63 and t.attiva and t.user_id is not null
  and not exists (select 1 from public.notifications n where n.user_id = t.user_id and n.titolo like '500 crediti per te%');
