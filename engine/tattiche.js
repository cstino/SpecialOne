// ============================================================
//  SISTEMA TATTICO
//
//  FUORI DAL NUCLEO VALIDATO NELLA FASE 0, come engine/rigori.js. Le formule
//  di engine.js (xG, controllo, modello strutturale dei moduli) non sono
//  toccate: questo modulo produce soltanto uno SCARTO IN PUNTI DI OVERALL per
//  ogni titolare, che engine.js somma all'overall prima di calcolare le forze
//  di linea. Senza un piano tattico lo scarto e' zero e il motore si comporta
//  esattamente come prima — verificabile rilanciando simulate.js.
//
//  L'IDEA, in una riga: una tattica non chiede giocatori PIU' FORTI, chiede
//  giocatori con un certo PROFILO.
//
//  Perche' e' questa la distinzione che conta (misure in leve-tattiche.sql):
//
//    tecnica da sola          correlazione con overall  0.70  -> travestito
//    tecnica MENO lotta       correlazione 0.09, ampiezza 32  -> leva vera
//
//  Chiedere "passaggi alti" significa chiedere giocatori piu' forti, perche' a
//  parita' di ruolo chi passa meglio ha anche l'overall piu' alto: non e' una
//  decisione. Chiedere uno SBILANCIAMENTO fra due qualita' e' una scelta vera,
//  perche' quello non si compra con l'overall — va cercato al draft e sul
//  mercato. L'esempio che ha corretto la prima stesura: Modric e Anguissa
//  hanno overall simili e profili opposti.
//
//  I PROFILI ESISTONO DENTRO LE ROSE VERE, non solo nel catalogo. Misurato su
//  29 rose umane di stagione 1 (profili-rose-vere.js, 11 settembre 2026):
//  ampiezza p10-p90 del profilo dentro una singola rosa 33-37 punti in tutti e
//  tre i reparti, correlazione con l'overall fra -0.27 e +0.18.
//
//  IL PREZZO DEL PIANO NON E' MODELLATO QUI, ed e' voluto. Schierare i quattro
//  difensori piu' veloci invece dei quattro piu' forti costa in media 3.9
//  punti di overall: lo applica gia' il motore da solo, perche' una difesa
//  veloce e debole ha un DEF piu' basso in forzeLinee(). Le scale qui sotto
//  vanno tenute sotto quel costo, altrimenti converrebbe a tutti schierare
//  velocisti a prescindere dall'avversario.
// ============================================================

import { REPARTO } from './config.js';

const clamp = (v, a, b) => Math.max(a, Math.min(b, v));

// ------------------------------------------------------------
//  SCALE — i numeri da tarare, tenuti in cima apposta.
//  Vincolo deciso con l'utente: la tattica perfetta contro quella sbagliata
//  deve valere MENO di 8 punti di overall, perche' a +8 il piu' forte vince
//  gia' l'84% (TEST 2 della Fase 0) e oltre quella soglia la tattica
//  conterebbe piu' della qualita' della rosa. Misurato: 4.0 punti.
// ------------------------------------------------------------
export const SCALE = {
  INTERPRETI: 3.5,   // avere il profilo giusto per il proprio piano
  CONTRASTO: 3.0,    // indovinare il piano contro quello avversario
  SNATURAMENTO: 2.0, // costo per ogni asse in cui ci si allontana dall'identita'
};

// Quanto sbilanciamento serve per essere "l'interprete perfetto". 25 punti di
// tilt corrispondono a circa il 90esimo percentile dentro una rosa vera.
const TILT_PIENO = 25;

// ------------------------------------------------------------
//  I DUE PROFILI, calcolati dagli attributi FC 26.
//  Entrambi sono DIFFERENZE, non valori assoluti: e' questo che li rende
//  indipendenti dall'overall.
// ------------------------------------------------------------
const n = (a, k) => Number(a?.[k] ?? 0);

/** positivo = regista tecnico, negativo = mediano di lotta */
export function tiltTecnico(attributi) {
  const tecnica = (n(attributi, 'short_passing') + n(attributi, 'skill_long_passing')
    + n(attributi, 'mentality_vision') + n(attributi, 'skill_ball_control')) / 4;
  const lotta = (n(attributi, 'power_strength') + n(attributi, 'standing_tackle')
    + n(attributi, 'mentality_interceptions') + n(attributi, 'mentality_aggression')) / 4;
  return tecnica - lotta;
}

/** positivo = rapido e leggero, negativo = lento e possente */
export function tiltRapido(attributi) {
  return n(attributi, 'pace') - n(attributi, 'physic');
}

export const PROFILI = {
  tecnico: (g) => g.tiltTecnico,
  rapido: (g) => g.tiltRapido,
};

