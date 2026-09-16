# Decisioni sul sistema tattico

Settembre 2026, branch `feat/tattiche`. **Vincolante e più recente del design doc**,
che non contiene nulla sulle tattiche.

Tutto quello che c'è qui è stato misurato, non stimato. Gli strumenti:

| strumento | cosa misura |
|---|---|
| `tools/validazione/leve-tattiche.sql` | quali attributi possono reggere una tattica (sul catalogo) |
| `tools/validazione/profili-rose-vere.js` | se i profili esistono dentro le rose vere |
| `tools/validazione/simulate-tattiche.js` | i quattro test di accettazione del sistema |

---

## 1. Una tattica chiede un PROFILO, non un attributo alto

È la decisione che regge tutte le altre, ed è nata da una correzione del committente.
La prima stesura del prototipo chiedeva attributi alti. Sbagliato:

| misura | correlazione con overall | giudizio |
|---|---|---|
| tecnica da sola | 0,70 | overall travestito |
| tecnica **meno** lotta | 0,09 (ampiezza 32) | leva vera |
| rapidità **meno** fisicità | ~0,00 (ampiezza 40) | leva vera |

Chiedere "passaggi alti" significa chiedere giocatori più forti, perché a parità di
ruolo chi passa meglio ha anche l'overall più alto: non è una decisione. Chiedere uno
**sbilanciamento** fra due qualità è una scelta vera, perché quello non si compra con
l'overall — va cercato al draft e sul mercato.

L'esempio che ha corretto l'analisi: Modrić e Anguissa hanno overall simili e profili
opposti. Un altro, misurato, fra 77 e 79 di overall:

```
Suso      passaggi 78  fisico 50  contrasti 23   profilo +45
P. Ciss   passaggi 75  fisico 88  contrasti 76   profilo -10
```

I due profili in uso sono `tiltTecnico` e `tiltRapido`, in `engine/tattiche.js`.

## 2. I profili esistono dentro le rose vere, non solo nel catalogo

Il catalogo ha 6.202 giocatori, ma nessuno gioca col catalogo: si gioca con 25 giocatori
usciti dal draft. Misurato su 29 rose umane di stagione 1:

| reparto | profilo | ampiezza in rosa | corr. overall |
|---|---|---|---|
| DEF | rapido | 35,0 | −0,02 |
| MID | tecnico | 34,7 | +0,18 |
| ATT | rapido | 34,4 | −0,27 |

Serve ampiezza ≥ 20 e correlazione vicina a zero: entrambe ampiamente rispettate.

**Le leghe vecchie non sono campioni validi.** LegaBot è alla stagione 4 e le squadre
del PC non hanno rinnovato i contratti: le rose si sono impoverite e stanno 10-14 punti
sotto l'unica umana. Lì l'ampiezza del profilo a centrocampo scende a 24,7 e il costo in
overall a 0,7 punti contro 4,0 — su rose degradate il profilo è quasi gratis e il dilemma
tattico sparisce. Tarare su leghe umane di stagione 1.

## 3. Il prezzo del piano non va modellato: lo applica già il motore

Schierare i quattro difensori più veloci invece dei quattro più forti costa in media
**3,9 punti di overall**. Non serve aggiungerlo: una difesa veloce e debole ha già un DEF
più basso in `forzeLinee()`. Le scale vanno tenute sotto quel costo, altrimenti
converrebbe a tutti schierare velocisti a prescindere dall'avversario.

## 4. La matrice dei contrasti deve essere antisimmetrica

Due regole, imparate sbagliando, in questo ordine:

1. **Ogni riga e ogni colonna devono contenere un valore sfavorevole.** Nella prima
   stesura la colonna "blocco basso" era tutta negativa: il blocco basso non veniva
   punito da nessuno e la morra cinese era solo apparente (13,6 pp di scarto).
2. **Le righe devono anche sommare a zero.** Con "corta" a −0,3 e "verticale" a +0,2,
   verticalizzare rendeva in media contro un campo uniforme: conveniva sempre, a
   prescindere dall'avversario, e l'assetto migliore in assoluto catturava quasi tutto
   il valore del leggere la partita (rapporto 1,4x invece di 7,5x).

## 5. Le opzioni neutre sono volutamente le più deboli

"Linea media" e "Mista" non chiedono nessun profilo e non vincono nessun contrasto.
È voluto: **avere un piano batte non averlo.** Chi non sceglie non viene punito, ma non
guadagna niente.

## 6. Il tetto: meno di 8 punti di overall

A +8 punti il più forte vince già l'84% (TEST 2 della Fase 0). Oltre quella soglia la
tattica conterebbe più della qualità della rosa, e una squadra nettamente più forte
potrebbe perdere per una scelta sbagliata. Misurato nel confronto più squilibrato:
**4,3 punti**. Dentro il vincolo con margine.

## 7. Lo scarto è una funzione (giocatore, slot), non una mappa sui titolari

`sostituzioni()` confronta chi è in campo con chi è in panchina. Con una mappa costruita
sui soli titolari, un panchinaro perfetto per il piano non sarebbe mai stato valorizzato:
saresti potuto restare con l'interprete sbagliato in campo avendo quello giusto seduto.

## 8. Dati incompleti significa "nessun profilo", mai un profilo sbagliato

`tiltTecnico` e `tiltRapido` restituiscono `null` se manca anche un solo attributo, e
`idoneita()` lo traduce in nessun effetto. Un attributo assente trattato come 0
produrrebbe un profilo falso e un bonus inventato.

