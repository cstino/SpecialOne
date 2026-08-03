# Decisioni Fase 1

Risposte alle domande sollevate prima di iniziare l'implementazione.
Questo file è **vincolante** quanto `CLAUDE.md`. Se una decisione qui contraddice
`docs/design.md`, vince questo file (è più recente).

---

## 1. La formazione la decide l'utente. Modifica al motore approvata.

**Decisione: opzione B.** Aggiungi `opt.lineupCasa` / `opt.lineupOspite`. Se presenti,
`simulaPartita` li usa e non chiama `schiera()`. Se assenti, comportamento invariato.

L'analisi è corretta: così com'è il motore vanifica la scelta tattica, che è metà del gioco.
Era un buco della specifica, non una scelta.

### Vincoli sull'implementazione

- L'oggetto passato deve avere **esattamente la forma restituita da `schiera()`**:
  `{ modulo, slots, titolari, panchina, cambiFatti: 0 }`, con `titolari` allineato
  posizionalmente a `slots`.
- `sostituzioni()` **muta** `lineup.titolari` e `lineup.panchina`. Costruisci un oggetto
  fresco per ogni partita. Non riusare lo stesso lineup tra due partite e non passare
  riferimenti a strutture che ti servono ancora dopo.
- `schiera()` **resta** e resta esportata: è esattamente l'algoritmo del fallback delle 23:00
  descritto in design §6.7 ("massimizza la somma di OVR_eff"). Non duplicarlo.
- Dopo la modifica, protocollo di regressione completo. Il diff deve restare a zero:
  la suite non passa mai `opt.lineup*`, quindi percorre il ramo di default.

### Validazione della formazione: lato API, mai lato motore

Il motore si fida del suo input. La verifica sta nell'endpoint che salva la formazione,
e deve rifiutare:

