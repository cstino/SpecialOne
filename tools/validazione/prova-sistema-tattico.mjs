// Tutte le leve tattiche INSIEME, nella stessa composizione dell'Edge Function.
// Misurare i pezzi uno alla volta non dice come si comportano sommati.
import { simulaPartita, schiera } from '/Users/cristianobraccili/SpecialOne/engine/engine.js';
import { creaRosaPerModulo, setSeed } from '/Users/cristianobraccili/SpecialOne/tools/validazione/roster.js';
import { MODULI } from '/Users/cristianobraccili/SpecialOne/engine/config.js';
import { deltaMorale } from '/Users/cristianobraccili/SpecialOne/engine/morale.js';
import { deltaRuoli, sommaDelta } from '/Users/cristianobraccili/SpecialOne/engine/ruoli.js';
import { deltaCorsie } from '/Users/cristianobraccili/SpecialOne/engine/corsie.js';

const M = MODULI['4-4-2'];
const N = 12000;

// B lascia scoperta la fascia sinistra tenendo il terzino dentro: c'e' qualcosa
// da leggere, altrimenti le corsie non hanno niente da dire.
const ruoliB = M.map((s) => (s === 'LB' ? 'terzino_interno' : null));

function prova(et, cfg) {
  setSeed(8080);
  let v = 0, p = 0;
  for (let i = 0; i < N; i++) {
    const ra = creaRosaPerModulo('A', 74, M), rb = creaRosaPerModulo('B', 74, M);
    ra.esperienzaModulo = { '4-4-2': 5 }; rb.esperienzaModulo = { '4-4-2': 5 };
    const A = schiera(ra, '4-4-2'), B = schiera(rb, '4-4-2');
    A.titolari.forEach((g) => { if (g) { g.morale = cfg.morale; g.composure = 60 } });
    B.titolari.forEach((g) => { if (g) { g.morale = 70; g.composure = 60 } });
    B.ruoli = ruoliB;
    A.ruoli = cfg.ruoli ? M.map((s) => cfg.ruoli[s] ?? null) : null;
    A.compiti = cfg.compiti ? M.map((s) => cfg.compiti[s] ?? null) : null;
    A.tattica = sommaDelta(deltaMorale(A), deltaRuoli(A), deltaCorsie(A, B, cfg.focus));
    B.tattica = sommaDelta(deltaMorale(B), deltaRuoli(B), deltaCorsie(B, A, null));
    const r = simulaPartita(ra, rb, '4-4-2', '4-4-2', { usaCondizione: true, lineupCasa: A, lineupOspite: B });
    if (r.golC > r.golO) v++; else if (r.golC === r.golO) p++;
  }
  const punti = (v * 3 + p) / N * 38;
  console.log(`  ${et.padEnd(34)} ${(v/N*100).toFixed(1).padStart(5)}%   ${punti.toFixed(1).padStart(5)} punti/38`);
  return punti;
}

console.log('  A contro B (che lascia scoperta la SUA sinistra = la destra di A)\n');
console.log(`  ${'configurazione di A'.padEnd(34)} ${'vitt.'.padStart(6)}   ${'punti'.padStart(5)}`);
const base = prova('niente (neutro, morale 70)', { morale: 70 });
prova('solo morale alto (95)', { morale: 95 });
prova('solo corsia giusta (destra)', { morale: 70, focus: 'DX' });
prova('solo ruoli sensati', { morale: 70, ruoli: { CM: 'regista', LM: 'ala_pura', RM: 'ala_pura', ST: 'finalizzatore', LB: 'terzino', RB: 'terzino', CB: 'centrale' } });
console.log('');
const tutto = prova('TUTTO giusto insieme', {
  morale: 95, focus: 'DX',
  ruoli: { CM: 'regista', LM: 'ala_pura', RM: 'ala_pura', ST: 'finalizzatore', LB: 'terzino_offensivo', RB: 'terzino', CB: 'centrale' },
  compiti: { CB: 'difesa', ST: 'attacco' },
});
const peggio = prova('TUTTO sbagliato insieme', {
  morale: 45, focus: 'CEN',
  ruoli: { CM: 'incursore', LM: 'esterno_di_rientro', RM: 'esterno_di_rientro', ST: 'punta_di_manovra', LB: 'terzino_bloccato', RB: 'terzino_bloccato', CB: 'centrale_impostatore' },
  compiti: { CB: 'attacco', ST: 'difesa' },
});
console.log(`\n  scarto fra tutto giusto e tutto sbagliato: ${(tutto - peggio).toFixed(1)} punti su 38`);
console.log(`  (metro FM-Arena: ~6,4 punti percentuali fra la migliore e la peggiore tattica)`);
