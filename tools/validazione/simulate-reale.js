// ============================================================
//  VALIDAZIONE IN CONDIZIONI DI PRODUZIONE
//  node tools/validazione/simulate-reale.js
//
//  PERCHE' ESISTE
//  simulate.js valida il motore nella configurazione della Fase 0: 4-3-3
//  contro 4-3-3 (o moduli uniformemente casuali), nessuno stile di gioco,
//  rose costruite su misura per il modulo. Il gioco pero' non gira piu'
//  cosi'. Gli stili sono stati aggiunti dopo la validazione e la suite non
//  li passa mai; i moduli reali non sono affatto uniformi; e gli undici
//  schierati dai partecipanti sono molto piu' disomogenei di una rosa
//  sintetica perfetta.
//
//  Il risultato e' che la suite storica dava (e da' tuttora) tutto OK
//  mentre le leghe vere producevano 3.7-4.3 gol a partita contro un
//  target di 2.50-2.90. Non era un difetto del motore — verificato
//  riproducendo una partita di produzione dal suo seed: stesso identico
//  risultato — ma di cosa il motore riceve in ingresso.
//
//  Questo file NON cambia nulla nel gioco: come tutto tools/validazione,
//  e' codice di test. engine/ non importa niente da qui (CLAUDE.md §4).
//  Serve come metro di misura PRIMA di ritarare qualunque costante: senza,
//  una modifica agli STILI non sarebbe verificabile.
//
//  I NUMERI DELLA REALTA'
//  Le distribuzioni qui sotto sono misurate sulle 80 partite della lega 63
//  (Serie F) l'8 settembre 2026, non inventate. Vanno riaggiornate se il
//  comportamento dei partecipanti cambia in modo evidente.
//
//  LO SCARTO E' SPIEGATO PER INTERO. In ordine di peso:
//
//   1. FAMILIARITA' (+0.90 gol) — il fattore piu' grosso, ed era invisibile.
//      roster.js crea le rose con esperienzaModulo vuoto, quindi tutta la
//      validazione gira col malus al massimo (-3.5). Una squadra vera esce
//      da quello stato dopo 5 partite: in Serie F il malus medio della lega
//      e' -0.31 su 3.5. Vedi TEST E.
//   2. STILI (+0.56 gol) — aggiunti dopo la Fase 0, mai passati alla suite.
//      Vedi TEST B.
//   3. MODULI reali (+0.13 gol) — la produzione gioca offensivo, non
//      uniformemente a caso.
//   4. FUORI RUOLO: nessun effetto (-0.08). Ipotesi verificata e scartata,
//      vedi TEST C, che resta apposta come risultato negativo.
//
//  Catena completa: 2.45 (suite storica) -> 3.35 -> 3.48 -> 4.04 gol,
//  contro i 4.33 misurati in produzione, con i tiri a 19.2 contro 19.6.
//  Il modello e' fedele, quindi utilizzabile come bersaglio di taratura.
//
//  Il residuo, verificato a parte su un laboratorio costruito con le 16 rose
//  vere di Serie F (attributi FC 26, formazioni e panchine reali), che
//  riproduce 4.28 gol: gli attributi veri valgono 1.02x e la condizione
//  reale 1.04x, entrambi trascurabili.
// ============================================================

import { CFG, MODULI, STILI } from '../../engine/config.js';
import { creaRosaPerModulo, setSeed, rnd } from './roster.js';
import { simulaPartita, schiera, forzeLinee, strutturale } from '../../engine/engine.js';

const media = a => a.reduce((x, y) => x + y, 0) / a.length;
const dev = a => { const m = media(a); return Math.sqrt(media(a.map(v => (v - m) ** 2))); };

function riga(label, val, min, max, fmt = v => v.toFixed(2)) {
  const ok = val >= min && val <= max;
  return `${label.padEnd(34)} ${fmt(val).padStart(8)}   target ${fmt(min)}–${fmt(max)}  ${ok ? '  OK ' : ' FUORI'}`;
}

