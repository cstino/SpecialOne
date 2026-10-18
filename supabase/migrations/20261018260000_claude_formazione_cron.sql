-- Formazione automatica di Atletico Neurale: un'ora e mezza prima della simulazione (21:30 per le 23:00), una volta per
-- giornata (il registro azioni_claude ricorda l'ultima giornata compilata).
begin;

create or replace function private.lancia_formazione_claude()
returns integer language plpgsql security definer set search_path = '' as $f$
declare
  v_chiave text;
  v_t record;
  v_n integer := 0;
begin
  select decrypted_secret into v_chiave from vault.decrypted_secrets where name = 'chiave_simulazione';
  if v_chiave is null then return 0; end if;

  for v_t in
    select t.id as team_id, t.league_id, f.giornata
    from public.teams t
    join public.leagues l on l.id = t.league_id and l.stato = 'stagione' and l.fase_carriera = 'normale'
    join lateral (select f.giornata, f.data_sim from public.fixtures f
                   where f.league_id = t.league_id and f.stato = 'programmata' and t.id in (f.home_team_id, f.away_team_id)
                   order by f.giornata limit 1) f on true
    where t.gestita_da_claude and f.data_sim - interval '90 minutes' <= now() and f.data_sim > now()
      and not exists (select 1 from public.azioni_claude a
                       where a.team_id = t.id and a.tipo = 'formazione' and (a.dettaglio->>'giornata')::int = f.giornata)
  loop
    perform net.http_post(
      url := 'http://api-gw:8000/functions/v1/simula-giornata',
      body := jsonb_build_object('azione', 'formazione_claude', 'league_id', v_t.league_id, 'team_id', v_t.team_id),
      headers := jsonb_build_object('Content-Type', 'application/json', 'apikey', v_chiave),
      timeout_milliseconds := 90000
    );
    v_n := v_n + 1;
  end loop;
  return v_n;
end $f$;

select cron.schedule('claude-formazione', '*/10 * * * *', 'select private.lancia_formazione_claude();');

commit;
