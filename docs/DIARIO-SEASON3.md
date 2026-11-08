# Diario della Season 3

Le funzionalità e le modifiche che il committente vuole per la **Season 3**. Le tiene la sessione supervisore: ogni
richiesta si annota qui con data, stato e decisioni prese, così resta traccia fra una conversazione e l'altra.

**Stati:** `da valutare` (appena chiesta) · `deciso` (regole fissate col committente) · `in lavoro` · `pronto` (fatto e
provato, in attesa di pubblicazione) · `pubblicato` · `rimandato` · `scartato`.

**Calendario:** la Season 2 della Serie F chiude la stagione regolare il 28/10/2026, poi playoff (giornate 23–29), poi
**off-season 3**. Quello che è `pronto` si pubblica a inizio off-season, salvo indicazioni diverse.

---

## 1. Motore di simulazione: meno goleade, più gol nel finale, più peso alla forza

* **Stato:** `rimandato` (5/11/2026): il committente preferisce i risultati di oggi. Il motore nuovo resta sul branch
  `feat/motore-s3`, validato, da riprendere eventualmente a metà Season 3 coi dati veri. Le misure dello stadio (voce 4)
  vanno rifatte col motore attuale.
* **Prima:** `pronto` — da pubblicare all'inizio dell'off-season 3 (deciso il 25/10/2026).
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

* **Stato:** `in lavoro` (5/11/2026): migrazione `20261105103000_season3_morale_tifo_soglia.sql`. Azzeramento alla
  chiusura dell'off-season (confermato il 5/11); soglia al 65% subito per tutte le leghe (oggi decide solo colori ed
  etichette: i richiami partono dal morale sotto 30).
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

* **Stato:** `pubblicato` (5/11/2026): migrazione `20261105113000_cambio_ruolo_secondario.sql`, rosa e vivaio. Lo sconto
  del 25% si somma in punti percentuali a quello dell'allenamento (Quiñones, allenamento −16%: TS 8, ATT o AS 6).
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

* **Stato:** `in lavoro` (5/11/2026): database applicato (migrazione `20261105130000_stadio.sql`), app pronta in
  locale. `leagues.stadio_attivo`: Serie F acceso subito, le altre leghe alla loro prossima stagione
  (`finalizza_offseason`). Tetto punti 26 solo dove lo stadio è acceso (`private.punti_abilita_massimi_lega`).
  Nome (5/11): **massimo 25 caratteri**, **mai vuoto**: ogni squadra ha già un nome di default diverso dalle altre della
  lega (`private.nomi_stadio_default`, 30 nomi; trigger per le squadre nuove). Si cambia in Club > Modifica squadra
  **solo a stagione in corso** (dalla Season 3), controllo anche nel database. Si vede nella pagina Club, nella sezione
  Stadio delle Risorse, nel riquadro della prossima partita e nella locandina dell'intro (squadra di casa).
* **Misure col motore ATTUALE (5/11/2026, 30.000 partite per riga, squadre pari):** vittorie casa / pari / trasferta:
  inizio S3 (stadio 0, pubblico 50) **39,6 / 24,8 / 35,6**; stadio 0 e pubblico pieno 41,3 / 24,3 / 34,3; stadio 5 e
  pubblico pieno (come oggi) 46,2 / 23,3 / 30,5; stadio 10 e pubblico pieno **51,4 / 21,8 / 26,8**. Stadio da 0 a 10 con
  pubblico pieno = **+3,0 punti a stagione** (11 partite in casa).
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
  * **crediti per partita in casa: 50 × livello dello stadio** (livello 1 = 50, poi +50 a livello: livello 10 = 500;
    livello 0 = niente). Da pagare insieme ai premi partita, quindi dopo la visione o dopo 24 ore, senza spoiler;
  * confermato dopo le misure: **si parte da +1,0** (proposta di partire da +2,0 scartata dal committente).
