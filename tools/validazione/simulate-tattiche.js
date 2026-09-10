// ============================================================
//  MISURA DEL SISTEMA TATTICO — node tools/validazione/simulate-tattiche.js
//
//  Risponde con dei numeri alle tre domande poste prima di progettare il
//  prossimo update. NON tocca il gioco: gira in locale, usa il motore
//  validato attraverso il prototipo in tattiche-prototipo.js, e non scrive
//  niente da nessuna parte.
//
//  L'unita' di misura di tutto e' "punti di overall equivalenti", perche' e'
//  l'unica scala che il progetto conosce gia': dal TEST 2 della Fase 0
//  sappiamo che +4 di overall valgono il 63% di vittorie e +8 l'84%. Dire
//  "questa tattica vale 3 punti" e' quindi immediatamente interpretabile,
//  dire "vale il 12%" no.
// ============================================================

import { MODULI } from '../../engine/config.js';
import { simulaPartita, schiera } from '../../engine/engine.js';
import { creaRosaPerModulo, setSeed } from './roster.js';
import {
  ASSI, SCALE, arricchisci, rosaConTattiche, tuttiGliAssetti, etichetta, sbilanciaInterpreti,
} from './tattiche-prototipo.js';

const OVR = 70.5;              // stesso livello usato da simulate-reale.js
const MODULO = '4-3-3';
const N = 4000;

function creaSquadra(nome, ovr = OVR) {
  return arricchisci(creaRosaPerModulo(nome, ovr, MODULI[MODULO]));
}

// Una serie di partite fra due assetti. Ritorna la quota di vittorie di A.
// Campo neutro e familiarita' piena: qui interessa isolare la tattica, non
// rimisurare il fattore campo o il malus di familiarita'.
function serie(assettoA, assettoB, { ovrA = OVR, ovrB = OVR, modificaA, modificaB, seme = 4242 } = {}) {
  setSeed(seme);
  let vinteA = 0, pariA = 0, golA = 0, golB = 0;
  for (let i = 0; i < N; i++) {
    let A = creaSquadra('A', ovrA), B = creaSquadra('B', ovrB);
    if (modificaA) A = modificaA(A);
    if (modificaB) B = modificaB(B);
    A.esperienzaModulo = { [MODULO]: 5 }; B.esperienzaModulo = { [MODULO]: 5 };
    const la = schiera(A, MODULO), lb = schiera(B, MODULO);
    const At = rosaConTattiche(A, la, assettoA, assettoB);
    const Bt = rosaConTattiche(B, lb, assettoB, assettoA);
    // le lineup vanno ricostruite sulle rose modificate, altrimenti i
    // titolari resterebbero i vecchi oggetti con l'overall non aggiornato
    const r = simulaPartita(At, Bt, MODULO, MODULO, {
      usaCondizione: true, campoNeutro: true,
      lineupCasa: schiera(At, MODULO), lineupOspite: schiera(Bt, MODULO),
    });
    golA += r.golC; golB += r.golO;
    if (r.golC > r.golO) vinteA++; else if (r.golC === r.golO) pariA++;
  }
  return { vittorie: 100 * vinteA / N, pareggi: 100 * pariA / N, golA: golA / N, golB: golB / N };
}

// Converte una quota di vittorie in "punti di overall equivalenti", usando
// la curva vera del motore misurata adesso. E' il ponte che rende
// interpretabile ogni numero di questo file.
function costruisciScala() {
  const NEUTRO = { linea: 'media', costruzione: 'mista' };
  const punti = [];
  for (const gap of [0, 1, 2, 3, 4, 6, 8]) {
    const r = serie(NEUTRO, NEUTRO, { ovrA: OVR + gap / 2, ovrB: OVR - gap / 2, seme: 77 });
    punti.push({ gap, vittorie: r.vittorie });
  }
  return punti;
}

function inPuntiOverall(vittorie, scala) {
  // interpolazione lineare fra i due punti della scala che la contengono
  for (let i = 0; i < scala.length - 1; i++) {
    const a = scala[i], b = scala[i + 1];
    if (vittorie >= a.vittorie && vittorie <= b.vittorie) {
      const t = (vittorie - a.vittorie) / (b.vittorie - a.vittorie || 1);
      return a.gap + t * (b.gap - a.gap);
    }
  }
  return vittorie > scala[scala.length - 1].vittorie ? scala[scala.length - 1].gap : 0;
}

console.log('MISURA DEL SISTEMA TATTICO (prototipo, il gioco non e\' toccato)');
console.log(`scale in prova: interpreti ${SCALE.INTERPRETI}, contrasto ${SCALE.COUNTER}`);
console.log(`${N} partite per confronto, campo neutro, familiarita' piena, rose pari a OVR ${OVR}\n`);

// ============================================================
//  SCALA DI RIFERIMENTO
// ============================================================
console.log('='.repeat(74));
console.log('SCALA — quanto vale un punto di overall, misurato adesso');
console.log('='.repeat(74));
const scala = costruisciScala();
for (const p of scala) {
  console.log(`  +${p.gap} overall  ->  ${p.vittorie.toFixed(1)}% vittorie`);
}

