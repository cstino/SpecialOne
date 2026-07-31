// ============================================================
//  MOTORE DI SIMULAZIONE — MODELLO A BLOCCHI
// ============================================================

import { CFG, MODULI, CONTEGGI, PESI_SLOT, REPARTO, penalitaRuolo, pesoStat } from './config.js';
import { rnd, gauss, poisson, scegliPesato } from './random.js';

const clamp = (v, a, b) => Math.max(a, Math.min(b, v));

// ---------- Overall efficace ----------

export function fattoreCondizione(c) {
  if (c >= 85) return 1.000;
  if (c >= 70) return 0.975;
  if (c >= 55) return 0.940;
  if (c >= 40) return 0.890;
  return 0.820;
}

export function ovrEfficace(g, slot) {
  const repSlot = REPARTO[slot];
  const repNat = REPARTO[g.posizioni[0]];
  let base;

  if (repSlot === 'GK' && repNat !== 'GK') base = Math.min(45, g.ovr * 0.45);
  else if (repSlot !== 'GK' && repNat === 'GK') base = Math.min(48, g.ovr * 0.50);
  else if (repSlot === 'GK' && repNat === 'GK') base = g.ovr;
  else base = g.ovr * penalitaRuolo(g.posizioni, slot);

  return base * fattoreCondizione(g.condizione);
}

// ---------- Assegnazione giocatori -> slot (greedy) ----------

export function schiera(rosa, modulo) {
  const slots = MODULI[modulo];
  const disponibili = rosa.giocatori.filter(g => g.infortunatoFinoA <= 0);

  const coppie = [];
  for (let s = 0; s < slots.length; s++)
    for (const g of disponibili)
      coppie.push({ s, g, val: ovrEfficace(g, slots[s]) });
  coppie.sort((a, b) => b.val - a.val);

  const titolari = new Array(slots.length).fill(null);
  const usati = new Set();
  for (const c of coppie) {
    if (titolari[c.s] || usati.has(c.g.id)) continue;
    titolari[c.s] = c.g;
    usati.add(c.g.id);
    if (usati.size === slots.length) break;
  }

  const panchina = disponibili.filter(g => !usati.has(g.id))
    .sort((a, b) => b.ovr - a.ovr).slice(0, 9);

  return { modulo, slots, titolari, panchina, cambiFatti: 0 };
}

// ---------- Forze di linea ----------

export function forzeLinee(lineup) {
  const acc = { DEF: [0, 0], MID: [0, 0], ATT: [0, 0] };
  let gk = 60;
  for (let i = 0; i < lineup.slots.length; i++) {
    const slot = lineup.slots[i], g = lineup.titolari[i];
    if (!g) continue;
    const eff = ovrEfficace(g, slot);
    if (slot === 'GK') { gk = eff; continue; }
    const w = PESI_SLOT[slot];
    for (const L of ['DEF', 'MID', 'ATT']) { acc[L][0] += eff * w[L]; acc[L][1] += w[L]; }
  }
  return {
    DEF: acc.DEF[1] ? acc.DEF[0] / acc.DEF[1] : 60,
    MID: acc.MID[1] ? acc.MID[0] / acc.MID[1] : 60,
    ATT: acc.ATT[1] ? acc.ATT[0] / acc.ATT[1] : 60,
    GK: gk,
    wDEF: acc.DEF[1], wMID: acc.MID[1], wATT: acc.ATT[1],
  };
}

// monte-pesi del 4-3-3, usato come baseline strutturale
export const BASELINE = (() => {
  const acc = { DEF: 0, MID: 0, ATT: 0 };
  for (const slot of MODULI['4-3-3']) {
    if (slot === 'GK') continue;
    const w = PESI_SLOT[slot];
    for (const L of ['DEF', 'MID', 'ATT']) acc[L] += w[L];
  }
  return acc;
})();

// bonus/malus strutturale in punti di overall
export function strutturale(f) {
  const k = CFG.K_STRUTTURA, c = CFG.STRUTT_CLAMP;
  return {
    DEF: clamp(k * (f.wDEF - BASELINE.DEF), -c, c),
    MID: clamp(k * (f.wMID - BASELINE.MID), -c, c),
    ATT: clamp(k * (f.wATT - BASELINE.ATT), -c, c),
  };
}