* **Misure col motore L2 (chat del motore, rapporto 8):** nessuna modifica al motore, il moltiplicatore oltre 1 funziona
  (va implementato in `moltiplicatori_casa` / `moltiplicatore_pubblico`, più il livello dello stadio salvato in
  `team_risorse`). Vittorie casa / pari / trasferta: inizio S3 (stadio 0, pubblico 50) **39,5 / 24,9 / 35,5**; stadio 5 e
  pubblico pieno (come oggi) 45,9 / 24,0 / 30,1; stadio 10 e pubblico pieno 50,7 / 22,4 / 26,8. Stadio da 0 a 10 con
  pubblico pieno = **+2,8 punti a stagione**. Il target V casa 43–47% di simulate-reale è misurato a moltiplicatore 1:
  con lo stadio va riferito al livello medio reale, da rivedere dopo qualche giornata di Season 3.
* **Grafica (26/10/2026):** nella sezione Stadio delle Risorse l'immagine cambia con il livello. Immagini del committente,
  compresse in WebP 1600×800 in `public/stadio/`: `stadio-0-2.webp` (stadio di provincia), `stadio-3-5.webp` (stadio
  medio a due anelli), `stadio-6-8.webp` (grande stadio col maxischermo), `stadio-9-10.webp` (arena chiusa con il tetto ad
  anello). Abbinamento per grandezza, confermato dal committente il 26/10/2026.
* **Nome dello stadio (26/10/2026):** nella pagina Club, con il pulsante di modifica (dove oggi si cambiano nome e
  stemma), si può scrivere il **nome dello stadio**, **al massimo 20 caratteri** (controllo anche nel database). Se non lo
  si scrive si usa un **nome di default**. Proposta da confermare: una lista di nomi generici entro 20 caratteri
  ("Stadio Comunale", "Arena Civica", "Stadio dei Pini", "Campo dei Tigli"...), assegnati in modo fisso per squadra.
  Dove mostrarlo (da decidere): sezione Stadio delle Risorse, pagina Club, e volendo l'intro della partita in casa.

---

## 5. Prestiti a club finti

* **Stato:** `in lavoro` (5/11/2026): database applicato (migrazione `20261105150000_prestiti.sql`), app pronta in
  locale, simulazione da ridispiegare (esclude i giocatori in prestito). Proposte confermate il 5/11 tranne i club:
  **club reali con stemmi reali** (112 club presenti nei dati, stemmi da TheSportsDB in `public/loghi-club/`,
  tabella `club_prestito`; il sistema sceglie il club meno usato nella lega in quella stagione, così non si ripetono). Regola in più confermata: dopo il prestito restano almeno 18 giocatori
  e un portiere. Si accende con lo stadio (`leagues.stadio_attivo`), quindi in Serie F dalla prima giornata della S3.
* **Richiesta:** «Possibilità di mandare giocatori in prestito. Se ne possono mandare solamente 5 in una stagione. Il
  giocatore in prestito sale quasi come uno che gioca titolare, tra titolare e turnover. Il training è deciso dalle squadre
  dove va in prestito, che decidono quale training e se cambiare ruolo al giocatore. Le squadre sono fittizie, non quelle
  della Serie F, come se andassero a squadre controllate da bot. Un giocatore può essere richiamato dal prestito ma poi non
  può più esserci mandato. Un giocatore può essere mandato in prestito una volta durante la stagione. Il giocatore conta
  sempre sull'ingaggio e sul numero dei giocatori della squadra.»
* **Decisioni:**
  * **massimo 5 prestiti per squadra a stagione**; ogni giocatore **una sola volta a stagione**; **richiamabile** in
    qualsiasi momento, ma dopo il richiamo non può ripartire (in quella stagione);
  * **durata: fino a fine stagione** (o fino al richiamo); **tutti i giocatori** possono andare in prestito;
  * va a **club finti** (non le squadre della lega), gestiti dal sistema come bot;
  * **crescita** come chi gioca il 60% dei minuti: moltiplicatore **1,16** (turnover 1,04, titolare 1,25), per
    l'**allenamento del club che lo ospita** (club finto di livello medio, 5), non quello della squadra proprietaria;
  * **training e cambio ruolo li decide il club ospite**, non il proprietario;
  * **niente infortuni né squalifiche** in prestito: torna com'era partito (crescita a parte);
  * conta **sempre** sul tetto ingaggi e sul numero di giocatori della rosa.
