-- ============================================================
--  PROMEMORIA FORMAZIONE ALLE 22:00, NIENTE PIU' AVVISO A GIORNATA FATTA
--
--  Richiesta dell'utente: la notifica "formazione automatica" che
--  simula-giornata mandava a ogni giornata simulata (una per squadra che non
--  aveva schierato entro le 23:00) arrivava sempre, un rumore di fondo senza
--  piu' nulla da fare a quel punto -- la partita e' gia' stata giocata con
--  la formazione di ripiego. Rimossa dalla Edge Function (il fallback
--  stesso resta: qualcuno deve pur scendere in campo).
--
--  Al suo posto, un promemoria PRIMA che sia troppo tardi: alle 22:00, un'ora
--  prima del fischio d'inizio delle 23:00, a chi non ha ancora salvato la
--  formazione per la prossima giornata in calendario.
-- ============================================================

create or replace function private.promemoria_formazione_22()
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_lega record;
  v_giornata smallint;
  v_team record;
  v_inviate integer := 0;
begin
  -- Il job gira ogni ora: qui si decide se e' l'ora giusta a Roma, stessa
  -- guardia gia' in uso per private.simula_giornata_notturna().
  if extract(hour from (now() at time zone 'Europe/Rome')) <> 22 then
    return 0;
  end if;

  for v_lega in
    select l.id from public.leagues l where l.stato = 'stagione'
  loop
    -- La stessa giornata che simula-giornata simulera' stanotte: la prima
    -- fixture ancora "programmata" in ordine.
    select f.giornata into v_giornata
    from public.fixtures f
    where f.league_id = v_lega.id and f.stato = 'programmata'
    order by f.giornata
    limit 1;

    if v_giornata is null then
      continue;
    end if;

    for v_team in
      select distinct t.id as team_id, t.user_id
      from public.fixtures f
      join public.teams t on t.id in (f.home_team_id, f.away_team_id) and t.attiva
      where f.league_id = v_lega.id and f.giornata = v_giornata and f.stato = 'programmata'
    loop
      if exists (
        select 1 from public.lineups l
        where l.team_id = v_team.team_id and l.giornata = v_giornata
      ) then
        continue;
      end if;

      perform private.notifica(
        v_team.user_id, v_lega.id, 'formazione_mancante',
        'Hai schierato la formazione?',
        'Manca poco alla prossima partita: il fischio d''inizio e'' alle 23:00.',
        jsonb_build_object('view', 'squad', 'giornata', v_giornata)
      );
      v_inviate := v_inviate + 1;
    end loop;
  end loop;

  return v_inviate;
end;
$$;

revoke all on function private.promemoria_formazione_22() from public, anon, authenticated;

comment on function private.promemoria_formazione_22() is
  'Invocata ogni ora dal cron: alle 22 di Roma avvisa chi non ha ancora schierato la formazione per la giornata di stanotte.';

select cron.schedule(
  'promemoria-formazione-22',
  '0 * * * *',
  $cron$select private.promemoria_formazione_22();$cron$
);
