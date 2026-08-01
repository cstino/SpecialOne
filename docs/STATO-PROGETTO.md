# Stato progetto e handoff

Ultimo aggiornamento: **1 agosto 2026**. Questo documento descrive lo stato reale della working tree ed è il punto di partenza per il prossimo agent.

## Prima di lavorare

1. Leggere `CLAUDE.md` e `docs/decisioni-fase1.md`.
2. Non scartare né sovrascrivere la working tree: contiene molto lavoro non ancora incluso nell'ultimo commit.
3. Per ogni modifica Supabase creare una nuova migrazione; non modificare migrazioni già applicate.
4. Il motore è validato. Se si modifica `engine/`, eseguire obbligatoriamente `npm run test:engine` e confrontare la baseline.
5. UI mobile-first, stato di gioco solo su Supabase, nessun `localStorage`.

## Stato Git

- Branch: `main`
- Ultimo commit: `71d1ffb feat: add independent draft and tactical squad management`
- Remote: `https://github.com/cstino/SpecialOne.git`
- **Importante:** calendario, simulazione, pagine stagione/partita/classifica/squadra e gli ultimi fix stemma sono ancora modifiche locali non committate. Un clone nuovo da GitHub non le contiene.

## Funzionalità completate

### Fondamenta e dati

- React 19 + Vite + TypeScript, Supabase Auth/Database/Storage/Edge Functions.
- Schema Fase 1 con RLS, RPC e privilegi server-side.
- Dataset FC 26 importato: 5.416 giocatori, 192 club, 10 campionati.
- Bucket privato per foto giocatori; avatar anonimo grigio quando la foto manca.
- Motore di simulazione validato e integrato mantenendo il seed deterministico.

### Onboarding e lega

- Login e sessione Supabase.
- Creazione lega e ingresso con codice invito.
- Creazione squadra con nome e stemma preset/custom.
- Stemmi ritagliati in formato quadrato, tool locale per rimuovere lo sfondo e upload privato.
- Compatibilità mobile: fallback UUID quando `crypto.randomUUID` non è disponibile.
- Compatibilità Safari/iOS: il client usa il MIME realmente prodotto dal canvas; Storage e validatore accettano `image/webp` e `image/png`.

### Draft

- Draft indipendente: ogni squadra procede senza aspettare le altre.
- Regola “chi prima arriva”: un giocatore già scelto rimane visibile ma non selezionabile; il server garantisce l'unicità.
- Spin club, reroll, budget/solvibilità e completamento rosa.
- Nella lega di test `sdsDas` sono presenti quattro squadre e il draft è stato completato anche per le squadre simulate.

### Formazione e rosa

- Campo tattico grafico in stile videogame, portiere in basso e attaccanti in alto.
- Moduli gestiti: 4-3-3, 4-2-3-1, 4-4-2, 3-5-2, 5-3-2, 3-4-3 e 4-3-1-2.
- Corretti gli slot noti: 4-2-3-1 (LW/CAM), 4-4-2 (RM), 3-4-3 (LM), 4-3-3 (ST/RW), 3-5-2 distinto dal 5-3-2.
- Selettore modulo aperto premendo il titolo; rimosso il select duplicato.
- Titolari, panchina e tribuna in tab separate.
- Click giocatore apre mini-card con posizioni preferite e azioni `Sostituzione` / `Dettagli`.
- Scambio possibile fra qualunque due giocatori, anche tra campo, panchina e tribuna.
- Panchina e tribuna ordinate per reparto (GK → DEF → MID → ATT), poi overall decrescente.
- Foto, overall e ruolo specifico; colori reparto: GK arancione, DEF azzurro, MID verde, ATT rosso.
- Indicatore fuori posizione: giallo per incompatibilità lieve, rosso per incompatibilità completa.
- Il colore della mini-card dipende dal reparto naturale del giocatore, non dallo slot occupato.
- La formazione resta consultabile durante il draft e viene salvata su Supabase senza perdere lo stato.

### Stagione e simulazione

- Inizializzazione stagione e calendario con metodo del cerchio.
- Edge Function `simula-giornata` implementata e distribuita; al momento l'admin può lanciarla dal pulsante `Simula giornata`.
- Simulazione sequenziale con seed salvato, adapter DB → motore che fallisce se mancano dati obbligatori e `usaCondizione: false`.
- Registrazione atomica e idempotente di risultato, statistiche, classifica e `formation_xp` tramite RPC.
- Se la formazione della giornata manca, viene ereditata l'ultima formazione salvata. Solo in assenza di qualsiasi formazione viene generato il 4-3-3 automatico.
- Corretto il bug che dopo una simulazione mostrava una formazione automatica diversa da quella salvata.
- Overview stagione con prossima partita, ultima partita e risultato.
- Menu Partite con calendario e risultati cliccabili.
- Dettaglio partita con risultato, moduli, statistiche squadra e statistiche giocatori.
- Classifica aggiornata dopo la simulazione.

