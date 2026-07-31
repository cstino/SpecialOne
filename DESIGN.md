---
name: SpecialOne
description: Un tavolo gara digitale per costruire e vivere una lega privata.
colors:
  pitch: "#1f6f43"
  pitch-dark: "#125030"
  pitch-light: "#dce9df"
  paper: "#f3f1e8"
  paper-light: "#fffdf4"
  ink: "#18221c"
  ink-muted: "#566058"
  referee: "#b9362d"
  warning: "#e9c46a"
  line: "#c9cdc3"
typography:
  display:
    fontFamily: "Aptos Narrow, Arial Narrow, Roboto Condensed, sans-serif"
    fontSize: "clamp(2.75rem, 10vw, 5.75rem)"
    fontWeight: 900
    lineHeight: 0.92
    letterSpacing: "-0.025em"
  body:
    fontFamily: "Inter, ui-sans-serif, -apple-system, BlinkMacSystemFont, Segoe UI, sans-serif"
    fontSize: "1rem"
    fontWeight: 400
    lineHeight: 1.55
rounded:
  sm: "10px"
  md: "14px"
  pill: "999px"
spacing:
  xs: "8px"
  sm: "16px"
  md: "24px"
  lg: "48px"
components:
  button-primary:
    backgroundColor: "{colors.pitch}"
    textColor: "{colors.paper-light}"
    rounded: "{rounded.sm}"
    padding: "14px 19px"
    height: "50px"
  input:
    backgroundColor: "{colors.paper-light}"
    textColor: "{colors.ink}"
    rounded: "{rounded.sm}"
    padding: "12px 14px"
    height: "50px"
---

# Design System: SpecialOne

## Overview

**Creative North Star: "La lavagna gara"**

SpecialOne prende il linguaggio operativo del calcio: distinta stampata, lavagna tattica, magneti squadra e segni rapidi dell'allenatore. Non imita un videogioco da console e non usa il dashboard SaaS come struttura predefinita. I dati restano nitidi; l'identità emerge da grandi campi colore, linee di campo funzionali e controlli compatti.

**Key Characteristics:**

- Interfaccia mobile densa ma leggibile, costruita attorno alla prossima decisione.
- Carta chiara e verde campo come superfici dominanti; rosso arbitro soltanto per urgenze e azioni critiche.
- Tipografia condensata per titoli e numeri, carattere di sistema per testi e moduli.
- Stato e conseguenze sempre espliciti prima della conferma.

## Colors

Strategia **Committed**: il verde campo occupa intere regioni e segnala il contesto di gioco; carta e inchiostro mantengono il lavoro quotidiano leggibile.

**The Referee Red Rule.** Il rosso non decora: appare solo per errori, scadenze e conseguenze irreversibili.

## Typography

Titoli condensati, netti e verticali come le intestazioni di una distinta; testo corrente neutro e altamente leggibile. Numeri di budget, giornate e codici invito ricevono una gerarchia specifica, non un font tecnico ornamentale.

La famiglia display usa i condensed di sistema disponibili; il testo usa lo stack UI nativo. Il display principale va da `2.75rem` a `5.75rem`, peso 900 e interlinea `0.92`. Il corpo resta a `1rem` con interlinea `1.55` e misura massima di circa 65–75 caratteri.

## Layout

La superficie mobile segue una colonna principale con una fascia di stato persistente. Su desktop, una zona “campo” laterale sostiene contesto e riepilogo mentre il compito rimane in una colonna di lettura stretta. Le impostazioni correlate formano righe e blocchi aperti, non una griglia di card equivalenti.

## Elevation & Depth

Profondità strutturale: superfici sovrapposte con ombre morbide e leggermente traslate. I controlli attivi si sollevano come magneti sulla lavagna; il resto resta piatto.

## Shapes

Angoli moderatamente smussati per superfici e campi. Pillole riservate a stati brevi, codici e selezioni compatte. Gli stemmi sono l'eccezione geometrica e possono usare scudi, diagonali e quartieri.

## Components

### Buttons

I pulsanti principali sono compatti e sicuri: altezza minima `50px`, raggio `10px`, verde campo su carta chiara. Al passaggio si sollevano di `2px` con ombra morbida; focus sempre giallo visibile.

### Inputs / Fields

Campi chiari con bordo strutturale singolo, altezza minima `50px` e raggio `10px`. Il focus non dipende dal solo colore del bordo. Gli errori spiegano problema e recupero in una fascia rosso attenuato.

### Navigation

Topbar piatta con marchio a sinistra e una sola azione contestuale a destra. I cambi di percorso usano righe aperte a tutta larghezza; le pillole sono riservate a stato e selezione binaria.

### Stemmi

Gli stemmi sono magneti geometrici: scudo asimmetrico, colori netti e nessuna ombra a riposo. La selezione usa fondo giallo e un sollevamento breve.

## Do's and Don'ts

### Do:

- **Do** mostrare durata, capienza e conseguenze economiche accanto alla scelta che le modifica.
- **Do** mantenere le azioni primarie raggiungibili col pollice e chiaramente nominate.
- **Do** usare linee e segni calcistici soltanto quando aiutano orientamento o stato.

### Don't:

- **Don't** trasformare ogni impostazione in una card autonoma.
- **Don't** usare bagliori neon, gradienti decorativi o vetro per simulare energia.
- **Don't** nascondere errori server dietro messaggi generici.