Serve davvero, non in teoria (misurato il 12 settembre 2026):

- i **210 giocatori del vivaio** non hanno 8 dei 10 attributi richiesti;
- i **portieri normali** hanno `pace` e `physic` presenti ma a `null`.

Con una validazione stretta la simulazione notturna sarebbe andata in errore su **ogni
formazione**, perché ognuna schiera un portiere.

Un giocatore senza profilo subisce il contrasto di reparto ma non riceve né bonus né
malus da interprete: finisce in mezzo fra l'interprete giusto e quello sbagliato.

## 9. A tattiche spente il motore è quello validato

Non è un'affermazione di principio: `simulate.js` e `simulate-reale.js` danno output
**identico byte per byte** prima e dopo l'integrazione. Senza piano `lineup.tattica`
è `undefined` e ogni chiamata a `ovrEfficace()` riceve scarto 0.

---

## 10. Un motore azione per azione è fattibile — misurato il 16 settembre 2026

Domanda posta dal committente dopo essersi informato su come lavora Football
Manager: **in FM non esiste un overall nel motore**. Per ogni azione si
richiamano gli attributi rilevanti, pesati per ruolo; la *current ability* è un
riassunto derivato, non un input. Il nostro motore a blocchi sta nella stessa
famiglia del motore **semplificato** che FM usa per le migliaia di partite di
contorno — il che è coerente con 8 partite a notte, ma non è la stessa cosa.

Prototipo in `tools/validazione/motore-azioni.mjs`, separato da `engine/`.
Sedici attributi invece di cinque, rose di giocatori veri, i gol emergono dalle
azioni invece di essere estratti da una Poisson sull'xG.

**Risultato: tutte e sette le metriche d'insieme dentro il bersaglio** su 3.000
partite. E la curva di competitività combacia con la Fase 0 entro 2,5 punti a
ogni gradino:

| divario | prototipo | Fase 0 |
|---|---|---|
| +0 | 38,6% | 36% |
| +4 | 62,8% | 62% |
| +8 | 85,8% | 84% |

**La scoperta che conta.** Alla prima taratura la curva schizzava al **93% a
+8**: in un motore azione per azione un vantaggio piccolo si moltiplica per
centinaia di duelli, e la squadra migliore vince praticamente sempre. La
costante che governa la ripidità del singolo duello decide se stai costruendo
un simulatore o un gioco. Appiattirla riporta la curva dove deve stare.

**Quello che il prototipo NON ha**, e che il motore attuale ha e ha validato:
sostituzioni, infortuni, cartellini, calo di condizione, effetto dei moduli,
effetto degli stili, familiarità. Portarlo in produzione significa rifarle una
per una e rivalidare — è la Fase 0 un'altra volta, non una serata.

**Perché comunque interessa.** In un motore così le tattiche smettono di essere
un modificatore sull'overall e diventano parametri veri: l'altezza della difesa
sposta dove si recupera il pallone, la costruzione corta cambia la lunghezza
media del passaggio. È la differenza fra simulare l'effetto di una scelta e
simulare la scelta.

**Da decidere, e non è ancora deciso**: se il motore azione per azione produca
davvero *più* profondità tattica del modificatore che abbiamo già misurato
(§punti 1-9), o solo più complessità. Si risponde con gli stessi quattro test
di accettazione, portati sul prototipo, e confrontando con 2,1 pp di scarto,
7,5x sul leggere l'avversario e 4,3 punti nel confronto più squilibrato. Se i
numeri non migliorano, vince il sistema semplice che funziona già.

## 11. Le tattiche nel motore azione per azione rendono MENO — misurato

Portati i due assi dentro il prototipo come parametri veri delle meccaniche —
la linea alta recupera il pallone piu' avanti ma si fa scavalcare, la
costruzione corta guadagna campo di rado ma al sicuro — e rifatti gli stessi
test di accettazione del sistema integrato.

| | motore azioni | sistema integrato |
|---|---|---|
| metriche d'insieme | 0 fuori su 7 | n.d. |
| scarto fra gli assetti | 3,3 pp | **2,1 pp** |
| leggere l'avversario | 2,0x | **7,5x** |
| confronto piu' squilibrato | 1,7 punti | **4,3 punti** |

**Il motore azione per azione e' piu' realistico ma tatticamente piu' piatto.**
Leggere l'avversario vale un terzo, e la scelta tattica pesa meno della meta'.

**Perche', ed e' la cosa da ricordare.** In un motore a blocchi lo scarto
tattico entra nelle forze di reparto e sopravvive fino al risultato. In un
motore azione per azione lo stesso scarto viene diluito su novecento duelli: la
legge dei grandi numeri lo appiattisce. Piu' azioni simuli, meno conta ogni
singola scelta a monte.

**E l'equilibrio non e' gratis.** Nel sistema integrato la morra cinese e'
garantita per costruzione: la matrice dei contrasti e' antisimmetrica, somma a
zero, non puo' esistere un assetto dominante. Nel motore azione per azione
l'equilibrio va trovato a mano tarando il prezzo di ogni meccanica, ed e' un
punto stretto: col prezzo della linea alta a 0,075 lo scarto era 12,5 pp con un
assetto dominante; a 0,26 scende a 3,3; a 0,34 risale a 7,4 col dominio
ribaltato sul blocco basso. Un ottimo fragile fra due dominii.

