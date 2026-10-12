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
5. **Archivio**: i 2 bucket (`team-crests` privato, `player-photos` pubblico) e le 3 regole di accesso. **File ancora da copiare**
   (10.951 foto giocatori, 60 MB; 5 stemmi, 1,4 MB).
6. **Prova della simulazione** (funzione `simula-giornata` eseguita in locale contro la copia): LegaBot giornata 11 e
   Serie F giornata 6 completate. **Serie F, giornata intera in 4,1 s** (rose, 12 partite, progressione, stipendi),
   contro i 10+ s della sola lettura delle abilita' sul cloud del 11 ottobre.
7. Le sottoscrizioni push sono **svuotate** nella copia: non puo' mandare notifiche a nessuno.

## Cosa manca per un passaggio vero
- [ ] Funzioni (`simula-giornata`, `invia-push`) dentro lo stack (ora girano solo da terminale): copiare anche `engine/`
      e riscrivere gli import; variabili `CHIAVE_SEGRETA_PROGETTO`, chiavi VAPID per le push; segreto `chiave_simulazione` nel vault.
- [ ] Copia dei file dell'archivio (foto e stemmi).
- [ ] Indirizzo pubblico: Cloudflare Tunnel (gratis) + un nome di dominio; `SUPABASE_PUBLIC_URL`/`API_EXTERNAL_URL`/`SITE_URL`.
- [ ] Account veri (auth.users con password) e prova di login dall'app puntata alla copia (anteprima Vercel separata).
- [ ] Mac sempre acceso: niente sospensione, riavvio automatico di Docker, gruppo di continuita'; backup giornaliero fuori casa.
- [ ] Procedura di passaggio e di ritorno al cloud (prova generale con congelamento della lega).
- [ ] Prova di carico (`tools/stress/reveal-simultaneo.mjs`) contro il Mac.

`sh tools/spinoff/ricarica-dati.sh` rifa la copia dei dati dal cloud (sola lettura sul cloud).
