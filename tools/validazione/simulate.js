// ============================================================
//  FASE 0 — VALIDAZIONE DEL MOTORE
//  node simulate.js [--esp 2.0] [--xg 0.225] [--sweep]
// ============================================================

import { CFG, MODULI } from '../../engine/config.js';
import { creaRosa, creaRosaPerModulo, setSeed, rnd } from './roster.js';
import { simulaPartita, calendario, counter, schiera } from '../../engine/engine.js';
import assert from 'node:assert/strict';

const args = process.argv.slice(2);
const getArg = (n, d) => { const i = args.indexOf('--' + n); return i >= 0 ? parseFloat(args[i + 1]) : d; };
CFG.SENSIBILITA_FORZA = getArg('sens', CFG.SENSIBILITA_FORZA);
CFG.XG_BASE_BLOCCO = getArg('xg', CFG.XG_BASE_BLOCCO);

const NOMI_MOD = Object.keys(MODULI);
const media = a => a.reduce((x, y) => x + y, 0) / a.length;
const dev = a => { const m = media(a); return Math.sqrt(media(a.map(v => (v - m) ** 2))); };
const pct = (a, p) => { const s = [...a].sort((x, y) => x - y); return s[Math.floor(s.length * p)]; };

function verificaFormazioneUtente() {
  setSeed(991);
  const casa = creaRosa('Casa', 81), ospite = creaRosa('Ospite', 81);
  let letture = 0;
  const sceltaUtente = new Proxy(schiera(casa, '4-3-3'), {
    get(target, property, receiver) {
      letture++;
      return Reflect.get(target, property, receiver);
    },
  });
  simulaPartita(casa, ospite, '4-3-3', '4-3-3', {
    usaCondizione: false,
    lineupCasa: sceltaUtente,
  });
  assert.ok(letture > 0, 'Il motore ha ignorato la formazione scelta dall’utente');
}

function riga(label, val, min, max, fmt = v => v.toFixed(2)) {
  const ok = val >= min && val <= max;
  const mark = ok ? '  OK ' : ' FUORI';
  return `${label.padEnd(34)} ${fmt(val).padStart(8)}   target ${fmt(min)}–${fmt(max)}  ${mark}`;
}

function istogramma(dati, minV, maxV, bins, label) {
  const conta = new Array(bins).fill(0);
  const w = (maxV - minV) / bins;
  for (const d of dati) conta[Math.min(bins - 1, Math.max(0, Math.floor((d - minV) / w)))]++;
  const maxC = Math.max(...conta);
  let s = `\n${label}\n`;
  for (let i = 0; i < bins; i++) {
    const lo = (minV + i * w).toFixed(0).padStart(3);
    s += `${lo} |${'#'.repeat(Math.round(conta[i] / maxC * 52))} ${(conta[i] / dati.length * 100).toFixed(1)}%\n`;
  }
  return s;
}

// ============================================================
//  TEST 1 — Baseline: due squadre identiche, 10.000 partite
// ============================================================

function test1(N = 10000) {
  setSeed(1001);
  let gol = 0, vC = 0, pari = 0, vO = 0;
  const tiri = [], pctPass = [], possesso = [], golPartita = [];

  for (let i = 0; i < N; i++) {
    const A = creaRosa('A', 81), B = creaRosa('B', 81);
    const r = simulaPartita(A, B, '4-3-3', '4-3-3', { usaCondizione: false });
    gol += r.golC + r.golO;
    golPartita.push(r.golC + r.golO);
    if (r.golC > r.golO) vC++; else if (r.golC === r.golO) pari++; else vO++;
    tiri.push(r.statsCasa.tiri, r.statsOspite.tiri);
    pctPass.push(r.statsCasa.passaggiPct * 100, r.statsOspite.passaggiPct * 100);
    possesso.push(r.statsCasa.possesso * 100);
  }

  console.log('\n' + '='.repeat(78));
  console.log('TEST 1 — BASELINE: due squadre identiche (OVR 81), 4-3-3 vs 4-3-3');
  console.log('='.repeat(78));
  console.log(riga('Gol per partita', gol / N, 2.50, 2.90));
  console.log(riga('Vittorie casa %', vC / N * 100, 43, 47, v => v.toFixed(1)));
  console.log(riga('Pareggi %', pari / N * 100, 23, 27, v => v.toFixed(1)));
  console.log(riga('Vittorie ospite %', vO / N * 100, 28, 33, v => v.toFixed(1)));
  console.log(riga('Tiri per squadra', media(tiri), 11, 14, v => v.toFixed(1)));
  console.log(riga('% passaggi riusciti', media(pctPass), 76, 88, v => v.toFixed(1)));
  console.log(riga('Possesso casa %', media(possesso), 49, 54, v => v.toFixed(1)));
  console.log(istogramma(golPartita, 0, 9, 9, 'Distribuzione gol totali per partita'));
}

