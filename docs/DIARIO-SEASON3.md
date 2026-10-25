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

## 2. Morale e tifosi a metà a inizio stagione; soglia dei titolari al 65%

* **Stato:** `deciso` (25/10/2026) — da preparare prima dell'off-season 3.
* **Richiesta:** «Dal prossimo anno ogni squadra parte con il morale rosa e tifosi a metà. I titolari devono avere come
  soglia di gioco il 65% al posto del 55%.»
* **Decisioni:**
  * **morale di tutti i giocatori a 50 e pubblico di tutte le squadre a 50 all'inizio di OGNI nuova stagione**, in
    **tutte le leghe** (la prima volta all'inizio della Season 3). Oggi non si azzerano mai (Serie F: morale medio 79,
    pubblico 91);
  * **soglia minima del "Titolare fisso" dal 55% al 65%** dei minuti, **per tutti** dalla Season 3, anche per le promesse
    già scritte nei contratti in corso. La soglia "rossa" (quando il giocatore si lamenta) segue: 70% della soglia,
    quindi dal 38,5% al 45,5%. La quota attesa dal morale resta 75%.
* **Note per farlo:**
  * l'azzeramento va fatto quando parte la nuova stagione (chiusura dell'off-season), non all'inizio dell'off-season:
    durante l'off-season il morale serve ancora ai rinnovi. Da confermare col committente quando si implementa;
  * con il pubblico a 50 il moltiplicatore del fattore campo parte da (50-10)/70 ≈ 0,57: a inizio stagione il vantaggio
    di giocare in casa è più basso e cresce con risultati e conferenze;
  * la soglia sta in due posti da tenere allineati: SQL `private.soglia_minutaggio` (e `controlla_minutaggio`) e
    `src/lib/minutaggio.ts` (`GRADINI_MINUTAGGIO`); poi `docs/decisioni-minutaggio.md` §6.

---

## 3. Cambio di ruolo più rapido verso un ruolo secondario

* **Stato:** `deciso` (25/10/2026) — da preparare prima dell'off-season 3.
* **Richiesta:** «Alcuni giocatori hanno ruoli secondari, tipo Quiñones della Mafiester. Col training lo posso far
  diventare anche TS (non è tra i ruoli secondari) e mi ci mette lo stesso tempo che a spostarlo in un ruolo che conosce
  come secondario. Spostarlo in un ruolo secondario dovrebbe richiedere meno tempo: nel mio caso 8 giorni per il ruolo non
  secondario e 6 per quello secondario.»
* **Oggi** (`public.avvia_cambio_ruolo`): base = max(6, 14 − 2 × (ruoli in scheda − 1)), poi lo sconto del livello di
  allenamento (`riduzione_tempi_ruolo_pct`), minimo 2 giornate. Il ruolo d'arrivo non conta. Quiñones (ED/ATT/AS,
  allenamento livello 4 = −16%): base 10 → 8 giornate per qualsiasi ruolo.
* **Decisione:** se il ruolo d'arrivo è **già tra i ruoli in scheda** del giocatore, la durata è **il 25% in meno**
  (Quiñones: TS 8, ATT o AS 6). Vale per tutti; si somma allo sconto dell'allenamento, minimo 2.
* **Note per farlo:** stessa regola anche in `avvia_cambio_ruolo_vivaio`, e nell'app dove si mostrano i giorni previsti
  prima di avviare il cambio (da cercare: anteprima della durata in Rosa/Allenamento).

---

## 4. Stadio: nuovo ramo delle risorse

* **Stato:** `deciso` in parte (25/10/2026) — da definire l'importo dei crediti; fattore campo da misurare col motore.
* **Richiesta:** «Gestione stadio tra le risorse. Più punti si assegnano allo stadio e più lo stadio diventa grande e di
  conseguenza aumenta il limite del bonus del pubblico. Con 0 punti risorsa il massimale del bonus del pubblico è +1,0;
  si sale di 0,2 per ogni punto risorsa, quindi al massimo uno stadio può dare +3.»
* **Oggi:** tre rami (vivaio, training, medico) da 0 a 10, 2 punti a ogni quarto di stagione, **massimo 20 punti** in
  tutta la vita della lega (Serie F: 16 ricevuti, ~15 spesi). Il pubblico scala il fattore campo con
  `private.moltiplicatore_pubblico` = (pubblico − 10)/70 fra 0 e 1, cioè fino a tutto il bonus casa del motore
  (attacco +2,0).
* **Decisioni:**
  * quarto ramo **stadio**, livello da 0 a 10; massimo del bonus del pubblico **+1,0 a livello 0, +0,2 per livello, +3,0 a
    livello 10** (livello 5 = come oggi). Tradotto nel motore: moltiplicatore casa = (1 + 0,2 × livello)/2 × fattore pubblico;
  * **tutti partono da 0** alla Season 3 (il committente lo sa: con il pubblico a 50, a inizio stagione il fattore campo
    vale circa un quarto di oggi e cresce con stadio, risultati e conferenze);
  * **massimo dei punti risorsa da 20 a 26**, nessuna ridistribuzione dei punti già spesi (romperebbe vivaio e training);
  * lo stadio dà anche **entrate di crediti del casinò per ogni partita in casa** (i "biglietti").
* **Da definire:** quanti crediti per partita in casa e per livello (proposta: 25 × livello, pagati insieme ai premi
  partita, quindi dopo la visione o dopo 24 ore, senza spoiler).
* **Da misurare (chat del motore):** vittorie in casa per livello di stadio e di pubblico con il motore L2; verificare
  che il motore accetti un moltiplicatore casa maggiore di 1 (oggi è al massimo 1).

---

<!-- Nuove richieste qui sotto: "## N. Titolo", poi Stato, Richiesta (parole del committente), Decisioni, Note. -->