**Conseguenza per la decisione**: il motore azione per azione vale per cio' che
porta davvero — tabellini credibili, i singoli attributi che contano, i gol che
emergono dalle azioni. NON e' la strada per avere tattiche piu' profonde: su
quel fronte il sistema che gia' gira fa meglio, e di molto.

## 12. Correzione del punto 11: il metro era sbagliato — 16 settembre 2026

Il committente ha obiettato che in Football Manager le tattiche contano
parecchio, e aveva ragione: la conclusione del punto 11 era misurata contro il
metro sbagliato, cioe' il nostro stesso sistema, invece che contro la realta'.

**I dati veri.** FM-Arena prova le tattiche in un campionato dove tutte le
squadre hanno pari qualita', normalizzando su 38 partite:

| | punti/stagione | punti/partita |
|---|---|---|
| tattica migliore | 84,5 su 114 | 2,22 |
| tattica peggiore in classifica | 77,1 | 2,03 |

Sono circa **6,4 punti percentuali** di scarto in termini di vittorie. Il nostro
sistema integrato ne fa 2,1 e il prototipo azione per azione 3,3. **In FM le
tattiche pesano due o tre volte piu' che da noi.**

Quindi il prototipo non appiattisce niente: e' piu' vicino a FM di quanto lo sia
il sistema che gia' gira. Il punto 11 resta valido nei numeri ma sbagliato nella
conclusione.

**Le qualificazioni, dalle parole dei tester di FM stessi:**

- *"the better/worse your players compared with your opponent players, the less
  your tactic matters"* — e' esattamente il vincolo che ci siamo dati al punto 6;
- uno scarto di 7 punti *"shrinks to 3 points or disappears entirely"* quando le
  squadre diventano forti;
- una tattica da 49 punti nei test **vince comunque il campionato** con giocatori
  di livello;
- e c'e' un rumore di **±25 punti** su una stagione di 38 partite, cioe' molto
  piu' grande dello scarto fra le tattiche.

Anche in FM, quindi, la qualita' della rosa domina e la tattica e' un margine.

**DA DOVE VIENE DAVVERO LA PROFONDITA' DI FM**, ed e' la risposta alla
sensazione del committente: non da una leva potente, ma da **tante leve che si
combinano**. Mentalita', forma della squadra, un ruolo e un compito
(difendere/sostenere/attaccare) per ciascuno degli undici, e istruzioni divise
in tre fasi — in possesso, in transizione, fuori possesso. Nella sola
transizione: Counter, Hold Shape, Counter-Press, Regroup.

Una tattica di FM e' una combinazione di trenta e piu' decisioni, ognuna
piccola. **Noi ne abbiamo due, per nove combinazioni totali.** E' li' la
differenza, non nella forza del singolo asse.

**Conseguenza operativa**: la strada per far contare le tattiche non e' rendere
un asse piu' potente — e' aggiungere assi, e soprattutto scendere al livello del
singolo giocatore con ruoli e compiti. Cioe' esattamente le "istruzioni per
slot" del punto aperto A, che a questo punto smettono di essere un di piu' e
diventano il cuore della cosa.

**Una cosa in cui restiamo pero' migliori, e va tenuta.** FM ha un problema di
tattica meta: FM-Arena esiste perche' la gente cerca la tattica che vince sempre.
Noi al punto 5 abbiamo deciso il contrario, e il test A lo verifica. Aggiungere
leve non deve significare rinunciare a quello.

## 13. I compiti per giocatore: meccanica sana, ma non sono una decisione tattica

Primo pezzo del punto aperto A, sul modello delle duties di FM. Ogni titolare
ha un compito — difendere, equilibrio, attaccare — che SPOSTA il suo peso da
una linea all'altra in PESI_SLOT. Un terzino che si sovrappone pesa meno in
difesa e di piu' davanti, e quel peso alla difesa manca davvero: il costo e'
automatico perche' sono gli stessi pesi con cui forzeLinee calcola DEF/MID/ATT.

Lo spostamento e' di UNA linea, non un salto, quindi funziona per ogni ruolo
senza casi speciali: un centrale che spinge entra a centrocampo, una punta in
attacco non guadagna nulla perche' non c'e' dove avanzare.

**Prima trappola, risolta.** Senza vincoli, "tutti all'attacco" conveniva
sempre: 37,7% contro il 34,2% del molto difensivo, ordine perfettamente
monotono. Si guadagnava davanti quanto si perdeva dietro, e con i gol che
contano piu' dei gol subiti il saldo era positivo per chiunque.

Corretto con un'asimmetria: **il peso che se ne va, se ne va sempre; quello che
arriva dipende da quanto il giocatore e' adatto**. Un terzino lento che si
sovrappone abbandona comunque la sua zona ma davanti non porta niente. Con
questo l'ordine si rovescia in una campana:

| assetto | vittorie |
|---|---|
| molto difensivo | 33,7% |
| prudente | 37,6% |
| **equilibrato** | **39,0%** |
| propositivo | 36,0% |
| molto offensivo | 36,2% |

**Seconda trappola, NON risolta, ed e' quella che conta.** Leggere l'avversario
vale **+0,0 punti percentuali**: equilibrato e' la risposta migliore a ognuno
dei cinque assetti, nessuno escluso. I compiti sono una manopola di rischio con
un ottimo piatto, non una decisione contro qualcuno.

