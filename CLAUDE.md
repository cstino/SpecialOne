# CLAUDE.md

Contesto per l'agent. Leggi questo file per intero prima di scrivere codice.
Vale anche per Codex: se usi Codex, copia questo file anche come `AGENTS.md`.

---

## 1. Cos'è questo progetto

Gioco manageriale calcistico multiplayer a turni, per un gruppo chiuso di amici (6-10 persone).
Non è un prodotto commerciale, non ci sono utenti esterni, non c'è monetizzazione.

**Il ciclo di gioco**: un admin crea una lega, i partecipanti entrano con un codice invito,
ognuno fa un draft casuale per costruire una rosa da 25 giocatori entro un tetto ingaggi,
poi schiera la formazione. Ogni notte alle 00:00 il sistema simula **una** giornata di campionato.
Di giorno c'è una finestra di mercato in cui i partecipanti si scambiano giocatori e fanno
aste a busta chiusa sugli svincolati. A fine stagione i giocatori invecchiano, crescono o
declinano, e i contratti vanno rinnovati.

Il riferimento estetico e di ritmo è il gioco virale "38-0", ma con carriera multiplayer.

---

## 2. Stack

| Livello | Scelta | Nota |
|---|---|---|
| Frontend | React + Vite + TypeScript | PWA, mobile-first |
| Backend/DB | Supabase (Postgres + Auth + Storage + Realtime) | |
| Hosting | Vercel | |
| Job schedulati | Supabase `pg_cron` → Edge Function via `pg_net` | **non** Vercel Cron |
| Motore di simulazione | modulo isolato, zero dipendenze | vedi sezione 4 |

**Perché pg_cron e non Vercel Cron**: la simulazione notturna deve leggere e scrivere molto
sul DB e non ha vincoli di latenza. Farla girare vicino al database evita timeout delle
serverless function e round-trip inutili. Il piano gratuito Vercel ha inoltre limiti stretti
sui cron.

**Fuso orario**: tutti i cron, le deadline e i confronti di data usano `Europe/Rome`
esplicito. Mai UTC, mai il fuso del server. È un requisito, non una preferenza.

---

## 3. Documenti di riferimento

Leggili quando servono. Non serve leggerli tutti per ogni task.

| File | Contenuto | Quando leggerlo |
|---|---|---|
| `docs/design.md` | Specifica completa del gioco: economia, draft, mercato, contratti, progressione, schema DB, roadmap | Prima di implementare qualsiasi meccanica di gioco |
| `docs/motore-validazione.md` | Report della Fase 0: risultati, formule corrette, cosa non ha funzionato e perché | Prima di toccare il motore. Anche solo per capire perché le formule sono quelle |
| `docs/risultati-fase0.txt` | Output grezzo dell'ultima validazione | Confronto numerico dopo modifiche al motore |
| `docs/decisioni-fase1.md` | Decisioni prese dopo la prima review. **Vincolante, e più recente del design doc** | Sempre, prima di iniziare un task |

**Gerarchia in caso di discrepanza**: `docs/decisioni-fase1.md` > codice del motore >
`docs/design.md`. Il design doc è stato scritto prima della validazione e corretto dopo;
potrebbe essere rimasto qualche residuo. Per i numeri della validazione, la verità è
`docs/risultati-fase0.txt`.


---

## 4. Il motore è validato. Non riscriverlo.

`engine/` contiene un motore di simulazione partita già scritto, tarato e verificato su
10.000 partite e 500 stagioni simulate. Tutti e 13 i target statistici rientrano.

```
engine/config.js              costanti, moduli, pesi slot, compatibilità ruoli
engine/random.js              RNG seeded, gauss, poisson, estrazione pesata
engine/engine.js              overall efficace, linee, profilo strutturale, xG, gol,
                              statistiche individuali, sostituzioni, calendario
tools/validazione/roster.js   generazione rose sintetiche — SOLO test
tools/validazione/simulate.js suite di validazione — SOLO test
```

`engine/` non importa nulla da `tools/`. La dipendenza è a senso unico:
`tools/validazione` → `engine`. Non invertirla mai.

### Regole vincolanti

1. **Non modificare le formule** in `engine.js`. In particolare: la forma esponenziale
   dell'xG, il modello strutturale dei moduli, il calcolo del controllo. Sono state
   ottenute per iterazione dopo che le versioni precedenti avevano fallito la validazione.
   Se una formula ti sembra strana, il motivo è documentato in `docs/motore-validazione.md`.

2. **Non cambiare le costanti** in `config.js` senza rilanciare la suite e confrontare
   i numeri con `docs/risultati-fase0.txt`. Una costante spostata "per migliorare il
   realismo" può far saltare cinque metriche a valle.

3. **Non "modernizzare" il codice.** Niente refactor in classi, niente astrazioni,
   niente dependency injection. È volutamente procedurale e leggibile perché deve
   restare confrontabile con la versione validata.

4. **Se serve una modifica al motore**, procedi così e non altrimenti:
   - descrivi il cambiamento e il motivo
   - applicalo
   - lancia `node tools/validazione/simulate.js`
   - confronta l'output con `docs/risultati-fase0.txt`
   - se una qualsiasi metrica esce dal target, **torna indietro**

### Porting a TypeScript

Il motore è in JavaScript ESM. Se lo porti a TypeScript:

- **non cambiare nessun numero, nessuna formula, nessun ordine di operazioni** —
  solo annotazioni di tipo
- sostituisci l'RNG seeded di `roster.js` con uno normale (o mantienilo seeded:
  avere partite riproducibili da un seed è utile per il debug e per contestare i risultati)
- **dopo il porting, rilancia la suite di validazione sulla versione TypeScript** e
  verifica che i numeri coincidano con `docs/risultati-fase0.txt` entro il rumore statistico