* **Proposte da confermare all'implementazione:**
  * il club ospite sceglie una specializzazione a caso fra quelle disponibili per il ruolo; cambia ruolo con
    probabilità **20%** per prestito, verso un ruolo raggiungibile (`private.ruoli_target_cambio`), con i tempi normali;
  * durante il prestito il giocatore non può essere schierato, scambiato, venduto né svincolato: prima va richiamato;
  * le promesse di minutaggio sono sospese e il morale resta fermo finché è in prestito;
  * a fine stagione rientrano tutti in automatico, prima dell'off-season (rinnovi, invecchiamento);
  * nomi dei club finti da una lista fissa, con stemma generico.

---

## 6. Il tifo segue di più i risultati; derby moltiplicati

* **Stato:** `in lavoro` (5/11/2026): stessa migrazione della voce 2 (`private.e_derby`, `morale_giornaliero`).
* **Cambio del 5/11/2026:** vittoria e sconfitta simmetriche, in casa **+4 / −1 / −4**, in trasferta la metà (+2 / −0,5 /
  −2), derby ×2 (+8 / −8 in casa). Con +3/−1/−5 e partenza da 50 una squadra media perdeva ~14 punti di tifo a stagione
  solo coi risultati; così resta intorno a 50 e il tifo racconta la stagione.
* **Richiesta:** «Vorrei che il morale del tifo si aggiorni con le partite: perdendo una partita si perde punteggio tifo,
  vincendo si guadagna. Nei derby sono moltiplicati.»
* **Oggi** (`private.morale_giornaliero`): in casa vittoria +1,5, pareggio −0,5, sconfitta −2,5; in trasferta la metà.
  Negli scontri fra rivali un bonus in più proporzionale al grado di rivalità (fino a +2 / −3 per il pubblico, ±4 per il
  morale dei giocatori). Il grosso del tifo lo muovono le conferenze stampa.
* **Decisioni:**
  * **risultati raddoppiati**: in casa **vittoria +3, pareggio −1, sconfitta −5**; in trasferta la metà
    (+1,5 / −0,5 / −2,5);
  * **nei derby l'effetto del risultato sul tifo è ×2** (vincere il derby in casa +6, perderlo −10; in trasferta +3 / −5),
    **al posto** del bonus proporzionale di oggi per il pubblico. Derby = rivalità oltre il 90% o rivale dichiarato,
    come nelle conferenze stampa;
  * il morale dei giocatori nei derby (fino a ±4) resta com'è.
* **Note:** con il tifo che riparte da 50 a ogni stagione (voce 2) e lo stadio (voce 4), i risultati contano di più sul
  fattore campo: una buona stagione in casa porta il tifo verso 80, una cattiva lo abbassa molto. Il pubblico resta fra
  0 e 100.

---

## 7. Inni di squadra: collezionabili dalle bustine, si sentono nell'intro

* **Stato:** `scartato` (5/11/2026): il committente ci ha ripensato.
* **Prima:** `da valutare` (27/10/2026): idea chiara, restano da decidere doppioni, quale intro e playoff.
* **Richiesta:** «Gli inni si sentono al posto della canzone della regular season durante l'intro. Si ottengono
  spacchettando le bustine, sono molto rari e a volte escono 3 figurine e 1 inno.» E poi: «gli inni sono canzoni che
  aggiungerò io. Ogni squadra nel menu "altro" troverà il menu "inno di squadra". Lì troveranno la lista degli inni
  disponibili e all'inizio avranno solo quello di default, ovvero quello della lega che si sente ora, e lo chiameremo
  "inno di lega". Quando riceveranno inni spacchettando, questi si aggiungeranno alla loro lista e potranno scegliere
  quale usare se ne hanno più di uno.»
