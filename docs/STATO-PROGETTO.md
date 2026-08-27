# Stato progetto e handoff

### Rose delle squadre PC bilanciate per reparto

Segnalazione dell'utente sulla lega di test Test2: il draft PC in modalita `BY ROLE`
sceglieva il reparto con una probabilita uniforme a ogni pick e poteva quindi produrre rose
con 7-9 portieri. La liberta totale prevista dal design resta invariata per gli utenti;
il correttivo riguarda soltanto le squadre controllate dal PC.

La migrazione `20260808197000_rose_pc_bilanciate_per_ruolo.sql` introduce cinque profili
realistici da 24 giocatori, tutti vicini alla base 3 portieri / 8 difensori / 8
centrocampisti / 5 attaccanti. Il reparto del prossimo pick viene mescolato fra quelli
ancora sotto obiettivo, evitando sia accumuli casuali di portieri sia il vecchio pattern
"prima un reparto intero, poi il successivo". Anche il fallback economico resta vincolato
al reparto richiesto.

Backfill applicato a Test2, che non aveva ancora partite simulate: sostituiti soltanto pick
PC non coinvolti in trattative, con giocatori liberi dello stesso identico ingaggio. Budget,
numero di giocatori e squadra umana invariati. Risultato verificato: tutte le rose PC hanno
2-3 portieri e rispettano esattamente il proprio profilo; una rosa da 25 dovuta al mercato
assegna lo slot aggiuntivo a un reparto di movimento.

### Notifica fine giornata senza spoiler, e annuncio admin a tutta la lega

Segnalazione dell'utente: la notifica push/in-app di fine giornata mostrava già il risultato
nel titolo (es. "Vittoria 3-1"), rovinando la sorpresa prima ancora di aprire l'app. In
`supabase/functions/simula-giornata/index.ts` il testo ora è fisso e uguale per entrambe le
squadre — `"Giornata {N} terminata"` / `"Entra per controllare il risultato!"` — tolta anche
la costruzione `verdetto`/`lati` che serviva solo a comporre il testo col punteggio. Ridistribuita.

Aggiunta anche una richiesta collegata: un campo nel pannello Admin per mandare un messaggio
libero a tutti i partecipanti della lega, come notifica in-app + push. Nuova RPC
`public.invia_annuncio_lega(p_league_id, p_messaggio)` (migrazione
`20260808140000_annuncio_admin_lega.sql`), stesso controllo diretto su `leagues.admin_id`
già usato da `elimina_lega` (non `private.e_admin()`, che è pensata per le policy RLS). Usa
`tipo = 'sistema'`, già previsto dalla CHECK di `notifications` — nessuna migrazione di
schema oltre alla funzione. Verificato via query transazionale (poi annullata) su Real
Fampionato: 8 notifiche inviate (una per squadra attiva), rifiutato correttamente un utente
non admin. `db lint` invariato.

### Campo neutro nell'ultimo girone dei campionati a gironi dispari

Segnalazione dell'utente: il fattore campo presuppone che ogni squadra giochi in casa e in
trasferta lo stesso numero di volte contro ogni avversaria — vero solo con un numero pari di
gironi. Verificato leggendo `private.inizializza_stagione`: alterna casa/trasferta per girone
e inverte l'ordine ai gironi pari (si accoppiano 1↔2, 3↔4...), ma con un numero dispari di
gironi l'ultimo resta spaiato e ripete l'ordine del girone 1 — chi era in casa lì lo è di
nuovo nell'ultimo, un vantaggio strutturale, non casuale.

**Verificato su dati reali**: Real Fampionato (lega 37, dell'utente) ha 3 gironi (dispari), e
aveva già l'ultimo girone generato (giornate 15-21, tutte `programmata`, nessuna simulata).
L'utente ha scelto esplicitamente di correggere anche questa lega, sulle giornate non ancora
giocate.

**Motore** (`engine/engine.js`): nuovo flag opzionale `opt.campoNeutro`, azzera
`BONUS_CASA_ATT`/`BONUS_CASA_MID` per quel blocco. Stesso pattern additivo di `opt.stileCasa`
(default assente, nessun effetto sulle chiamate esistenti). Protocollo CLAUDE.md §4 seguito
per intero: `node tools/validazione/simulate.js` dà lo stesso numero di metriche OK/FUORI del
baseline (13/13 invariate); verifica direzionale ad-hoc (3000 partite, squadre identiche,
stesso seed): normale 1,87 gol/partita in casa contro 1,35 in trasferta (il vantaggio atteso),
con `campoNeutro:true` 1,44 contro 1,46 — il vantaggio sparisce come previsto.

**Schema**: `fixtures.campo_neutro boolean default false` (migrazione
`20260808130000_campo_neutro_gironi_dispari.sql`), `inizializza_stagione` lo imposta
sull'ultimo girone quando `n_gironi` è dispari, più un **backfill** nella stessa migrazione
per le leghe già in corso (verificato: copre esattamente le giornate 15-21 di Real
Fampionato, senza toccare la giornata 1 già simulata). Una migrazione di correzione
immediata (`20260808130100`) ha tolto una doppia dichiarazione di variabili nei loop che
aveva fatto salire i warning di lint da 2 (baseline) a 10 — tornati a 2.

**Frontend**: `FixtureScore` (`src/components/SeasonUI.tsx`), l'unico punto che disegna il
segno centrale di ogni card partita in tutta l'app, mostra "Campo neutro" quando
`fixture.campo_neutro`. Attenzione conservata nel CSS: i contenitori chiamanti sono griglie a
3 colonne fisse (`.fixture-row`, `.last-match-duel`, `.next-match-duel`), quindi il componente
resta sempre a **un solo elemento radice** (mai un Fragment con due figli) — per il caso
campo neutro avvolge risultato/etichetta in un unico `.fixture-score-wrap`.

### Il minutaggio sposta la velocità di progressione (§10.2)

Richiesto dall'utente: prima la progressione dipendeva solo dall'età, identica per un
titolare fisso e per chi non gioca mai. Ora `applica_progressione_trimestrale` scala ogni
delta per un moltiplicatore lineare sulla quota di minuti giocati in stagione — 0,8x chi
non gioca affatto, 1,4x chi gioca sempre — riusando la stessa fonte dati già in produzione
per il morale (`match_stats`/`quota_partite_attesa`, §10bis.3), non serve nessuna colonna
nuova.

Due parametri scelti esplicitamente dall'utente dopo un confronto fra opzioni: si applica a
**tutte** le fasce d'età, declino incluso (non solo agli under 27 in crescita — un
veterano titolare fisso cala anche più in fretta), con un range moderato 0,8x-1,4x (non
0,5x-1,5x né 0,2x-2x, le due alternative proposte). Migrazione
`20260808120000_progressione_da_minutaggio.sql`. Verificato eseguendo la funzione vera in
una transazione poi annullata (lega 29, checkpoint 4): nessun errore, gli overall si
muovono nella direzione attesa. Non è una modifica al motore (`engine/`) — è una RPC di fine
trimestre separata — quindi non richiede il protocollo di validazione di CLAUDE.md §4, ma
segue comunque lo stesso principio: descritta, applicata, verificata su dati reali prima di
considerarla fatta.

### Due varianti del 4-3-3: offensivo (CAM) e difensivo (CDM)

Segnalazione dell'utente: pochi moduli usavano CAM o CDM (solo il 4-2-3-1). Aggiunte due nuove
voci in `engine/config.js` `MODULI`, derivate dal 4-3-3 cambiando solo uno dei tre centrocampisti
centrali: **4-3-3 offensivo** (CM, CM, CAM) e **4-3-3 difensivo** (CM, CM, CDM).

Modifica al motore, protocollo CLAUDE.md §4 seguito per intero: descritta, applicata, rilanciata
`node tools/validazione/simulate.js`. Nessuna delle 13 metriche target è peggiorata (stessi
pass/fail di prima, differenze solo di rumore statistico fra run). Il profilo strutturale non
richiede alcuna taratura a mano — si calcola già a runtime dal monte-pesi degli slot (design.md
§6.4) — quindi le due varianti sono entrate automaticamente bilanciate: nel torneo all-play-all
a 9 moduli si piazzano in mezzo al gruppo (1,378 e 1,349 punti/partita su un range 1,335–1,413),
scarto massimo 0,078 punti/partita contro un target di 0,000–0,220 (più stretto del baseline a 7
moduli, 0,113–0,122 a seconda del giro). Nessun modulo domina.

Sincronizzate le tre copie tenute a mano (stesso pattern già in uso per gli altri 7 moduli):
`engine/config.js` (MODULI), `private.moduli_validi()` lato DB (migrazione
`20260808110000_varianti_433.sql`), `MODULI`/`MODULO_DESCRIZIONI` in `Formazione.tsx`. Aggiornati
anche `docs/design.md` §6.1/§6.4 e la voce "Moduli e stile di gioco" della guida "Aiuto".
`docs/risultati-fase0.txt` resta il baseline storico originale, non riscritto — stesso
precedente già seguito per lo stile di gioco.

### Notifiche push del browser

Richiesta dell'utente. Secondo canale di consegna sopra `public.notifications`, esattamente
come anticipato nel commento di `20260802120000_notifiche.sql`: non si tocca la tabella
esistente, si aggiunge solo la sottoscrizione e un trigger.

- **`push_subscriptions`**: una riga per dispositivo/browser (endpoint + chiavi p256dh/auth),
  scritta direttamente dal client — a differenza di `notifications`, qui e' l'utente ad
  autogestire le proprie righe (RLS `user_id = auth.uid()` su tutte le operazioni).
- **Trigger `notifications_invia_push`** (`AFTER INSERT` su `notifications`): chiama via
  `pg_net` la nuova Edge Function `invia-push`, stesso schema gia' in uso per il cron
  notturno (chiave dal vault, header `apikey`). Fire-and-forget: un push service lento o
  irraggiungibile non fa mai fallire l'insert su `notifications` (verificato in rollback).
  Effetto pratico: ogni RPC che gia' notifica in-app (mercato, infortuni, giornata simulata)
  ottiene la push gratis, senza essere toccata.
- **Edge Function `invia-push`** (Deno, libreria `npm:web-push`): legge le sottoscrizioni
  dell'utente destinatario e invia a ciascuna. Una sottoscrizione revocata (404/410, es.
  disinstallazione o dati del browser cancellati) viene rimossa automaticamente invece di
  essere ritentata.
