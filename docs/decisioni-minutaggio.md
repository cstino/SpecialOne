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

## 2. Cosa chiede un giocatore

Ogni giocatore **chiede** un gradino, uguale per tutte le squadre (deciso il 4 ottobre 2026):
si misura sul suo **reparto nella lega**, non sulla rosa di chi lo vuole. Per ogni reparto si
mettono in fila per overall i giocatori in rosa nella lega:

| Reparto | Metro del titolare | Metro del turnover |
|---|---|---|
| Portieri | i primi (squadre × 1) | — (fra i pali non c'è turnover) |
| Difensori | i primi (squadre × 4) | i successivi (squadre × 2) |
| Centrocampisti | i primi (squadre × 4) | i successivi (squadre × 2) |
| Attaccanti | i primi (squadre × 2) | i successivi (squadre × 2) |

Chi ha l'overall del titolare chiede «Titolare fisso», chi quello del turnover «Turnover»,
gli altri «Sporadico»; un under 21 che non chiede di essere titolare chiede «Promessa
futura». In Serie F il 4 ottobre: portieri titolari da 77, difensori e centrocampisti da
75, attaccanti da 77. C. Mandas (76) chiede «Sporadico», Ederson (85) «Titolare fisso».

La richiesta si ricalcola sempre dal livello attuale: un giovane che cresce, al rinnovo chiede
di più; un veterano che cala abbassa le pretese.

## 3. Dove vale la richiesta

- **Mercato svincolati e mercato a scelte**: ogni giocatore mostra «Chiede: …». Chi lo
  prende **firma con quella promessa**, già trattata: valgono subito richiami e cessione. Il
  gradino non cambia il prezzo dell'asta, è una condizione da accettare. Lo scrive il
  database alla firma (`private.minutaggio_alla_firma`, sul cambio di squadra da svincolato e
  sull'inserimento di una nuova istanza), qualunque sia la strada: asta, scelta, completamento
  della rosa a fine off-season.
- **Scambi**: la promessa **viaggia col giocatore**, come l'ingaggio. Richiami e richiesta di
  cessione invece si azzerano: erano verso il mister di prima.
- **Svincolo**: la promessa si azzera.
- **Rinnovo**: il giocatore apre chiedendo il suo gradino, insieme all'ingaggio. Puoi
  promettergli di più (ogni gradino in più toglie l'8% alla richiesta) o un gradino in meno
  (+12%); due gradini in meno li rifiuta. Rifiuta comunque «Sporadico» se è almeno 3 punti
  sopra la media della rosa e «Turnover» se è almeno 6 sopra. «Promessa futura» si offre solo
  sotto i 21 anni (la promessa sta al livello dello sporadico).

## 3b. Chi è già in squadra al lancio

Chi è già in una squadra riceve **come promessa quello che chiederebbe oggi** (§2), così ogni
giocatore ha il suo gradino fin dall'inizio (richiesta del committente, 4 ottobre 2026): vale
per morale e richiami come ogni altra promessa. Il minutaggio si conta dall'inizio della
stagione corrente, quindi i primi richiami arrivano alla verifica della giornata 8.

`player_instances.minutaggio_promesso` vuoto resta possibile solo dopo uno scambio verso una
squadra di una lega senza tattiche; vuol dire **gradino automatico**, dalla gerarchia della
rosa (portieri 1 titolare; difesa e centrocampo 4 e 2; attacco 2 e 2; un under 21 non titolare
è una promessa futura). Serve solo al morale, non fa partire richiami.

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

- **molto al di sotto** (il rosso del §6) se gioca meno del 70% della soglia minima (es.
  titolare fisso con meno del 38,5% dei minuti giocabili) e almeno 10 punti sotto la quota;
- primo controllo «molto al di sotto»: **richiamo**. Il giocatore scrive al mister: «Mister, mi
  era stato promesso più spazio e al momento non lo sto avendo. Le chiedo di migliorare la
  mia situazione, altrimenti sarò costretto a chiedere la cessione.»
- controllo successivo ancora «molto al di sotto»: **richiesta di cessione**. Il giocatore non
  rinnoverà più il contratto: alla scadenza lascia la squadra. Arriva un secondo messaggio.
- se al controllo dopo il richiamo la situazione è rientrata, il richiamo si cancella.

La richiesta di cessione non si ritira nella stessa squadra; uno scambio la azzera. Non mette
il giocatore in lista di vendita da sola: decidere se e come cederlo resta al mister.

## 6. Soglia minima, colori e assenti

La **soglia minima** di un gradino è la quota di minuti sotto la quale la promessa non è più
rispettata: titolare fisso **55%**, turnover **30%**, sporadico 3%, promessa futura 3%. Si
vede accanto al nome del gradino in scheda, nella trattativa e nei mercati («Titolare fisso
(min. 55%)»). La **quota** promessa (75%, 40%, 5%, 5%) resta quella che il morale si aspetta.

Il 4 ottobre la soglia del titolare era 45% (60% della quota): troppo bassa, il committente
l'ha giudicata poco da titolare. Sui titolari della stagione 1 di Serie F la mediana dei minuti
reali è 63%, e il 29% di loro stava sotto il 45%; i «titolari» per soglia di lega sono circa 13
per squadra e in campo ne vanno 11.

I minuti in rosa, accanto alla **percentuale**, si colorano come i richiami:

| Colore | Quando |
|---|---|
| verde | raggiunge la soglia minima: la promessa è rispettata |
| giallo | sotto la soglia ma non molto (anche uno sporadico che non gioca mai: non si lamenterebbe) |
| rosso | molto sotto: meno del 70% della soglia (38,5% per un titolare, 21% per un turnover) e almeno 10 punti sotto la quota. È il caso in cui il giocatore si fa sentire (§5) |

Stessa regola in `src/lib/minutaggio.ts` (`statoMinuti`, `GRADINI_MINUTAGGIO`) e in SQL
(`private.soglia_minutaggio`, `private.controlla_minutaggio`): se si cambia una, va cambiata
l'altra. Le statistiche della rosa (minuti, gol, assist, voti) contano la sola stagione corrente.

**Gli assenti non contano.** La percentuale si calcola sulle sole partite in cui il giocatore
poteva giocare: quelle in cui era infortunato o squalificato non entrano né nei minuti attesi né
nel denominatore. Prima non esisteva uno storico: ora il trigger `matches_registra_assenze`
(`private.assenze_partita`) registra chi era indisponibile a ogni partita, leggendo lo stato
prima che la simulazione lo aggiorni (infortuni e cartellini si aggiornano dopo il salvataggio
delle partite). Le partite giocate prima del 4 ottobre non hanno storico e contano come
«disponibile». Con meno di 5 partite giocabili un giocatore non viene controllato.

## 7. Dove sta il codice

- Migrazione `20261004140000_minutaggio_promesso.sql`: colonne su `player_instances`
  (`minutaggio_promesso`, `richiamo_stagione`, `richiamo_giornata`,
  `richiesta_cessione_stagione`), funzioni `private.quota_minutaggio`,
  `private.gradino_automatico`, `private.gradino_effettivo`, `private.controlla_minutaggio`,
  morale, rinnovi (`proposta_rinnovo`, `offri_rinnovo` con il gradino), reset al trasferimento,
  job `controlla-minutaggio`.
- App: trattativa e scheda in `SchedaGiocatore.tsx`, chiamate in `TeamProfile.tsx`.

I numeri (quote, sconti, soglie, cadenza) sono tutti qui: se il committente vuole ritoccarli,
si cambiano in un posto solo.
