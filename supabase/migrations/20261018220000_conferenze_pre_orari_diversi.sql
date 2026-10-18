-- Domande pre partita: orari diversi (13:00-18:00 a scatti di 5 minuti, per partita) invece di tutte alle 16:00.
begin;
create or replace function private.lancia_conferenze_pre()
returns integer language plpgsql security definer set search_path = '' as $f$
declare
  v_chiave text;
  v_fx bigint;
  v_lanciate integer := 0;
begin
  select decrypted_secret into v_chiave from vault.decrypted_secrets where name = 'chiave_simulazione';
  if v_chiave is null then return 0; end if;

  for v_fx in
    select f.id
    from public.fixtures f
    join public.leagues l on l.id = f.league_id and l.conferenze_stampa and l.stato = 'stagione' and l.fase_carriera = 'normale'
    where f.stato = 'programmata'
      -- Orario della domanda: per ogni partita un momento fisso tra 10 e 5 ore prima della simulazione
      -- (13:00-18:00 per le 23:00), a scatti di 5 minuti, cosi' i giornalisti arrivano a orari diversi.
      and f.data_sim - interval '10 hours' + (abs(hashtext('pre' || f.id::text)) % 61) * interval '5 minutes' <= now()
      and f.data_sim > now() + interval '30 minutes'
      and exists (select 1 from public.teams t
                  where t.id in (f.home_team_id, f.away_team_id) and t.user_id is not null and not t.controllata_da_pc
                    and not exists (select 1 from public.conferenze_domande d where d.fixture_id = f.id and d.team_id = t.id))
      and not exists (select 1 from private.conferenze_pre_richieste r
                      where r.fixture_id = f.id and (r.richiesta_il > now() - interval '3 minutes' or r.tentativi >= 8))
    order by f.id
    limit 1
  loop
    insert into private.conferenze_pre_richieste (fixture_id) values (v_fx)
    on conflict (fixture_id) do update set richiesta_il = now(), tentativi = private.conferenze_pre_richieste.tentativi + 1;
    perform net.http_post(
      url := 'http://api-gw:8000/functions/v1/conferenza-stampa',
      body := jsonb_build_object('azione', 'genera_pre', 'fixture_id', v_fx),
      headers := jsonb_build_object('Content-Type', 'application/json', 'apikey', v_chiave),
      timeout_milliseconds := 60000
    );
    v_lanciate := v_lanciate + 1;
  end loop;
  return v_lanciate;
end $f$;

commit;