Il motivo e' lo stesso del punto 11: **l'interazione non emerge, va costruita**.
Gli assi tattici hanno il 7,5x perche' hanno una matrice di contrasti esplicita
e antisimmetrica. I compiti cambiano le TUE linee in assoluto, e non esiste
nessun termine che leghi la tua scelta a quella dell'avversario.

**Conseguenza per il disegno.** Cosi' come sono, i compiti aggiungono una
trappola per i distratti e niente per chi ragiona: un giocatore razionale mette
sempre equilibrato. Tre strade:

  1. lasciarli come manopola di rischio, riconoscendo che valgono poco;
  2. dargli un'interazione esplicita — un terzino sbilanciato in avanti punito
     di piu' contro chi ha ali veloci — cioe' rifare quello che la matrice dei
     contrasti fa gia' per gli assi;
  3. accettare che in FM le duties non sono rock-paper-scissors nemmeno loro, e
     che la profondita' li' nasce dalla COMBINATORIA di ruoli, compiti e
     istruzioni divise per fase. In quel caso il pezzo che manca non e'
     l'interazione: sono i RUOLI, che ancora non abbiamo.

La 3 e' la lettura piu' fedele a FM ed e' quella che seguirei, ma va decisa.

---

# Punti aperti

## A. Istruzioni ai singoli giocatori — da decidere

Richiesta del committente (11 settembre 2026), **non ancora progettata**. L'esempio:
"il terzino destro si sovrappone". La domanda posta è se dare istruzioni offensive e
difensive **a ogni giocatore** oppure **per reparto**.

L'obiezione del committente, che è il vincolo vero: un reparto non ha una forma sola.
Con due punte non si possono usare le istruzioni da ala, e lo stesso vale negli altri
reparti.

**Osservazione da verificare**: il motore ragiona già per **slot**, non per reparto
(`ST`, `CF`, `LW`, `RW`, `LB`, `LWB`...). Se le istruzioni sono agganciate allo slot
invece che al reparto, l'obiezione si scioglie da sé: le istruzioni da ala esistono solo
se il modulo ha `LW`/`RW`, e col `4-4-2` compaiono quelle da seconda punta. Da discutere
prima di disegnare lo schema.

**Conseguenza sullo schema**: la tabella dei piani non deve chiudere la porta a questo.
Due assi di squadra oggi, ma una forma che possa ospitare anche indicazioni per slot.

## 15. I ruoli dicono *dove*, i compiti dicono *quanto*

Un compito sposta un giocatore in avanti o indietro. Un ruolo lo sposta dentro o fuori.
Sono due assi indipendenti, e il secondo ha potuto esistere solo dopo le corsie (punto 14).

`engine/ruoli.js` definisce 18 ruoli su cinque famiglie di slot. Ognuno è **due numeri**,
non un blocco di codice: `dentro` (−1 si allarga, +1 rientra) e `avanti` (come un compito).
Aggiungere un ruolo nuovo costa due numeri e una riga di commento.

**Il ruolo naturale è esattamente neutro**, non un ruolo fra gli altri: a ruoli spenti la
suite dà gli stessi identici numeri della versione senza ruoli, cifra per cifra.

## 16. L'idoneità doveva toccare la resa, non lo smistamento

Primo tentativo sbagliato, vale la pena ricordarlo. L'idoneità al ruolo governava solo
quanto peso *arrivava* nella nuova corsia. Misurato: un regista interpretato da un
passatore puro e dallo stesso ruolo dato a un finalizzatore rendevano **uguale** (scarto
−0,2 punti, cioè rumore). Il motivo è che lo smistamento del peso è una cosa che
l'avversario LEGGE, non il rendimento di chi gioca.

La correzione usa il canale che già esisteva, lo scarto di overall efficace
(`lineup.tattica`): `VALORE_IDONEITA = 2,6` punti a idoneità piena. Ora, a parità di
overall:

| CM al centrocampo | da regista | da incursore |
|---|---|---|
| profilo passatore | **43,5%** | 39,7% |
| profilo finalizzatore | 39,6% | **42,8%** |
| (ruolo naturale, entrambi) | 41,0% | 41,0% |

Il giusto interprete guadagna +2,5 punti sul naturale, quello sbagliato ne perde 1,4.
È così che funziona in Football Manager: la resa dipende da quanto il ruolo somiglia al
giocatore, non dal ruolo in sé.

## 17. Un ruolo si può leggere

Con B che tiene il terzino sinistro dentro — centro rinforzato, fascia scoperta:

| A attacca | vittorie A |
|---|---|
| non concentra | 39,8% |
| a sinistra | 39,8% |
| al centro (il forte) | 37,4% |
| **a destra (il buco)** | **46,0%** |

Scarto 8,6 punti, dentro la forbice di Football Manager (~6,4 fra migliore e peggiore
tattica a pari qualità, punto 12). Il primo valore tarato dava 19,3 punti: era una
roulette, e `SCALA_DENTRO` è stata portata da 0,30 a 0,13.

## E. La suite storica era già stata superata — e non me n'ero accorto

Chiuso, ma vale la pena tenerlo scritto perché l'errore è istruttivo.

Rilanciando `tools/validazione/simulate.js` l'ho trovata rossa (1,9 gol contro 2,50–2,90)
e l'ho segnalata come una domanda aperta da decidere. **Era già stata decisa il 9 settembre
2026**, e sta scritta in testa a `docs/risultati-fase0.txt`: quel file non è più il criterio
di accettazione, lo è `docs/risultati-produzione.txt`, prodotto da `simulate-reale.js`. La
ragione registrata è esattamente quella che ho ricostruito da capo: le rose di
`tools/validazione` nascono con `esperienzaModulo` vuoto, quindi ogni numero della suite
storica è misurato col malus di familiarità al massimo, uno stato che una squadra vera vive
per cinque partite e poi mai più (in Serie F il malus medio di lega è −0,31 su 3,5).

