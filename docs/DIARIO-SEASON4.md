# Diario della Season 4

Le funzionalità e le modifiche che il committente vuole per la **Season 4**. Le tiene la sessione supervisore: ogni
richiesta si annota qui con data, stato e decisioni prese, così resta traccia fra una conversazione e l'altra.

**Stati:** `da valutare` (appena chiesta) · `deciso` (regole fissate col committente) · `in lavoro` · `pronto` (fatto e
provato, in attesa di pubblicazione) · `pubblicato` · `rimandato` · `scartato`.

**Calendario:** la Season 3 della Serie F è iniziata l'8/11/2026. Quello che è `pronto` si pubblica a inizio
off-season 4, salvo indicazioni diverse. Fino ad allora il lavoro resta su un branch a parte e si prova su LegaBot.

---

## 1. Partita in diretta: motore azione per azione e campo 2D

* **Stato:** `in lavoro` (10/11/2026): tappa 1 (motore) e prima versione del campo 2D, in prova fuori dal gioco.
* **Chi:** sessione supervisore. Branch `feat/season4-live`, worktree `/Users/cristianobraccili/SpecialOne-s4`.
* **Richiesta (9/11/2026):** partite in diretta di 5 minuti (2 e mezzo per tempo), tutte insieme alle 22:00, in cui si
  può intervenire con cambi e tattiche come in Football Manager. Il motore simula azione per azione, non più a blocchi.
  «Assistere non deve essere un vantaggio. È solo per chi vuole. Chi non ha voglia lascia il pilota automatico e alla
  fine vede la cronaca o il risultato finale.» «Nel live della partita va fatto il campo 2D. Una bella grafica wow,
  nuova e moderna.» «Chi non vuole assistere al live, al termine della partita, trova la cronaca come oggi.»

* **Decisioni (9/11/2026):**
  * **durata:** 5 minuti reali a partita, 2,5 per tempo; tutte le partite della giornata partono insieme alle 22:00;
  * **motore azione per azione**: ogni passaggio, contrasto e tiro è un evento con minuto, giocatore e punto del campo;
  * **la diretta è facoltativa e non dà vantaggi**: chi non si collega è guidato dal pilota automatico;
  * **campo 2D nella diretta**, grafica nuova e moderna (stile videogioco, come il resto dell'app);
  * **la cronaca a fine partita resta quella di oggi**, stessa grafica, per chi non ha assistito.

* **Proposte della sessione, non contestate (da confermare quando si arriva alla tappa che le riguarda):**
  * **pilota automatico bravo quanto un allenatore attento**: cambia gli stanchi, gli ammoniti e chi rende male, si
    sbilancia se perde nel finale, si copre se vince, si riassesta se resta in dieci;
  * **nessun comando dominante**: ogni comando ha un prezzo. In validazione «pilota automatico contro allenatore che
    interviene» deve finire alla pari, entro il rumore statistico. Se non succede, il comando si ritara o si toglie;
  * **piano partita** preparato prima della gara, per tutti (regole del tipo «se perdo dopo il 70' passo a offensivo»):
    è quello che esegue il pilota. Chi è collegato può cambiarlo in corsa;
  * **la diretta non mostra niente che il pilota non usi** (nessuna informazione riservata a chi guarda);
  * **un ordine vale dall'azione successiva**, mai all'indietro;
  * **comandi**: 5 cambi in 3 finestre, mentalità (difensiva / equilibrata / offensiva / tutti all'attacco), pressing
    (basso / medio / alto), linea difensiva (bassa / media / alta), cambio di modulo (con la familiarità di oggi);
  * **decide sempre il server**: la partita si simula sul server, e a ogni ordine si rigioca dal minuto dell'ordine.
    Il telefono disegna soltanto;
  * **i movimenti senza palla** degli altri 20 giocatori li disegna la grafica a partire dal modulo e dalla zona della
    palla: non sono simulati e non contano per il risultato.

* **Tappe:**
  1. **Motore azione per azione** alla pari con quello di oggi (gol, vittorie in casa, pareggi, peso della forza,
     tattiche), con la posizione di ogni azione, validato. Gira in parallelo su LegaBot senza decidere i risultati.
  2. **Partite che avanzano nel tempo**: la partita non si gioca più tutta in un istante ma lungo i 5 minuti.
  3. **Campo 2D in diretta.**
  4. **Comandi e piano partita**, con la prova «nessun comando dominante».
  5. **Passaggio in Serie F** a inizio Season 4.

* **Punto di partenza:** il prototipo del 16/9/2026 (`tools/validazione/motore-azioni.mjs`, registro tattico punti
  10-12): tre zone di campo, duelli fra attributi, sette metriche d'insieme e curva di competitività già nei bersagli.
  Gli mancano sostituzioni, infortuni, cartellini, stanchezza, moduli, stili, familiarità, ruoli e compiti, morale,
  pubblico, stato della partita e voti: è il lavoro della tappa 1.

* **Note tecniche:**
  * il motore nuovo vive in una cartella sua (`motore-live/`), accanto a `engine/` e senza toccarlo: quello attuale
    resta validato e in uso fino al passaggio;
  * il generatore casuale ha lo stato dentro la partita (non globale come in `engine/random.js`): così una partita si
    può fermare, salvare e riprendere dallo stesso punto, che è quello che serve per applicare un ordine in corsa.