// ------------------------------------------------------------
//  Distribuzioni misurate in produzione (Serie F, 160 schieramenti)
// ------------------------------------------------------------
const MIX_STILE = [
  ['fasce', 0.281], ['equilibrato', 0.269], ['diretto', 0.188], ['contropiede', 0.131],
  ['recupero_veloce', 0.063], ['possesso_palla', 0.063], ['blocco_basso', 0.006],
];
const MIX_MODULO = [
  ['4-3-3 offensivo', 0.431], ['4-4-2', 0.338], ['4-3-3', 0.106], ['3-4-3', 0.063],
  ['4-2-4', 0.038], ['3-5-2', 0.013], ['4-2-3-1', 0.006], ['5-3-2', 0.006],
];
// Overall efficace medio dell'undici realmente schierato in Serie F.
const OVR_XI_REALE = 73.5;

// Le rose sintetiche nascono con esperienzaModulo vuoto, cioe' con il malus
// di familiarita' al massimo. Questa funzione le porta allo stato in cui una
// squadra vera passa la quasi totalita' della stagione: familiarita' piena.
// Misurato in Serie F: malus medio della lega -0.31 su un massimo di -3.5.
function conFamiliaritaPiena(rosa, modulo, stile) {
  rosa.esperienzaModulo = { [modulo]: CFG.FAM_PARTITE_PIENA };
  rosa.esperienzaStile = stile ? { [stile]: CFG.FAM_PARTITE_PIENA } : {};
  return rosa;
}

function pescaDa(mix) {
  let x = rnd();
  for (const [valore, p] of mix) { if ((x -= p) <= 0) return valore; }
  return mix[0][0];
}

// Schieramento "come lo fanno i partecipanti": una quota di titolari finisce
// in uno slot che non copre. NON e' rumore gaussiano sull'overall — provato,
// non riproduce niente: la varianza vera nasce dalla penalita' fuori ruolo,
// che e' brutale e a gradini. In produzione il caso peggiore osservato era un
// terzino destro schierato centravanti: overall 72, efficace 38.
//
// Misurato in Serie F: 9.4% dei titolari fuori ruolo.
const QUOTA_FUORI_RUOLO_REALE = 0.094;

function schieraConErrori(rosa, modulo, quotaFuoriRuolo) {
  const lineup = schiera(rosa, modulo);
  if (quotaFuoriRuolo <= 0) return lineup;
  // Si scambiano fra loro due titolari a caso: chi si ritrova in uno slot
  // che non copre paga la penalita', esattamente come nel gioco vero.
  const scambi = Math.round(lineup.titolari.length * quotaFuoriRuolo / 2);
  for (let s = 0; s < scambi; s++) {
    // il portiere resta fuori dallo scambio: schierare un attaccante in porta
    // e' un errore che nessuno commette, e falserebbe tutto da solo
    const i = 1 + Math.floor(rnd() * (lineup.titolari.length - 1));
    let j = 1 + Math.floor(rnd() * (lineup.titolari.length - 1));
    if (i === j) j = 1 + ((i + 3) % (lineup.titolari.length - 1));
    const t = lineup.titolari[i];
    lineup.titolari[i] = lineup.titolari[j];
    lineup.titolari[j] = t;
  }
  return lineup;
}

function quotaEffettivaFuoriRuolo(lineup) {
  let fuori = 0;
  for (let i = 0; i < lineup.titolari.length; i++) {
    if (!lineup.titolari[i].posizioni.includes(lineup.slots[i])) fuori++;
  }
  return fuori / lineup.titolari.length;
}

