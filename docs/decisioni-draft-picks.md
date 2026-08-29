# Decisioni — Playoff a doppio tabellone e mercato a scelte scambiabili

Deciso il 27 agosto 2026, in conversazione con l'utente, come evoluzione dei playoff
economici di `design.md` §10.7 (26 agosto) — che questo file **sostituisce nella parte
relativa alla composizione dei gruppi, al seeding e ai premi**, lasciando invariato tutto
il resto (formato andata/ritorno, supplementari, rigori: vedi §1 sotto).

Questo file è **vincolante** quanto `docs/decisioni-economia.md`. Dove contraddice
`docs/design.md` §10.7, vince questo file: è più recente.

**Stato: approvato, non ancora implementato. Restano punti aperti — vedi §6.**

---

## 0. Perché

Il playout economico (§10.7) risolveva il problema delle squadre di bassa classifica senza
cassa, ma restava un premio in denaro in un'economia che sta migrando a tetto salariale
(`decisioni-economia.md`), dove il denaro non è più la posta in gioco. L'utente ha deciso di
sostituire il premio economico con qualcosa che ha senso sotto un tetto fisso: **l'ordine di
scelta nel nuovo mercato a scelte**, sul modello NBA (chi va peggio in campionato ha più
chance di scegliere bene, ma non per sorteggio: se lo gioca in un torneo vero).

Nello stesso momento, l'utente ha deciso di sostituire l'intero mercato giornaliero a buste
chiuse con un sistema di scelte periodiche scambiabili, sempre sul modello NBA.

---

## 1. Playoff a doppio tabellone

Sostituisce interamente §10.7 "Composizione dei gruppi" e "Premio di partecipazione /
premio economico". **Non tocca** il formato dei match (andata/ritorno, finale secca in
campo neutro, supplementari, rigori, risoluzione della parità): quella parte di §10.7 resta
valida parola per parola.

### 1.1 Composizione dei gruppi

Con **Real Fampionato a 14 squadre**:

- **Title Playoff** — prime **8** in classifica, sempre, indipendentemente da N (vedi §6).
  Si gioca per il titolo. Nessun premio economico: il vantaggio è il trofeo e l'albo d'oro
  (invariato da §10.7).
- **Draft Playoff** — tutte le altre N−8. Si gioca per l'ordine di scelta nel mercato della
  stagione successiva (vedi §3).

### 1.2 Seeding — diverso da §10.7

§10.7 usava lo stesso algoritmo di seeding incrociato (`private.ordine_tabellone`) per
entrambi i gruppi. Qui i due gruppi usano regole **diverse**:

**Title Playoff (8 squadre, nessun bye)**: seeding incrociato classico, invariato da §10.7 —
1ª-8ª, 2ª-7ª, 3ª-6ª, 4ª-5ª.

**Draft Playoff (6 squadre, 2 bye)**: **accoppiamento per posizioni adiacenti**, non
incrociato. Le teste di serie sono le due squadre col piazzamento peggiore (13ª e 14ª: la
peggiore assoluta ha il vantaggio maggiore, coerente con lo spirito del vecchio playout).

```
Primo turno:  9ª vs 10ª          11ª vs 12ª
Semifinali:   vinc.(9-10) vs 13ª  vinc.(11-12) vs 14ª
Finale:       vincenti delle due semifinali
```

Questo è **diverso** dall'algoritmo generico `private.ordine_tabellone` usato oggi (che per
6 squadre produrrebbe 9ª-12ª e 10ª-11ª, non 9ª-10ª e 11ª-12ª): serve una funzione di seeding
apposta per il Draft Playoff, non un riuso di quella esistente.

---

## 2. Ordine di scelta nel mercato — determinato dai playoff

Il piazzamento nei due tabelloni della stagione N determina l'ordine di scelta nei due
mercati (ON-Season e OFF-Season, vedi §3) della stagione **N+1**. Le prime scelte (le
migliori) vengono dal Draft Playoff; le ultime (le peggiori) dal Title Playoff — il
campione assoluto della lega sceglie per ultimo.

