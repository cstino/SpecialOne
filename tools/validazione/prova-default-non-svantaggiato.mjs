// Il caso onesto: chi entra nella schermata, tocca le cose senza studiarle, e
// se ne va. Non il sabotaggio deliberato — quello nessuno lo fa.
import { simulaPartita, schiera } from '/Users/cristianobraccili/SpecialOne/engine/engine.js';
import { creaRosaPerModulo, setSeed, rnd } from '/Users/cristianobraccili/SpecialOne/tools/validazione/roster.js';
import { MODULI, COMPITI } from '/Users/cristianobraccili/SpecialOne/engine/config.js';
import { deltaMorale } from '/Users/cristianobraccili/SpecialOne/engine/morale.js';
import { deltaRuoli, sommaDelta, ruoliPerSlot } from '/Users/cristianobraccili/SpecialOne/engine/ruoli.js';
import { deltaCorsie } from '/Users/cristianobraccili/SpecialOne/engine/corsie.js';
const M = MODULI['4-4-2'], N = 12000;
const ruoliB = M.map((s) => (s === 'LB' ? 'terzino_interno' : null));
const scelta = (a) => a[Math.floor(rnd() * a.length)];

function prova(et, come) {
  setSeed(5511); let v = 0, p = 0;
  for (let i = 0; i < N; i++) {
    const ra = creaRosaPerModulo('A', 74, M), rb = creaRosaPerModulo('B', 74, M);
    ra.esperienzaModulo = { '4-4-2': 5 }; rb.esperienzaModulo = { '4-4-2': 5 };
    const A = schiera(ra, '4-4-2'), B = schiera(rb, '4-4-2');
    A.titolari.forEach((g) => { if (g) { g.morale = 70; g.composure = 60 } });
    B.titolari.forEach((g) => { if (g) { g.morale = 70; g.composure = 60 } });
    B.ruoli = ruoliB;
    let focus = null;
    if (come === 'caso') {
      A.ruoli = M.map((s) => { const l = ruoliPerSlot(s); return l.length ? scelta(l) : null });
      A.compiti = M.map(() => scelta(COMPITI));
      focus = scelta([null, 'SX', 'CEN', 'DX']);
    }
    A.tattica = sommaDelta(deltaMorale(A), deltaRuoli(A), deltaCorsie(A, B, focus));
    B.tattica = sommaDelta(deltaMorale(B), deltaRuoli(B), deltaCorsie(B, A, null));
    const r = simulaPartita(ra, rb, '4-4-2', '4-4-2', { usaCondizione: true, lineupCasa: A, lineupOspite: B });
    if (r.golC > r.golO) v++; else if (r.golC === r.golO) p++;
  }
  const punti = (v * 3 + p) / N * 38;
  console.log('  ' + et.padEnd(40) + (v/N*100).toFixed(1).padStart(5) + '%   ' + punti.toFixed(1).padStart(5) + ' punti/38');
  return punti;
}
const base = prova('lascia tutto predefinito', 'niente');
const caso = prova('tocca tutto a caso, senza studiarlo', 'caso');
console.log('\n  chi smanetta a caso rispetto a chi non tocca niente: ' + (caso - base >= 0 ? '+' : '') + (caso - base).toFixed(1) + ' punti');
