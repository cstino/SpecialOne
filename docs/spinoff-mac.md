# Spinoff: Supabase sul Mac (12 ottobre 2026)

Una **copia** di Supabase che gira sul Mac mini, pronta per il giorno in cui il piano gratuito del cloud non bastera'
(vedi la discussione del 12 ottobre: niente Pro a 25 dollari). **Non e' in produzione**: l'app parla ancora al cloud.

## Dove sta
- Stack: `~/supabase-spinoff/project` (configurazione ufficiale `docker/` di Supabase, immagini Docker, Postgres 17).
  Segreti in `~/supabase-spinoff/project/.env` (permessi 600, **mai nel repo**).
- Dump e log: `~/supabase-spinoff/dump/`. Gestione: `sh run.sh start|stop|status|logs` dalla cartella del progetto.
- API: `http://localhost:8000` (gateway). Studio (pannello): stessa porta, con le credenziali `DASHBOARD_*` del `.env`.
- Il Mac ha 8 GB: lo stack a riposo usa ~1,4 GB sui 3,8 GB assegnati a Docker (con Home Assistant gia' acceso).

## Cosa e' gia' fatto
1. **Schema**: `supabase db dump --linked --schema public,private` caricato senza errori. Confronto col cloud: 54+14
   tabelle, 55 regole di lettura, 291 funzioni, 39 trigger, identici.
2. **Dati**: public e private (24 MB), righe identiche al cloud (giocatori 6.666, istanze 2.264, partite 1.147...).
3. **Utenti**: 27 utenti SEGNAPOSTO (stesso id, email `utente-xxxx@spinoff.local`, **nessuna password**). I veri account
   (con le password) si copiano solo al passaggio definitivo.
4. **Job pianificati**: i 16 del cloud, creati **disattivati** (`cron.job.active = false`).
5. **Archivio**: i 2 bucket (`team-crests` privato, `player-photos` pubblico), le 3 regole di accesso e i file
   (10.951 foto giocatori, 60 MB; 5 stemmi), copiati con `tools/spinoff/copia-archivio.mjs`. Su Docker Desktop i file stanno in un
   **volume Docker con nome** (`docker-compose.mac.yml`): le cartelle montate da macOS non supportano gli attributi estesi e
   Storage rispondeva 500. Su un server Linux non serve.
6. **Prova della simulazione**: eseguita prima dal terminale (Serie F, giornata intera in **4,1 s** contro i 10+ s della sola
   lettura delle abilita' sul cloud dell'11 ottobre) e poi **dentro lo stack**: job `simula-giornata-notturna` -> `pg_net` ->
   gateway -> Edge Function -> database, giornata 7 di Serie F simulata, HTTP 200.
   Funzioni portate con `tools/spinoff/costruisci-funzioni.sh` (copia anche `engine/` e riscrive gli import); gli indirizzi del
   cloud dentro le funzioni del database sono riscritti con `tools/spinoff/indirizzi-locali.sql`; segreto `chiave_simulazione`
   nel vault = chiave di servizio dello stack (che e' anche `CHIAVE_SEGRETA_PROGETTO` delle funzioni).
7. **Accesso da fuori e login vero** (12 ottobre 2026, prova con tunnel `cloudflared` temporaneo, indirizzi che cambiano a ogni avvio):
   app avviata con `VITE_SUPABASE_URL` = indirizzo del tunnel verso il Mac; login con un utente segnaposto a cui si e' messo una
   password di prova (via API admin di GoTrue). Nota: gli utenti inseriti a mano devono avere le colonne token a `''`, non NULL,
   altrimenti GoTrue risponde «Database error querying schema».
8. **Test di carico contro il Mac** (`tools/stress/reveal-simultaneo.mjs`, Serie F): 20 persone 0,15 s, 40 persone 0,35 s in locale;
   **via tunnel pubblico 20 persone 0,8 s, 40 persone 0,9 s**, zero errori (cloud gratuito: 24 s nel caso peggiore con 20).
9. Le sottoscrizioni push sono **svuotate** nella copia: non puo' mandare notifiche a nessuno.

## Cosa manca per un passaggio vero
- [ ] Chiavi VAPID (`VAPID_PUBLIC_KEY`, `VAPID_PRIVATE_KEY`) per le notifiche push: ora non configurate, e le sottoscrizioni sono vuote.
- [ ] Indirizzo stabile: dominio `specialonegame.com` (DNS ora su Vercel; zona Cloudflare pronta, vedi `docs/backup-cloudflare.md`):
      serve spostare i nameserver su Cloudflare, poi tunnel con nome (es. `db.specialonegame.com`) e `SUPABASE_PUBLIC_URL`/`API_EXTERNAL_URL`/`SITE_URL`.
- [ ] Account veri (auth.users con password) al passaggio definitivo.
- [ ] Mac sempre acceso: niente sospensione, riavvio automatico di Docker, gruppo di continuita'; backup giornaliero fuori casa.
- [ ] Procedura di passaggio e di ritorno al cloud (prova generale con congelamento della lega).
- [ ] Prova di carico (`tools/stress/reveal-simultaneo.mjs`) contro il Mac.

`sh tools/spinoff/ricarica-dati.sh` rifa la copia dei dati dal cloud (sola lettura sul cloud).

## Pagina "Server in manutenzione"

Tabella `public.stato_app` (una riga, leggibile da tutti). L'app la controlla all'apertura, ogni 45 s e al ritorno in primo piano.
Se il server non risponde per due controlli di fila, mostra la stessa pagina da sola.

```
-- accendi (con messaggio facoltativo)
update public.stato_app set manutenzione = true, messaggio = null;
-- spegni
update public.stato_app set manutenzione = false;
```
Cloud: `npx supabase db query --linked "<sql>"`. Mac: `docker exec supabase-db psql -U postgres -c "<sql>"`.
Nel passaggio: accendi sul cloud prima di `congela`; il dato viene caricato sul Mac, poi spegni sul Mac.