| Scelta | Chi la ottiene |
|---|---|
| 1ª | Campione Draft Playoff |
| 2ª | Finalista Draft Playoff (perso la finale) |
| 3ª | Perdente di semifinale, lato del campione |
| 4ª | Perdente di semifinale, lato del finalista |
| 5ª-6ª | Eliminati al 1° turno del Draft Playoff (9-10 e 11-12) |
| 7ª-10ª | Eliminati ai quarti del Title Playoff |
| 11ª-12ª | Perdenti di semifinale del Title Playoff |
| 13ª | Finalista Title Playoff |
| 14ª | Campione Title Playoff (ultima scelta) |

**Parità fra squadre eliminate nello stesso turno** (i due eliminati al 1° turno del Draft
Playoff; i quattro eliminati ai quarti del Title Playoff): si spezza con la classifica della
stagione regolare appena conclusa — la peggio piazzata delle due (o quattro) sceglie prima.

**Il campione del Draft Playoff della stagione N ottiene la 1ª scelta di *entrambi* i
mercati (ON-Season e OFF-Season) della stagione N+1** — non solo di uno dei due.

### 2.1 Transizione dalla stagione 1 (nessun playoff pregresso)

Real Fampionato entra nella stagione 2 senza playoff a monte: l'ordine di scelta per i primi
due mercati (ON-Season 2 e OFF-Season 2) si stabilisce così, una tantum:

1. **Prime 6 scelte**: alle 6 squadre entrate in stagione 2, ordinate per **spesa crescente**
   nel loro draft iniziale (chi ha speso meno sceglie prima).
2. **Scelte 7-14**: alle 8 squadre originali, in **ordine inverso di classifica** — l'8ª
   (peggiore delle originali) sceglie 7ª assoluta, la 1ª (Regginho FC) sceglie 14ª (ultima).

Verificato sui dati reali di Real Fampionato al momento della decisione: 6 squadre entrate
(Giampiero, Fonald Fump, Futuro Nazionale, Es. Atletico Bar Sport, FC Rocazz, Cocciaspigola)
+ 8 originali (Regginho FC 1ª, McDon's 2ª, Fel Lazio 3ª, Team AS Turbo 4ª, Lou Po FC 5ª,
Coccialand 6ª, God damn spring 7ª, Ciuf Ciuf Diouf 8ª) = 14.

---

## 3. Mercato a scelte scambiabili (stile NBA)

Sostituisce il mercato giornaliero a buste chiuse per i giocatori di fascia alta. Il
mercato a buste chiuse **non sparisce**: resta come mercato di emergenza per la fascia
bassa (vedi §3.3).

### 3.1 Due finestre per stagione

- **ON-Season X** — l'estrazione avviene a metà della stagione X, dopo la giornata
  `⌊giornate_totali / 2⌋` (vedi §6).
- **OFF-Season X** — l'estrazione avviene **allo scadere dell'off-season che segue la
  stagione X**, cioè quella che porta alla stagione X+1. L'istante è esattamente
  `leagues.offseason_fine`.

> **Correzione del 28 agosto 2026.** La prima stesura diceva «l'off-season che porta
> *alla* stagione X», cioè prima della stagione X. È sbagliato, e si vede da due lati:
> una lega nuova comincia dalla stagione 1 con il draft iniziale, **non da un'off-season**,
> quindi un "OFF-Season 1" precedente alla stagione 1 non esisterebbe mai; e l'elenco di
> §3.2 (ON-Season 2, OFF-Season 2, ON-Season 3, …) è in ordine cronologico solo se OFF-X
> viene *dopo* ON-X.
>
> Le due finestre di una stagione stanno quindi entrambe dentro il ciclo di quella
> stagione: `ON-X` a metà del campionato, `OFF-X` alla fine, appena prima della X+1.

### 3.1 bis Quando si vede il pool e fino a quando si modificano le preferenze

*Precisato dall'utente il 28 agosto 2026.*

Il pool **non** si svela poco prima dell'estrazione: si svela **appena si chiude lo
stadio precedente**, e da quel momento le preferenze si possono già indicare. Il
tempo di riflessione è quindi lungo, non una finestra stretta a ridosso del sorteggio.

