-- Serie F (lega 63): chiusura dell'off-season spostata da domenica 8/11 alle 11:00 alle 12:00 Roma (richiesta del
-- committente). offseason_fine trascina con se' la finestra 'off' delle scelte (trigger sincronizza_estrazione_off).
update public.leagues
  set offseason_fine = timestamp '2026-11-08 12:00:00' at time zone 'Europe/Rome'
  where id = 63;
update public.offseasons
  set scade_il = timestamp '2026-11-08 12:00:00' at time zone 'Europe/Rome'
  where league_id = 63 and stato = 'aperta';
