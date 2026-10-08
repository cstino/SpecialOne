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

## 25. I pezzi erano tarati, il sistema no

Ogni canale era stato misurato da solo e stava nella forbice giusta. Messi
insieme, no — e si vede solo provandoli insieme.

Prima taratura, A contro un avversario che lascia scoperta una fascia:

| A | punti/38 |
|---|---|
| neutro | 60,5 |
| solo ruoli sensati | **72,0** |
| tutto giusto | 77,2 |
| tutto sbagliato | 54,9 |

**22,3 punti di scarto**, tre volte e mezzo il metro di Football Manager. E il
colpevole erano i **ruoli**: da soli valevano +11,5.

**La causa.** Avevo tarato `VALORE_IDONEITA` per GIOCATORE — un interprete
giusto valeva +2,5 punti percentuali — ma l'effetto è per SQUADRA. Undici ruoli
sensati si sommano, e undici volte «poco» fa «molto». È lo stesso errore di
prospettiva del morale, dove per fortuna avevo misurato subito l'effetto di
squadra; qui no.

**La correzione**: `VALORE_IDONEITA` da 2,6 a **0,9**, `SCALA_CORSIA` da 40 a
**20**. Il morale non si tocca: era già ancorato al dato FM-Arena.

Dopo:

| leva da sola | guadagno |
|---|---|
| morale alto | +1,5 |
| corsia giusta | +3,0 |
| ruoli sensati | +3,8 |
| **tutto insieme** | **+8,4** |
| tutto sbagliato | −2,3 |

**10,7 punti di scarto totale.** Il metro di FM sommato è 6,4 (spread fra la
migliore e la peggiore tattica) + 3,8 (morale) = **10,2**. E nessuna leva
domina: 1,5 / 3,0 / 3,8.

I criteri dei singoli pezzi reggono ancora, il che era il rischio della
ritaratura:

- il ruolo naturale resta **esattamente neutro** (44,9% contro 44,9%);
- l'interprete giusto vale **+2,5** sul ruolo sbagliato, quello sbagliato −1,6;
- leggere la corsia scoperta vale **5,8 punti** contro leggerla male.

`tools/validazione/prova-sistema-tattico.mjs` conserva la prova d'insieme. La
lezione vale oltre questo caso: **tarare i pezzi uno alla volta non dice come si
comporta il sistema**, e in un gioco dove le leve si scelgono tutte insieme è il
totale che l'utente sente.

## 26. Chi non tocca niente non deve perdere

Decisione del committente dopo aver parlato con gli altri partecipanti: non
tutti vogliono investire energie. *«Le tattiche devono essere come in EA FC:
si possono tranquillamente scegliere quelle predefinite, oppure chi vuole può
dare tutte le indicazioni che ritiene. Chi le lascia predefinite non è
svantaggiato, ma chi ci lavora può ottenere risultati migliori — e anche
peggiori.»*

**Il dato diceva che aveva ragione.** Misurato prima della modifica: chi non
apriva la schermata era **8,4 punti su 38 dietro** a chi ci lavorava. Le
tattiche erano di fatto obbligatorie.

**Cosa fa EA FC.** I *Tactical Preset* esistono dichiaratamente per «chi non
vuole spendere tempo a personalizzare». E soprattutto: un giocatore in un ruolo
che non gli è familiare prende una **penalità del 10%** sul posizionamento
difensivo. Non c'è un premio per il ruolo azzeccato — c'è un **costo per quello
sbagliato**. È l'asimmetria che rende il default competitivo.

**Due correzioni, e la seconda era un difetto vero.**

*Prima*: l'idoneità al ruolo diventa **solo penalità**. Chi non assegna ruoli non
paga niente; chi mette un giocatore in un ruolo che non sa fare, sì. Il valore
tattico di un ruolo resta dov'era — in DOVE mette il giocatore (corsia e linea),
che è una scelta a due facce — non nel premio per averlo azzeccato.

*Seconda*: i compiti **aggiungevano forza** invece di spostarla. Il pressing alto
sommava `+0,22 +1,40 −0,35 = +1,27` netti, e quasi tutti gli altri erano
positivi. Misurato: **chi smanettava a caso batteva di 1,7 punti chi lasciava il
predefinito**. Ora ogni vettore somma a zero fra le tre linee — la stessa regola
che lo stile di gioco seguiva già nel motore.

**Il risultato:**

| A | punti/38 | rispetto al default |
|---|---|---|
| **lascia tutto predefinito** | **61,6** | — |
| tocca tutto a caso | 59,3 | **−1,8** |
| solo ruoli sensati | 61,6 | +0,0 |
| solo corsia giusta | 64,8 | +3,2 |
| lavora bene su tutto | 66,8 | **+5,2** |
| sbaglia tutto deliberatamente | 49,0 | −12,6 |

Chi non tocca niente sta al riferimento. Chi prova senza studiare perde poco.
Chi legge l'avversario guadagna. Chi mette ogni giocatore nel ruolo che sa fare
peggio, paga — ma è una configurazione che non si raggiunge per distrazione.

I criteri dei pezzi reggono: il ruolo naturale resta esattamente neutro,
l'interprete sbagliato costa **−2,7**, leggere la corsia scoperta vale **4,6
punti**. `simulate-reale` invariato.

`tools/validazione/prova-default-non-svantaggiato.mjs` conserva la misura che
conta: **chi smanetta a caso non deve battere chi non tocca niente**.

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

## C. ~~Il vivaio non ha gli attributi per i profili~~ — risolto su `main`

Risolto dalla migrazione `20260916100000_vivaio_attributi_completi.sql` (commit 248aaf4):
i prospetti nascono con tutti gli attributi, come i giocatori del catalogo. Testo originale:

I 210 giocatori del vivaio non hanno 8 dei 10 attributi richiesti, quindi sono immuni
all'effetto "interprete". Sette sono già tesserati in Serie F. Non è un bug bloccante —
il punto 8 lo gestisce senza inventare nulla — ma la pipeline del vivaio dovrebbe
generare anche quegli attributi.

## D. Da implementare

1. ~~`forzeLinee` legge i profili~~ — fatto
2. ~~L'Edge Function passa i profili al motore~~ — fatto
3. ~~**Il piano avversario non deve essere leggibile prima della simulazione**~~ — verificato,
   non serviva scrivere niente. Schema, ruoli e compiti stanno su `lineups`, che ha già la
   politica giusta (`private.lineup_visibile`): vedi una formazione solo se è tua o se quella
   giornata è già simulata. Provato impersonando un utente vero: la propria formazione della
   19 si vede con lo schema, quella dell'avversario dà **0 righe**, quella della 18 già
   simulata si vede. Le altre superfici nuove (`indicazioni_xp`, `formation_xp.disposizione`)
   contengono solo storia di partite già giocate, e `teams.capitano` è pubblico come nel calcio.
4. ~~Flag per abilitarlo su una lega sola~~ — fatto: `leagues.tattiche_attive`, spento di
   default, si accende con `public.imposta_tattiche_attive` e **solo l'amministratore**.
   Non è un flag da sviluppatore da togliere poi: una lega avviata può legittimamente non
   volere le tattiche a metà stagione.

   L'interruttore vale in tre punti, non solo nel motore — le altre due erano fughe vere:
   - `salva_formazione` a interruttore spento **ignora** schema, ruoli e compiti. Non è
     pignoleria: la familiarità è indicizzata sullo schieramento, quindi salvare una variante
     che il motore ignora creerebbe un contatore per una forma mai giocata davvero;
   - il **capitano** agiva su `applica_morale_checkpoint`, che gira sempre e non passa dal
     motore. Era la più insidiosa, perché quel checkpoint tocca i rinnovi.