* **Oggi:** l'intro suona un solo brano in loop (`MUSICA_FASE` in `src/lib/faseSquadra.ts`, riprodotto da
  `MatchIntro.tsx`); in regular season è `/musica-fase/regular_season.m4a`. L'intro parte da un tocco dell'utente, quindi
  l'audio può partire da solo senza blocchi del browser.
* **Decisioni:**
  * gli inni sono un **catalogo di canzoni caricate dal committente**, non legati a una squadra precisa: chiunque può
    trovarli e usarli;
  * nuova voce **"Inno di squadra"** nel menu **Altro**: lista degli inni posseduti, si sceglie quello attivo (con ascolto
    di prova);
  * tutti partono con l'**"Inno di lega"** (il brano di oggi), sempre posseduto, attivo di default;
  * gli inni escono **raramente dalle bustine**: in quella bustina escono 3 figurine **più** 1 inno;
  * rarità **1 bustina su 20** (deciso 27/10: «1 su 100 è un po' troppo raro»).
* **Proposte (da confermare):**
  * uguale per bustine comprate e gratis; fra gli inni non ancora posseduti si estrae a caso, così non escono doppioni
    finché ne manca qualcuno;
  * se li hai già tutti, al posto dell'inno arrivano crediti (es. 300);
  * nell'intro si sente l'inno **di chi guarda** (ognuno sente il suo); chi non ne ha scelto uno sente l'inno di lega;
  * **solo regular season**: nei playoff restano le musiche del Title Playoff e del Draft Playoffs.
* **Note tecniche:** i file audio (consigliati 30–90 s, m4a, ~0,5–1,5 MB) vanno su Supabase Storage, non nel sito, così
  se ne aggiungono di nuovi senza rifare il deploy; tabella catalogo (`inni`: titolo, file, attivo) + inni posseduti per
  squadra + inno scelto. L'estrazione dentro `album_compra_bustina` va fatta lato server (non si bara). Per aggiungere un
  inno il committente mi passa il file e il titolo, oppure una piccola pagina admin.

---

## 8. Figurine: quattro rarità (common, rare, ultrarara, ultimate)

* **Stato:** `in lavoro` (5/11/2026): database applicato (migrazione `20261105170000_album_rarita.sql`), app pronta in
  locale. Decisioni del 5/11: **stemmi e conference al 5% per figurina** (sempre ultimate; conference un decimo di quel
  5%), giocatori nel restante 95% con common 75 / rare 18 / ultrarara 6 / ultimate 1 (se nessun giocatore ha quella
  versione si scende alla precedente). Proposte confermate: normali → common, ultra → ultrarara, l'album si completa
  con qualsiasi versione, nella pagina si vede la più preziosa. Riciclo: common 10, rare 25, ultrarara 50, ultimate 150.
  Grafica: common argento, rara oro pieno, ultrarara oro olografico (come prima), ultimate cornice iridescente che gira.
  Prova su 2.000 figurine: 71 / 19 / 5,2 / 0,6 % giocatori, 4,2 % stemmi e conference.
* **Richiesta:** «Vorrei fare varie rarità: common, rare, ultrarare, ultimate.» Rarità delle **figurine**, non delle
  bustine: la bustina resta una sola.
* **Oggi** (`album_compra_bustina`): per ogni figurina 2% ultrarara, 10% stemma, il resto giocatore normale; il giocatore
  si estrae con un peso che favorisce gli overall alti; le figurine delle conference escono solo ultrarare.
  `album_possesso` tiene due contatori per figurina, `normali` e `ultra`.
* **Decisioni:**
  * stesso giocatore in **più versioni**, ognuna con la sua grafica; **quali versioni esistono dipende dall'overall**:
    common per tutti, **rare da 70**, **ultrarara da 78**, **ultimate da 83** (Serie F: 576 / 209 / 36 giocatori su 672;
    LegaBot: 147 / 63 / 14 su 462). «Un giocatore con overall 70 non può avere la ultimate»;
  * probabilità per figurina: **common 75%, rare 18%, ultrarara 6%, ultimate 1%**. Prima si estrae la rarità, poi il
    giocatore fra quelli che hanno quella versione;
  * **stemmi e conference solo ultimate**, ed escono **dentro l'1% delle ultimate** (non più il 10% di oggi per gli stemmi).
* **Proposte (da confermare):**
  * dentro l'1% delle ultimate: metà giocatori, metà stemmi (con le conference al 10% dove esistono);
  * le figurine già possedute: `normali` → common, `ultra` → ultrarara;
  * l'album si completa con qualsiasi versione; le versioni rare si vedono nella pagina del giocatore (come oggi l'ultra);
  * l'inno (voce 7) resta una quarta carta a parte, fuori da queste probabilità.
