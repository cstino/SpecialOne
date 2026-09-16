// ============================================================
//  LE TATTICHE DENTRO IL MOTORE AZIONE PER AZIONE
//
//  Stessi quattro test di accettazione di simulate-tattiche.js, cosi' i numeri
//  si possono mettere accanto a quelli del sistema integrato:
//
//     scarto fra gli assetti schierati      2.1 punti percentuali
//     leggere l'avversario contro assetto fisso   7.5x
//     confronto piu' squilibrato            4.3 punti di overall
//     identita': adattarsi di un asse       35.8% contro 25.1% e 25.3%
//
//  La domanda non e' "funziona" ma "funziona MEGLIO". Se i numeri non
//  migliorano, vince il sistema semplice che gia' gira in produzione.
// ============================================================
import { readFileSync } from 'fs';
import { simulaAzioni, creaSquadraReale, ASSETTI } from './motore-azioni.mjs';
import { setSeed } from './roster.js';
import { MODULI } from '../../engine/config.js';

const pool = JSON.parse(readFileSync(new URL('./pool-reale.json', import.meta.url)));
const N = Number(process.env.N || 700);
const OVR = 74;

const assetti = [];
for (const l of Object.keys(ASSETTI.linea)) for (const c of Object.keys(ASSETTI.costruzione)) assetti.push({ linea: l, costruzione: c });
const nome = (a) => `${a.linea}+${a.costruzione}`;
const schierato = (a) => a.linea !== 'media' && a.costruzione !== 'mista';

function serie(pA, pB, opt = {}) {
  setSeed(opt.seme ?? 31337);
  let v = 0;
  for (let i = 0; i < N; i++) {
    const A = creaSquadraReale(pool, MODULI['4-3-3'], opt.ovrA ?? OVR, 'A');
    const B = creaSquadraReale(pool, MODULI['4-3-3'], opt.ovrB ?? OVR, 'B');
    const r = simulaAzioni(A, B, { campoNeutro: true, pianoCasa: pA, pianoOspite: pB });
    if (r.golC > r.golO) v++;
  }
  return 100 * v / N;
}

// Ponte fra percentuali e punti di overall, rimisurato adesso sul prototipo.
const scala = [0, 2, 4, 6, 8].map((g) => ({ g, v: serie(null, null, { ovrA: OVR + g/2, ovrB: OVR - g/2, seme: 77 }) }));
function inPunti(pct) {
  let best = scala[0];
  for (const p of scala) if (Math.abs(p.v - pct) < Math.abs(best.v - pct)) best = p;
  const i = scala.indexOf(best);
  const alt = scala[pct > best.v ? Math.min(i+1, scala.length-1) : Math.max(i-1, 0)];
  if (alt === best || alt.v === best.v) return best.g;
  return best.g + (pct - best.v) * (alt.g - best.g) / (alt.v - best.v);
}

console.log(`\n  TATTICHE NEL MOTORE AZIONE PER AZIONE — ${N} partite per confronto, campo neutro\n`);
console.log('  scala: ' + scala.map((p) => `+${p.g}=${p.v.toFixed(0)}%`).join('  ') + '\n');

// --- A: nessun assetto deve convenire sempre ---
const medie = assetti.map((a) => ({ a, m: assetti.reduce((s, b) => s + serie(a, b), 0) / assetti.length }));
medie.sort((x, y) => y.m - x.m);
console.log('  A — media contro tutti gli assetti');
for (const r of medie) console.log(`    ${nome(r.a).padEnd(22)} ${r.m.toFixed(1)}%`);
const sch = medie.filter((r) => schierato(r.a));
const spread = sch[0].m - sch[sch.length - 1].m;
console.log(`\n    scarto fra i soli assetti schierati: ${spread.toFixed(1)} pp   (sistema integrato: 2.1)`);

// --- B: leggere l'avversario ---
const migliore = sch[0].a;
const cieco = sch.reduce((s, r) => s + serie(migliore, r.a), 0) / sch.length;
let informato = 0;
for (const r of sch) {
  let best = -1;
  for (const a of assetti) best = Math.max(best, serie(a, r.a));
  informato += best;
}
informato /= sch.length;
console.log(`\n  B — alla cieca ${cieco.toFixed(1)}%  ·  informato ${informato.toFixed(1)}%`);
const gCieco = Math.max(0.1, cieco - 50 + spread), gInf = informato - cieco;
console.log(`    guadagno del leggere l'avversario: +${gInf.toFixed(1)} pp`);
console.log(`    guadagno dell'assetto migliore:    +${spread.toFixed(1)} pp`);
console.log(`    rapporto: ${(gInf / Math.max(0.1, spread)).toFixed(1)}x   (sistema integrato: 7.5x)`);

// --- confronto piu' squilibrato ---
let peggio = { v: -1, a: assetti[0], b: assetti[0] };
for (const a of assetti) for (const b of assetti) {
  const v = serie(a, b);
  if (v > peggio.v) peggio = { v, a, b };
}
console.log(`\n  confronto piu' squilibrato: ${nome(peggio.a)} contro ${nome(peggio.b)} -> ${peggio.v.toFixed(1)}% = ${inPunti(peggio.v).toFixed(1)} punti di overall`);
console.log('    (sistema integrato: 4.3 punti; il tetto concordato e 8)');