| Momento | Cosa succede |
|---|---|
| L'off-season finisce e comincia la stagione X | Si svela il pool di **ON-Season X**, preferenze aperte |
| Si risolve il draft ON-Season X | Si svela il pool di **OFF-Season X**, preferenze aperte |
| Si risolve il draft OFF-Season X | Il ciclo riprende con la stagione successiva |

**Le preferenze restano modificabili fino a un'ora prima dell'estrazione.**
Nell'ultima ora la lista è congelata: è la stessa logica delle buste chiuse, evita
il ritocco dell'ultimo secondo e dà alla risoluzione un input stabile.

Ne segue che ogni finestra ha bisogno di un **istante di estrazione noto in
anticipo**, non ricavato al volo quando il cron gira: serve sia per calcolare il
congelamento a −1h, sia per mostrare un conto alla rovescia onesto in interfaccia.
È registrato in `public.finestre_scelte`.

> Il pool resta **immobile** dal momento in cui si svela fino alla risoluzione
> (§6 bis). È proprio perché le preferenze si compilano con largo anticipo che il
> pool non può cambiare sotto ai piedi: è la ragione per cui il mercato di
> emergenza è stato limitato a overall ≤ 75.

### 3.2 Le scelte come asset scambiabile

Ogni squadra possiede una scelta per ciascuna delle due finestre, per le **4 stagioni
successive** a quella in corso — esattamente come i diritti di scelta al draft in NBA.

Per Real Fampionato, che sta per entrare in stagione 2: ogni squadra parte con le scelte
ON-Season 2, OFF-Season 2, ON-Season 3, OFF-Season 3, ON-Season 4, OFF-Season 4,
ON-Season 5, OFF-Season 5 — otto scelte totali.

Le scelte si scambiano fra squadre come qualsiasi altro asset di mercato (giocatori,
conguagli). Una scelta scambiata **conserva la propria identità di origine**: la squadra
che l'ha "guadagnata" con il proprio piazzamento resta quella che la determina (la sua
posizione nell'ordine dipende dal SUO risultato in campionato, non da quello di chi la
possiede ora). Vedi §5 per come questo si traduce in UI.

**Il pool di ogni finestra è limitato ai giocatori con overall > 75** (esattamente 75 esclude,
va nel mercato di emergenza — deciso il 27 agosto 2026).

### 3.3 Mercato di emergenza (quello di oggi)

Il mercato giornaliero a buste chiuse esistente resta attivo, ma **solo per i giocatori con
overall ≤ 75**. Nessun'altra modifica alle sue regole (orari, soglie, risoluzione): quelle
di `design.md` §9.4 restano valide.

---

## 4. Risoluzione asincrona di ogni finestra di mercato

Non è un draft dal vivo: ogni squadra sottomette in anticipo una lista di preferenze
ordinate, e il sistema risolve tutte le scelte in sequenza.

- La squadra con la scelta **N** (dove N va da 1 a 14, 1 = prima a scegliere) sottomette una
  lista di **al massimo N** giocatori preferiti, in ordine. Non è obbligata a riempirla
  tutta: può indicarne anche solo una, o nessuna.
- La risoluzione scorre le scelte **in ordine, dalla 1ª alla 14ª**: a ogni squadra si
  assegna la prima preferenza della sua lista **non ancora presa** da chi ha scelto prima.
- **Non esiste un ripiego automatico.** Se una squadra esaurisce tutta la lista senza che
  nessuna preferenza sia più disponibile quando tocca a lei, resta senza giocatore per
  quella finestra. È un rischio che la squadra si assume esplicitamente non allungando la
  lista: per essere sicura di ottenere qualcosa deve indicare tante preferenze quanto la
  propria posizione di scelta.

> **Punto aperto**: se una scelta viene scambiata, chi sottomette la lista di preferenze
> per quella scelta — la squadra che la possiede ora, ovviamente — ma la sua **posizione**
> nell'ordine (1-14) resta quella determinata dal piazzamento della squadra di origine.
> Questo è già implicito in §2/§3.2, lo esplicito qui per chiarezza in fase di
> implementazione.

