// IL SISTEMA TATTICO MISURATO SU GIOCATORI VERI
// node tools/validazione/prova-ruoli-reali.mjs [partite] [modulo]
//
// roster.js genera cinque attributi: con quelle rose l'idoneita' e' zero per
// tutti e la prova non direbbe niente. Qui le rose si pescano da
// pool-reale.json, con tutti gli attributi FC 26.
//
// A cambia modo di scegliere, B non tocca niente. Stesse rose e stessi semi
// per ogni riga: la differenza e' solo nelle scelte di A. Il vincolo del
// registro (punti 26, 27, 30): chi sceglie a caso NON deve battere chi non
// tocca niente.
//
// Le leve: ruoli e compiti (pagina Giocatori), stile, linea, ampiezza,
// portiere e dove attacchiamo (pagina Squadra).
import { readFileSync } from 'fs';
import { simulaPartita, schiera } from '../../engine/engine.js';
import { setSeed, rnd } from '../../engine/random.js';
import { MODULI, COMPITI, STILI } from '../../engine/config.js';
import { deltaMorale } from '../../engine/morale.js';
import { deltaRuoli, sommaDelta, ruoliPerSlot, idoneitaRuolo } from '../../engine/ruoli.js';
import { deltaCorsie, vantaggioCorsia } from '../../engine/corsie.js';
import { deltaSquadra, deltaCoperturaLibero, OPZIONI_SQUADRA, PREDEFINITE, idoneitaSquadra } from '../../engine/squadra.js';

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
const caso = (l) => l[Math.floor(rnd() * l.length)];

// Undici titolari naturali piu' una riserva per posizione. Familiarita' piena
// col modulo e con ogni stile: la prova misura le scelte, non l'abitudine.
function rosa(nome) {
  const giocatori = [];
  for (const s of M) giocatori.push(giocatore(pesca(s)));
  for (const s of M) giocatori.push({ ...giocatore(pesca(s)), ovr: 66 });
  return { nome, giocatori, esperienzaModulo: { [MODULO]: 5 }, esperienzaStile: Object.fromEntries(Object.keys(STILI).map((k) => [k, 5])) };
}

// Quanto vale per QUESTA squadra un'indicazione di squadra, a occhio di chi la
// conosce bene: la somma degli scarti che produrrebbe sui titolari.
const valoreSquadra = (A, ind) => {
  const f = sommaDelta(deltaSquadra(ind), deltaCoperturaLibero(A, ind));
  return f ? A.titolari.reduce((t, g, i) => t + (g ? f(g, A.slots[i]) : 0), 0) : 0;
};
const assi = { stile: Object.keys(OPZIONI_SQUADRA.stile), linea: Object.keys(OPZIONI_SQUADRA.linea), ampiezza: Object.keys(OPZIONI_SQUADRA.ampiezza), portiere: Object.keys(OPZIONI_SQUADRA.portiere) };

// Sceglie, asse per asse, l'opzione migliore (o peggiore) per la propria rosa.
function squadraMirata(A, verso, soloAsse = null) {
  const ind = { ...PREDEFINITE };
  for (const asse of ['linea', 'ampiezza', 'stile', 'portiere']) {
    if (soloAsse && asse !== soloAsse) continue;
    let migliore = ind[asse], v = verso * valoreSquadra(A, ind);
    for (const o of assi[asse]) {
      const w = verso * valoreSquadra(A, { ...ind, [asse]: o });
      if (w > v) { v = w; migliore = o; }
    }
    ind[asse] = migliore;
  }
  return ind;
}
const corsiaMirata = (A, verso) => ['CEN', 'DX'].reduce((m, c) => (verso * vantaggioCorsia(A, c) > verso * vantaggioCorsia(A, m) ? c : m), 'SX');
const ruoliMirati = (A, verso) => A.slots.map((s, i) => {
  const l = ruoliPerSlot(s); if (!l.length) return null;
  return l.reduce((a, b) => (verso * idoneitaRuolo(A.titolari[i], b) > verso * idoneitaRuolo(A.titolari[i], a) ? b : a));
});

