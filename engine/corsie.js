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
//  DOVE ATTACCARE — il proprio lato forte
//
//  Registro, punto 27: la tattica e' l'identita' della squadra, non la mossa
//  della giornata. "Dove attacchiamo" non legge piu' il buco dell'avversario
//  (che andava riletto ogni giornata): guarda la PROPRIA squadra. Concentrare
//  l'attacco sulla corsia dove hai i giocatori piu' forti rende; sulla corsia
//  debole costa. Non concentrare non da' ne' toglie.
//
//  La forza di una corsia e' la media degli overall pesata per quanto ognuno
//  attacca li' (forzeCorsia): una MEDIA, non un totale, quindi il centro non
//  vince solo perche' ci stanno piu' giocatori.
// ============================================================

// Punti di overall, sugli attaccanti, a vantaggio pieno. Tarato nel sistema
// intero (task 4).
export const SCALA_CORSIA = 2.5;
// Quanti punti di scarto fra la corsia scelta e la media delle tre valgono il
// vantaggio pieno.
export const SCARTO_PIENO = 4;
export const CONCENTRAZIONE = 0.35;

export function vantaggioCorsia(mio, focus) {
  if (!focus) return 0;
  const f = forzeCorsia({ ...mio, compiti: null, ruoli: null });
  const media = (f.att.SX + f.att.CEN + f.att.DX) / 3;
  return Math.max(-1, Math.min(1, (f.att[focus] - media) / SCARTO_PIENO));
}

export function deltaCorsie(mio, focus) {
  if (!focus) return null;
  const v = vantaggioCorsia(mio, focus);
  if (!v) return null;
  // Chi attacca sulla corsia scelta ne raccoglie di piu', gli altri meno:
  // stessa distribuzione di prima, con il vantaggio che nasce dalla propria
  // squadra invece che dall'avversario.
  const vant = { SX: 0, CEN: 0, DX: 0 };
  for (const c of ['SX', 'CEN', 'DX']) vant[c] = (c === focus ? 1 : -CONCENTRAZIONE) * v;
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
