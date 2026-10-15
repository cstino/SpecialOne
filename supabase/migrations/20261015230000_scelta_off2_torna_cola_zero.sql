-- Decisione dell'amministratore (15/10/2026): la scelta OFF-Season 2 di ASD Cola Zero, ceduta a Pro secco nello
-- scambio 583, torna ad ASD Cola Zero. L'allenatore di Cola Zero ha lasciato il giorno dopo lo scambio: il valore di
-- quella scelta (posizione non ancora decisa) dipenderebbe dall'abbandono della squadra. Il resto dello scambio resta valido.
update public.scelte_draft set team_proprietario_id = 305, aggiornata_il = now()
where id = 3398 and team_origine_id = 305 and team_proprietario_id = 299 and stato = 'futura';

insert into public.notifications (user_id, league_id, tipo, titolo, corpo, dati)
select t.user_id, 63, 'sistema', 'Scelta OFF-Season 2 restituita',
       'Decisione dell''amministratore: la scelta OFF-Season 2 di ASD Cola Zero, ceduta nello scambio con Pro secco, torna ad ASD Cola Zero perché il suo allenatore ha lasciato la squadra il giorno dopo. Il resto dello scambio resta valido.',
       jsonb_build_object('scelta_id', 3398, 'proposta_id', 583)
from public.teams t where t.id in (299, 305) and t.user_id is not null;
