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
