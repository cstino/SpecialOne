// La forza di attacco e di difesa per corsia, e lo scontro speculare.
import { ovrEfficace } from './engine.js';
import { PESI_SLOT, PESI_CORSIA, pesiConCompito } from './config.js';
import { corsiaConRuolo, avanzamentoRuolo } from './ruoli.js';
export function forzeCorsia(lineup) {
  const att = { SX:[0,0], CEN:[0,0], DX:[0,0] }, dif = { SX:[0,0], CEN:[0,0], DX:[0,0] };
  for (let i=0;i<lineup.slots.length;i++) {
    const slot = lineup.slots[i], g = lineup.titolari[i];
    if (!g || slot === 'GK') continue;
    const eff = ovrEfficace(g, slot);
    const ruolo = lineup.ruoli?.[i];
    const wl = pesiConCompito(PESI_SLOT[slot], lineup.compiti?.[i], g, avanzamentoRuolo(ruolo), slot);
    const wc = corsiaConRuolo(PESI_CORSIA[slot], ruolo, g);
    for (const c of ['SX','CEN','DX']) {
      att[c][0] += eff * wl.ATT * wc[c]; att[c][1] += wl.ATT * wc[c];
      dif[c][0] += eff * wl.DEF * wc[c]; dif[c][1] += wl.DEF * wc[c];
    }
  }
  const m = (x) => x[1] ? x[0]/x[1] : 60;
  return { att: { SX:m(att.SX), CEN:m(att.CEN), DX:m(att.DX) },
           dif: { SX:m(dif.SX), CEN:m(dif.CEN), DX:m(dif.DX) },
           pesoAtt: { SX:att.SX[1], CEN:att.CEN[1], DX:att.DX[1] },
           pesoDif: { SX:dif.SX[1], CEN:dif.CEN[1], DX:dif.DX[1] } };
}

// ============================================================
//  DOVE ATTACCARE — lo scontro di corsia
//
//  La mia sinistra incontra la loro destra: e' cosi' che si guarda una
//  partita. Concentrare l'attacco su una fascia porta li' piu' peso, e rende
//  in proporzione a quanto quella fascia e' sguarnita dall'altra parte.
//
//  E' QUI CHE NASCE L'INTERAZIONE che ai compiti mancava (punto 13: leggere
//  l'avversario valeva +0,0). Non serve nessuna matrice inventata: il buco lo
//  crea l'avversario da solo, mandando avanti un terzino. Chi se ne accorge lo
//  attacca, chi non se ne accorge attacca dove c'e' gente.
// ============================================================
const SPECCHIO = { SX: 'DX', CEN: 'CEN', DX: 'SX' };

// Quanto pesa una corsia scoperta. Tarato a 40 perche' la vulnerabilita' e'
// una frazione piccola — mandare avanti un terzino scopre la sua fascia
// dell'11% — e va moltiplicata per arrivare a un effetto leggibile.
//
// Al valore scelto, indovinare la fascia sguarnita vale circa +8 punti
// percentuali di vittorie, cioe' poco piu' di un punto di overall; sbagliarla
// ne costa 2. Sopra, diventava una roulette: a 110 si passava dal 27% al 57%
// secondo dove si attaccava, e la partita la decideva la lettura invece della
// squadra.
export const SCALA_CORSIA = 20;
export const CONCENTRAZIONE = 0.35;

export function deltaCorsie(mio, suo, focus) {
  const fs = forzeCorsia(suo);
  // Il confronto e' con LORO STESSI a compiti neutri, non con la media fra le
  // corsie. Due correzioni in una:
  //
  //  - confrontare le corsie fra loro faceva punire SEMPRE il centro, che ha
  //    strutturalmente piu' difensori: attaccare in mezzo diventava un
  //    suicidio a prescindere, il che non e' calcio;
  //  - e soprattutto cosi' si misura esattamente cio' che l'avversario ha
  //    SCELTO di lasciare, che e' l'unica cosa che un allenatore puo' leggere.
  //    La sua forma di partenza non e' una sua colpa.
  // Il paragone e' l'avversario con se' stesso a compiti e ruoli neutri: cosi'
  // si isola quello che ha SCELTO di lasciare scoperto, invece di premiare la
  // corsia che in ogni modulo e' naturalmente piu' sguarnita. Anche i ruoli
  // vanno azzerati, non solo i compiti: schierare un terzino che rientra e'
  // una scelta tanto quanto spingerlo in avanti, e deve potersi leggere.
  const neutro = forzeCorsia({ ...suo, compiti: null, ruoli: null });
  const vulnerabilita = {};
  for (const c of ['SX', 'CEN', 'DX']) {
    const q = SPECCHIO[c];
    const base = neutro.pesoDif[q] || 1;
    vulnerabilita[c] = (base - fs.pesoDif[q]) / base;
  }

  // Concentrare paga in proporzione a quanto quella corsia e' sguarnita, e
  // costa se e' presidiata. Non concentrare non da' ne' toglie.
  const vant = { SX: 0, CEN: 0, DX: 0 };
  if (focus) {
    for (const c of ['SX', 'CEN', 'DX']) {
      vant[c] = (c === focus ? 1 : -0.35) * vulnerabilita[c];
    }
  }

  return (g, slot) => {
    if (!g || slot === 'GK') return 0;
    const wl = PESI_SLOT[slot], wc = PESI_CORSIA[slot];
    let somma = 0, peso = 0;
    for (const c of ['SX', 'CEN', 'DX']) {
      const w = wc[c] * (wl.ATT + 0.3);
      somma += vant[c] * w; peso += w;
    }
    return peso ? SCALA_CORSIA * (somma / peso) : 0;
  };
}
