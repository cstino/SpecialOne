#!/bin/sh
# Rifa la copia dei DATI del cloud sul Supabase del Mac (spinoff). NON tocca il cloud: legge soltanto.
# Uso: sh tools/spinoff/ricarica-dati.sh            (dalla radice del repo)
# Prerequisiti: stack avviato in ~/supabase-spinoff/project (sh run.sh start) e `npx supabase` collegato al progetto.
# Cancella e rifa SOLO i dati delle tabelle public/private della copia; schema, cron e utenti segnaposto restano.
set -e
DUMP="$HOME/supabase-spinoff/dump"
DB="supabase-db"
mkdir -p "$DUMP"
echo "1/4 esporto i dati dal cloud..."
npx supabase db dump --linked --data-only --use-copy --schema public,private -f "$DUMP/dati.sql"
echo "2/4 svuoto le tabelle della copia..."
docker exec "$DB" psql -U postgres -qtc "
do \$\$ declare r record; begin
  for r in select schemaname, tablename from pg_tables where schemaname in ('public','private') loop
    execute format('truncate table %I.%I restart identity cascade', r.schemaname, r.tablename);
  end loop; end \$\$;"
echo "3/4 carico i dati..."
docker exec -i "$DB" psql -U postgres -v ON_ERROR_STOP=0 -q < "$DUMP/dati.sql" > "$DUMP/dati.log" 2>&1 || true
echo "   errori: $(grep -c ERROR "$DUMP/dati.log" || true)"
echo "4/4 niente notifiche push dalla copia: svuoto le sottoscrizioni"
docker exec "$DB" psql -U postgres -qc "truncate public.push_subscriptions;"
echo "fatto."
