# Decisioni — Minutaggio promesso e richiesta di cessione

Deciso col committente il 4 ottobre 2026. Nasce da una segnalazione: C. Mandas (portiere
76 del Regginho FC, vice di Ederson 85) era «Scontento» pur con la squadra campione, perché
il morale gli chiedeva di giocare il 55% delle partite, una quota impossibile per un secondo
portiere. Nel calcio vero un secondo portiere sa di giocare poco: lo sa perché glielo hanno
detto alla firma. Da qui la regola: **il minutaggio fa parte del contratto**, come in
Football Manager.

Vale nelle leghe con `tattiche_attive` (dal lancio della Season 2 sono tutte).

## 1. Quattro gradini

| Gradino | Chiave | Quota di minuti attesa | Chi |
|---|---|---|---|
| Titolare fisso | `titolare` | 75% | tutti |
| Turnover | `turnover` | 40% | tutti |
| Sporadico | `sporadico` | 5% | tutti |
| Promessa futura | `promessa` | 5% | solo sotto i 21 anni |

La quota è sui minuti delle partite giocate dalla squadra da quando il giocatore è arrivato
(`giornata_acquisizione`, `arrivo_stagione`).

Sporadico e promessa futura partivano al 15% e al 10%, ma la prova sulla stagione 1 di
Serie F ha detto che con rose da 25-30 giocatori ne giocano 14-16: chi sta in panchina come
pattuito non deve deprimersi. Al 5% non si lamentano mai davvero; i richiami restano per
titolari fissi e turnover traditi.

## 2. Il gradino si tratta al rinnovo

Nella trattativa si scelgono **ingaggio e gradino**. Il gradino cambia la richiesta:
promettere più minuti fa accettare meno soldi, come in FM.

| Gradino | Richiesta |
|---|---|
| Titolare fisso | −8% |
| Turnover | invariata |
| Sporadico | +12% |
| Promessa futura | −10% |

Un giocatore **rifiuta** un gradino che non è alla sua altezza, misurata sull'overall rispetto
alla media della rosa: chi è almeno 3 punti sopra la media non accetta «Sporadico», chi è
almeno 6 sopra non accetta neppure «Turnover». «Promessa futura» si può offrire solo sotto i
21 anni: chi li ha compiuti passa a uno degli altri tre al primo rinnovo.

## 3. Chi non ha ancora un gradino trattato

`player_instances.minutaggio_promesso` vuoto vuol dire **gradino automatico**: lo decide la
posizione del giocatore nel suo reparto, per overall, dentro la propria rosa. Vale per i
contratti in corso al lancio e per chi arriva dal mercato, dagli scambi o dal draft, finché
non rinnova.

| Reparto | Titolari fissi | Turnover | Gli altri |
|---|---|---|---|
| Portieri | il primo | — | sporadico |
| Difensori | i primi 4 | i 2 dopo | sporadico |
| Centrocampisti | i primi 4 | i 2 dopo | sporadico |
| Attaccanti | i primi 2 | i 2 dopo | sporadico |

Un under 21 che non è titolare fisso diventa «Promessa futura». Così il vice di Ederson è
«Sporadico» senza che nessuno l'abbia trattato, ed è sereno.

Piccola differenza rispetto a quanto detto in chat («calcolato da quanto ha giocato»): il
gradino automatico guarda la gerarchia della rosa e non i minuti. Coi minuti un titolare
infortunato a lungo diventerebbe «Sporadico» e un ripiego in campo per necessità «Titolare»:
la gerarchia è più vicina a quello che un allenatore avrebbe promesso.

Un trasferimento (scambio, svincolo) azzera il gradino trattato: la promessa era della
squadra di prima.

## 4. Il morale

Nella voce «minuti» del morale (`applica_morale_checkpoint`, a ogni quarto di stagione) la
quota attesa non viene più dall'overall (`private.quota_partite_attesa`) ma dal gradino. Se
il gradino è stato **trattato** e non viene rispettato, il malcontento pesa il 50% in più: è
una promessa tradita, non un'aspettativa delusa.

## 5. I richiami e la richiesta di cessione

Un controllo ogni 5 giornate di stagione regolare, dalla giornata 8 (8, 13, 18, 23, 28):
prima non c'è abbastanza campione. Riguarda **solo i gradini trattati al rinnovo**: il
gradino automatico è una stima della gerarchia, non una promessa, e serve solo al morale.
La prova sulla stagione 1 di Serie F, contando anche gli automatici, dava 148 richiami (circa
9 per squadra): troppi, e quasi tutti per promesse mai fatte. Per ogni giocatore con un
gradino trattato, di una squadra umana, arrivato da almeno 5 giornate e non infortunato in
quel momento:

- **non rispettato** se gioca meno del 60% della quota del suo gradino, e almeno 10 punti
  sotto (es. titolare fisso con meno del 45% dei minuti);
- primo controllo non rispettato: **richiamo**. Il giocatore scrive al mister: «Mister, mi
  era stato promesso più spazio e al momento non lo sto avendo. Le chiedo di migliorare la
  mia situazione, altrimenti sarò costretto a chiedere la cessione.»
- controllo successivo ancora non rispettato: **richiesta di cessione**. Il giocatore non
  rinnoverà più il contratto: alla scadenza lascia la squadra. Arriva un secondo messaggio.
- se al controllo dopo il richiamo la situazione è rientrata, il richiamo si cancella.

La richiesta di cessione non si ritira nella stessa squadra; uno scambio la azzera. Non mette
il giocatore in lista di vendita da sola: decidere se e come cederlo resta al mister.

## 6. Dove sta il codice

- Migrazione `20261004140000_minutaggio_promesso.sql`: colonne su `player_instances`
  (`minutaggio_promesso`, `richiamo_stagione`, `richiamo_giornata`,
  `richiesta_cessione_stagione`), funzioni `private.quota_minutaggio`,
  `private.gradino_automatico`, `private.gradino_effettivo`, `private.controlla_minutaggio`,
  morale, rinnovi (`proposta_rinnovo`, `offri_rinnovo` con il gradino), reset al trasferimento,
  job `controlla-minutaggio`.
- App: trattativa e scheda in `SchedaGiocatore.tsx`, chiamate in `TeamProfile.tsx`.

I numeri (quote, sconti, soglie, cadenza) sono tutti qui: se il committente vuole ritoccarli,
si cambiano in un posto solo.
