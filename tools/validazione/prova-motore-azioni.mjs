// Mette il prototipo azione-per-azione davanti ai bersagli della Fase 0.
// node tools/validazione/prova-motore-azioni.mjs
import { readFileSync } from 'fs';
import { simulaAzioni, creaSquadraReale, CFG } from './motore-azioni.mjs';
import { setSeed } from './roster.js';
import { MODULI } from '../../engine/config.js';

const pool = JSON.parse(readFileSync(new URL('./pool-reale.json', import.meta.url)));
const N = Number(process.env.N || 2000);
setSeed(20260916);

const BERSAGLI = [
  ['Gol per partita',        (s) => s.gol / s.n,                 2.50, 2.90],
  ['Vittorie casa %',        (s) => 100 * s.vc / s.n,            43.0, 47.0],
  ['Pareggi %',              (s) => 100 * s.pa / s.n,            23.0, 27.0],
  ['Vittorie ospite %',      (s) => 100 * s.vo / s.n,            28.0, 33.0],
  ['Tiri per squadra',       (s) => s.tiri / (2 * s.n),          11.0, 14.0],
  ['% passaggi riusciti',    (s) => 100 * s.pr / s.pt,           76.0, 88.0],
  ['Possesso casa %',        (s) => 100 * s.poss / s.n,          49.0, 54.0],
];

const s = { n: 0, gol: 0, vc: 0, vo: 0, pa: 0, tiri: 0, inPorta: 0, pt: 0, pr: 0, poss: 0 };
for (let i = 0; i < N; i++) {
  const casa = creaSquadraReale(pool, MODULI['4-3-3'], 74, 'Casa');
  const osp = creaSquadraReale(pool, MODULI['4-3-3'], 74, 'Ospite');
  const r = simulaAzioni(casa, osp);
  s.n++; s.gol += r.golC + r.golO;
  if (r.golC > r.golO) s.vc++; else if (r.golC < r.golO) s.vo++; else s.pa++;
  for (const lato of [r.casa, r.ospite]) { s.tiri += lato.tiri; s.inPorta += lato.inPorta; s.pt += lato.passaggiT; s.pr += lato.passaggiR; }
  s.poss += r.casa.possesso;
}

console.log(`\n  PROTOTIPO AZIONE PER AZIONE — ${N} partite, rose reali a OVR 74\n`);
let fuori = 0;
for (const [nome, f, lo, hi] of BERSAGLI) {
  const v = f(s);
  const ok = v >= lo && v <= hi;
  if (!ok) fuori++;
  console.log(`  ${nome.padEnd(24)} ${v.toFixed(2).padStart(7)}   target ${lo.toFixed(1)}–${hi.toFixed(1)}   ${ok ? 'OK' : 'FUORI'}`);
}
console.log(`  ${'Tiri in porta per squadra'.padEnd(24)} ${(s.inPorta/(2*s.n)).toFixed(2).padStart(7)}   (riferimento reale 4–5)`);
console.log(`  ${'Passaggi per squadra'.padEnd(24)} ${(s.pt/(2*s.n)).toFixed(0).padStart(7)}   (riferimento reale 400–550)`);
console.log(`\n  metriche fuori bersaglio: ${fuori} su ${BERSAGLI.length}\n`);

// ============================================================
//  ESITO DELLA PRIMA TARATURA — 16 settembre 2026
//
//  Tutte e sette le metriche d'insieme dentro il bersaglio, su 3000 partite
//  con rose reali a OVR 74.
//
//  E la curva di competitivita', che era la domanda vera (un motore realistico
//  in media ma piatto sarebbe inutile come gioco), combacia con quella della
//  Fase 0 entro due punti e mezzo a ogni gradino:
//
//     divario    questo motore    Fase 0
//        +0          38.6%          36%
//        +2          49.9%          48%
//        +4          62.8%          62%
//        +6          78.4%          76%
//        +8          85.8%          84%
//
//  LA COSTANTE CHE HA DECISO TUTTO e' SCALA_DUELLO. A 11 la curva schizzava al
//  93% a +8: in un motore azione per azione un piccolo vantaggio si moltiplica
//  per centinaia di duelli, e la squadra migliore vinceva sempre. Portarla a 15
//  appiattisce il singolo duello e riporta la curva dove deve stare. E' la
//  differenza fra un simulatore e un gioco.
// ============================================================
