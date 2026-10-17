-- Conferenze stampa: una partita al minuto (il cron passa da ogni 5 minuti a ogni minuto) e ripetizione PER SQUADRA.
-- Prima: a gruppi di 4 ogni 5 minuti, e una partita con le domande di una sola squadra non veniva piu' ripresa;
-- con 24 allenatori le quote al minuto dell'AI (Groq 8000 token/min, Gemini 429) saltavano e restavano buchi.
-- Riscritta dalla definizione viva.
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
      -- Basta che UNA squadra con un allenatore umano non abbia ancora le sue domande (ordine 1-2): se l'AI e'
      -- fallita per una sola squadra, si riprova solo per quella (genera salta chi ha gia' le domande).
      and exists (select 1 from public.teams t
                  where t.id in (f.home_team_id, f.away_team_id) and t.user_id is not null and not t.controllata_da_pc
                    and not exists (select 1 from public.conferenze_domande d where d.match_id = m.id and d.team_id = t.id and d.ordine < 3))
      -- Nuovo tentativo dopo 3 minuti (quote al minuto dell'AI), fino a 8 volte.
      and not exists (select 1 from private.conferenze_richieste r
                      where r.match_id = m.id and (r.richiesta_il > now() - interval '3 minutes' or r.tentativi >= 8))
    order by m.id
    limit 1
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
select cron.alter_job((select jobid from cron.job where jobname = 'conferenze-stampa'), schedule := '* * * * *');
commit;