### Pagina squadra

- Nuova voce `Squadra` nel menu.
- Profilo della propria squadra con statistiche, risultati recenti e rosa ordinata per ruolo.
- Modifica di nome e stemma solo per il proprietario, validata da RPC server-side.
- Click su una squadra avversaria apre il suo profilo pubblico nella lega, senza controlli di modifica.

## Database remoto

Le migrazioni risultano applicate fino a:

`20260801113304_supporta_png_stemmi.sql`

Le ultime migrazioni locali aggiungono:

- `20260801094500_inizializza_stagione_calendario.sql`
- `20260801094923_correggi_lint_calendario.sql`
- `20260801100819_registra_risultato_partita.sql`
- `20260801111119_aggiorna_profilo_squadra.sql`
- `20260801113304_supporta_png_stemmi.sql`

La Edge Function attiva è `supabase/functions/simula-giornata/index.ts`. Non mettere la `service_role` nel frontend.

## Verifiche già eseguite

- `npm run build`: superato.
- `npm run lint`: superato.
- Supabase `db lint --linked`: nessun errore di schema.
- Test SQL di `registra_risultato_partita`: superato con rollback.
- Test SQL di `aggiorna_profilo_squadra`: superato con rollback.
- Verificato sul database remoto che `team-crests` accetti WebP e PNG e che policy/validatore siano coerenti.
- Simulazione manuale della giornata verificata dall'utente su mobile.

## Stato UX deciso dall'utente

- Il prodotto deve sembrare un videogioco manageriale, non un sito minimale.
- Riferimenti visivi: Football Manager e lineup “Dream Team”; fondo scuro, viola, immagini giocatori e gerarchia forte.
- L'esperienza principale è smartphone; ogni cambiamento va testato prima su viewport mobile.
- Le immagini giocatore non devono avere un rettangolo netto dietro: sfumatura trasparente.
- Logo squadra sempre quadrato.

## Prossime task consigliate

1. **Mettere in sicurezza l'handoff Git:** rivedere le modifiche locali, eseguire test finali, poi commit e push. Finché non viene fatto, GitHub non contiene il lavoro descritto sopra.
2. **Automazione stagione:** configurare davvero i job `pg_cron`/`pg_net` in `Europe/Rome` (fallback formazione alle 23:00 e simulazione alle 00:00). Il pulsante admin è attualmente il percorso di test.
3. **Completamento Fase 1:** test end-to-end con più account reali, turni di riposo, fine calendario, criteri classifica e controlli RLS avversari.
4. **Mercato:** richiesto dall'utente come prossimo grande modulo. Prima di implementarlo rileggere le sezioni mercato/economia di `docs/design.md` e chiarire se entra subito nella roadmap nonostante il vecchio scope della Fase 1 lo rimandasse.
5. **Pagina squadra:** eventuali rifiniture visuali, scelta/crop logo più guidata e collegamenti al profilo squadra da tutte le classifiche/partite.
6. **Fine stagione:** non ancora implementata; crescita/declino, contratti e seconda stagione restano fuori dallo stato attuale.

## File principali aggiunti o modificati localmente

- `src/App.tsx`: routing a stato tra overview, draft/rosa, partite, classifica, squadra e dettaglio partita.
- `src/components/Formazione.tsx`: campo, moduli, selezione e dettagli giocatore.
- `src/components/SeasonOverview.tsx`: dashboard stagione e simulazione admin.
- `src/components/Matches.tsx`: calendario.
- `src/components/MatchDetail.tsx`: tabellino.
- `src/components/Standings.tsx`: classifica.
- `src/components/TeamProfile.tsx`: pagina squadra e modifica profilo.
- `src/components/SeasonUI.tsx`: componenti condivisi stagione.
- `src/lib/useSeasonData.ts`: caricamento aggregato dati stagione.
- `src/lib/crest.ts`: elaborazione stemmi, rimozione sfondo, UUID compatibile e MIME reale.
- `supabase/functions/simula-giornata/index.ts`: orchestrazione simulazione.
- `supabase/migrations/20260801*.sql`: calendario, risultati, profilo squadra e PNG stemmi.

## Attenzioni tecniche

- La working tree è intenzionalmente sporca: non usare `git reset --hard`, `git checkout --` o pulizie automatiche.
- La formazione salvata è slot-per-slot; non riordinare gli array dei titolari prima di passarli al motore.
- `sostituzioni()` muta il lineup: costruire sempre oggetti freschi per ogni partita.
- Il seed globale impone simulazioni in sequenza, mai in parallelo.
- Formazioni altrui devono rimanere protette dalle policy fino alla simulazione.
- Gli stemmi custom sono percorsi Storage privati, non URL pubblici.
- Le foto FC 26 devono essere ospitate nel bucket privato, mai hotlinkate.

