-- Richiesta admin (lega 37, "Real Fampionato"): prorogare l'off-season in
-- corso di 24 ore per avere tempo di sistemare alcune cose prima dell'avvio
-- della stagione 2. Sposta la sola scadenza (offseasons.scade_il, letta sia
-- dal cron di finalizzazione sia da leagues.offseason_fine per il gate dello
-- spin off-season): niente altro nello stato della lega cambia.
update public.offseasons
set scade_il = scade_il + interval '24 hours'
where league_id = 37 and stato = 'aperta';

update public.leagues
set offseason_fine = (select scade_il from public.offseasons where league_id = 37 and stato = 'aperta')
where id = 37;
