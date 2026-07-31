// ============================================================
//  GENERAZIONE ROSE SINTETICHE — FILE DI TEST
//  Serve solo alla suite di validazione. NON va nel bundle di produzione:
//  in produzione i giocatori arrivano dal dataset FC 26 su Supabase.
// ============================================================

export { rnd, gauss, poisson, scegliPesato, setSeed } from '../../engine/random.js';
import { rnd, gauss, poisson, scegliPesato } from '../../engine/random.js';

const clamp = (v, a, b) => Math.max(a, Math.min(b, v));

// composizione tipica di una rosa da 25 slot
const COMPOSIZIONE = [
  ['GK', 3],
  ['CB', 4], ['LB', 2], ['RB', 2],
  ['CDM', 2], ['CM', 3], ['CAM', 2],
  ['LW', 2], ['RW', 2], ['ST', 3],
];

const SECONDARIE = {
  LWB: ['LB','LM'], RWB: ['RB','RM'], LM: ['LW','LB'], RM: ['RW','RB'], CF: ['ST','CAM'],
  GK: [], CB: ['LB', 'RB', 'CDM'], LB: ['LWB', 'LM', 'CB'], RB: ['RWB', 'RM', 'CB'],
  CDM: ['CM', 'CB'], CM: ['CDM', 'CAM'], CAM: ['CM', 'LW', 'RW'],
  LW: ['LM', 'ST', 'CAM'], RW: ['RM', 'ST', 'CAM'], ST: ['CF', 'CAM'],
};

let _pid = 0;

function creaGiocatore(slotNat, ovrTarget) {
  const ovr = clamp(Math.round(gauss(ovrTarget, 4.5)), 48, 94);
  const eta = clamp(Math.round(gauss(26, 4.2)), 16, 39);
  const posizioni = [slotNat];
  for (const s of SECONDARIE[slotNat] || []) if (rnd() < 0.45) posizioni.push(s);

  const rep = slotNat === 'GK' ? 'GK'
    : ['CB', 'LB', 'RB'].includes(slotNat) ? 'DEF'
    : ['CDM', 'CM', 'CAM'].includes(slotNat) ? 'MID' : 'ATT';

  // attributi correlati al ruolo, ancorati all'overall
  const near = (bias) => clamp(Math.round(gauss(ovr + bias, 6)), 20, 99);

  return {
    id: ++_pid,
    nome: `${slotNat}-${_pid}`,
    slotNat, posizioni, ovr, eta,
    stamina: clamp(Math.round(gauss(72, 9)), 40, 96),
    finishing:     near(rep === 'ATT' ? 4 : rep === 'MID' ? -6 : -20),
    short_passing: near(rep === 'MID' ? 4 : rep === 'GK' ? -22 : -3),
    tackle:        near(rep === 'DEF' ? 5 : rep === 'MID' ? -3 : -22),
    dribbling:     near(rep === 'ATT' ? 4 : rep === 'MID' ? 1 : -16),
    gk:            slotNat === 'GK' ? ovr : 0,
    condizione: 100,
    infortunatoFinoA: 0,
  };
}

// rosa costruita SU MISURA per un modulo: 2 giocatori naturali per slot.
// Serve al test di equilibrio: confrontare moduli con una rosa a forma di 4-3-3
// falsa il risultato, perche' gli altri moduli giocano con gente fuori ruolo.
export function creaRosaPerModulo(nome, ovrMedio, slots) {
  const giocatori = [];
  const conta = {};
  for (const s of slots) conta[s] = (conta[s] || 0) + 1;
  conta.GK = Math.max(conta.GK || 0, 3);
  for (const [slot, n] of Object.entries(conta)) {
    for (let i = 0; i < n * 2; i++) {
      const bias = i < n ? 1.5 : -3.0;
      giocatori.push(creaGiocatore(slot, ovrMedio + bias));
    }
  }
  return { nome, giocatori, esperienzaModulo: {}, punti: 0, gf: 0, gs: 0, v: 0, n: 0, p: 0 };
}

export function creaRosa(nome, ovrMedio) {
  const giocatori = [];
  for (const [slot, n] of COMPOSIZIONE) {
    for (let i = 0; i < n; i++) {
      // i titolari sono leggermente sopra la media, le riserve sotto
      const bias = i === 0 ? 2.5 : i === 1 ? 0 : -3.5;
      giocatori.push(creaGiocatore(slot, ovrMedio + bias));
    }
  }
  return { nome, giocatori, esperienzaModulo: {}, punti: 0, gf: 0, gs: 0, v: 0, n: 0, p: 0 };
}
