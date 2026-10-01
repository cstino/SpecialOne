// LE PAGELLE MISURATE — node tools/validazione/prova-pagelle.mjs [partite]
//
// Rose vere da pool-reale.json (come prova-ruoli-reali), ruoli scelti a caso
// per avere interpreti adatti e non adatti. Misura:
//   - la distribuzione dei voti (obiettivo SofaScore: media ~6,7, scarto ~0,6);
//   - il migliore in campo: voto e reparto (tutti devono poterlo essere);
//   - quanto la media voto separa chi e' adatto al proprio ruolo da chi no;
//   - che i voti non cambino gol e risultati (seme separato).
import { readFileSync } from 'fs';
import { simulaPartita, schiera } from '../../engine/engine.js';
import { setSeed, rnd } from '../../engine/random.js';
import { MODULI, REPARTO } from '../../engine/config.js';
import { deltaMorale } from '../../engine/morale.js';
import { deltaRuoli, sommaDelta, ruoliPerSlot } from '../../engine/ruoli.js';
import { pagelle, migliorInCampo } from '../../engine/pagelle.js';

const N = Number(process.argv[2] ?? 3000);
const MODULO = '4-3-3';
const M = MODULI[MODULO];
const pool = JSON.parse(readFileSync(new URL('./pool-reale.json', import.meta.url), 'utf8'))
  .filter((p) => p.overall >= 66 && p.overall <= 82);
const perPos = {};
for (const p of pool) (perPos[p.posizioni[0]] ??= []).push(p);
let prossimoId = 1;
const giocatore = (p) => {
  const a = p.attributi;
  return { id: prossimoId++, nome: p.nome, posizioni: p.posizioni, ovr: p.overall, eta: 27,
    stamina: a.stamina ?? 70, finishing: a.finishing ?? 50, short_passing: a.short_passing ?? 50,
    tackle: a.standing_tackle ?? 50, dribbling: a.dribbling ?? 50, condizione: 100,
    infortunatoFinoA: 0, squalificatoFinoA: 0, morale: 70, composure: 60, attributi: a };
};
const pesca = (pos) => { const l = perPos[pos]; return l[Math.floor(rnd() * l.length)]; };
const rosa = (nome) => {
  const giocatori = [];
  for (const s of M) giocatori.push(giocatore(pesca(s)));
  for (const s of M) giocatori.push({ ...giocatore(pesca(s)), ovr: 64 });
  return { nome, giocatori, esperienzaModulo: { [MODULO]: 5 } };
};
// Assist come li assegna la cronaca: un compagno in campo, piu' spesso chi passa.
function assist(stats, golIds) {
  const m = new Map();
  const passatori = [...stats.passaggi.entries()];
  const tot = passatori.reduce((t, [, v]) => t + v, 0);
  for (const marcatore of golIds) {
    if (rnd() > 0.72 || !tot) continue;
    let r = rnd() * tot;
    for (const [id, v] of passatori) { r -= v; if (r <= 0) { if (id !== marcatore) m.set(id, (m.get(id) ?? 0) + 1); break; } }
  }
  return m;
}

