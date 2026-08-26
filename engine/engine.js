// ============================================================
//  MOTORE DI SIMULAZIONE — MODELLO A BLOCCHI
// ============================================================

import { CFG, MODULI, CONTEGGI, PESI_SLOT, REPARTO, STILI, penalitaRuolo, pesoStat } from './config.js';
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

// ---------- Stile di gioco ----------

// redistribuzione a somma zero in PUNTI di overall tra DEF/MID/ATT.
// 'equilibrato' o stile mancante/sconosciuto -> nessun aggiustamento.
export function stileTattico(stile) {
  return STILI[stile] || STILI.equilibrato;
}

// ---------- Sostituzioni automatiche ----------

function sostituzioni(lineup) {
  if (lineup.cambiFatti >= CFG.MAX_CAMBI) return;
  let fatti = 0;
  for (let i = 0; i < lineup.slots.length && fatti < CFG.MAX_CAMBI_FINESTRA; i++) {
    const slot = lineup.slots[i], tit = lineup.titolari[i];
    // Il portiere non si sostituisce per stanchezza: nel calcio vero esce solo
    // per infortunio. Col modello di fatica da partita scendeva sotto soglia
    // come tutti e veniva cambiato all'intervallo.
    if (slot === 'GK') continue;
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

// Un infortunio non aspetta il fischio finale: se c'e' una riserva e un cambio
// disponibile, il giocatore esce nello stesso slot e il cambio conta nei 5.
// A differenza del cambio per stanchezza, qui entra la migliore alternativa
// disponibile anche se non migliora l'overall dello slot.
function sostituisciInfortunato(lineup, slot) {
  if (lineup.cambiFatti >= CFG.MAX_CAMBI || !lineup.titolari[slot]) return null;
  let bestIdx = -1, bestVal = -Infinity;
  for (let j = 0; j < lineup.panchina.length; j++) {
    const valore = ovrEfficace(lineup.panchina[j], lineup.slots[slot]);
    if (valore > bestVal) { bestVal = valore; bestIdx = j; }
  }
  if (bestIdx < 0) return null;
  const esce = lineup.titolari[slot];
  const entra = lineup.panchina.splice(bestIdx, 1)[0];
  lineup.titolari[slot] = entra;
  entra._entrato = true;
  lineup.cambiFatti++;
  return { esce: esce.id, entra: entra.id };
}

function creaRngInfortuni(seme) {
  let stato = seme >>> 0;
  return () => { stato = (stato * 1664525 + 1013904223) >>> 0; return stato / 4294967296; };
}

function durataInfortunio(rng) {
  const r = rng();
  return r < 0.60 ? 1 + Math.floor(rng() * 2)
       : r < 0.90 ? 3 + Math.floor(rng() * 4)
       : 8 + Math.floor(rng() * 8);
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
  const lc = opt.lineupCasa || schiera(rosaCasa, modCasa);
  const lo = opt.lineupOspite || schiera(rosaOspite, modOspite);

  const famC = familiarita(rosaCasa, modCasa);
  const famO = familiarita(rosaOspite, modOspite);
  const stC = stileTattico(opt.stileCasa);
  const stO = stileTattico(opt.stileOspite);
  // Separato dal RNG dei gol: l'introduzione degli infortuni in partita non
  // deve cambiare lo stream validato di xG/gol. L'Edge Function passa il seed
  // della fixture; il fallback rende riproducibili anche i test standalone.
  const seedInfortuni = opt.seedInfortuni ?? ((rosaCasa.giocatori[0]?.id || 1) * 1103515245 + (rosaOspite.giocatori[0]?.id || 1));
  const rndInfortunio = creaRngInfortuni(seedInfortuni);
  // La condizione e' un valore persistente fra le giornate: il rischio della
  // gara parte da quella fotografata al calcio d'inizio, non dall'usura dei
  // singoli blocchi di questa stessa partita.
  for (const rosa of [rosaCasa, rosaOspite]) for (const g of rosa.giocatori) g._condizioneInizioPartita = g.condizione;

  let golC = 0, golO = 0, xgTotC = 0, xgTotO = 0;
  const ctrlStorico = [];
  const inCampo = new Map(); // id -> blocchi giocati
  const golPerBlocco = []; // solo bookkeeping: quanti gol cadono in quale blocco
  // Chi era davvero in campo in ciascun blocco, squadra per squadra: serve a
  // chi presenta la partita (Edge Function) per non attribuire un gol a un
  // giocatore che a quel blocco non era ancora entrato. Non influenza nessun
  // calcolo di questa funzione, e' solo dato esposto in piu'.
  const presenzeCasaPerBlocco = [];
  const presenzeOspitePerBlocco = [];
  const infortuniInPartita = [];

  // Supplementari (design §10.7): si aggiungono IN CORSA, solo se alla fine dei
  // regolamentari l'eliminatoria e' ancora in parita'. opt.scartoAndata e' il
  // vantaggio gia' maturato nell'andata dalla squadra che qui gioca in casa
  // (0 per una gara secca), cosi' la stessa condizione copre entrambi i casi.
  // Senza opt.supplementariSeParita il limite resta CFG.BLOCCHI_PARTITA e ogni
  // chiamata esistente si comporta esattamente come prima.
  let blocchiDaGiocare = CFG.BLOCCHI_PARTITA;
  let golRegolamentari = null;
  let supplementariGiocati = false;

  for (let b = 0; b < blocchiDaGiocare; b++) {
    const fc = forzeLinee(lc), fo = forzeLinee(lo);

    // tutto in PUNTI di overall: bonus e malus sono additivi, non moltiplicativi
    const sc = strutturale(fc), so = strutturale(fo);
    // Campo neutro (ultimo girone di un campionato a gironi dispari, vedi
    // Edge Function): azzera il fattore campo, non lo tocca per nessuno.
    // Flag opzionale, di default assente -> comportamento identico a prima
    // per ogni chiamata che non lo passa esplicitamente.
    const bonusCasaAtt = opt.campoNeutro ? 0 : CFG.BONUS_CASA_ATT;
    const bonusCasaMid = opt.campoNeutro ? 0 : CFG.BONUS_CASA_MID;
    const ATT_C = fc.ATT + sc.ATT + famC + bonusCasaAtt + stC.ATT;
    const MID_C = fc.MID + sc.MID + famC + bonusCasaMid + stC.MID;
    const DEF_C = fc.DEF + sc.DEF + stC.DEF;
    const ATT_O = fo.ATT + so.ATT + famO + stO.ATT;
    const MID_O = fo.MID + so.MID + famO + stO.MID;
    const DEF_O = fo.DEF + so.DEF + stO.DEF;

    const ctrlC = clamp(0.5 + CFG.AMPLIFICA_CONTROLLO * (MID_C - MID_O) / 100, CFG.CTRL_MIN, CFG.CTRL_MAX);
    const ctrlO = 1 - ctrlC;
    ctrlStorico.push(ctrlC);

    let xgC = CFG.XG_BASE_BLOCCO * (ctrlC / 0.5) * Math.exp(CFG.SENSIBILITA_FORZA * clamp(ATT_C - DEF_O, -CFG.DIFF_CLAMP, CFG.DIFF_CLAMP));
    let xgO = CFG.XG_BASE_BLOCCO * (ctrlO / 0.5) * Math.exp(CFG.SENSIBILITA_FORZA * clamp(ATT_O - DEF_C, -CFG.DIFF_CLAMP, CFG.DIFF_CLAMP));
    xgC *= (1 - (fo.GK - 75) / CFG.DIVISORE_PORTIERE);
    xgO *= (1 - (fc.GK - 75) / CFG.DIVISORE_PORTIERE);

    xgC = Math.max(0, xgC); xgO = Math.max(0, xgO);
    xgTotC += xgC; xgTotO += xgO;
    // stesse due estrazioni di prima, nello stesso ordine: qui vengono solo
    // trattenute per sapere in quale blocco e' caduto ogni gol
    const nGolC = poisson(xgC);
    const nGolO = poisson(xgO);
    golC += nGolC;
    golO += nGolO;
    golPerBlocco.push({ blocco: b + 1, casa: nGolC, ospite: nGolO });

    // consumo condizione + conteggio blocchi. Il portiere non consuma
    // condizione: nel calcio vero non si stanca come un giocatore di movimento,
    // resta stabile salvo infortuni (stesso spirito dell'esclusione dai cambi
    // per stanchezza, poco sopra).
    for (const [L, presenzeBlocco] of [[lc, presenzeCasaPerBlocco], [lo, presenzeOspitePerBlocco]]) {
      const idsBlocco = [];
      for (let i = 0; i < L.titolari.length; i++) {
        const g = L.titolari[i];
        if (!g) continue;
        inCampo.set(g.id, (inCampo.get(g.id) || 0) + 1);
        idsBlocco.push(g.id);
        if (usaCondizione && L.slots[i] !== 'GK') {
          g.condizione = Math.max(0, g.condizione - (CFG.CONSUMO_BASE - CFG.CONSUMO_MOD_STAMINA * (g.stamina / 100)));
        }
      }
      presenzeBlocco.push(idsBlocco);
    }

    // La probabilita' configurata e' per partita giocata. La distribuiamo sui
    // sei blocchi, usando la condizione reale maturata fino a questo momento:
    // un infortunio produce un cambio forzato prima dei cambi per stanchezza.
    if (usaCondizione) {
      for (const [lato, L] of [['casa', lc], ['ospite', lo]]) {
        for (let i = 0; i < L.titolari.length; i++) {
          const g = L.titolari[i];
          if (!g || L.cambiFatti >= CFG.MAX_CAMBI || L.panchina.length === 0) continue;
          const modEta = g.eta < 24 ? 0.85 : g.eta <= 30 ? 1.0 : g.eta <= 33 ? 1.25 : 1.5;
          const pPartita = CFG.INFORTUNIO_BASE * (1 + (100 - g._condizioneInizioPartita) / CFG.INFORTUNIO_DIV_COND) * modEta;
          if (rndInfortunio() >= pPartita / CFG.BLOCCHI_PARTITA) continue;
          const cambio = sostituisciInfortunato(L, i);
          if (!cambio) continue;
          g.infortunatoFinoA = durataInfortunio(rndInfortunio);
          g._nuovoInfortunio = true;
          infortuniInPartita.push({ lato, blocco: b + 1, ...cambio, giornate: g.infortunatoFinoA });
        }
      }
    }

    if (CFG.FINESTRE_CAMBI.includes(b + 1)) { sostituzioni(lc); sostituzioni(lo); }

    if (b + 1 === CFG.BLOCCHI_PARTITA) {
      golRegolamentari = { casa: golC, ospite: golO };
      if (opt.supplementariSeParita && (opt.scartoAndata || 0) + golC - golO === 0) {
        blocchiDaGiocare += CFG.BLOCCHI_SUPPLEMENTARI;
        supplementariGiocati = true;
        // Finestra di cambi extra concessa all'inizio dei supplementari, come
        // nel calcio vero. Resta soggetta a MAX_CAMBI: chi li ha gia' esauriti
        // non ne guadagna uno in piu'.
        sostituzioni(lc); sostituzioni(lo);
      }
    }
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

  const perGiocatore = opt.statsGiocatori ? (() => {
    const marcatoriCasa = marcatori(lc, golC);
    const marcatoriOspite = marcatori(lo, golO);
    const minuti = rosa => new Map(rosa.giocatori
      .map(g => [g.id, Math.round((inCampo.get(g.id) || 0) * 90 / CFG.BLOCCHI_PARTITA)])
      .filter(([, valore]) => valore > 0));
    return { casa: {
      tiri: distribuisci(lc, 'tiri', sC.tiri, 'finishing'),
      passaggi: distribuisci(lc, 'passaggi', sC.passaggiT, 'short_passing'),
      contrasti: distribuisci(lc, 'contrasti', sC.contrasti, 'tackle'),
      dribbling: distribuisci(lc, 'dribbling', sC.dribbling, 'dribbling'),
      minuti: minuti(rosaCasa),
      marcatori: marcatoriCasa.map(g => g.nome),
      marcatoriIds: marcatoriCasa.map(g => g.id),
    },
    ospite: {
      tiri: distribuisci(lo, 'tiri', sO.tiri, 'finishing'),
      passaggi: distribuisci(lo, 'passaggi', sO.passaggiT, 'short_passing'),
      contrasti: distribuisci(lo, 'contrasti', sO.contrasti, 'tackle'),
      dribbling: distribuisci(lo, 'dribbling', sO.dribbling, 'dribbling'),
      minuti: minuti(rosaOspite),
      marcatori: marcatoriOspite.map(g => g.nome),
      marcatoriIds: marcatoriOspite.map(g => g.id),
    },
  }; })() : null;

  // ---------- recupero condizione + infortuni ----------
  if (usaCondizione) {
    for (const [rosa, L] of [[rosaCasa, lc], [rosaOspite, lo]]) {
      const inLineup = new Set(L.titolari.filter(Boolean).map(g => g.id));
      const inPanca = new Set(L.panchina.map(g => g.id));
      for (const g of rosa.giocatori) {
        if (g.infortunatoFinoA > 0) {
          // Un infortunio avvenuto in questa gara non perde gia' una giornata
          // nel recupero immediatamente successivo al match.
          if (g._nuovoInfortunio) { g._nuovoInfortunio = false; continue; }
          g.infortunatoFinoA--; if (g.infortunatoFinoA === 0) g.condizione = 65; continue;
        }
        if (inLineup.has(g.id) || g._entrato) {
          g.condizione = Math.min(100, g.condizione + CFG.REC_GIOCATO);
        } else if (inPanca.has(g.id)) g.condizione = Math.min(100, g.condizione + CFG.REC_PANCHINA);
        else g.condizione = Math.min(100, g.condizione + CFG.REC_TRIBUNA);
        g._entrato = false;
      }
    }
  }

  rosaCasa.esperienzaModulo[modCasa] = (rosaCasa.esperienzaModulo[modCasa] || 0) + 1;
  rosaOspite.esperienzaModulo[modOspite] = (rosaOspite.esperienzaModulo[modOspite] || 0) + 1;
  for (const rosa of [rosaCasa, rosaOspite]) for (const g of rosa.giocatori) delete g._condizioneInizioPartita;

  return {
    golC, golO, statsCasa: sC, statsOspite: sO, perGiocatore, golPerBlocco,
    presenzePerBlocco: { casa: presenzeCasaPerBlocco, ospite: presenzeOspitePerBlocco },
    infortuniInPartita,
    // golC/golO sono il risultato FINALE (supplementari inclusi). Chi presenta
    // la partita ha qui anche il parziale dei 90', e se i supplementari sono
    // stati davvero giocati.
    golRegolamentari, supplementari: supplementariGiocati,
  };
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