// ============================================================
//  DOMANDA 2 — il triangolo regge o collassa?
//  Si mette ogni assetto contro ogni altro e si guarda la media delle
//  vittorie. Se un assetto vince contro tutti, e' l'ottimo unico e il
//  sistema e' fallito: in due settimane giocherebbero tutti cosi'.
// ============================================================
console.log('\n' + '='.repeat(74));
console.log('DOMANDA 2 — esiste un assetto che batte tutti gli altri?');
console.log('='.repeat(74));
const assetti = tuttiGliAssetti();
const media = new Map();
const matrice = new Map();
for (const a of assetti) {
  let somma = 0;
  for (const b of assetti) {
    const r = serie(a, b, { seme: 999 });
    matrice.set(`${etichetta(a)}|${etichetta(b)}`, r.vittorie);
    somma += r.vittorie;
  }
  media.set(etichetta(a), somma / assetti.length);
}
const ordinati = [...media.entries()].sort((x, y) => y[1] - x[1]);
console.log('\n  media delle vittorie di ogni assetto contro TUTTI gli altri:');
for (const [nome, m] of ordinati) {
  console.log(`    ${nome.padEnd(34)} ${m.toFixed(1)}%`);
}
const spread = ordinati[0][1] - ordinati[ordinati.length - 1][1];
console.log(`\n  scarto fra il migliore e il peggiore: ${spread.toFixed(1)} punti percentuali`);
console.log(`  = ${inPuntiOverall(50 + spread / 2, scala).toFixed(1)} punti di overall equivalenti`);
console.log(spread < 6
  ? '  -> nessun assetto domina: il sistema regge (le differenze vengono dai confronti, non dalla scelta in se)'
  : '  -> ATTENZIONE: esiste un assetto tendenzialmente migliore, il triangolo non basta a bilanciare');

// verifica esplicita del triangolo: ogni assetto deve avere almeno un
// avversario che lo batte. E' la definizione operativa di morra cinese.
console.log('\n  ogni assetto ha un avversario che lo batte?');
let triangoloOk = true;
for (const a of assetti) {
  let peggiore = { v: 101 };
  for (const b of assetti) {
    const v = matrice.get(`${etichetta(a)}|${etichetta(b)}`);
    if (v < peggiore.v) peggiore = { v, b };
  }
  const battuto = peggiore.v < 47;
  if (!battuto) triangoloOk = false;
  console.log(`    ${etichetta(a).padEnd(34)} peggiore contro ${etichetta(peggiore.b).padEnd(32)} ${peggiore.v.toFixed(1)}%  ${battuto ? '' : '<-- non lo batte nessuno'}`);
}
console.log(triangoloOk
  ? '  -> ogni assetto ha il suo contrasto: morra cinese confermata'
  : '  -> qualche assetto non e\' battuto da nessuno: da rivedere');

// ============================================================
//  DOMANDA 1 — quanto vale indovinare la tattica?
// ============================================================
console.log('\n' + '='.repeat(74));
console.log('DOMANDA 1 — quanto vale la tattica giusta contro quella sbagliata?');
console.log('='.repeat(74));
let miglioreConfronto = { v: -1 };
for (const a of assetti) {
  for (const b of assetti) {
    const v = matrice.get(`${etichetta(a)}|${etichetta(b)}`);
    if (v > miglioreConfronto.v) miglioreConfronto = { v, a, b };
  }
}
console.log(`\n  confronto piu' squilibrato: ${etichetta(miglioreConfronto.a)}`);
console.log(`                       contro ${etichetta(miglioreConfronto.b)}`);
console.log(`  vittorie: ${miglioreConfronto.v.toFixed(1)}%`);
const valeTattica = inPuntiOverall(miglioreConfronto.v, scala);
console.log(`  = ${valeTattica.toFixed(1)} punti di overall equivalenti`);
console.log(valeTattica < 8
  ? `  -> sotto la soglia di 8: una rosa nettamente piu' forte resta favorita`
  : `  -> SOPRA la soglia di 8: la tattica conterebbe piu' della qualita' della rosa`);

// ============================================================
//  DOMANDA 3 — quanto pesano gli interpreti?
//  Stesso assetto per entrambe, stesse rose, ma a una squadra si alzano e
//  all'altra si abbassano gli attributi che quella tattica richiede.
// ============================================================
console.log('\n' + '='.repeat(74));
console.log('DOMANDA 3 — quanto vale avere gli interpreti giusti?');
console.log('='.repeat(74));
console.log('  stesso assetto per entrambe, stessa forza: cambia solo l\'attributo richiesto\n');
for (const [asse, chiave] of [['linea', 'alta'], ['linea', 'bassa'], ['costruzione', 'corta'], ['costruzione', 'verticale']]) {
  const opzione = ASSI[asse][chiave];
  const assetto = asse === 'linea'
    ? { linea: chiave, costruzione: 'mista' }
    : { linea: 'media', costruzione: chiave };
  const r = serie(assetto, assetto, {
    modificaA: (rosa) => sbilanciaInterpreti(rosa, opzione.attributo, +1),
    modificaB: (rosa) => sbilanciaInterpreti(rosa, opzione.attributo, -1),
    seme: 31337,
  });
  const punti = inPuntiOverall(r.vittorie, scala);
  console.log(`  ${opzione.etichetta.padEnd(18)} (${opzione.attributo})`);
  console.log(`     interpreti giusti vs sbagliati: ${r.vittorie.toFixed(1)}% vittorie  = ${punti.toFixed(1)} punti di overall\n`);
}

console.log('='.repeat(74));
console.log('Le scale si cambiano in cima a tattiche-prototipo.js (SCALE).');
console.log('Nessun file del gioco e\' stato toccato da questa esecuzione.');
