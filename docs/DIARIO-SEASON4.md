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

* **Stato al 10/11/2026** (lavoro nel branch `feat/season4-live`, cartella `SpecialOne-s4`; niente è in gioco):
  * **motore (`motore-live/`)**: una partita azione per azione con posizioni in campo, ripartenze, cartellini,
    stanchezza, tattiche (mentalità, pressing, linea) e pilota dei cambi. Su 3000 partite 16 bersagli su 16
    (`docs/risultati-motore-live.txt`). I gol restano fra 2,7 e 2,9 a partita da rose di OVR 66 a rose di OVR 85;
  * **campo 2D (`campo-live/`)**: registro di cosa disegnare, regia dei cinque minuti, disegno su canvas, tabellone,
    cronaca breve e numeri. Pagina di prova con Mafiester Utd – Fc Riskmond: si costruisce con
    `node campo-live/prova/costruisci.mjs <file.html>`;
  * **la regia**: 90 minuti in 5 vuol dire in media 18 volte più veloce del vero. Le occasioni (12-15 a partita, circa
    90 secondi su 300) si vedono a 1,5 volte la velocità vera, il resto scorre fino a 35-40 volte;
  * **nella prova ogni tempo è calcolato tutto prima di essere mostrato.** Con i comandi veri (tappa 4) la regia
    dovrà lavorare con pochi secondi di anticipo: è il pezzo ancora da progettare;
  * **gli 11 moduli sono alla pari** (10/11): in un girone fra moduli a parità di giocatori lo scarto fra il primo e
    l'ultimo è sceso da 0,57 a 0,19 punti a partita (motore di oggi: 0,13). Tre leve nuove: chi difende si stringe
    contro chi attacca senza uomini larghi, il trequartista cerca più spesso il filtrante, gli esterni di centrocampo
    crossano dalla trequarti. Con gli schemi che la Serie F usa davvero si segnano 3,0 gol a partita (oggi 3,08);
  * **gli schemi personalizzati sono equilibrati** (10/11, indicazione del committente: «ci sta che il 4-2-4 tiri di
    più, dall'altro lato avrà un centrocampo più scoperto; gli schemi vanno equilibrati, prendi spunto da Football
    Manager»). Spostando i giocatori dentro la linea l'app permette 1230 schemi: misurati su due campioni da 240,
    ognuno contro gli 11 moduli. Prima andavano da 0,08 a 1,85 punti a partita, col 59% fuori dalla fascia 1,15-1,55;
    ora da 0,85 a 1,72 col 18-20% fuori (motore di oggi, stessa prova: da 0,85 a 1,57, 19-20% fuori). I migliori
    veri valgono 1,55-1,65 contro 1,47 del miglior modulo. Cinque regole, nessuna sposta i posti degli 11 moduli:
    1. il campo è sempre coperto (un uomo per fascia per linea, i doppioni giocano dentro; una linea con meno di tre
       uomini gioca al centro; un attacco a tre senza ali allarga le punte);
    2. pressare è corsa, marcare è mestiere (chi porta palla è disturbato per metà dalla corsa di chi gli sta
       addosso, non solo dal suo voto difensivo: prima riempire il campo di mediani vinceva sempre);
    3. lo schema ha due facce: con la palla tre uomini davanti (salgono i centrocampisti avanzati), senza palla
       quattro a centrocampo (rientrano le ali) e due centrali in mediana (scendono i trequartisti);
    4. i centrocampisti centrali non fanno gli esterni: in quattro o cinque restano stretti e lasciano le fasce;
    5. niente tre uomini in colonna: mezzala e mediano soli si sfalsano di lato.
    **Che cosa resta, da sapere:** un mediano solo davanti alla difesa rende (1,44 contro 1,29 senza); senza mediani
    né mezzali si subisce troppo (1,16); quattro esterni di centrocampo o quattro punte sono scelte perdenti
    (0,99 e 1,24); le mediane centrali affollate restano le più forti (circa 1,6). Si pensava che dipendesse dal
    blocco di chi difende che seguiva la palla senza ritardo: l'inerzia del punto qui sotto c'è e non è bastata,
    quindi la causa va cercata altrove. La prova è
    `node tools/validazione/prova-schemi-live.mjs` (`VECCHIO=1` per il motore di oggi). Ruoli, compiti, stili e
    fuori ruolo sposteranno questo equilibrio: la prova va rifatta dopo ognuno;
  * **il fuorigioco si vede giusto** (10/11, segnalazione del committente: Retegui serve il numero 11 in netto
    fuorigioco e il gioco va avanti). Il motore considera in gioco chi riceve e fischia solo sui filtranti; era il
    disegno a portare chi riceve oltre la linea secondi prima del passaggio. Ora chi riceve resta al di qua della
    linea finché la palla non parte, e nel fuorigioco fischiato lo si vede oltre. Fuorigioco non fischiati
    visibili: da 686 su 16.561 passaggi a 0;
  * **il blocco di chi difende ha inerzia** (10/11): non si sposta più all'istante con la palla ma la rincorre a
    8 metri al secondo, in profondità e di lato. Sul filtrante riuscito chi riceve è oltre la linea di 1,7 m (prima
    la difesa era già 3 m alle sue spalle), la linea arretra a 3 m/s mentre la palla vola, e su angoli e punizioni chi
    riceve si muove durante il tempo morto invece di partire alla battuta. Validazione su 3000 partite: 16 bersagli
    su 16 (2,66 gol). I comandi presi uno per volta stanno entro un decimo di punto a partita.
    **Che cosa è costato, da riprendere alla prossima taratura** (insieme a ruoli, compiti e ampiezza, che spostano
    comunque l'equilibrio: si ritara una volta sola):
    * i moduli sono passati da 0,19 a 0,25 di scarto (3-5-2 a 1,52 e 5-3-2 a 1,50 in cima, 4-2-4 a 1,26 in fondo).
      Decisione: l'inerzia resta intera. Togliere la parte laterale avrebbe recuperato circa 0,03, ma è il ritardo di
      lato che fa valere il cambio di gioco;
    * le vittorie in casa sono scese dal 47,0% al 43,2%: dentro la fascia 43-47 ma sul bordo, da riportare verso 45;
    * **punto aperto per la tappa 4**: la coppia «linea alta + mentalità difensiva» vale +0,22 punti a partita
      (+0,25 già prima dell'inerzia). Nessun comando da solo passa +0,09;
  * **come si lanciano le prove** (10/11): database e server del gioco stanno sullo stesso Mac, e dodici prove del
    motore lanciate insieme li hanno fatti cadere per qualche minuto. Da ora una prova alla volta, in sottofondo sui
    processori lenti (`taskpolicy -b node tools/validazione/...`): 1000 partite con tutte le sezioni durano 9 minuti
    e il server non se ne accorge. Le batterie lunghe solo in un momento concordato col committente, mai verso le 22.
    La sera del 10/11 il Mac aveva già un carico di 8 su 8 processori per conto suo (sei processi fermi al 100% da
    giorni: cinque «Codex» dell'app ChatGPT e uno di VS Code): in queste condizioni solo prove da un paio di minuti,
    con un freno che le ferma se il server risponde in più di un secondo;
  * **ruoli e compiti dei giocatori** (10/11, prima taratura; `docs/decisioni-tattiche.md` punti 13, 15, 16, 22, 23,
    28, 36). Nel motore di oggi spostano punti fra le linee; nel motore nuovo spostano il giocatore sul campo: un
    ruolo lo fa giocare più su o più dentro quando la squadra ha la palla (5 metri in avanti, 8 verso il centro per
    un uomo di fascia), un compito lo sbilancia secondo il reparto (un difensore si blocca o si sgancia, un
    centrocampista copre o si inserisce, una punta pressa il portatore o resta sul filo). Quello che si guadagna e
    quello che si paga lo decide il campo: chi sale è un uomo in più davanti e uno in meno dietro la palla quando la
    si perde; chi rientra dalla fascia toglie ampiezza. Saper fare il ruolo vale come nel gioco di oggi (stesso
    elenco, stessa idoneità, stessi consumi: una fonte sola). Con ruolo base ed «equilibrio» la partita è identica
    evento per evento. Numeri (4-3-3 contro 4-3-3, 600 partite per riga, punti in più su 38 giornate per chi sceglie,
    errore 2):
    * a posto: chi tocca tutto a caso −3,5 (non batte chi non tocca niente); chi sbaglia apposta −10,8 (uguale al
      motore di oggi); «tutti in attacco» −0,3 con più gol da tutte e due le parti, «tutti in difesa» +0,2 con meno
      gol; nessun compito e nessun ruolo sopra +1,6;
    * **da rifinire nella ritaratura**: chi legge bene la rosa va solo in pari (+0,3, nel motore di oggi +4,0),
      perché uscire dal posto del modulo costa ancora circa 2 punti per gruppo di giocatori; la punta di manovra con
      una punta sola costa −6,6 (esce dalla zona dei filtranti e nessuno ne prende il posto): così sarebbe una scelta
      morta; terzini che si sganciano −4,5, incursore −3,7, pressing −3,5, marcatore −3,5 sono al limite. Misurato
      solo il 4-3-3. Il costo vero del pressing (la condizione fra una partita e l'altra) arriva col pezzo della
      condizione. La prova è `node tools/validazione/prova-ruoli-live.mjs`;
  * **mancano ancora nel motore nuovo**: infortuni e condizione, stili e ampiezza, familiarità coi moduli, fuori
    ruolo, morale, pubblico, voti, mentalità decisa dal pilota, la scelta di ruoli e compiti nella pagina di prova,
    la prova «pilota contro allenatore che interviene» e il confronto in parallelo su LegaBot. Poi la **ritaratura
    unica** (moduli, casa, ruoli e compiti, schemi) con batterie lunghe in un momento concordato.