// ---------- Counter moduli (centrato: 4-3-3 vs 4-3-3 = 0) ----------

// mantenuta solo per ispezione/debug: mostra lo scarto strutturale tra due moduli
export function counter(modA, modB) {
  const mk = (m) => {
    const acc = { DEF: 0, MID: 0, ATT: 0 };
    for (const s of MODULI[m]) { if (s === 'GK') continue; const w = PESI_SLOT[s]; for (const L of ['DEF','MID','ATT']) acc[L] += w[L]; }
    return strutturale({ wDEF: acc.DEF, wMID: acc.MID, wATT: acc.ATT });
  };
  const a = mk(modA), b = mk(modB);
  return { attA: a.ATT, midA: a.MID, defA: a.DEF, scartoAttDif: a.ATT - b.DEF, scartoMid: a.MID - b.MID };
}

// malus in PUNTI di overall: -3.5 alla prima partita, 0 dopo 15
export function familiarita(rosa, modulo) {
  const n = rosa.esperienzaModulo[modulo] || 0;
  return -CFG.FAM_MALUS_MAX * (1 - Math.min(1, n / CFG.FAM_PARTITE_PIENA));
}

// ---------- Sostituzioni automatiche ----------

function sostituzioni(lineup) {
  if (lineup.cambiFatti >= CFG.MAX_CAMBI) return;
  let fatti = 0;
  for (let i = 0; i < lineup.slots.length && fatti < CFG.MAX_CAMBI_FINESTRA; i++) {
    const slot = lineup.slots[i], tit = lineup.titolari[i];
    if (!tit || tit.condizione >= CFG.SOGLIA_CAMBIO_COND) continue;
    let bestIdx = -1, bestVal = ovrEfficace(tit, slot);
    for (let j = 0; j < lineup.panchina.length; j++) {
      const v = ovrEfficace(lineup.panchina[j], slot);
      if (v > bestVal) { bestVal = v; bestIdx = j; }
    }
    if (bestIdx >= 0) {
      const entra = lineup.panchina.splice(bestIdx, 1)[0];
      lineup.titolari[i] = entra;
      entra._entrato = true;
      lineup.cambiFatti++; fatti++;
      if (lineup.cambiFatti >= CFG.MAX_CAMBI) return;
    }
  }
}

// ---------- Statistiche individuali ----------

function distribuisci(lineup, tipo, totale, attributo) {
  const out = new Map();
  const pesi = [], gio = [];
  for (let i = 0; i < lineup.slots.length; i++) {
    const g = lineup.titolari[i];
    if (!g) continue;
    gio.push(g);
    pesi.push(pesoStat(tipo, lineup.slots[i]) * (g[attributo] / 100));
  }
  const tot = pesi.reduce((a, b) => a + b, 0) || 1;
  for (let i = 0; i < gio.length; i++) {
    const q = Math.round(totale * pesi[i] / tot);
    out.set(gio[i].id, (out.get(gio[i].id) || 0) + q);
  }
  return out;
}

function marcatori(lineup, nGol) {
  const gio = [], pesi = [];
  for (let i = 0; i < lineup.slots.length; i++) {
    const g = lineup.titolari[i];
    if (!g || lineup.slots[i] === 'GK') continue;
    gio.push(g);
    pesi.push(PESI_SLOT[lineup.slots[i]].ATT * Math.pow(g.finishing / 100, 1.5) + 0.001);
  }
  const res = [];
  for (let k = 0; k < nGol; k++) {
    const g = scegliPesato(gio, pesi);
    res.push(g);
    const ix = gio.indexOf(g);
    if (ix >= 0) pesi[ix] *= CFG.DAMPING_MARCATORE;
  }
  return res;
}

// ============================================================
//  SIMULAZIONE PARTITA
// ============================================================

