#!/bin/sh
# Backup giornaliero del database di SpecialOne sul Mac: dati di gioco, account e schema, compressi.
# Copia locale in ~/Backups/specialone e copia FUORI CASA in iCloud Drive (se disponibile). Tiene gli ultimi 14 giorni.
# Pianificato da ~/Library/LaunchAgents/com.specialone.backup.plist (ogni giorno alle 05:00).
set -e
DATA=$(date +%Y%m%d-%H%M)
LOCALE="$HOME/Backups/specialone"
ICLOUD="$HOME/Library/Mobile Documents/com~apple~CloudDocs/SpecialOne-backup"
mkdir -p "$LOCALE"
FILE="$LOCALE/specialone-$DATA.sql.gz"
docker exec supabase-db pg_dump -U postgres --no-owner --no-privileges -n public -n private -n auth -n storage -n vault postgres | gzip > "$FILE"
SIZE=$(stat -f %z "$FILE")
[ "$SIZE" -gt 100000 ] || { echo "backup sospetto (troppo piccolo: $SIZE byte)"; exit 1; }
if [ -d "$HOME/Library/Mobile Documents/com~apple~CloudDocs" ]; then
  mkdir -p "$ICLOUD"; cp "$FILE" "$ICLOUD/"
  ls -1t "$ICLOUD"/specialone-*.sql.gz 2>/dev/null | tail -n +15 | xargs -I{} rm -f "{}"
fi
ls -1t "$LOCALE"/specialone-*.sql.gz | tail -n +15 | xargs -I{} rm -f "{}"
echo "backup ok: $FILE ($SIZE byte)"
