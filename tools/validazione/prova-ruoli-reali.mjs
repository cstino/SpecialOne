// I RUOLI MISURATI SU GIOCATORI VERI — node tools/validazione/prova-ruoli-reali.mjs
//
// roster.js genera cinque attributi: con quelle rose l'idoneita' ai ruoli e'
// zero per tutti e la prova non direbbe niente. Qui le rose si pescano da
// pool-reale.json, con tutti gli attributi FC 26.
//
// A cambia modo di scegliere i ruoli, B non tocca niente. Stesse rose, stessi
// semi per ogni configurazione: la differenza e' solo nelle scelte di A.
// Il vincolo del registro (punti 26 e 27): chi sceglie a caso NON deve battere
// chi non tocca niente.
import { readFileSync } from 'fs';
import { simulaPartita, schiera } from '../../engine/engine.js';
import { setSeed, rnd } from '../../engine/random.js';
import { MODULI, COMPITI } from '../../engine/config.js';
import { deltaMorale } from '../../engine/morale.js';
import { deltaRuoli, sommaDelta, ruoliPerSlot, idoneitaRuolo } from '../../engine/ruoli.js';
import { deltaCorsie } from '../../engine/corsie.js';

const N = Number(process.argv[2] ?? 8000);
const MODULO = process.argv[3] ?? '4-4-2';
const M = MODULI[MODULO];
const pool = JSON.parse(readFileSync(new URL('./pool-reale.json', import.meta.url), 'utf8'))
  .filter((p) => p.overall >= 68 && p.overall <= 80);
const perPos = {};
for (const p of pool) (perPos[p.posizioni[0]] ??= []).push(p);
// Le posizioni del modulo che il campione non ha (LWB, CF) prendono dalla
// famiglia vicina, come farebbe un partecipante.
const FONTE = { LWB: 'LB', RWB: 'RB', CF: 'ST' };

let prossimoId = 1;
function giocatore(p) {
  const a = p.attributi;
  return {
    id: prossimoId++, nome: p.nome, posizioni: p.posizioni, ovr: p.overall, eta: 27,
    stamina: a.stamina ?? 70, finishing: a.finishing ?? 50, short_passing: a.short_passing ?? 50,
    tackle: a.standing_tackle ?? 50, dribbling: a.dribbling ?? 50,
    condizione: 100, infortunatoFinoA: 0, squalificatoFinoA: 0,
    morale: 70, composure: a.mentality_composure ?? 60, attributi: a,
  };
}
const pesca = (pos) => { const l = perPos[FONTE[pos] ?? pos]; return l[Math.floor(rnd() * l.length)]; };

// Undici titolari naturali piu' una riserva per posizione, come creaRosaPerModulo.
function rosa(nome) {
  const giocatori = [];
  for (const s of M) giocatori.push(giocatore(pesca(s)));
  for (const s of M) giocatori.push({ ...giocatore(pesca(s)), ovr: 66 });
  return { nome, giocatori, esperienzaModulo: { [MODULO]: 5 } };
}

const STRATEGIE = {
  'non tocca niente': () => null,
  'ruolo base ovunque': (A) => A.slots.map((s) => ruoliPerSlot(s)[0] ?? null),
  'ruoli a caso': (A) => A.slots.map((s) => { const l = ruoliPerSlot(s); return l.length ? l[Math.floor(rnd() * l.length)] : null; }),
  'sa leggere i suoi giocatori': (A) => A.slots.map((s, i) => {
    const l = ruoliPerSlot(s); if (!l.length) return null;
    return l.reduce((a, b) => (idoneitaRuolo(A.titolari[i], b) > idoneitaRuolo(A.titolari[i], a) ? b : a));
  }),
  // Il caso onesto del punto 26: entra, tocca tutto senza studiarlo, esce.
  'tocca tutto a caso': (A) => {
    A.compiti = A.slots.map(() => COMPITI[Math.floor(rnd() * COMPITI.length)]);
    A.focus = [null, 'SX', 'CEN', 'DX'][Math.floor(rnd() * 4)];
    return A.slots.map((s) => { const l = ruoliPerSlot(s); return l.length ? l[Math.floor(rnd() * l.length)] : null; });
  },
  'sbaglia apposta': (A) => A.slots.map((s, i) => {
    const l = ruoliPerSlot(s); if (!l.length) return null;
    return l.reduce((a, b) => (idoneitaRuolo(A.titolari[i], b) < idoneitaRuolo(A.titolari[i], a) ? b : a));
  }),
};

function prova(nome, scegli) {
  setSeed(4242); prossimoId = 1;
  let v = 0, p = 0, gf = 0, gs = 0;
  for (let i = 0; i < N; i++) {
    const ra = rosa('A'), rb = rosa('B');
    const A = schiera(ra, MODULO), B = schiera(rb, MODULO);
    A.ruoli = scegli(A);
    A.tattica = sommaDelta(deltaMorale(A), deltaRuoli(A), deltaCorsie(A, B, A.focus ?? null));
    B.tattica = sommaDelta(deltaMorale(B), deltaRuoli(B), deltaCorsie(B, A, null));
    const r = simulaPartita(ra, rb, MODULO, MODULO, { usaCondizione: true, lineupCasa: A, lineupOspite: B });
    if (r.golC > r.golO) v++; else if (r.golC === r.golO) p++;
    gf += r.golC; gs += r.golO;
  }
  return { nome, punti: (v * 3 + p) / N * 38, gf: gf / N, gs: gs / N };
}

console.log(`\n  ${N} partite per riga, ${MODULO}, rose vere fra 68 e 80 di overall\n`);
const righe = Object.entries(STRATEGIE).map(([k, f]) => prova(k, f));
const base = righe[0].punti;
for (const r of righe) {
  const d = r.punti - base;
  console.log(`  ${r.nome.padEnd(30)} ${r.punti.toFixed(1).padStart(5)} punti/38   ${r.gf.toFixed(2)} - ${r.gs.toFixed(2)}   ${r === righe[0] ? '' : (d >= 0 ? '+' : '') + d.toFixed(1)}`);
}
for (const k of ['ruoli a caso', 'tocca tutto a caso']) {
  const caso = righe.find((r) => r.nome === k).punti - base;
  console.log(`\n  vincolo, ${k}: non deve battere chi non tocca niente -> ${caso <= 0.3 ? 'RISPETTATO' : 'VIOLATO'} (${caso >= 0 ? '+' : ''}${caso.toFixed(1)})`);
}