const azioni = {};
const voti = [], mvp = [], mvpRep = {}, perRep = {}, perFit = { adatto: [], neutro: [], inadatto: [] };
let mvpVincente = 0, partiteConVincitore = 0;
setSeed(777);
for (let i = 0; i < N; i++) {
  const ra = rosa('A'), rb = rosa('B');
  const A = schiera(ra, MODULO), B = schiera(rb, MODULO);
  for (const L of [A, B]) {
    L.ruoli = L.slots.map((s) => { const l = ruoliPerSlot(s); return l.length ? l[Math.floor(rnd() * l.length)] : null; });
    L.tattica = sommaDelta(deltaMorale(L), deltaRuoli(L));
  }
  const r = simulaPartita(ra, rb, MODULO, MODULO, { usaCondizione: true, statsGiocatori: true, lineupCasa: A, lineupOspite: B });
  const lato = (rosaX, L, stats, squadra, gf, gs, nome) => ({
    giocatori: new Map(rosaX.giocatori.map((g) => [g.id, g])), lineup: L, stats, squadra, golFatti: gf, golSubiti: gs,
    assist: assist(stats, stats.marcatoriIds),
    cartellini: (r.cartelliniInPartita ?? []).filter((c) => c.lato === nome).map((c) => ({ giocatore: c.giocatore, tipo: c.tipo })),
  });
  const v = pagelle({
    casa: lato(ra, A, r.perGiocatore.casa, r.statsCasa, r.golC, r.golO, 'casa'),
    ospite: lato(rb, B, r.perGiocatore.ospite, r.statsOspite, r.golO, r.golC, 'ospite'),
  }, i * 7919 + 13);
  const tutti = new Map([...ra.giocatori, ...rb.giocatori].map((g) => [g.id, g]));
  const slotDi = new Map([...r.perGiocatore.casa.slot, ...r.perGiocatore.ospite.slot]);
  for (const [id, x] of v) {
    if (x.voto === null) continue;
    voti.push(x.voto);
    const rep = REPARTO[slotDi.get(id)] ?? '?';
    (perRep[rep] ??= []).push(x.voto);
    if (x.dettaglio) { const dd = (azioni[rep] ??= {}); for (const [k, val] of Object.entries(x.dettaglio)) dd[k] = (dd[k] ?? 0) + val; dd.n = (dd.n ?? 0) + 1; }
    const g = tutti.get(id), L = x.lato === 'casa' ? A : B;
    const d = L.tattica ? L.tattica(g, slotDi.get(id)) : 0;
    (d >= 0.8 ? perFit.adatto : d <= -0.8 ? perFit.inadatto : perFit.neutro).push(x.voto);
  }
  const best = migliorInCampo(v);
  if (best !== null) {
    mvp.push(v.get(best).voto);
    const rep = REPARTO[slotDi.get(best)] ?? '?';
    mvpRep[rep] = (mvpRep[rep] ?? 0) + 1;
    if (r.golC !== r.golO) { partiteConVincitore++; if ((v.get(best).lato === 'casa') === (r.golC > r.golO)) mvpVincente++; }
  }
}
const media = (a) => a.reduce((x, y) => x + y, 0) / a.length;
const dev = (a) => { const m = media(a); return Math.sqrt(media(a.map((x) => (x - m) ** 2))); };
const q = (a, p) => { const s = [...a].sort((x, y) => x - y); return s[Math.floor(p * (s.length - 1))]; };
console.log(`\n  ${N} partite, ${voti.length} voti`);
console.log(`  voti: media ${media(voti).toFixed(2)}  scarto ${dev(voti).toFixed(2)}  5%-95%: ${q(voti, .05)}-${q(voti, .95)}  min ${Math.min(...voti)} max ${Math.max(...voti)}`);
console.log(`  migliore in campo: media ${media(mvp).toFixed(2)}  10%-90%: ${q(mvp, .1)}-${q(mvp, .9)}  della squadra vincente ${(mvpVincente / partiteConVincitore * 100).toFixed(0)}%`);
const tot = Object.values(mvpRep).reduce((a, b) => a + b, 0);
console.log('  MVP per reparto: ' + ['GK', 'DEF', 'MID', 'ATT'].map((k) => `${k} ${((mvpRep[k] ?? 0) / tot * 100).toFixed(0)}%`).join('  ') + '   (titolari: GK 9%, DEF 36%, MID 27%, ATT 27%)');
console.log('  media per reparto: ' + ['GK', 'DEF', 'MID', 'ATT'].map((k) => `${k} ${media(perRep[k] ?? [0]).toFixed(2)}`).join('  '));
console.log(`  interpreti: adatti ${media(perFit.adatto).toFixed(2)} (${perFit.adatto.length})  neutri ${media(perFit.neutro).toFixed(2)}  inadatti ${media(perFit.inadatto).toFixed(2)} (${perFit.inadatto.length})`);
for (const k of ['GK', 'DEF', 'MID', 'ATT']) { const dd = azioni[k]; if (!dd) continue; console.log(`  azioni medie ${k}: ` + Object.entries(dd).filter(([x]) => x !== 'n').map(([x, val]) => `${x} ${(val / dd.n).toFixed(1)}`).join('  ')); }
