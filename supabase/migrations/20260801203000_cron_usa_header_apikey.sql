-- ============================================================
--  CORREZIONE: la chiave del cron va nell'header `apikey`
--
--  @supabase/server, in modalita' `secret`, legge `request.headers.apikey` e
--  la confronta con la mappa delle chiavi segrete. Un `Authorization: Bearer`
--  non viene nemmeno guardato da quel ramo, e la chiamata finiva in 401.
--
--  Nota sulla stessa mappa: `createAdminClient` usa la voce `default` di
--  quella mappa come chiave del progetto. Quindi il segreto che il cron
--  presenta e la chiave con cui la funzione parla al database sono lo stesso
--  valore: metterci un segreto inventato fa fallire ogni query della funzione.
--
--  Trovato provando la catena a mano prima di affidarla al cron.
-- ============================================================

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
  -- Il job gira ogni ora: qui si decide se e' l'ora giusta a Roma, cosi' il
  -- cambio dell'ora legale non sposta ne' duplica la simulazione.
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
    perform net.http_post(
      url     := 'https://hhvyyjpbsgjcaaaizgwb.supabase.co/functions/v1/simula-giornata',
      body    := jsonb_build_object('league_id', v_lega),
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'apikey', v_chiave
      ),
      timeout_milliseconds := 120000
    );
    v_lanciate := v_lanciate + 1;
  end loop;

  return v_lanciate;
end;
$$;

revoke all on function private.simula_giornata_notturna() from public, anon, authenticated;