// ============================================================
//  TEST A — STAGIONI COMPLETE IN CONDIZIONI DI PRODUZIONE
//  Stessi target della Fase 0: mostrano di quanto la configurazione reale
//  li sfonda. E' il numero che una ritaratura degli STILI deve riportare
//  dentro.
// ============================================================
function testA() {
  const N = 20000;
  console.log('\n' + '='.repeat(78));
  console.log('TEST A — CONFIGURAZIONE DI PRODUZIONE (moduli e stili con le quote reali)');
  console.log('='.repeat(78));

  const scenari = [
    ['come la suite storica (nessuna familiarita\')', false, false, 0, false],
    ['+ familiarita\' piena (stato normale vero)', false, false, 0, true],
    ['+ moduli reali', true, false, 0, true],
    ['+ stili reali', true, true, 0, true],
    ['+ fuori ruolo reali = PRODUZIONE', true, true, QUOTA_FUORI_RUOLO_REALE, true],
  ];

  for (const [etichetta, usaModuli, usaStili, quotaFuori, famPiena] of scenari) {
    setSeed(4242);
    let gol = 0, tiri = 0, pari = 0, vinteCasa = 0, fuoriRuolo = 0;
    for (let i = 0; i < N; i++) {
      const mA = usaModuli ? pescaDa(MIX_MODULO) : '4-3-3';
      const mB = usaModuli ? pescaDa(MIX_MODULO) : '4-3-3';
      const stA = usaStili ? pescaDa(MIX_STILE) : undefined;
      const stB = usaStili ? pescaDa(MIX_STILE) : undefined;
      let A = creaRosaPerModulo('A', OVR_XI_REALE - 3, MODULI[mA]);
      let B = creaRosaPerModulo('B', OVR_XI_REALE - 3, MODULI[mB]);
      if (famPiena) { conFamiliaritaPiena(A, mA, stA); conFamiliaritaPiena(B, mB, stB); }
      const lc = schieraConErrori(A, mA, quotaFuori);
      const lo = schieraConErrori(B, mB, quotaFuori);
      fuoriRuolo += (quotaEffettivaFuoriRuolo(lc) + quotaEffettivaFuoriRuolo(lo)) / 2;
      const r = simulaPartita(A, B, mA, mB, {
        usaCondizione: true,
        statsGiocatori: true,
        lineupCasa: lc,
        lineupOspite: lo,
        stileCasa: stA,
        stileOspite: stB,
      });
      gol += r.golC + r.golO;
      tiri += (r.statsCasa.tiri + r.statsOspite.tiri) / 2;
      if (r.golC === r.golO) pari++; else if (r.golC > r.golO) vinteCasa++;
    }
    console.log(`\n  ${etichetta}` +
      (quotaFuori > 0 ? `   (fuori ruolo effettivi: ${(100 * fuoriRuolo / N).toFixed(1)}%, reali 9.4%)` : ''));
    console.log('  ' + riga('Gol per partita', gol / N, 2.50, 2.90));
    console.log('  ' + riga('Tiri per squadra', tiri / N, 11.0, 14.0));
    console.log('  ' + riga('Pareggi %', 100 * pari / N, 23.0, 27.0, v => v.toFixed(1)));
    console.log('  ' + riga('Vittorie casa %', 100 * vinteCasa / N, 43.0, 47.0, v => v.toFixed(1)));
  }

  console.log('\n  Riferimento misurato in produzione (Serie F, 80 partite):');
  console.log('    gol 4.33   tiri/squadra 19.6   pareggi 15.0%   vittorie casa 58.8%');
}