- **Service worker** (`public/sw.js`, gia' esistente per l'installabilita' PWA): ora gestisce
  anche `push` (mostra la notifica) e `notificationclick` (porta alla lega giusta se l'app e'
  gia' aperta, tramite `postMessage` intercettato in `App.tsx`; altrimenti apre `/`).
- **UI**: pulsante "Attiva le notifiche push" nel pannello Notifiche (`Notifiche.tsx`),
  visibile solo se il browser supporta l'API Push; nasconde il pulsante e mostra un avviso se
  il permesso e' stato negato dal browser.
- **Chiavi VAPID**: generate una volta, la privata sta solo nei secret della Edge Function
  (`VAPID_PRIVATE_KEY`, mai nel database), la pubblica e' anche in `VITE_VAPID_PUBLIC_KEY`
  (frontend, sia `.env.local` sia variabile d'ambiente Vercel di produzione).

**iOS**: le push funzionano solo se l'app e' stata aggiunta alla schermata Home (limite di
Safari, non di questo progetto) — su Android funzionano anche nel semplice browser.

**Verificato in rollback su dati reali**: RLS respinge l'inserimento di una sottoscrizione a
nome di un altro utente e accetta la propria; l'insert su `notifications` con il trigger
attivo si completa comunque. Non verificabile da qui: la consegna reale su un dispositivo,
che richiede una sottoscrizione vera generata da un browser — da provare in app.

### Pagina "Finanza": entrate/uscite del club con grafici

Nuova voce di menu (solo a stagione avviata: `seasonItems`/`offseasonItems`/`concludedItems`
di `GameNav.tsx`, non in draft). Legge `public.transactions` (RLS già corretta: un membro vede
solo le transazioni della propria squadra) filtrate alla stagione corrente, con card KPI
(budget attuale, entrate/uscite/saldo netto stagione), un grafico ad area sull'andamento del
saldo e uno a barre per categoria (Recharts — prima dipendenza UI di terze parti del progetto,
scelta esplicitamente dall'utente).

**Due cose non ovvie**:
- Le righe `rinnovo_in_stagione` hanno `importo` sempre positivo ma non sono un vero movimento
  di cassa (§10.4 bis: "rinnovare oggi non muove denaro oggi", infatti `saldo_dopo` non cambia
  per quelle righe). Sono escluse dai totali entrate/uscite e dal grafico a categoria, restano
  visibili nel registro con l'etichetta "nessun movimento di cassa".
- Il confine di stagione **non può** essere `seasons.creata_il` alla lettera per la stagione 1:
  quella riga nasce quando il draft finisce (stato → `'stagione'`), **dopo** che dotazione
  iniziale e ingaggi draft sono già stati registrati — verificato su dati reali (lega 29,
  squadra 56: dotazione delle 15:40, riga `seasons` delle 16:16). Per la stagione 1 quindi non
  si filtra affatto; dal 2 in poi si usa `creata_il` (il passaggio di stagione è un'unica
  operazione atomica, non ancora verificabile in produzione perché nessuna lega ha raggiunto la
  stagione 2).

### Sezione "Aiuto" in-app, raggiungibile anche prima di entrare in una lega

Sostituisce i due PDF statici (`docs/guida-giocatori.pdf`, `docs/guida-ruoli-ritiri-infortuni.pdf`)
con una guida sempre aggiornata dentro l'app: accordion di 19 argomenti (`ARGOMENTI_AIUTO` in
`src/components/Help.tsx`), voce di menu "Aiuto" in ogni fase di lega (draft incluso — a
differenza di Finanza) e, su richiesta dell'utente, anche in `MenuIniziale.tsx` (la schermata
prima di entrare in una lega), perché un partecipante deve poterla leggere prima ancora di
iscriversi.

**Contenuto volutamente neutro**: la prima stesura calcolava cifre concrete dal budget della
lega aperta (es. "ogni squadra riceve 100 M€"), ma quei valori li sceglie liberamente l'admin
lega per lega — l'utente l'ha corretto esplicitamente. Il testo ora cita solo percentuali e
formule relative (regole fisse del motore, es. "lo sponsor è il 20% della dotazione
iniziale"), mai importi assoluti, proprio perché la stessa guida deve valere identica sia
dentro una lega specifica sia nella schermata prima di sceglierne una, dove non esiste ancora
nessun `league` da cui leggere numeri.

### Buonuscita per lo svincolo anticipato (§9.5)

Segnalato dall'utente durante la revisione della guida "Aiuto" appena aggiunta: la spiegazione
del pagamento ingaggi diceva "svincolare un giocatore non dà nessun rimborso" senza nessun
costo legato alle stagioni residue — e infatti `svincola_giocatore` era davvero completamente
gratuito a prescindere dal contratto. Un vero exploit: rinnovare a 4 stagioni e disfarsene
dopo la prima senza mai pagare le altre tre.

Migrazione `20260807110000_buonuscita_svincolo.sql`. Formula scelta dall'utente: metà (per
difetto) dell'ingaggio delle stagioni residue dopo quella in corso —
`⌊(contratto_scadenza − stagione_corrente) × ingaggio / 2⌋`. Zero se è l'ultima stagione di
contratto o se il giocatore ha già annunciato il ritiro (esce comunque a fine stagione per
conto suo, §10.3, quindi non c'è nulla da "comprare"). Se il budget non copre la buonuscita lo
svincolo viene rifiutato con un messaggio che indica la cifra mancante, mai un budget negativo.

Verificato su dati reali (lega 37, istanza 1259: ingaggio 8 M€, 4 stagioni residue, budget 30
M€): buonuscita calcolata 16 M€, budget sceso a 14 M€, transazione `svincolo_buonuscita`
registrata con `importo = -16000000`. Verificato anche il rifiuto per budget insufficiente
(istanza 1116, buonuscita 6 M€ contro budget abbassato artificialmente a 1 M€, in una
transazione di prova mai committata) e i due casi a costo zero (ultima stagione di contratto;
ritiro annunciato). `db lint` invariato.

Lato client, `TeamProfile.tsx` mostra la buonuscita nella finestra di conferma prima di
premere "Svincola definitivamente" (calcolo di anteprima, la cifra vera la ricalcola comunque
il server). Aggiornati anche `docs/design.md` §5.4/§9.5 e la voce "Finanza — ingaggi e
insolvenza" della guida "Aiuto" in-app.

### La richiesta di rinnovo ora tiene conto della mentalità (§10.4 bis)

Segnalato dall'utente su un caso reale: M. Silvestri (istanza 1138), 34 anni, OVR 72,
bandiera 55 dominante, ingaggio 700k€. Alla trattativa chiedeva 800k€ — un aumento, per un
veterano in declino la cui mentalità dice "la maglia viene prima dei soldi". Il moltiplicatore
casuale sulla richiesta era fisso `uniform(1.00, 1.12)` per chiunque: mai uno sconto,
indipendentemente da età, declino o mentalità.

Fix scelto dall'utente fra tre opzioni proposte: **la mentalità sposta il centro del
moltiplicatore**, non il pavimento. `centro = 1.06 + (economia − bandiera) / 500`, range
`uniform(centro − 0.06, centro + 0.06)`. A mentalità equilibrata (33/33) il range resta
identico a prima (`[1.00, 1.12)` sul teorico) — verificato su 2000 semi via query diretta,
nessun giocatore medio cambia comportamento. Con Silvestri il centro scende a ~0,98: su 2000
semi la richiesta è rimasta **sempre e solo 700.000€** (il pavimento sull'ingaggio attuale,
mai toccato da questa modifica, ha sempre vinto sul calcolo). Con un giocatore economia-
dominante di controprova (10/60) il range è salito a `[800k, 900k]`, sopra il vecchio tetto
di 800k — conferma che la direzione economica funziona nei due sensi.

Migrazione `20260807100000_richiesta_rinnovo_da_mentalita.sql`: `private.rinnovo_proposta`
guadagna due parametri (`p_bandiera`, `p_economia`); `public.proposta_rinnovo` e
`public.offri_rinnovo` passano `v_player.mentalita_bandiera/economia`, già disponibili prima
della chiamata in entrambi. `db lint` invariato (solo i 2 warning di baseline pre-esistenti).

Deliberatamente **non toccato**: il pavimento `greatest(ingaggio_attuale, ...)` — l'utente ha
scelto l'opzione che lascia questa protezione (contro il sovrapprezzo pagato in asta) intatta,
non quella che l'avrebbe dissolta per permettere sconti reali sotto l'ingaggio attuale.

### Il bottone "Ritira" era stato aggiunto alla sezione sbagliata

Nella sessione precedente il bottone "Ritira offerta" (RPC `ritira_offerta`, già esistente e
funzionante) era stato aggiunto alla lista `<ul className="mercato-aste">` — che sta dentro
`{mostraListaLegacySvincolati && <>...}`, un flag **fermo a `false`** da prima (nascosto su
richiesta dell'utente, stesso pattern di `mostraArchivioSvincolati`). Il bottone non era mai
visibile: bug trovato perché l'utente ha chiesto "come si ritira un'offerta?" e non lo trovava.

Il componente davvero mostrato in "Asta a busta chiusa" è `cardSvincolato` (griglia
`free-agent-grid`). Il bottone "Ritira" è stato spostato lì, insieme a due richieste
correlate:

- **Svincolati raggruppati per ruolo** (portieri/difensori/centrocampisti/attaccanti, nuovo
  helper `perRuolo`), invece dell'ordine casuale dell'estrazione.
- **Nuova card "Le mie proposte"**, subito sotto "Asta a busta chiusa": mostra solo gli
  svincolati per cui hai già offerto, per modificare o ritirare l'offerta senza dover
  ripescare la carta giusta in una griglia di 24.

La sezione legacy con l'aggiunta della sessione precedente resta al suo posto (dormiente,
dietro il flag) invece di essere ripulita: stesso principio già in uso nel progetto per il
codice dietro un flag spento.

### Eccezione una tantum — le due tornate del 5/6 agosto unite per un giorno

Conseguenza diretta del bug appena corretto qui sotto. Sequenza reale su Real Fampionato (id
37): l'admin apre il mercato a mano la sera del 5 agosto (~23:30), poi il mattino del 6 il
vecchio cron delle 07:00 (non ancora corretto) ne apre un altro **senza chiudere il primo**.
Risultato: 12 svincolati del 5 e 12 del 6, tutti ancora `aperta` nel database — ci si può già
offrire su entrambi i gruppi, semplicemente la UI mostra solo il giorno più recente
(`asteDelGiorno` filtrava su un solo `giorno`).

Non è un problema di dati (nessun giocatore in comune fra i due giorni, verificato), solo di
visualizzazione. Soluzione scelta dall'utente: unire i due giorni **solo per oggi** invece di
correggere lato database (che avrebbe riscritto la data reale di un'estrazione già avvenuta).
In `Mercato.tsx`, `GIORNI_ECCEZIONE_6AGOSTO = ['2026-08-05', '2026-08-06']`: quando il giorno
più recente è uno di questi due, `asteDelGiorno` li unisce entrambi. **Si disattiva da sola**
il 7 agosto, quando il giorno più recente non è più nell'elenco — non va tolta a mano, ma se
si vuole ripulire il codice si può rimuovere dopo quella data senza alcun effetto.

### Mercato: apertura spostata a 23:30, e tre RPC che ignoravano l'apertura admin

Quattro segnalazioni dell'utente su una lega reale (Real Fampionato, id 37), dopo aver aperto
il mercato a mano la sera prima intorno alle 23:30. Migrazione
`20260807090000_mercato_apertura_2330.sql`. Dettagli in `docs/design.md` §9.1.

**Bug sistemico, non isolato**: `svincola_giocatore`, `proponi_scambio` e
`rispondi_a_proposta` controllavano `private.mercato_aperto()` (solo l'orario fisso), non
`private.mercato_aperto_lega(league_id)` (che considera anche `mercato_override_admin`, la
tabella dell'apertura manuale). Solo le tre RPC sulle aste svincolati usavano già la versione
corretta. Effetto pratico segnalato dall'utente: apri il mercato a mano, le aste si
sbloccano, **ma non puoi svincolare né proporre uno scambio** — stesso identico bug in tre
punti diversi, trovato cercando sistematicamente ogni funzione che chiama
`mercato_aperto()` invece di `mercato_aperto_lega()`. Tutte e sei le RPC del mercato ora si
comportano allo stesso modo.

**Apertura automatica spostata da 07:00 a 23:30**: le partite si simulano alle 23:00 (non a
mezzanotte), quindi 23:30 è davvero "30 minuti dopo le partite". Chiusura invariata alle
21:00. La finestra ora scavalca la mezzanotte (aperta 23:30→21:00 del giorno dopo, chiusa solo
nelle due ore e mezza 21:00–23:30): il confronto orario è diventato un OR (`ora ≥ 23:30 OR ora
< 21:00`) invece di un intervallo semplice, sia lato server sia nella copia JS del frontend
(`Mercato.tsx`, usata solo per non far comporre una proposta che il database rifiuterebbe).

**L'estrazione dei nuovi svincolati segue la stessa apertura.** Con un cron che gira una
volta l'ora non si può intercettare un confine a mezz'ora in modo affidabile: il job
`estrazione-svincolati` passa da un giro l'ora a quattro (ogni 15 minuti,
`cron.alter_job`), e la guardia interna diventa una finestra di 15 minuti (23:30–23:45)
invece di un'ora esatta — scatta una volta sola al giorno anche col fuso che scivola con
l'ora legale (CLAUDE.md §2). Gli altri cron (chiusura 21:00, simulazione 23:00) restano su
un giro l'ora: cadono su un'ora esatta, non serve altro.

**Ritira offerta**: la RPC `ritira_offerta` esisteva già (controlla proprietà e finestra di
mercato lato server) ma nessun bottone la richiamava — ci si poteva solo pentire *modificando*
un'offerta su uno svincolato, mai ritirandola. Aggiunto il bottone "Ritira" accanto a
"Modifica" nella card dell'asta.

**Messaggio di svincolo che restava fisso**: ora sparisce da solo dopo 2 secondi, stesso
pattern già usato per la lista trasferimenti (cleanup del timer se arriva un altro avviso o
si cambia pagina).

**Verificato in rollback su dati reali** (Real Fampionato): 12 controlli tutti OK — la nuova
finestra oraria su 7 orari campione, le tre RPC che non chiamano più `mercato_aperto()` nudo,
e lo svincolo di un giocatore vero con l'override admin attivo che **riesce indipendentemente
dall'ora reale** (prima falliva sempre). `db lint` invariato.

### Pannello admin raggiungibile anche in draft

Richiesta dell'utente. Puramente frontend, nessuna migrazione.

Il pannello era riservato a `stato = 'stagione'`, perché le tre azioni di riserva (simula
giornata, apri/chiudi mercato) hanno senso solo lì. Ma "Elimina lega" no — anzi serve
soprattutto **in draft**, dove una lega può restare bloccata (è successo davvero: Fampionato,
vedi la voce sul fix della solvibilità draft più sotto) e l'unica via d'uscita era cancellarla
a mano dal database.

Due punti separati, entrambi necessari:

- **`GameNav.tsx`**: la voce "Admin" ora compare per l'amministratore in ogni fase tranne
  l'off-season (che ha già un pannello dedicato), non solo a `stato = 'stagione'`.
- **`App.tsx`**: bug trovato mentre verificavo il primo punto — il routing per `stato =
  'draft'` reindirizzava **sempre** a `Draft` (o `Rosa` per `squad`), ignorando qualunque
  altra vista scelta. Aggiungere la voce di menu da sola non sarebbe bastata: cliccarla non
  avrebbe portato da nessuna parte. Aggiunto il ramo `gameView === 'admin'` allo stesso modo
  di `squad`.
- **`Admin.tsx`**: le tre card stagionali (Simula giornata, Mercato) sono condizionate a
  `stato === 'stagione'`; "Elimina lega" resta sempre visibile. Fuori stagione il testo in
  cima lo dice esplicitamente, invece di mostrare card che fallirebbero cliccandole.

### Elimina lega — pannello admin

Richiesta dell'utente. Migrazioni `20260805230000_elimina_lega.sql` e
`20260805240000_fix_elimina_lega_restrict.sql`. Dettagli in `docs/design.md`, fine §9.

**Conferma testuale, non un semplice OK/Annulla**: bisogna ridigitare il nome esatto della
lega — l'impatto è su tutti i partecipanti, non solo su chi elimina, quindi la frizione
richiesta è più alta di un doppio clic.

**Trovato e corretto un bug reale durante la prima verifica**: la funzione falliva sempre,
bloccata da due foreign key `RESTRICT` non coperte da cascade — `match_stats.player_instance_id`
e `transactions.team_id`, entrambe volute (sono i registri append-only che CLAUDE.md protegge
esplicitamente). Non ho allentato quei vincoli (proteggono ogni altro percorso dell'app): la
funzione ora svuota esplicitamente le due tabelle per quella lega prima della cascade generale.

**Secondo difetto trovato nella stessa verifica, preesistente e non causato da questa
richiesta**: `season_morale_checkpoints` (di ieri) non aveva **nessuna** foreign key, né su
`season_id` né su `league_id` — a differenza di `season_progression_checkpoints`, che le ha
entrambe cascade. Non bloccava l'eliminazione (senza FK non c'è nulla da controllare) ma
avrebbe lasciato righe orfane per sempre in ogni lega eliminata. Corretto nella stessa
migrazione.

**Verificato in rollback su una lega reale** (id 29, 5 squadre, 120 giocatori, 1 stagione, 2
checkpoint morale): un non-admin respinto, nome di conferma sbagliato respinto, e con la
conferma corretta la lega **sparisce davvero** — squadre, giocatori, stagioni e checkpoint
morale tutti a zero — poi tutto annullato dal `rollback` finale, nessun dato reale perso.

**UI**: nuova card rosso-bordata in fondo al pannello Admin. Il bottone di conferma resta
disabilitato finché il testo digitato non coincide esattamente col nome della lega. Dopo
l'eliminazione si torna al menu iniziale (non c'è più una pagina di lega a cui tornare).

### Lista trasferimenti — "Mercato della lega"

Richiesta dell'utente. Migrazione `20260805220000_lista_trasferimenti.sql`, dettagli in
`docs/design.md` §9.4 bis.

Dalla scheda di un proprio giocatore, sotto "Svincola" e "Rinnovo", un bottone a piena
larghezza **"Metti sul mercato"** (che diventa "Rimuovi dal mercato"), con messaggio di
conferma verde. Nella pagina Mercato, subito dopo l'asta a busta chiusa, la card **"Mercato
della lega"** con la vetrina di tutti i giocatori in lista, filtrabile per ruolo, età e
overall — filtri **indipendenti** da quelli dell'archivio svincolati, sono due elenchi diversi.

**È una vetrina che porta dritta alla proposta**: cliccando una card non si apre la scheda
del giocatore ma il compositore "Nuova proposta" più sotto nella stessa pagina, con
l'avversaria e il giocatore richiesto già pre-selezionati — un solo tocco invece di tre
(scegli squadra → scegli giocatore → scorri). Non è un vero modale sopra la pagina: è la
sezione esistente di §9.2, pre-compilata e portata in vista con `scrollIntoView`. Nessun nuovo
componente, stessa logica di invio già in uso per le proposte di scambio manuali.

Nessuna policy RLS nuova: `player_instances_lettura` permette già a ogni membro di leggere
tutte le rose della lega, basta filtrare sul flag. Un **trigger azzera il flag al cambio di
squadra**: un giocatore appena acquistato non deve risultare già in vetrina per il nuovo
proprietario, che quella scelta non l'ha mai fatta.

**Verificato in rollback su dati reali** (lega 29): messo in lista dal proprietario, visibile
agli altri membri della lega, **non rimovibile da chi non lo possiede**, e flag azzerato dal
trasferimento.

### Un rinnovo per stagione, e contratti leggibili nella rosa

Richieste dell'utente. Migrazione `20260805210000_un_rinnovo_per_stagione.sql`.

**Un solo rinnovo per stagione.** Chi ha appena firmato non può ritrattare subito: se ne
riparla dalla stagione successiva. Nuova colonna `player_instances.rinnovo_stagione`, scritta
alla firma; `offri_rinnovo` respinge un secondo rinnovo nella stessa stagione e
`proposta_rinnovo` espone il flag `gia_rinnovato` così la UI può disabilitare il bottone col
motivo. Senza questo vincolo il rinnovo era ripetibile all'infinito nella stessa stagione — e
siccome firmare azzera i tentativi, si sarebbe azzerato anche il costo della trattativa,
rendendo di nuovo aggirabile il limite dei tre tentativi.

**Chi ha annunciato il ritiro non tratta**: era già così (guardia UI + server), verificato.

**Riepilogo rosa**: l'ingaggio è ora espresso `/stagione` (non `/anno` — il gioco scandisce il
tempo in stagioni, coerente col resto del vocabolario) e accanto compare la durata residua.
In rosso quando la squadra sta per perdere il giocatore: "ultima stagione" o "ritiro a termine
stag.". Il colore resta un segnale, non decorazione.

**Verificato in rollback su dati reali** (lega 29): 6 controlli tutti OK — flag basso prima
del rinnovo, firma accettata, flag alzato dopo, secondo rinnovo respinto lato server anche
raddoppiando l'offerta, stagione della firma memorizzata, e chi si ritira non apre nemmeno la
trattativa.

### Trattativa sul rinnovo, e i rinnovi di off-season eliminati

Due decisioni dell'utente nella stessa richiesta. Migrazioni
`20260805170000_via_rinnovi_offseason.sql`, `20260805180000_trattativa_rinnovo.sql`,
`20260805190000_fix_cast_offri_rinnovo.sql`, `20260805200000_fix_lint_proposta_rinnovo_2.sql`.
Dettagli in `docs/design.md` §10.4 (rimosso) e §10.4 bis.

**Via i rinnovi di off-season.** Restava un canale doppio: quello di giugno (§10.4) e quello
in stagione. Ora chi arriva a fine off-season col contratto scaduto lascia semplicemente la
squadra ed entra nel pool svincolati. `prepara_offseason` non genera più `contract_renewals`;
`finalizza_offseason` legge direttamente `contratto_scadenza` invece delle trattative aperte.
Le tabelle `contract_renewals` e `contract_renewal_terms` **non sono state droppate**:
contengono 195 righe di una lega reale e restano come archivio storico, semplicemente non si
scrive più. Anche `rispondi_rinnovo` resta in piedi ma non ha più nulla da leggere — droppare
una funzione ancora referenziata darebbe un errore peggiore di una lista vuota; è il frontend
che ha smesso di chiamarla.

> **Effetto collaterale voluto**: rende definitiva la regola dei tre tentativi. Finché il
> rinnovo di off-season esisteva, chi aveva chiuso la trattativa era recuperabile aspettando
> giugno — la conseguenza era aggirabile. Era il problema aperto segnalato ieri.

**Trattativa su due assi.** Il giocatore apre con cifra e durata, poi si tratta su entrambe.
I due assi **si compensano**: allontanarsi dalla durata che chiede svaluta l'offerta del 7%
per stagione di scarto, da compensare con l'ingaggio — senza questo la durata sarebbe una
scelta finta (converrebbe sempre il massimo). La **tolleranza** (0-25%, quanto scende sotto la
sua richiesta) dipende da morale e mentalità e **non è mai mostrata**: se lo fosse si
calcolerebbe la soglia esatta e la trattativa diventerebbe aritmetica. Misurato: una bandiera
serena in una squadra prima concede il 20%, un avido scontento e ultimo concede zero.

**Tre tentativi**, rifiuto informativo ma che consuma un tentativo; esauriti, il giocatore va
a scadenza. Il contatore (`player_instances.rinnovo_tentativi`) si azzera **solo** firmando.

**Verificato in rollback su dati reali** (lega 29): 8 controlli tutti OK — offerta minima
rifiutata col tentativo consumato, messaggi informativi diversi per distanza, offerta piena
accettata con contatore azzerato, firma scritta su `player_instances`, terzo rifiuto che
chiude, e nessuna trattativa possibile dopo la chiusura **nemmeno triplicando l'offerta**.

> **Difetto trovato e corretto durante la verifica**: `coalesce(v_posizione, 1)` restituiva un
> `integer` (il letterale 1 non è `smallint`), quindi la chiamata a `rinnovo_tolleranza` non
> trovava la firma e `offri_rinnovo` falliva a ogni invocazione. Corretto col cast esplicito.

**UI**: la vista rinnovo ha ora due campi (ingaggio in M€, durata 1-4), il contatore dei
tentativi rimasti, e la risposta del giocatore virgolettata. La card ingaggio della scheda
mostra anche la durata residua del contratto ("ancora 2 stagioni dopo questa" / "In scadenza a
fine stagione"). Rimossa la card rinnovi da `Offseason.tsx` e tutto il codice morto collegato.

### Mentalità e morale — base pronta

Richiesta dell'utente, dettagli in `docs/design.md` §10 bis. Migrazioni
`20260805150000_mentalita_e_morale.sql` e `20260805160000_fix_riferimenti_mentalita.sql`.

**Mentalità**: tre rami che si dividono 100 punti (bandiera / economia / vittorie) — dicono
*cosa viene prima*, non quanto vale il giocatore. Il dataset FC 26 non contiene nulla di
simile, quindi è **generata deterministicamente dall'id**: stesso giocatore, stessa
personalità in ogni lega e per sempre. Implementata come **colonne generate** su `players`,
non riempite da un UPDATE: così non può esistere il caso "importato dopo, senza mentalità"
(è già successo coi 576 del pool élite globale) né andare fuori sincrono. Serve una funzione
`IMMUTABLE`, quindi aritmetica pura — `hashtext()` è solo `STABLE`.

> **Trappola incontrata e risolta**: i tre rami devono usare tre moltiplicatori **diversi**.
> Il primo tentativo usava lo stesso moltiplicatore con un offset per ramo, producendo rami
> correlati (`r2 = r1 + costante`): "bandiera" risultava dominante solo 1.123 volte sui 5.992
> giocatori contro le ~2.434 delle altre due. Con moltiplicatori distinti: 1.908 / 1.996 /
> 1.897, un terzo ciascuno.

**Morale**: 0-100 per istanza, parte da 70, ricalcolato a ogni quarto di stagione da
`applica_morale_checkpoint`, chiamata dalla Edge Function subito dopo la progressione overall.
Funzione e registro (`season_morale_checkpoints`) **separati** dalla progressione: stesso
ritmo, ma si può correggere una senza toccare l'altra. Componenti: minutaggio (vale per tutti,
asimmetrico — deludere pesa più che gratificare), economia e vittorie (pesate dal rispettivo
ramo), e la **bandiera che non è un contributo a sé ma attenua le insoddisfazioni** — che è
la definizione data dall'utente: chi è bandiera si lamenta meno, non è più felice a prescindere.

**Il morale non tocca il rendimento in campo** (decisione dell'utente): `engine/` intatto,
nessun protocollo di validazione richiesto. Serve ai rinnovi.

**UI**: card "Morale" sotto quella della forma fisica nella scheda giocatore, con etichetta
parlata (Entusiasta → In rotta con la squadra), barra colorata per fascia, e i tre rami della
mentalità col dominante evidenziato. Visibile solo sulla propria rosa.

**Verificato in rollback su dati reali**: somma dei rami sempre 100 su tutti i 5.992 giocatori,
distribuzione del dominante equilibrata, idempotenza del checkpoint, morale sempre in 0-100,
chi gioca sta meglio di chi non gioca (77 vs 62) e a parità di zero minuti chi ha bandiera
alta sta meglio di chi ce l'ha bassa (65 vs 60). `db lint` pulito.

> **Fatto il 5 agosto**: la trattativa è stata implementata (vedi la sezione in cima) e i
> rinnovi di off-season sono stati eliminati, il che ha risolto anche il problema
> dell'aggiramento aspettando giugno.

### Rinnovo contrattuale a stagione in corso

Richiesta dell'utente: finora si rinnovava solo in off-season (`rispondi_rinnovo`, legata a
`contract_renewals.offseason_id` NOT NULL). Ora c'è un canale separato dalla scheda giocatore,
su contratti ancora in corso. Migrazioni `20260805130000_rinnovo_in_stagione.sql` e
`20260805140000_fix_lint_proposta_rinnovo.sql`. Dettagli in `docs/design.md` §10.4 bis.

- **È il giocatore a proporre**, non la squadra a offrire: cifra secca + durata, da prendere o
  lasciare. Niente range ±12% né soglia al 90% — quella meccanica esiste perché in off-season
  il contratto è scaduto e la squadra ha leva; qui il giocatore è sotto contratto e non ha
  bisogno di firmare.
- **Proposta deterministica** su `(istanza, overall, età, ingaggio)`: riaprire la scheda mostra
  sempre la stessa cifra. Senza, con un `random()` vero basterebbe chiudere e riaprire finché
  non esce un numero comodo. Per lo stesso motivo **non serve una tabella di stato**: si
  ricalcola identica, e firmare scrive direttamente su `player_instances`.
- **Durata coerente con l'età** (4 stagioni fino a 23 anni, 1 sola dai 36 in su).
- **Decorrenza dalle stagioni successive**: quella corrente è già stata addebitata a inizio
  stagione (§5.4), quindi rinnovare oggi non muove denaro oggi — il costo è l'impegno futuro.
  Nuova scadenza `max(scadenza_attuale, stagione_corrente + durata)`: non accorcia mai.
- **La cifra è ricalcolata server-side** in `accetta_rinnovo_stagione`: il browser non decide
  mai quanto si paga, una proposta ritoccata viene respinta.
- **UI**: bottone "Rinnovo" accanto a "Svincola" nella scheda giocatore; apre una vista con
  ritratto grande e la proposta scritta in prima persona dal giocatore, rivolta al mister (il
  nome dell'allenatore arriva da `profiles`).
- **Verificato in un rollback su dati reali** (lega 32): 10 controlli, tutti OK — determinismo
  su due letture, pavimento all'ingaggio attuale, cifra ritoccata respinta, firma valida,
  ingaggio e scadenza aggiornati, scadenza mai accorciata, transazione registrata, durata ≤1
  per tutti gli over 36 della lega, durata sempre in 1..4 su tutta la rosa. `db lint` pulito.

**Non ancora fatto, discusso con l'utente nella stessa sessione**: la meccanica del **morale**
e la statistica **MENTALITÀ** (tre rami: bandiera / economia / vittorie), con card sotto quella
della forma fisica e check a ogni 25% di stagione. Decisioni già prese: il morale inciderà
**solo su rinnovi e richieste economiche, mai sul rendimento in campo** (così non tocca
`engine/` e non serve il protocollo di CLAUDE.md §4), e la MENTALITÀ sarà **generata in modo
deterministico dall'id del giocatore** (stessa in ogni lega, per sempre) — il dataset FC 26
non la contiene: le colonne `mentality_*` non sono importate e comunque non misurano
attaccamento o avidità. Il morale terrà conto anche di quanto un giocatore gioca rispetto a
quanto ritiene di dover giocare, calcolato dalla sua posizione rispetto all'overall medio
della rosa.

### Ingaggi — mod_età invertito, premio ai giovani forti

Decisione dell'utente dopo aver giocato: un giovane già forte costava un terzo di un adulto
di pari overall (design §5.1, scala precedente: 16-20 a ×0,35, picco ×1,00 a 27-30) — ed è
anche l'unico che cresce **gratis** per anni verso il potenziale sotto lo stesso contratto
scontato (progressione trimestrale, §6.2/§10.2). Doppio vantaggio, non uno solo: un 19enne da
84 OVR costava 2,6 M€ contro i 10,0 M€ di un 28enne di pari livello.

Filosofia ribaltata: chi è giovane e già forte ora **paga il potenziale**, non solo
l'overall attuale. Nuova scala (`20260805120000_ingaggio_premio_giovani.sql`, solo
`private.ingaggio_teorico`, `base(overall)` invariato):

| Età | 16-20 | 21-23 | 24-26 | 27-30 | 31-32 | 33-34 | 35+ |
|---|---|---|---|---|---|---|---|
| Mod | 1,25 | 1,10 | 1,00 | 0,95 | 0,80 | 0,60 | 0,40 |

Il picco si sposta da 27-30 a 24-26; gli over 30 restano scontati verso fine carriera,
coerente col resto del gioco (rinnovi, ritiro). Un giovane da 84 OVR ora costa 9,4 M€ (prima
2,6 M€). Nessun chiamante toccato: la funzione è definita una sola volta e richiamata per
nome da draft, aste, rinnovi e off-season. Verificato sui valori d'esempio del design doc via
`db query`; `db lint` invariato.

### Stile di gioco — nuova leva tattica indipendente dal modulo

Richiesta dell'utente: oltre al modulo, scegliere anche uno stile di gioco con effetto reale
sul risultato. Sette voci (design §6.8): `equilibrato` (default), `contropiede`,
`possesso_palla`, `fasce`, `recupero_veloce`, `diretto`, `blocco_basso` — le quattro chieste
dall'utente più tre proposte per completare le coppie filosofiche (possesso↔diretto,
contropiede↔pressing) e il neutro obbligatorio.

**Aggancio al motore, senza toccare formule protette da CLAUDE.md §4**: `engine/engine.js`
calcola già le tre linee ATT/MID/DEF come somma additiva in punti di overall (forza media +
profilo strutturale + familiarità + bonus casa). Lo stile entra come un ulteriore addendo
della stessa somma (`stileTattico()`, nuova funzione pura, stesso stile di `familiarita()`) —
l'xG esponenziale, il profilo strutturale e il calcolo del controllo restano bit-per-bit
identici. `opt.stileCasa`/`opt.stileOspite` sono due nuove chiavi dentro l'oggetto `opt` già
esistente di `simulaPartita`, non nuovi parametri posizionali: nessuna chiamata esistente (7
in `tools/validazione/simulate.js`, la Edge Function) le passava, quindi risolvono tutte a
`equilibrato` = `{0,0,0}`. **Verificato**: `node tools/validazione/simulate.js` produce un
diff zero contro `docs/risultati-fase0.txt` dopo la modifica.

Ogni stile è una redistribuzione **a somma zero** tra DEF/MID/ATT (nessuno è un buff netto),
magnitudine paragonabile a bonus casa/familiarità/clamp strutturale già esistenti. Valori e
verifica direzionale (4000 partite per stile, contro una squadra equilibrata di pari livello)
in design.md §6.8: ogni stile mostra il trade-off atteso (chi attacca di più concede di più,
chi si chiude segna meno), nessuno domina. Deliberatamente **senza** familiarità/curva di
apprendimento per lo stile (a differenza del modulo) — non richiesta, avrebbe aggiunto
un'altra dimensione di bilanciamento (7 moduli × 7 stili) da validare.

**Schema**: `20260805110000_stile_di_gioco.sql`. Stesso pattern già in uso per il modulo:
`private.stili_validi()` (vocabolario controllato, sync a mano con `engine/config.js STILI`),
colonna `lineups.stile_gioco` (default `'equilibrato'`, così le formazioni già salvate
restano invariate), colonne `matches.stile_home`/`stile_away` a fotografia (specchio di
`modulo_home`/`modulo_away`). `salva_formazione` e `registra_risultato_partita` estese con
`p_stile_gioco`/`p_stile_home`/`p_stile_away`, stesso trattamento del `modulo` in ogni
validazione. `db lint` invariato.

**UI**: `Formazione.tsx`, nuovo selettore a tendina a destra di quello del modulo, stessa
struttura trigger/menu/scrim ma volutamente più piccolo (i nomi degli stili sono più lunghi,
non deve competere con il font enorme del modulo che resta la card dominante). Descrizione
breve sotto al nome di ciascuno stile nel menu, come richiesto.

### Fix — il vincolo di solvibilità del draft controllava il budget iniziale, non il tetto draft

Segnalato dall'utente su una lega reale (Fampionato, id 34, budget iniziale 70M / tetto
draft 40M, configurato separatamente dal 4 agosto): il draft si è bloccato con due squadre
su cinque arrivate senza più margine sotto il tetto per completare i 24 slot a 0,5M minimo,
impedendo l'avvio della stagione.

`private.pick_sostenibile` (design §4.4) confrontava la riserva per gli slot rimanenti col
**portafoglio della squadra** (`budget_iniziale - speso`) invece che col **tetto draft
residuo** (`budget_draft - speso`). Quando il tetto era vicino all'80% di default del budget
iniziale il bug quasi non si vedeva; con un tetto scelto molto più stretto (com'è possibile
dalla configurabilità del 4 agosto) il portafoglio residuo resta sempre ampiamente
sufficiente anche col tetto ormai esaurito, e il vincolo non blocca mai nulla in pratica —
esattamente il deadlock descritto in `CLAUDE.md` §7. Verificato sui dati reali: Amburgo a
22/24 aveva speso 39,5M dei 40M di tetto (margine 0,5M, ne servivano 1,0M per 2 slot); Team
AS Turbo a 16/24 aveva speso 38,8M (margine 1,2M, ne servivano 4,0M per 8 slot). In entrambi
i casi il portafoglio (30-31M sui 70M iniziali) copriva ampiamente il vecchio controllo.

Corretto in `20260805090000_fix_solvibilita_tetto_draft.sql` riscrivendo la riserva sul
tetto draft residuo, che assorbe anche il vecchio secondo controllo (all'ultimo slot la
condizione equivale a `speso + ingaggio <= tetto`). Dato che `budget_draft` ha un minimo di
20M già vincolato in DB e 24 slot al floor di 0,5M richiedono 12M, il draft è ora
completabile per costruzione qualunque sia la combinazione budget_iniziale/budget_draft.
Aggiunta anche in `Draft.tsx` la cifra "puoi spendere fino a X sul prossimo giocatore" nella
barra budget, calcolata con la stessa formula del vincolo server-side.

**Lega 34 non recuperata**: l'utente ha scelto di cancellarla e ricrearla invece di
sbloccare le due squadre incastrate con spese già registrate sopra il nuovo tetto corretto.

### Albo d'oro della lega

La navigazione della lega include la sezione **Albo d'oro**, disponibile in
draft, stagione, off-season e a campionato concluso. Legge le sole stagioni
`conclusa` della lega corrente, individua la riga di classifica in posizione
1 e mostra squadra campione, stemma, punti e record. Non introduce nuove
tabelle: `seasons`, `standings` e `teams` erano gia' protetti dalle policy RLS
per i membri della lega. La card principale celebra il campione in carica; in
assenza di stagioni concluse mostra uno stato vuoto esplicativo.

### Centro Avvisi nella navigazione della lega

Gli avvisi non sono piu' un pannello a comparsa nella sidebar o nel drawer.
La nuova voce **Avvisi** apre una pagina dedicata con badge delle non lette,
apertura dell'evento collegato, cancellazione della singola riga e stato vuoto.
Lo stato di `useNotifiche` ora vive una sola volta in `App` e viene condiviso
dal menu e dalla pagina tramite contesto: nessuna doppia sottoscrizione Realtime
e il badge si aggiorna immediatamente quando arriva un avviso.

### Pool élite globale — 576 giocatori esterni

Richiesta dell'utente: aggiungere i migliori giocatori dei campionati non
presenti nel pool base. La pipeline `normalizza.py --elite-globale` legge lo
stesso snapshot FC 26, esclude le 10 leghe già importate e le 20 righe senza
campionato. Importati **355** giocatori OVR 75+ da 24 campionati/117 club e,
su richiesta successiva, **221** under 22 con OVR 67–74 dalle stesse leghe
esterne qualificate. Tutti hanno `players.elite_globale = true` (catalogo:
5.992 giocatori) e nessuno esce dalle due fasce. La migrazione
`20260804210000_pool_elite_globale.sql` li mantiene col campionato originale
ma li rende idonei a draft, estrazioni mercato e spin in ogni lega, senza
cambiare le liste di campionati configurabili.

### Filtro temporaneo del pool giocatori

Per il test richiesto dall'utente, la migrazione
`20260804204000_filtro_pool_giocatori_test.sql` marca come non estraibili i
giocatori con overall inferiore a 66 ed età superiore a 22 anni, oltre a tutti
gli overall inferiori a 60 indipendentemente dall'età. Sono **831** record:
restano integralmente nel catalogo e nelle rose esistenti, ma non possono
comparire in nuovo draft, aste svincolati o spin off-season. Il flag
`players.disponibile_estrazione` è reversibile: per riattivarli basta impostarlo
a `true`, senza importare o ricreare dati.

### Progressione overall — quattro checkpoint stagionali

Decisione dell'utente: gli overall non aspettano più la sola off-season. La migrazione
`20260804200000_progressione_overall_trimestrale.sql` distribuisce la formula annuale
di `design.md` §10.2 alla conclusione del 25%, 50%, 75% e 100% delle giornate reali.
La Edge Function `simula-giornata` chiama la RPC dopo avere registrato il turno. Il
registro `season_progression_checkpoints` la rende idempotente; per le stagioni già
avviate recupera al massimo un checkpoint arretrato per giornata, evitando salti multipli.
L'off-season ora aumenta soltanto l'età, recupera condizione/infortuni e apre i rinnovi:
non applica un quinto cambio OVR.

Ultimo aggiornamento: **5 agosto 2026**. Questo documento descrive lo stato reale del
repository ed è il punto di partenza per il prossimo agent (Claude o Codex).

### Tabellino — un subentrato non può più segnare prima di entrare in campo

Segnalato dall'utente su una lega reale (Batshuayi marcatore al 36' pur partito in panchina,
entrato solo a inizio ripresa). Causa in `supabase/functions/simula-giornata/index.ts`, non
nell'engine: i marcatori arrivano dal motore come lista aggregata di fine partita senza legame
col blocco, e l'abbinamento a un evento cronologico era puramente in ordine, senza controllare
la presenza in campo. `engine.js` ora espone anche `presenzePerBlocco` (dato aggiuntivo, zero
formule toccate — suite di validazione byte-per-byte identica dopo la modifica); la Edge
Function sceglie fra i marcatori rimasti chi era davvero presente nel blocco dell'evento. Il
totale di gol/assist per giocatore a fine partita resta quello del motore, cambia solo in quale
blocco viene mostrata l'occorrenza. Dettagli e verifica in `docs/motore-validazione.md`.

