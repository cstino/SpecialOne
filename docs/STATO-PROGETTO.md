# Stato progetto e handoff

Ultimo aggiornamento: **2 agosto 2026**. Questo documento descrive lo stato reale del
repository ed è il punto di partenza per il prossimo agent (Claude o Codex).

## Prima di lavorare

1. Leggere `CLAUDE.md` (o `AGENTS.md`, sono lo stesso file) e `docs/decisioni-fase1.md`.
2. Per ogni modifica Supabase creare una nuova migrazione; non modificare migrazioni già applicate.
3. Il motore è validato. Se si modifica `engine/`, eseguire obbligatoriamente
   `node tools/validazione/simulate.js` e confrontare con `docs/risultati-fase0.txt`.
   Il confronto va fatto con `diff --strip-trailing-cr`: il file di baseline ha fine riga CRLF.
4. UI mobile-first, stato di gioco solo su Supabase, nessun `localStorage`.
5. La CLI Supabase non è installata globalmente: si usa `npx supabase@2.111.0 …`.
   Quasi tutti i comandi richiedono `--linked --experimental`.

## Stato Git

- Branch: `main`, allineato con `origin/main`
- Remote: `https://github.com/cstino/SpecialOne.git`
- Working tree pulita al momento di questo aggiornamento.

## Accesso al database dall'agent

Verificato funzionante e molto utile per diagnosi:

```bash
npx supabase@2.111.0 db query --linked --experimental "select count(*) from public.players;"
npx supabase@2.111.0 db query --linked --experimental --file percorso/query.sql
npx supabase@2.111.0 db push --linked --experimental --yes
npx supabase@2.111.0 functions deploy simula-giornata --project-ref hhvyyjpbsgjcaaaizgwb
```

Project ref: `hhvyyjpbsgjcaaaizgwb`. Il login (`npx supabase login`) è già stato fatto su questa
macchina; su un'altra va rifatto insieme a `supabase link`, perché `supabase/.temp/` è in `.gitignore`.

---

## Funzionalità completate

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

Le sostituzioni sono già leggibili nel tabellino senza lavoro aggiuntivo: `match_stats.minuti` è
calcolato sui blocchi giocati, quindi chi esce ha 45' e chi entra il resto.

### Simulazione notturna automatica — attiva

Job `simula-giornata-notturna` in `cron.job`, **attivo**. Gira **ogni ora**; è la funzione
`private.simula_giornata_notturna()` a decidere se a Roma è mezzanotte.

**Perché ogni ora e non alle 23:00 UTC.** pg_cron pianifica in UTC: un orario fisso sarebbe a
mezzanotte d'inverno e all'una d'estate. Il controllo sull'ora italiana dentro la funzione
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

### Deploy su Vercel — preparato, non ancora pubblicato

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

### Mercato — trattative fra squadre (backend fatto, UI da fare)

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

Vincoli all'accettazione, per **entrambe** le squadre: rosa ≤ `slot_rosa`, rosa ≥ 11 (sotto gli
undici il motore non saprebbe schierare), portieri ≥ `portieri_minimi`. La proprietà dei giocatori
è ricontrollata all'accettazione: fra proposta e risposta possono passare ore e un altro scambio.

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

---

## Database remoto

Migrazioni applicate fino a `20260802150000_mercato_trattative.sql`.

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
- **Mercato, prove negative**: un terzo partecipante della stessa lega vede 0 righe di una proposta
  pendente e non può accettarla al posto del destinatario («Questa proposta non è indirizzata a
  te»); la stessa proposta, una volta accettata, gli diventa visibile (design §9.3). Uno scambio
  alla pari che lascerebbe una squadra senza portieri è respinto dal controllo giusto — la prima
  versione della prova era stata respinta dal vincolo sugli slot, che scatta prima, quindi è stata
  rifatta a parità di numeri per esercitare davvero la regola sui portieri.

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
- **Il cron `chiusura-mercato` non è mai stato visto girare alle 21:00.** È registrato e la
  funzione è provata chiamandola a mano, ma nessuna esecuzione reale è stata osservata.
