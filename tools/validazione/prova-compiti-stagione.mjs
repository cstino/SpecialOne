import { simulaPartita, schiera } from '/Users/cristianobraccili/SpecialOne/engine/engine.js';
import { creaRosaPerModulo, setSeed } from '/Users/cristianobraccili/SpecialOne/tools/validazione/roster.js';
import { MODULI } from '/Users/cristianobraccili/SpecialOne/engine/config.js';
const M = MODULI['4-4-2'];
const GIORNATE = 30, STAGIONI = 500;

// Una stagione vera: la condizione si porta dietro fra una giornata e l'altra,
// quindi il conto del pressing si paga nel tempo e non nei novanta minuti.
function stagione(pressa, staminaST) {
  let punti = 0, gf = 0, gs = 0, condFinale = 0;
  for (let s = 0; s < STAGIONI; s++) {
    setSeed(1000 + s);
    const ra = creaRosaPerModulo('A', 74, M);
    ra.esperienzaModulo = { '4-4-2': 5 };
    if (staminaST) ra.giocatori.forEach((g) => { if (g.slotNat === 'ST') g.stamina = staminaST });
    for (let g = 0; g < GIORNATE; g++) {
      const rb = creaRosaPerModulo('B', 74, M);
      rb.esperienzaModulo = { '4-4-2': 5 };
      const A = schiera(ra, '4-4-2'), B = schiera(rb, '4-4-2');
      if (pressa) A.compiti = M.map((x) => (x === 'ST' ? 'difesa' : null));
      const r = simulaPartita(ra, rb, '4-4-2', '4-4-2', { usaCondizione: true, lineupCasa: A, lineupOspite: B });
      punti += r.golC > r.golO ? 3 : r.golC === r.golO ? 1 : 0;
      gf += r.golC; gs += r.golO;
    }
    const st = ra.giocatori.filter((g) => g.slotNat === 'ST');
    condFinale += st.reduce((a, g) => a + g.condizione, 0) / st.length;
  }
  const n = STAGIONI;
  return { punti: punti / n / GIORNATE * 38, gf: gf / n / GIORNATE, gs: gs / n / GIORNATE, cond: condFinale / n };
}
console.log(`  Stagione da ${GIORNATE} giornate, ${STAGIONI} ripetizioni. Punti normalizzati su 38.\n`);
console.log(`  ${'punte'.padEnd(26)} ${'punti/38'.padStart(9)} ${'fatti'.padStart(7)} ${'subiti'.padStart(7)} ${'cond.fine'.padStart(10)}`);
for (const [et, p, st] of [
  ['stamina media, neutro', false, null],
  ['stamina media, pressing', true, null],
  ['stamina 90, pressing', true, 90],
  ['stamina 55, pressing', true, 55],
]) {
  const r = stagione(p, st);
  console.log(`  ${et.padEnd(26)} ${r.punti.toFixed(1).padStart(9)} ${r.gf.toFixed(2).padStart(7)} ${r.gs.toFixed(2).padStart(7)} ${r.cond.toFixed(1).padStart(10)}`);
}
