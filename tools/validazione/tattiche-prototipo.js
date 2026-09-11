// ============================================================
//  PROTOTIPO DEL SISTEMA TATTICO — SOLO MISURA, NON E' IL GIOCO
//
//  Seconda stesura, 11 settembre 2026. La prima chiedeva alle tattiche un
//  ATTRIBUTO alto; l'utente l'ha smontata con un esempio (Modric contro
//  Anguissa: overall simili, profili opposti) e i dati gli hanno dato
//  ragione. Ora le tattiche chiedono un PROFILO, che e' tutt'altra cosa:
//
//    tecnica da sola          correlazione con overall  0.70  -> travestito
//    tecnica MENO lotta       correlazione 0.09, ampiezza 32  -> leva vera
//    rapidita MENO fisicita   correlazione ~0.00, ampiezza 40 -> leva vera
//                             (misurata in tutti e tre i reparti)
//
//  La differenza non e' accademica. Chiedere "passaggi alti" significa
//  chiedere giocatori piu' forti, perche' a parita' di ruolo chi passa
//  meglio ha anche l'overall piu' alto: non e' una decisione. Chiedere un
//  profilo e' una scelta vera, perche' il profilo NON si compra con
//  l'overall — va cercato.
//
//  COSA MISURA, e perche' non tocca engine/
//  Il motore validato riduce ogni giocatore a un numero (overall x
//  adattamento al ruolo x condizione) e non guarda mai gli attributi. Il
//  sistema definitivo dovra' cambiarlo, ma per misurarne le grandezze no:
//  qui le tattiche producono uno scarto in punti di overall applicato alle
//  rose PRIMA di chiamare simulaPartita(), cosi' xG, blocchi e sostituzioni
//  restano quelli validati.
//
//  I TRE INGREDIENTI dello scarto:
//    1. INTERPRETI  quanto i miei uomini hanno il profilo che chiedo
//    2. CONTRASTO   quanto il mio piano regge contro il suo
//    3. SNATURAMENTO quanto mi costa allontanarmi dalla mia identita'
//
//  Il terzo e' la novita' di questa stesura, e nasce dalla richiesta
//  dell'utente: una squadra ha una sua identita' (l'Inter gioca col 3-5-2
//  in un certo modo) e la prepara partita per partita senza stravolgerla.
//  Senza un costo, "conosco il contrasto giusto, lo applico" sarebbe
//  automatico e l'identita' finta.
// ============================================================

import { REPARTO } from '../../engine/config.js';
import { gauss } from '../../engine/random.js';

const clamp = (v, a, b) => Math.max(a, Math.min(b, v));

// ------------------------------------------------------------
//  SCALE — i numeri da tarare, tenuti in cima apposta.
//  Vincolo deciso con l'utente: la tattica perfetta contro quella sbagliata
//  deve valere MENO di 8 punti di overall, perche' a +8 il piu' forte vince
//  gia' l'84% (TEST 2 della Fase 0) e oltre quella soglia la tattica
//  conterebbe piu' della qualita' della rosa.
// ------------------------------------------------------------
export const SCALE = {
  INTERPRETI: 3.5,   // avere il profilo giusto per il proprio piano
  CONTRASTO: 3.0,    // indovinare il piano contro quello avversario
  SNATURAMENTO: 2.0, // costo per ogni asse in cui ci si allontana dall'identita'
};

// ------------------------------------------------------------
//  I DUE PROFILI, misurati sul catalogo vero (vedi leve-tattiche.sql).
//  Entrambi sono differenze, non valori assoluti: e' questo che li rende
//  indipendenti dall'overall.
// ------------------------------------------------------------
const DISPERSIONE = { tecnico: 16, rapido: 20 }; // dev.std che riproduce l'ampiezza misurata

export const PROFILI = {
  // positivo = regista, negativo = mediano/incontrista
  tecnico: (g) => g.tilt_tecnico,
  // positivo = rapido e leggero, negativo = lento e possente
  rapido: (g) => g.tilt_rapido,
};

