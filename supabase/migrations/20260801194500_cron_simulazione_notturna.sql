-- ============================================================
--  SIMULAZIONE NOTTURNA AUTOMATICA
--
--  Fino ad ora la giornata si simulava solo premendo il pulsante admin.
--  Qui il campionato comincia a girare da solo.
--
--  ORA LEGALE — la trappola annunciata in CLAUDE.md §2.
--  pg_cron pianifica in UTC. Un job fissato alle 23:00 UTC sarebbe a
--  mezzanotte d'inverno e all'una d'estate. Percio' il job gira **ogni ora**
--  e la funzione decide se e' davvero mezzanotte a Roma. Nessun salto e
--  nessun doppione al cambio dell'ora.
--
--  DOPPIA SIMULAZIONE — due guardie indipendenti:
--   1. si simula solo una giornata la cui data programmata e' gia' arrivata;
--   2. non si simula se in quella lega e' gia' stata registrata una partita
--      nella stessa giornata di calendario italiana.
--  La RPC registra_risultato_partita e' comunque idempotente per fixture.
-- ============================================================

create extension if not exists pg_cron;
create extension if not exists pg_net with schema extensions;

create or replace function private.simula_giornata_notturna()
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_oggi    date;
  v_chiave  text;
  v_lega    bigint;
  v_lanciate integer := 0;
begin
  -- Il job gira ogni ora: qui si decide se e' l'ora giusta a Roma.
  if extract(hour from (now() at time zone 'Europe/Rome')) <> 0 then
    return 0;
  end if;

  v_oggi := (now() at time zone 'Europe/Rome')::date;

  select decrypted_secret into v_chiave
  from vault.decrypted_secrets
  where name = 'chiave_simulazione';

  if v_chiave is null then
    raise exception using
      errcode = '55000',
      message = 'Manca il segreto chiave_simulazione nel vault: il cron non puo'' autenticarsi.';
  end if;

  for v_lega in
    select l.id
    from public.leagues l
    where l.stato = 'stagione'
      -- Guardia 1: la giornata deve essere in calendario per oggi o prima.
      and exists (
        select 1
        from public.fixtures f
        where f.league_id = l.id
          and f.stato = 'programmata'
          and (f.data_sim at time zone 'Europe/Rome')::date <= v_oggi
      )
      -- Guardia 2: niente due giornate nella stessa data italiana.
      and not exists (
        select 1
        from public.matches m
        join public.fixtures f2 on f2.id = m.fixture_id
        where f2.league_id = l.id
          and (m.simulata_il at time zone 'Europe/Rome')::date = v_oggi
      )
    order by l.id
  loop
    -- Il progetto e' hhvyyjpbsgjcaaaizgwb: se cambia, cambia anche questo URL.
    perform extensions.http_post(
      url     := 'https://hhvyyjpbsgjcaaaizgwb.supabase.co/functions/v1/simula-giornata',
      body    := jsonb_build_object('league_id', v_lega),
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || v_chiave
      ),
      timeout_milliseconds := 120000
    );
    v_lanciate := v_lanciate + 1;
  end loop;

  return v_lanciate;
end;
$$;

revoke all on function private.simula_giornata_notturna() from public, anon, authenticated;

comment on function private.simula_giornata_notturna() is
  'Invocata ogni ora dal cron: simula la giornata solo se a Roma e'' mezzanotte.';

-- Ogni ora al minuto zero. La funzione filtra da se' l'ora italiana.
select cron.schedule(
  'simula-giornata-notturna',
  '0 * * * *',
  $cron$select private.simula_giornata_notturna();$cron$
);
