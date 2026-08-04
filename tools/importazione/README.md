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

### Pool élite globale

Per aggiungere gli esterni da `overall >= 75` e i giovani under 22 con overall
`67–74` dei campionati non presenti nel pool base, usa lo stesso CSV con l'opzione
seguente. I giovani vengono presi solo dalle leghe esterne che hanno già almeno un
giocatore da 75+. Tutti conservano il campionato reale ma diventano disponibili in
ogni lega.

```bash
python3 tools/importazione/normalizza.py \
  --input /tmp/fc26-player-data/FC26_20250921.csv \
  --output-dir /tmp/specialone-fc26-elite-sql \
  --elite-globale
```

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

## Foto senza il CSV Kaggle

Quando il dataset sorgente non è più a portata di mano, `scarica_foto.py` ricostruisce
l'URL del CDN dall'`fc_id`, che è già in `public.players`. Il sorgente è la variante a
240px ridotta a 160, così si ritaglia verso il basso invece di ingrandire un 120px.

```bash
npx --yes supabase@2.111.0 db query --linked --experimental \
  "select fc_id from public.players order by fc_id;" > /tmp/ids.json

/tmp/specialone-foto-venv/bin/python tools/importazione/scarica_foto.py \
  --ids /tmp/ids.json --output-dir /tmp/specialone-foto
```

Accetta sia l'output JSON di `db query` sia un id per riga, ed è ripetibile: i file già
presenti vengono saltati, quindi si può rilanciare dopo un'interruzione.

### Upload: due trappole della CLI su Windows

1. **Percorsi con lettera di unità non funzionano.** `C:/…` viene interpretato come schema
   URI e il comando fallisce con `LegacyStorageUnsupportedOperationError`. Bisogna entrare
   nella cartella e usare un percorso relativo.
2. **La cartella sorgente diventa la cartella di destinazione.** `cp -r ./players
   ss:///player-photos` scrive in `player-photos/players/…`. Se la cartella locale si
   chiama `images`, i file finiscono in `players/images/…` e i percorsi in `foto_url`
   non corrispondono più.

```bash
cd /tmp/specialone-foto            # la cartella locale deve chiamarsi "players"
npx --yes supabase@2.111.0 storage cp -r ./players ss:///player-photos \
  --linked --experimental --jobs 8

for file_sql in /tmp/specialone-foto/sql/foto_*.sql; do
  npx --yes supabase@2.111.0 db query --linked --experimental --file "$file_sql"
done
```

I giocatori senza ritratto sul CDN restano con `foto_url` nullo e l'app mostra l'avatar
anonimo: è il comportamento previsto, non un errore da correggere.