**Lezione**: prima di dichiarare rosso un guardrail, leggere l'intestazione del file che lo
definisce. Il tempo speso a ricostruire la diagnosi era già tutto sul disco.

Ho anche provato a far nascere le rose familiari in `roster.js`, e l'ho annullato:
`simulate-reale.js` ha un braccio di controllo *a familiarità zero* che quella modifica
distruggeva. Le due suite hanno bisogno di condizioni diverse ed è giusto così.

**Il criterio vero, misurato su questo branch** (`simulate-reale.js`, punto di produzione:
familiarità piena, moduli, stili e fuori ruolo reali):

| | branch | criterio 9 set | target |
|---|---|---|---|
| gol/partita | **2,87** | 2,71 | 2,50–2,90 |
| tiri/squadra | **13,41** | 13,2 | 11–14 |
| pareggi | **23,7%** | 24,5% | 23–27 |
| vittorie casa | **46,9%** | 45,8% | 43–47 |

Verde su tutti e quattro, coi calci piazzati dentro. `docs/risultati-produzione.txt` va
rigenerato quando il branch entra in main, non prima.

**Nota sul banco**: `tools/validazione/roster.js` ora pesca il blocco dei calci piazzati
(battuta, stacco, marcatura, punizione, presa) e il piede da un giocatore VERO dello
stesso ruolo e overall vicino, invece di lasciarli vuoti. Senza, le rose sintetiche erano
giocatori che i piazzati non li sapevano fare, e i calci piazzati rendevano 0,31 gol a
partita invece di 0,63. È un file di test: non tocca il motore. Questo resta.

## F. La familiarità è la leva più grande del gioco

Emerso di rimbalzo, ed è una domanda di design aperta, non un bug.

`FAM_MALUS_MAX` vale 3,5 punti di overall su tutti e undici. Misurato: da familiarità zero
a piena sono **+16,7 punti su 38 partite**. Per confronto, sullo stesso metro:

| leva | punti su 38 |
|---|---|
| familiarità col modulo | **+16,7** |
| condizione fisica (FM-Arena) | +15,6 |
| tattiche nostre, lettura dell'avversario | +6 / +8 |
| coesione di squadra (FM-Arena) | +6 |
| morale (FM-Arena, e il nostro) | +3,8 |

Non è assurdo — è nell'ordine della condizione fisica, che in FM è la leva più grande. Ma
va notato che da noi *conoscere il proprio modulo* pesa quanto *essere in forma*, e più
del doppio di qualunque scelta tattica. Se un giorno si vuole che le tattiche contino di
più, questa è la costante da guardare per prima. **Non toccata**: è una costante validata,
e cambiarla sposta il gioco vivo.

## 18. Il morale pesa poco, e il dato lo dice chiaro

Domanda d'istinto: un giocatore demoralizzato rende molto meno? In Football Manager,
**no**. FM-Arena lo ha misurato su 2.880 partite, normalizzate su una stagione da 38:

| morale | punti su 38 | GF | GS |
|---|---|---|---|
| Quite Poor (5) | 47,1 | 69 | 75 |
| Okay (10) | 47,3 | 70 | 75 |
| Very Good (15) | 50,9 | 72 | 73 |

Da scarso a molto buono: **+3,8 punti**. Nello stesso banco la condizione fisica da "Fair"
a "Excellent" ne vale **+15,6**, e la coesione di squadra **+6**. Il morale e' la piu'
piccola delle tre leve, circa un quarto della condizione, e meta' di quanto valgono le
nostre tattiche.

Tarato a sensazione avrebbe schiacciato tutto il lavoro tattico. `engine/morale.js` e'
tarato su quel numero: misurati **3,6 punti su 38** fra morale 45 e morale 95, con
`SCALA_MORALE = 0,27` punti di overall efficace. Prima taratura a 0,85: dava 9,6 punti,
quasi il triplo del vero.

**La coesione non si duplica.** In FM morale individuale e coesione di squadra sono due
cose diverse, e la seconda pesa di piu'. Da noi la coesione esiste gia' ed e' la
familiarita' col modulo (`formation_xp`), che vale quasi un gol a partita. Qui si e'
aggiunto solo il pezzo individuale.

## 19. Il capitano non sta nel motore

Provato prima dentro la partita, dove attenua il malcontento dei compagni. Misurato in
modo esatto invece che a simulazione: **+0,68 punti su 38**, cioe' sotto il rumore di un
banco da 20.000 partite. Non era una taratura sbagliata, era il posto sbagliato.

In Football Manager la fascia agisce sullo **spogliatoio nel tempo** — atmosfera, recupero
del morale — non sui novanta minuti. Da noi il morale si ricalcola a ogni quarto di
stagione (`applica_morale_checkpoint`), ed e' li' che il capitano e' stato messo: attenua
fino al 30% del malcontento dei compagni, e **lo peggiora se e' lui il primo scontento**,
perche' la qualita' va sotto zero.

Si moltiplica con l'attenuazione da mentalita' "bandiera" invece di sommarsi: sono due
modi diversi di reggere lo stesso colpo, e sommandoli un bandiera capitano sarebbe
diventato immune.

