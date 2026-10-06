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
export const SCALA_CORSIA = 3.5;
// Quanti punti di scarto fra la corsia scelta e la media delle tre valgono il
// vantaggio pieno. Era 4: nelle rose vere la corsia migliore supera la media di
// 0,8-1,4 punti in un caso tipico (raramente oltre 3), quindi nessuno arrivava
// a piu' di un quarto dell'effetto e la leva valeva +0,2 punti su 38. 1,5 e'
// lo scarto di una squadra con una corsia davvero piu' forte (registro, p. 36).
export const SCARTO_PIENO = 1.5;
export const CONCENTRAZIONE = 0.35;

// "Entrambe le fasce" (FASCE): la forza e' la media delle due fasce. Rispetto
// alla media delle tre corsie lo scarto e' la meta' di quello del centro a
// parita' di squilibrio, quindi il vantaggio pieno arriva a meta' scarto.
export const SCARTO_FASCE = SCARTO_PIENO / 2;
export function vantaggioCorsia(mio, focus) {
  if (!focus) return 0;
  const f = forzeCorsia({ ...mio, compiti: null, ruoli: null });
  const media = (f.att.SX + f.att.CEN + f.att.DX) / 3;
  if (focus === 'FASCE') return Math.max(-1, Math.min(1, ((f.att.SX + f.att.DX) / 2 - media) / SCARTO_FASCE));
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
  const scelte = focus === 'FASCE' ? ['SX', 'DX'] : [focus];
  for (const c of ['SX', 'CEN', 'DX']) vant[c] = (scelte.includes(c) ? 1 : -CONCENTRAZIONE) * v;
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