// ============================================================
//  TEST 2 — Sensibilita al divario di overall
// ============================================================

function test2(N = 4000) {
  console.log('\n' + '='.repeat(78));
  console.log('TEST 2 — SENSIBILITA AL DIVARIO DI OVERALL (campo neutro)');
  console.log('='.repeat(78));
  console.log('  gap     vitt.forte%   pareggi%   vitt.debole%   gol forte   gol debole');
  for (const gap of [0, 2, 4, 6, 8, 12]) {
    setSeed(2000 + gap);
    let vF = 0, pa = 0, vD = 0, gF = 0, gD = 0;
    const cs = CFG.BONUS_CASA_ATT; CFG.BONUS_CASA_ATT = 0; CFG.BONUS_CASA_MID = 0;
    for (let i = 0; i < N; i++) {
      const F = creaRosa('F', 80 + gap / 2), D = creaRosa('D', 80 - gap / 2);
      const r = simulaPartita(F, D, '4-3-3', '4-3-3', { usaCondizione: false });
      gF += r.golC; gD += r.golO;
      if (r.golC > r.golO) vF++; else if (r.golC === r.golO) pa++; else vD++;
    }
    CFG.BONUS_CASA_ATT = cs; CFG.BONUS_CASA_MID = cs;
    console.log(`  ${String(gap).padStart(2)}      ${(vF / N * 100).toFixed(1).padStart(7)}     ${(pa / N * 100).toFixed(1).padStart(7)}      ${(vD / N * 100).toFixed(1).padStart(7)}      ${(gF / N).toFixed(2).padStart(6)}      ${(gD / N).toFixed(2).padStart(6)}`);
  }
}

// ============================================================
//  TEST 3 — Stagioni complete
// ============================================================

function test3(NS = 500, nSquadre = 8, gironi = 4) {
  setSeed(3003);
  const cal = calendario(nSquadre, gironi);
  const nPartite = (nSquadre - 1) * gironi;
  const puntiVinc = [], spread = [], puntiUlt = [], golTot = [], titolo = new Array(nSquadre).fill(0);
  const condFine = [];

  for (let s = 0; s < NS; s++) {
    // spread realistico dopo un draft con tetto: 79 -> 84
    const rose = [];
    for (let t = 0; t < nSquadre; t++) rose.push(creaRosa('T' + t, 79 + t * (5 / (nSquadre - 1))));
    let gp = 0;

    for (const giornata of cal) {
      for (const [a, b] of giornata) {
        const mA = NOMI_MOD[Math.floor(rnd() * NOMI_MOD.length)];
        const mB = NOMI_MOD[Math.floor(rnd() * NOMI_MOD.length)];
        const r = simulaPartita(rose[a], rose[b], mA, mB, { usaCondizione: true });
        gp += r.golC + r.golO;
        rose[a].gf += r.golC; rose[a].gs += r.golO;
        rose[b].gf += r.golO; rose[b].gs += r.golC;
        if (r.golC > r.golO) { rose[a].punti += 3; rose[a].v++; rose[b].p++; }
        else if (r.golC === r.golO) { rose[a].punti++; rose[b].punti++; rose[a].n++; rose[b].n++; }
        else { rose[b].punti += 3; rose[b].v++; rose[a].p++; }
      }
    }

    const ord = rose.map((r, i) => ({ i, p: r.punti })).sort((x, y) => y.p - x.p);
    puntiVinc.push(ord[0].p);
    puntiUlt.push(ord[ord.length - 1].p);
    spread.push(ord[0].p - ord[ord.length - 1].p);
    titolo[ord[0].i]++;
    golTot.push(gp / (cal.flat().length));
    condFine.push(media(rose.map(r => {
      const top = [...r.giocatori].sort((a, b) => b.ovr - a.ovr).slice(0, 11);
      return media(top.map(g => g.condizione));
    })));
  }

  console.log('\n' + '='.repeat(78));
  console.log(`TEST 3 — STAGIONI COMPLETE (${NS} stagioni, ${nSquadre} squadre, ${gironi} gironi = ${nPartite} partite)`);
  console.log('  Forza squadre: da OVR 79 (T0) a OVR 84 (T7). Moduli casuali ogni partita.');
  console.log('='.repeat(78));
  console.log(riga('Punti del vincitore', media(puntiVinc), 58, 68, v => v.toFixed(1)));
  console.log(riga('Punti dell\'ultimo', media(puntiUlt), 15, 28, v => v.toFixed(1)));
  console.log(riga('Spread primo-ultimo', media(spread), 35, 50, v => v.toFixed(1)));
  console.log(riga('Gol per partita', media(golTot), 2.50, 2.90));
  // Target ri-tarato il 2 agosto 2026, da 55-85 a 75-95.
  // Il vecchio intervallo misurava un mondo in cui le sostituzioni non
  // scattavano mai: i titolari giocavano tutti i 90 minuti di tutte le
  // giornate. Con il modello di fatica da partita chi si stanca esce al 60',
  // quindi la rosa arriva a fine stagione piu' fresca. Il valore piu' alto e'
  // la conseguenza del meccanismo che funziona, non una deriva del motore.
  console.log(riga('Condizione titolari a fine stag.', media(condFine), 75, 95, v => v.toFixed(1)));
  console.log(`\n  Punti vincitore  p10=${pct(puntiVinc, 0.10)}  mediana=${pct(puntiVinc, 0.5)}  p90=${pct(puntiVinc, 0.90)}   dev.std=${dev(puntiVinc).toFixed(1)}`);
  console.log('\n  Titoli vinti per forza squadra (T0=piu debole, T7=piu forte):');
  titolo.forEach((c, i) => {
    console.log(`   T${i} (OVR ${(79 + i * 5 / (nSquadre - 1)).toFixed(1)})  ${String((c / NS * 100).toFixed(1)).padStart(5)}%  ${'#'.repeat(Math.round(c / NS * 100))}`);
  });
  console.log(istogramma(puntiVinc, 40, 84, 11, 'Distribuzione punti del vincitore'));
}