**Chi e' un buon capitano**: il suo morale e la sua freddezza (`mentality_composure`), meta'
e meta'. Non serve un attributo di leadership, che nei dati FC 26 non esiste — era la
ragione per cui la fascia era stata rimandata.

Il piccolo effetto in partita e' rimasto, perche' e' corretto e non costa niente. Ma il
peso vero e' al checkpoint, dove si accumula.

**Stato**: la migrazione e' applicata in produzione ed e' **inerte**. `teams.capitano`
nasce NULL e niente lo assegna in automatico, quindi l'attenuazione vale 1 e il checkpoint
calcola esattamente quello che calcolava prima. L'assegnazione automatica e l'interfaccia
arrivano col resto del lavoro tattico.

## 20. Due barre di familiarità, come in FM

Deciso col committente, che ha scelto questa strada fra tre.

**Il problema, misurato.** In Serie F, prima della modifica: familiarità media di lega
**66,1%**, 19 combinazioni squadra-modulo su 36 sotto soglia, e **23 squadre su 40 hanno
usato un solo modulo per tutta la stagione**. L'ultima riga non descrive una scelta
tattica: descrive la risposta razionale a una tassa da 3,5 punti di overall su tutti e
undici per cinque giornate. La familiarità non faceva contare le tattiche, faceva evitare
le tattiche — e con gli schemi personalizzati in arrivo sarebbe stata fatale: ogni ritocco
azzera la squadra, e nessuno userebbe la funzione due volte.

**Cosa fa FM.** La familiarità lì è per componente: disposizione, mentalità, ritmo,
ampiezza e libertà creativa hanno ognuna la sua barra, e cambiare un'istruzione muove solo
quelle collegate. Inoltre non sparisce quando cambi tattica, decade.

**Cosa abbiamo fatto.** Due barre, media 50/50 — lo stesso peso che avevano modulo e stile,
quindi nessuno spostamento di equilibrio.

| barra | cosa misura | memoria |
|---|---|---|
| **disposizione** | dove stanno gli undici | sì: indicizzata sullo schieramento, tornare al vecchio 4-4-2 ritrova il contatore |
| **indicazioni** | stile, ruoli, compiti | no: arretra in proporzione a quanto è cambiato |

La differenza è voluta. Uno schieramento è una cosa discreta a cui si torna; le indicazioni
sono un continuo in cui ci si sposta, e tenerne la memoria vorrebbe dire indicizzare ogni
combinazione di 23 elementi — una tabella che cresce senza che nessuna riga venga riusata.

**Eredità e arretramento** usano la stessa formula: `resa = max(0, 1 − 1,6 × distanza)`.

Schieramento (misurato su una squadra vera a barra piena):

| slot cambiati su 11 | barra di partenza |
|---|---|
| 1 | 80% |
| 2 — *due CM che diventano CDM* | 80% |
| 3 | 60% |
| 5 | 20% |
| 8 | 0% |

Indicazioni (23 elementi: lo stile, 11 ruoli, 11 compiti):

| indicazioni cambiate | barra dopo |
|---|---|
| 1 | 100% |
| 3 | 80% |
| 6 | 60% |
| 11 | 20% |

È il *«non fare troppe modifiche in una volta»* di Football Manager, reso numerico.

**Una trappola trovata e chiusa.** La prima versione scalava il *conteggio grezzo*: una
squadra con 21 partite col suo 4-4-2 faceva `21 × 0,71 = 15`, ancora sopra la soglia di 5,
quindi la variante nasceva già piena. L'eredità non mordeva mai proprio per chi gioca da
tempo lo stesso modulo, cioè esattamente chi dovrebbe sentirla. Ora si scala la **quota**,
già tagliata a 1.

**Una seconda, che avrebbe rotto la produzione.** `indicazioni_xp` nasceva vuota, quindi
quella barra sarebbe valsa 0 per tutti e la media avrebbe dimezzato la familiarità di ogni
squadra alla prima giornata dopo il deploy. La barra indicazioni assorbe quello che prima
era lo stile, quindi eredita il suo contatore. Verificato squadra per squadra: **0 squadre
su 40 cambiano, scarto massimo 0,000.**

**Stato**: schema e meccaniche applicate in produzione e inerti — `lineups.disposizione`,
`ruoli` e `compiti` nascono NULL, e con NULL si ricade sullo schieramento standard del
modulo. `engine/engine.js` usa le due barre solo se gli vengono passate. Manca
l'interfaccia.

## 21. Una posizione cambia dentro la sua linea, non fra linee

Correzione a una regola che avevo scritto sbagliata. Dicevo *«sale o scende di una linea
restando sulla propria corsia»*, e consentiva a una punta di scendere a CAM.

Segnalato dal committente con l'esempio giusto: **un 4-4-2 in cui una punta scende a CAM
non è più un 4-4-2, è un 4-4-1-1.** Un modulo diverso, con una familiarità diversa e un
nome che non corrisponde più a niente. Il modulo lo sceglie l'utente; lo schema
personalizzato lo *dettaglia*, non lo sostituisce.

La regola giusta: una posizione può stringersi al centro, allargarsi, alzarsi o abbassarsi
**dentro la propria linea**. In un 4-4-2 i due CM possono diventare CDM perché i
centrocampisti restano quattro. Le linee sono quelle di `REPARTO` in `engine/config.js`,
così «stessa linea» vuol dire la stessa cosa nel motore, in SQL e nell'interfaccia.

