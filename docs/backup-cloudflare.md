# Un secondo host, come rete di sicurezza

SpecialOne gira su Vercel. Questo documento serve a tenerne **una copia viva su
Cloudflare Pages**, aggiornata dallo stesso repo, da usare se Vercel dovesse
bloccare il progetto per la quota di spazio deploy.

Non è una migrazione: i due host convivono e si aggiornano insieme a ogni push.

## Perché si può fare senza rischi

SpecialOne è **puramente statico**. Non c'è nessuna cartella `api/`, nessuna
funzione serverless, nessuna dipendenza da Vercel nel `package.json`: tutto il
backend è Supabase (database, autenticazione, storage, edge function, cron).
I due host servono gli stessi file e parlano allo stesso Supabase.

Di conseguenza **i dati sono gli stessi da entrambe le parti**: un utente che
gioca dal dominio Cloudflare e uno che gioca da quello Vercel vedono la stessa
lega, in tempo reale. Non c'è niente da sincronizzare.

## Cosa c'è già nel repo

| file | a cosa serve | equivalente Vercel |
|---|---|---|
| `public/_redirects` | riscrittura SPA: ogni indirizzo serve `index.html` | `rewrites` in `vercel.json` |
| `public/_headers` | header di sicurezza e cache | `headers` in `vercel.json` |

Finiscono in `dist/` col build e **non disturbano Vercel**, che li ignora.

> Se cambi le regole in `vercel.json`, cambiale anche qui. Sono due file
> separati per due host diversi, e nessuno li tiene allineati al posto tuo.

## Come collegarlo, una volta sola

1. Su **Cloudflare Pages** → *Create a project* → *Connect to Git* → scegli il
   repo di SpecialOne.
2. Impostazioni di build:
   - **Framework preset**: nessuno (o "Vite")
   - **Build command**: `npm run build`
   - **Build output directory**: `dist`
3. **Variabili d'ambiente** — le stesse due che usa Vercel, senza le quali il
   sito si apre ma non si collega a niente:
   - `VITE_SUPABASE_URL`
   - `VITE_SUPABASE_PUBLISHABLE_KEY`
4. Fai partire il primo deploy e apri l'indirizzo `*.pages.dev` che ti dà.

## L'unica cosa da non dimenticare

Il **login funziona subito**: è email e password, e non usa nessun redirect.

La **registrazione di un nuovo utente**, invece, manda un'email di conferma che
rimanda a `window.location.origin` — cioè al dominio da cui è partita. Perché
funzioni anche dal dominio Cloudflare, quell'indirizzo va aggiunto in Supabase:

> Authentication → URL Configuration → **Redirect URLs** → aggiungi
> `https://<nome-progetto>.pages.dev/**`

Se non lo fai, chi gioca già continua a entrare senza problemi da entrambi i
domini; si rompe solo la conferma per un'iscrizione nuova fatta da Cloudflare.

## Il dominio: `specialonegame.com`

Il dominio esiste già ed è acquistato da Vercel. Stato verificato il 22
settembre 2026:

| | |
|---|---|
| `specialonegame.com` | 308 → `www.specialonegame.com` |
| `www.specialonegame.com` | HTTP 200, serve l'app (PWA installabile) |
| nameserver | `ns1.vercel-dns.com`, `ns2.vercel-dns.com` |

**Questo risolve il problema della PWA**: chi installa l'icona dal dominio
continua a funzionare qualunque host ci sia dietro. Un cambio di host non lo
vede nessuno.

### Ma c'è un punto debole, ed è il motivo per cui questo paragrafo esiste

Registrazione **e** DNS stanno entrambi dentro l'account Vercel. Il dominio
resta tuo in ogni caso — nessuno te lo toglie — ma se l'account finisse
limitato proprio nel momento in cui serve ripuntarlo, ti troveresti a dover
cambiare la destinazione da dentro il pannello che non funziona.

**Il rimedio è separare le due cose**, e si fa una volta sola:

1. Su Cloudflare → *Add a site* → `specialonegame.com`: legge i record
   esistenti e li ricopia.
2. Controlla che abbia preso i record che puntano a Vercel (A e CNAME `www`).
3. Cambia i **nameserver** su Vercel (dove il dominio è registrato) mettendo
   quelli che Cloudflare ti indica.

Da quel momento la **registrazione resta a Vercel** e il **DNS è su
Cloudflare**, che è gratis. Il sito continua a stare su Vercel esattamente come
adesso: non cambia niente per chi gioca.

Il giorno in cui servisse, cambi **un record** su Cloudflare e il dominio punta
a Cloudflare Pages. Nessuno reinstalla niente, nessuno cambia indirizzo, e non
dipendi dal pannello Vercel per farlo.

## Se un giorno serve davvero

Con DNS su Cloudflare e il sito già in piedi su Pages: cambi il record, e
basta. Non c'è niente da migrare e niente da comunicare ai partecipanti.

Senza aver spostato il DNS: devi riuscire a cambiare la destinazione dal
pannello Vercel. Di norma si può — un blocco riguarda i deploy, non il DNS — ma
è esattamente il tipo di cosa che non vuoi scoprire mentre il gioco è fermo.