// ============================================================
//  TEST 4 — Matrice counter moduli
// ============================================================

function test4() {
  console.log('\n' + '='.repeat(78));
  console.log('TEST 4 — PROFILO STRUTTURALE DEI MODULI + verifica di equilibrio');
  console.log('='.repeat(78));
  console.log('  Profilo strutturale (punti di overall rispetto al 4-3-3):');
  console.log('  modulo        ATT     MID     DEF');
  for (const m of NOMI_MOD) {
    const c = counter(m, m);
    console.log(`  ${m.padEnd(10)} ${c.attA.toFixed(2).padStart(6)}  ${c.midA.toFixed(2).padStart(6)}  ${c.defA.toFixed(2).padStart(6)}`);
  }

  console.log('\n  TORNEO ALL-PLAY-ALL: ogni modulo con rosa su misura, OVR 81, campo neutro,');
  console.log('  familiarita piena, 1500 partite per accoppiamento. Un modulo equilibrato sta a ~50%.\n');
  const cs = CFG.BONUS_CASA_ATT; CFG.BONUS_CASA_MID = 0; CFG.BONUS_CASA_ATT = 0;
  const punti = {}, golF = {}, golS = {}, nP = {};
  for (const m of NOMI_MOD) { punti[m] = 0; golF[m] = 0; golS[m] = 0; nP[m] = 0; }
  for (let i = 0; i < NOMI_MOD.length; i++) for (let j = 0; j < NOMI_MOD.length; j++) {
    if (i === j) continue;
    const mA = NOMI_MOD[i], mB = NOMI_MOD[j];
    setSeed(4004 + i * 17 + j);
    for (let k = 0; k < 1500; k++) {
      const A = creaRosaPerModulo('A', 81, MODULI[mA]), B = creaRosaPerModulo('B', 81, MODULI[mB]);
      A.esperienzaModulo[mA] = 20; B.esperienzaModulo[mB] = 20;
      const r = simulaPartita(A, B, mA, mB, { usaCondizione: false });
      golF[mA] += r.golC; golS[mA] += r.golO; golF[mB] += r.golO; golS[mB] += r.golC;
      nP[mA]++; nP[mB]++;
      if (r.golC > r.golO) punti[mA] += 3; else if (r.golC === r.golO) { punti[mA]++; punti[mB]++; } else punti[mB] += 3;
    }
  }
  console.log('  modulo      punti/partita   gol fatti   gol subiti');
  const ord = NOMI_MOD.slice().sort((a, b) => punti[b] / nP[b] - punti[a] / nP[a]);
  for (const m of ord)
    console.log(`  ${m.padEnd(10)} ${(punti[m] / nP[m]).toFixed(3).padStart(10)}      ${(golF[m] / nP[m]).toFixed(2).padStart(6)}       ${(golS[m] / nP[m]).toFixed(2).padStart(6)}`);
  const pmax = Math.max(...NOMI_MOD.map(m => punti[m] / nP[m])), pmin = Math.min(...NOMI_MOD.map(m => punti[m] / nP[m]));
  console.log('\n' + riga('  Scarto punti/partita max-min', pmax - pmin, 0, 0.22, v => v.toFixed(3)));
}

// ============================================================
//  SWEEP — ricerca del valore ottimale di ESPONENTE_FORZA
// ============================================================

