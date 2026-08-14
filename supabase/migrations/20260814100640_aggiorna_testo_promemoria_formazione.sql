-- ============================================================
--  PROMEMORIA FORMAZIONE: testo richiesto e invio idempotente
-- ============================================================
-- Il cron gira ogni ora e questa funzione agisce soltanto alle 22:00 di
-- Roma. Il controllo sulla notifica evita doppioni se pg_cron ritenta il job.

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
  v_inizio_giorno timestamptz := ((now() at time zone 'Europe/Rome')::date::timestamp at time zone 'Europe/Rome');
begin
  if extract(hour from (now() at time zone 'Europe/Rome')) <> 22 then
    return 0;
  end if;

  for v_lega in
    select l.id from public.leagues l where l.stato = 'stagione'
  loop
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
      ) or exists (
        select 1 from public.notifications n
        where n.user_id = v_team.user_id
          and n.league_id = v_lega.id
          and n.tipo = 'formazione_mancante'
          and n.dati ->> 'giornata' = v_giornata::text
          and n.creata_il >= v_inizio_giorno
      ) then
        continue;
      end if;

      perform private.notifica(
        v_team.user_id, v_lega.id, 'formazione_mancante',
        'Promemoria formazione',
        'Hai inserito la formazione? manca solamente un''ora alla prossima giornata.',
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
  'Alle 22:00 di Roma invia una sola push di promemoria a chi non ha salvato la formazione per la prossima giornata.';
