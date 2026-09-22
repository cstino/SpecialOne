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

## Se un giorno serve davvero

Non c'è niente da migrare: il sito è già in piedi e aggiornato. Basta dare ai
partecipanti il nuovo indirizzo.

L'unico effetto è sulla **PWA installata**: chi ha l'icona sul telefono l'ha
installata dal dominio Vercel, e quella continuerebbe a puntare lì. Dovranno
reinstallarla dal nuovo indirizzo. L'alternativa che evita tutto questo è un
dominio tuo puntato sull'host attivo: allora il cambio non lo vede nessuno.