function sweep() {
  console.log('\n' + '='.repeat(78));
  console.log('SWEEP — SENSIBILITA_FORZA: effetto sul campionato (200 stagioni per valore)');
  console.log('='.repeat(78));
  console.log('  sens   punti vinc.   spread   %titoli T7   %titoli T0..T3   gol/partita');
  const orig = CFG.SENSIBILITA_FORZA;
  for (const esp of [0.04, 0.06, 0.08, 0.10, 0.13, 0.16]) {
    CFG.SENSIBILITA_FORZA = esp;
    setSeed(5005);
    const cal = calendario(8, 4);
    const pv = [], sp = [], gpp = [];
    let t7 = 0, deboli = 0;
    const NS = 200;
    for (let s = 0; s < NS; s++) {
      const rose = [];
      for (let t = 0; t < 8; t++) rose.push(creaRosa('T' + t, 79 + t * 5 / 7));
      let g = 0, np = 0;
      for (const giornata of cal) for (const [a, b] of giornata) {
        const r = simulaPartita(rose[a], rose[b], '4-3-3', '4-3-3', { usaCondizione: true });
        g += r.golC + r.golO; np++;
        rose[a].gf += r.golC; rose[b].gf += r.golO;
        if (r.golC > r.golO) rose[a].punti += 3;
        else if (r.golC === r.golO) { rose[a].punti++; rose[b].punti++; }
        else rose[b].punti += 3;
      }
      const ord = rose.map((r, i) => ({ i, p: r.punti })).sort((x, y) => y.p - x.p);
      pv.push(ord[0].p); sp.push(ord[0].p - ord[7].p); gpp.push(g / np);
      if (ord[0].i === 7) t7++;
      if (ord[0].i <= 3) deboli++;
    }
    console.log(`  ${esp.toFixed(2)}    ${media(pv).toFixed(1).padStart(8)}   ${media(sp).toFixed(1).padStart(6)}   ${(t7 / NS * 100).toFixed(1).padStart(8)}%   ${(deboli / NS * 100).toFixed(1).padStart(12)}%   ${media(gpp).toFixed(2).padStart(10)}`);
  }
  CFG.SENSIBILITA_FORZA = orig;
}

// ============================================================

console.log(`\nCONFIG:  SENSIBILITA_FORZA=${CFG.SENSIBILITA_FORZA}   XG_BASE_BLOCCO=${CFG.XG_BASE_BLOCCO}   AMPLIFICA_CONTROLLO=${CFG.AMPLIFICA_CONTROLLO}`);

// ============================================================
//  TEST 5 — Tabellino di esempio (controllo di plausibilita a occhio)
// ============================================================

function test5() {
  setSeed(9099);
  const A = creaRosa('Casa', 83), B = creaRosa('Ospite', 80);
  A.esperienzaModulo['4-3-3'] = 20; B.esperienzaModulo['3-5-2'] = 4;
  const r = simulaPartita(A, B, '4-3-3', '3-5-2', { statsGiocatori: true, usaCondizione: true });
  console.log('\n' + '='.repeat(78));
  console.log('TEST 5 — TABELLINO DI ESEMPIO   (Casa OVR83 4-3-3  vs  Ospite OVR80 3-5-2)');
  console.log('='.repeat(78));
  console.log(`\n  RISULTATO:  ${r.golC} - ${r.golO}\n`);
  const t = (n, s) => `  ${n.padEnd(10)} poss ${(s.possesso*100).toFixed(0)}%  tiri ${String(s.tiri).padStart(2)} (${s.inPorta} in porta)  pass ${s.passaggiR}/${s.passaggiT} (${(s.passaggiPct*100).toFixed(0)}%)  contr ${s.contrasti}  drib ${s.dribbling}`;
  console.log(t('CASA', r.statsCasa));
  console.log(t('OSPITE', r.statsOspite));
  console.log(`\n  Marcatori casa:   ${r.perGiocatore.casa.marcatori.join(', ') || '-'}`);
  console.log(`  Marcatori ospite: ${r.perGiocatore.ospite.marcatori.join(', ') || '-'}`);
  const lc = schiera(A, '4-3-3');
  console.log('\n  Top statistiche individuali CASA:');
  console.log('   giocatore        tiri  passaggi  contrasti  dribbling');
  const pg = r.perGiocatore.casa;
  [...pg.passaggi.entries()].sort((a,b)=>b[1]-a[1]).slice(0,6).forEach(([id]) => {
    const g = A.giocatori.find(x=>x.id===id);
    console.log(`   ${g.nome.padEnd(14)} ${String(pg.tiri.get(id)||0).padStart(4)} ${String(pg.passaggi.get(id)||0).padStart(9)} ${String(pg.contrasti.get(id)||0).padStart(10)} ${String(pg.dribbling.get(id)||0).padStart(10)}`);
  });
}

if (args.includes('--sweep')) { sweep(); }
else { test1(); test2(); test3(); test4(); test5(); }
verificaFormazioneUtente();