- tieni la versione `.js` originale in `engine/_reference/` come riferimento congelato

Il porting non è urgente. Il motore funziona in JS e può restare in JS a lungo.

---

## 5. Stato attuale e task corrente

**Fatto**: Fase 0 — motore di simulazione validato.

**Da fare adesso**: Fase 1 — lega giocabile con una singola stagione.

### Scope della Fase 1 — cosa includere

- Autenticazione (Supabase Auth)
- Creazione lega da parte dell'admin, con le impostazioni della sezione 3.1 del design doc
- Codice invito e ingresso partecipanti
- Registrazione squadra: nome + stemma (galleria prefatta o upload su Supabase Storage)
- Import del dataset giocatori (FC 26, 10 campionati) in Postgres
- Draft: spin casuale del club, selezione giocatore, reroll, unicità globale,
  tetto ingaggi all'80% del budget, vincolo di solvibilità, ordine a serpentina
- Schieramento formazione: 7 moduli, titolari + panchina + tribuna, penalità fuori ruolo
- Generazione calendario (metodo del cerchio, gestione squadre dispari con turni di riposo)
- Cron notturno che simula **una** giornata (vedi `docs/decisioni-fase1.md` §7)
- Anteprima della durata stagione nella creazione lega: con una giornata per turno,
  `P = (N − 1) × G` è anche il numero di giorni reali
- Classifica con i criteri corretti (punti → scontri diretti → differenza reti → gol fatti)
- Pagina partita con tabellino e statistiche individuali
- Formazione automatica di fallback se il partecipante non schiera entro le 23:00

### Scope della Fase 1 — cosa NON includere

Niente mercato. Niente contratti. Niente rinnovi. Niente stamina o infortuni.
Niente progressione o declino dei giocatori. Niente seconda stagione. Niente giocatori
generati. Niente premi economici.

> **Eccezione**: la familiarità coi moduli (`formation_xp`) è **dentro** la Fase 1.
> Il design doc la colloca in Fase 2 ma è sbagliato — vedi `docs/decisioni-fase1.md` §2.

**Non anticipare le fasi successive** anche se il codice sembra "quasi pronto" per farlo.
L'obiettivo della Fase 1 è avere qualcosa di giocabile in fretta e capire se il gioco
diverte, prima di investire nel resto.

Il motore in `engine/` contiene già stamina, infortuni e sostituzioni automatiche: in
Fase 1 chiamalo con `{ usaCondizione: false }`. Non rimuovere quel codice.

---

## 6. Convenzioni

- **Lingua**: interfaccia in italiano. Nomi di variabili, funzioni e tabelle in italiano
  o inglese purché coerenti nel file. Commenti in italiano.
- **Migrazioni**: ogni modifica allo schema è un file in `supabase/migrations/`,
  mai una modifica manuale dalla dashboard.
- **Row Level Security attiva su tutte le tabelle.** Un partecipante non deve poter
  leggere le formazioni altrui prima che la giornata sia simulata, né le offerte a
  busta chiusa prima della rivelazione. Questo è il requisito di sicurezza principale
  del progetto: non è un'app pubblica, ma i partecipanti hanno tutto l'interesse a barare.
- **Registro append-only** dei movimenti economici nella tabella `transactions`.
  Non è opzionale: senza, il primo bug di budget è impossibile da diagnosticare.
- **Mobile-first.** I partecipanti giocheranno dal telefono. Ogni schermata va pensata
  prima per il telefono.
- **Niente localStorage per lo stato di gioco.** Tutto su Supabase, la sessione può
  cambiare dispositivo.

---

## 7. Trappole note

Cose che sono già state analizzate. Non riaprirle senza un motivo nuovo.

- **Il draft può andare in deadlock.** Se un partecipante riempie 22 slot su 25 senza
  portieri e resta senza budget, non può finire. Il vincolo di solvibilità (design doc 4.4)
  serve esattamente a questo, e va implementato **prima** del draft, non dopo.
- **Se il club estratto non ha nessun giocatore ingaggiabile**, lo spin si ripete
  automaticamente senza consumare un reroll. Senza questa regola la sfortuna blocca il draft.
- **L'economia si rompe se i premi partita sono valori assoluti.** Il numero di partite
  dipende dalle impostazioni dell'admin. I premi vanno normalizzati come frazione del budget
  diviso il numero di partite (design doc 5.2).
- **I 100M€ iniziali sono una dotazione una tantum, non ricorrente.** Se li ricarichi
  ogni stagione, il denaro smette di essere una risorsa entro la stagione 3.
- **La condizione media della rosa è una metrica inutile** (14 giocatori su 25 non giocano
  mai). Se devi mostrare un indicatore di freschezza, usa la media degli 11 migliori.
- **Il fuso orario.** Vedi sezione 2. Ci si inciampa solo al cambio dell'ora legale,
  cioè nel momento peggiore.

---

## 8. Come lavorare

- Un task alla volta. Se la richiesta ne contiene più d'uno, elencali e chiedi da quale
  partire invece di farli tutti.
- Prima di implementare una meccanica di gioco, cita la sezione del design doc che stai
  seguendo. Se la specifica è ambigua o incompleta, **chiedi** invece di inventare:
  quasi tutte le decisioni sono già state prese, probabilmente la risposta esiste.
- Se pensi che una regola del design doc sia sbagliata, dillo esplicitamente prima di
  implementarla diversamente. Non cambiarla in silenzio.
- Il committente non ha formazione formale in programmazione ma spedisce applicazioni in
  produzione da tempo. Spiega le decisioni tecniche, non darle per scontate, e non nascondere
  i compromessi.
