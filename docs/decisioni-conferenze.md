# Conferenze East / West e sorteggio in diretta (Serie F, 24 squadre)

Decisioni prese col committente il **5 ottobre 2026**. Valgono solo per le leghe con
`leagues.conferenze_attive = true` (oggi: da accendere per la Serie F quando tutto e' pronto).
Le altre leghe funzionano come prima.

## Regole decise

- **Squadre**: 24 (16 attuali + 8 nuove), due conferenze da 12: **Eastern Conference** e **Western Conference** (nome ufficiale dal 6 ottobre 2026; nelle schede strette «Eastern» e «Western»).
- **Regular season**: si gioca solo dentro la propria conferenza, 2 gironi (andata e ritorno):
  11 avversarie x 2 = **22 giornate** (prima 30). Le due conferenze giocano le stesse giornate.
- **Sorteggio a ogni stagione**, in diretta dopo la chiusura dell'off-season: **una squadra ogni
  20 secondi**, alternando East e West ("La prima squadra estratta per la Eastern Conference e'...")
  fino a 12 e 12. 24 estrazioni = 8 minuti. Il sorteggio parte nel momento in cui si chiude
  l'off-season, quindi l'orario lo decide chi chiude l'off-season (il committente la posticipa a mano).
- **Playoff a tre tabelloni da 8 squadre** (BLOCCO 2, NON ANCORA FATTO):
  - **Champions League** (ex Title Playoff): prime 4 di ogni conferenza. Loghi della Champions.
  - **Europa League**: dalla 5a all'8a di ogni conferenza. Usa sfondo, musica e grafica dell'attuale
    Draft Playoff (stile Europa League).
  - **Draft Playoffs** (nuovo): dalla 9a alla 12a di ogni conferenza. Asset ricevuti il 5 ottobre 2026 e
    gia' nel progetto (non ancora collegati, si collegano nel blocco 2): sfondo viola
    `public/sfondi-fase-verticali/draft_playoffs_nuovo_vert.webp` (941x1672) e canzone di 38 s
    `public/musica-fase/draftplayoffs_nuovo.m4a`. Nel blocco 2 i vecchi `draft_playoffs_*` e
    `draftplayoffs.mp3` diventano quelli dell'Europa League.
  - Quarti incrociati Est-Ovest: 1E-4W, 2E-3W, 1W-4E, 2W-3E. Andata e ritorno; finale secca in campo
    neutro. Stessa cosa per tutti e tre i tabelloni.
- **Ordine di scelta nel mercato a scelte** (BLOCCO 2): stessa idea del Draft Playoff di oggi
  (docs/decisioni-draft-picks.md): scelgono per primi quelli del Draft Playoffs, poi Europa League, poi
  Champions League, dentro ogni gruppo secondo il risultato del proprio tabellone.
- **Pool degli eleggibili al draft**: con 24 squadre sono **30** (6 portieri + 8 difensori + 8 centrocampisti +
  8 attaccanti), uno per ogni scelta piu' un margine; fino a 16 squadre restano 23 (migrazione
  20261005090000; il committente aveva pensato a 35 e poi ha preferito 30). La dimensione si fissa
  quando la finestra viene svelata.
- **Le 8 nuove squadre** (BLOCCO 3): costruiscono la rosa col mini-draft a pacchetti come sempre, con un
  budget del draft uguale per tutte e piu' alto: **48 M EUR** (il draft iniziale della Serie F era 40 M su
  tetto 80 M; i monti ingaggi attuali sono in media 53 M). Si imposta `leagues.budget_draft` all'apertura
  del loro draft. Il limite di squadre per lega e' stato portato da 20 a 24.

## Cosa e' implementato (migrazione 20261005050000)