// ============================================================
//  TEST B — MATRICE STILE CONTRO STILE
//  Il commento in config.js dice che nessuno stile e' un buff netto,
//  perche' la redistribuzione DEF/MID/ATT e' a somma zero. E' vero sui
//  punti di overall e falso sui GOL: l'xG e' esponenziale, quindi spostare
//  peso sull'attacco ne aggiunge piu' di quanti la difesa ne tolga.
//  Questa matrice rende quello squilibrio visibile a colpo d'occhio, ed e'
//  il pannello da guardare dopo ogni ritaratura degli STILI.
// ============================================================
function testB() {
  const N = 2500;
  const stili = Object.keys(STILI);
  console.log('\n' + '='.repeat(78));
  console.log('TEST B — GOL TOTALI PER ACCOPPIAMENTO DI STILI  (squadre pari, 4-3-3)');
  console.log('='.repeat(78));
  console.log('  Un motore equilibrato dovrebbe tenere tutte le caselle vicine al target');
  console.log('  2.50-2.90. Lo scarto fra la casella piu\' alta e la piu\' bassa e\' la');
  console.log('  misura di quanto lo stile pesa sui gol invece che solo sull\'enfasi.\n');

  process.stdout.write('  casa \\ ospite'.padEnd(20));
  for (const s of stili) process.stdout.write(s.slice(0, 8).padStart(9));
  console.log();

  let alta = { v: -1 }, bassa = { v: 99 };
  for (const sc of stili) {
    process.stdout.write('  ' + sc.slice(0, 17).padEnd(18));
    for (const so of stili) {
      setSeed(999);
      let gol = 0;
      for (let i = 0; i < N; i++) {
        // a familiarita' piena: e' il punto di lavoro in cui le squadre vere
        // passano la stagione, e l'unico su cui abbia senso giudicare gli stili
        const A = conFamiliaritaPiena(creaRosaPerModulo('A', OVR_XI_REALE - 3, MODULI['4-3-3']), '4-3-3', sc);
        const B = conFamiliaritaPiena(creaRosaPerModulo('B', OVR_XI_REALE - 3, MODULI['4-3-3']), '4-3-3', so);
        const r = simulaPartita(A, B, '4-3-3', '4-3-3', { usaCondizione: false, stileCasa: sc, stileOspite: so });
        gol += r.golC + r.golO;
      }
      const m = gol / N;
      if (m > alta.v) alta = { v: m, sc, so };
      if (m < bassa.v) bassa = { v: m, sc, so };
      process.stdout.write(m.toFixed(2).padStart(9));
    }
    console.log();
  }
  console.log(`\n  piu' alta: ${alta.v.toFixed(2)} (${alta.sc} vs ${alta.so})`);
  console.log(`  piu' bassa: ${bassa.v.toFixed(2)} (${bassa.sc} vs ${bassa.so})`);
  // Soglia 1.5: sopra, lo stile sposta i gol piu' di quanto faccia un divario
  // di 4 punti di overall fra le squadre, cioe' conta piu' della forza. Prima
  // del 9 settembre 2026 l'escursione era 3.20.
  console.log(`  ESCURSIONE: ${(alta.v - bassa.v).toFixed(2)} gol` +
    `   ${alta.v - bassa.v > 1.5 ? '<-- lo stile pesa piu\' del divario di forza' : '(sotto la soglia di 1.5)'}`);
}

// ============================================================
//  TEST C — RISULTATO NEGATIVO, TENUTO APPOSTA.
//  L'ipotesi di partenza era che gli undici veri, piu' irregolari,
//  gonfiassero i gol attraverso la convessita' di exp(): il caso limite
//  osservato in produzione era un terzino destro schierato centravanti
//  (overall 72, efficace 38). La misura dice di no: la riga al livello
//  reale (9.4%) e' identica a quella a zero, e perfino spingendo al 27%
//  non si muove. Il fuori ruolo abbassa entrambe le squadre e i due
//  effetti si annullano.
//  Il test resta per due motivi: perche' l'ipotesi non venga riproposta,
//  e perche' se una ritaratura futura la rendesse vera si vedrebbe qui.
// ============================================================
function testC() {
  const N = 6000;
  console.log('\n' + '='.repeat(78));
  console.log('TEST C — TITOLARI FUORI RUOLO (a parita\' di rosa e di forza media)');
  console.log('='.repeat(78));
  console.log('  Il differenziale ATT-DEF e\' cio\' che finisce nell\'esponente dell\'xG:');
  console.log('  conta la sua DISPERSIONE, non solo la media, perche\' exp() e\' convessa.\n');
  console.log('  fuori ruolo   dev.std ATT-DEF   gol/partita   tiri/sq');

  for (const q of [0, 0.094, 0.18, 0.27]) {
    setSeed(4242);
    let gol = 0, tiri = 0;
    const differenziali = [];
    for (let i = 0; i < N; i++) {
      const A = creaRosaPerModulo('A', OVR_XI_REALE - 3, MODULI['4-3-3']);
      const B = creaRosaPerModulo('B', OVR_XI_REALE - 3, MODULI['4-3-3']);
      const la = schieraConErrori(A, '4-3-3', q), lb = schieraConErrori(B, '4-3-3', q);
      if (i < 400) {
        const fa = forzeLinee(la), fb = forzeLinee(lb);
        const sa = strutturale(fa), sb = strutturale(fb);
        differenziali.push((fa.ATT + sa.ATT) - (fb.DEF + sb.DEF));
        differenziali.push((fb.ATT + sb.ATT) - (fa.DEF + sa.DEF));
      }
      const r = simulaPartita(A, B, '4-3-3', '4-3-3', {
        usaCondizione: true, statsGiocatori: true, lineupCasa: la, lineupOspite: lb,
      });
      gol += r.golC + r.golO;
      tiri += (r.statsCasa.tiri + r.statsOspite.tiri) / 2;
    }
    const nota = Math.abs(q - QUOTA_FUORI_RUOLO_REALE) < 0.001 ? '  <-- livello reale (Serie F)' : '';
    console.log(`  ${(100 * q).toFixed(1).padStart(10)}%   ${dev(differenziali).toFixed(1).padStart(14)}   ` +
      `${(gol / N).toFixed(2).padStart(11)}   ${(tiri / N).toFixed(1).padStart(7)}${nota}`);
  }
  console.log('\n  dispersione misurata in produzione: 6.2');
}