export function simulaPartita(rosaCasa, rosaOspite, modCasa, modOspite, opt = {}) {
  const usaCondizione = opt.usaCondizione !== false;
  const lc = schiera(rosaCasa, modCasa);
  const lo = schiera(rosaOspite, modOspite);

  const famC = familiarita(rosaCasa, modCasa);
  const famO = familiarita(rosaOspite, modOspite);

  let golC = 0, golO = 0, xgTotC = 0, xgTotO = 0;
  const ctrlStorico = [];
  const inCampo = new Map(); // id -> blocchi giocati

  for (let b = 0; b < CFG.BLOCCHI_PARTITA; b++) {
    const fc = forzeLinee(lc), fo = forzeLinee(lo);

    // tutto in PUNTI di overall: bonus e malus sono additivi, non moltiplicativi
    const sc = strutturale(fc), so = strutturale(fo);
    const ATT_C = fc.ATT + sc.ATT + famC + CFG.BONUS_CASA_ATT;
    const MID_C = fc.MID + sc.MID + famC + CFG.BONUS_CASA_MID;
    const DEF_C = fc.DEF + sc.DEF;
    const ATT_O = fo.ATT + so.ATT + famO;
    const MID_O = fo.MID + so.MID + famO;
    const DEF_O = fo.DEF + so.DEF;

    const ctrlC = clamp(0.5 + CFG.AMPLIFICA_CONTROLLO * (MID_C - MID_O) / 100, CFG.CTRL_MIN, CFG.CTRL_MAX);
    const ctrlO = 1 - ctrlC;
    ctrlStorico.push(ctrlC);

    let xgC = CFG.XG_BASE_BLOCCO * (ctrlC / 0.5) * Math.exp(CFG.SENSIBILITA_FORZA * clamp(ATT_C - DEF_O, -CFG.DIFF_CLAMP, CFG.DIFF_CLAMP));
    let xgO = CFG.XG_BASE_BLOCCO * (ctrlO / 0.5) * Math.exp(CFG.SENSIBILITA_FORZA * clamp(ATT_O - DEF_C, -CFG.DIFF_CLAMP, CFG.DIFF_CLAMP));
    xgC *= (1 - (fo.GK - 75) / CFG.DIVISORE_PORTIERE);
    xgO *= (1 - (fc.GK - 75) / CFG.DIVISORE_PORTIERE);

    xgC = Math.max(0, xgC); xgO = Math.max(0, xgO);
    xgTotC += xgC; xgTotO += xgO;
    golC += poisson(xgC);
    golO += poisson(xgO);

    // consumo condizione + conteggio blocchi
    for (const L of [lc, lo]) {
      for (const g of L.titolari) {
        if (!g) continue;
        inCampo.set(g.id, (inCampo.get(g.id) || 0) + 1);
        if (usaCondizione) {
          g.condizione = Math.max(0, g.condizione - (CFG.CONSUMO_BASE - CFG.CONSUMO_MOD_STAMINA * (g.stamina / 100)));
        }
      }
    }

    if (CFG.FINESTRE_CAMBI.includes(b + 1)) { sostituzioni(lc); sostituzioni(lo); }
  }

  // ---------- statistiche ----------
  const ctrlMedio = ctrlStorico.reduce((a, b) => a + b, 0) / ctrlStorico.length;
  const mk = (lineup, gol, ctrl, forze, xgTot) => {
    const conv = clamp(gauss(CFG.CONVERSIONE_MEDIA, CFG.CONVERSIONE_SIGMA), 0.07, 0.17);
    const tiri = Math.max(gol, Math.round(xgTot / conv));
    const inPorta = Math.max(gol, Math.round(tiri * clamp(gauss(CFG.TIRI_PORTA_MEDIA, CFG.TIRI_PORTA_SIGMA), 0.15, 0.65)));
    const pTent = Math.round(CFG.PASSAGGI_BASE * ctrl * 2);
    const pPct = clamp(0.78 + 0.0025 * (forze.MID - 75), 0.62, 0.94);
    return {
      gol, tiri, inPorta,
      passaggiT: pTent, passaggiR: Math.round(pTent * pPct), passaggiPct: pPct,
      contrasti: Math.round(CFG.CONTRASTI_BASE * (1 - ctrl) * 2),
      dribbling: Math.round(CFG.DRIBBLING_BASE * ctrl * 2),
      possesso: ctrl,
    };
  };

  const sC = mk(lc, golC, ctrlMedio, forzeLinee(lc), xgTotC);
  const sO = mk(lo, golO, 1 - ctrlMedio, forzeLinee(lo), xgTotO);

  const perGiocatore = opt.statsGiocatori ? {
    casa: {
      tiri: distribuisci(lc, 'tiri', sC.tiri, 'finishing'),
      passaggi: distribuisci(lc, 'passaggi', sC.passaggiT, 'short_passing'),
      contrasti: distribuisci(lc, 'contrasti', sC.contrasti, 'tackle'),
      dribbling: distribuisci(lc, 'dribbling', sC.dribbling, 'dribbling'),
      marcatori: marcatori(lc, golC).map(g => g.nome),
    },
    ospite: {
      tiri: distribuisci(lo, 'tiri', sO.tiri, 'finishing'),
      passaggi: distribuisci(lo, 'passaggi', sO.passaggiT, 'short_passing'),
      contrasti: distribuisci(lo, 'contrasti', sO.contrasti, 'tackle'),
      dribbling: distribuisci(lo, 'dribbling', sO.dribbling, 'dribbling'),
      marcatori: marcatori(lo, golO).map(g => g.nome),
    },
  } : null;

  // ---------- recupero condizione + infortuni ----------
  if (usaCondizione) {
    for (const [rosa, L] of [[rosaCasa, lc], [rosaOspite, lo]]) {
      const inLineup = new Set(L.titolari.filter(Boolean).map(g => g.id));
      const inPanca = new Set(L.panchina.map(g => g.id));
      for (const g of rosa.giocatori) {
        if (g.infortunatoFinoA > 0) { g.infortunatoFinoA--; if (g.infortunatoFinoA === 0) g.condizione = 65; continue; }
        if (inLineup.has(g.id) || g._entrato) {
          g.condizione = Math.min(100, g.condizione + CFG.REC_GIOCATO);
          const modEta = g.eta < 24 ? 0.85 : g.eta <= 30 ? 1.0 : g.eta <= 33 ? 1.25 : 1.5;
          const p = CFG.INFORTUNIO_BASE * (1 + (100 - g.condizione) / CFG.INFORTUNIO_DIV_COND) * modEta;
          if (rnd() < p) {
            const r = rnd();
            g.infortunatoFinoA = r < 0.60 ? 1 + Math.floor(rnd() * 2)
                               : r < 0.90 ? 3 + Math.floor(rnd() * 4)
                               : 8 + Math.floor(rnd() * 8);
          }
        } else if (inPanca.has(g.id)) g.condizione = Math.min(100, g.condizione + CFG.REC_PANCHINA);
        else g.condizione = Math.min(100, g.condizione + CFG.REC_TRIBUNA);
        g._entrato = false;
      }
    }
  }

  rosaCasa.esperienzaModulo[modCasa] = (rosaCasa.esperienzaModulo[modCasa] || 0) + 1;
  rosaOspite.esperienzaModulo[modOspite] = (rosaOspite.esperienzaModulo[modOspite] || 0) + 1;

  return { golC, golO, statsCasa: sC, statsOspite: sO, perGiocatore };
}

// ---------- Calendario (metodo del cerchio) ----------

export function calendario(nSquadre, gironi) {
  const ids = [...Array(nSquadre).keys()];
  if (ids.length % 2) ids.push(-1); // riposo
  const n = ids.length, giornateGiro = n - 1;
  const giornate = [];
  let arr = [...ids];
  for (let g = 0; g < giornateGiro; g++) {
    const gg = [];
    for (let i = 0; i < n / 2; i++) {
      const a = arr[i], b = arr[n - 1 - i];
      if (a !== -1 && b !== -1) gg.push(g % 2 === 0 ? [a, b] : [b, a]);
    }
    giornate.push(gg);
    arr = [arr[0], arr[n - 1], ...arr.slice(1, n - 1)];
  }
  const tutte = [];
  for (let giro = 0; giro < gironi; giro++)
    for (const gg of giornate)
      tutte.push(giro % 2 === 0 ? gg : gg.map(([a, b]) => [b, a]));
  return tutte;
}