* **Avviso dato al committente sugli stemmi:** finora in Serie F sono uscite circa 3.400 figurine (≈ 1.100 bustine,
  tutto il gruppo). Con stemmi allo 0,5% per figurina ne sarebbero usciti circa 17 in tutto il gruppo, e un album di
  24 stemmi richiederebbe a un singolo migliaia di bustine. Da rivedere se l'album stemmi deve restare completabile.
* **Note tecniche:** `album_possesso` passa da due contatori a quattro (o a una riga per versione); scambi, doppioni,
  "mancano a" e bustine vanno adeguati alle versioni. Grafica delle carte: quattro cornici distinte in stile EA FC.

---

* **Solo dall'album della stagione nuova** (5/11/2026, richiesta del committente): rarità, card FUT e foto valgono
  dall'album successivo al lancio (`leagues.album_nuovo_dalla_stagione`: Serie F 3, LegaBot 6, leghe nuove 1).
  L'album in corso torna alla figurina e all'estrazione di prima. Le 13 rare e le 6 ultimate già uscite nell'album S2
  della Serie F sono state convertite: rara → normale, ultimate di giocatore → ultrarara, ultimate di stemma → normale.
  Migrazione `20261105230000_album_nuovo_dalla_stagione.sql`, che toglie anche un rallentamento (7,5 s a bustina).

## 9. Figurine: foto a mezzo busto

* **Stato:** `in lavoro` (5/11/2026): **foto scontornate da TheSportsDB** (dalla vita in su, trasparenti, stile card
  FUT), solo per le figurine. Per **tutti i 5.992 giocatori reali** del database (non solo quelli con la figurina oggi),
  prima quelli dell'album; accettate solo se coincide la data di nascita. Scarico con
  `tools/importazione/scarica_figurine.py`, caricamento in `player-photos/cutout/` con `carica_figurine.py`, colonna
  `players.foto_figurina`. Chi non ce l'ha (circa 10% dei reali, tutti i generati del vivaio) tiene il ritratto EA.
  Il busto disegnato con la maglia è stato scartato dal committente. Il CDN EA (sofifa) risponde 403.
* **Richiesta:** «Per ogni giocatore abbiamo solo la foto della faccia e sulle bustine non vengono un granché. Non si
  riuscirebbero a reperire almeno le foto a mezzo busto?»
* **Oggi:** le foto vengono dal CDN di sofifa (i ritratti ufficiali di EA FC, testa e spalle) e sono salvate a
  **160×160** (`tools/importazione/scarica_foto.py`), mentre la carta le mostra più grandi: una parte della resa scadente
  viene da lì. Il 27/10 il CDN risponde 403 alle nostre richieste.
* **Valutazione:** una fonte gratuita di foto a mezzo busto per tutti i 5.400 giocatori non esiste. Le foto vere sono di
  agenzie (Getty e simili, a pagamento), e i corpi interi di EA esistono solo per pochi campioni. Strade possibili:
  1. riscaricare i ritratti alla dimensione più grande disponibile (240 o più) e ridisegnare la carta attorno al ritratto
     in stile FUT (sfondo per rarità, ritratto grande che "esce" dalla cornice);
  2. busto disegnato con la maglia nei colori della squadra sotto il ritratto;
  3. immagini generate (già scartato una volta per lo stile anime).

