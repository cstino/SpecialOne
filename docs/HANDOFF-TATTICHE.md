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
   un merge), e applicare in produzione la migrazione `20260928100000`.
2. **Indicazioni di squadra** (seconda pagina): stile, dove attacchiamo legato
   alla propria rosa, linea difensiva e ampiezza nuove.
   Qui anche il **portiere-libero**, che conta con la linea alta: dà senso al
   piano di sviluppo "Fuori dai pali". Su `main` l'anteprima di quel piano dice
   che conterà con le tattiche (`SchedaGiocatore.tsx`, confrontoScelta del
   PannelloAllenamento): toglierla o legarla a `leagues.tattiche_attive` quando
   il ruolo esiste. Attributi utili: `goalkeeping_speed`, `gk_positioning`,
   `gk_kicking`. `engine/tattiche.js` ha già un asse "linea" alta/media/bassa
   con profilo, mai collegato: riusarlo senza la parte di lettura dell'avversario.
3. **Voti in pagella** stile SofaScore, da azioni riuscite/sbagliate, RNG separato.
4. **Ritaratura del sistema intero** con la prova del predefinito;
   **`FAM_MALUS_MAX`** (punto F) va rivisto qui.
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