---

## 5. UI — menu Draft

Nuova sezione "Draft" nell'app. Ogni scelta è visualizzata come un **ticket**, con:

- **Stemma della squadra di origine** — sempre quella, non cambia mai per uno scambio.
  Serve a ricordare da dove viene quel ticket anche dopo che ha cambiato proprietario più
  volte.
- **Etichetta stagione e finestra** (es. "OFF-Season 3").
- Implicitamente, la squadra **proprietaria attuale** — la sezione va mostrata dal punto di
  vista di "le scelte che possiedo ora", non "le scelte che ho generato".

Nel modello dati, ogni riga di "scelta" ha quindi **due riferimenti a squadra distinti e
indipendenti**: origine (fissa, determina la posizione 1-14) e proprietario (cambia con gli
scambi). Nessuno dei due deriva dall'altro.

---

## 6. Punti risolti il 27 agosto 2026

- **Soglia 8/6**: **8 è fisso**, indipendente da N. Il Title Playoff prende sempre le prime
  8 in classifica; il Draft Playoff prende tutte le altre (N−8), qualunque sia N. Non è più
  una frazione della lega come il vecchio playout: con N=20 il Draft Playoff avrebbe 12
  squadre, con N=10 solo 2. Sotto una certa N il Draft Playoff diventa troppo piccolo per
  avere senso (2 squadre = una partita secca, non un torneo) — soglia minima da fissare in
  implementazione con un criterio ragionevole (es. nessun Draft Playoff sotto le 4 squadre
  rimanenti, quelle picks assegnate direttamente per classifica), non è un nuovo punto
  aperto da chiedere: è una scelta di implementazione, non di design.
- **Timing ON-Season**: `⌊giornate_totali / 2⌋` — metà esatta arrotondata per difetto.
- **Confine 75 overall**: **>75 = mercato a scelte, ≤75 = mercato di emergenza**. Aggiornato
  anche il testo di §3.2 e §3.3 sopra.
- **Contratto da scelta**: ingaggio teorico fisso (`private.ingaggio_teorico` su overall ed
  età, la stessa formula già usata per aste e rinnovi), contratto di **1 stagione** come
  qualunque altro sotto `decisioni-economia.md` — nessuna trattativa, nessuna asta.

## 6 bis. Punti risolti il 28 agosto 2026

- **Leghe sotto soglia per il Draft Playoff** (es. LegaBot, 8 squadre: Title
  Playoff gioca comunque il tabellone completo su tutte e 8, il Draft Playoff
  resta vuoto — §6, "sotto una certa N"). L'ordine delle scelte segue comunque
  l'eliminazione nel **Title Playoff**, stessa logica di §2 estesa a tutte le
  posizioni: il campione sceglie per ultimo, chi esce prima nel tabellone
  sceglie prima. Non la classifica pura di fine campionato: il piazzamento nel
  tabellone resta quello che conta, anche quando non c'e' un Draft Playoff a
  fargli da contrappeso.

- **Composizione del pool**: non "tutti gli svincolati overall > 75", ma un'**estrazione
  dedicata** alla finestra, **10 giocatori per ruolo (GK/DEF/MID/ATT) = 40 totali**, stesso
  meccanismo dell'estrazione del mercato di emergenza (`private.estrai_svincolati_lega`) ma
  filtrato a overall > 75 e senza tornate giornaliere: un'estrazione sola per finestra, che
  resta la stessa finché la finestra non si risolve (altrimenti la lista di preferenze
  sottomessa non avrebbe senso: cambierebbe sotto ai piedi delle squadre).

## 7. Punti risolti il 28 agosto 2026 (seconda tornata)

- **Squadre PC**: partecipano con una logica automatica, non raffinata — stesso spirito
  delle altre decisioni prese per il bot. Per ogni scelta propria pronta in una finestra
  aperta, prendono i migliori overall disponibili nel pool fino alla propria posizione
  (`private.preferenze_squadre_pc`, richiamata dal cron ad ogni giro).
