// Prova mirata della regola del portiere (12/11/2026): la porta non resta mai
// vuota, e un giocatore di movimento in porta subisce CFG.PORTIERE_DI_MOVIMENTO_GOL
// volte i gol di un portiere vero (para 2 tiri in porta su 10 invece di 7).
//   node tools/validazione/prova-portiere.mjs [partite]
import { CFG, REPARTO } from '../../engine/config.js';
import { creaRosa, setSeed } from './roster.js';
import { simulaPartita, schiera } from '../../engine/engine.js';
import { portiereDaLineup } from '../../engine/rigori.js';
import assert from 'node:assert/strict';

const N = Number(process.argv[2] ?? 3000);
const ePortiere = (g) => REPARTO[g.posizioni[0]] === 'GK';
const inCampo = (L) => L.titolari.filter(Boolean).length;
const inPorta = (L) => L.titolari[L.slots.indexOf('GK')];

// --- 1. giocatore di movimento in porta dal primo minuto ---
function giro(conMovimento) {
  let subiti = 0, tiriPorta = 0, tiri = 0;
  for (let k = 0; k < N; k++) {
    setSeed(1000 + k);
    const casa = creaRosa('Casa', 78), ospite = creaRosa('Ospite', 78);
    const L = schiera(casa, '4-3-3');
    if (conMovimento) {
      const j = L.panchina.findIndex((g) => !ePortiere(g));
      L.titolari[L.slots.indexOf('GK')] = L.panchina.splice(j, 1)[0];
      L.panchina = L.panchina.filter((g) => !ePortiere(g));
    }
    const r = simulaPartita(casa, ospite, '4-3-3', '4-3-3', { usaCondizione: false, lineupCasa: L, seedInfortuni: 77 + k });
    subiti += r.golO; tiriPorta += r.statsOspite.inPorta; tiri += r.statsOspite.tiri;
  }
  return { subiti: subiti / N, tiriPorta: tiriPorta / N, tiri: tiri / N, parati: 1 - subiti / tiriPorta };
}
const vero = giro(false), movimento = giro(true);
console.log(`=== in porta dal primo minuto (${N} partite, rose pari) ===`);
for (const [nome, x] of [['portiere vero', vero], ['giocatore di movimento', movimento]])
  console.log(`${nome.padEnd(24)} gol subiti ${x.subiti.toFixed(2)}  tiri subiti ${x.tiri.toFixed(1)}  in porta ${x.tiriPorta.toFixed(2)}  parati ${(x.parati * 10).toFixed(1)} su 10`);
// «Para 2 su 10»: si misura sugli stessi tiri che subirebbe un portiere vero. La
// statistica dei tiri in porta della partita cresce coi gol, quindi non fa testo.
const paratiSuDieci = 10 - 10 * movimento.subiti / vero.tiriPorta;
console.log(`gol subiti x${(movimento.subiti / vero.subiti).toFixed(2)}; sui tiri in porta di un portiere vero ne para ${paratiSuDieci.toFixed(1)} su 10 (obiettivo 2)`);
assert.ok(paratiSuDieci > 1 && paratiSuDieci < 3, 'un giocatore di movimento in porta non para circa 2 tiri su 10');