- `leagues.conferenze_attive`; `leagues.giornate_totali` (colonna generata) tiene conto delle conferenze
  ((n_squadre/2 - 1 + parita') x n_gironi); `n_squadre` fino a 24; `fase_carriera` puo' essere `'sorteggio'`.
- `standings.conferenza` ('est'/'ovest'): la **posizione e' calcolata dentro la conferenza**
  (`registra_risultato_partita`, `partition by conferenza`; indice unico (stagione, conferenza, posizione)).
- `sorteggi_conferenze` e `sorteggio_estrazioni`: l'ordine lo decide il server all'inizio (casuale; posti
  dispari East, pari West). **Segreto**: ogni estrazione e' leggibile (RLS) solo dal momento della
  rivelazione (`private.sorteggio_rivelate`); nessuno puo' sapere in anticipo chi uscira'.
- `finalizza_offseason`: con le conferenze non crea il calendario; mette la lega in `'sorteggio'` e crea il
  sorteggio. `private.completa_sorteggi_scaduti` (cron ogni minuto) a sorteggio finito (+20 s) rimette la
  lega in `'normale'` e chiama `inizializza_stagione`, che ora genera il calendario per conferenza
  (stesso metodo del cerchio, stesse giornate) e le `standings` con la conferenza. Se qualcosa fallisce
  la lega resta in `'sorteggio'` e si riprova al giro dopo.
- App: `SorteggioConferenze.tsx` (diretta sincronizzata sull'orologio del server, roulette di suspense,
  carta della squadra estratta, due colonne 0/12), `ConferenceBadge.tsx` (segnaposto finche' non arrivano i
  loghi: metterli in `public/loghi-conferenza/east.png` e `west.png`), classifica con due schede East/West e
  zone 1-4 Champions / 5-8 Europa League / 9-12 Draft Playoffs.

## Cosa manca (in ordine)

1. **Accendere** `conferenze_attive` per la Serie F (e `n_squadre` = 24, numero pari di squadre attive)
   solo quando i nuovi sono entrati e hanno completato il draft, e prima di chiudere l'off-season.
2. **BLOCCO 2: tabelloni.** `private.crea_tabelloni`, `assegna_posizioni_playoff`, `ordine_draft_playoff` e il
   tipo di tabellone (`brackets.tipo`: oggi 'title'/'draft') vanno adattati a tre tabelloni con le posizioni
   per conferenza. **Va fatto entro la fine della regular season (22 giornate)**: `crea_tabelloni` oggi
   assumerebbe una classifica unica e produrrebbe tabelloni sbagliati.
3. Grafica e nomi: Champions League (loghi), Europa League, Draft Playoffs; loghi East/West (arrivati il 5 ottobre 2026: `public/loghi-conferenza/east.svg`, `west.svg` e le versioni `-emblema.svg` per gli spazi stretti, gia' in uso nel sorteggio e nella classifica); stelle e albo
   (il titolo diventa la Champions League).
4. Ingresso degli 8 nuovi e budget 48 M.

## Come provare senza toccare dati veri

Transazione annullata: accendere il flag, forzare `offseasons.scade_il` nel passato, chiamare
`private.finalizza_offseason(<lega>)`, anticipare `sorteggi_conferenze.avviato_il`, chiamare
`private.completa_sorteggi_scaduti()` e controllare calendario (solo dentro la conferenza) e posizioni.

## Loghi UEFA (5 ottobre 2026)

Scaricati da Wikimedia Commons (file SVG marcati "public domain, trademarked": sono marchi UEFA, usati
qui solo per il gioco privato fra amici). Gli originali sono scuri (blu notte e nero), quindi illeggibili
sul nostro sfondo: ne ho fatto versioni **chiare** (nero e blu diventano bianco-argento sfumato; l'arancione
dell'Europa League resta). In `public/loghi-fase/uefa/`:
`champions-league.png` (scritta + pallone a stelle), `champions-league-compatto.png`,
`champions-league-pallone.png` (solo pallone), `europa-league.png` (versione 2024), `europa-league-2021.png`,
`europa-league-classico.png`. Non ancora collegati: si usano nel blocco 2 (tre tabelloni).


## Draft OFF-Season e sorteggio in diretta, uno dopo l'altro (6 ottobre 2026)

Richiesta del committente: alla chiusura dell'off-season due dirette per tutti insieme, prima il
draft dei giocatori e poi il sorteggio delle conference, con un pulsante ciascuna (il secondo
compare a draft finito) e la possibilita' di uscire e rientrare.

- **Sequenza.** Alla scadenza (`finalizza_offseason`) le scelte OFF-Season si risolvono come sempre,
  subito, ma si **rivelano** una alla volta: **30 secondi a scelta, 15 di annuncio** («con la scelta
  n la squadra X seleziona…») **e 15 di reveal** del giocatore; in basso il recap delle scelte gia'
  rivelate. La diretta parte al minuto pieno successivo alla chiusura. Il **sorteggio parte 3 minuti
  dopo l'ultima scelta** (16 scelte = 8 minuti, poi 3 di pausa, poi 24 x 20 s = 8 minuti).
- **Prima giornata.** Con le conferenze e' alle 23:00 di almeno **20 ore** dopo la fine del sorteggio
  (`inizializza_stagione`): chi scopre la conference ha un giorno per schierarsi. Provato: finita la
  diretta alle 10:14, prima giornata il giorno dopo alle 23:00.
- **Cosa e' segreto.** `scelte_live_stato(lega)` restituisce il giocatore di una scelta solo da quando
  scatta il suo reveal (ora del server). Le **notifiche** ai proprietari partono alla rivelazione
  (`private.notifica_scelte_rivelate`, sul cron di `completa_sorteggi_scaduti`), non alla risoluzione.
  **Limite noto:** le rose cambiano alla chiusura, quindi chi guardasse la rosa di un'altra squadra
  durante gli 8 minuti potrebbe vedere in anticipo il giocatore. Non da' vantaggio competitivo, solo
  spoiler, e tutti stanno guardando la diretta.
- **Tabella** `scelte_live` (una riga per lega, stagione e finestra: avvio, passo, secondi di annuncio,
  totale, notificate). Nomi scelti per non scontrarsi col draft iniziale in diretta
  (`private.avanza_draft_live` esiste gia'). Alle leghe senza conferenze non cambia nulla.
- **App.** `OffseasonLive.tsx` (menu con i due pulsanti), `DraftScelteLive.tsx` (la diretta),
  `lib/useScelteLive.ts` (sincronizzazione con l'orologio del server); `SorteggioConferenze` ha il
  conto alla rovescia prima dell'avvio e il tasto Menu. Senza `scelte_live` la lega vede solo il sorteggio.
- **Scelte vuote.** Una scelta e' «vuota» se nella lista non c'e' nessun giocatore libero che entri nel
  tetto: la diretta lo dice («Nessuna scelta»). Nel test 5 scelte su 16 erano vuote.
- **Aperto:** gli 8 nuovi non hanno scelte in OFF-Season 1 e ON-Season 2 (16 scelte, una per squadra
  originale); da decidere se e dove ne hanno dall'ON-Season 2.

## Roulette del sorteggio (6 ottobre 2026)

Prima l'estratta restava in scena 8 secondi e la roulette girava per i 12 restanti, con stemmi a caricamento
pigro che lampeggiavano (andava a scatti). Ora: **l'estratta resta 14 secondi e la roulette gira solo gli
ultimi 6**, stemmi precaricati e caricati subito, ordine mescolato senza ripetizioni, rallentamento
progressivo (da un cambio ogni 80 ms fino a uno ogni 380 ms), anello del conto alla rovescia sui 6 secondi.
Il primo turno, che non ha un'estratta prima, mostra un punto interrogativo fermo finche' non iniziano i 6 secondi.

**Aggiornamento (6 ottobre 2026): niente roulette dei loghi.** Al posto della roulette c'e' un caricamento
disegnato: anelli concentrici che girano nel colore della conference che ricevera' la squadra (azzurro East,
arancio West), con un anello che si riempie negli ultimi 6 secondi, l'emblema della conference al centro e il
conto alla rovescia. Al termine la squadra si rivela con un'onda luminosa attorno allo stemma. Prima del
conto finale (primo turno) gli anelli girano piano e la scritta dice «Preparo l'estrazione».

**Primo turno del sorteggio (6 ottobre 2026).** Aspettava 20 secondi invece dei 6 del caricamento. Ora l'«avvio»
che si vede (conto alla rovescia, menu) e' quando comincia il caricamento della prima squadra, cioe' 14 secondi
dopo `sorteggi_conferenze.avviato_il` (`ANTICIPO_PRIMA_ESTRAZIONE` in `lib/conferenze.ts`): anche la prima
squadra aspetta 6 secondi. Nessun cambio nel database.

## «La vetta» in home con le conference (7 ottobre 2026)

Il recap della classifica in home mostra le **due conference** in due schede (East e Western) che **scorrono da sole**
ogni 5 secondi, si possono scorrere col dito o con i pallini, e si fermano per 8 secondi dopo un tocco (e a scheda
del browser nascosta o con «riduci movimento» attivo). Si parte dalla conference della propria squadra, segnata «La tua»;
se la propria squadra non e' fra le prime quattro compare sotto, dopo un «⋯». `VettaConferenze.tsx`. Senza conferenze «La vetta» resta com'era.
La pagina **Classifica** ha gia' le due schede East/Western e si apre su quella della propria squadra.
