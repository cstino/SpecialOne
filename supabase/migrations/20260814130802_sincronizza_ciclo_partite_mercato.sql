-- ============================================================
--  CICLO DINAMICO: partita ogni 24 ore dall'evento effettivo
-- ============================================================
-- Il calendario conserva il primo calcio d'inizio programmato. Da quando una
-- giornata e' conclusa, il turno successivo viene ripianificato 24 ore dopo
-- l'ultima partita realmente registrata. Mercato e cron condividono quindi lo
-- stesso riferimento temporale, senza dipendere dal minuto in cui parte cron.

create or replace function private.pianifica_prossima_giornata()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_completata_il timestamptz;
  v_prossima_giornata smallint;
begin
  if new.stato <> 'simulata' or old.stato = 'simulata' then
    return new;
  end if;

  -- Si aspetta l'ultima partita della giornata: fino ad allora non si deve
  -- spostare il turno successivo.
  if exists (
    select 1 from public.fixtures f
    where f.league_id = new.league_id
      and f.giornata = new.giornata
      and f.stato <> 'simulata'
  ) then
    return new;
  end if;

  select max(m.simulata_il) into v_completata_il
  from public.matches m
  join public.fixtures f on f.id = m.fixture_id
  where f.league_id = new.league_id and f.giornata = new.giornata;

  select min(f.giornata) into v_prossima_giornata
  from public.fixtures f
  where f.league_id = new.league_id
    and f.giornata > new.giornata
    and f.stato = 'programmata';

  if v_completata_il is not null and v_prossima_giornata is not null then
    update public.fixtures
    set data_sim = v_completata_il + interval '24 hours'
    where league_id = new.league_id
      and giornata = v_prossima_giornata
      and stato = 'programmata';
  end if;

  return new;
end;
$$;

drop trigger if exists fixtures_pianifica_prossima_giornata on public.fixtures;
create trigger fixtures_pianifica_prossima_giornata
after update of stato on public.fixtures
for each row execute function private.pianifica_prossima_giornata();

revoke all on function private.pianifica_prossima_giornata() from public, anon, authenticated;

create or replace function private.mercato_aperto_lega(p_league_id bigint)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  with ciclo as (
    select
      (select max(m.simulata_il)
       from public.matches m
       join public.fixtures f on f.id = m.fixture_id
       where f.league_id = p_league_id) as ultima_partita_il,
      (select min(f.data_sim)
       from public.fixtures f
       where f.league_id = p_league_id and f.stato = 'programmata') as prossima_partita_il
  )
  select exists (
    select 1 from private.mercato_override_admin o
    where o.league_id = p_league_id
      and o.giorno = (now() at time zone 'Europe/Rome')::date
  ) or coalesce(
    (select now() >= ultima_partita_il + interval '30 minutes'
             and now() < prossima_partita_il - interval '2 hours'
     from ciclo
     where ultima_partita_il is not null and prossima_partita_il is not null),
    (now() at time zone 'Europe/Rome')::time >= time '23:30'
      or (now() at time zone 'Europe/Rome')::time < time '21:00'
  );
$$;

create or replace function private.simula_giornata_notturna()
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_chiave text;
  v_lega bigint;
  v_lanciate integer := 0;
begin
  select decrypted_secret into v_chiave
  from vault.decrypted_secrets
  where name = 'chiave_simulazione';

  if v_chiave is null then
    raise exception using errcode = '55000',
      message = 'Manca il segreto chiave_simulazione nel vault: il cron non puo'' autenticarsi.';
  end if;

  for v_lega in
    select l.id
    from public.leagues l
    where l.stato = 'stagione'
      and l.fase_carriera = 'normale'
      and exists (
        select 1 from public.fixtures f
        where f.league_id = l.id
          and f.stato = 'programmata'
          and f.data_sim <= now()
      )
    order by l.id
  loop
    perform net.http_post(
      url := 'https://hhvyyjpbsgjcaaaizgwb.supabase.co/functions/v1/simula-giornata',
      body := jsonb_build_object('league_id', v_lega),
      headers := jsonb_build_object('Content-Type', 'application/json', 'apikey', v_chiave),
      timeout_milliseconds := 120000
    );
    v_lanciate := v_lanciate + 1;
  end loop;
  return v_lanciate;
end;
$$;

revoke all on function private.simula_giornata_notturna() from public, anon, authenticated;

select cron.alter_job(jobid, schedule => '* * * * *')
from cron.job
where jobname = 'simula-giornata-notturna';