## 10. Sponsor

* **Stato:** `in lavoro` (5/11/2026): database applicato (`20261105190000_sponsor.sql`, `..191000_sponsor_cron.sql`),
  app pronta in locale (Extra campo > Sponsor). Regole confermate: 3 offerte per colonna, un contratto attivo per
  colonna, offerte rinnovate a ogni giornata e dopo completamento/fallimento, rinuncia = 24 ore senza offerte, premi
  in crediti verificati solo su partite già viste. **Offerte costruite sulla squadra** (richiesta del committente):
  tifo attuale + 15 e solo sotto 85, classifica solo con spazio sopra (primo = "resta primo"), gol su media ultime 6,
  derby/trasferta/U21/capitano solo se possibili, premio × forza avversari (0,6-2,0) e trasferte. 14 tipi: vittoria,
  porta inviolata, segna X, Under 21 titolare, vittoria in trasferta, derby, gol del capitano, pubblicità occulta
  (tifo −1), testimonial (tifo −2); serie 3 su 5, imbattuto 5, gol fatti 6, gol subiti 6, bomber, sponsor di maglia
  (tifo +3), classifica, tifo. 67 aziende reali in 8 settori. Controllo automatico ogni 10 minuti (cron
  `sponsor-valuta`). Acceso con la Season 3.
* **Richiesta:** «Vorrei aggiungere gli sponsor. In "Extra campo" il menu "Sponsor": arrivano richieste di
  sponsorizzazione da aziende reali (scarichiamo i loghi). Servono a guadagnare crediti. Le richieste possono essere
  brevi o lunghe, per esempio: PUBBLICITÀ OCCULTA, cita il nostro sponsor nella prossima intervista (200 crediti), si
  ripercuote leggermente sull'ambiente dei tifosi; VITTORIE, vinci 3 delle prossime 5 partite (1000 crediti). Ne
  dobbiamo pensare varie. Gli utenti ne hanno varie tra cui scegliere, divise tra breve e lungo termine; se ne sceglie
  solo una per categoria finché non la completano; completata quella, si aggiornano. Tipo 3 per categoria.»
* **Note:** loghi da Simple Icons (SVG ufficiali monocolore, con il colore del marchio); le risposte alle conferenze
  sono testo libero, quindi "cita lo sponsor" si verifica cercando il nome nella risposta.

## 11. Richiesta del capitano (giorno libero) e richieste ignorate

* **Stato:** `in lavoro` (5/11/2026): migrazione `20261105220000_richiesta_capitano_e_silenzio.sql`, funzione
  `conferenza-stampa` e `RichiesteGiocatori.tsx` pronti. Provato in transazione annullata su Serie F.
* **Richiesta:** «Vorrei richieste anche da parte del capitano, che ad esempio può chiedere un giorno libero dagli
  allenamenti per la squadra. Questo si traduce con un −8% di forma fisica per tutti se accettato, un + nel morale. Se
  rifiutato la forma fisica rimane uguale ma scende il morale di squadra.» E: «alcuni, per evitare richieste insidiose
  dei loro giocatori, semplicemente evitano di rispondere».
* **Decisioni (committente, 5/11/2026):**
  * Risposta a testo libero valutata dall'AI, come le altre richieste. Concesso: condizione −8 punti e morale +4 a tutta
    la rosa; negato: morale −4 a tutti. Il voto alle parole (da −3 a +1,5) si somma, arrotondato. Esclusi ritirati e
    giocatori in prestito.
  * Richiesta ignorata (scaduta senza risposta): vale come un rifiuto secco (voto −1,5) e il giocatore si sfoga su
    SocialOne. Per il capitano: −4 −1,5 → −6 di morale a tutta la rosa. Prima "scadeva senza effetti" (in Serie F 20
    richieste su 70 lasciate scadere).
  * Frequenza ("2-3 volte a stagione, non di più"): solo dopo una vittoria, con probabilità 8 / giornate (Serie F
    36%), al massimo 3 a stagione e a 6 giornate di distanza, mai nei playoff; serve un capitano disponibile. In
    simulazione: squadra media 2 a stagione, chi vince spesso 2-3, chi vince poco 1-2. Non
    conta nel tetto di 7 richieste personali e può cadere sulla stessa giornata di una di esse.

