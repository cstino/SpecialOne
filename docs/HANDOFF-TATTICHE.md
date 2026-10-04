# Passaggio di consegne — sistema tattico

Documento per riprendere il lavoro sulle tattiche in una sessione nuova senza
rispiegare niente. Aggiornato al 25 settembre 2026. Leggere dopo `CLAUDE.md`.

Il registro completo delle decisioni, con i numeri e i perché, è
`docs/decisioni-tattiche.md` (punti 1–26 più i punti aperti A–F). Questo file è
la mappa; il registro è il territorio.

## Dove sta il lavoro

- **Branch**: `feat/tattiche`. **Non va unito a `main`** finché il committente
  non lo dice esplicitamente.
- Il branch va **riallineato a `main` all'inizio di ogni sessione**
  (`git merge origin/main`). È rimasto indietro due volte, e una volta stava per
  cancellare una correzione di produzione.
- Le migrazioni del branch sono **già applicate al database di produzione** ma
  **inerti**: tutto è dietro l'interruttore `leagues.tattiche_attive`, spento in
  tutte le leghe.
- L'Edge Function in produzione è quella di `main`. Distribuire quella del
  branch è il passo che accende il sistema: va chiesto al committente.
  **Prima di distribuirla, unire `origin/main`**: su `main` arrivano fix alla
  simulazione (es. v64-v65 del 1° ottobre: cartellini riletti prima del calcolo,
  marcatori abbinati ai gol) che una distribuzione dal branch annullerebbe.

## Checklist del lancio della season 2

> **Stato al 4 ottobre 2026 (ore 11):** punti 1 e 2 fatti: main = ramo, `simula-giornata`
> distribuita dal ramo, migrazione del 3-5-2 applicata, `simula-giornata-s2` e
> `LEGA_PROVA_SEASON_2` tolti dal codice. Restano il punto 3 (tattiche sulle altre leghe) e il 4
> (piani aperti), che decide il committente.

Da fare **in quest'ordine**, chiedendo prima al committente:

1. `git merge origin/main` nel ramo e controllare i conflitti (in
   `simula-giornata` tenere la versione del ramo dove si sovrappongono).
2. Distribuire `simula-giornata` dal ramo, togliere `simula-giornata-s2` da
   `supabase/config.toml`, dal database delle funzioni (`supabase functions
   delete simula-giornata-s2`) e il ramo `LEGA_PROVA_SEASON_2` in `Admin.tsx`.
   **Subito dopo** applicare `20261004110000_352_esterni_e_mediano.sql` (nuovo
   3-5-2, registro punto 42): il motore distribuito e l'app del ramo hanno gia'
   il 3-5-2 nuovo, il database e main ancora il vecchio. Provata il 4 ottobre
   in una transazione annullata.
3. Accendere le tattiche sulle altre leghe: `update public.leagues set
   tattiche_attive = true where stato <> 'archiviata'` (o lega per lega).
4. **Chiudere i piani di sviluppo rimasti aperti** (vedi registro, punto 40):
   i piani avviati nelle ultime giornate o ai playoff non si completano mai
   (a Serie F erano 177 il 3 ottobre) e bloccano i giocatori:
   `update public.specializzazioni_giocatore s set completa_giornata = 0 from
   public.leagues l where s.league_id = l.id and l.tattiche_attive and
   s.completato_il is null; select private.completa_specializzazioni();`
   (la funzione completa solo le leghe in stato `stagione`: farlo a stagione 2
   avviata).
5. Pubblicare l'anteprima/produzione dal ramo.

## Come si applicano le migrazioni

**Una per una**, con `supabase db query --linked --experimental --file <migrazione>`.
**Mai `supabase db push`**: la cronologia remota (`supabase_migrations.schema_migrations`)
si ferma a `20260827110000`, e ~250 migrazioni successive sono applicate ma non registrate;
`db push` proverebbe a rieseguirle tutte. Il worktree ha bisogno di una copia di
`supabase/.temp` dalla cartella principale (link del progetto, in `.gitignore`).
Dopo averle applicate, verificarle in una transazione con `rollback` impersonando un utente.

