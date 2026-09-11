// ============================================================
//  MISURA DEL SISTEMA TATTICO — node tools/validazione/simulate-tattiche.js
//
//  Non tocca il gioco: gira in locale, usa il motore validato attraverso il
//  prototipo, non scrive da nessuna parte.
//
//  Tutto e' espresso in PUNTI DI OVERALL EQUIVALENTI, l'unica scala che il
//  progetto conosce gia' (Fase 0: +4 = 63% di vittorie, +8 = 84%). La scala
//  viene rimisurata a ogni esecuzione invece di essere copiata dai documenti.
// ============================================================

import { MODULI } from '../../engine/config.js';
import { simulaPartita, schiera } from '../../engine/engine.js';
import { creaRosaPerModulo, setSeed } from './roster.js';
import {
  ASSI, SCALE, arricchisci, rosaConTattiche, rosaPerProfilo,
  tuttiGliAssetti, etichetta,
} from './tattiche-prototipo.js';

const OVR = 70.5;
const MODULO = '4-3-3';
const N = 3000;
const NEUTRO = { linea: 'media', costruzione: 'mista' };

const creaSquadra = (nome, ovr = OVR) => arricchisci(creaRosaPerModulo(nome, ovr, MODULI[MODULO]));

// Una serie fra due piani. identitaA/B assenti = nessun costo di
// snaturamento (si sta misurando altro).
function serie(pianoA, pianoB, opt = {}) {
  const { ovrA = OVR, ovrB = OVR, identitaA, identitaB, modificaA, modificaB, seme = 4242 } = opt;
  setSeed(seme);
  let vinteA = 0;
  for (let i = 0; i < N; i++) {
    let A = creaSquadra('A', ovrA), B = creaSquadra('B', ovrB);
    if (modificaA) A = modificaA(A);
    if (modificaB) B = modificaB(B);
    A.esperienzaModulo = { [MODULO]: 5 }; B.esperienzaModulo = { [MODULO]: 5 };
    const At = rosaConTattiche(A, schiera(A, MODULO), pianoA, pianoB, identitaA);
    const Bt = rosaConTattiche(B, schiera(B, MODULO), pianoB, pianoA, identitaB);
    const r = simulaPartita(At, Bt, MODULO, MODULO, {
      usaCondizione: true, campoNeutro: true,
      lineupCasa: schiera(At, MODULO), lineupOspite: schiera(Bt, MODULO),
    });
    if (r.golC > r.golO) vinteA++;
  }
  return 100 * vinteA / N;
}

// Ponte fra percentuali e punti di overall, misurato adesso sul motore.
const scala = (() => {
  const punti = [];
  for (const gap of [0, 1, 2, 3, 4, 6, 8]) {
    punti.push({ gap, v: serie(NEUTRO, NEUTRO, { ovrA: OVR + gap / 2, ovrB: OVR - gap / 2, seme: 77 }) });
  }
  return punti;
})();

function inPunti(vittorie) {
  for (let i = 0; i < scala.length - 1; i++) {
    const a = scala[i], b = scala[i + 1];
    if (vittorie >= a.v && vittorie <= b.v) {
      return a.gap + ((vittorie - a.v) / (b.v - a.v || 1)) * (b.gap - a.gap);
    }
  }
  return vittorie > scala[scala.length - 1].v ? scala[scala.length - 1].gap : 0;
}

console.log('MISURA DEL SISTEMA TATTICO (prototipo — il gioco non e\' toccato)');
console.log(`scale: interpreti ${SCALE.INTERPRETI}, contrasto ${SCALE.CONTRASTO}, snaturamento ${SCALE.SNATURAMENTO}`);
console.log(`${N} partite per confronto, campo neutro, rose pari a OVR ${OVR}\n`);
console.log('  scala di riferimento: ' + scala.map((p) => `+${p.gap}=${p.v.toFixed(0)}%`).join('  '));

// ============================================================
//  A — la matrice dei confronti
// ============================================================
const assetti = tuttiGliAssetti();
const M = new Map();
for (const a of assetti) for (const b of assetti) M.set(`${etichetta(a)}|${etichetta(b)}`, serie(a, b, { seme: 999 }));
const mediaDi = (a) => assetti.reduce((s, b) => s + M.get(`${etichetta(a)}|${etichetta(b)}`), 0) / assetti.length;

console.log('\n' + '='.repeat(74));
console.log('A — nessun assetto deve convenire sempre');
console.log('='.repeat(74));
const classifica = assetti.map((a) => ({ a, m: mediaDi(a) })).sort((x, y) => y.m - x.m);
for (const { a, m } of classifica) console.log(`  ${etichetta(a).padEnd(34)} ${m.toFixed(1)}% in media`);

const spread = classifica[0].m - classifica[classifica.length - 1].m;
// Le opzioni neutre sono volutamente le piu' deboli (confermato con
// l'utente: avere un piano batte non averlo), quindi includerle nello
// scarto misura una cosa che vogliamo. Il numero che conta e' lo scarto fra
// gli assetti SCHIERATI: li' nessuno deve convenire piu' degli altri.
const schierati = classifica.filter(({ a }) => a.linea !== 'media' && a.costruzione !== 'mista');
const spreadSchierati = schierati[0].m - schierati[schierati.length - 1].m;
const valeSempreIlMigliore = inPunti(50 + spreadSchierati / 2);
console.log(`\n  scarto fra tutti: ${spread.toFixed(1)} punti percentuali (include le opzioni neutre, volutamente deboli)`);
console.log(`  scarto fra i soli assetti schierati: ${spreadSchierati.toFixed(1)} punti percentuali  <- e' questo che conta`);