5. Familiarità col piano? Oggi esiste `formation_xp` per modulo e stile. Se un piano
   tattico nuovo costasse anche in familiarità, cambiare assetto ogni giornata sarebbe
   più caro — da valutare, interagisce col costo di snaturamento.

## 27. La tattica è l'identità della squadra, non la mossa della giornata — 25 settembre 2026

Ripensamento del committente, che **supera il punto 26 dove i due sono in conflitto**:
*«le tattiche si fanno all'inizio e sono il modo in cui la squadra impara a giocare. Sono
modificabili nel tempo, ma non voglio che ognuno debba fare modifiche a ogni giornata. Le
istruzioni un partecipante le dà, se vuole, per applicare il metodo di gioco che ritiene
migliore.»*

**Cosa cambia.**

1. **Il valore di una scelta tattica nasce dall'accordo fra metodo e rosa**, non dalla
   lettura dell'avversario. Una mezzala a cui si chiede di inserirsi rende se ha il profilo
   dell'incursore, rende meno se non ce l'ha.
2. **Il ruolo azzeccato dà un bonus, quello sbagliato una penalità.** Cade la regola "solo
   penalità" del punto 26. Resta il vincolo misurabile, che è quello che conta davvero:
   *chi smanetta a caso non deve battere chi non tocca niente*
   (`prova-default-non-svantaggiato.mjs`). Il predefinito resta il riferimento neutro.