## 22. I compiti significano cose diverse a seconda del reparto

Stessa segnalazione, e va più a fondo. A un attaccante il compito difensivo diceva
*«resta dietro la linea della palla»*, che per una punta non vuol dire niente. Per lei il
compito difensivo è **andare addosso al portatore e rientrare** — e soprattutto ha un
altro prezzo.

Ogni compito ha ora due numeri suoi, per reparto:

| reparto | compito difensivo | peso | fiato | compito offensivo | peso | fiato |
|---|---|---|---|---|---|---|
| difensori | Bloccato | −0,24 | ×0,92 | Si sgancia | +0,26 | ×1,18 |
| centrocampisti | In copertura | −0,22 | ×1,05 | Si inserisce | +0,24 | ×1,20 |
| attaccanti | **Pressa e rientra** | **−0,13** | **×1,35** | Sul filo | +0,18 | ×0,90 |

Il caso che ha fatto nascere la tavola è l'ultima riga: aiuto piccolo, costo grande.
Misurato, due punte che pressano:

| compito alle punte | gol subiti | gol fatti | condizione punte |
|---|---|---|---|
| nessuno | 1,02 | 1,35 | 93,0 |
| **Pressa e rientra** | **0,97** | 1,25 | **85,3** |
| Sul filo | 1,03 | 1,41 | 96,3 |

**Due correzioni sono servite per arrivarci, entrambe istruttive.**

*Prima*: non aiutava per niente — anzi faceva subire di più (1,06 contro 1,02). La formula
sposta il peso di una linea alla volta, ma una punta ha `DEF 0` e `MID 0,05`: tutto quello
che lasciava l'attacco si fermava a centrocampo e alla difesa non arrivava nulla. Il
pressing però non è un arretramento, è lavoro difensivo fatto in avanti: una quota
(`versoDifesa`) arriva ora in difesa senza passare dal centrocampo.

*Seconda*: continuava a non aiutare, perché l'idoneità al compito si misura su *tackle
contro finishing* — e su quel metro qualunque attaccante è negato, quindi il compito
rendeva zero a chiunque lo si desse. Ma una punta non pressa perché sa contrastare: pressa
perché ha il fiato. L'idoneità di quel compito si misura ora sulla **stamina**, il che ha
anche un effetto gradito e gratuito: chi ha fiato regge il pressing, chi non ce l'ha si
spegne, perché il consumo per blocco è già modulato dalla stamina.

Il costo in fiato è mostrato nell'interfaccia accanto al nome del compito: si vede prima
di sceglierlo.

## 23. Un'opzione che non conviene mai non è una scelta

Il committente, guardando la scheda del pressing: *«il trade-off deve essere onesto, non può
essere che aiuta poco ma spende tantissimo altrimenti nessuno lo userà. Vedi sempre FM»*.
Aveva ragione due volte — la descrizione era pessima **perché i numeri lo erano**, e li avevo
misurati io stesso: 43,8% contro 42,4%, cioè una perdita secca in ogni scenario. In Football
Manager aggredire alto è fra gli approcci più forti, non una penitenza.

**Primo limite, strutturale.** `forzeLinee` calcola una *media pesata*. Dare peso difensivo a
una punta non aggiunge un difensore: diluisce la media con qualcuno che lì vale meno. Con quel
canale il pressing non poteva aiutare, per quanto lo si tarasse. Ma pressare non è mettere un
corpo in area, è **togliere il pallone**: e quel canale esiste già ed è il controllo, che
dipende dallo scarto fra i centrocampi e moltiplica gli xG di entrambe le squadre. I compiti
hanno ora un secondo canale, in punti di linea, nella stessa forma additiva della familiarità
e dello stile.

**Secondo, e più importante: stavo misurando la cosa sbagliata.** Dentro i novanta minuti la
condizione scende di otto punti, quindi il «si spegne col fiato» è quasi inerte. Il conto del
pressing si paga **fra una partita e l'altra**, perché la condizione si porta dietro e il
recupero non tiene il passo. Una prova su partita singola non poteva vedere niente, e infatti
mi ha fatto oscillare per quattro tarature.

Su trenta giornate, punti normalizzati su 38:

| punte | punti/38 | gol fatti | subiti | condizione a fine stagione |
|---|---|---|---|---|
| neutro | 40,2 | 0,98 | 1,45 | 87,3 |
| pressing, stamina media | 40,3 | 0,93 | 1,38 | 83,2 |
| **pressing, stamina 90** | **42,1** | 0,98 | 1,35 | 86,2 |
| pressing, stamina 55 | 37,9 | 0,89 | 1,42 | 79,2 |

Conviene se hai le gambe, è indifferente con punte normali, ti punisce se le gambe non ci
sono. Chiede rosa profonda e rotazione, esattamente come in FM.

Tutti e sei i compiti sono ora vivi almeno in uno scenario:

| compito | effetto misurato |
|---|---|
| Bloccato (dif.) | +1,1 punti percentuali, subiti 1,02 → 0,98 |
| Si sgancia (dif.) | sostanzialmente neutro: segna di più, subisce di più |
| In copertura (cen.) | +1,2, subiti 1,02 → 0,95 |
| Si inserisce (cen.) | +0,3, gol fatti 1,35 → 1,47 |
| Pressing alto (att.) | +1,9 con stamina alta, −2,3 con stamina bassa |
| Sul filo (att.) | +1,3, segna di più ed è esposto dietro |

