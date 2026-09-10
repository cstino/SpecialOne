// ============================================================
//  PROTOTIPO DEL SISTEMA TATTICO — SOLO MISURA, NON E' IL GIOCO
//
//  Serve a rispondere con dei numeri a tre domande poste prima di
//  progettare il prossimo update, discusso con l'utente l'11 settembre 2026:
//
//    1. quanto vale la tattica giusta, in punti di overall equivalenti?
//    2. il triangolo dei contrasti regge, o collassa su un assetto migliore
//       di tutti?
//    3. quanto pesano gli attributi individuali rispetto all'overall?
//
//  COME FUNZIONA, e perche' non tocca engine/
//  Il motore validato riduce ogni giocatore a un numero solo
//  (ovrEfficace = overall x adattamento al ruolo x condizione) e non guarda
//  MAI gli attributi individuali per decidere quanti gol si fanno. Il
//  sistema tattico vero dovra' cambiarlo — ed e' la modifica piu' grossa dal
//  Fase 0 — ma per misurarne l'effetto non serve ancora.
//
//  Qui le tattiche producono uno scarto in PUNTI DI OVERALL per ogni
//  giocatore in campo, che dipende dai suoi attributi e dalla tattica
//  avversaria. Lo scarto viene applicato alle rose PRIMA di passarle a
//  simulaPartita(). Il motore poi lavora come sempre: stesso xG, stessi
//  blocchi, stesse sostituzioni. La misura e' quindi reale, non un modello
//  parallelo che assomiglia al gioco.
//
//  Cio' che questo prototipo NON dimostra: che quella sia la forma giusta
//  per il sistema definitivo. Dimostra solo se le grandezze in gioco stanno
//  dove vogliamo. E' esattamente lo scopo per cui e' stato scritto.
// ============================================================

import { REPARTO } from '../../engine/config.js';
import { gauss, rnd } from '../../engine/random.js';

const clamp = (v, a, b) => Math.max(a, Math.min(b, v));

// ------------------------------------------------------------
//  SCALE — sono i numeri da tarare, tenuti qui in cima apposta.
//  Il criterio deciso con l'utente: il vantaggio massimo ottenibile con la
//  tattica perfetta contro quella sbagliata deve valere MENO di 8 punti di
//  overall, perche' a +8 il piu' forte vince gia' l'84% (TEST 2 della Fase
//  0) e a quel punto la tattica conterebbe piu' della rosa.
// ------------------------------------------------------------
export const SCALE = {
  // quanto pesa avere gli interpreti giusti per la propria tattica
  INTERPRETI: 4.0,
  // quanto pesa indovinare la tattica contro quella avversaria
  COUNTER: 3.0,
};

// ------------------------------------------------------------
//  I DUE ASSI, con le opzioni discusse con l'utente.
//  'attributo' e' cio' che il motore dovrebbe imparare a leggere: e' il
//  cuore del punto 1 (bravura nello scegliere gli interpreti).
//  'reparti' dice a chi si applica l'idoneita'.
// ------------------------------------------------------------
export const ASSI = {
  linea: {
    alta:  { etichetta: 'Difesa alta',        attributo: 'velocita',        reparti: ['DEF'] },
    media: { etichetta: 'Linea media',        attributo: null,              reparti: [] },
    bassa: { etichetta: 'Blocco basso',       attributo: 'posizionamento',  reparti: ['DEF'] },
  },
  costruzione: {
    corta:     { etichetta: 'Fitti passaggi', attributo: 'passaggi_corti',  reparti: ['MID'] },
    mista:     { etichetta: 'Mista',          attributo: null,              reparti: [] },
    verticale: { etichetta: 'Verticalizza',   attributo: 'passaggi_lunghi', reparti: ['MID', 'ATT'] },
  },
};

// ------------------------------------------------------------
//  IL TRIANGOLO. Non e' inventato: e' come si contrastano davvero questi
//  assetti nel calcio, ed e' il motivo per cui l'utente voleva assetti che
//  si battono a vicenda invece di una scelta giusta.
//
//    difesa alta      batte  fitti passaggi   (comprimi, recuperi alto)
//    verticalizza     batte  difesa alta      (palla dietro la linea)
//    blocco basso     batte  verticalizza     (nessuno spazio alle spalle)
//    fitti passaggi   battono blocco basso    (pazienza contro chi si chiude)
//
//  Il valore e' il vantaggio di CHI ATTACCA in quel confronto: positivo
//  significa che la costruzione ha la meglio sulla linea difensiva.
// ------------------------------------------------------------
const CONTRASTI = {
  //            linea alta   media   bassa
  corta:      { alta: -1.0,  media: 0,  bassa: +0.7 },
  mista:      { alta:  0,    media: 0,  bassa:  0   },
  verticale:  { alta: +1.0,  media: 0,  bassa: -0.8 },
};
// La casella corta/bassa era -0.6 nella prima stesura, sul ragionamento che
// la pazienza non crea occasioni ma toglie solo vantaggio a chi si chiude.
// La misura ha bocciato quel ragionamento: con quel valore la colonna
// "bassa" era interamente negativa, cioe' il blocco basso non veniva punito
// da NESSUN assetto, e le sue tre varianti finivano tutte nelle prime cinque
// (scarto di 13.6 punti percentuali fra il migliore e il peggiore assetto).
// Ogni riga e ogni colonna devono contenere almeno un valore sfavorevole,
// altrimenti la morra cinese e' apparente: esiste il contrasto diretto ma
// esiste anche un assetto che conviene sempre.

