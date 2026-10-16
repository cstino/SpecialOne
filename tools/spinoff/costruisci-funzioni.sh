#!/bin/sh
# Porta le funzioni del repo (supabase/functions/*) nello stack Supabase del Mac (~/supabase-spinoff/project/volumes/functions).
# Il cloud le impacchetta da solo; l'ambiente self-hosted legge le cartelle cosi' come sono: quindi si copia anche engine/
# dentro la funzione che lo usa e si riscrivono gli import relativi (../../../engine/ -> ./engine/).
# Uso: sh tools/spinoff/costruisci-funzioni.sh   (dalla radice del repo), poi: sh run.sh restart functions
set -e
DEST="$HOME/supabase-spinoff/project/volumes/functions"
for f in simula-giornata invia-push collega-occhiali conferenza-stampa; do
  rm -rf "$DEST/$f"; mkdir -p "$DEST/$f"
  cp supabase/functions/$f/index.ts supabase/functions/$f/deno.json "$DEST/$f/"
  if grep -q "../../../engine/" "$DEST/$f/index.ts"; then
    cp -R engine "$DEST/$f/engine"; rm -rf "$DEST/$f/engine/_reference" 2>/dev/null || true
    sed -i '' "s#'\.\./\.\./\.\./engine/#'./engine/#g" "$DEST/$f/index.ts"
  fi
  echo "ok: $f"
done
