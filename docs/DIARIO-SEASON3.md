# Diario della Season 3

Le funzionalità e le modifiche che il committente vuole per la **Season 3**. Le tiene la sessione supervisore: ogni
richiesta si annota qui con data, stato e decisioni prese, così resta traccia fra una conversazione e l'altra.

**Stati:** `da valutare` (appena chiesta) · `deciso` (regole fissate col committente) · `in lavoro` · `pronto` (fatto e
provato, in attesa di pubblicazione) · `pubblicato` · `scartato`.

**Calendario:** la Season 2 della Serie F chiude la stagione regolare il 28/10/2026, poi playoff (giornate 23–29), poi
**off-season 3**. Quello che è `pronto` si pubblica a inizio off-season, salvo indicazioni diverse.

---

## 1. Motore di simulazione: meno goleade, più gol nel finale, più peso alla forza

* **Stato:** `pronto` — da pubblicare **all'inizio dell'off-season 3** (deciso il 25/10/2026).
* **Chi:** chat di lavoro "motore S3" (specialone-6a), supervisionata. Branch `feat/motore-s3`, worktree
  `/Users/cristianobraccili/SpecialOne-motore-s3`. Dettagli in `docs/HANDOFF-MOTORE-SEASON3.md` e
  `docs/RAPPORTI-MOTORE-S3.md` (nella worktree); procedura in `docs/PUBBLICAZIONE-MOTORE-S3.md`.
* **Decisioni (25/10/2026):**
  * "stato della partita": chi è in vantaggio rallenta, sempre di più verso la fine; gol più probabili nel finale;
  * livello **L2**: il centrocampo pesa di più nel controllo della partita (AMPLIFICA_CONTROLLO 2,2), bonus casa di
    centrocampo ricalibrato (1,3), pubblico senza compensazioni;
  * gol a partita **invariati (~2,9)**; ritmo degli stili invariato, soglia TEST B alzata a **1,9**;
  * **economia invariata** (il tetto ingaggi resta com'è, anche se è la leva più forte per allargare le distanze);
  * niente motore azione per azione: si migliora quello attuale.
* **Effetti misurati:** varianza dei gol da 1,16 a 1,06, vittorie con 4+ gol di scarto da 7,2% a 4,4%, gol negli ultimi
  15' da 16,7% a 21,1%, favorito a 2/4/8 punti di vantaggio da 52/66/85 a 53/68/88 su 100; tattiche e pubblico invariati.

---

<!-- Nuove richieste qui sotto: "## N. Titolo", poi Stato, Richiesta (parole del committente), Decisioni, Note. -->