// ------------------------------------------------------------
//  I DUE ASSI. Ogni opzione chiede UN profilo a UN reparto: e' cio' che
//  rende leggibile la scelta ("mi serve una difesa veloce") e misurabile
//  l'effetto. Le opzioni neutre non chiedono niente — e per questo sono
//  volutamente le piu' deboli: avere un piano batte non averlo.
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

export const PIANO_NEUTRO = { linea: 'media', costruzione: 'mista' };

// ------------------------------------------------------------
//  IL TRIANGOLO — come questi assetti si contrastano.
//  Valore = vantaggio di CHI ATTACCA in quel confronto.
//
//  Due regole imparate sbagliando, in questo ordine:
//
//  1. ogni riga e ogni colonna devono contenere almeno un valore sfavorevole.
//     Nella prima stesura la colonna "bassa" era tutta negativa, il blocco
//     basso non veniva punito da nessuno e la morra cinese era solo apparente.
//
//  2. le righe devono anche SOMMARE A ZERO. Con corta a -0.3 e verticale a
//     +0.2, verticalizzare rendeva in media contro un campo uniforme:
//     conveniva sempre, a prescindere dall'avversario, e l'assetto migliore in
//     assoluto catturava quasi tutto il valore del leggere la partita.
//
//  Matrice antisimmetrica: quello che una riga guadagna contro un assetto, lo
//  perde contro l'altro.
// ------------------------------------------------------------
const CONTRASTI = {
  //            linea alta   media    bassa
  corta:     { alta: -1.0, media: 0, bassa: +1.0 },
  mista:     { alta:  0,   media: 0, bassa:  0   },
  verticale: { alta: +1.0, media: 0, bassa: -1.0 },
};

/** Quanto un giocatore e' adatto a cio' che il piano chiede, da -1 a +1. */
function idoneita(g, richiesta) {
  if (!richiesta.profilo) return 0;
  const tilt = PROFILI[richiesta.profilo](g);
  if (typeof tilt !== 'number' || !Number.isFinite(tilt)) return 0;
  return clamp((tilt * richiesta.verso) / TILT_PIENO, -1, 1);
}

function valido(piano) {
  return !!(piano && ASSI.linea[piano.linea] && ASSI.costruzione[piano.costruzione]);
}

/**
 * Costruisce lo scarto tattico in punti di overall, dato il piano scelto per
 * questa partita, quello avversario e l'identita' di squadra.
 *
 * Restituisce una FUNZIONE (giocatore, slot) -> punti, non una mappa sui soli
 * titolari. La differenza conta: le sostituzioni confrontano un titolare con
 * chi e' in panchina, e con una mappa sui titolari un panchinaro adatto al
 * piano non verrebbe mai valorizzato. Cosi' invece chi entra e' giudicato con
 * lo stesso metro di chi esce.
 *
 * Se uno dei due piani manca o e' malformato restituisce null, e il motore si
 * comporta esattamente come senza tattiche.
 */
export function deltaTattico(piano, pianoAvv, identita) {
  if (!valido(piano) || !valido(pianoAvv)) return null;

  const perReparto = { DEF: 0, MID: 0, ATT: 0 };

  // 1. CONTRASTO — il mio attacco contro la sua linea, e viceversa.
  // Non dipende dal singolo giocatore: e' un bonus di reparto.
  perReparto.ATT += SCALE.CONTRASTO * CONTRASTI[piano.costruzione][pianoAvv.linea];
  perReparto.DEF -= SCALE.CONTRASTO * CONTRASTI[pianoAvv.costruzione][piano.linea];

  // 2. SNATURAMENTO — un asse fuori dall'identita' costa a tutta la squadra.
  // E' cio' che rende la domanda interessante: conviene tradirmi per il
  // contrasto giusto, o restare me stesso e vincere sui miei punti di forza?
  if (valido(identita)) {
    const assiFuori = (piano.linea !== identita.linea ? 1 : 0)
      + (piano.costruzione !== identita.costruzione ? 1 : 0);
    if (assiFuori) {
      for (const rep of ['DEF', 'MID', 'ATT']) perReparto[rep] -= SCALE.SNATURAMENTO * assiFuori;
    }
  }

  // 3. INTERPRETI — questo si', dipende dal giocatore: solo i reparti a cui il
  // piano chiede un profilo, e solo nella misura in cui quel giocatore ce l'ha.
  const richieste = [ASSI.linea[piano.linea], ASSI.costruzione[piano.costruzione]]
    .filter((r) => r.profilo);

  return (g, slot) => {
    // Il portiere resta fuori dal sistema tattico: nel motore non entra nelle
    // forze di reparto, ci arriva solo col suo moltiplicatore sull'xG.
    if (!g || slot === 'GK') return 0;
    const rep = REPARTO[slot];
    let punti = perReparto[rep] ?? 0;
    for (const r of richieste) {
      if (r.reparto === rep) punti += SCALE.INTERPRETI * idoneita(g, r);
    }
    return punti;
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
