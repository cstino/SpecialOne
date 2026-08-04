# Stato progetto e handoff

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

Ultimo aggiornamento: **4 agosto 2026**. Questo documento descrive lo stato reale del
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