## Il principio guida

**Football Manager è il riferimento**, e le tarature si ancorano a dati misurati
(FM-Arena), non a sensazioni. Più una regola arrivata dopo e che le prevale:

> **Stile EA FC**: le tattiche si possono ignorare. Chi lascia il predefinito
> non è svantaggiato; chi ci lavora può ottenere risultati migliori *o peggiori*.

Misura che lo garantisce, da ricontrollare ogni volta che si aggiunge una leva:
`tools/validazione/prova-default-non-svantaggiato.mjs` — **chi smanetta a caso
non deve battere chi non tocca niente** (oggi: −1,8 punti su 38).

## Cosa c'è, tutto collegato

| pezzo | file | nota |
|---|---|---|
| Calci piazzati, 5 incaricati | `engine/piazzati.js`, `engine/rigori.js` | ancorati ai riferimenti Premier League; incaricati automatici al salvataggio |
| Morale in campo | `engine/morale.js` | 3,8 punti su 38 fra scarso e ottimo, come FM-Arena |
| Capitano | `applica_morale_checkpoint` (SQL) | agisce sullo spogliatoio al checkpoint, non nel motore |
| Ruoli (18) | `engine/ruoli.js` | **solo penalità** se il giocatore non sa farli; il valore tattico sta in dove lo mettono |
| Compiti per reparto | `COMPITI_REPARTO` in `engine/config.js` | **a somma zero** fra le linee, con costo in fiato |
| Corsie, "dove attacchiamo" | `engine/corsie.js`, `lineups.focus_corsia` | leggere il buco vs il lato forte: 4,6 punti |
| Schemi personalizzati | `src/components/SchemaTattico.tsx`, `src/lib/schieramento.ts` | trascinamento a calamita, solo dentro la propria linea |
| Due barre di familiarità | `formation_xp.disposizione`, `indicazioni_xp` | disposizione (con memoria) e indicazioni (24 elementi) |
| Nome dello schieramento | `nomeSchieramento()` | segue la forma in campo, non il modulo di partenza |
| Interruttore per lega | `leagues.tattiche_attive` | vale nel motore, in `salva_formazione` e sul capitano |

Tabelle del frontend generate dal motore: `src/lib/tattica.ts`. Le copie SQL
(`private.spostamenti_slot`, `private.ruoli_slot`) sono generate dalla stessa
fonte. **Se cambia il motore, vanno rigenerate entrambe.**

## Numeri attuali del sistema intero

Rispetto a chi non tocca niente (`tools/validazione/prova-sistema-tattico.mjs`):
tocca tutto a caso −1,8 · solo corsia giusta +3,2 · lavora bene su tutto +5,2 ·
sbaglia tutto apposta −12,6.

Criterio di accettazione del motore: `node tools/validazione/simulate-reale.js`,
riga PRODUZIONE — oggi 2,87 gol · 13,46 tiri · 23,3% pareggi · 46,1% vittorie
casa. **Non** `simulate.js`, che è la suite storica superata (registro, punto E).

## Cosa resta da fare

**Aggiornato il 25 settembre 2026: vedi registro, punto 27.** La tattica è
l'identità della squadra, non la mossa della giornata; il ruolo azzeccato ora dà
un bonus. Ordine concordato, un task alla volta:

1. **Indicazioni individuali**: fatto il 28 settembre (registro, punto 28):
   profili su 4 attributi, bonus e malus, "++"/"+"/"−" nel foglio della
   posizione. Restano: la riga "ruoli in cui rende" nella scheda del giocatore
   (`SchedaGiocatore.tsx`, che l'altra chat modifica spesso su `main`: fare dopo
   un merge). Migrazioni `20260928100000` e `20260929100000` **applicate in
   produzione** il 29 settembre.
   Fatti anche (29 settembre): moduli personalizzati (registro, punto 29,
   migrazione `20260929100000`), segnalino allenamento sulla rosa,
   icone centrate, Schema Tattico sistemato per il telefono.
   **Anteprima Vercel**: il branch si prova su
   `specialone-git-feat-tattiche-cstinos-projects.vercel.app`, ma NON fare push
   a ogni modifica (storage Vercel): si accumula e si pubblica su richiesta.
