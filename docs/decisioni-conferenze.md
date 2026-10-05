# Conferenze East / West e sorteggio in diretta (Serie F, 24 squadre)

Decisioni prese col committente il **5 ottobre 2026**. Valgono solo per le leghe con
`leagues.conferenze_attive = true` (oggi: da accendere per la Serie F quando tutto e' pronto).
Le altre leghe funzionano come prima.

## Regole decise

- **Squadre**: 24 (16 attuali + 8 nuove), due conferenze da 12: **East Conference** e **West Conference**.
- **Regular season**: si gioca solo dentro la propria conferenza, 2 gironi (andata e ritorno):
  11 avversarie x 2 = **22 giornate** (prima 30). Le due conferenze giocano le stesse giornate.
- **Sorteggio a ogni stagione**, in diretta dopo la chiusura dell'off-season: **una squadra ogni
  20 secondi**, alternando East e West ("La prima squadra estratta per la East Conference e'...")
  fino a 12 e 12. 24 estrazioni = 8 minuti. Il sorteggio parte nel momento in cui si chiude
  l'off-season, quindi l'orario lo decide chi chiude l'off-season (il committente la posticipa a mano).
- **Playoff a tre tabelloni da 8 squadre** (BLOCCO 2, NON ANCORA FATTO):
  - **Champions League** (ex Title Playoff): prime 4 di ogni conferenza. Loghi della Champions.
  - **Europa League**: dalla 5a all'8a di ogni conferenza. Usa sfondo, musica e grafica dell'attuale
    Draft Playoff (stile Europa League).
  - **Draft Playoffs** (nuovo): dalla 9a alla 12a di ogni conferenza. Asset (sfondo, canzone) da inviare.
  - Quarti incrociati Est-Ovest: 1E-4W, 2E-3W, 1W-4E, 2W-3E. Andata e ritorno; finale secca in campo
    neutro. Stessa cosa per tutti e tre i tabelloni.
- **Ordine di scelta nel mercato a scelte** (BLOCCO 2): stessa idea del Draft Playoff di oggi
  (docs/decisioni-draft-picks.md): scelgono per primi quelli del Draft Playoffs, poi Europa League, poi
  Champions League, dentro ogni gruppo secondo il risultato del proprio tabellone.
- **Le 8 nuove squadre** (BLOCCO 3): costruiscono la rosa col mini-draft a pacchetti come sempre, con un
  budget del draft uguale per tutte e piu' alto: **48 M EUR** (il draft iniziale della Serie F era 40 M su
  tetto 80 M; i monti ingaggi attuali sono in media 53 M). Si imposta `leagues.budget_draft` all'apertura
  del loro draft. Il limite di squadre per lega e' stato portato da 20 a 24.

## Cosa e' implementato (migrazione 20261005050000)

- `leagues.conferenze_attive`; `leagues.giornate_totali` (colonna generata) tiene conto delle conferenze
  ((n_squadre/2 - 1 + parita') x n_gironi); `n_squadre` fino a 24; `fase_carriera` puo' essere `'sorteggio'`.
- `standings.conferenza` ('est'/'ovest'): la **posizione e' calcolata dentro la conferenza**
  (`registra_risultato_partita`, `partition by conferenza`; indice unico (stagione, conferenza, posizione)).
- `sorteggi_conferenze` e `sorteggio_estrazioni`: l'ordine lo decide il server all'inizio (casuale; posti
  dispari East, pari West). **Segreto**: ogni estrazione e' leggibile (RLS) solo dal momento della
  rivelazione (`private.sorteggio_rivelate`); nessuno puo' sapere in anticipo chi uscira'.
- `finalizza_offseason`: con le conferenze non crea il calendario; mette la lega in `'sorteggio'` e crea il
  sorteggio. `private.completa_sorteggi_scaduti` (cron ogni minuto) a sorteggio finito (+20 s) rimette la
  lega in `'normale'` e chiama `inizializza_stagione`, che ora genera il calendario per conferenza
  (stesso metodo del cerchio, stesse giornate) e le `standings` con la conferenza. Se qualcosa fallisce
  la lega resta in `'sorteggio'` e si riprova al giro dopo.
- App: `SorteggioConferenze.tsx` (diretta sincronizzata sull'orologio del server, roulette di suspense,
  carta della squadra estratta, due colonne 0/12), `ConferenceBadge.tsx` (segnaposto finche' non arrivano i
  loghi: metterli in `public/loghi-conferenza/east.png` e `west.png`), classifica con due schede East/West e
  zone 1-4 Champions / 5-8 Europa League / 9-12 Draft Playoffs.

## Cosa manca (in ordine)

1. **Accendere** `conferenze_attive` per la Serie F (e `n_squadre` = 24, numero pari di squadre attive)
   solo quando i nuovi sono entrati e hanno completato il draft, e prima di chiudere l'off-season.
2. **BLOCCO 2: tabelloni.** `private.crea_tabelloni`, `assegna_posizioni_playoff`, `ordine_draft_playoff` e il
   tipo di tabellone (`brackets.tipo`: oggi 'title'/'draft') vanno adattati a tre tabelloni con le posizioni
   per conferenza. **Va fatto entro la fine della regular season (22 giornate)**: `crea_tabelloni` oggi
   assumerebbe una classifica unica e produrrebbe tabelloni sbagliati.
3. Grafica e nomi: Champions League (loghi), Europa League, Draft Playoffs; loghi East/West; stelle e albo
   (il titolo diventa la Champions League).
4. Ingresso degli 8 nuovi e budget 48 M.

## Come provare senza toccare dati veri

Transazione annullata: accendere il flag, forzare `offseasons.scade_il` nel passato, chiamare
`private.finalizza_offseason(<lega>)`, anticipare `sorteggi_conferenze.avviato_il`, chiamare
`private.completa_sorteggi_scaduti()` e controllare calendario (solo dentro la conferenza) e posizioni.