- **Nessuna lega è attualmente in stato `stagione`**: le tre esistenti sono due in `setup` e una
  `conclusa`. Il mercato quindi non è provabile dall'interfaccia finché non se ne avvia una.

---

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

1. **Provare la simulazione** con la Edge Function versione 6 e verificare cronaca e assist.
2. **Completare la grafica**: il menu di stagione è finito. Restano **Lobby**, **Draft**,
   **Onboarding** e **Login**. I mattoni condivisi esistono già (`.esito`, `.esito-riga`,
   `.stat-guida`, `.giornata-card`, `.sezione-testa`, `.button-fantasma`, `.pillola-stato`,
   `.menu-azione`, `.forma-chip`, `.pannello-laterale`): è in gran parte riuso.
3. **Decidere il disallineamento del calendario** descritto sopra: il cron rispetta le date, ma le
   simulazioni manuali sono andate avanti rispetto ad esse.
4. **Fallback formazione alle 23:00**: oggi l'ereditarietà avviene dentro la simulazione, cioè alle
   00:00. L'utente non ha modo di vedere e correggere la formazione automatica prima della partita,
   che è lo scopo dell'orario anticipato (design §6.7).
5. **Test end-to-end** con più account reali: turni di riposo, fine calendario, controlli RLS.
6. **Mercato**: è il modulo in corso, fuori dallo scope Fase 1, deciso dall'utente. Sono tre
   sottosistemi indipendenti (design §9) più due cron nuovi, e vanno fatti uno alla volta:
   - **trattative fra squadre** (§9.2): acquisto secco, scambio, scambio con conguaglio;
     solvibilità e validità rosa per **entrambe** le squadre; log pubblico dei conclusi (§9.3);
   - **aste svincolati** (§9.4): 10 estratti alle 07:00 con almeno 3 under 20, busta chiusa,
     risoluzione alle 17:00 con soglia nascosta, massimo 3 aste vinte al giorno per squadra;
   - **svincolo** (§9.5): non richiede schema nuovo, `player_instances.team_id` è già nullable
     e il commento in `20260731120500_rose.sql` dice già «null = svincolato».

   **Due cose da sapere prima di scrivere codice**, entrambe verificate nel codice:

   - **Le istanze giocatore nascono solo al pick** (`draft_indipendente.sql:223`): chi non è mai
     stato draftato **non ha una riga**. Quindi il pool svincolati non è «istanze con `team_id`
     null» ma «catalogo meno gli istanziati in questa lega, filtrati per `campionati_attivi`», e la
     riga nasce quando l'asta viene vinta. Il design doc lascia intendere il contrario.
   - `transactions` è già append-only con `saldo_dopo`: i trasferimenti ci entrano senza toccare
     nulla. I premi partita vanno normalizzati (design §5.2), mai valori assoluti.

   **Stato**: le **trattative sono fatte, database e interfaccia**, con finestra 07:00–21:00.
   Restano **le aste svincolati** e **lo svincolo**.

   Per provare il mercato dall'app serve una lega in stato `stagione`: al 2 agosto 2026 non ce ne
   sono (due in `setup` con una sola squadra, una `conclusa`).

7. **Push del browser**, sopra la tabella `notifications` che ora esiste. Vedi il limite iOS
   descritto nella sezione delle notifiche.

## Stato UX deciso dall'utente

- Deve sembrare un videogioco manageriale, non un sito minimale.
- Riferimenti visivi: app di risultati live in stile LiveScore e cruscotti calcistici viola.
- L'esperienza principale è smartphone: ogni cambiamento va provato prima su viewport mobile.
- Le immagini giocatore non devono avere rettangoli dietro. **Attenzione**: un `filter` CSS si
  applica anche agli pseudo-elementi, quindi un `drop-shadow` sul contenitore proietta l'ombra dei
  loro riquadri invece della sagoma del giocatore. L'ombra va sull'`img`.
- Logo squadra sempre quadrato, e senza cornice attorno.