// ============================================================
//  TEST D — QUANTO PESA OGNI FATTORE
//  Scomposizione moltiplicativa: i due fattori non si sommano, si
//  moltiplicano, perche' agiscono sullo stesso esponente.
// ============================================================
function testD() {
  const N = 12000;
  console.log('\n' + '='.repeat(78));
  console.log('TEST D — SCOMPOSIZIONE DELLO SCARTO');
  console.log('='.repeat(78));

  const misura = ({ stili = false, fuori = 0, fam = false, moduli = false } = {}) => {
    setSeed(4242);
    let gol = 0;
    for (let i = 0; i < N; i++) {
      const m = moduli ? pescaDa(MIX_MODULO) : '4-3-3';
      const st = stili ? pescaDa(MIX_STILE) : undefined;
      const A = creaRosaPerModulo('A', OVR_XI_REALE - 3, MODULI[m]);
      const B = creaRosaPerModulo('B', OVR_XI_REALE - 3, MODULI[m]);
      if (fam) { conFamiliaritaPiena(A, m, st); conFamiliaritaPiena(B, m, st); }
      const r = simulaPartita(A, B, m, m, {
        usaCondizione: true,
        lineupCasa: schieraConErrori(A, m, fuori),
        lineupOspite: schieraConErrori(B, m, fuori),
        stileCasa: st,
        stileOspite: stili ? pescaDa(MIX_STILE) : undefined,
      });
      gol += r.golC + r.golO;
    }
    return gol / N;
  };

  // ogni fattore preso DA SOLO, a partire dalla configurazione della suite storica
  const base = misura({});
  const soloFam = misura({ fam: true });
  const soloStili = misura({ stili: true });
  const soloModuli = misura({ moduli: true });
  const soloFuori = misura({ fuori: QUOTA_FUORI_RUOLO_REALE });
  const tutto = misura({ fam: true, stili: true, moduli: true, fuori: QUOTA_FUORI_RUOLO_REALE });

  const r2 = (v) => `${v.toFixed(2).padStart(5)} gol   ${(v / base).toFixed(2)}x   ${(v - base >= 0 ? '+' : '')}${(v - base).toFixed(2)}`;
  console.log(`\n  ${'partenza: configurazione della suite storica'.padEnd(46)} ${base.toFixed(2)} gol`);
  console.log(`\n  ogni fattore da solo:`);
  console.log(`  ${'  familiarita\' piena'.padEnd(46)} ${r2(soloFam)}`);
  console.log(`  ${'  stili reali'.padEnd(46)} ${r2(soloStili)}`);
  console.log(`  ${'  moduli reali'.padEnd(46)} ${r2(soloModuli)}`);
  console.log(`  ${'  fuori ruolo reali'.padEnd(46)} ${r2(soloFuori)}`);
  console.log(`\n  ${'tutti insieme'.padEnd(46)} ${r2(tutto)}`);
  console.log(`\n  Serie F misurata: 4.33 gol.  Il modello ne riproduce ${tutto.toFixed(2)} ` +
    `(${(100 * tutto / 4.33).toFixed(0)}% dello scarto osservato).`);
}

