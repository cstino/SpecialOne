# Handoff — modifiche al motore per la Season 3

Scritto il 25 ottobre 2026 dalla sessione supervisore **"SpecialOne [d0b093]"** per una nuova chat di lavoro.
Tu sei la chat di lavoro: lavori per il committente (Cstino) e fai **sempre rapporto al supervisore**.

---

## 1. Chi comanda e come si fa rapporto

* Il **committente** decide. Il **supervisore** (la sessione "SpecialOne", id d0b093, su questo stesso Mac) controlla il
  tuo lavoro prima che arrivi in produzione.
* **Come fare rapporto.** Con lo strumento `SendMessage`, destinatario `SpecialOne` (se serve il nome completo:
  `SpecialOne [d0b093]`; `ListAgents` mostra le sessioni). In più, **ogni rapporto lo aggiungi anche in fondo a
  `docs/RAPPORTI-MOTORE-S3.md`**, con data e ora lette dall'orologio. Così resta traccia anche se il supervisore
  non è attivo in quel momento.
* **Quando fare rapporto:**
  1. appena hai letto tutto: cosa hai capito e il piano di lavoro, **prima di scrivere codice**;
  2. a ogni risultato di validazione, con i numeri veri copiati dall'output;
  3. **prima di qualsiasi cosa che tocchi la produzione** (migrazione, funzione sul server, push su main): chiedi l'ok
     al supervisore **e** al committente, e aspetta;
  4. quando il committente ti chiede altre cose: avvisa il supervisore di cosa ti ha chiesto.
* Il rapporto è breve: cosa hai fatto, i numeri, cosa resta, le domande aperte. Niente "dovrebbe funzionare": solo cose
  verificate. Se una prova fallisce lo scrivi.

## 2. Regole del progetto (non negoziabili)

Leggi per intero `CLAUDE.md` e poi `docs/STATO-PROGETTO.md`. In più, regole di lavoro con questo committente:

* **Rispondi sempre in italiano**, anche nel campo `description` dei comandi. Il committente non è un programmatore ma
  spedisce app da anni: spiega le scelte tecniche, non nascondere i compromessi.
* **Niente screenshot**: si verifica con numeri e misure; la grafica la guarda il committente.
* **Il motore è validato.** Procedura obbligatoria per ogni modifica (CLAUDE.md §4): descrivi, applica, lancia le suite,
  confronta, e se una metrica esce dal target **torna indietro**. Non riscrivere, non "modernizzare".
* **Lavora su un branch** (`feat/motore-s3`), mai direttamente su main. Push su main solo quando il committente lo dice
  (ogni push rifà il sito su Vercel: si raggruppano).
* **Database sul Mac** (non il cloud): migrazioni una per una con
  `docker exec -i supabase-db psql -U postgres -v ON_ERROR_STOP=1 -q < supabase/migrations/FILE.sql`. **Mai `db push`.**
  Una funzione SQL da riscrivere si riparte dalla definizione viva (`pg_get_functiondef`), non da memoria.
* **Edge function `simula-giornata`**: si pubblica copiando `supabase/functions/simula-giornata/index.ts` in
  `~/supabase-spinoff/project/volumes/functions/simula-giornata/index.ts` **sostituendo gli import**
  `'../../../engine/` con `'./engine/'`; i file del motore vanno copiati in
  `~/supabase-spinoff/project/volumes/functions/simula-giornata/engine/`. Poi `docker restart supabase-edge-functions`.
* **La giornata si simula alle 23:00 (Europe/Rome).** Mai pubblicare il motore fra le 22:30 e la fine della
  simulazione. **Rileggi l'orologio (`date`) nello stesso comando del riavvio** e riporta quell'ora: le sessioni
  durano ore e un orario letto prima è sbagliato.
* `npm run build` sempre (non basta `tsc --noEmit`).
* Le chiavi delle AI stanno solo in `~/supabase-spinoff/project/.env`: mai stamparle.

## 3. Cosa leggere per capire il motore

1. `docs/motore-validazione.md` — perché le formule sono quelle (non toccarle senza un motivo nuovo).
2. `docs/risultati-produzione.txt` — **il criterio di accettazione attuale** (`node tools/validazione/simulate-reale.js`).
3. `docs/risultati-fase0.txt` — storico (avviso in testa: non è più il criterio).
4. `docs/decisioni-tattiche.md` — il sistema tattico della Season 2 (ruoli, compiti, morale, familiarità): le modifiche
   non devono cancellarne gli effetti misurati (rilancia anche `tools/validazione/simulate-tattiche.js`).