const STRATEGIE = {
  'non tocca niente': () => {},
  'solo ruoli giusti': (A) => { A.ruoli = ruoliMirati(A, 1); },
  'solo stile giusto': (A) => { A.squadra = squadraMirata(A, 1, 'stile'); },
  'solo linea giusta': (A) => { A.squadra = squadraMirata(A, 1, 'linea'); },
  'solo ampiezza giusta': (A) => { A.squadra = squadraMirata(A, 1, 'ampiezza'); },
  'solo corsia giusta': (A) => { A.focus = corsiaMirata(A, 1); },
  'linea alta + portiere-libero': (A) => { A.squadra = { ...PREDEFINITE, linea: 'alta', portiere: 'libero' }; },
  // Il portiere-libero e' una scelta da profilo, come le altre: si misura
  // leggendo il proprio portiere (registro, punto 37). Stessa linea alta in
  // entrambe le righe, cosi' la differenza e' solo il portiere.
  'solo linea alta, portiere normale': (A) => { A.squadra = { ...PREDEFINITE, linea: 'alta' }; },
  'linea alta + libero se adatto': (A) => {
    const gk = A.titolari[A.slots.indexOf('GK')];
    A.squadra = { ...PREDEFINITE, linea: 'alta', portiere: idoneitaSquadra(gk, 'portiere_libero') > 0 ? 'libero' : 'normale' };
  },
  'linea alta + libero se NON adatto': (A) => {
    const gk = A.titolari[A.slots.indexOf('GK')];
    A.squadra = { ...PREDEFINITE, linea: 'alta', portiere: idoneitaSquadra(gk, 'portiere_libero') < 0 ? 'libero' : 'normale' };
  },
  'tocca tutto a caso': (A) => {
    A.ruoli = A.slots.map((s) => { const l = ruoliPerSlot(s); return l.length ? caso(l) : null; });
    A.compiti = A.slots.map(() => caso(COMPITI));
    A.focus = caso([null, 'SX', 'CEN', 'DX']);
    A.squadra = { stile: caso(assi.stile), linea: caso(assi.linea), ampiezza: caso(assi.ampiezza), portiere: caso(assi.portiere) };
  },
  'sa leggere la sua rosa (tutto)': (A) => { A.ruoli = ruoliMirati(A, 1); A.squadra = squadraMirata(A, 1); A.focus = corsiaMirata(A, 1); },
  'sbaglia apposta (tutto)': (A) => { A.ruoli = ruoliMirati(A, -1); A.squadra = squadraMirata(A, -1); A.focus = corsiaMirata(A, -1); },
};

function prova(nome, scegli) {
  setSeed(4242); prossimoId = 1;
  let v = 0, p = 0, gf = 0, gs = 0;
  for (let i = 0; i < N; i++) {
    const ra = rosa('A'), rb = rosa('B');
    const A = schiera(ra, MODULO), B = schiera(rb, MODULO);
    scegli(A);
    const ind = A.squadra ?? PREDEFINITE;
    A.tattica = sommaDelta(deltaMorale(A), deltaRuoli(A), deltaCorsie(A, A.focus ?? null), deltaSquadra(ind), deltaCoperturaLibero(A, ind));
    B.tattica = sommaDelta(deltaMorale(B), deltaRuoli(B));
    const r = simulaPartita(ra, rb, MODULO, MODULO, {
      usaCondizione: true, lineupCasa: A, lineupOspite: B, stileCasa: ind.stile, stileOspite: 'equilibrato',
    });
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
  console.log(`  ${r.nome.padEnd(32)} ${r.punti.toFixed(1).padStart(5)} punti/38   ${r.gf.toFixed(2)} - ${r.gs.toFixed(2)}   ${r === righe[0] ? '' : (d >= 0 ? '+' : '') + d.toFixed(1)}`);
}
const casoD = righe.find((r) => r.nome === 'tocca tutto a caso').punti - base;
console.log(`\n  vincolo, tocca tutto a caso: non deve battere chi non tocca niente -> ${casoD <= 0.3 ? 'RISPETTATO' : 'VIOLATO'} (${casoD >= 0 ? '+' : ''}${casoD.toFixed(1)})`);