### Ritiro dei giocatori — nuova tabella di probabilità, annuncio in due fasi

Sostituisce integralmente il vecchio meccanismo (formula lineare `(età−33)×0.12`, ritiro tirato
e applicato nello stesso istante a fine stagione). Decisione dell'utente, dettagli e tabella
completa in `docs/design.md` §10.3. Migrazione `20260804150000_ritiro_giocatori.sql`.

- **`private.probabilita_ritiro(età)`**: nuova tabella 34→10% ... 41→99%, 42+ automatico.
- **Annuncio a inizio stagione (`finalizza_offseason`), uscita a fine stagione
  (`prepara_offseason`)**: prima erano lo stesso istante. Ora chi annuncia gioca tutta la
  stagione ma non è più cedibile (`player_instances.ritiro_annunciato`); alla transizione
  successiva `prepara_offseason` lo rimuove per davvero, **prima** di invecchiare gli altri (il
  roll del ritiro non c'è più in quel loop: si decide solo a inizio stagione).
- **`svincola_giocatore`**: se il giocatore aveva già annunciato, lo svincolo è definitivo (non
  torna disponibile), non un normale passaggio nel pool.
- **`proponi_scambio` e `rispondi_a_proposta`**: rifiutano qualunque proposta che coinvolga un
  giocatore con l'annuncio attivo, in offerta o in richiesta.
- **Giocatori mai scelti da nessuno**: stesso calcolo ogni inizio stagione, età derivata (età
  di catalogo + stagioni passate nella lega, perché il pool svincolati non fa mai invecchiare
  le istanze non possedute). Se il dado dice ritiro finiscono nella nuova tabella
  `public.retired_players(league_id, player_id)`, esclusi per sempre da quella lega **senza
  essere mai passati da una squadra**.
- **`retired_players` come controllo unico**, aggiunto a tutte le query che pescano un pool:
  `estrai_svincolati_lega`, `offri_per_svincolato_archivio`, `pesca_carta_ruolo` (draft),
  `spin_offseason`. Bug di rimbalzo sistemato di riflesso: prima un giocatore già ritirato
  poteva ricomparire nel mercato, perché quelle query controllavano solo "è posseduto da
  qualcuno?", mai `ritirato`.
- **Domanda dell'utente sull'età, verificata e confermata corretta**: una stagione avanza
  l'età di 1 anno per ogni giocatore a ogni transizione (`prepara_offseason`), indipendente dai
  giorni reali trascorsi. Non serviva nessuna modifica.
- **Verificato in un rollback su dati reali** (lega 32): tabella di probabilità su tutte le età
  di riferimento, finalizzazione di un annuncio precedente, annuncio deterministico a 45 anni
  (p=1.0), nessun annuncio sotto i 34, ritiro di un giocatore mai scelto (età derivata forzata a
  45), esclusione dal pool di estrazione, svincolo normale vs svincolo definitivo di un
  annunciato, rifiuto di `proponi_scambio` su un giocatore annunciato. Nove verifiche, tutte OK.

### Motore — due correzioni dopo la Fase 0, entrambe segnalate dall'utente su dati reali

Prime modifiche al motore dopo la Fase 0, entrambe fatte seguendo il protocollo di CLAUDE.md
§4: descritte, applicate, suite rilanciata per intero, confrontate con
`docs/risultati-fase0.txt` (aggiornato dopo ciascuna).

1. **Varianza dei tiri per partita.** Alcune partite reali avevano 35-37 tiri per una squadra
   contro il target validato di 11-14. La media era ed è corretta (`tools/validazione/
   simulate.js` misura solo quella); il difetto era nella varianza di `CONVERSIONE_SIGMA`
   (0,03 in `engine/config.js`), che mandava la conversione sul tetto basso del clamp (0,07)
   circa 1 partita su 8, raddoppiando i tiri anche con un xG normale. Ridotta a `0.015`: media
   tiri invariata (12,1-12,4), quota di partite con 30+ tiri scesa dal ~12% teorico allo 0,14%
   osservato su 10.000 simulazioni. Dettagli in `docs/motore-validazione.md` e `docs/design.md`
   §7.3.
2. **Il portiere si stancava come un giocatore di movimento.** Segnalato dall'utente: dopo una
   partita il proprio portiere era il più stanco della rosa, all'80%. Il consumo di condizione
   per blocco si applicava a tutti i titolari senza eccezioni — l'unica eccezione per il
   portiere era nelle sostituzioni (non viene mai cambiato per stanchezza, dal 2 agosto), non
   nel consumo stesso. Corretto in `engine.js`: il portiere non consuma più condizione, resta
   stabile salvo infortuni. Unico target che si sposta: "Condizione titolari a fine stagione"
   sale da 88,5 a 90,4 (target 75-95, resta OK) — atteso, il portiere è sempre uno degli 11
   titolari. Dettagli in `docs/motore-validazione.md`; anche la sezione "Costanti finali" di
   `docs/design.md` era ferma ai valori pre-2-agosto (`CONSUMO_BASE`, `REC_*`) ed è stata
   allineata nella stessa occasione.

### Mercato — chiarezza ingaggio, richiesta di rinnovo ancorata, archivio nascosto

Quattro correzioni volute dall'utente dopo aver provato il mercato con dati reali, migrazione
`20260804120000_rinnovo_ancorato_e_stagioni.sql`:

1. **Label "Valore" → "Ingaggio minimo"** nelle card degli svincolati (`Mercato.tsx`). L'utente
   la leggeva come un cartellino di trasferimento, che nel gioco non esiste — l'asta è sempre e
   solo ingaggio annuale (design §9.4). Il numero mostrato resta `ingaggio_teorico`: è un
   riferimento pubblico, non una garanzia, perché la soglia vera nascosta può salire fino al 10%
   sopra (vedi nota aggiunta in design.md §9.4).
2. **Vocabolario "stagioni" invece di "anni"** per la durata dei contratti, sia in
   `Offseason.tsx` (select e riepilogo del rinnovo accettato) sia nei messaggi generati dal
   server (`rispondi_rinnovo`, `risolvi_aste_giorno`).
3. **La richiesta di rinnovo si ancora all'ingaggio attuale** (design §10.4): prima ripartiva
   ogni volta dal solo `ingaggio_teorico(OVR, età)`, quindi un giocatore aggiudicato molto sopra
   il suo valore teorico (asta cara, o pick di draft fortunato) tornava a chiedere il teorico più
   basso al primo rinnovo, cancellando il sovrapprezzo pagato. Ora
   `richiesta = max(ingaggio_attuale, formula teorica)`. Il range ±12% mostrato e la soglia di
   accettazione al 90% restano identici, applicati sopra il nuovo pavimento: è lì che sta il
   margine di trattativa verso il basso. Verificato in un rollback su una lega reale (id 32):
   ingaggio forzato a 3× il teorico (13,5 M€ contro 4,5 M€), la richiesta esatta generata da
   `prepara_offseason` è risultata 13,5 M€, non il teorico più basso.
4. **Archivio svincolati nascosto**, non rimosso: l'utente vuole provare il mercato senza prima
   di decidere se tenerlo. `Mercato.tsx` ha un flag `mostraArchivioSvincolati = false` (stesso
   pattern già usato per `mostraListaLegacySvincolati`) che nasconde il blocco via rendering
   condizionale — codice, funzioni e stato restano tutti al loro posto, si riattiva con `true`.

### Pannello admin — fallback manuale se pg_cron non parte

Decisione utente. Tre azioni, visibili solo all'amministratore della lega (voce "Admin" nel
menu laterale, solo a `stato='stagione'` e fuori dall'off-season), pensate come rete di
sicurezza e non come meccanica di gioco:

- **Simula giornata**: chiama direttamente la Edge Function `simula-giornata` dal browser.
  Non è stato scritto nulla di nuovo lato server — la funzione accettava già il JWT
  dell'admin (`auth: ['user','secret']`) e verifica da sola che l'utente sia
  `league.admin_id` quando non è il cron a chiamare. Mancava solo il collegamento frontend.
- **Apri mercato**: `public.admin_apri_mercato(league_id)`, chiama
  `private.estrai_svincolati_lega`. Nessun vincolo orario, richiamabile a piacere; una
  seconda apertura lo stesso giorno è un no-op (guardia già esistente).
- **Chiudi mercato**: `public.admin_chiudi_mercato(league_id)`, risolve le aste del giorno e
  fa scadere le proposte in attesa **solo per questa lega**. Ha richiesto due modifiche:
  `private.risolvi_aste_giorno` non aveva un filtro di lega (il cron risolve tutte le leghe
  insieme, non aveva bisogno di isolarle) — aggiunto un parametro opzionale
  `p_league_id default null`, che non cambia il comportamento del cron. La scadenza delle
  proposte era dentro `chiudi_mercato_giornaliero` senza mai essere stata spezzata dalla
  guardia oraria come le aste — estratta in `private.scadi_proposte_giorno(p_league_id)` con
  lo stesso schema di oggi pomeriggio.

Tutte e tre le RPC ricontrollano `auth.uid() = leagues.admin_id` lato server: la voce di menu
nascosta e il guard in `Admin.tsx` sono comodità, non la difesa vera. Verificato in un
rollback su una lega reale: un non-admin viene respinto col messaggio giusto, l'admin estrae
correttamente, una doppia apertura non duplica, la chiusura tocca solo le aste della propria
lega.

---

---

## ▶ NOTA 3 agosto 2026 — draft a pacchetti in produzione, due correzioni dello stesso giorno

Il branch `pack_draft_exploration` menzionato in una versione precedente di questa nota è
stato **integralmente unito a `main` e applicato al database remoto** (commit `5b665d5`,
`04930a5`, poi rifiniture). Il draft a spin-club non esiste più: ogni squadra apre pacchetti
di 4 carte per macro-ruolo (GK/DEF/MID/ATT) dal pool attivo intero, non da un club, e sceglie
2 carte su 4. Motivo del cambio: lo spin-club permetteva di svuotare un club specifico prima
che un altro partecipante lo estraesse — vedi design §4.1 e `docs/decisioni-fase1.md` §8.

**Due difetti reali trovati e corretti oggi**, entrambi mentre si usava davvero il sistema
(non in un test isolato):

1. **`draft_scegli_pacchetto` scriveva il pick_numero sbagliato in `draft_picks`.**
   `draft_picks` ha `UNIQUE (league_id, pick_numero)`: è una numerazione **globale di lega**
   (lo dimostra il codice off-season, che semina il contatore leggendo
   `max(draft_picks.pick_numero)+1` su tutta la lega). La funzione di ieri scriveva invece
   `draft_team_state.pick_numero`, il contatore **per squadra** che riparte da 0 per ognuna.
   Effetto: la prima squadra a completare il draft in una lega andava benissimo (nessuna
   collisione, è sola); **la seconda squadra falliva già al primo pacchetto** con una chiave
   duplicata. Non un caso limite: il caso normale di qualunque lega con più di un
   partecipante. Corretto in `20260803150000_fix_draft_picks_numerazione_globale.sql`
   usando `v_global.pick_numero` (già letto e lockato in testa alla funzione), verificato
   completando 5 squadre in una lega di prova (120 giocatori assegnati, zero collisioni).

2. **Il modulo 4-2-4 mostrava RW e uno dei due ST scambiati sul campo.** Non era il motore
   (che ordina i giocatori correttamente): `Formazione.tsx` non aveva un caso esplicito per
   4-2-4 nel raggruppamento in righe della formazione, quindi cadeva nel ramo generico che
   ordina la linea offensiva come `['LW','RW','ST','CF']` — mette RW prima di entrambi gli
   ST. Aggiunto un caso dedicato in `src/components/Formazione.tsx` (solo frontend, nessuna
   migrazione) con l'ordine corretto `['LW','ST','RW']`. Controllati tutti gli altri moduli:
   nessun altro cade più nel ramo generico.

**Novità dello stesso giorno**: ogni squadra ora **comincia il draft appena entra**, senza
aspettare che la lega sia piena (`20260803160000_draft_indipendente_dall_ingresso.sql`).
Prima serviva un `avvia_draft` manuale dell'admin una volta raggiunte tutte le `n_squadre`.
Design §4.1 diceva già «nessun ordine di turno, ogni squadra pesca per conto proprio, senza
aspettare le altre»: mancava solo togliere il cancello sull'*inizio*. `crea_lega` ora crea la
lega direttamente in stato `draft` con `draft_state` + `draft_team_state` per la squadra
dell'admin; `entra_in_lega` accetta l'ingresso anche a `stato='draft'` (oltre a `'setup'` e
all'ingresso off-season) e crea `draft_team_state` per il nuovo entrante, stesso pattern già
usato per l'ingresso off-season. **Retrocompatibile di proposito**: le leghe già ferme in
`'setup'` (due, di prova) continuano col vecchio flusso — `avvia_draft` non è stato toccato
né droppato, sarebbe stato un cambiamento distruttivo su dati esistenti per un problema che
non hanno. Verificato in un rollback: lega creata già in `draft`, admin apre un pacchetto da
solo (1 squadra su 8), un secondo utente entra a lega quasi vuota ed apre subito un
pacchetto, entrambi scelgono senza collisione di pick_numero.

Conseguenza UI: chi entra per primo non passa più dalla Lobby (route diretta alla schermata
di Draft), quindi il codice invito non aveva più un posto dove essere mostrato dopo la
creazione. Aggiunto un banner in `Draft.tsx`, visibile finché `squadre_iscritte < n_squadre`,
con lo stesso gesto "tocca per copiare" già usato in Lobby.

**Terzo difetto, scoperto in produzione dall'utente poche ore dopo il deploy**: gli amici
invitati ricevevano «Questa lega non accetta nuovi partecipanti» subito dopo aver digitato
il codice, prima ancora di scegliere nome e stemma squadra. Causa: `anteprima_invito`, la
RPC chiamata dal passo "Continua" sul codice (`Onboarding.tsx` → `verifyCode`), **duplica**
lo stesso controllo di stato di `entra_in_lega` invece di condividerlo — e non era stata
toccata dalla migrazione precedente, che aveva sistemato solo `entra_in_lega`. Corretto in
`20260803170000_fix_anteprima_invito_stato_draft.sql` con lo stesso identico cambiamento
(`stato in ('setup','draft')`). Verificato sulla lega reale segnalata dall'utente
(codice `N2YE6X`, id 32): prima falliva su entrambe le chiamate, dopo il fix passa su
entrambe. **Nota per chi tocca ancora questo flusso**: `anteprima_invito` ed
`entra_in_lega` hanno lo stesso gate ripetuto due volte in due funzioni diverse — se cambia
ancora una condizione di ingresso, va cambiata in tutt'e due, o va estratta in un helper
condiviso (`private.lega_accetta_ingressi(league)` ad esempio) per non ricadere nello
stesso errore una terza volta.

**Quarto difetto, stessa sera, più serio dei primi tre**: completare l'ultimo pacchetto del
proprio draft falliva con «Il numero di squadre attive non coincide con le impostazioni», e
**la scelta non veniva salvata affatto** — non solo un messaggio fastidioso, una perdita di
progresso vera. Causa: `draft_scegli_pacchetto` porta la lega a `stato='stagione'` quando
nessuna `draft_team_state` è più `'in_corso'`. Prima dell'ingresso indipendente questo
equivaleva sempre a "la lega è piena", perché `avvia_draft` richiedeva tutte le `n_squadre`
PRIMA di creare qualunque `draft_team_state`. Con l'ingresso indipendente quell'equivalenza
si è rotta: 5 squadre su 8 possono finire tutte il proprio draft mentre mancano ancora 3
posti, il vecchio controllo scattava lo stesso, e il trigger `leagues_avvia_stagione`
(AFTER UPDATE, chiama `private.inizializza_stagione`, che pretende
`count(teams) = n_squadre`) falliva — annullando per `AFTER UPDATE` **l'intera transazione**,
comprese le due `player_instances` appena inserite. Corretto in
`20260803180000_fix_stagione_solo_a_lega_piena.sql` aggiungendo la condizione mancante:
la stagione parte solo quando la lega è piena *e* tutte hanno finito, non solo quando tutte
le iscritte hanno finito. Verificato prima con i dati reali della lega segnalata (id 32,
codice `N2YE6X`): dopo il fix l'utente ha ripetuto la scelta con successo, tutte le 6 squadre
allora iscritte sono `concluso` e la lega è correttamente rimasta in `draft` in attesa delle
ultime 2. **Nessun dato perso**: il pick fallito non aveva scritto nulla (rollback completo),
il giocatore ha solo dovuto riprovare dopo il deploy del fix.

---

## ▶ CONSEGNA A CODEX — leggi prima questo

Il lavoro passa a Codex a partire dal 2 agosto 2026, sera. Ultimo commit pubblicato: `5003e99`.

### Stato corrente, in concreto

Il flusso completo di **off-season e seconda stagione** è implementato e applicato al database
remoto fino alla migrazione `20260802235500_fix_lint_calendario_23.sql`. L'off-season dura 24 ore,
si chiude automaticamente, completa a 21 le rose corte e programma la prima giornata alle prime
23:00 di Roma utili. Per il dettaglio più recente fa fede l'ultima sezione di questo documento.

### Prossima verifica manuale

Provare da mobile il drawer, la cancellazione degli avvisi, l'animazione degli spin e il carosello
news; poi lasciare scadere o anticipare in ambiente di test un'off-season per osservare il passaggio
automatico alla nuova stagione. Build, lint, lint DB e test SQL automatizzato sono già verdi.

### Decisioni ferme

1. I nuovi partecipanti dell'off-season costruiscono la rosa con le **rollate sui club**.
2. I giocatori delle squadre rimosse diventano tutti svincolati; un rinnovo senza risposta
   scade e libera il giocatore; gli scambi diretti restano aperti durante l'off-season.
3. Le squadre entranti ricevono l'intero budget iniziale della lega.
4. **Cartellini**: il motore non li ha affatto. Due strade descritte in fondo a questo documento.
5. Se le **offerte perdenti** delle aste debbano diventare pubbliche dopo le 21:00. Oggi restano
   private per sempre; l'utente ha chiesto che si rivelino «le vincenti», ed è ciò che accade.

### Come si verifica il lavoro su questo progetto

Il metodo usato per tutto il mercato, e che conviene continuare: **uno script SQL dentro
`begin; … rollback;`** che porta il database nello stato voluto, esegue le RPC **assumendo
l'identità di utenti reali**, raccoglie gli esiti in una tabella temporanea e la stampa alla
fine. Si lancia con `db query --file`. Esempi vivi in `scratchpad` (non versionati, si riscrivono
in due minuti). Lo scheletro:

```sql
begin;
create temporary table esiti (n int, verifica text, misurato text, esito text) on commit drop;
-- … prepara lo stato …
grant select on <temp tables> to authenticated;   -- servono dopo il cambio di ruolo
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', '<uuid utente>', 'role', 'authenticated')::text, true);
-- … chiama le RPC, inserisci in esiti …
reset role;
select verifica, misurato, esito from esiti order by n;
rollback;
```

Per provare che una RPC **rifiuta** qualcosa, avvolgila in un `do $$ … exception when others then
get stacked diagnostics v_msg = message_text; … end $$;` e registra il messaggio: così il test
dimostra *quale* controllo è scattato, non solo che è fallito qualcosa.

**Il CLI restituisce solo l'ultimo result set**: raccogliere tutto in una tabella e fare una sola
select finale, altrimenti si vedono solo le ultime righe.

---

## Prima di lavorare

1. Leggere `CLAUDE.md` (o `AGENTS.md`, sono lo stesso file) e `docs/decisioni-fase1.md`.
2. Per ogni modifica Supabase creare una nuova migrazione; non modificare migrazioni già applicate.
3. Il motore è validato. Se si modifica `engine/`, eseguire obbligatoriamente
   `node tools/validazione/simulate.js` e confrontare con `docs/risultati-fase0.txt`.
   Il confronto va fatto con `diff --strip-trailing-cr`: il file di baseline ha fine riga CRLF.
4. UI mobile-first, stato di gioco solo su Supabase, nessun `localStorage`.
5. La CLI Supabase non è installata globalmente: si usa `npx supabase …`.
   `db query` è **sperimentale e non compare in `--help`**: va invocato con
   `--linked --experimental`. È il comando più utile del progetto, non rinunciarci.

## Stato Git

- Branch: `main`, allineato con `origin/main`
- Remote: `https://github.com/cstino/SpecialOne.git`
- Ultimo commit al momento di questo aggiornamento: `f5bc91e`.
- **Vercel è collegato a GitHub**: ogni push su `main` fa un deploy di produzione da solo, in
  circa 10 secondi. Non serve `vercel --prod` a mano. Verificato confrontando l'hash del bundle
  locale con quello servito da `specialone-five.vercel.app`.

## Accesso al database dall'agent

Verificato funzionante e indispensabile per diagnosi e verifiche:

```bash
npx supabase db query --linked --experimental "select count(*) from public.players;"
npx supabase db query --linked --experimental --file percorso/query.sql
npx supabase db push --linked --experimental --yes
npx supabase functions deploy simula-giornata
```

Project ref: `hhvyyjpbsgjcaaaizgwb`. Il login (`npx supabase login`) è già stato fatto su questa
macchina; su un'altra va rifatto insieme a `supabase link`, perché `supabase/.temp/` è in `.gitignore`.

**`db dump` non funziona su questa macchina**: richiede Docker, che non è in esecuzione. Per
ispezionare lo schema si usa `db query` su `information_schema` / `pg_catalog`.

Il file locale `.env.local` contiene **solo** URL e chiave pubblicabile: da qui non si può
interrogare il database via REST con privilegi. La chiave segreta sta solo nelle variabili
d'ambiente della Edge Function e nel Vault.

---

## Funzionalità completate

### Off-season e nuova stagione

- Le leghe concluse aprono ora una schermata `Off-season` invece di restare senza avanzamento.
- L'admin conferma le squadre, può rimuoverne e riservare nuovi posti; la squadra admin resta.
- Premi stagione, premio classifica e sponsor vengono accreditati prima dei rinnovi.
- Età, progressione/declino e ritiri seguono il design §10.2; il motore partita non è stato toccato.
- Richieste di rinnovo con intervallo pubblico, offerta 1–4 anni, accettazione/rifiuto server-side.
- Mancata risposta alla chiusura = contratto scaduto e giocatore svincolato.
- Nuove squadre entrano col codice durante l'off-season, budget pieno e draft indipendente a club.
- Mercato e aste restano disponibili; le squadre rimosse sono bloccate anche lato database.
- L'avvio della stagione successiva valida rose da 21–30, budget e draft, addebita gli
  ingaggi e genera il calendario usando soltanto le squadre attive.
- Test transazionale versionato in `tools/validazione/test_offseason.sql`: tutte le verifiche OK,
  incluso avvio stagione 2 e nuova classifica; il `ROLLBACK` preserva i dati reali.
- `npm run build` e `supabase db lint --linked --level warning`: OK.

### Fondamenta e dati

- React 19 + Vite + TypeScript, Supabase Auth/Database/Storage/Edge Functions.
- Schema Fase 1 con RLS, RPC e privilegi server-side.
- Dataset FC 26 importato: 5.416 giocatori, 192 club, 10 campionati.
- Motore di simulazione validato e integrato mantenendo il seed deterministico.

### Foto giocatori — ospitate, non più in hotlink

**Questa è la modifica più delicata dell'ultima sessione.**

Prima l'app non aveva foto proprie: `foto_url` era nullo per tutti e 5.416 i giocatori e
`Formazione.tsx` cadeva su una funzione `eaPortraitUrl()` che **hotlinkava il CDN di EA**
(`ratings-images-prod.pulse.ea.com`). Era esattamente ciò che `decisioni-fase1.md` §3 vieta.

Ora:

- 5.225 ritratti scaricati, convertiti in WebP 160×160 con canale alpha, caricati nel bucket
  privato `player-photos` al percorso `players/{fc_id}.webp`.
- `foto_url` valorizzato per tutti e 5.225. Verificato con una join fra `public.players` e
  `storage.objects`: 5.225 su 5.225 puntano a file esistenti.
- 191 giocatori non hanno ritratto sul CDN sorgente: restano con `foto_url` nullo e mostrano
  l'avatar anonimo grigio. È il comportamento previsto, non un difetto.
- `eaPortraitUrl()` è stata **rimossa**. Non reintrodurla.

Nuovo script `tools/importazione/scarica_foto.py`: ricostruisce l'URL del CDN dall'`fc_id`,
quindi non serve più il CSV Kaggle (che non è su questa macchina). Sorgente a 240px ridotto a
160, così si ritaglia verso il basso invece di ingrandire. È ripetibile: salta i file già presenti.
Procedura completa e trappole della CLI in `tools/importazione/README.md`.

### Assist e minuti dei gol

- **Motore**: unica modifica, puramente contabile. Le due chiamate `poisson()` per blocco erano
  già lì; ora il risultato viene trattenuto in `golPerBlocco`, che dice quanti gol sono caduti in
  quale blocco. Nessuna estrazione RNG in più, nessuna formula toccata.
  **Protocollo di regressione eseguito: diff zero contro `docs/risultati-fase0.txt`.**
- **Assist**: calcolati **fuori** dal motore, nella Edge Function, con un LCG a stato locale
  seminato dal seed della partita. Sono riproducibili quanto il risultato ma non consumano lo
  stream RNG dell'engine, che resta intatto. Tabella `PESO_ASSIST` dedicata per slot: non deriva
  da `PESI_STAT.passaggi`, che misura il volume di passaggi e incoronerebbe i centrali difensivi.
  Il 28% dei gol resta senza assist (rigori, tiri da fuori, ribattute).
- **Minuti**: derivati dal blocco (6 blocchi da 15 minuti) nella Edge Function.
- Gli eventi gol finiscono in `matches.blocchi` (colonna già esistente, prima riempita con `[]`).
  `match_stats.assist` non è più il letterale `0`.
- Verificato su 4.000 partite: eventi e gol coincidono sempre, minuti sempre in 1-90, assist mai
  uguale al marcatore, 72,4% dei gol assistiti, assist distribuiti in modo plausibile per ruolo.
- **Edge Function distribuita**: versione 6, stato ACTIVE.

### Interfaccia — nuovo linguaggio grafico

Direzione approvata dall'utente su un mockup: fondo scuro con luce ambientale, viola come
identità, colore semantico separato (verde vittoria, grigio pari, rosso sconfitta), immagini in
ogni riga, un elemento dominante per schermata invece di riquadri tutti uguali.

Già applicato:

- **Navigazione**: barra **fissa in basso** su mobile con indicatore viola sopra la voce attiva.
  Le icone erano glifi Unicode (`▦ ♜ ♙ ◆ ◉ ≡`) resi dal font di sistema, quindi diversi su ogni
  dispositivo: ora sono **SVG disegnate**, usate anche nella barra laterale desktop.
- **Stemmi**: sei stemmi SVG con forme e palette distinte, al posto di sei caratteri di testo
  dentro la stessa sagoma viola. Prima chi non sceglieva prendeva il default e nei risultati non
  si distingueva una squadra dall'altra.
- **Rapporto partita**: marcatori con minuto e assist fra parentesi sotto la propria squadra;
  niente più pannello cronaca separato, niente casa/trasferta e moduli. Stemmi e punteggio sono
  sulla riga 1 della griglia e i marcatori sulla riga 2, così la lista cresce verso il basso senza
  spostare gli stemmi.
- **Formazione**: il campo è rimasto **volutamente com'era** (scelta dell'utente). È cambiata solo
  la targhetta: cognome, e sotto ruolo e overall con trattamento tipografico dedicato.
- **Squadra**: stemma senza cornice, gerarchia delle statistiche (posizione dominante, tre di
  supporto), chip della forma V/N/P, striscia colorata dell'esito su ogni risultato, club rimosso
  dalla riga della rosa, righe della rosa cliccabili.
- **Partite**: ristrutturata in «Prossima giornata» + «Giornate completate» sfogliabili con le
  frecce (impilarle tutte allungava troppo la pagina) + calendario integrale dietro un pulsante.
  Card per giornata con fascia di intestazione e pillola di stato.
- **Overview**: l'eroe porta l'identità della squadra (stemma, nome, posizione, punti, forma)
  invece di uno slogan fisso; la card dell'ultima partita prende il colore dell'esito.
- **Classifica**: colonna forma con i chip V/N/P delle ultime cinque giornate. Sono **dentro la
  cella squadra**, non in una colonna nuova: la griglia nasconde le colonne su mobile con regole
  `nth-child`, e aggiungerne una le avrebbe sfasate tutte. Così la forma resta visibile anche su
  telefono, dove V/N/P/GF/GS sono nascoste.
- Nelle partite non ancora giocate compare **VS** invece del segnaposto `00:00`.

Il calcolo della forma (`formaPerSquadra`) e il componente `Forma` stanno in `SeasonUI.tsx` e
sono condivisi da Overview, Classifica e pagina Squadra: una sola implementazione.

**Con questo il menu di stagione è completo.** Restano da rivedere Lobby, Draft, Onboarding e
Login, che stanno tutte prima dell'inizio della stagione.

Una cosa deliberatamente **non** fatta: le frecce di salita e discesa in classifica. Servirebbe
la posizione della giornata precedente e `standings` conserva solo quella corrente, quindi
andrebbero inventate.

### Modello di fatica «da partita» — costanti del motore cambiate

**Questa è la prima modifica deliberata alle costanti validate. Va letta prima di toccare
`engine/config.js`.**

Il motore modellava la fatica **di stagione**: ~2,1 punti a blocco, cioè un titolare finiva i 90
minuti a 87 con soglia di cambio a 55. Dentro la partita nessuno si stancava abbastanza, quindi
**le sostituzioni non si innescavano mai**. Su richiesta dell'utente si è passati al modello
«da partita» in stile FIFA: si consuma molto in campo e si recupera quasi tutto dopo.

| Costante | Prima | Ora |
|---|---|---|
| `CONSUMO_BASE` | 3,4 | 10,5 |
| `CONSUMO_MOD_STAMINA` | 1,6 | 4,0 |
| `REC_GIOCATO` | 8 | 36 |
| `REC_PANCHINA` | 30 | 40 |
| `REC_TRIBUNA` | 38 | 45 |
| `SOGLIA_CAMBIO_COND` | 55 | 75 |

`sostituzioni()` ha una riga in più: **il portiere è escluso dai cambi per stanchezza**. Col
consumo nuovo scendeva sotto soglia come tutti e veniva sostituito all'intervallo — è successo
davvero in una partita di prova, Alisson fuori al 45°. Nel calcio un portiere esce solo per
infortunio.

#### Un target della validazione è stato ri-tarato

`Condizione titolari a fine stagione`: da **55-85** a **75-95**, con il motivo scritto accanto
alla riga in `tools/validazione/simulate.js`.

Non è una deriva del motore ed è importante capirlo. Il vecchio intervallo misurava un mondo in
cui **nessuno veniva mai sostituito**: i titolari giocavano tutti i 90 minuti di tutte le
giornate. Ora chi si stanca esce al 60', quindi la rosa arriva a fine stagione più fresca. Il
valore più alto è la conseguenza del meccanismo che funziona.

Tentativi misurati prima di decidere, per non ri-tarare a occhio:

| `REC_GIOCATO` | Punti vincitore (min 58,0) | Condizione fine stagione |
|---|---|---|
| 38 | 58,4 OK | 90,6 |
| 36 | 58,2 OK | 89,0 |
| 34 | 57,9 FUORI | 87,3 |
| 30 | 57,6 FUORI | 83,6 |

Nessun valore soddisfaceva insieme il vecchio target e i punti del vincitore: le due metriche si
muovono in direzioni opposte. Da notare che `Punti del vincitore` ha 58,0 come minimo e la
baseline storica stava a 58,4 — quattro decimi di margine, quindi è una metrica fragile.

Con le costanti nuove **tutti e tredici i target passano**. `docs/risultati-fase0.txt` è stato
rigenerato; la baseline precedente è conservata in `docs/risultati-fase0-pre-rotazione.txt`.

#### Verifica del comportamento, su 1.500 partite

- squadre con almeno un cambio: **99,9%** (prima: nessuna);
- cambi medi per squadra 3,71, **massimo 5 mai superato**, tre finestre come in Serie A
  (erano già in `config.js`: `FINESTRE_CAMBI: [3,4,5]`, `MAX_CAMBI: 5`, `MAX_CAMBI_FINESTRA: 2`);
- **portieri sostituiti: 0**;
- entrati fuori dal reparto dello slot: 5,7%, e solo quando la panchina non offre di meglio.
  La scelta passa da `ovrEfficace`, che è `ovr × penalitaRuolo × fattoreCondizione`: un difensore
  messo in attacco prende 0,58 di penalità e non viene scelto.

Di conseguenza `fattoreUsura` è stato **rimosso** dalla Edge Function: serviva a far accumulare
fatica in stagioni corte, ma ora il consumo dentro i 90 minuti basta da solo.

### Condizione, sostituzioni e infortuni — attivi

Fino a ieri `usaCondizione: false`, com'era previsto per la Fase 1. Ora è **acceso**, e con esso
sostituzioni e infortuni. Va capito perché non bastava girare il flag.

**Le colonne non venivano mai riscritte.** `condizione` e `infortunato_fino_a` esistevano dal
primo giorno e la Edge Function le leggeva, ma non le salvava: ogni partita ripartiva da 100 e
senza infortuni. Con la condizione ferma a 100 nemmeno le sostituzioni potevano scattare, perché
la soglia di cambio del motore è 55. Ora c'è la RPC `aggiorna_condizione_rosa`, chiamata a fine
giornata.

**Nota importante sulla validazione**: il test stagionale della suite gira con
`usaCondizione: true`. Era la produzione a discostarsi dalla configurazione validata, non il
contrario. Accendere la condizione ci riporta dentro il perimetro tarato in Fase 0.

#### Due adattamenti alla lunghezza della stagione — nell'adapter, mai nel motore

Le costanti del motore sono tarate su 28 giornate. Entrambe le correzioni stanno nella Edge
Function: `engine/` resta intatto, come impone `CLAUDE.md` §4.

1. **Durata degli infortuni** (`scalaInfortunio`): il motore sorteggia fino a 15 giornate, che in
   un campionato da 12 significa perdere il giocatore per sempre. La durata è scalata sulle
   giornate reali, con tetto al 40% del totale.
2. **Usura della condizione**: era stata scalata sulla stagione con un `fattoreUsura`, poi
   **rimosso** quando il motore è passato al modello di fatica da partita descritto sopra. Il
   consumo dentro i 90 minuti ora basta da solo a innescare i cambi.

#### Un difetto che esisteva solo in potenza

Un giocatore può infortunarsi **dopo** che la formazione è stata salvata, e la formazione
ereditata dalla giornata precedente non veniva mai ricontrollata. `schiera()` scarta gli
indisponibili, ma una formazione che arriva dal database no — e il motore controlla gli infortuni
solo a fine partita. Un infortunato sarebbe sceso in campo. Ora `buildLineup` lo rimpiazza con il
miglior disponibile per quello slot, usando `ovrEfficace` invece di un criterio inventato.

#### Interfaccia

Sul ritratto in "Rosa", in alto a sinistra, c'è la **percentuale di energia**: verde sopra 75,
gialla fra 55 e 75, rossa sotto 55 — la soglia oltre cui il motore sostituisce da solo — e una
croce rossa per gli infortunati, con le giornate mancanti nel titolo.

#### Gestione infortuni completa — 2 agosto 2026

- Ogni nuovo infortunio prodotto dalla simulazione genera una notifica `infortunio` per il
  proprietario, con nome e giornate residue. Toccandola si apre direttamente "Rosa".
- Un infortunato non può essere salvato fra titolari o panchina, ma resta correttamente ammesso
  in tribuna. Il controllo è sia nella UI sia nella RPC `salva_formazione`.
- Sostituendo manualmente un titolare infortunato con una riserva, l'infortunato viene mandato
  direttamente in tribuna. Se l'allenatore non interviene, `buildLineup` lo rimpiazza prima
  della simulazione e completa la panchina fino a 9 con i migliori sani disponibili.
- La scheda giocatore contiene ora una sezione "Forma fisica": percentuale e barra quando è
  disponibile, stato infortunato e giornate al rientro quando non lo è.
- Migrazione `20260802214000_gestione_infortuni.sql` applicata e Edge Function
  `simula-giornata` distribuita. Test transazionale remoto superato: tribuna accettata,
  panchina respinta, tipo notifica accettato, rollback finale.

Le sostituzioni sono già leggibili nel tabellino senza lavoro aggiuntivo: `match_stats.minuti` è
calcolato sui blocchi giocati, quindi chi esce ha 45' e chi entra il resto.

### Simulazione notturna automatica — attiva

Job `simula-giornata-notturna` in `cron.job`, **attivo**. Gira **ogni ora**; è la funzione
`private.simula_giornata_notturna()` a decidere se a Roma sono le **23:00**.

**Perché ogni ora e non a un orario UTC fisso.** pg_cron pianifica in UTC: l'equivalente delle
23:00 cambia con l'ora legale. Il controllo sull'ora italiana dentro la funzione
attraversa il cambio dell'ora legale senza saltare né duplicare una giornata — è la trappola
annunciata in `CLAUDE.md` §2.

Due guardie contro la doppia simulazione: si simula solo una giornata la cui data di calendario
è già arrivata, e mai due volte nella stessa data italiana. `registra_risultato_partita` resta
comunque idempotente per fixture.

#### Autenticazione del cron — la parte che è costata di più

`verify_jwt = false` nel `config.toml`: l'autenticazione la fa `@supabase/server` dentro la
funzione con `auth: ['user', 'secret']`, quindi l'endpoint non è aperto. Il browser passa dal
JWT utente e resta soggetto al controllo su `admin_id`; il cron passa dal ramo `secret`.

Tre cose scoperte provando, ognuna aveva prodotto un 401 o un 404:

1. **La chiave va nell'header `apikey`, non in `Authorization`.** Il ramo `secret` legge solo
   `request.headers.apikey`; un bearer token non viene nemmeno guardato.
2. **`SUPABASE_SECRET_KEY` non è iniettata** nel runtime e la piattaforma **vieta** di creare
   variabili col prefisso `SUPABASE_`. Per questo la chiave è esposta come
   `CHIAVE_SEGRETA_PROGETTO` e passata a `withSupabase` con `env: { secretKeys: { default: … } }`.
3. **Quella mappa è la stessa che alimenta `createAdminClient`.** Metterci un segreto inventato
   autentica il cron ma rompe ogni query della funzione, perché il client amministrativo userebbe
   quel valore come chiave del progetto. Deve essere la chiave segreta vera.

Il segreto sta nel vault come `chiave_simulazione` e non compare in nessun file del repository.

#### Verificato in produzione

La catena `pg_net → gateway → Edge Function` è stata provata a mano prima di lasciarla al cron:
risposta `200`, `modo: "secret"`, giornata 6 simulata. **Con questa esecuzione è finalmente
verificata anche la funzione assist**: eventi gol pari al numero di gol in entrambe le partite,
assist scritti in `match_stats`, un gol senza assist su quattro — coerente con la quota prevista.

#### Da decidere: il calendario è disallineato

Le prime cinque giornate sono state simulate a mano **in anticipo** rispetto alle date generate
all'avvio della stagione. Oggi è il 1º agosto ma la giornata 7 è in calendario per l'**8 agosto**,
quindi il cron resterà fermo per una settimana e poi recupererà una giornata per notte.

È coerente — il calendario è la fonte di verità e le date sono quelle mostrate nell'app — ma va
deciso: o si accetta la pausa, o il pulsante admin deve spostare le date delle giornate successive
quando simula in anticipo, oppure il cron ignora il calendario e simula la prima giornata pendente
ogni notte (e allora le date mostrate diventano bugiarde).

### Deploy su Vercel — pubblicato e automatico

Progetto collegato: `cstinos-projects/specialone`. Variabili `VITE_SUPABASE_URL` e
`VITE_SUPABASE_PUBLISHABLE_KEY` già impostate su production, preview e development.

File aggiunti: `vercel.json` (fallback SPA, header `X-Robots-Tag: noindex`, cache immutabile
sugli asset, `no-cache` sul service worker), `public/robots.txt` con `Disallow: /`, e il
`<meta name="robots" content="noindex, nofollow">` in `index.html`. Non è pignoleria: è
`decisioni-fase1.md` §3, che vieta di rendere il dataset pubblico o indicizzabile.

`.vercelignore` tiene fuori dal caricamento `docs/`, `tools/`, `supabase/` ed `engine/`: al
browser non servono, e `engine/` appartiene alle Edge Function su Supabase.

**Manca solo l'autenticazione.** La CLI installata globalmente è la 42.3.0 e l'API ora pretende
almeno la 47.2.2; il token salvato da quella vecchia non vale per la nuova. Serve:

```bash
npx vercel@latest login
npx vercel@latest --prod --yes
```

Da fare a mano perché `login` apre il browser.

### Menu iniziale e profilo allenatore

Prima la `Lobby` faceva da schermata di casa, ma è la **sala d'attesa di una singola lega**:
mostra i partecipanti di quella lega e il suo codice invito. Ora è tornata a fare solo quello.

`src/components/MenuIniziale.tsx` è la vera schermata iniziale, raggiungibile toccando il
marchio in alto a sinistra da dentro qualunque lega (draft o stagione):

- Crea una lega / Entra con un codice, che aprono l'onboarding già dentro il ramo giusto
  (`Onboarding` accetta `modoIniziale`).
- Elenco delle proprie leghe con stemma, stato e, per le leghe in corso, posizione e punti.
- Bottone a tre lineette in alto a destra: apre un pannello laterale con **Profilo** ed **Esci**.

Il ritorno alla schermata iniziale passa da un **contesto React** (`src/lib/navigazione.ts`),
non da una prop: altrimenti `onHome` andrebbe infilata in tutte e otto le schermate solo per
arrivare a `GameNav`.

**Tabella `profiles`** (migrazione `20260801181500_profilo_allenatore.sql`): fino ad ora un
partecipante era solo un `user_id` e un'email. Contiene il nome dell'allenatore, con:

- helper `private.condivide_lega(uuid)` in SECURITY DEFINER — obbligatorio, altrimenti una
  policy su `profiles` che interroga `teams` applica anche la RLS di `teams` ed entra in
  ricorsione. È la trappola documentata in `20260731120400_helper_rls.sql`;
- policy di lettura: il proprio profilo più quello di chi condivide una lega. Non è una
  rubrica globale;
- scrittura solo via RPC `aggiorna_nome_allenatore`, il browser non ha INSERT/UPDATE;
- creazione pigra al primo salvataggio: nessun trigger su `auth.users`, nessun backfill.

Le statistiche di carriera (leghe, stagioni, titoli, partite, record punti, miglior
piazzamento) sono calcolate dal client su `standings` × `seasons`, senza schema aggiuntivo.
**L'albo d'oro nasce vuoto per costruzione**: i titoli si contano su `standings.posizione = 1`
con stagione `conclusa`, e nessuna stagione lo è ancora.

### Scheda giocatore condivisa

`src/components/SchedaGiocatore.tsx` è usata **sia** da Formazione **sia** da Squadra: non
duplicare la scheda, estenderla. Mostra anagrafica, attributi e — quando le statistiche vengono
passate — la sezione «Stagione»: presenze, minuti, gol, assist, porta inviolata, G+A ogni 90',
% tiri in porta, % passaggi riusciti, contrasti vinti, dribbling riusciti. Ogni percentuale porta
sotto i valori grezzi.

`src/lib/nomi.ts` contiene `cognome()`, che trasforma il nome puntato del dataset nel solo
cognome. Provata su tutti i 5.416 nomi: zero risultati vuoti, gestisce cognomi composti
(`O. El Hilali` → `El Hilali`), doppie iniziali e mononimi (`Rodri` resta `Rodri`).

### Notifiche in-app — attive

Richieste dall'utente come premessa al mercato: *«se un giocatore manda un'offerta, mi arriva la
notifica»*. Sono state fatte **prima** del mercato di proposito — sono il pezzo su cui il mercato
scrive, e farle dopo avrebbe significato tornare a modificare ogni RPC già scritta.

- `notifications`: una riga per **persona**, non per squadra, perché la campanella è una sola per
  tutte le leghe. `league_id` nullable (null = avviso di account). `dati jsonb` porta il
  collegamento profondo: `{"match_id": 12}` apre il tabellino invece della home della lega.
- La CHECK su `tipo` elenca già i tre valori del mercato (`mercato_proposta`, `mercato_esito`,
  `mercato_asta`) benché nessuno li emetta ancora: serve a non migrare la CHECK a ogni pezzo.
- RLS: si leggono **solo le proprie**. Non esiste una vista di lega, perché sapere cosa è stato
  notificato a un avversario rivelerebbe che ha ricevuto una proposta.
- Scrittura: nessuna policy per il browser. `private.notifica(...)` per le future RPC del mercato,
  `public.segna_notifiche_lette(bigint[])` per segnare lette (senza argomenti, tutte).
- Realtime: la tabella è nella publication `supabase_realtime`, quindi il pallino compare senza
  ricaricare. `useNotifiche` ha comunque un refetch su `visibilitychange`, per quando il socket
  cade mentre il telefono è in tasca.
- La simulazione notturna emette due tipi: `giornata_simulata` (personalizzata — «Vittoria 3-1»,
  «Giornata 5 contro …», con `match_id`) e `formazione_mancante` a chi non ha schierato entro le
  23:00. Le notifiche sono in un `try/catch` che **non** propaga: la giornata è già scritta, e un
  500 farebbe ritentare il cron su dati registrati. Una partita con `gia_simulata: true` non
  rinotifica.
- UI: `Notifiche.tsx` (campanella + pannello) compare nella topbar del menu iniziale, nella sidebar
  desktop e nella barra mobile. Aprire il pannello vale come aver visto: chiedere un secondo tocco
  per spegnere il pallino sarebbe solo attrito.

**Push del browser: non fatte, e l'ordine è voluto.** Una push senza una schermata dove atterrare
non serve. Il service worker esiste già (`public/sw.js`), quindi mancano solo chiavi VAPID nel Vault
e un handler `push`. **Su iPhone le push web arrivano solo se la PWA è installata sulla schermata
home**: da Safari normale non arrivano e non c'è modo di aggirarlo.

### Mercato — trattative fra squadre (database e interfaccia, complete)

**Finestra: 07:00–21:00 Europe/Rome.** L'utente ha spostato la chiusura dalle 17:00 (design §9.1)
alle 21:00 il 2 agosto 2026; il design doc è stato aggiornato con la motivazione. Le 17:00 cadevano
in orario di lavoro. Alle 21:00 si scopre l'esito delle aste e restano **due ore** per rifare la
formazione prima del fallback delle 23:00.

**Non esiste uno stato «mercato aperto» sul database e nessun cron lo apre**: `private.mercato_aperto()`
guarda l'ora di Roma. Uno stato memorizzato può restare disallineato se un job salta, un orario
calcolato no. Il cron (`chiusura-mercato`, ogni ora al minuto 5) serve solo a far scadere le
proposte rimaste appese, e come il cron notturno decide da sé se a Roma sono davvero le 21:00.

Le tre forme di proposta di §9.2 stanno in **una tabella sola**, `trade_proposals`: acquisto secco
= offerti vuoti; scambio = liste piene e conguaglio 0; con conguaglio = liste piene e conguaglio
diverso da 0. Il conguaglio è **con segno**: positivo paga il proponente, negativo paga il
destinatario (serve per «ti do il campione, tu dammi una riserva più denaro»).

RLS: le pendenti le vedono **solo le due squadre coinvolte**; le accettate le vede tutta la lega
(design §9.3, deterrente sociale alla collusione). Provato con tre identità reali.

RPC: `proponi_scambio`, `rispondi_a_proposta(id, accetta)`, `ritira_proposta`.

**La correzione economica da conoscere.** Design §5.4 vuole che chi acquista a stagione in corso
paghi «costo trasferimento + ingaggio pro-rata sulle giornate rimanenti». Preso alla lettera quel
pro-rata **sparirebbe dalla lega**: il venditore l'ingaggio pieno l'ha già pagato al draft, e §5.3
dice che i trasferimenti sono a somma zero. Qui si applica l'unica lettura coerente con entrambe:
chi riceve un giocatore ne paga il pro-rata, **chi lo cede se lo vede accreditato**. La RPC verifica
a runtime che i due saldi sommino a zero e solleva un errore interno se non lo fanno.
`giornate_rimanenti` conta le fixture ancora `programmata`.

Vincoli all'accettazione, per **entrambe** le squadre: rosa tra 21 e 30 giocatori.
`slot_rosa` resta l'obiettivo del draft iniziale, non il tetto del mercato.
La proprietà dei giocatori è ricontrollata all'accettazione: fra proposta e risposta possono
passare ore e un altro scambio.

Uno scambio **cancella le formazioni già salvate** delle giornate non ancora simulate che
contenevano un giocatore coinvolto, e lo dice nella notifica. Senza, si scenderebbe in campo con
una scelta del computer al posto della propria.

**UI**: `Mercato.tsx`, voce di navigazione fra «Squadra» e «Partite». Contiene, in quest'ordine:
proposte ricevute (per prime, sono la cosa urgente), compositore di una nuova proposta, proposte
inviate, log pubblico delle concluse. Il compositore mostra le due rose affiancate e si seleziona
per tocco; il conguaglio si scrive in M€ ed è con segno. Fuori orario la schermata resta navigabile
ma il pulsante d'invio è disattivato — la regola vera resta nella RPC, dove non è aggirabile
cambiando l'orologio del telefono. Squadre e stemmi vengono da `useSeasonData`, che risolve già la
firma delle URL: rifarla a mano avrebbe prodotto una seconda verità.

La voce «Mercato» **sparisce a campionato concluso**: non ci sono giornate su cui schierare chi si
compra, e le RPC rifiuterebbero comunque.

### Mercato — aste a busta chiusa sugli svincolati (design §9.4)

Estrazione alle 07:00, risoluzione alle 21:00, entrambe con la solita forma: job ogni ora, la
funzione decide se a Roma è l'ora giusta.

**La soglia non è in `public`.** La RLS filtra le righe, non le colonne: se la soglia stesse in
`free_agent_auctions`, chiunque possa leggere l'asta la leggerebbe e offrirebbe un euro sopra. Sta
in `private.auction_thresholds`, che PostgREST non espone. Verificato: un partecipante che prova a
leggerla riceve `permission denied`.

**Busta chiusa**: la policy su `free_agent_bids` consegna solo le proprie offerte, anche dopo la
risoluzione — ciò che viene rivelato è *chi ha preso chi*, non quanto avevano offerto gli altri.
Verificato: con 5 offerte in tabella, una squadra ne vede 1.

Il pool è «catalogo meno chi ha già una squadra in questa lega», filtrato per `campionati_attivi`.
Gli under 20 vengono estratti **per primi** (3 su N): un sorteggio uniforme su migliaia di nomi non
ne pescherebbe quasi mai tre.

**Nessun tetto di vittorie giornaliere**, e **a parità vince chi ha offerto prima**. Entrambe sono
correzioni dell'utente del 2 agosto contro design §9.4, che imponeva un massimo di 3 aste al giorno
e il sorteggio in caso di parità; la specifica è stata aggiornata con la motivazione. Il tetto non
regge al modo in cui è fatta la giornata: la lista esce completa alle 07:00 e nulla viene assegnato
fino alle 21:00, quindi si offre su tutti e si scopre solo alla fine quante se ne sono vinte.

Conseguenza della precedenza: conta l'istante in cui è stato fissato l'importo **attuale**.
Modificare l'offerta riazzera `free_agent_bids.aggiornata_il` — la colonna si chiamava `creata_il`
ma veniva già riscritta a ogni modifica, e il nome mentiva. Senza questa regola si piazzerebbe il
minimo su tutto alle 07:00 solo per prenotare la precedenza, alzando poi alle 20:59.

**Offrire impegna budget e slot** (decisione dell'utente, stesso giorno). È ciò che rende coerente
l'assenza di tetto: non potendosi impegnare oltre le proprie possibilità, tutto ciò su cui si è
offerto è anche tutto ciò che si può pagare. Senza, si sarebbe potuto offrire su dieci giocatori
avendo i soldi per quattro, e alle 21:00 se ne sarebbero vinti quattro **arbitrari**, scelti
dall'ordine di estrazione. Questo chiude il dettaglio che era rimasto aperto.

**Impegno calcolato, non denaro spostato**: `private.budget_impegnato()` e
`private.slot_impegnati()` sommano le offerte su aste ancora `aperta`; il budget resta intatto.
Scalare e rimborsare avrebbe richiesto un percorso di rimborso affidabile per ogni asta persa,
ritirata o deserta, e un solo difetto lì distruggerebbe denaro. Un impegno calcolato si annulla da
solo. Entrambe le funzioni accettano un `p_escludi`, che serve quando si **sostituisce** la propria
offerta su una certa asta: quella vecchia non va contata contro la nuova.

`public.budget_disponibile(league_id)` è il wrapper che il browser chiama per sapere quanto gli
resta; la schermata mostra il disponibile al posto del budget quando c'è qualcosa di impegnato.
Gli slot liberi sono calcolati rispetto al massimo permanente di 30 giocatori.

I controlli su budget e slot restano anche alla risoluzione, ma ora sono una rete e non la regola:
l'impegno li ha già garantiti.

**Il numero di estratti è un parametro**, `private.svincolati_da_estrarre()`: 10 normalmente, 20 con
`leagues.stato = 'offseason'` (design §10.6). Quello stato non esiste ancora nel CHECK, quindi il
ramo è per ora inerte — è scritto adesso perché la regola è già decisa e per non lasciare in giro
un `10` da ritrovare.

**Nota di metodo**: la prima stesura aveva la guardia sull'ora dentro il corpo delle funzioni, il
che le rendeva non verificabili (a qualunque altra ora restituiscono 0). Una seconda migrazione ha
separato la guardia dalla logica — `estrai_svincolati_lega(lega, giorno)` e
`risolvi_aste_giorno(giorno)` — senza cambiare il comportamento in produzione. Se si toccano le
aste, si provano da lì.

### Mercato — svincolo (design §9.5)

Completato il 2 agosto 2026. `public.svincola_giocatore(instance_id)` mette `team_id` a null senza
toccare budget o `transactions`, quindi non rimborsa l'ingaggio già pagato. La RPC verifica
autenticazione, proprietà, stagione attiva, finestra 07:00–21:00 e almeno 21 giocatori residui.
Le formazioni future che contengono il giocatore vengono cancellate e
l'utente riceve una notifica.

L'azione è nella scheda giocatore della propria squadra, con una conferma esplicita; non compare
nel mercato né sui profili avversari. Il test in `tools/validazione/test_svincola_giocatore.sql`
copre i controlli in `begin/rollback`, inclusi proprietà, minimi rosa, budget invariato,
formazione rimossa, riacquisto della stessa istanza all'asta e privilegi RPC.

### Una lega conclusa non è più scambiata per una lega vuota

Segnalato dall'utente: la lega di prova mostrava «la lega partirà quando l'admin avrà completato i
posti e aperto il draft» pur avendo 4 squadre su 4. Non mancava nessuno — **quella lega è finita**:
24 giornate su 24 simulate, stagione 1 conclusa, 100 giocatori assegnati.

La causa era l'instradamento: `App.tsx` mandava allo spogliatoio **tutto ciò che non era `draft`
né `stagione`**, e lo spogliatoio è scritto per il *prima* del draft. Una lega `conclusa` ci finiva
dentro e veniva descritta come in attesa di partecipanti. Nella barra laterale lo stesso equivoco
al contrario: «Stagione 1 in corso», perché `GameNav` trattava come in corso tutto ciò che non era
draft.

Ora `conclusa` va alle schermate di stagione — classifica, partite e rose restano da guardare — e
l'etichetta dice «Stagione N conclusa».

### Il motore non muore più per una formazione stantia

`buildLineup` faceva `throw` se un giocatore della formazione salvata non era più in rosa. Siccome
l'errore risale fino al gestore esterno, **una sola formazione stantia avrebbe fatto fallire la
giornata dell'intera lega**. Non era un difetto vivo finché `team_id` non cambiava mai dopo il
draft: lo sarebbe diventato al primo scambio. Ora un ceduto è trattato come un indisponibile
qualsiasi e viene rimpiazzato; si solleva un errore solo se non si arriva a undici.

### Limiti permanenti della rosa

Completato il 2 agosto 2026. Il draft iniziale resta configurabile tramite `slot_rosa`, ora tra
21 e 30 giocatori (default 25). Dopo il draft il mercato può far variare la rosa, ma svincoli,
scambi e aste devono conservarla tra **21 e 30 giocatori**. Le offerte aperte prenotano uno dei
30 posti; il resolver delle 21:00 ricontrolla il massimo prima dell'assegnazione.

Le funzioni `private.rosa_minima()` e `private.rosa_massima()` centralizzano i due valori lato
database. La UI esporta gli equivalenti `ROSA_MINIMA` e `ROSA_MASSIMA` da `src/lib/league.ts`.
Il test transazionale dello svincolo copre ora 14 verifiche, inclusi minimo 21, contatore a 30,
offerta per il trentunesimo giocatore e rete finale del resolver.

### Galleria stemmi squadra

Completata il 2 agosto 2026. I sei stemmi SVG provvisori sono stati rimossi dal selettore e
sostituiti con 34 PNG in `public/stemmi-squadra/`. L'app usa copie 320×320 leggere in
`public/stemmi-squadra/thumbs/` e le carica in lazy loading; gli originali restano disponibili
come sorgenti. Il caricamento di uno stemma personale su Storage resta invariato.

I codici accettati sono centralizzati lato frontend in `src/lib/teamCrests.ts` e validati lato
database da `private.stemma_valido`. La migrazione converte gli eventuali sei preset storici nel
nuovo default `preset:1`. Verifica remota: 34/34 nuovi preset validi, 0 vecchi ancora validi e
0 squadre con stemma non valido.

### Realtime notifiche compatibile con supabase-js 2.111

Corretto il 2 agosto 2026 un crash che lasciava la pagina della lega completamente nera.
`GameNav` monta sia la campanella desktop sia quella mobile; realtime-js 2.111 riusa il canale
quando il topic coincide e vieta di aggiungere callback `postgres_changes` dopo `subscribe()`.
Ogni istanza usa ora un topic univoco e gli errori sincroni della sottoscrizione restano confinati
alle notifiche, senza interrompere il gioco.

---

## Database remoto

Migrazioni applicate fino a `20260802214000_gestione_infortuni.sql`. Il file dello
svincolo era stato generato
dal CLI alle 09:50, ma è stato spostato dopo le migrazioni del mercato perché dipende da quelle
funzioni e ne corregge il resolver delle aste; la cronologia remota è stata riallineata.

Le migrazioni principali del 2 agosto e il perché di ciascuna:

| Migrazione | Perché |
|---|---|
| `094000_persisti_condizione_rosa` | condizione e infortuni riscritti dopo la giornata |
| `210000_svincola_giocatore` | RPC di svincolo e riuso della stessa istanza se torna dall'asta |
| `211000_limiti_rosa` | draft 21–30 e limiti permanenti 21–30 su svincoli, scambi e aste |
| `212000_pulisci_budget_disponibile` | rimuove una lettura della lega diventata inutile |
| `213000_stemmi_squadra_preset` | abilita i 34 stemmi nuovi e ritira i sei preset provvisori |
| `214000_gestione_infortuni` | notifiche dedicate e indisponibili ammessi soltanto in tribuna |
| `120000_notifiche` | tabella notifiche, RLS, RPC, realtime |
| `133000_chiudi_privilegi_scrittura` | revoca write ad `authenticated`, elenco a mano — **ne mancava tre** |
| `134500_chiudi_privilegi_tabelle_draft` | rifatto iterando su `pg_class`, più le default privileges |
| `150000_mercato_trattative` | finestra, `trade_proposals`, tre RPC, cron delle 21:00 |
| `170000_mercato_aste_svincolati` | aste, soglia in `private`, offerte, due cron |
| `173000_aste_logica_verificabile` | guardia oraria separata dalla logica, per poterla provare |
| `183000_aste_niente_tetto_e_precedenza` | correzioni dell'utente contro §9.4 |
| `193000_aste_budget_impegnato` | offrire impegna budget e slot |
| `200000_aste_messaggi_leggibili` | `private.in_milioni()`, messaggi d'errore leggibili |

**Cron registrati**, tutti ogni ora, ciascuno decide da sé se a Roma è l'ora giusta:
`simulazione-notturna` 23:00 · `estrazione-svincolati` 07:00 · `chiusura-mercato` 21:00 ·
`risoluzione-aste` 21:00.

**Nessuna lega è in stato `stagione`**: due in `setup` con una sola squadra, una `conclusa` con
24 giornate su 24 simulate. Finché non se ne avvia una, il mercato non è visibile dall'app e i
cron non hanno nulla su cui lavorare. È anche il motivo per cui nulla del mercato è stato ancora
provato dall'interfaccia.

### Privilegi di scrittura chiusi — difetto latente trovato il 2 agosto

Supabase imposta `ALTER DEFAULT PRIVILEGES` in modo che **ogni tabella creata in `public` conceda
automaticamente ALL a `anon` e `authenticated`**. Le migrazioni del progetto avevano sempre revocato
ad `anon` ma mai ad `authenticated`, contando sulla RLS. La RLS in effetti bloccava tutto:
`INSERT`/`UPDATE`/`DELETE` sono negate perché nessuna tabella ha policy di scrittura, e la verifica
ha confermato **RLS attiva su tutte e 15 le tabelle** di `public`.

Il buco era un altro: **`TRUNCATE` non passa dalla RLS**. E su `draft_team_state` — creata dopo la
migrazione dei privilegi e mai coperta da nessun revoke — i privilegi pieni erano concessi anche ad
**`anon`**, cioè alla chiave pubblicabile che viaggia dentro il bundle del frontend.

Nulla stava trapelando: `TRUNCATE` non è esposto da PostgREST e nessuna policy si applica ad `anon`.
Ma la sicurezza del progetto non deve dipendere da cosa PostgREST espone.

Due migrazioni: `20260802133000` elenca le tabelle a mano e **ne manca tre** (le tre del draft);
`20260802134500` le chiude iterando su `pg_class` invece di elencarle. La lezione è nel commento
della seconda: un elenco scritto a mano ha già sbagliato una volta, e la prossima tabella
dimenticata sarebbe una del mercato. La prima migrazione contiene anche
`alter default privileges in schema public revoke all on tables from anon, authenticated`, così le
tabelle future — proposte di scambio e offerte a busta chiusa — **nascono chiuse**.

Nessun effetto sull'applicazione: il frontend non fa **nessuna** scrittura diretta (verificato con
una ricerca su `src/`), tutto passa da RPC `SECURITY DEFINER` che girano come proprietario.

Quella migrazione corregge un difetto latente che vale la pena capire, perché è il genere di cosa
che si ripresenta. La policy `player_photos_download` limitava l'accesso alle sole operazioni
`object.get_authenticated_info` e `object.get_authenticated`. **La creazione di una URL firmata è
un'operazione diversa e restava negata.** Il difetto non si era mai visto perché con `foto_url`
nullo il client non aveva mai chiesto una firma: è emerso tutto insieme nel momento in cui le foto
sono state caricate. La policy è ora allineata a quella degli stemmi, che usa il solo vincolo sul
bucket. Conseguenza accettata: un partecipante autenticato può anche elencare il bucket delle foto.

---

## Verifiche eseguite

- `npm run build` e `npm run lint`: superati.
- `node tools/validazione/simulate.js`: **diff zero** contro `docs/risultati-fase0.txt`.
- Attribuzione minuti/assist provata su 4.000 partite generate dal motore.
- `cognome()` provata su tutti i 5.416 nomi del dataset.
- Integrità foto: join `players` × `storage.objects`, 5.225 su 5.225.
- L'utente ha verificato su iPhone che le foto si vedono e che la navigazione in basso funziona.
- **Isolamento RLS delle notifiche, provato sul database reale** con due identità vere
  (`set local role authenticated` + `request.jwt.claims`), il tutto dentro un `rollback`:
  l'utente B legge 0 righe di A, l'utente A legge la propria, `authenticated` non ha né `TRUNCATE`
  né `DELETE`, `anon` non ha `SELECT`. Lo script è in `scratchpad`, non versionato: si rifà in un
  minuto e va rifatto **dopo ogni tabella nuova del mercato**.
- Stato privilegi dopo le due migrazioni: zero privilegi di scrittura per `anon`/`authenticated`
  su tutto `public`, zero grant di qualsiasi tipo per `anon`, `SELECT` per `authenticated` su tutte.
- Esistenza degli oggetti confermata anche da PostgREST: una chiamata senza login a
  `/rest/v1/notifications` e a `/rest/v1/rpc/segna_notifiche_lette` risponde `42501`
  (permesso negato) e non «relation not found», cioè la schema cache li vede.
- **Mercato, percorso completo sul database reale** (lega riportata in stagione dentro un
  `rollback`, tre identità vere): proposta creata e visibile a entrambe le parti, accettata,
  giocatori scambiati, **somma dei due saldi = 0**, due movimenti in `transactions`, 6 formazioni
  rimosse perché contenevano un ceduto, 3 notifiche generate.
- **Aste, percorso completo** (15 controlli, rollback): 10 estratti di cui 4 under 20, nessuno già
  in una rosa, 10 soglie generate, istanze create, budget addebitato, movimenti e notifiche.
- **Aste, riservatezza**: un partecipante che prova a leggere `private.auction_thresholds` riceve
  `permission denied`; con 5 offerte in tabella una squadra ne vede **1**, la propria.
- **Aste, regole corrette dall'utente**: una squadra ne ha vinte **5** dove il vecchio tetto ne
  avrebbe permesse 3; su un pareggio esatto ha vinto la squadra la cui offerta era retrodatata.
- **Aste, impegno del budget** (7 controlli): la prima offerta azzera il disponibile, la seconda è
  respinta col motivo, il ritiro libera all'istante, modificare la propria offerta non la conta due
  volte, gli slot liberi tornano il numero atteso.
- **Deploy automatico**: hash del bundle locale identico a quello servito da
  `specialone-five.vercel.app` dopo un push, con deploy partito da solo in ~10 secondi.
- **Mercato, prove negative**: un terzo partecipante della stessa lega vede 0 righe di una proposta
  pendente e non può accettarla al posto del destinatario («Questa proposta non è indirizzata a
  te»); la stessa proposta, una volta accettata, gli diventa visibile (design §9.3). Uno scambio
  alla pari che lascerebbe una squadra senza portieri è respinto dal controllo giusto — la prima
  versione della prova era stata respinta dal vincolo sugli slot, che scatta prima, quindi è stata
  rifatta a parità di numeri per esercitare davvero la regola sui portieri.
- **Svincolo, percorso completo** (11 controlli, rollback): proprietà verificata, minimo 11 e
  minimo portieri protetti, istanza resa libera, budget invariato, formazione futura rimossa,
  notifica creata, doppio svincolo respinto, riacquisto all'asta sulla stessa istanza e privilegi
  `anon`/`authenticated` corretti.

## Cosa NON è verificato

- Il bundler di Supabase non fa type-check del TypeScript delle Edge Function: un errore di tipo
  non blocca il deploy e si manifesta solo alla prima chiamata.
- **Le notifiche non sono ancora state viste arrivare da una simulazione reale.** Il percorso è
  verificato pezzo per pezzo (tabella, policy, isolamento, grant, build, deploy), ma nessuna
  giornata è stata simulata dopo il deploy: manca la prova che la riga compaia sulla campanella.
  Si fa simulando una giornata e guardando il campanello, oppure con
  `select tipo, titolo, corpo from public.notifications order by id desc limit 10;`.
- Il canale Realtime non è stato provato con un client vero: la tabella è nella publication e il
  codice si iscrive, ma la consegna dal vivo non è stata osservata. Se non funzionasse, il refetch
  su `visibilitychange` copre comunque il caso.
- **Nessuno dei tre cron del mercato è mai stato visto girare al proprio orario.** Sono registrati
  (`chiusura-mercato`, `estrazione-svincolati`, `risoluzione-aste`, tutti ogni ora) e le funzioni
  sono provate chiamandole a mano, ma nessuna esecuzione reale è stata osservata. Il primo giorno
  con una lega in stagione è anche il primo collaudo vero.
- **Tutto il mercato non è mai stato usato dall'interfaccia da un utente vero**: le verifiche sono
  passate dalle RPC via SQL. Le schermate compilano e sono state ragionate, non provate a mano.
- **Nessuna lega è attualmente in stato `stagione`**: le tre esistenti sono due in `setup` e una
  `conclusa`. Il mercato quindi non è provabile dall'interfaccia finché non se ne avvia una.

---

## Trappole scoperte il 2 agosto — costano ore se le si reincontra

- **`now()` è costante dentro una transazione.** Due righe inserite di seguito in uno script di
  prova hanno lo **stesso identico istante**. Provando la precedenza a parità d'offerta il test
  sarebbe passato senza dimostrare nulla: i timestamp vanno impostati a mano. In produzione il
  problema non esiste, perché ogni chiamata dal browser è una transazione a sé.
- **La RLS filtra le righe, non le colonne.** Un segreto che sta in una colonna di una tabella
  leggibile *è leggibile*. La soglia delle aste è per questo in `private.auction_thresholds`,
  fuori da `public`, che PostgREST non espone. In alternativa esistono i GRANT per colonna, ma
  rompono `select('*')` dal client.
- **Le default privileges di Supabase concedevano ALL a `anon` e `authenticated` su ogni tabella
  nuova.** Chiuse il 2 agosto: ora una tabella nuova nasce senza privilegi e **i GRANT vanno
  scritti a mano nella migrazione**, altrimenti la tabella è invisibile anche a chi ha diritto.
- **Una guardia oraria dentro il corpo di una funzione la rende non verificabile.** Le funzioni
  delle aste sono state spezzate in wrapper (con la guardia) e logica (con il giorno come
  parametro) proprio per poterle provare. Se aggiungi job schedulati, fai lo stesso.
- **`supabase.rpc(...)` non restituisce una `Promise`** ma un builder attendibile: nelle firme
  TypeScript va tipizzato `PromiseLike<…>`, altrimenti `tsc` fallisce.
- **`round(x / 100000.0) / 10.0` conserva la scala della divisione** e stampa
  `2.0000000000000000`. Per il testo che legge un utente c'è `private.in_milioni(bigint)`.
- **Il CLI Supabase mostra solo l'ultimo result set** di uno script multi-statement.
- **`transactions.importo` ha un CHECK `<> 0`**: un movimento nullo va saltato, non inserito.

## Debiti noti e trappole

- **5.225 oggetti duplicati** nel bucket, al percorso sbagliato `players/images/…`, residuo del
  primo tentativo di upload. Nessuno li referenzia, ma occupano 44 MB. **`supabase storage rm`
  risponde `{"deleted":[]}` senza errore** con qualunque forma di percorso: è un difetto della CLI.
  Vanno cancellati dalla dashboard (Storage → `player-photos` → cartella `images`).
- **Percorsi Windows con lettera di unità rompono la CLI Storage**: `C:/…` viene letto come schema
  URI. Bisogna entrare nella cartella e usare percorsi relativi.
- **`storage cp -r` usa il nome della cartella sorgente come destinazione**: la cartella locale
  deve chiamarsi `players`, altrimenti i percorsi non corrispondono a `foto_url`.
- **% contrasti vinti e % dribbling riusciti non sono calcolabili**: il motore non produce i
  tentativi. `contrasti_persi` è scritto come `0` fisso dalla Edge Function, quindi la percentuale
  sarebbe 100% per chiunque. Nella scheda giocatore sono mostrati come numeri assoluti. Renderle
  vere richiede una modifica additiva a `engine.js` con protocollo di regressione completo.
- **I gol sono distribuiti in modo piatto sui 90 minuti** (16,6% per quarto d'ora): il motore
  assegna a tutti e 6 i blocchi lo stesso xG di base. Non è un difetto dell'attribuzione. Correggerlo
  significherebbe modulare `XG_BASE_BLOCCO` per blocco, cioè toccare le formule validate.
- `useSeasonData` interroga `matches` per `league_id` senza `season_id`: innocuo con una sola
  stagione, diventa un difetto alla seconda.
- `Rosa.tsx` carica `foto_url` ma non lo usa: nessuna foto nella rosa di draft.
- Il bundle ha superato i 500 kB e Vite lo segnala a ogni build. Non e' un errore, ma e' il
  momento in cui varrebbe la pena separare il codice per schermata.
- La formazione salvata è slot-per-slot; non riordinare gli array dei titolari prima del motore.
- `sostituzioni()` muta il lineup: costruire oggetti freschi per ogni partita.
- Il seed globale impone simulazioni in sequenza, mai in parallelo.
- **I cartellini non esistono nel motore**: nessun riferimento a falli, ammonizioni o espulsioni
  in tutto `engine/`. Non sono un flag da accendere. Due strade: attribuirli fuori dal motore come
  gli assist (rischio zero) oppure modellarli dentro con l'effetto vero dell'uomo in meno, che
  però tocca le formule validate e impone il protocollo di regressione.

---

## Prossime task consigliate

1. **Completare la grafica**: il menu di stagione è finito. Restano **Lobby**, **Draft**,
   **Onboarding** e **Login**. I mattoni condivisi esistono già (`.esito`, `.esito-riga`,
   `.stat-guida`, `.giornata-card`, `.sezione-testa`, `.button-fantasma`, `.pillola-stato`,
   `.menu-azione`, `.forma-chip`, `.pannello-laterale`): è in gran parte riuso.
2. **Decidere il disallineamento del calendario** descritto sopra: il cron rispetta le date, ma le
   simulazioni manuali sono andate avanti rispetto ad esse.
3. **Fallback formazione alle 23:00**: oggi l'ereditarietà avviene dentro la simulazione, cioè alle
   00:00. L'utente non ha modo di vedere e correggere la formazione automatica prima della partita,
   che è lo scopo dell'orario anticipato (design §6.7).
4. **Test end-to-end** con più account reali: turni di riposo, fine calendario, controlli RLS.
5. **Mercato**: fuori dallo scope Fase 1, deciso dall'utente. Tutti e tre i sottosistemi di design
   §9 sono completati:
   - ~~trattative fra squadre (§9.2)~~ — **fatte**, database e interfaccia;
   - ~~aste svincolati (§9.4)~~ — **fatte**, database e interfaccia;
   - ~~svincolo (§9.5)~~ — **fatto**, database e interfaccia.

   **Due cose da sapere prima di scrivere codice**, entrambe verificate nel codice:

   - **Le istanze giocatore nascono solo al pick** (`draft_indipendente.sql:223`): chi non è mai
     stato draftato **non ha una riga**. Quindi il pool svincolati non è «istanze con `team_id`
     null» ma «catalogo meno gli istanziati in questa lega, filtrati per `campionati_attivi`», e la
     riga nasce quando l'asta viene vinta. Il design doc lascia intendere il contrario.
   - `transactions` è già append-only con `saldo_dopo`: i trasferimenti ci entrano senza toccare
     nulla. I premi partita vanno normalizzati (design §5.2), mai valori assoluti.

   **Stato**: mercato completo a livello di database e interfaccia, con finestra 07:00–21:00.

   Per provare il mercato dall'app serve una lega in stato `stagione`: al 2 agosto 2026 non ce ne
   sono (due in `setup` con una sola squadra, una `conclusa`).

6. **Push del browser**, sopra la tabella `notifications` che ora esiste. Vedi il limite iOS
   descritto nella sezione delle notifiche.

7. **Off-season** (Fase 3): specificato dall'utente il 2 agosto 2026 e scritto in `design.md`
   **§10.6**, che vince sul resto della sezione 10. In sintesi: a fine stagione l'admin sceglie fra
   terminare la lega, rimuovere partecipanti o aggiungerne; poi **una settimana** prima del via, in
   cui i nuovi fanno il draft, le vecchie squadre trattano i rinnovi (tutti i giocatori presi al
   draft hanno **un anno** di contratto, quindi vanno tutti a rinnovo insieme) e il sorteggio
   giornaliero degli svincolati passa da 10 a **20**.

   Due cose da NON dare per risolte, entrambe elencate in §10.6: un **conflitto** su come pesca un
   nuovo partecipante (rollate sui club, versione utente, contro draft dagli svincolati, versione
   §10.5) e **quattro punti non specificati** (sorte dei giocatori di un rimosso, silenzio-assenso
   sui rinnovi, trattative attive o no durante la settimana, budget dell'entrante contro la regola
   della dotazione una tantum).

   Conseguenza pratica sul lavoro in corso: **le aste svincolati vanno scritte con il numero di
   estratti come parametro**, non come `10` fisso.

## Stato UX deciso dall'utente

- Deve sembrare un videogioco manageriale, non un sito minimale.
- Riferimenti visivi: app di risultati live in stile LiveScore e cruscotti calcistici viola.
- L'esperienza principale è smartphone: ogni cambiamento va provato prima su viewport mobile.
- Le immagini giocatore non devono avere rettangoli dietro. **Attenzione**: un `filter` CSS si
  applica anche agli pseudo-elementi, quindi un `drop-shadow` sul contenitore proietta l'ombra dei
  loro riquadri invece della sagoma del giocatore. L'ombra va sull'`img`.
- Logo squadra sempre quadrato, e senza cornice attorno.

## Aggiornamento rapido 2 agosto 2026

- Loading screen: usa `specialone-mark.svg` invece del vecchio scudo `S1`.
- Onboarding: dal menu nuovo, il tasto Indietro di "Crea lega" e "Entra con un codice" torna al menu nuovo.
- Join lega: ora e' in due step, prima codice invito e poi nome/stemma squadra.
- Stemmi: picker ingrandito; quelli gia' usati nella lega sono disabilitati nel join.
- Database: migrazione `20260802221000_offseason_un_giorno_stemmi_unici.sql` applicata. Aggiunge `anteprima_invito`, respinge stemmi duplicati in `entra_in_lega` e `aggiorna_profilo_squadra`, e forza l'off-season a 1 giorno tramite trigger su `offseasons`.
- Off-season spin: migrazioni `20260802222000_offseason_spin_mercato.sql` e `20260802223000_fix_offseason_spin_lint.sql` applicate. Ogni squadra attiva in off-season ha 5 spin. Uno spin propone un giocatore libero sostenibile: la squadra puo' ingaggiarlo subito oppure mandarlo nella lista svincolati del giorno. Gli spin mandati al mercato creano aste `origine = 'spin_offseason'` e non consumano i 20 estratti giornalieri `origine = 'estrazione'`.
- UI Mercato: in off-season compare il pannello "Spin mercato" con contatore, proposta aperta, azioni "Ingaggia" e "Manda al mercato", piu' log degli spin gia' risolti.
- Verifiche eseguite: `npm.cmd run build`, `npm.cmd run lint`, `npx.cmd supabase db lint --linked --level warning`, `tools/validazione/test_offseason_spins.sql` via `supabase db query --linked --file ...` con rollback. Tutto OK.

## Aggiornamento rinnovi 2 agosto 2026

- Migrazione `20260802224000_rinnovi_controproposta.sql` applicata. Un rinnovo non viene piu' rifiutato al primo tentativo sotto la richiesta reale: passa a `controproposta`, mostra la cifra esatta come ultima richiesta e resta trattabile. Se anche la seconda offerta non basta, allora il giocatore viene svincolato.
- UI rinnovi: input offerta passato da `type=number` a `type=text` con `inputMode=decimal`, quindi su mobile si puo' cancellare il campo e usare la virgola italiana senza trasformazioni automatiche a `0`.
- UI rinnovi: se un rinnovo e' accettato, accanto allo stato viene mostrato il nuovo contratto, es. `2,5 M€/stag · 3 anni`.
- Verifiche eseguite: `npm.cmd run build`, `npm.cmd run lint`, `npx.cmd supabase db lint --linked --level warning`, `tools/validazione/test_rinnovi_controproposta.sql` via `supabase db query --linked --file ...` con rollback. Tutto OK.

## Fix rinnovi 2 agosto 2026

- Migrazione `20260802225000_rinnovi_ingaggio_netto_mobile.sql` applicata. La durata del rinnovo non maggiora piu' l'ingaggio: l'offerta accettata e' l'ingaggio annuo firmato. La durata serve solo a bloccare quella cifra per piu' stagioni.
- La migration riallinea anche i rinnovi gia' accettati: `player_instances.ingaggio = contract_renewals.offerta`. Verifica diretta su `sdsDas`: Olise 12,0M/anno e Bruno Varela 1,3M/anno.
- UI mobile rinnovi: layout a colonna singola sotto i 720px; richiesta/controproposta e azioni non finiscono piu' nella colonna desktop compressa.
- Test `tools/validazione/test_rinnovi_controproposta.sql` reso dinamico: non dipende piu' da ID fissi gia' risolti manualmente. Verifica rollback OK per controproposta, rifiuto finale e accettazione con ingaggio netto.

## Aggiornamento mercato svincolati 2 agosto 2026

- Migrazione `20260802230000_svincolati_per_ruolo.sql` applicata. L'estrazione giornaliera non pesca piu' un numero totale generico: in stagione normale crea 12 aste, cioe' 3 portieri, 3 difensori, 3 centrocampisti e 3 attaccanti; in off-season crea 40 aste, cioe' 10 per macro-ruolo.
- Classificazione macro-ruolo centralizzata in `private.macro_ruolo(posizioni)`: GK, DEF (`CB/LB/RB/LWB/RWB`), MID (`CDM/CM/CAM/LM/RM`), ATT (`ST/CF/LW/RW`).
- UI Mercato: la sezione svincolati e' ora divisa in "Nuovi oggi" con card fotografiche e "Archivio" con tutti gli svincolati caricati dalle aste recenti. L'archivio ha filtri per ruolo, eta', ingaggio e overall.
- Verifiche eseguite: `npm.cmd run build`, `npm.cmd run lint`, `npx.cmd supabase db lint --linked --level warning`, `tools/validazione/test_svincolati_per_ruolo.sql` via `supabase db query --linked --file ...` con rollback. Tutto OK.

## Fix archivio svincolati 2 agosto 2026

- Migrazioni `20260802231000_svincolati_archivio_rioffribili.sql`, `20260802232000_fix_lint_svincolati_archivio.sql` e `20260802233000_fix_trigger_squadra_attiva_bids.sql` applicate.
- Regola definitiva: "Nuovi oggi" e' solo la vetrina giornaliera. I vecchi svincolati non ingaggiati restano rioffribili dall'Archivio. Quando una squadra offre su un vecchio svincolato, `public.offri_per_svincolato_archivio(league_id, player_id, ingaggio)` crea/usa un'asta aperta per oggi con `origine = 'archivio'` e poi passa dalla stessa validazione di `offri_per_svincolato`.
- `origine = 'archivio'` non conta come estrazione giornaliera: non blocca i 12/40 nuovi del giorno.
- Il test ha scoperto e corretto un bug nel trigger `private.verifica_squadra_mercato_attiva()`: su `free_agent_bids` poteva leggere `da_team_id` invece di `team_id`. Ora il trigger usa `to_jsonb(new)` e sceglie il campo presente.
- UI Archivio: i giocatori sotto contratto sono esclusi; gli svincolati storici mostrano il bottone `Rioffri`, che apre l'asta odierna lato server.
- Verifiche eseguite: `npm.cmd run build`, `npm.cmd run lint`, `npx.cmd supabase db lint --linked --level warning`, `tools/validazione/test_svincolati_archivio_rioffribili.sql` con rollback. Tutto OK.

## Aggiornamento limiti rosa 2 agosto 2026

- Il minimo portieri e' stato rimosso come regola di gioco. La colonna `leagues.portieri_minimi`
  resta per compatibilita' con RPC e codice storico, ma deve essere sempre `0`.
- I limiti vincolanti restano solo **minimo 21** e **massimo 30** giocatori in rosa.
- Conseguenza off-season: alla scadenza delle 24 ore una squadra sotto il minimo viene completata
  automaticamente fino a 21 con gli svincolati piu' economici sostenibili. Non e' richiesto alcun
  numero minimo di portieri.
- Verifiche eseguite: `npm.cmd run build`, `npm.cmd run lint`, `npx.cmd supabase db lint --linked --level warning`,
  query remota su `public.leagues` (`min=max=0`) e `tools/validazione/test_minimo_portieri_rimosso.sql`
  con rollback.

## Timer off-season, navigazione e news — 2 agosto 2026

- Migrazione `20260802235000_offseason_timer_notifiche.sql` applicata. L'off-season dura 24 ore
  effettive e non puo' essere chiusa prima dall'admin. Un cron la finalizza automaticamente alla
  scadenza; il bottone admin resta solo come recupero dopo la deadline.
- Alla chiusura i rinnovi irrisolti scadono, gli spin ancora aperti tornano fra gli svincolati e
  ogni rosa sotto il limite viene completata automaticamente fino a 21 giocatori con opzioni
  sostenibili. I posti espansione rimasti vuoti non entrano nel calendario.
- La prima giornata e' fissata alle prime 23:00 `Europe/Rome` strettamente successive alla
  scadenza; anche le giornate seguenti vengono simulate alle 23:00.
- Navigazione mobile: rimossa la doppia barra inferiore. Tutte le sezioni e gli avvisi sono ora in
  un drawer laterale aperto dal menu in alto a destra. Ogni avviso puo' essere eliminato con la X.
- Mercato: lo spin off-season ha una sequenza animata fluida con nomi in rotazione e reveal
  fotografico, senza ricaricare l'intera pagina.
- Overview: la vecchia card tecnica "Campionato" e' stata sostituita da un carosello di notizie
  giornaliere costruite da risultati, acquisti e scambi reali della lega.
- Verifiche: build e lint frontend OK; lint del database remoto senza errori né warning. Il test transazionale
  `tools/validazione/test_offseason_timer_24h.sql` verifica timer, blocco della chiusura anticipata,
  completamento automatico a 21, primo calcio alle 23:00 e cancellazione degli avvisi.

### Rimossa la funzionalità "spin off-season"

Richiesta diretta dell'utente, 27 agosto 2026: non piaciuta, va tolta del tutto — non solo
disattivata per una lega. Erano le 5 occasioni extra per pescare un giocatore libero durante la
finestra di preparazione (ingaggio diretto o invio agli svincolati del giorno).

Rimossi `public.spin_offseason`, `ingaggia_spin_offseason`, `manda_spin_al_mercato`,
`stato_spin_offseason`, `private.offseason_spin_corrente` e la tabella `offseason_spins`
(nessuna FK entrante, verificato prima di cancellarla). Ripulite le due funzioni collegate:
`finalizza_offseason` non chiude più spin rimasti in sospeso (non ne esistono più), e
`estrai_svincolati_lega` non esclude più i giocatori con uno spin proposto dal sorteggio —
resta invece l'esclusione per `private.rilasci_in_coda`, introdotta il giorno prima e senza
relazione con questa rimozione.

Attenzione al nome: "spin" indica anche il meccanismo di estrazione delle carte nel draft "BY
ROLE" (`draft_by_role_spin`) — tutt'altra funzionalità, non toccata da questa rimozione.

Lato frontend, tolta l'intera sezione da `Mercato.tsx` (stato, fetch, le tre funzioni
`usaSpin`/`ingaggiaSpin`/`mandaSpinAlMercato`, il blocco JSX con l'animazione) e il relativo CSS
morto. Restano intenzionalmente **il tipo `origine: 'spin_offseason'`** su `Asta` e il badge che
lo mostra nelle card: esistono ancora aste storiche generate da vecchi spin (senza alcun vincolo
verso la tabella rimossa), e restano visibili come aste normali.

Verificato prima dell'esecuzione reale: solo Real Fampionato aveva spin legati a un'off-season
ancora aperta (10 righe, delle due squadre entranti, tutte già risolte — nessuno restava "a
metà" con la rimozione). Applicata prima in transazione con rollback, poi per davvero.
