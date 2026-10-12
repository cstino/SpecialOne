#!/bin/sh
# Passaggio di SpecialOne dal Supabase cloud a quello sul Mac. Comandi, in ordine:
#   sh tools/spinoff/passaggio.sh stato           mostra dove siamo (cloud e Mac)
#   sh tools/spinoff/passaggio.sh congela         1) cloud chiuso all'app (congela.sql) + job del cloud spenti
#   sh tools/spinoff/passaggio.sh trasferisci     2) ultimo trasferimento dati + account + file e job del Mac accesi
#   sh tools/spinoff/passaggio.sh scongela        ROLLBACK: cloud riaperto (scongela.sql) e job del cloud accesi (i dati scritti sul Mac DOPO il passaggio non tornano)
# Dopo 'trasferisci': cambiare le variabili su Vercel (indirizzo e chiavi del Mac) e ripubblicare l'app.
set -e
CLOUD="npx supabase db query --linked --file"
MAC="docker exec -i supabase-db psql -U postgres -v ON_ERROR_STOP=0 -q"
DUMP="$HOME/supabase-spinoff/dump"
q() { printf '%s\n' "$1" > "$DUMP/q.sql"; $CLOUD "$DUMP/q.sql"; }
mkdir -p "$DUMP"

case "$1" in
stato)
  echo "== Mac"; docker exec supabase-db psql -U postgres -tAc "select 'job attivi: '||count(*) filter (where active)||' su '||count(*) from cron.job; select 'ultima giornata giocata Serie F: '||coalesce(max(f.giornata)::text,'-') from public.fixtures f join public.seasons s on s.id=f.season_id where f.league_id=63 and s.numero=2 and f.stato='simulata' and f.bracket_tie_id is null;"
  echo "== Cloud"; q "select 'job attivi: '||count(*) filter (where active)||' su '||count(*) as v from cron.job" | grep -E '"v"'
  q "select 'funzioni chiuse all''app: '||(not has_function_privilege('authenticated','public.capienza_squadra(bigint)','execute'))::text as v" | grep -E '"v"'
  ;;
congela)
  echo "Cloud: job spenti e funzioni chiuse all'app (congela.sql)..."
  q "select cron.alter_job(jobid, active := false) from cron.job" > /dev/null
  $CLOUD tools/spinoff/congela.sql > /dev/null
  echo "fatto: da ora l'app collegata al cloud riceve 'permission denied' e chi la ricarica passa al nuovo indirizzo."
  ;;
trasferisci)
  echo "1/6 esporto dati di gioco dal cloud..."
  npx supabase db dump --linked --data-only --use-copy --schema public,private -f "$DUMP/dati.sql"
  echo "2/6 esporto gli account (utenti e identita', senza sessioni)..."
  npx supabase db dump --linked --data-only --use-copy --schema auth \
    -x auth.sessions -x auth.refresh_tokens -x auth.audit_log_entries -x auth.flow_state -x auth.one_time_tokens \
    -x auth.mfa_amr_claims -x auth.mfa_challenges -x auth.mfa_factors -x auth.saml_relay_states -x auth.sso_domains \
    -x auth.sso_providers -x auth.saml_providers -x auth.schema_migrations -x auth.instances -f "$DUMP/auth.sql"
  echo "3/6 svuoto e carico il Mac..."
  docker exec supabase-db psql -U postgres -qtc "
    do \$\$ declare r record; begin
      for r in select schemaname, tablename from pg_tables where schemaname in ('public','private') loop
        execute format('truncate table %I.%I restart identity cascade', r.schemaname, r.tablename); end loop;
      delete from auth.identities; delete from auth.users; end \$\$;"
  $MAC < "$DUMP/dati.sql" > "$DUMP/dati.log" 2>&1 || true
  $MAC < "$DUMP/auth.sql" > "$DUMP/auth.log" 2>&1 || true
  docker exec supabase-db psql -U postgres -qc "truncate public.push_subscriptions;"
  echo "   errori dati: $(grep -c ERROR "$DUMP/dati.log" || true), errori account: $(grep -c ERROR "$DUMP/auth.log" || true)"
  echo "4/6 file nuovi dell'archivio..."
  q "select bucket_id, name, coalesce(metadata->>'mimetype','image/webp') mime from storage.objects order by 1,2" -o json > /dev/null 2>&1 || true
  echo "   (lanciare tools/spinoff/copia-archivio.mjs se ci sono stemmi nuovi)"
  echo "5/6 job del Mac accesi..."
  docker exec supabase-db psql -U postgres -qc "select cron.alter_job(jobid, active := true) from cron.job;" > /dev/null
  echo "6/6 controllo"
  docker exec supabase-db psql -U postgres -tAc "select 'utenti: '||count(*) from auth.users; select 'giocatori in rosa: '||count(*) from public.player_instances; select 'job attivi: '||count(*) filter (where active) from cron.job;"
  ;;
scongela)
  echo "ROLLBACK: cloud scrivibile e job del cloud accesi, job del Mac spenti."
  docker exec supabase-db psql -U postgres -qc "select cron.alter_job(jobid, active := false) from cron.job;" > /dev/null
  $CLOUD tools/spinoff/scongela.sql > /dev/null
  q "select cron.alter_job(jobid, active := true) from cron.job" > /dev/null
  echo "fatto. Ricordare di rimettere su Vercel l'indirizzo e la chiave del cloud e ripubblicare l'app."
  ;;
*) sed -n 2,9p "$0";;
esac