## 12. Contratti pluriennali con opzione +1 (squadra o giocatore)

* **Stato:** `pronto` (6/11/2026): migrazione `20261106010000_contratti_pluriennali.sql` provata in transazione
  annullata su Serie F (prezzi, tetto su ogni stagione, opzioni, svincolo a metà, morale basso), app pronta in locale
  (scheda giocatore: durata, opzione, decisione dell'opzione squadra; rosa; guida). Si accende da sola quando la Serie F
  passa alla stagione 3. Promemoria opzioni ogni giorno alle 12 con al massimo 3 partite da giocare (cron
  `promemoria-opzioni`). Squadre del computer: restano su rinnovi di un anno.
* **Taratura (6/11/2026):** sui 472 contratti della Serie F in scadenza a fine S3 il premio dei giovani era troppo
  debole (il morale alto, che ha l'83% dei giocatori, lo annullava): portato a +5% a stagione +1% per ogni punto di
  margine oltre i 3, al massimo +15%. Moltiplicatore medio per 3 stagioni: under 23 con 10+ punti di margine 1,25 (max
  1,40), altri under 23 1,08, 24-29 anni 0,98, 30-31 0,88, 32+ 0,79. 20 giocatori sotto 30 di morale firmerebbero solo
  per un anno.
* **Decisioni (committente, 6/11/2026):**
  * Numeri della proposta come base, da misurare simulando i rinnovi della Serie F prima di accendere.
  * Svincolo di un contratto lungo: l'ingaggio pesa per intero sul tetto fino a fine della stagione in corso, poi a
    metà in ognuna delle stagioni rimaste (oggi pesa per intero fino a scadenza, che però è al massimo fine stagione).
  * Opzione squadra non decisa entro fine stagione = **rifiutata**: il giocatore va svincolato.
* **Richiesta:** «Vorrei anche che dalla prossima season si possano trattare contratti per più stagioni e come in nba
  inserire anche la clausola del +1 (a scelta della squadra o a scelta del giocatore). Ovviamente dobbiamo bilanciare.
  Nel senso che un giocatore che ha del potenziale, dovrà considerare che ha appunto del potenziale e quindi se gli si
  propone un ingaggio a lungo termine, magari chiede di più. Il contrario per un giocatore avanti con l'età. Poi
  dipenderà anche dal morale di quel giocatore. Il massimo di lunghezza del contratto direi 3 fissi col + 1. Non di più.»
* **Cosa cambia rispetto a oggi:** `docs/decisioni-economia.md` §2 fissa i contratti a 1 anno (`offri_rinnovo` rifiuta
  `p_durata <> 1`, `rinnovo_proposta` restituisce sempre durata 1). Il tetto resta fisso e uguale per tutti, quindi il
  controllo resta esatto: si ripete `verifica_capienza` per ogni stagione coperta dal contratto. Va aggiornata la §2
  di decisioni-economia (gerarchia: quel file vince sul design doc).
* **Dati disponibili:** `players.potential` (già usato da `private.valore_proiettato` per gli scambi), eta e overall
  correnti, `player_instances.morale`, mentalità bandiera/economia. Oggi in Serie F 180 contratti scadono a fine S2 e
  472 a fine S3.
* **Proposta (da confermare):** durata 1-3 + opzione facoltativa; ingaggio fisso per tutta la durata; per ogni anno
  oltre il primo il giocatore chiede di più se giovane con margine di crescita, di meno se over 30; il morale alto fa
  sconto, il morale basso fa chiedere di più (sotto 30 solo un anno); opzione squadra +8%, opzione giocatore −5%; si
  rinnova solo nell'ultima stagione del contratto; opzione squadra decisa dall'allenatore entro fine stagione, opzione
  giocatore decisa in automatico (rinuncia se ora vale più del contratto o se è scontento).

<!-- Nuove richieste qui sotto: "## N. Titolo", poi Stato, Richiesta (parole del committente), Decisioni, Note. -->

## 13. Espansione a 28 squadre (conference da 14): playoff

* **Stato:** `deciso` (7/11/2026), solo come regola. L'espansione non è ancora programmata: si implementa quando
  arrivano le 4 squadre nuove.
* **Regular season:** 13 avversarie × 2 = **26 giornate** (oggi 22); playoff invariati in 7 serate, in tutto 33.
* **Scelta del committente: OPZIONE A**, tabelloni invariati:
  * **Champions** 1ª-6ª di ogni conference e **Draft Playoffs** 9ª-14ª, stesso formato B di oggi
    (`docs/decisioni-conferenze.md`), con il Draft Playoffs spostato di due posizioni: 14ª e 13ª dirette ai quarti,
    play-in 12E–9W, 11E–10W, 12W–9E, 11W–10E.
  * **7ª e 8ª** di ogni conference: stagione finita, niente playoff.
* **Ordine delle scelte (28):** 1ª-12ª Draft Playoffs come oggi; **13ª-16ª le quattro escluse (7ª-8ª), per classifica:
  peggiore prima** (stessi criteri della classifica, confrontando le due conference); 17ª-28ª Champions come oggi
  (17ª-20ª eliminate nel play-in, ..., 27ª finalista, 28ª campione).
* **Scartate:** B (tabelloni da 7 con un solo bye: svaluta il 2° posto); C (Europa League a 4 per la 7ª e l'8ª):
  eventualmente da aggiungere in seguito sopra la A.
* **Da toccare quando si fa:** `crea_tabelloni_conferenze` (posizioni del Draft), `assegna_posizioni_playoff` /
  ordine delle scelte (le 4 escluse), legenda della classifica (zona neutra 7-8), `giornate_totali`, calendario a 14.

## 14. Rinnovi: chi cala chiede meno (contro l'inflazione degli ingaggi)

* **Stato:** `proposta` (8/11/2026), da rivalutare a inizio off-season 3 guardando quante squadre restano incastrate
  sotto il tetto dopo le scadenze. Il tetto (80 M€) resta com'è: alzarlo aiuterebbe solo chi lo riempie già.
* **Richiesta:** il committente è al limite del tetto e chiedeva se fosse il momento di alzarlo.
* **Fotografia (8/11/2026, Serie F, monte S3):** 4 squadre sotto 2 M€ di margine (Fel Lazio 80,0, Detroit 79,1,
  Coccialand 78,8, Mafiester 78,3), 5 fra 3 e 7 M€, 12 fra 9 e 18 M€, 7 con 20 M€ o più (Barbers 46,5). Media ~66 M€.
  A fine S3 si liberano molti contratti (Mafiester 38,2 M€, Coccialand 31,8, Cocciaspigola 17,7).
* **Il problema:** `private.rinnovo_proposta` chiede `greatest(500k, ingaggio attuale, teorico × fattore)`, quindi un
  rinnovo non abbassa mai l'ingaggio. I giovani che crescono chiedono di più, i veterani che calano tengono lo stipendio
  di quando erano al massimo: il monte della lega può solo salire. Dall'8/11 i veterani calano davvero (residuo al
  tetto del potenziale, `20261108170000`), quindi il divario fra quanto valgono e quanto prendono crescerà.
* **Proposta:** al rinnovo si chiede quanto si vale oggi, anche meno di prima, con un pavimento (es. 80% dell'ingaggio
  attuale) per evitare crolli di colpo. Da toccare: `rinnovo_proposta` (e quindi `proposta_rinnovo`, `offri_rinnovo`,
  i rinnovi delle squadre PC), testo di Aiuto sui rinnovi, §2 di decisioni-economia.
