# Importazione FC 26

Fonte: [FC 26 (FIFA 26) Player Data](https://www.kaggle.com/datasets/rovnez/fc-26-fifa-26-player-data),
snapshot 21 settembre 2025, licenza CC BY 4.0. I dati derivano da SoFIFA.

Il CSV non va committato: contiene dati e URL di terzi ed è escluso dal repository.
L'import seleziona i campionati tramite `league_id`, non tramite nome, per evitare collisioni
come Bundesliga tedesca/austriaca e Serie A italiana/ecuadoriana.

## Giocatori

```bash
curl -fL https://www.kaggle.com/api/v1/datasets/download/rovnez/fc-26-fifa-26-player-data \
  -o /tmp/fc26-player-data.zip
unzip -o /tmp/fc26-player-data.zip -d /tmp/fc26-player-data

python3 tools/importazione/normalizza.py \
  --input /tmp/fc26-player-data/FC26_20250921.csv \
  --output-dir /tmp/specialone-fc26-sql

for file_sql in /tmp/specialone-fc26-sql/players_*.sql; do
  npx --yes supabase@2.111.0 db query --linked --file "$file_sql"
done
```

L'upsert non modifica `foto_url`, quindi un reimport non cancella immagini già ospitate.

## Foto (opzionale, separato)

```bash
python3 -m venv /tmp/specialone-foto-venv
/tmp/specialone-foto-venv/bin/pip install -r tools/importazione/requirements-foto.txt

/tmp/specialone-foto-venv/bin/python tools/importazione/prepara_foto.py \
  --input /tmp/fc26-player-data/FC26_20250921.csv \
  --output-dir /tmp/specialone-foto

npx --yes supabase@2.111.0 storage cp --linked --recursive --jobs 8 \
  /tmp/specialone-foto/images ss:///player-photos/players

for file_sql in /tmp/specialone-foto/sql/foto_*.sql; do
  npx --yes supabase@2.111.0 db query --linked --file "$file_sql"
done
```

Le immagini vengono scaricate solo dallo script one-off, convertite in WebP 160×160 e
caricate nel bucket privato `player-photos`. Nel database resta il percorso Storage,
mai l'URL SoFIFA.
