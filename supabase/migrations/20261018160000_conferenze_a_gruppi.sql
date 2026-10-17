-- Le conferenze si lanciano a gruppi di 4 partite ogni 5 minuti (prima 10): con 24 allenatori non si chiede all'AI
-- tutto insieme e le quote al minuto reggono. Riscritta dalla definizione viva.
begin;
CREATE OR REPLACE FUNCTION private.lancia_conferenze_stampa()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_chiave text;
  v_match bigint;
  v_lanciate integer := 0;
begin
  select decrypted_secret into v_chiave from vault.decrypted_secrets where name = 'chiave_simulazione';
  if v_chiave is null then return 0; end if;

  for v_match in
    select m.id
    from public.matches m
    join public.fixtures f on f.id = m.fixture_id
    join public.leagues l on l.id = f.league_id and l.conferenze_stampa
    where m.simulata_il > now() - interval '20 hours'
      and exists (select 1 from public.teams t
                  where t.id in (f.home_team_id, f.away_team_id) and t.user_id is not null and not t.controllata_da_pc)
      and not exists (select 1 from public.conferenze_domande d where d.match_id = m.id)
      and not exists (select 1 from private.conferenze_richieste r
                      where r.match_id = m.id and (r.richiesta_il > now() - interval '30 minutes' or r.tentativi >= 3))
    order by m.id
    limit 4
  loop
    insert into private.conferenze_richieste (match_id) values (v_match)
    on conflict (match_id) do update set richiesta_il = now(), tentativi = private.conferenze_richieste.tentativi + 1;
    perform net.http_post(
      url := 'http://api-gw:8000/functions/v1/conferenza-stampa',
      body := jsonb_build_object('azione', 'genera', 'match_id', v_match),
      headers := jsonb_build_object('Content-Type', 'application/json', 'apikey', v_chiave),
      timeout_milliseconds := 60000
    );
    v_lanciate := v_lanciate + 1;
  end loop;
  return v_lanciate;
end;
$function$;
commit;