// ============================================================
//  B — leggere l'avversario deve pagare piu' che scegliere il solito
// ============================================================
let max = { v: -1 };
for (const a of assetti) for (const b of assetti) {
  const v = M.get(`${etichetta(a)}|${etichetta(b)}`);
  if (v > max.v) max = { v, a, b };
}

// Confronto ALLA PARI fra due strategie, non fra due numeri costruiti in
// modi diversi (era l'errore della prima versione di questa misura):
//   ALLA CIECA  gioco sempre il mio assetto migliore, senza guardare chi ho
//               davanti -> vinco quanto la sua media
//   INFORMATO   conosco il suo assetto e gli rispondo al meglio -> vinco,
//               per ogni avversario, il massimo di quella colonna
const allaCieca = Math.max(...assetti.map(mediaDi));
const informato = assetti
  .map((b) => Math.max(...assetti.map((a) => M.get(`${etichetta(a)}|${etichetta(b)}`))))
  .reduce((s, v) => s + v, 0) / assetti.length;

console.log('\n' + '='.repeat(74));
console.log('B — conviene leggere l\'avversario o scegliere sempre il solito assetto?');
console.log('='.repeat(74));
console.log(`\n  alla cieca (sempre il mio migliore)  ${allaCieca.toFixed(1)}% vittorie  = ${inPunti(allaCieca).toFixed(1)} punti di overall`);
console.log(`  informato (rispondo al suo assetto)  ${informato.toFixed(1)}% vittorie  = ${inPunti(informato).toFixed(1)} punti di overall`);
// Le due strategie messe sulla stessa unita': punti percentuali di vittorie
// guadagnati. Convertirne una in punti di overall e l'altra no produceva un
// confronto senza senso (errore della stesura precedente di questa misura).
const guadagnoLettura = informato - allaCieca;
console.log(`\n  guadagno del leggere l'avversario:            +${guadagnoLettura.toFixed(1)} punti percentuali`);
console.log(`  guadagno dello scegliere l'assetto migliore:  +${spreadSchierati.toFixed(1)} punti percentuali`);
console.log(`  rapporto: ${(guadagnoLettura / Math.max(spreadSchierati, 0.1)).toFixed(1)}x`);
console.log(guadagnoLettura > spreadSchierati * 2
  ? '  -> leggere la partita paga molto piu\' che avere l\'assetto giusto in tasca: c\'e\' profondita\''
  : '  -> il solito assetto cattura troppo valore: poca profondita\'');
console.log(`\n  confronto piu' squilibrato: ${etichetta(max.a)}`);
console.log(`  contro ${etichetta(max.b)} -> ${max.v.toFixed(1)}% = ${inPunti(max.v).toFixed(1)} punti`);
console.log(inPunti(max.v) < 8
  ? `  -> sotto 8 punti: una rosa nettamente piu' forte resta favorita`
  : `  -> ATTENZIONE: sopra 8 punti, la tattica conterebbe piu' della rosa`);

// ============================================================
//  C — gli interpreti
// ============================================================
console.log('\n' + '='.repeat(74));
console.log('C — quanto vale avere il profilo giusto per il proprio piano');
console.log('='.repeat(74));
console.log('  stesso piano per entrambe, stessa forza: cambia solo il profilo dei giocatori\n');
for (const [asse, chiave] of [['linea', 'alta'], ['linea', 'bassa'], ['costruzione', 'corta'], ['costruzione', 'verticale']]) {
  const opzione = ASSI[asse][chiave];
  const piano = asse === 'linea' ? { linea: chiave, costruzione: 'mista' } : { linea: 'media', costruzione: chiave };
  const v = serie(piano, piano, {
    modificaA: (r) => rosaPerProfilo(r, opzione, +1),
    modificaB: (r) => rosaPerProfilo(r, opzione, -1),
    seme: 31337,
  });
  console.log(`  ${opzione.etichetta.padEnd(18)} interpreti giusti vs sbagliati: ${v.toFixed(1)}%  = ${inPunti(v).toFixed(1)} punti`);
}

// ============================================================
//  D — l'identita': conviene tradirsi per contrastare?
// ============================================================
console.log('\n' + '='.repeat(74));
console.log('D — con un\'identita\', conviene snaturarsi per il contrasto giusto?');
console.log('='.repeat(74));
console.log('  la mia identita\' e\' "Difesa alta + Fitti passaggi".');
console.log('  incontro chi verticalizza, che e\' proprio cio\' che punisce la difesa alta.\n');

const miaIdentita = { linea: 'alta', costruzione: 'corta' };
const avversario = { linea: 'media', costruzione: 'verticale' };
const opzioni = [
  ['resto me stesso', { linea: 'alta', costruzione: 'corta' }],
  ['abbasso solo la linea', { linea: 'bassa', costruzione: 'corta' }],
  ['cambio tutto', { linea: 'bassa', costruzione: 'verticale' }],
];
for (const [nome, piano] of opzioni) {
  const v = serie(piano, avversario, { identitaA: miaIdentita, seme: 5150 });
  const fuori = (piano.linea !== miaIdentita.linea ? 1 : 0) + (piano.costruzione !== miaIdentita.costruzione ? 1 : 0);
  console.log(`  ${nome.padEnd(24)} ${v.toFixed(1)}% vittorie   (assi fuori identita': ${fuori})`);
}

console.log('\n' + '='.repeat(74));
console.log('Le scale si cambiano in cima a tattiche-prototipo.js.');
console.log('Nessun file del gioco e\' stato toccato.');
