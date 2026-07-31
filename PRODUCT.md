# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Users

Gruppo chiuso di 6–10 amici che gioca prevalentemente da smartphone. Un partecipante crea e amministra la lega; gli altri entrano tramite codice invito e gestiscono la propria squadra durante la giornata.

## Product Purpose

SpecialOne rende giocabile una carriera calcistica multiplayer a turni: draft casuale, formazione, simulazione notturna e classifica condivisa. La Fase 1 deve validare rapidamente se il ciclo di una singola stagione è divertente.

## Positioning

Combina il ritmo immediato di “38-0” con una lega privata persistente: le decisioni di tutti confluiscono in una sola giornata simulata ogni notte, in `Europe/Rome`.

## Operating Context

La lega viene configurata una volta dall'admin, condivisa con un codice di sei caratteri e usata in sessioni brevi durante il giorno. Alle 23:00 viene predisposta la formazione automatica di fallback; alle 00:00 viene simulata una giornata.

## Capabilities and Constraints

- Fase 1: autenticazione, setup lega e squadra, draft, formazione, calendario, simulazione, classifica e tabellino.
- Supabase è l'autorità per stato di gioco, autenticazione, file e sicurezza; nessuno stato di gioco vive in `localStorage`.
- Tutte le tabelle applicative hanno RLS. Formazioni altrui e future informazioni sensibili non devono essere leggibili prima del momento previsto.
- Interfaccia in italiano, mobile-first, PWA; desktop come adattamento del flusso mobile.
- Motore di simulazione validato e non modificabile senza il protocollo di regressione documentato.

## Brand Commitments

Nome prodotto: SpecialOne. Tono adulto, diretto e competitivo, senza estetica infantile o promesse commerciali. Il riferimento dichiarato è il ritmo del gioco “38-0”, non una copia della sua identità visiva.

## Evidence on Hand

- Specifica funzionale: `docs/design.md` e `docs/decisioni-fase1.md`.
- Motore validato: `engine/` e report in `docs/motore-validazione.md`.
- Dataset FC 26 importato: 5.416 giocatori e 192 club, documentato in `docs/dataset-fc26.md`.
- Non esistono ancora logo, fotografie di giocatori o asset ufficiali da mostrare nell'interfaccia.

## Product Principles

- Ogni schermata porta a una decisione chiara in pochi secondi.
- Il gioco rende visibili conseguenze e scadenze, senza nascondere regole importanti.
- La competizione resta equa grazie a vincoli server-side e RLS, non alla fiducia nel client.
- Si costruisce soltanto ciò che serve a validare la Fase 1.

## Accessibility & Inclusion

Controlli usabili da tastiera, focus visibile, contrasto WCAG AA, testi e target tattili leggibili su smartphone.