2. **Indicazioni di squadra**: fatto il 29 settembre (registro, punto 30),
   migrazione `20260929110000` applicata.
   Qui anche il **portiere-libero**, che conta con la linea alta: dà senso al
   piano di sviluppo "Fuori dai pali". Su `main` l'anteprima di quel piano dice
   che conterà con le tattiche (`SchedaGiocatore.tsx`, confrontoScelta del
   PannelloAllenamento): toglierla o legarla a `leagues.tattiche_attive` quando
   il ruolo esiste. Attributi utili: `goalkeeping_speed`, `gk_positioning`,
   `gk_kicking`. `engine/tattiche.js` ha già un asse "linea" alta/media/bassa
   con profilo, mai collegato: riusarlo senza la parte di lettura dell'avversario.
3. **Voti in pagella**: fatto il 1° ottobre (registro, punto 31), tabella `pagelle`
   applicata. ← il prossimo è il 4.
4. **Ritaratura del sistema intero**: fatta il 2-3 ottobre 2026 (registro,
   punti 34-38). Lo stile decide come si gioca (ritmo, possesso, volume tiri),
   linea e ampiezza lasciano un'impronta, "dove attacchiamo" e portiere libero
   ora contano, ruoli riequilibrati (+4 invece di +6,2), familiarità lasciata
   com'è (costo vero di un cambio di modulo: −2 punti), voti dei difensori
   riallineati. Prima ancora (punti 32-33): cambi a 3 soste più l'intervallo,
   piazzati dentro i blocchi; telecronaca e grafico della pressione nella live.
   **LegaBot (id 62) ha `tattiche_attive = true`** e il tasto admin chiama la
   funzione **`simula-giornata-s2`** (codice del ramo). Al lancio: unire main,
   distribuire `simula-giornata` dal ramo, togliere `simula-giornata-s2` e il
   ramo in `Admin.tsx`.
5. **Preset**: combinazioni pronte delle due pagine.

**Da sistemare dopo il merge del 28 settembre** (piani di sviluppo su `main`):
`private.incaricati_automatici` e `private.qualita_capitano` leggono gli
attributi con `private.attributi_effettivi` (catalogo + crescita +
`attributi_override`), ma `main` ha svuotato `attributi_override` e ora calcola
tutto con `private.attributi_istanza`. Non si rompe niente, ma i piani di
sviluppo verrebbero ignorati per incaricati e capitano. Serve una migrazione che
passi a `attributi_istanza`, ricostruendo le funzioni dal `prosrc` live.

Fuori da questa sequenza: **accendere su LegaBot** (distribuire l'Edge Function
del branch) tocca il vivo, chiedere prima.
Anteprima navigabile per il telefono: artifact "Schema Tattico"
   (claude.ai/code/artifact/2e790aba-e445-4299-a5a8-51c742a944a1), non ancora
   aggiornato con "dove attacchiamo" e con le tarature degli ultimi giorni.

## Lezioni pagate care, da non ripetere

- **Misurare il sistema, non i pezzi**: undici ruoli tarati uno per uno facevano
  22 punti di scarto tutti insieme (punto 25).
- **Per un costo che si accumula, la partita singola è il metro sbagliato**: il
  fiato si paga fra una giornata e l'altra (punti 23–24). Usare la prova su
  stagione, con **entrambe** le squadre che vivono la stagione.
- `forzeLinee` calcola una **media**: spostare peso non rinforza una linea, la
  diluisce. Per questo i compiti agiscono sui punti di linea.
- Aggiungere un parametro a una funzione SQL **crea un sovraccarico**: togliere
  sempre la firma vecchia, o PostgREST continua a chiamare quella.
- Le sostituzioni di testo negli script vanno **verificate** (`assert`), e un
  artifact va **eseguito**, non solo analizzato: un'anteprima è uscita con una
  variabile inesistente.
