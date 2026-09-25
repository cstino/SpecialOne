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

1. **Preset di tattiche**, stile FC: la metà della regola "stile EA FC" ancora
   non costruita. Proposta sul tavolo, non confermata: i preset coincidono con
   gli stili di gioco esistenti (equilibrato, contropiede, possesso, fasce,
   recupero veloce, diretto, blocco basso), riempiti con ruoli, compiti e corsie
   coerenti — un solo menu, non due concetti sovrapposti.
2. **Accendere su LegaBot**: distribuire l'Edge Function del branch e guardare
   qualche giornata. Primo passo che tocca il vivo: chiedere prima.
3. Domande di design aperte: il **piano di squadra** (registro, punto A) serve
   ancora sopra ruoli e compiti?; **`FAM_MALUS_MAX`** (punto F): la familiarità
   pesa più di qualunque scelta tattica.
4. Anteprima navigabile per il telefono: artifact "Schema Tattico"
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