// ------------------------------------------------------------
//  Attributi che oggi non esistono nelle rose sintetiche di roster.js.
//  Si derivano da quello che c'e', con correlazioni plausibili per ruolo:
//  serve solo che abbiano una dispersione realistica, perche' la domanda e'
//  "quanto pesa la differenza fra un interprete giusto e uno sbagliato",
//  non "quanto vale Cucurella".
//  roster.js NON viene toccato: e' il generatore della suite storica.
// ------------------------------------------------------------
export function arricchisci(rosa) {
  for (const g of rosa.giocatori) {
    if (g.velocita !== undefined) continue;
    const rep = REPARTO[g.posizioni[0]] ?? 'MID';
    const near = (media, sigma) => clamp(Math.round(gauss(media, sigma)), 20, 99);
    // la velocita' non e' correlata all'overall come le altre: esistono
    // difensori forti e lenti, ed e' esattamente il caso interessante
    g.velocita        = near(rep === 'ATT' ? 74 : rep === 'DEF' ? 66 : 70, 12);
    g.posizionamento  = near(g.ovr + (rep === 'DEF' ? 3 : -6), 7);
    g.passaggi_lunghi = near(g.ovr + (rep === 'MID' ? 2 : rep === 'DEF' ? -2 : -10), 8);
    g.passaggi_corti  = g.short_passing;
  }
  return rosa;
}

// idoneita' di un giocatore a una richiesta tattica, da 0 (inadatto) a 1
// (perfetto). 60 e' il centro: sotto penalizza, sopra premia.
function idoneita(g, attributo) {
  if (!attributo) return 0.5;
  const v = g[attributo];
  if (typeof v !== 'number') return 0.5;
  return clamp((v - 40) / 50, 0, 1);
}

/**
 * Scarto in punti di overall per ogni giocatore in campo, dato il proprio
 * assetto e quello avversario. Non muta nulla: restituisce una mappa
 * id -> delta, cosi' chi chiama decide cosa farne.
 */
export function deltaTattici(lineup, assettoMio, assettoAvv) {
  const delta = new Map();
  const linea = ASSI.linea[assettoMio.linea];
  const costruzione = ASSI.costruzione[assettoMio.costruzione];

  // 1. INTERPRETI: quanto i miei uomini sanno fare quello che chiedo
  for (const richiesta of [linea, costruzione]) {
    if (!richiesta.attributo) continue;
    for (let i = 0; i < lineup.titolari.length; i++) {
      const g = lineup.titolari[i];
      const slot = lineup.slots[i];
      if (!g || slot === 'GK') continue;
      if (!richiesta.reparti.includes(REPARTO[slot])) continue;
      const punti = SCALE.INTERPRETI * (idoneita(g, richiesta.attributo) - 0.5) * 2;
      delta.set(g.id, (delta.get(g.id) ?? 0) + punti);
    }
  }

  // 2. CONTRASTO: quanto il mio assetto regge contro il suo.
  // La mia costruzione contro la sua linea difensiva mi aiuta in attacco;
  // la sua costruzione contro la mia linea mi penalizza in difesa.
  const vantaggioMioAttacco = CONTRASTI[assettoMio.costruzione][assettoAvv.linea];
  const vantaggioSuoAttacco = CONTRASTI[assettoAvv.costruzione][assettoMio.linea];
  for (let i = 0; i < lineup.titolari.length; i++) {
    const g = lineup.titolari[i];
    const slot = lineup.slots[i];
    if (!g || slot === 'GK') continue;
    const rep = REPARTO[slot];
    let punti = 0;
    if (rep === 'ATT') punti += SCALE.COUNTER * vantaggioMioAttacco;
    if (rep === 'DEF') punti -= SCALE.COUNTER * vantaggioSuoAttacco;
    if (punti) delta.set(g.id, (delta.get(g.id) ?? 0) + punti);
  }

  return delta;
}

/**
 * Copia della rosa con gli overall gia' spostati dalle tattiche. Copia e non
 * mutazione: la stessa rosa viene riusata in confronti diversi, e mutarla
 * significherebbe accumulare gli effetti di una prova sulla successiva —
 * un errore che falserebbe tutte le misure a valle senza dare segnale.
 */
export function rosaConTattiche(rosa, lineup, assettoMio, assettoAvv) {
  const delta = deltaTattici(lineup, assettoMio, assettoAvv);
  return {
    ...rosa,
    giocatori: rosa.giocatori.map((g) => {
      const d = delta.get(g.id);
      return d ? { ...g, ovr: clamp(Math.round(g.ovr + d), 40, 99) } : g;
    }),
  };
}

/** Tutti gli assetti possibili: 3 linee x 3 costruzioni. */
export function tuttiGliAssetti() {
  const out = [];
  for (const linea of Object.keys(ASSI.linea)) {
    for (const costruzione of Object.keys(ASSI.costruzione)) {
      out.push({ linea, costruzione });
    }
  }
  return out;
}

export function etichetta(a) {
  return `${ASSI.linea[a.linea].etichetta} + ${ASSI.costruzione[a.costruzione].etichetta}`;
}

/** Rosa con interpreti scelti apposta (o apposta sbagliati) per un assetto. */
export function sbilanciaInterpreti(rosa, attributo, verso) {
  if (!attributo) return rosa;
  return {
    ...rosa,
    giocatori: rosa.giocatori.map((g) => ({
      ...g,
      [attributo]: clamp(Math.round(g[attributo] + verso * (18 + rnd() * 8)), 20, 99),
    })),
  };
}