// --- 2. portiere espulso: la porta si copre sempre ---
// Si azzera il contrasto di tutti: ogni giocatore, portiere compreso, pesa uguale
// fra i candidati al cartellino; e i rossi diretti sono resi molto piu' frequenti,
// cosi' le espulsioni del portiere sono abbastanza da poterle contare. I gol dopo
// l'espulsione si confrontano solo nelle partite con quell'unico rosso.
const rossoVero = CFG.CARTELLINO_ROSSO_DIRETTO_LAMBDA_BLOCCO;
CFG.CARTELLINO_ROSSO_DIRETTO_LAMBDA_BLOCCO = rossoVero * 12;
let conRiserva = 0, senzaRiserva = 0, golDopo = { riserva: 0, movimento: 0 }, blocchiDopo = { riserva: 0, movimento: 0 };
for (let k = 0; k < N * 6; k++) {
  setSeed(50000 + k);
  const casa = creaRosa('Casa', 78), ospite = creaRosa('Ospite', 78);
  for (const g of casa.giocatori) g.tackle = 0;
  const L = schiera(casa, '4-3-3');
  const titolare = inPorta(L);
  const togliRiserve = k % 2 === 1;
  if (togliRiserve) L.panchina = L.panchina.filter((g) => !ePortiere(g));
  const r = simulaPartita(casa, ospite, '4-3-3', '4-3-3', { usaCondizione: true, lineupCasa: L, seedInfortuni: 9000 + k });
  const rosso = r.cartelliniInPartita.find((c) => c.lato === 'casa' && c.tipo !== 'giallo' && c.giocatore === titolare.id);
  if (!rosso) continue;
  // Coi rossi resi frequenti puo' essere espulso anche il secondo portiere: qui si guarda cosa e' successo al titolare.
  const cambio = r.cambiInPartita.find((c) => c.lato === 'casa' && c.motivo === 'portiere' && c.espulso === titolare.id);
  const spostato = r.portieriDiMovimento.find((p) => p.lato === 'casa' && p.espulso === titolare.id);
  const ora = inPorta(L);
  assert.ok(ora, 'porta vuota dopo l’espulsione del portiere');
  assert.notEqual(ora.id, titolare.id, 'l’espulso e’ ancora in porta');
  const altriRossi = r.cartelliniInPartita.filter((c) => c.lato === 'casa' && c.tipo !== 'giallo').length;
  assert.equal(inCampo(L), 11 - altriRossi, 'la squadra non e’ con un uomo in meno per ogni espulso');
  const golSuccessivi = r.golPerBlocco.filter((g) => g.blocco > rosso.blocco).reduce((s, g) => s + g.ospite, 0);
  const blocchi = r.golPerBlocco.filter((g) => g.blocco > rosso.blocco).length;
  const soloLui = altriRossi === 1;
  if (cambio) {
    conRiserva++;
    assert.ok(!togliRiserve, 'e’ entrato un portiere che non era in panchina');
    assert.equal(cambio.espulso, titolare.id);
    assert.equal(cambio.blocco, rosso.blocco);
    assert.ok(!spostato, 'cambio e spostamento insieme');
    assert.ok(cambio.sosta >= 1 && cambio.sosta <= CFG.MAX_SOSTE);
    assert.ok(r.cambiInPartita.filter((c) => c.lato === 'casa').length <= CFG.MAX_CAMBI, 'piu’ di cinque cambi');
    // puo' poi essere uscito a sua volta (infortunio): in porta comunque c'e' qualcuno
    if (soloLui) { golDopo.riserva += golSuccessivi; blocchiDopo.riserva += blocchi; }
  } else {
    senzaRiserva++;
    assert.ok(spostato, 'ne’ cambio ne’ giocatore di movimento in porta');
    assert.equal(spostato.espulso, titolare.id);
    if (soloLui) { golDopo.movimento += golSuccessivi; blocchiDopo.movimento += blocchi; }
  }
}
CFG.CARTELLINO_ROSSO_DIRETTO_LAMBDA_BLOCCO = rossoVero;
const per90 = (chi) => golDopo[chi] / Math.max(1, blocchiDopo[chi]) * 6;
console.log(`\n=== portiere espulso (${N * 6} partite, cartellini resi uguali per tutti e rossi x12) ===`);
console.log(`entra il secondo portiere: ${conRiserva} casi, gol su azione subiti dopo ${per90('riserva').toFixed(2)} ogni 90'`);
console.log(`va in porta uno di movimento: ${senzaRiserva} casi, gol su azione subiti dopo ${per90('movimento').toFixed(2)} ogni 90' (x${(per90('movimento') / per90('riserva')).toFixed(2)})`);
assert.ok(conRiserva > 30 && senzaRiserva > 30, 'troppo pochi casi da controllare: aumentare le partite');
assert.ok(per90('movimento') > per90('riserva') * 2, 'con un giocatore di movimento in porta i gol subiti non salgono abbastanza');

// --- 3. rigori: uno di movimento in porta non vale il suo overall ---
setSeed(5);
const rosa = creaRosa('Rigori', 80), Lr = schiera(rosa, '4-3-3');
const vera = portiereDaLineup(Lr).ovr;
Lr.titolari[Lr.slots.indexOf('GK')] = Lr.panchina.find((g) => !ePortiere(g));
const finta = portiereDaLineup(Lr).ovr;
console.log(`\n=== rigori ===\nportiere vero ${vera}, giocatore di movimento fra i pali ${finta.toFixed(0)}`);
assert.ok(finta <= 45);
console.log('\nTutti i controlli superati.');