// ------------------------------------------------------------
//  I DUE ASSI. Ogni opzione chiede UN profilo a UN reparto: e' cio' che
//  rende leggibile la scelta ("mi serve una difesa veloce") e misurabile
//  l'effetto. Le opzioni neutre non chiedono niente — e per questo, come
//  confermato dall'utente, sono volutamente le piu' deboli: avere un piano
//  batte non averlo.
// ------------------------------------------------------------
export const ASSI = {
  linea: {
    alta:  { etichetta: 'Difesa alta',   profilo: 'rapido',  verso: +1, reparto: 'DEF' },
    media: { etichetta: 'Linea media',   profilo: null },
    bassa: { etichetta: 'Blocco basso',  profilo: 'rapido',  verso: -1, reparto: 'DEF' },
  },
  costruzione: {
    corta:     { etichetta: 'Fitti passaggi', profilo: 'tecnico', verso: +1, reparto: 'MID' },
    mista:     { etichetta: 'Mista',          profilo: null },
    verticale: { etichetta: 'Verticalizza',   profilo: 'rapido',  verso: -1, reparto: 'ATT' },
  },
};

// ------------------------------------------------------------
//  IL TRIANGOLO — come questi assetti si contrastano nel calcio vero.
//  Valore = vantaggio di CHI ATTACCA in quel confronto.
//
//  Regola imparata dalla prima stesura: ogni riga e ogni colonna devono
//  contenere almeno un valore sfavorevole. Nella versione precedente la
//  colonna "bassa" era tutta negativa, il blocco basso non veniva punito da
//  nessuno, e la morra cinese era solo apparente.
// ------------------------------------------------------------
//  Seconda regola, emersa dalla misura dell'11 settembre: non basta che
//  ogni riga e ogni colonna contengano un valore sfavorevole, devono anche
//  SOMMARE A ZERO. Con corta a -0.3 e verticale a +0.2, verticalizzare
//  rendeva in media contro un campo uniforme: conveniva sempre, a
//  prescindere dall'avversario, e l'assetto migliore in assoluto catturava
//  quasi tutto il valore del leggere la partita (rapporto 1.4x).
//  Matrice antisimmetrica: quello che una riga guadagna contro un assetto,
//  lo perde contro l'altro.
const CONTRASTI = {
  //            linea alta   media    bassa
  corta:     { alta: -1.0, media: 0, bassa: +1.0 },
  mista:     { alta:  0,   media: 0, bassa:  0   },
  verticale: { alta: +1.0, media: 0, bassa: -1.0 },
};

// ------------------------------------------------------------
//  Profili sulle rose sintetiche. roster.js NON viene toccato: e' il
//  generatore della suite storica. I due tilt sono generati con la
//  dispersione misurata sul catalogo reale e SENZA correlazione con
//  l'overall — che e' esattamente la proprieta' che li rende leve.
// ------------------------------------------------------------
export function arricchisci(rosa) {
  for (const g of rosa.giocatori) {
    if (g.tilt_rapido !== undefined) continue;
    g.tilt_tecnico = clamp(Math.round(gauss(6, DISPERSIONE.tecnico)), -40, 45);
    g.tilt_rapido = clamp(Math.round(gauss(-4, DISPERSIONE.rapido)), -45, 40);
  }
  return rosa;
}

// Quanto un giocatore e' adatto a cio' che il piano chiede, da -1
// (esattamente il profilo sbagliato) a +1 (esattamente quello giusto).
function idoneita(g, richiesta) {
  if (!richiesta.profilo) return 0;
  const tilt = PROFILI[richiesta.profilo](g);
  if (typeof tilt !== 'number') return 0;
  return clamp((tilt * richiesta.verso) / 25, -1, 1);
}

/**
 * Scarto in punti di overall per ogni titolare, dato il piano scelto per
 * questa partita, quello avversario e la propria identita' di squadra.
 * Non muta nulla: restituisce una mappa id -> delta.
 */
