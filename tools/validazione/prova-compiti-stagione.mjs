import { simulaPartita, schiera } from '/Users/cristianobraccili/SpecialOne/engine/engine.js';
import { creaRosaPerModulo, setSeed } from '/Users/cristianobraccili/SpecialOne/tools/validazione/roster.js';
import { MODULI } from '/Users/cristianobraccili/SpecialOne/engine/config.js';
const M = MODULI['4-4-2'];
const GIORNATE = 30, STAGIONI = 400;

function stagione(slotBersaglio, compito) {
  let punti = 0, gf = 0, gs = 0, condRosa = 0, condXI = 0;
  for (let s = 0; s < STAGIONI; s++) {
    setSeed(2000 + s);
    // ENTRAMBE le rose vivono tutta la stagione. Rigenerare l'avversario fresco
    // a ogni giornata rendeva A sistematicamente la squadra stanca, e con quel
    // banco difendere valeva troppo e attaccare troppo poco.
    const ra = creaRosaPerModulo('A', 74, M);
    const rb = creaRosaPerModulo('B', 74, M);
    ra.esperienzaModulo = { '4-4-2': 5 };
    rb.esperienzaModulo = { '4-4-2': 5 };
    for (let g = 0; g < GIORNATE; g++) {
      const A = schiera(ra, '4-4-2'), B = schiera(rb, '4-4-2');
      if (compito) A.compiti = M.map((x) => (slotBersaglio.includes(x) ? compito : null));
      const r = simulaPartita(ra, rb, '4-4-2', '4-4-2', { usaCondizione: true, lineupCasa: A, lineupOspite: B });
      punti += r.golC > r.golO ? 3 : r.golC === r.golO ? 1 : 0;
      gf += r.golC; gs += r.golO;
      condXI += A.titolari.filter(Boolean).reduce((a, p) => a + p.condizione, 0) / 11;
    }
    condRosa += ra.giocatori.reduce((a, p) => a + p.condizione, 0) / ra.giocatori.length;
  }
  const n = STAGIONI;
  return { punti: punti / n / GIORNATE * 38, gf: gf / n / GIORNATE, gs: gs / n / GIORNATE,
           condRosa: condRosa / n, condXI: condXI / n / GIORNATE };
}
console.log(`  Stagione da ${GIORNATE} giornate, ${STAGIONI} ripetizioni. Punti su 38.\n`);
console.log(`  ${'compito'.padEnd(30)} ${'punti'.padStart(6)} ${'fatti'.padStart(6)} ${'subiti'.padStart(7)} ${'cond.XI'.padStart(8)} ${'cond.rosa'.padStart(10)}`);
const base = stagione([], null);
console.log(`  ${'(nessuno)'.padEnd(30)} ${base.punti.toFixed(1).padStart(6)} ${base.gf.toFixed(2).padStart(6)} ${base.gs.toFixed(2).padStart(7)} ${base.condXI.toFixed(1).padStart(8)} ${base.condRosa.toFixed(1).padStart(10)}`);
for (const [et, slots, c] of [
  ['difesa · Bloccato',        ['LB','RB','CB'], 'difesa'],
  ['difesa · Si sgancia',      ['LB','RB'],      'attacco'],
  ['centrocampo · In copertura',['CM'],          'difesa'],
  ['centrocampo · Si inserisce',['CM'],          'attacco'],
  ['attacco · Pressing alto',  ['ST'],           'difesa'],
  ['attacco · Sul filo',       ['ST'],           'attacco'],
]) {
  const r = stagione(slots, c);
  const d = r.punti - base.punti;
  console.log(`  ${et.padEnd(30)} ${r.punti.toFixed(1).padStart(6)} ${r.gf.toFixed(2).padStart(6)} ${r.gs.toFixed(2).padStart(7)} ${r.condXI.toFixed(1).padStart(8)} ${r.condRosa.toFixed(1).padStart(10)}   ${d >= 0 ? '+' : ''}${d.toFixed(1)}`);
}