console.log('CONFIG:  SENSIBILITA_FORZA=' + CFG.SENSIBILITA_FORZA +
  '   XG_BASE_BLOCCO=' + CFG.XG_BASE_BLOCCO +
  '   AMPLIFICA_CONTROLLO=' + CFG.AMPLIFICA_CONTROLLO);
console.log('\nValidazione nelle condizioni in cui il gioco gira davvero.');
console.log('I target restano quelli della Fase 0: mostrano di quanto la realta\' li sfonda.');

// ============================================================
//  TEST E — LA FAMILIARITA', PUNTO CIECO DELLA SUITE STORICA.
//
//  E' il fattore piu' pesante, ed era invisibile: roster.js crea le rose con
//  esperienzaModulo vuoto, quindi TUTTA la validazione (test 1, 2 e 3
//  compresi, quelli che fissano i target) gira con il malus al massimo,
//  -3.5. Una squadra vera esce da quello stato dopo 5 partite e ci resta
//  fuori per il resto della carriera: in Serie F il malus medio della lega
//  e' -0.31 su 3.5, cioe' praticamente zero.
//
//  Il malus, inoltre, NON e' simmetrico: engine.js lo somma ad ATT e MID,
//  mai a DEF. Non e' quindi "due squadre un po' piu' deboli", e' "due
//  attacchi piu' deboli contro due difese intatte". Toglierlo libera gli
//  attacchi di 3.5 punti, che nell'esponenziale dell'xG valgono exp(0.09*3.5)
//  = 1.37x.
//
//  Conseguenza pratica da tenere a mente: il cambio di FAM_PARTITE_PIENA da
//  15 a 5 (3 settembre 2026) ha triplicato la velocita' con cui le squadre
//  raggiungono lo stato scarico, e la suite storica NON avrebbe potuto
//  rilevarlo, perche' li' l'esperienza non si accumula mai.
// ============================================================
function testE() {
  const N = 12000;
  console.log('\n' + '='.repeat(78));
  console.log('TEST E — EFFETTO DELLA FAMILIARITA\' (moduli e stili reali)');
  console.log('='.repeat(78));
  console.log('  partite col   malus');
  console.log('  stesso modulo ATT/MID   gol/partita   tiri/sq');

  for (const p of [0, 1, 2, 3, 4, 5]) {
    setSeed(4242);
    let gol = 0, tiri = 0;
    for (let i = 0; i < N; i++) {
      const mA = pescaDa(MIX_MODULO), mB = pescaDa(MIX_MODULO);
      const stA = pescaDa(MIX_STILE), stB = pescaDa(MIX_STILE);
      const A = creaRosaPerModulo('A', OVR_XI_REALE - 3, MODULI[mA]);
      const B = creaRosaPerModulo('B', OVR_XI_REALE - 3, MODULI[mB]);
      A.esperienzaModulo = { [mA]: p }; A.esperienzaStile = { [stA]: p };
      B.esperienzaModulo = { [mB]: p }; B.esperienzaStile = { [stB]: p };
      const r = simulaPartita(A, B, mA, mB, {
        usaCondizione: true, statsGiocatori: true, stileCasa: stA, stileOspite: stB,
      });
      gol += r.golC + r.golO;
      tiri += (r.statsCasa.tiri + r.statsOspite.tiri) / 2;
    }
    const malus = -CFG.FAM_MALUS_MAX * (1 - Math.min(1, p / CFG.FAM_PARTITE_PIENA));
    const nota = p === 0 ? '  <-- stato in cui gira la suite storica'
      : p >= CFG.FAM_PARTITE_PIENA ? '  <-- stato normale di una squadra vera' : '';
    console.log(`  ${String(p).padStart(13)} ${malus.toFixed(2).padStart(7)}   ` +
      `${(gol / N).toFixed(2).padStart(11)}   ${(tiri / N).toFixed(1).padStart(7)}${nota}`);
  }
  console.log('\n  Malus medio misurato in Serie F: -0.31 (le squadre sono tutte a regime).');
}

testA();
testB();
testC();
testD();
testE();