3. **"Dove attacchiamo" diventa una scelta di identità** legata alla propria rosa (attacco
   dove ho l'esterno forte), non più la lettura della fascia scoperta dell'avversario.
4. **La familiarità delle indicazioni è il freno naturale**: cambiare spesso la fa
   scendere, quindi chi ritocca ogni giornata paga senza bisogno di vietarlo. Da rivedere
   insieme al punto F.

**Due pagine nel menu "schema di gioco"** (sostituisce il punto A):

| pagina | contenuto |
|---|---|
| **Indicazioni individuali** | tocchi una posizione, scegli ruolo e compito. Ogni ruolo chiede un **profilo di 2-4 attributi** (oggi uno solo, su quattro); accanto ai giocatori un indicatore di idoneità stile FC (+ / ++) |
| **Indicazioni di squadra** | stile di gioco (i 7 esistenti), dove attacchiamo (spostato qui), **linea difensiva** (bassa / media / alta, nuova), **ampiezza** (stretta / normale / larga, nuova) |

Per ogni indicazione di squadra vale lo stesso principio dei ruoli: l'opzione predefinita
è neutra, le altre sono a due facce e rendono se la rosa è adatta (il contropiede vuole
attaccanti veloci, la linea alta centrali veloci, l'ampiezza larga esterni che crossano).

**Voti in pagella, stile SofaScore.** Ogni giocatore riceve un voto da 1 a 10 costruito
dalle azioni riuscite e sbagliate, non estratto a caso. Tutti i ruoli pesano uguale: un
difensore o un portiere possono essere il migliore in campo. Serve a capire se un giocatore
è adatto al proprio metodo, quindi il voto dipende anche dall'idoneità a ruolo, compito e
indicazioni di squadra. Vincoli:
- oggi il motore **non** ha azioni individuali: `distribuisci()` divide i totali di squadra
  per peso di posizione × attributo. Un voto costruito su quelle statistiche ricalcherebbe
  l'overall. Serve uno strato "pagella" che generi azioni riuscite/sbagliate per giocatore;
- lo strato usa un **RNG separato**, come gli infortuni: gol e risultati restano quelli del
  motore validato;
- il segnale vero è la **media voto** su più partite, da mostrare nella scheda.

**Ordine di lavoro concordato:**
1. indicazioni individuali: profili dei ruoli su più attributi, bonus/penalità, indicatore
2. indicazioni di squadra: stile e dove attacchiamo spostati, linea difensiva e ampiezza nuove
3. voti in pagella
4. ritaratura del sistema intero, con la prova del predefinito
5. preset: combinazioni pronte delle due pagine

## 28. I ruoli leggono il profilo vero, e premiano — 28 settembre 2026

Primo pezzo del punto 27. Decisioni del committente nella stessa sessione:
- l'idoneità al ruolo usa gli attributi FC 26 **solo** per dire chi è adatto; il motore
  resta a overall (decisione del 28 settembre sulla chat dell'allenamento), e l'effetto
  è uno scarto di overall come quello che c'era già;
- il ruolo vale **anche fuori posizione**: un centrale schierato da schermo è confrontato
  con i centrocampisti. Non cancella mai il malus di posizione (giallo = −9% di overall,
  il ruolo vale al massimo ±2 punti);
- "Esterno di rientro" diventa **"Esterno difensivo"**, anche nella chiave
  (`esterno_difensivo`, migrazione `20260928100000`);
- la **resistenza** non entra nei profili: la conta già il motore nella fatica.

**Profili.** Ogni ruolo non base chiede 4 attributi (`engine/ruoli.js`). Il ruolo base di
ogni posizione (centrale, terzino, mediano, esterno, punta) non ha profilo ed è neutro.

**Due trappole, misurate e chiuse** (`tools/validazione/taratura-ruoli.mjs`):
1. *Senza il collega tipico* il profilo si misura contro la media del giocatore stesso, e un
   centrale è sempre "più marcatore che altro": il marcatore converrebbe a tutti.
2. *Senza il livello*, anche confrontando coi colleghi, il profilo resta legato all'overall:
   correlazione **0,52** per il finalizzatore, 0,43 per il terzino interno. Overall travestito.

La soluzione: lo scarto atteso per ruolo è una **retta sull'overall** calcolata sui colleghi
veri (3.463 giocatori di `pool-reale.json`). Dopo: correlazione con l'overall **0,00** in tutti
i ruoli; circa il 18% dei colleghi è "++" e altrettanti "−−"; nessun ruolo è il migliore per
tutti (fra i centrali 49% marcatore, 51% impostatore).

**Bonus e malus**, `VALORE_IDONEITA = 2` punti di overall a idoneità piena.

**Misura su giocatori veri** (`tools/validazione/prova-ruoli-reali.mjs`, 40.000 partite per
riga, 4-4-2; le rose sintetiche hanno 5 attributi e lì l'idoneità è zero per tutti):

| A | punti/38 | rispetto a chi non tocca niente |
|---|---|---|
| non tocca niente | 60,9 | — |
| ruolo base ovunque | 60,9 | 0,0 |
| ruoli a caso | 60,4 | −0,6 |
| tocca tutto a caso (ruoli, compiti, corsia) | 59,8 | −1,1 |
| sa leggere i suoi giocatori | 66,9 | **+5,9** |
| sbaglia apposta | 53,3 | −7,7 |

In 4-3-3 (8.000 partite): +6,9 e −8,9. Il vincolo regge. I ruoli ora sono la leva più
grande del sistema, più del morale (3,8) e della corsia (4,6): è voluto, perché è la leva
d'identità del punto 27, ma la ritaratura del sistema intero (task 4) deve ripartire da qui.

Con 8.000 partite "tocca tutto a caso" dava +0,4: era rumore (±0,6). Per le prove fra
strategie vicine servono decine di migliaia di partite.

`simulate-reale` invariato: 2,87 gol · 13,46 tiri · 23,3% pareggi · 46,1% vittorie casa.

**Frontend.** `src/lib/tattica.ts` ha la stessa formula, **generata** dallo script di taratura
(`--scrivi`), che poi verifica che frontend e motore diano lo stesso numero su tutti i
giocatori (65.797 confronti). I segnalini "++" / "+" / "−" / "−−" stanno **solo sulle
magliette della formazione**, accanto all'overall, e solo se la posizione ha un ruolo.
Decisione del committente: lo Schema Tattico è lo schema della squadra, fatto di posizioni,
ruoli e compiti, non di giocatori; i segnalini appartengono ai giocatori. Nello stesso
giro il costo dei compiti si legge in "stanchezza" invece che in "fiato".

## 29. Moduli personalizzati — 29 settembre 2026

Richiesta del committente: uno schema modificato si salva con un nome e compare nel menu dei
moduli della Formazione. Decisioni sue:
- si salva **tutto**: posizioni, ruoli, compiti e dove si attacca;
- **massimo 3** per squadra; al quarto se ne sovrascrive uno o se ne elimina uno;
- ognuno vede **solo i suoi** (RLS sulla tabella, scrittura solo dalle funzioni).

Tabella `public.moduli_personalizzati`, funzioni `salva_modulo_personalizzato` (con
`p_sostituisci` per sovrascrivere) ed `elimina_modulo_personalizzato`, migrazione
`20260929100000`. Stessi controlli di `salva_formazione` su posizioni, ruoli e compiti.

Il modulo salvato è un modello: richiamarlo riempie lo schema, e per la partita conta la
formazione salvata. La familiarità non ha bisogno di niente, perché `formation_xp` è già
indicizzata sullo schieramento: tornare a un modulo salvato ritrova il suo contatore.

Nello Schema Tattico il pulsante "Salva come modulo personalizzato" compare quando lo schema
differisce dal modulo standard; se coincide con uno salvato, compare "Salvato come «nome»".
Nel menu dei moduli della Formazione i salvati stanno in una sezione "I tuoi moduli", con la
"x" per eliminarli, e il selettore mostra il nome del modulo personalizzato in campo.

## 30. La pagina "Squadra": stile, dove attacchiamo, linea, ampiezza, portiere — 29 settembre 2026

Task 2 del punto 27, sulla tabella proposta al committente e approvata. Lo Schema Tattico ha
due schede: **Giocatori** (campo, ruoli, compiti) e **Squadra**. Lo stile di gioco esce dalla
Formazione e va qui.

**Regola comune.** L'opzione predefinita (equilibrato, ovunque, linea media, ampiezza normale,
portiere normale) è neutra. Le altre spostano forza fra i reparti e chiedono un profilo alla
rosa, con la stessa misura dei ruoli (collega tipico dello stesso livello, punto 28):
`engine/squadra.js`, profili tarati da `taratura-ruoli.mjs` (correlazione con l'overall ≤ 0,02).

| indicazione | sposta | chiede |
|---|---|---|
| linea alta | DEF −1, MID +1 | difensori veloci |
| linea bassa | DEF +1, MID e ATT −0,5 | difensori da marcatura e forza |
| ampiezza larga | fasce +0,8, centro −0,8 | esterni e terzini che crossano e corrono |
| ampiezza stretta | centro +0,8, fasce −0,8 | centrocampisti tecnici |
| stile (6 non neutri) | come prima (STILI) | contropiede: attaccanti veloci · possesso: centrocampisti tecnici · fasce: esterni che crossano · recupero veloce: aggressività e intercetti · diretto: punte forti di testa e fisico · blocco basso: difensori da marcatura e forza |
| portiere-libero | — | uscite, posizionamento, rinvii; con la linea alta copre i difensori (`COPERTURA_LIBERO`) |

Valore a idoneità piena: 2 punti di overall (1,5 il portiere), come i ruoli.

**Dove attacchiamo guarda la propria squadra** (`engine/corsie.js`): rende sulla corsia dove si
hanno i giocatori più forti, costa su quella debole. Non legge più l'avversario.

**La formazione ereditata tiene la tattica.** Chi salta un salvataggio riceve la formazione della
giornata prima: prima si ereditavano solo modulo e giocatori, ora anche schema, ruoli, compiti e
indicazioni. È la conseguenza diretta di "la tattica è l'identità".

**Database** (migrazione `20260929110000`, applicata): colonne `linea_difensiva`, `ampiezza`,
`ruolo_portiere` su `lineups`, `indicazioni_xp` e `moduli_personalizzati`; `salva_formazione` e
`salva_modulo_personalizzato` con tre (quattro) parametri in più, firme vecchie tolte; la barra
Indicazioni conta 27 elementi. Funzioni ricostruite dalla definizione live. Verificato che il
salvataggio come lo fa l'app di produzione (undici parametri) funziona ancora, in rollback.

**Misura** (`prova-ruoli-reali.mjs`, 40.000 partite, 4-4-2, rose vere):

| A | rispetto a chi non tocca niente |
|---|---|
| solo ruoli giusti | +5,9 |
| solo stile giusto | +2,2 |
| solo ampiezza giusta | +1,5 |
| solo linea giusta | +0,9 |
| solo corsia giusta | +0,2 |
| linea alta + portiere-libero | +0,1 |
| **tocca tutto a caso** | **−0,1** |
| sa leggere la sua rosa (tutto) | +10,6 |
| sbaglia apposta (tutto) | −10,6 |

Il vincolo regge. Da rivedere nel task 4: la corsia è quasi inerte (le corsie di una rosa vera
differiscono poco), il portiere-libero vale poco, e lo scarto totale di 21 punti su 38 fra tutto
giusto e tutto sbagliato va confrontato col limite del punto 6. `simulate-reale` invariato.

## 31. Voti in pagella, stile SofaScore — 1° ottobre 2026

Task 3 del punto 27. Decisione del committente: come SofaScore, tutti i reparti pesano uguale e
anche un difensore o un portiere possono essere il migliore in campo.

**Come nasce il voto** (`engine/pagelle.js`). Dopo la partita, con un generatore casuale suo
(seme separato: gol e risultato non cambiano), ogni giocatore con almeno 15 minuti riceve:
- le **azioni** che il motore gli ha già assegnato (passaggi, contrasti, dribbling, tiri) più
  gli **interventi difensivi**, che il motore non distribuiva (senza, un difensore aveva due
  contrasti a partita e poteva solo perdere punti);
- per ogni azione, **riuscita o errore**, secondo il suo attributo, il reparto avversario che ha
  davanti e il suo **scarto tattico** (`lineup.tattica`: ruolo, indicazioni di squadra, morale);
- gol, assist, tiri in porta, parate, gol subiti, porta inviolata, cartellini, risultato.

I passaggi pesano per la **precisione rispetto all'attesa**, non uno per uno: un centrocampista
ne tenta 60, e contarli singolarmente dava a chi passa molto un voto a caso. Chi gioca poco
resta vicino al 6. Sotto i 15 minuti: "SV".

**Taratura** (`tools/validazione/prova-pagelle.mjs`, 1.500 partite con rose vere):

| misura | valore | riferimento |
|---|---|---|
| media voti | 6,80 | SofaScore ~6,8 |
| scarto | 0,65 | |
| 90% dei voti | 5,9 – 8,0 | |
| migliore in campo | ~8,2 (7,7–8,9) | |
| MVP per reparto | GK 11% · DEF 30% · MID 29% · ATT 30% | titolari: 9 · 36 · 27 · 27 |
| interpreti adatti / inadatti | 6,84 / 6,65 | il segnale della media voto |

Il migliore in campo viene dalla squadra che vince nel 97% delle partite non pareggiate: più che
su SofaScore. Da rivedere se in gioco sembra troppo legato al risultato.

**Dove si vedono.** Tabella `public.pagelle` (migrazione `20261001200000`, applicata; scritta
dalla Edge Function dopo `registra_risultato_partita`, senza toccarla). Pagina partita: card
"Migliore in campo" con le tre azioni che spiegano il voto, colonna VOTO subito dopo il nome.
Rosa: colonna MV (media voto della stagione). Scheda giocatore: media voto, volte migliore in
campo, ultimi cinque voti. Colori SofaScore in `src/lib/voti.ts`.

Le pagelle nascono solo con l'Edge Function del branch: finché in produzione gira quella di
`main`, la tabella resta vuota e le pagine non mostrano voti (senza errori).

## 32. Cambi come nel calcio vero: 3 soste più l'intervallo — 2 ottobre 2026

**Prima**: il motore cambiava solo al 45', 60' e 75' (fine dei blocchi 3, 4, 5),
massimo 2 per volta, e l'intervallo valeva come una delle tre finestre. In
produzione (736 partite) i cambi cadevano tutti e soli a quei tre minuti.

**Regola** (IFAB, cinque cambi): massimo 5 cambi e 3 interruzioni di gioco per
farli; l'intervallo e la pausa prima dei supplementari non contano.

- Motore (`engine/engine.js`, `config.js`): `lineup.soste`; all'intervallo esce
  solo chi è sotto `SOGLIA_CAMBIO_INTERVALLO` (65), al massimo
  `MAX_CAMBI_INTERVALLO` (1); anche il cambio per infortunio consuma una sosta, e
  senza soste libere l'infortunato non si sostituisce. Dopo il 75' una finestra
  con più cambi a volte si divide in due soste (`QUOTA_SOSTA_DIVISA`, 0,5). Flusso
  casuale proprio (`seedCambi`), il motore restituisce `cambiInPartita`.
- Cronaca (`simula-giornata`): `minutiCambi` dà a ogni sosta un minuto vero
  vicino al confine del blocco (stanchezza 56'-70' e 71'-85', l'ultima di una
  finestra divisa 82'-89', infortuni dentro il loro blocco); `finestreInCampo` e
  `adattaAiMinutiInCampo` tengono gol, assist, tiri e cartellini dentro i minuti
  in cui il giocatore era in campo; i minuti giocati (tabellino, pagelle)
  seguono il minuto vero. Anche i cartellini non cadono più a fine blocco.
  L'effetto del cambio sulla forza resta al confine del blocco: lo scarto è al
  massimo di 10-14 minuti, dentro la risoluzione del motore (blocchi da 15').

**Numeri** (`tools/validazione/prova-cambi.mjs`, banco della cronaca su 1.800
partite): 4,3 cambi per squadra; intervallo 19%, 51'-60' 15%, 61'-70' 28%,
71'-80' 18%, 81'-90' 14%, infortuni del primo tempo 5%. Nessun evento fuori dai
minuti in campo, nessuna squadra oltre 5 cambi o 3 soste.

**Validazione** (`simulate-reale`, riga PRODUZIONE): 2,87 gol · 13,46 tiri ·
22,6% pareggi · 46,9% casa. Il pareggio esce di 0,4 dal target sul seme della
suite; su sei semi la media è 23,2% col motore nuovo e 23,1% col vecchio, che
scende a 22,9% su due semi: è rumore attorno al bordo, non un effetto dei cambi.
Segnalato al committente.

**Risolto al punto 33.** ~~Aperto, non legato ai cambi~~: nel ramo i gol da calcio piazzato
(`engine/piazzati.js`) si aggiungono a `golC/golO` dopo il ciclo dei blocchi e
non entrano in `golPerBlocco`: la cronaca non li racconta e il parziale dei 90'
li esclude. Su `main` i piazzati non ci sono e i conti tornano (238 partite su
238). Va risolto prima di distribuire l'Edge Function del ramo.

## 33. Calci piazzati dentro i blocchi — 2 ottobre 2026

**Prima**: `calcolaPiazzati` girava una volta a fine partita e i suoi gol si
sommavano a `golC/golO`. Tre difetti: la cronaca non li raccontava (nella live
il punteggio sarebbe stato sbagliato), nessun giocatore ne risultava marcatore,
e i supplementari si decidevano su un pari al 90' calcolato senza quei gol.

**Ora** (`engine/engine.js`, `engine/piazzati.js`): i piazzati si calcolano
blocco per blocco, dopo i gol su azione, sulla formazione in campo in quel
momento. Pressione = xG del blocco / (`XG_RIFERIMENTO_PIAZZATI` / 6); le
frequenze sono scalate di 1/6 col nuovo parametro `quota` di `calcolaPiazzati`
(conversioni e scelte invariate; senza `quota` si comporta come prima). Il
motore restituisce `piazzatiInPartita` (blocco, marcatore, tipo, `battitore`);
`marcatori()` sceglie solo i marcatori dei gol su azione. Nei supplementari
ora ci sono anche i piazzati (prima no). La cronaca (`simula-giornata`) li
trasforma in gol con `piazzato` e l'assist di chi ha battuto; la telecronaca
ha frasi proprie per angolo, punizione diretta e punizione messa in mezzo.

**Numeri**: piazzati 0,97 gol a partita prima e dopo (sei semi); PRODUZIONE
2,87 gol · 13,42 tiri · 23,0% pareggi · 45,8% casa, tutto nei target; prova
del predefinito −1,0 punti per chi smanetta a caso. Banco della cronaca su
1.800 partite: gol in cronaca = risultato, parziale dei 90' = motore,
supplementari solo da un pari vero.

## 34. Lo stile decide come si gioca, non solo chi è più forte — 2 ottobre 2026

**Il problema** (segnalato dal committente: «se metto difesa a oltranza devo
fare pochi tiri»). Lo stile spostava solo 1-2 punti di forza fra i reparti, e
tutte le statistiche ne derivavano: fra gli stili 1-2 tiri e 2-4 punti di
possesso di differenza, invisibili in una partita.

**La scelta** (B, dentro il task 4): lo stile cambia davvero la partita, con
tre leve nuove (`STILI_PARTITA` in `config.js`, `identitaStile` nel motore):

- **ritmo** della partita, media dei due stili, moltiplica gli xG di entrambe le
  squadre (blocco basso 0,80, possesso 0,90, contropiede 0,95, fasce 1,04,
  diretto 1,06, recupero veloce 1,10). Simmetrico: non regala niente in media,
  cambia la varianza;
- **possesso** mostrato (e passaggi, contrasti, dribbling) spostato dallo stile;
- **volume dei tiri** a parità di xG: cambia il conteggio dei tiri, mai i gol.

`RITMO_NORMA` e `TIRI_NORMA` riportano a 1 la media sul mix di stili misurato
nelle leghe. Senza stile (suite storica) nessun effetto.

**Il diretto era già il più forte** (+2,9 punti su 38 contro equilibrato, prima
di questa modifica): un punto d'attacco vale circa tre punti di centrocampo
(xG +9% contro ctrl ~2,8% per parte), quindi la somma zero in punti non è
neutra. Bilanciato sull'effetto: da {0, −1,5, +1,5} a {0, −1,5, +0,9}.

**Numeri** (stagioni vere, stesso avversario equilibrato, 6.600 partite per stile):

| stile | tiri | possesso | passaggi | punti/38 vs equilibrato, pari forza | squadra più debole di 4 |
|---|---|---|---|---|---|
| equilibrato | 12,0 | 53% | 507 | — | — |
| contropiede | 10,2 | 43% | 410 | +1,2 | +0,6 |
| possesso palla | 10,2 | 64% | 613 | −0,2 | −0,4 |
| fasce | 13,9 | 52% | 500 | +1,4 | −0,3 |
| recupero veloce | 13,8 | 57% | 546 | +0,1 | −1,2 |
| diretto | 15,3 | 46% | 438 | +0,5 | −0,6 |
| blocco basso | 8,2 | 41% | 397 | −0,4 | **+2,0** |

Nessuno stile domina a pari forza (tutti entro ±1,4, il rumore è ~0,6); chi è
più debole guadagna a chiudere la partita (blocco basso +2,0) e perde ad
aprirla. PRODUZIONE: 2,85 gol · 13,37 tiri · 23,7% pareggi · 45,8% casa, tutto
nei target; nello scenario intermedio «+ stili reali» le vittorie casa escono
di 0,1 (47,1%, era 46,9%). Predefinito: −1,0 per chi smanetta a caso. Scarto
fra tutto giusto e tutto sbagliato: 8,9 punti su 38.

## 35. Linea e ampiezza lasciano un'impronta sulla partita — 3 ottobre 2026

Stessa idea del punto 34, per le indicazioni di squadra: oltre allo spostamento
di forza (`OPZIONI_SQUADRA`, gia' tarato sui profili), linea e ampiezza cambiano
come si gioca (`INDICAZIONI_PARTITA` in `config.js`, sommate allo stile in
`identitaStile`). Passate al motore da `simula-giornata` **solo con le tattiche
accese** (`opt.indicazioniCasa/Ospite`).

- linea alta: ritmo 1,04, +3% possesso, l'avversario tira il 10% in meno
  (poche occasioni ma alle spalle), +15% contrasti;
- linea bassa: ritmo 0,95, −3% possesso, l'avversario tira il 12% in piu'
  (da lontano), +10% contrasti;
- ampiezza larga: ritmo 1,02, +5% tiri, +15% dribbling;
- ampiezza stretta: ritmo 0,98, −5% tiri, +1% possesso.

Misurato contro una squadra predefinita di pari forza (tre serie di semi da
6.000 partite): possesso 53% con linea alta e 47% con linea bassa, che subisce
1,2 tiri in piu'. Punti su 38 rispetto al predefinito fra −0,3 e −1,5, dentro
l'oscillazione fra serie (1-3 punti): il ritmo e' simmetrico, quindi non
avvantaggia nessuno; abbassa i punti di entrambe solo perche' aumentano i
pareggi. Il valore di linea e ampiezza resta quello dei profili dei giocatori.
PRODUZIONE e prove tattiche invariate (non passano indicazioni).

## 36. Riequilibrio delle leve: la corsia conta, i ruoli non schiacciano tutto — 3 ottobre 2026

**"Dove attacchiamo" valeva +0,2 punti su 38.** La forza di una corsia è la
media pesata di chi attacca lì, e nelle rose vere la corsia migliore supera la
media delle tre di poco (3.000 rose da `pool-reale.json`):

| modulo | mediana | 75% | 90% | massimo |
|---|---|---|---|---|
| 4-4-2 | 0,8 | 1,2 | 1,6 | 2,7 |
| 4-3-3 | 1,4 | 2,1 | 2,8 | 4,7 |
| 3-5-2 | 0,8 | 1,1 | 1,4 | 2,4 |
| 4-2-3-1 | 1,4 | 2,1 | 2,8 | 4,7 |

Con `SCARTO_PIENO = 4` nessuno arrivava oltre un quarto dell'effetto. Portato a
**1,5**, e `SCALA_CORSIA` da 2,5 a **3,5**.

**I ruoli valevano più di tutte le altre leve insieme** (+6,2 contro 1-1,4
ciascuna). `VALORE_IDONEITA` da 2,0 a **1,5**: restano la leva più grande, perché
sono l'identità dei giocatori, ma non cinque volte le altre.

**Misura** (`prova-ruoli-reali.mjs`, 16.000 partite per riga, rose vere):

| A, rispetto a chi non tocca niente | 4-4-2 prima | 4-4-2 dopo | 4-3-3 dopo |
|---|---|---|---|
| solo ruoli giusti | +6,2 | +4,0 | +3,9 |
| solo stile giusto | +1,4 | +1,4 | +2,3 |
| solo linea giusta | +1,0 | +1,0 | +0,4 |
| solo ampiezza giusta | +1,2 | +1,2 | +1,2 |
| solo corsia giusta | +0,2* | +1,4 | +1,3 |
| linea alta + portiere libero | +0,6 | +0,6 | 0,0 |
| tocca tutto a caso | −0,4 | −1,2 | −0,6 |
| sa leggere la sua rosa | +10,8 | +9,3 | +10,7 |
| sbaglia apposta | −11,8 | −10,8 | −11,4 |

(*prima della soglia nuova: +1,0 dopo la sola soglia, +1,4 con la scala.)
Totale nell'ordine di FM (10,2 fra migliore e peggiore, morale compreso).
Predefinito sintetico: −1,0. Sistema sintetico: 7,4 punti fra tutto giusto e
tutto sbagliato. `simulate-reale` non usa tattiche, invariato.

## 37. Il portiere libero si sceglie leggendo il portiere — 3 ottobre 2026

"Valeva poco" (punto 30) perché la prova lo sceglieva sempre, con portieri
pescati a caso: metà adatti, metà no, effetto medio nullo. Come le altre leve è
una scelta da profilo, e va misurata leggendo il proprio portiere. Nuove righe in
`prova-ruoli-reali.mjs`, tutte con la linea alta, così la differenza è solo il
portiere.

Con `COPERTURA_LIBERO = 1,0`: libero se adatto +0,1 rispetto al portiere
normale, se non adatto −1,1. Punisce l'errore ma non premia la lettura. Portata a
**2,5** (resta la metà del ruolo giusto di un singolo):

| linea alta, 30.000 partite, 4-4-2 | rispetto al portiere normale |
|---|---|
| libero con portiere adatto | +0,9 |
| libero con portiere non adatto | −1,7 |
| libero a caso | −1,0 |

Insieme: sa leggere la sua rosa +8,6, sbaglia apposta −11,4, tocca a caso −0,7.

## 38. Familiarità: il costo vero è sano. Voti: i difensori non sono più i peggiori — 3 ottobre 2026

**Familiarità (punto F), nessuna modifica.** Il +16,7 punti su 38 confrontava
familiarità sempre zero con familiarità sempre piena, che nel gioco non esiste:
si riempie in `FAM_PARTITE_PIENA` (5) partite. Il costo vero, stessa forza, 30
giornate riportate su 38:

| A | punti/38 |
|---|---|
| conosce già il modulo | 61,9 |
| cambia modulo una volta, a inizio stagione | 59,9 (−2,0) |
| cambia modulo tre volte | 57,4 (−4,5) |

Un cambio costa quanto una buona leva tattica, cambiare spesso costa davvero:
premia l'identità di squadra, come voluto (punto 27). `FAM_MALUS_MAX` resta 3,5.

**Voti.** Su 20.215 voti veri di LegaBot: portieri 6,65, **difensori 6,49**,
centrocampisti 6,63, **attaccanti 6,81**; MVP 12% / 19% / 31% / 38% (SofaScore:
medie vicine fra reparti, MVP circa 9 / 23 / 33 / 35). Nelle partite vere si segna
molto (Serie F 4,3 gol a partita) e ogni gol subito pesava −0,14 sui difensori.
`golSubito.DEF` a −0,11 e `basePerReparto` { DEF +0,04, ATT −0,08 }: un
compromesso fra la prova sintetica (pochi gol: MVP difensori 39% su 36% di
titolari, attaccanti 21% su 27%; medie GK 6,73 · DEF 6,78 · MID 6,82 · ATT 6,69)
e le partite vere (stima: difensori ~6,60, attaccanti ~6,73). Da verificare sui
voti nuovi di LegaBot.

## 39. Preset tattici — 3 ottobre 2026 (task 5)

La specifica era una riga («combinazioni pronte delle due pagine»), quindi la
forma l'ho scelta con questi criteri, in coerenza col punto 26 (chi non studia
non deve essere punito) e coi Tactical Preset di EA FC (per chi non vuole
spendere tempo):

- **sei identità**, in `src/lib/preset.ts` (solo dati e logica pura: lo leggono
  sia l'app sia `prova-ruoli-reali.mjs`, quindi i numeri misurati sono quelli
  dell'app): Palleggio, Pressing alto, Contropiede, Catenaccio, Gioco sulle
  fasce, Verticale. Ognuno imposta stile, linea, ampiezza, qualche compito e i
  ruoli;
- **i ruoli solo dove il giocatore è adatto** (idoneità > 0): un preset non può
  mai mettere un giocatore in un ruolo che non sa fare; gli altri posti restano
  «nessuna indicazione»;
- **non toccano** posizioni, «dove attacchiamo» e portiere: il portiere libero
  conviene solo con un portiere adatto (punto 37) e si sceglie a mano;
- **si applicano con un tocco** dallo Schema Tattico («Preset tattici»), poi si
  ritocca tutto e si salva: non salvano da soli.

**Taratura.** Il primo giro era sbilanciato (fasce +4,3, verticale e contropiede
+3, catenaccio −1,6): tutti avrebbero scelto le fasce. Scomposto l'effetto per
pezzo (`PRESET_SENZA=ruoli|compiti|squadra`) ho tolto dove si accumulava (ruoli
di ala in contropiede e fasce, ampiezza larga nelle fasce, compiti dove
costavano o regalavano senza motivo, quasi tutti) e rimesso la linea alta nel
palleggio. Risultato, punti su 38 rispetto a chi non tocca niente (16.000
partite, rose vere, linea e ampiezza con l'impronta del punto 35):

| preset | 4-4-2 | 4-3-3 |
|---|---|---|
| Palleggio | +0,3 | −0,2 |
| Pressing alto | −0,5 | +0,6 |
| Contropiede | +1,0 | +2,7 |
| Catenaccio | −0,1 | −0,1 |
| Gioco sulle fasce | +2,0 | +2,4 |
| Verticale | +1,4 | +0,7 |

Nessuno sotto −0,5, nessuno sopra +2,7; chi legge davvero la rosa fa +9,6. Il
Catenaccio resta neutro a pari forza ed è la scelta di chi è più debole (punto 34).

## 40. Il piano di sviluppo vale subito — 3 ottobre 2026

Segnalato dal committente: col modello dei piani (il piano sceglie DOVE va la
crescita che il giocatore fa comunque, non regala punti) l'attesa di circa 10
giornate (ridotta dal livello Training, −4% per livello, minimo 3) non ha piu'
senso. Migrazione `20261003100000`: `avvia_specializzazione` applica il piano
subito, con la stessa contabilita' di `completa_specializzazioni` (quello che il
piano uscente ha gia' spostato resta al giocatore), **solo nelle leghe con
`tattiche_attive`** (il flag della season 2). Le altre leghe tengono l'attesa
fino al lancio. Il cambio ruolo resta con la sua attesa.

**Difetto trovato per strada, anche su `main`.** Un piano si completa quando
`completa_giornata <= prossima giornata`, e se non ci sono partite programmate
la prossima vale `giornate_totali + 1` (31). I piani avviati dopo circa la
giornata 20 finiscono oltre la fine della stagione (le giornate dei playoff
continuano la numerazione, 31-35+) e **non si completano mai**: alla stagione
successiva la numerazione riparte da 1 e restano aperti, e il giocatore non puo'
avviare altri allenamenti ("ha gia' un allenamento in corso"). Il 3 ottobre:
8 piani a LegaBot (chiusi dalla migrazione), **177 a Serie F** (stagione 1, in
playoff, finali alla giornata 35, completamento previsto 36-43: nessuno ce la
fara'). Con la regola nuova il difetto sparisce; al lancio i piani aperti delle
altre leghe si chiudono in blocco (checklist in `HANDOFF-TATTICHE.md`).

Aggiunta (3 ottobre 2026, migrazione `20261003110000`): **piano e cambio ruolo
possono andare insieme** nelle leghe con il flag. `avvia_specializzazione` non
guarda piu' il cambio ruolo in corso. Il catalogo dei piani e' per ruolo primario
(un CM ha `mezzala_inserimento`, un CDM no): a fine cambio ruolo,
`completa_cambi_ruolo` riporta a `bilanciato` il piano attivo che non vale per il
nuovo ruolo, tenendo al giocatore quello che ha gia' spostato (contabilita' col
reparto di prima) e mandando la notifica «Piano di sviluppo interrotto». Provato
in transazione annullata (CB -> RB con il piano «Libero»). Nell'interfaccia la
scheda tiene l'esclusione solo senza flag. Il difetto dell'esclusione resta
com'era nelle altre leghe fino al lancio; il caso «piano attivo e cambio ruolo
che completa» esiste gia' oggi su `main` senza pulizia.

## 41. Due schemi, attivo e riserva — 3 ottobre 2026

Richiesta del committente: una squadra puo' preparare un secondo modulo che
accumula familiarita' anche se non lo schiera; dopo 5 partite e' conosciuto come il
principale. Poi, dopo la prima versione (un menu nei moduli), la forma voluta e'
**stile EA FC**: sopra le card di modulo e stile, una card larga quanto le due con
**due schemi tattici con un nome**. Solo nelle leghe con `tattiche_attive`.

- **Schema attivo**: quello che gioca, coincide con la formazione salvata; nome di
  default «Schema 1», rinominabile con la matita. **Schema riserva**: uno schema
  tattico completo (modulo, schieramento, ruoli, compiti, dove si attacca, stile,
  linea, ampiezza, portiere), all'inizio vuoto. Si tocca uno dei due per vederlo e
  modificarlo (lo Schema Tattico, il menu dei moduli e i ruoli editano quello
  selezionato); toccando la riserva vuota si crea come COPIA dell'attivo da ritoccare.
  «Usa in partita» li scambia (anche i nomi), «Elimina» libera la riserva e se ne
  prepara un'altra. Il pulsante Salva salva entrambi; la **prima volta** che si salva
  una riserva ne chiede il nome (default «Schema 2»).
- **Database** (migrazione `20261003130000`, sostituisce `20261003120000`, la cui tabella
  era vuota): `schemi_squadra` (una riga per squadra: `nome_attivo` e la riserva in
  colonne, tutto o niente; visibile solo al proprietario) e `salva_schemi` (stessi
  controlli di `salva_formazione`; rifiuta le leghe senza flag). La formazione resta
  in `lineups` e rappresenta l'attivo.
- **Familiarita'**: `private.avanza_familiarita` chiama `private.avanza_secondario`, che
  legge la riserva e, se il suo schieramento non e' quello appena giocato, gli da' una
  partita (`private.assicura_riga_xp` crea la riga con la quota ereditata dal piu'
  simile). I contatori non calano mai: scambiare e riscambiare non perde nulla.
  `registra_risultato_partita` la chiama per entrambe le squadre a ogni partita.
- **Non tocca** la barra INDICAZIONI (stile, ruoli, compiti, ...): la riserva prepara il
  MODULO, le sue istruzioni sono salvate con lei ma la barra indicazioni resta una sola
  e scende se si cambiano, come oggi.
- **Prova** (transazione annullata, utente di LegaBot): rifiuto su lega senza flag, stile
  inesistente, nome vuoto; con la riserva 4-4-2 e tre partite col 4-3-3 il 4-4-2 passa da
  52 a 55; giocato, +1 una volta sola; eliminazione.
- **Effetto sull'equilibrio da misurare**: il costo di un cambio di modulo (−2 punti su
  38, punto 38) per chi pianifica diventa zero con 5 partite di anticipo.

Revisione del punto 41 (3 ottobre 2026, sera): **va in partita lo schema selezionato
quando si salva.** Via la riga con «Usa in partita» ed «Elimina»: i due schemi sono due
slot con un'etichetta, «In partita» e «Riserva», alla stessa altezza. Se al momento di
Salva e' selezionata la riserva, diventa lo schema in partita e quello di prima passa a
riserva (continua a imparare); i nomi seguono gli schemi e lo scambio avviene nel
salvataggio (`salva_formazione` con lo schema selezionato, poi `salva_schemi` con i
ruoli invertiti). Per questo il bottone Salva si accende anche solo selezionando la
riserva, e una nota lo dice. Chi vuole solo prepararla torna sullo schema in partita
prima di salvare. La riserva ha una «×» per essere eliminata e la barra dei progressi
dentro il suo riquadro. La card sta come primo figlio del contenitore di moduli e stile
(la barra superiore e' una griglia ad aree con nome: fuori da quell'area spostava Salva).


## 42. Il 3-5-2 ha esterni di centrocampo e un mediano — 4 ottobre 2026

**Problema** (segnalato dal committente): sul campo il 3-5-2 e il 5-3-2 erano identici,
perche' i due esterni del 3-5-2 erano quinti LWB/RWB, disegnati all'altezza dei terzini.

**Decisione**: 3-5-2 = `GK CB CB CB LM CM CDM CM RM ST ST`. Esterni di centrocampo alti,
un mediano davanti alla difesa e due centrocampisti ai suoi lati. Il 5-3-2 resta con LB
e RB. Stesso ordine degli slot: i titolari restano allo stesso indice (slot 4 LWB -> LM,
slot 6 il CM centrale -> CDM, slot 8 RWB -> RM, contando da zero).

**Motore** (`engine/config.js`, MODULI): validato con `simulate.js` e `simulate-reale.js`.
Nessuna metrica uscita dal target; le metriche gia' fuori lo erano anche prima (suite
storica, punto E). Il profilo strutturale del 3-5-2 passa da ATT −1,10 / MID −0,33 / DEF
+1,32 a ATT −0,88 / MID +0,66 / DEF +0,33: piu' centrocampo, meno difesa, come chiesto.
Nel torneo fra moduli resta equilibrato: 1,379 punti/partita, prima 1,383; lo scarto
massimo fra i moduli e' 0,086, con un target fino a 0,22. Riga di produzione: 2,72
gol, 13,4 tiri, 23,5% pareggi, 46,0% vittorie in casa.

**App**: `src/lib/formazioni.ts`, `Formazione.tsx`, `src/lib/tattica.ts` (copia a mano
della sola voce, senza rigenerare le tarature). Le posizioni sul campo arrivano da sole
dalle ancore di `schieramento.ts`. LWB/RWB restano come spostamento possibile di un
terzino nei moduli a quattro.

**Database**: migrazione `20261004110000_352_esterni_e_mediano.sql`, **da applicare al
lancio** (checklist dell'handoff). Converte familiarita', formazioni, moduli
personalizzati e schemi riserva. I ruoli degli esterni tornano vuoti, perche' i ruoli da
terzino non valgono per un esterno di centrocampo. Fino ad allora, nella LegaBot, un
3-5-2 con posizioni spostate a mano viene rifiutato al salvataggio; quello standard si
salva.


## 43. La familiarità la legge solo il proprietario — 4 ottobre 2026

Le tabelle `formation_xp` e `indicazioni_xp` erano leggibili da tutti i membri della lega:
da lì si capiva quali moduli e quali indicazioni un avversario stava imparando, **compreso
lo schema riserva** che si prepara senza schierarlo (punto 41). Dato tattico, quindi
riservato. Migrazione `20261004130000`: le policy di lettura passano da «membro della
lega» a «proprietario della squadra». La Edge Function legge con la chiave di servizio e
l'app legge solo la riga della propria squadra: nulla cambia per chi gioca. Provata in
transazione annullata come utente LegaBot (3 squadre sue visibili, 0 altrui).

Lancio della season 2 (4 ottobre 2026, ore 11): `tattiche_attive` acceso su tutte le leghe
non archiviate; chiusi tutti i piani di sviluppo aperti **annullandoli** (non
completandoli): nessuno riceve crescita dal piano a metà e tutti possono sceglierne uno
nuovo. Erano 177, tutti a Serie F.


## 44. Stile «Personalizzato», velocità di manovra, «Entrambe le fasce» — 6 ottobre 2026

**Il problema.** Stile, linea, ampiezza e dove si attacca erano quattro scelte indipendenti
che si sommavano: «recupero veloce» con «linea bassa» si annullavano in parte, «difesa a
oltranza» con «linea alta» faceva il contrario del suo nome. Nessun errore, ma un effetto
confuso senza che il giocatore se ne accorgesse.

**La regola.** Sotto uno stile preimpostato linea, ampiezza, velocità di manovra e dove si
attacca sono **bloccate**: le decide lo stile e l'app le mostra soltanto («dallo stile»).
Il motore non cambia i numeri: sotto un preset vale solo l'effetto dello stile, com'è
sempre stato. Con il nuovo stile **Personalizzato** (neutro, come equilibrato) le quattro
sezioni si sbloccano e contano solo quelle scelte. Passando a Personalizzato si parte dai
valori dello stile che si lascia; scegliendo uno stile preimpostato i valori si azzerano
(niente valori nascosti, che peserebbero sulla familiarità senza che si vedano).
Il blocco è applicato in `simula-giornata` (`assiLiberi` in `engine/squadra.js`).

| Stile | Linea | Ampiezza | Velocità | Dove attacchiamo |
|---|---|---|---|---|
| Equilibrato | media | normale | normale | ovunque |
| Contropiede | bassa | stretta | veloce | ovunque |
| Possesso palla | alta | stretta | ragionata | ovunque |
| Gioco sulle fasce | media | larga | normale | entrambe le fasce |
| Recupero veloce | alta | normale | veloce | ovunque |
| Gioco diretto | media | normale | veloce | ovunque |
| Difesa a oltranza | bassa | stretta | ragionata | ovunque |

(`ASSI_STILE` in `src/lib/stili.ts`: valori solo informativi.) I sei **Preset tattici**
(punto 39) restano: applicano lo stile e azzerano le altre scelte; per ritoccare si passa a
Personalizzato. Il portiere-libero resta libero sotto ogni stile, ma la copertura sulla
linea alta vale solo in Personalizzato.

**Velocità di manovra** (nuova leva, `normale` predefinita):
- *ragionata*: MID +0,5, ATT −0,5; ritmo 0,97, possesso +0,04, tiri ×0,92; chiede centrocampisti
  tecnici (stesso profilo dell'ampiezza stretta);
- *veloce*: MID −0,5, ATT +0,5; ritmo 1,04, possesso −0,03, tiri ×1,08; chiede giocatori che
  passano e scattano (`manovra_veloce`: passaggi corti + accelerazione, famiglia MANOVRA,
  correlazione con l'overall −0,01 dopo la taratura).

**Entrambe le fasce** (`focus_corsia = 'FASCE'`): rende se la media delle due fasce supera la
media delle tre corsie, costa se è il lato debole; il centro prende il malus. Il vantaggio
pieno arriva a metà scarto (`SCARTO_FASCE`), perché lo scarto delle fasce è la metà di quello
del centro a parità di squilibrio.

**Misura** (`prova-ruoli-reali.mjs`, 40.000 partite, 4-4-2, rose vere), rispetto a chi non tocca niente:

| scelta | punti su 38 |
|---|---|
| solo ruoli giusti | +4,4 |
| solo stile giusto (preset) | +1,5 |
| i sei preset | da −0,6 a +1,9 |
| Personalizzato: solo velocità giusta | +0,9 |
| Personalizzato: solo corsia giusta (con le fasce) | +1,8 |
| **Personalizzato: tutto giusto** | **+4,8** |
| Personalizzato: tutto sbagliato | −5,4 |
| tocca tutto a caso | −1,0 (vincolo rispettato) |

Personalizzato vale quanto valeva prima la somma di stile, linea, ampiezza e corsia (+4,8
contro circa +4,8): il tetto non cambia, cambia che per raggiungerlo si rinuncia al bonus
dello stile. I preset restano la scelta sicura (da −0,6 a +1,9). Nota: la corsia «giusta» vale
+1,8 e non +0,2 come scritto al punto 30: quella cifra era precedente alla ritaratura del
punto 36.

**Database** (migrazione `20261006100000`, da applicare alla pubblicazione): `stili_validi`
con `personalizzato`; colonne `velocita_manovra` (lineups, moduli_personalizzati,
indicazioni_xp) e `riserva_velocita` (schemi_squadra); `focus_corsia` accetta `FASCE`;
`salva_formazione`, `salva_modulo_personalizzato`, `salva_schemi` con `p_velocita`
(ricostruite dalla definizione live, vecchie firme tolte); familiarità con le indicazioni a
28 elementi. Le formazioni, i moduli e gli schemi riserva con indicazioni sopra uno stile
passano a `personalizzato` (9 formazioni al momento della prova). Provata in transazione
annullata.


## 45. Ogni schema ha i suoi giocatori — 6 ottobre 2026

Segnalato dal committente: preparando due schemi con giocatori diversi, tornando sul primo ci si ritrovavano
i giocatori dell'ultimo salvato. Il motivo: i due schemi erano due **tattiche** (modulo, ruoli, compiti,
indicazioni) ma la **distinta** (titolari, panchina, tribuna) era una sola, quella della formazione salvata.

Ora anche la riserva conserva la sua distinta (`schemi_squadra.riserva_titolari`, `riserva_panchina`,
`riserva_tribuna`; migrazione `20261006140000`, `salva_schemi` con tre parametri in piu', vecchia firma compatibile
grazie ai valori predefiniti). L'app tiene la distinta dentro ogni schema (`Tattica.giocatori`): passando da uno
schema all'altro i giocatori cambiano con lui; salvando, la distinta dello schema selezionato diventa la formazione
che gioca e quella dell'altro resta nella riserva.

- **Riserva nuova o mai salvata con i giocatori**: parte come copia della distinta in campo (come prima).
- **Pulizia al caricamento**: chi non e' piu' in rosa lascia il posto vuoto dov'era; chi e' arrivato dopo va in tribuna.
- **Controlli**: undici posti (0 = vuoto), ogni id deve essere della rosa della squadra (provato: un giocatore
  altrui viene rifiutato; senza riserva le colonne si azzerano). Il blocco su infortunati e squalificati resta
  sullo schema che si salva come attivo.

## 46. Rendimento in partita e cambi per scarso rendimento — 8 ottobre 2026

Richiesta del committente (7 ottobre): in una sosta si possono fare piu' di 2 cambi, e il mister deve poter
sostituire anche chi sta giocando male, non solo chi e' stanco. Il motore deve vedere la valutazione LIVE del
giocatore, costruita da cio' che succede in campo, **senza aggiungere nulla di casuale** (niente «forma del giorno»).
Mai il portiere.

**Cosa e' cambiato** (`engine/rendimento.js`, nuovo; `engine/engine.js`, `engine/config.js`, `engine/pagelle.js`):
- **Voto che cresce durante la gara.** Dopo ognuno dei blocchi, ogni giocatore in campo accumula passaggi,
  interventi, contrasti e dribbling (tentati e riusciti, con la stessa formula e gli stessi PESI delle pagelle),
  piu' gol, assist, cartellini e gol subiti mentre era in campo. Flussi casuali PROPRI (seme `seedInfortuni + 331`):
  gol, infortuni e cartellini non si spostano. Il caso entra solo dove entrava gia': la riuscita di ogni gesto.
- **Voto finale = la stessa linea.** `pagelle()` con `L.live` prende il voto dal rendimento e aggiunge solo cio' che si sa
  a fine gara (tiri, parate, porta inviolata, risultato). Niente rumore gaussiano: il voto che il mister vede a meta'
  partita e quello in pagella sono la stessa cosa. Statistiche individuali e di squadra (passaggi, contrasti,
  dribbling) sono i tentativi veri blocco per blocco, non piu' una distribuzione post-partita.
- **Marcatore e assist scelti nel blocco del gol**, fra chi e' in campo in quel momento (stessi pesi di prima).
  La Edge Function non li abbina piu' a posteriori: `eventiGolDalMotore` da' solo il minuto dentro il blocco.
  `QUOTA_GOL_SENZA_ASSIST` e `PESO_ASSIST` ora vivono in `engine/rendimento.js`.
- **Cambi** (`sostituzioni()`): 1) per rendimento, prima: voto live sotto `SOGLIA_RENDIMENTO_CAMBIO` (6,2), almeno
  `MIN_BLOCCHI_RENDIMENTO` (2) blocchi giocati, entra la migliore alternativa dello slot purche' non sia piu' debole
  di `MARGINE_CAMBIO_RENDIMENTO` (8) punti; **mai chi e' subentrato dalla panchina** (committente, 8 ottobre); all'intervallo al massimo `MAX_CAMBI_RENDIMENTO_INTERVALLO` (1) in piu'
  del cambio per stanchezza; 2) per stanchezza, come prima; 3) **rotazione** (committente, 8 ottobre: nel calcio vero
  quasi tutte le squadre usano tutti e cinque i cambi): `OBIETTIVO_CAMBI` `{4: 3, 5: 5}`, alla finestra che chiude il
  blocco 4 la squadra arriva ad almeno 3 cambi, a quella del blocco 5 a 5, togliendo i piu' affaticati (mai il portiere,
  mai un subentrato) se l'alternativa non e' piu' debole di `MARGINE_CAMBIO_ROTAZIONE` (12) punti di overall nello slot. **Tolto il tetto di 2 cambi per sosta**
  (`MAX_CAMBI_FINESTRA` 2 → 5): valgono solo i 5 cambi totali e le 3 soste.
- **Cronaca e rapporto**: il cambio per rendimento porta `motivo: 'rendimento'` («scarso rendimento» nel rapporto,
  «non in giornata» nella telecronaca).
- **Cambio «fantasma» corretto** (Edge Function, `minutiGiocati`): un infortunio nell'ultimo blocco faceva entrare un
  sostituto senza blocchi giocati nel motore, quindi senza riga di statistiche (il rapporto mostrava l'id).
  Ora chi entra riceve i minuti veri della sua finestra.

**Misure** (suite `tools/validazione`, confronto con la base prima delle modifiche):
- `simulate.js`: nessun target che era OK diventa FUORI. Con la rotazione dei cambi (gambe fresche) la squadra rende un
  poco di piu': gol/partita 1,92 → 2,10 e 2,14 → 2,19 nella stagione, vittorie casa 41,5 → 43,6 (ora OK), tiri per
  squadra 10,6 → 11,2 (ora OK). I FUORI di partenza (gol/partita, pareggi...) c'erano gia' prima.
- `prova-pagelle.mjs` (1.500 partite, rose vere): media voti 6,70, scarto 0,52, 5%-95% 6,1-7,7, migliore in campo 8,05;
  MVP per reparto GK 10 · DEF 35 · MID 28 · ATT 27 (titolari 9/36/27/27). Per tenere queste misure sono stati ritoccati
  `PESI.base` 6,4 → 6,5 (i subentrati, con voto stretto verso il 6, abbassavano la media), `intervento` 0,11 → 0,14 e
  `parata` 0,17 → 0,14. Prima: 6,72 / 0,60 / 8,01 / 13-39-28-20.
- Cambi per squadra (60 stagioni, rose sintetiche con panchina piu' debole): 4,14 → 4,72; con 5 cambi: 35% → 74%.
  Con le rose vere di Serie F (150 partite): 298 squadre su 300 con 5 cambi, circa 0,4 a squadra per rendimento.
- Funzione completa in locale (150 partite, `simulaAmichevoleCore`): i gol degli eventi sono quelli del punteggio, ogni
  marcatore, assist e sostituto ha la sua riga di statistiche (0 problemi).

**Da sapere**: la prima giornata dopo l'off-season ha pochi cambi per stanchezza perche' tutti partono con la condizione
al massimo (media 3,1 a squadra alla giornata 1 di stagione 2, contro ~4,9 nelle altre). I cambi per rendimento non
dipendono dalla condizione.