5. Codice: `engine/engine.js`, `engine/config.js`, `engine/random.js`, gli altri `engine/*.js`,
   `supabase/functions/simula-giornata/index.ts`.

## 4. L'analisi da cui si parte (fatta il 25/10/2026 sulle partite vere)

Partite col motore attuale: **Serie F stagione 2** (216) e **LegaBot stagione 5** (184). Le stagioni prima della
ritaratura del 9 settembre non fanno testo.

**Funziona (non va peggiorato):**

| Indicatore | Serie F S2 | LegaBot S5 | Target attuale |
|---|---|---|---|
| Gol a partita | 2,93 | 3,01 | 2,50–2,90 |
| Tiri per squadra | 13,3 | 12,7 | 11–14 |
| Pareggi | 25,0% | 22,8% | 23–27% |
| Vittorie casa | 44,0% | 43,5% | 43–47% |

Gialli 3,6 e rossi 0,16 a partita, gol su palla ferma 31%, capocannoniere 0,67 gol a partita, punti del primo ~2,2 e
dell'ultimo ~0,5 a partita: tutto plausibile. **Forza contro risultato** a fasce di 1 punto di overall medio dei titolari:
in linea con la curva TEST 2 entro il rumore (0–1 punti: 39,8/24,8/35,3 contro 39,8/27,5/32,7 atteso).

**Difetto 1 — troppa varianza.** Anche fra squadre con meno di 4 punti di divario (335 partite), media 2,88 gol ma:

| | Motore | Calcio vero (circa) |
|---|---|---|
| 0-0 | 10,7% | 7–8% |
| partite con 1–2 gol | 35,8% | ~43% |
| partite con 5+ gol | 19,4% | ~12% |
| vittorie con 4+ gol di scarto | 11,3% | ~4% |
| deviazione standard dei gol totali | 1,94 | ~1,65 (Poisson con media 2,7) |

**Difetto 2 — i gol hanno lo stesso ritmo per 90 minuti.** Fasce di 15': motore 18,4 / 15,9 / 17,5 / 16,7 / 14,6 / 16,9%;
calcio vero circa 13 / 15 / 18 / 16 / 17 / 22% (si segna di più nel finale, meno all'inizio).

Limite della misura: si è usato l'overall *di oggi* dei giocatori, non quello del giorno della partita.

Per rifare le misure, partire dalle query sul database: `matches` (gol_home/gol_away, `stats_squadra` con i tiri,
`blocchi` = eventi con `tipo` 'gol'/'cartellino'/'infortunio' e `minuto`, `titolari_home/away`), `fixtures`
(`bracket_tie_id` null = stagione regolare), `seasons` (`numero`), `leagues` (Serie F = 63, LegaBot = 62).

## 5. Le modifiche da fare (per l'inizio della Season 3)

1. **Ridurre la varianza fra partite** senza spostare la media: meno 0-0 e meno goleade, più partite da 1–3 gol.
   Prima di toccare qualcosa capisci **da dove nasce** la sovradispersione (variabilità del controllo/possesso fra
   partite? forma esponenziale dell'xG con differenziali dispersi? blocchi indipendenti che si sommano?) e porta al
   supervisore la diagnosi con i numeri, **non una soluzione a tentativi**.
2. **Profilo temporale dei gol**: un po' meno gol nei primi minuti e più nell'ultima mezz'ora (stanchezza, chi è sotto
   che si sbilancia), lasciando invariato il totale.

**Target nuovi da aggiungere a `simulate-reale.js`** (in condizioni di produzione), oltre ai quattro attuali e alla
curva TEST 2 che devono restare dentro:
* 0-0 fra 6% e 9%; partite con 1–2 gol fra 39% e 46%; 5+ gol fra 9% e 14%; scarto ≥ 4 gol fra 3% e 6%
  (fra squadre di forza simile);
* gol negli ultimi 15' fra 20% e 24% del totale; nei primi 15' fra 11% e 15%.

Se un target nuovo è incompatibile con quelli vecchi, **non forzare**: riporta al supervisore e al committente.

**Facoltativo, da proporre:** salvare in `matches` la forza delle due squadre al momento della partita
(es. `ovr_home`, `ovr_away`), così le analisi future sono esatte. Non tocca il motore.

## 6. Tempi

* Ora: studio, diagnosi, prototipo sul branch, validazione. Niente in produzione.
* Stagione regolare della Serie F fino al 28/10, poi playoff (giornate 23–29, inizio novembre), poi off-season.
* **Pubblicazione: all'inizio della Season 3**, quando il committente lo dice, dopo l'ok del supervisore, mai a
  ridosso delle 23:00.
* Il committente ti darà anche altre richieste: falle con le stesse regole e avvisa il supervisore.
