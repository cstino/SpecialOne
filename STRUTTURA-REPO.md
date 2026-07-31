# Struttura del repo

```
specialone/
├── CLAUDE.md                      handoff per l'agent
├── AGENTS.md                      copia identica, la legge Codex
├── package.json
│
├── docs/
│   ├── design.md                  specifica completa del gioco (v1.1)
│   ├── motore-validazione.md      report Fase 0: formule, risultati, correzioni
│   └── risultati-fase0.txt        BASELINE del test di regressione — non cancellare
│
├── engine/                        PRODUZIONE — va nel bundle
│   ├── config.js
│   ├── random.js
│   └── engine.js
│
├── tools/validazione/             TEST — non va nel bundle
│   ├── roster.js
│   ├── simulate.js
│   └── package.json
│
├── src/                           React + Vite (da creare)
└── supabase/
    ├── migrations/
    └── functions/simula-giornate/
```

## Regola di dipendenza

`tools/validazione` importa da `engine`. **Mai il contrario.**
Se un file in `engine/` importa qualcosa da `tools/`, è un bug: significa che
codice di test finirebbe nel bundle di produzione.

## Test di regressione

L'unico test che esiste al momento. Va lanciato ogni volta che qualcuno tocca `engine/`.

```bash
cd tools/validazione
node simulate.js > /tmp/nuovo.txt
diff /tmp/nuovo.txt ../../docs/risultati-fase0.txt
```

Output atteso: nessuna differenza. Il seed è fisso, quindi i numeri sono deterministici —
qualsiasi riga di diff significa che il comportamento del motore è cambiato.

Se il cambiamento è voluto e tutti i 13 target restano verdi, rigenera la baseline:

```bash
node simulate.js > ../../docs/risultati-fase0.txt
```

Se anche un solo target esce dal range, **torna indietro**.

## Verifica rapida

```bash
cd tools/validazione && node simulate.js | grep -c " OK $"
```

Deve stampare `13`.

## Primo prompt all'agent

Non chiedergli di costruire la Fase 1 in blocco. Apri con una verifica di contesto:

> Leggi CLAUDE.md e dimmi cosa hai capito del progetto e da dove proponi di partire.

Se la risposta cita mercato, contratti o progressione dei giocatori, non ha letto la
sezione 5 e la Fase 1 partirà già fuori scope.

Poi un task alla volta, in quest'ordine:

1. schema Supabase + migrazioni + RLS
2. import del dataset FC 26
3. auth + creazione lega + codice invito + registrazione squadra
4. draft
5. schieramento formazione
6. calendario + cron + pagina partita
7. classifica
