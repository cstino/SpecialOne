// Distribuzione dei cambi su stagioni vere (la condizione si trascina fra le
// giornate, come in produzione): quanti cambi per squadra, in quale momento,
// quante soste. Uso: node tools/validazione/prova-cambi.mjs [sogliaIntervallo maxIntervallo quotaDivisa]
import { simulaPartita, schiera } from '../../engine/engine.js';
import { creaRosaPerModulo, setSeed } from './roster.js';
import { MODULI, CFG } from '../../engine/config.js';

const [soglia, maxInt, quota] = process.argv.slice(2).map(Number);
if (!Number.isNaN(soglia) && process.argv[2]) CFG.SOGLIA_CAMBIO_INTERVALLO = soglia;
if (process.argv[3]) CFG.MAX_CAMBI_INTERVALLO = maxInt;
if (process.argv[4]) CFG.QUOTA_SOSTA_DIVISA = quota;

const MODULI_PROVA = ['4-3-3', '4-4-2', '4-2-3-1', '3-5-2'];
const GIORNATE = 30, STAGIONI = 150;
let squadre = 0, cambi = 0, gol = 0, partite = 0;
const momento = { intervallo: 0, '46-60 (infortunio)': 0, 'dopo il 60': 0, 'dopo il 75': 0, 'verso la fine': 0, 'primo tempo (infortunio)': 0, 'altro infortunio': 0 };
const perNumero = {}, perSoste = {};
for (let s = 0; s < STAGIONI; s++) {
  setSeed(7000 + s);
  const mA = MODULI_PROVA[s % 4], mB = MODULI_PROVA[(s + 1) % 4];
  const ra = creaRosaPerModulo('A', 74, MODULI[mA]);
  const rb = creaRosaPerModulo('B', 74, MODULI[mB]);
  for (let g = 0; g < GIORNATE; g++) {
    const r = simulaPartita(ra, rb, mA, mB, { usaCondizione: true, lineupCasa: schiera(ra, mA), lineupOspite: schiera(rb, mB) });
    partite++; gol += r.golC + r.golO;
    for (const lato of ['casa', 'ospite']) {
      const c = r.cambiInPartita.filter((x) => x.lato === lato);
      squadre++; cambi += c.length;
      perNumero[c.length] = (perNumero[c.length] ?? 0) + 1;
      const soste = Math.max(0, ...c.map((x) => x.sosta));
      perSoste[soste] = (perSoste[soste] ?? 0) + 1;
      for (const x of c) {
        if (x.motivo === 'infortunio') momento[x.blocco <= 3 ? 'primo tempo (infortunio)' : x.blocco === 4 ? '46-60 (infortunio)' : 'altro infortunio']++;
        else if (x.sosta === 0) momento.intervallo++;
        else if (x.tardiva) momento['verso la fine']++;
        else if (x.blocco === 4) momento['dopo il 60']++;
        else momento['dopo il 75']++;
      }
    }
  }
}
console.log(`partite ${partite}  gol/partita ${(gol / partite).toFixed(2)}  cambi per squadra ${(cambi / squadre).toFixed(2)}`);
console.log('momento dei cambi (%):', Object.entries(momento).map(([k, v]) => `${k} ${(100 * v / cambi).toFixed(0)}`).join(' | '));
console.log('squadre per numero di cambi (%):', Object.entries(perNumero).map(([k, v]) => `${k}:${(100 * v / squadre).toFixed(0)}`).join(' '));
console.log('squadre per soste usate (%):', Object.entries(perSoste).map(([k, v]) => `${k}:${(100 * v / squadre).toFixed(0)}`).join(' '));