- **Scelta non ancora nata di una squadra rimossa**: si annulla. Se la squadra di origine
  viene rimossa dalla lega (`prepara_offseason`) e la sua scelta per una stagione futura è
  ancora `'futura'` (posizione non assegnata), la riga viene cancellata — non ha più senso
  senza una squadra che l'abbia guadagnata. Una scelta già `'determinata'` non viene
  toccata: è già un impegno reale della transizione in corso.
- **Regola Stepien in stile NBA**: non si può cedere la propria scelta d'origine (quella
  guadagnata col proprio piazzamento, non una acquisita per scambio) per due stagioni
  consecutive nella stessa finestra (ON o OFF). Controllata sia alla proposta
  (`proponi_scambio`) sia all'accettazione (`rispondi_a_proposta`, nel caso lo stato sia
  cambiato nel frattempo) — `private.viola_regola_stepien`. Riguarda solo le scelte ancora
  vive (`futura`/`determinata`): una già esercitata o andata a vuoto è storia.

## 8. Punti risolti il 29 agosto 2026 — bootstrap della stagione 1 e correzione OFF-Season

Emerso creando una nuova lega da zero: **ON-Season 1 e OFF-Season 1 non sono mai esistite**
per nessuna lega. `private.genera_scelte_draft` genera solo `stagione_corrente+1..+4`, quindi
la primissima stagione di una lega non riceve mai le proprie scelte — verificato sui dati
reali (LegaBot non ha nessuna riga `scelte_draft` con stagione=1). §2.1 copriva solo il caso
di una lega già esistente che migra al sistema (Real Fampionato, con un vero draft e una vera
classifica di stagione 1 alle spalle): non il caso di una lega che nasce già con questo
sistema attivo.

- **ON-Season 1**: nessun playoff precedente esiste. Si assegna dalla **spesa nel draft di
  creazione squadra, crescente** (chi ha speso meno sceglie prima), pareggio spezzato **a
  caso** — la stessa formula già usata da `private.assegna_posizioni_transizione` per le
  squadre "nuove" di una transizione, qui applicata a tutte le squadre della lega perché sono
  tutte nuove alla stagione 1. Assegnata subito, alla conclusione del draft di creazione,
  perché la spesa è già interamente nota a quel punto.
- **OFF-Season 1**: aspetta il playoff della stagione 1 stessa (Title/Draft Playoff), come
  qualunque altra OFF-Season a regime — vedi il punto successivo.

**Correzione alla regola a regime (§2)**: `private.assegna_posizioni_playoff` abbinava
finora ON-Season e OFF-Season della stessa stagione N+1, assegnandole **insieme** dal
piazzamento della stagione N. Ma OFF-Season N si risolve alla fine dell'off-season che segue
la stagione N — cioè quando il playoff di N è già concluso da un pezzo, e quindi è
un'informazione più recente di quella di N−1 che si stava usando. **Quando i playoff della
stagione N si concludono, si assegnano invece OFF-Season N (che aspettava proprio questo) e
ON-Season N+1** (che non ha ancora un playoff più recente a disposizione). Il calcolo del
piazzamento (vittorie nel tabellone, spareggio di classifica) non cambia: cambia solo quali
due righe riceve.

Sequenza completa per una lega nuova: ON-Season 1 = spesa draft · OFF-Season 1 = playoff
stagione 1 · ON-Season 2 = playoff stagione 1 · OFF-Season 2 = playoff stagione 2 · ON-Season
3 = playoff stagione 2 · e così via — ogni finestra usa il playoff più recente disponibile
nel momento in cui si risolve.

Vedi `supabase/migrations/20260829050000_bootstrap_scelte_stagione_1.sql`. Compatibilità con
le leghe in corso: dove una finestra è già stata assegnata dalla vecchia regola (es. OFF-Season
2 di LegaBot, già `determinata` dalla transizione di §2.1), la nuova `assegna_posizioni_playoff`
la lascia stare e assegna solo ciò che è ancora `futura` — nessun doppio assegnamento, nessun
errore.