`tools/validazione/prova-compiti-stagione.mjs` conserva la prova su stagione: è quella che
conta, e la lezione è che per un costo che si accumula la partita singola è il metro sbagliato.

**Le descrizioni ora dicono prima cosa si guadagna.** Erano scritte per assecondare numeri
sbagliati — *«aiuta poco dietro, ma costa molto fiato»* è una scheda che nessuno sceglierebbe,
ed è giusto così: era la descrizione onesta di un'opzione morta.

## 24. L'energia andava rivista, e il problema era un gradino

Domanda del committente dopo il lavoro sui compiti: *«avendo fatto tutte queste modifiche,
conviene rivedere anche l'utilizzo dell'energia?»*. Sì, e quello che è venuto fuori era più
grosso della taratura.

**L'economia dell'energia è tesa.** Un titolare consuma ~45,7 di condizione a partita
(6 blocchi) e ne recupera 36: saldo **−9,7**, cioè regge circa **tre partite di fila** prima
di scendere sotto la soglia di sostituzione. Ci avevo aggiunto sopra moltiplicatori fino a
×1,20, che quasi raddoppiano il drenaggio: il compito costava due volte quello che comprava.

**Ma la causa vera era un'altra.** `fattoreCondizione` era una **scala a gradini**: 85 valeva
1,000 e 84,9 valeva 0,975. Un decimo di punto di fiato costava il 2,5% di overall a tutti e
undici — cioè ~1,9 punti su ogni linea. Finché niente nel gioco spostava la condizione di
poco il gradino non si notava; coi compiti che moltiplicano il consumo è diventato dominante.

Misurato: `Si inserisce` dava **+1,09 punti di attacco** e segnava **0,99 gol contro gli 0,99**
di chi non lo usava. Il vantaggio c'era ed era cancellato per intero dal salto del gradino.

`fattoreCondizione` è ora **continua** e passa esattamente per gli stessi punti della versione
validata (85, 70, 55, 40, 25): interpola invece di saltare. Il criterio del motore non si
muove (2,87 gol, 13,46 tiri, 23,3% pareggi, 46,1% vittorie casa).

**Un secondo errore, nel banco di prova.** Rigeneravo l'avversario fresco a ogni giornata,
quindi la squadra in esame era sistematicamente quella stanca: segnava 0,99 e subiva 1,43.
Con quel metro difendere valeva troppo e attaccare troppo poco, e stavo per tarare su un
artefatto. Ora vivono la stagione entrambe.

**Risultato, su trenta giornate** (punti normalizzati su 38, entrambe le squadre persistenti):

| compito | punti | gol fatti | subiti | |
|---|---|---|---|---|
| nessuno | 60,6 | 1,41 | 1,07 | |
| Bloccato | 61,8 | 1,37 | 0,98 | +1,2 |
| Si sgancia | 61,1 | 1,43 | 1,09 | +0,6 |
| In copertura | 60,9 | 1,40 | 1,03 | +0,3 |
| Si inserisce | 60,4 | 1,46 | 1,11 | −0,2 |
| Pressing alto | 63,2 | 1,42 | 0,98 | +2,7 |
| Sul filo | 61,1 | 1,51 | 1,12 | +0,6 |

Nessuno è dominato, e il pressing resta legato al fiato: con punte da stamina 90 vale +2,6
punti, con punte da stamina 55 ne vale −0,8.

**La conseguenza leggibile**, che prima non esisteva — quante partite di fila regge un titolare:

| compito | partite |
|---|---|
| Bloccato, Sul filo | 4 |
| nessuno, In copertura, Pressing alto | 3 |
| Si sgancia, Si inserisce | 2 |
| Pressing con stamina 92 / 52 | 4 / 2 |

È la gestione della rosa che in FM fa parte del gioco: aggredire chiede profondità.

## B. Le squadre del PC si sfaldano fra le stagioni

Scoperto misurando LegaBot: le squadre controllate dal PC non rinnovano i contratti e in
tre stagioni sono finite 13 punti di overall sotto quella umana, con rose riempite di
giocatori sotto 55. Finché sono solo avversarie di prova non è grave, ma se una lega umana
avrà squadre abbandonate rimpiazzate dal PC diventeranno vittime sacrificali e falseranno
la classifica. **Task a sé, non del sistema tattico.**

## C. Il vivaio non ha gli attributi per i profili

I 210 giocatori del vivaio non hanno 8 dei 10 attributi richiesti, quindi sono immuni
all'effetto "interprete". Sette sono già tesserati in Serie F. Non è un bug bloccante —
il punto 8 lo gestisce senza inventare nulla — ma la pipeline del vivaio dovrebbe
generare anche quegli attributi.

## D. Da implementare

1. ~~`forzeLinee` legge i profili~~ — fatto
2. ~~L'Edge Function passa i profili al motore~~ — fatto
3. Schema: piano per giornata + identità di squadra, migrazione e RLS.
   **Il piano avversario non deve essere leggibile prima della simulazione**, esattamente
   come le formazioni (CLAUDE.md §6).
4. UI, dietro un flag per abilitarlo su una lega sola.
5. Familiarità col piano? Oggi esiste `formation_xp` per modulo e stile. Se un piano
   tattico nuovo costasse anche in familiarità, cambiare assetto ogni giornata sarebbe
   più caro — da valutare, interagisce col costo di snaturamento.