export function deltaTattici(lineup, piano, pianoAvv, identita) {
  const delta = new Map();
  const aggiungi = (g, punti) => delta.set(g.id, (delta.get(g.id) ?? 0) + punti);

  const mieOpzioni = [ASSI.linea[piano.linea], ASSI.costruzione[piano.costruzione]];

  // 1. INTERPRETI — solo i reparti a cui il piano chiede qualcosa
  for (const richiesta of mieOpzioni) {
    if (!richiesta.profilo) continue;
    for (let i = 0; i < lineup.titolari.length; i++) {
      const g = lineup.titolari[i];
      const slot = lineup.slots[i];
      if (!g || slot === 'GK') continue;
      if (REPARTO[slot] !== richiesta.reparto) continue;
      aggiungi(g, SCALE.INTERPRETI * idoneita(g, richiesta));
    }
  }

  // 2. CONTRASTO — il mio attacco contro la sua linea, e viceversa
  const mioVantaggio = CONTRASTI[piano.costruzione][pianoAvv.linea];
  const suoVantaggio = CONTRASTI[pianoAvv.costruzione][piano.linea];
  for (let i = 0; i < lineup.titolari.length; i++) {
    const g = lineup.titolari[i];
    const slot = lineup.slots[i];
    if (!g || slot === 'GK') continue;
    const rep = REPARTO[slot];
    if (rep === 'ATT') aggiungi(g, SCALE.CONTRASTO * mioVantaggio);
    if (rep === 'DEF') aggiungi(g, -SCALE.CONTRASTO * suoVantaggio);
  }

  // 3. SNATURAMENTO — un asse fuori dall'identita' costa a tutta la squadra.
  // E' cio' che rende la domanda interessante: conviene tradirmi per il
  // contrasto giusto, o restare me stesso e vincere sui miei punti di forza?
  if (identita) {
    let assiFuori = 0;
    if (piano.linea !== identita.linea) assiFuori++;
    if (piano.costruzione !== identita.costruzione) assiFuori++;
    if (assiFuori) {
      for (let i = 0; i < lineup.titolari.length; i++) {
        const g = lineup.titolari[i];
        if (!g || lineup.slots[i] === 'GK') continue;
        aggiungi(g, -SCALE.SNATURAMENTO * assiFuori);
      }
    }
  }

  return delta;
}

/**
 * Copia della rosa con gli overall gia' spostati. Copia e non mutazione: la
 * stessa rosa viene riusata in confronti diversi, e mutarla accumulerebbe
 * gli effetti di una prova sulla successiva falsando tutto a valle.
 */
export function rosaConTattiche(rosa, lineup, piano, pianoAvv, identita) {
  const delta = deltaTattici(lineup, piano, pianoAvv, identita);
  return {
    ...rosa,
    giocatori: rosa.giocatori.map((g) => {
      const d = delta.get(g.id);
      return d ? { ...g, ovr: clamp(Math.round(g.ovr + d), 40, 99) } : g;
    }),
  };
}

/** Rosa costruita APPOSTA (o apposta male) per un profilo. */
export function rosaPerProfilo(rosa, richiesta, verso) {
  if (!richiesta.profilo) return rosa;
  const campo = richiesta.profilo === 'tecnico' ? 'tilt_tecnico' : 'tilt_rapido';
  return {
    ...rosa,
    giocatori: rosa.giocatori.map((g) => ({
      ...g,
      [campo]: clamp(g[campo] + verso * richiesta.verso * 22, -45, 45),
    })),
  };
}

export function tuttiGliAssetti() {
  const out = [];
  for (const linea of Object.keys(ASSI.linea)) {
    for (const costruzione of Object.keys(ASSI.costruzione)) out.push({ linea, costruzione });
  }
  return out;
}

export function etichetta(a) {
  return `${ASSI.linea[a.linea].etichetta} + ${ASSI.costruzione[a.costruzione].etichetta}`;
}