- giocatore non appartenente alla rosa di quella squadra
- giocatore infortunato (in Fase 1 non applicabile, ma il controllo va scritto adesso)
- stesso giocatore in due slot
- numero di titolari diverso da 11
- zero portieri fra i titolari (uno di movimento in porta è **legittimo** — design §6.2 —
  ma dev'essere una scelta esplicita, non il risultato di un form incompleto)
- più di 9 in panchina

Rifiuta con un errore leggibile. Non correggere silenziosamente.

### Conseguenza sullo schema

`lineups` deve memorizzare l'assegnazione **slot per slot**, non un insieme di giocatori:
serve l'indice dello slot per ricostruire `titolari[]` allineato a `slots[]`. Un array
ordinato di `player_instance_id` di lunghezza 11 è sufficiente e più semplice di un JSON
con chiavi.

---

## 2. Familiarità moduli: attiva in Fase 1, con `formation_xp` persistita.

Il design doc la colloca in Fase 2. **Correzione: sale in Fase 1.**

Il rilievo è corretto e il doc era sbagliato: il motore applica `familiarita()`
incondizionatamente, quindi con `esperienzaModulo` vuoto ogni squadra prende −3,5 punti
di overall per sempre. Non è disattivata, è attiva al massimo malus.

Delle due opzioni, **persisti `formation_xp`**. Precaricare l'esperienza a 15 significa
iniettare dati falsi nel motore per neutralizzare un comportamento — è il genere di hack che
sopravvive fino alla Fase 2 e poi nessuno ricorda perché c'è. Persistere costa un contatore
e una riga di UPDATE dopo ogni partita, e il motore già mantiene la mappa da solo.

Non implementare il decadimento del 10% a stagione (design §6.5): serve solo dalla stagione 2,
che è Fase 3.

---

## 3. Dataset: importato. Foto: scaricate e ospitate, mai in hotlink.

È stato importato lo snapshot Kaggle `rovnez/fc-26-fifa-26-player-data`, derivato da
SoFIFA e dichiarato CC BY 4.0: 5.416 giocatori, 192 club, 10 campionati. Fonte, hash e
conteggi sono in `docs/dataset-fc26.md`; la pipeline ripetibile è in `tools/importazione/`.

È materiale in zona grigia dal punto di vista della licenza. Per un gioco privato tra
8 persone senza monetizzazione il rischio è nullo, ma **non va reso pubblico né indicizzabile**.
Nessuna pagina del dataset accessibile senza autenticazione.

**Foto: mai hotlink.** Script one-off separato dall'app che scarica, ridimensiona a 160×160
webp e carica su Supabase Storage. ~6.000 immagini, ordine di grandezza 60-100 MB, dentro
il piano gratuito. L'app deve degradare senza errori quando `foto_url` è null: un placeholder
con le iniziali va benissimo, e in Fase 1 va bene partire direttamente senza foto.

Le foto restano opzionali e non sono ancora state caricate. Il bucket privato e lo script
WebP separato sono pronti; l'app deve comunque funzionare con `foto_url = null`.

---

## 4. Adapter: confermato. Ma deve fallire rumorosamente.

Gestisci tutto nell'adapter DB → motore. Il motore non si tocca.

Il rilievo su `undefined <= 0` è quello che più mi preoccupa di tutta la lista: produce
un undici vuoto **senza sollevare nessun errore**, e si manifesta come "la partita è finita
0-0 e le statistiche sono vuote" tre settimane dopo.

Contromisura obbligatoria: una funzione `adattaGiocatore()` che **lancia un'eccezione**
se manca uno dei campi richiesti, citando l'id del giocatore. Meglio un cron che fallisce
e ti manda una notifica che una stagione di partite silenziosamente sbagliate.

Campi che l'adapter deve garantire su ogni oggetto giocatore:

```
id, nome, posizioni[], ovr, eta, stamina,
finishing, short_passing, tackle, dribbling, gk,
condizione (100 in Fase 1), infortunatoFinoA (0 in Fase 1)
```

La mappatura dei nomi (`standing_tackle` → `tackle` e simili) sta **solo** nell'adapter,
in un unico oggetto di mapping. Non sparpagliarla nelle query.

---

## 5. Seed: approvato, e va salvato in `matches`.

La proposta è giusta. Aggiungo un requisito: il seed usato va **scritto nella riga della
partita**, non solo derivato al volo. Il valore vero non è la determinismo in sé, è poter
ri-simulare una partita identica quando qualcuno contesterà un risultato — e succederà.

- Deriva il seed da `fixture_id` (più `season_id` se gli id non sono globalmente unici)
- Chiama `setSeed(seed)` prima di ogni partita
- Salva `seed` nella riga di `matches`

**Vincolo: simula le partite in sequenza, mai in parallelo.** `_seed` in `random.js` è
una variabile a livello di modulo: due simulazioni concorrenti si corromperebbero a vicenda.
Con 4-5 partite per giornata il costo è irrilevante. Se un giorno servisse il parallelismo,
la soluzione è rendere l'RNG istanziabile — ma è una modifica al motore, quindi protocollo
di regressione.

Nota tecnica: l'LCG in `random.js` è debole dal punto di vista statistico. Per questo uso
va benissimo. Il seed deve essere un intero positivo minore di 2³².

---

## 6. Sui documenti disallineati

Segnalazione corretta: `docs/motore-validazione.md` conteneva i numeri di un run intermedio
(`SENSIBILITA_FORZA = 0.080`) mentre la baseline è stata generata con `0.090`.
**Il documento è stato corretto.** Riscarica `docs/motore-validazione.md`.

La regola resta quella dichiarata: in caso di discrepanza **vince
`docs/risultati-fase0.txt`**, che è riproducibile byte per byte.

---

## 7. Una giornata per turno. `P` diventa la durata della stagione.

**Decisione: si simula una sola giornata per notte**, non due. Il design doc §9.1 e
`CLAUDE.md` §1 dicevano 2 e **sono stati corretti**.

Motivo: una formazione per turno *è* una formazione per giornata, quindi l'ambiguità su
come chiavare `lineups` sparisce invece di essere risolta con una convenzione.

### Conseguenza: `lineups` ha chiave `(team, giornata)`

Nessuna riga "per notte", nessun campo che dica a quale delle due partite si riferisce
la formazione.

### Conseguenza: l'admin sceglie la durata reale senza saperlo

Con una giornata per turno, `P = (N − 1) × G` è il numero di partite per squadra.
La durata in giorni è `D = (N − 1 + N mod 2) × G`: coincide con `P` per N pari,
mentre con N dispari è `N × G` perché il metodo del cerchio aggiunge un riposo.
Le combinazioni ammesse da §3.1 vanno da 6 giorni (N=4, G=2) a **114 giorni**
(N=19 o 20, G=6).

Chi crea la lega crede di scegliere il formato del campionato e sta scegliendo il mese
in cui finisce. Quindi la schermata di creazione lega **deve** mostrare in tempo reale,
mentre l'admin muove i selettori, il numero di giornate e la data di fine stagione,
calcolata in `Europe/Rome`. È un requisito di Fase 1.

Un avviso morbido sopra le ~40 giornate è consigliato, non obbligatorio. Nessun blocco.

### I default NON cambiano

`N = 8`, `G = 4` restano quelli di §3.1. Erano un esempio, non la configurazione: il
formato è scelto dall'admin partita per partita e nessuna combinazione va privilegiata
nel codice.

### Nessuna configurazione rompe l'equilibrio

Misurato su 200 stagioni per cella, spread di forza 79→84 distribuito su N squadre,
`usaCondizione: false`:

| N | G | P = partite per squadra | % titolo alla più forte | (caso puro) | % titolo alla metà debole |
|---|---|---|---|---|---|
| 6 | 2 | 10 | 45,5% | 16,7% | 13,0% |
| 8 | 2 | 14 | 36,5% | 12,5% | 13,0% |
| 8 | 4 | 28 | 38,5% | 12,5% | 6,0% |
| 10 | 4 | 36 | 44,0% | 10,0% | 3,5% |
| 12 | 4 | 44 | 30,0% | 8,3% | 3,5% |

La squadra più forte vince sempre fra 2,7 e 4 volte più spesso del puro caso, dal formato
più corto al più lungo. Nessuna combinazione degenera. Cambia solo quanto la stagione
perdona: sotto le ~15 giornate la metà debole vince il titolo il 13% delle volte, sopra
le 30 scende al 3,5%.

> ⚠️ **I target di Fase 0 valgono per una stagione da 28 partite.** Con 14 partite i punti
> del vincitore scendono a ~30 e lo spread a ~21, fuori dai target 58–68 e 35–50. **Non è
> una regressione del motore**: è una stagione più corta. La suite di regressione continua
> a girare a N=8, G=4 e non va toccata.

### Nota sulla familiarità

`FAM_PARTITE_PIENA = 15`. Nelle configurazioni sotto le 15 giornate il malus di familiarità
non si azzera mai: restando sullo stesso modulo tutta la stagione si finisce con un residuo
di −0,23 punti di overall a 14 giornate. Trascurabile, nessuna azione. Segnalato perché
è il genere di numero che sembra un bug quando lo si incontra nell'UI.

---

## 8. Draft a pacchetti al posto dello spin-club. Rosa fissa a 24.

**Decisione: il draft non estrae più un club.** Estrae **4 carte, una per macro-ruolo**
(GK/DEF/MID/ATT) da tutto il pool delle leghe attive, non da un club. Il giocatore ne tiene
**2**; le altre 2 restano semplicemente non-draftate — nessuno stato di "scarto", nessuna
tabella nuova: `player_instances` nasce solo al pick (già vero prima di questa decisione),
quindi una carta non scelta è indistinguibile da una mai pescata.

### Motivo

Playtest reale: chi arriva prima al draft può svuotare un club specifico prima che un altro
partecipante lo estragga, che si è manifestato esattamente così ("ho estratto il Real Madrid
già svuotato dei migliori"). Il problema non è l'ordine di turno in sé, è che lo spin-club
concentra lo scarso in poche decine di nomi per club: chi arriva prima su quel club specifico
vince. Pescando per ruolo da tutto il pool quel bersaglio specifico sparisce.

### Il vantaggio di velocità è stato misurato, non assunto — e la prima stima era sbagliata

Prima ipotesi (sbagliata): "pescare dal pool intero non cambia il principio, chi pesca prima
ha comunque un vantaggio". Misurato con una simulazione in scratchpad (pool di quality ~N(67,7)
per ruolo, dimensioni proporzionate al dataset reale, 800 prove):

| Configurazione | Scarto overall 1ª−ultima squadra, senza turno | Con turno a serpentina |
|---|---|---|
| 10 campionati, 8 squadre (tipico) | 0,22 | 0,16 |
| 2 campionati, 8 squadre | 0,92 | 0,16 |
| 2 campionati, 16 squadre | 2,60 | −0,02 |
| 1 campionato, 20 squadre | pool esaurito a metà draft | — |

Nella configurazione tipica lo scarto è rumore statistico: **non serve un vincolo di turno**.
Il problema torna solo con pochi campionati attivi e molte squadre (scarto 2,60, più del bonus
casa del motore). Decisione: **niente vincolo di turno per ora**, backlog a bassa priorità da
riaprire solo se qualcuno gioca davvero in quella configurazione estrema. Il caso limite di
pool esaurito va gestito con un errore leggibile (come "nessun giocatore ingaggiabile nel pool
attivo" già esistente), non è mai stato un problema pratico.

### Meccanica esatta

- Pacchetto giocabile = **almeno 2 carte su 4 ingaggiabili** (design §4.4, stessa formula di
  solvibilità di prima, senza il termine `portieri_minimi` che è sempre 0).
- Sotto soglia: le carte già ingaggiabili restano ferme, **solo le altre** vengono ripescate
  automaticamente — stile slot machine, i rulli buoni si fermano — finché il pacchetto non è
  giocabile. Non consuma reroll: è un'azione di sistema, non una scelta (stesso principio dello
  spin-a-vuoto sul club, design §4.4).
- Il reroll manuale resta, stessa granularità di prima: brucia **l'intero** pacchetto mostrato
  (anche le carte ingaggiabili) e ne apre uno nuovo.
- `draft_picks.club_estratto` ora contiene il **macro-ruolo** della carta (GK/DEF/MID/ATT), non
  più un nome di club. Il nome della colonna resta per non rompere lo storico.

### Rosa fissata a 24, non più configurabile

12 pacchetti da 2 tenute = 24, zero resto. Prima l'admin poteva scegliere 21-30: con 2 tenute a
pacchetto un obiettivo dispari lascerebbe un ultimo pick spaiato. Si è scelto di fissare il
numero piuttosto che complicare l'ultimo pacchetto con una regola speciale. Il tetto permanente
di stagione (21–30, `private.rosa_minima()`/`rosa_massima()`, usato da mercato e aste) **non
cambia**: riguarda la rosa dopo il draft, non l'obiettivo del draft stesso.

### Stesso meccanismo per il draft iniziale e per gli ingressi in off-season

`draft_team_state` e il trio di RPC (rinominate `draft_apri_pacchetto` / `draft_pacchetto_reroll`
/ `draft_scegli_pacchetto`) servivano già a entrambi i flussi prima di questa decisione — l'utente
ha scelto di mantenerli unificati per coerenza col resto del sistema di gioco, invece di forkare
un'infrastruttura a parte solo per il draft iniziale.

### Verificato

Migrazione `20260803120000_draft_pacchetti.sql`, testata con script transazionali
`begin; … rollback;` contro il database remoto (metodo già in uso nel progetto, vedi
`docs/STATO-PROGETTO.md`): apertura pacchetto, reroll, scelta di 2 carte, scarti non
istanziati, completamento di tutti i 12 pacchetti con transizione a "concluso", lega che resta
in `draft` finché non finiscono tutte le squadre, soglia di sostenibilità con ripescaggio
forzato, funzioni vecchie (`draft_spin`/`draft_reroll`/`draft_pick`) rimosse, percorso di
ingresso off-season verificato a parte. **Non ancora applicata al database remoto**: le
migrazioni restano da eseguire con `db push` quando si deciderà di procedere.

---

## Ordine di lavoro confermato

Schema Supabase + migrazioni + RLS per primo, con la forma di `lineups` decisa al punto 1.

Poi, un task alla volta:

1. **Schema + RLS** ← si parte da qui
2. Import dataset FC 26 (+ script foto separato)
3. Auth, creazione lega, codice invito, registrazione squadra
4. Draft
5. Schieramento formazione (con la modifica al motore del punto 1)
6. Calendario, cron, pagina partita
7. Classifica

Sulle policy RLS, il requisito da tenere presente mentre disegni le tabelle: i partecipanti
sono amici e hanno tutto l'interesse a leggere le formazioni altrui prima della simulazione.
Non è una minaccia teorica.
