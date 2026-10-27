// Banco della cronaca nelle eliminatorie (27/10/2026). Prova il codice VERO di simula-giornata (non una copia): ricava
// le funzioni della cronaca da supabase/functions/simula-giornata/index.ts, rifà per ogni partita gli stessi passaggi
// della simulazione notturna e controlla la cronaca che verrebbe salvata:
//   - gol totali e gol dei 90' per squadra = motore; niente oltre il 90' senza supplementari;
//   - supplementari solo con l'eliminatoria in parità (andata compresa); marcatori in campo nel minuto del gol;
//   - la rete di sicurezza (verificaCronaca/correggiFasiCronaca) non scatta sulle cronache buone e corregge quelle
//     rovinate apposta (un gol che cambia fase, come nella stagione 1).
// Uso: node tools/validazione/banco-cronaca.mjs [partite]   (default 20000). Atteso: tutti gli errori a 0.
import ts from 'typescript';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import url from 'node:url';

const radice = path.resolve(path.dirname(url.fileURLToPath(import.meta.url)), '../..');
let s = fs.readFileSync(path.join(radice, 'supabase/functions/simula-giornata/index.ts'), 'utf8');
s = s.split('\n').filter((l) => !/^import '@supabase|^import \{ withSupabase|^import \{ jwtVerify/.test(l)).join('\n');
s = s.replace(/'\.\.\/\.\.\/\.\.\/engine\//g, `'${radice}/engine/`).replace(/Deno\.env\.get\([^)]*\)/g, 'undefined');
s = s.slice(0, s.indexOf('export default {'));
s += '\nexport { eventiGolDalMotore, minutiCambi, finestreInCampo, minutiCartellini, adattaAiMinutiInCampo, minutiGiocati, playerStats, rendiTiriCoerenti, costruisciEventiPartita, normalizzaCronaca, creaRng, verificaCronaca, correggiFasiCronaca, MINUTI_PER_BLOCCO, BLOCCHI_REGOLAMENTARI, MINUTO_MASSIMO }\n';
const fileModulo = path.join(os.tmpdir(), `cronaca-vera-${process.pid}.mjs`);
fs.writeFileSync(fileModulo, ts.transpileModule(s, { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ESNext } }).outputText);
const C = await import(url.pathToFileURL(fileModulo).href);
const { simulaPartita, schiera } = await import(`${radice}/engine/engine.js`);
const { setSeed } = await import(`${radice}/engine/random.js`);
const { creaRosaPerModulo } = await import(`${radice}/tools/validazione/roster.js`);
const { MODULI } = await import(`${radice}/engine/config.js`);

const MOD = Object.keys(MODULI), N = Number(process.argv[2] || 20000);
const err = { totale: 0, novanta: 0, oltre90SenzaSupp: 0, suppSenzaParita: 0, marcatoreFuori: 0, eccezioni: 0, reteScattataSuCronacaBuona: 0, guastoNonRilevato: 0, guastoNonCorretto: 0 };
let supp = 0, guasti = 0;
for (let i = 0; i < N; i++) {
  try {
    const mA = MOD[i % MOD.length], mB = MOD[(i * 7 + 3) % MOD.length];
    const ra = creaRosaPerModulo('A', 74 + (i % 9), MODULI[mA]), rb = creaRosaPerModulo('B', 74 + ((i * 5) % 9), MODULI[mB]);
    const homeLineup = schiera(ra, mA), awayLineup = schiera(rb, mB);
    const titH = homeLineup.titolari.map((p) => p.id), titA = awayLineup.titolari.map((p) => p.id);
    const scartoAndata = [-2, -1, 0, 0, 0, 1, 2][i % 7], seed = 50000 + i;
    setSeed(seed);
    const r = simulaPartita(ra, rb, mA, mB, { usaCondizione: true, statsGiocatori: true, lineupCasa: homeLineup, lineupOspite: awayLineup, supplementariSeParita: true, scartoAndata });
    const eventi = C.eventiGolDalMotore(r.marcatoriPerBlocco, { casa: 1, ospite: 2 }, seed);
    const rndP = C.creaRng(seed ^ 0x2545f491);
    for (const p of r.piazzatiInPartita ?? []) eventi.push({ tipo: 'gol', minuto: (p.blocco - 1) * C.MINUTI_PER_BLOCCO + 1 + Math.floor(rndP() * C.MINUTI_PER_BLOCCO), blocco: p.blocco, lato: p.lato, team_id: p.lato === 'casa' ? 1 : 2, marcatore: p.marcatore, assist: p.battitore !== null && p.battitore !== p.marcatore ? p.battitore : null, piazzato: p.tipo });
    const cambi = C.minutiCambi(r.cambiInPartita, seed);
    const finestre = C.finestreInCampo([{ lato: 'casa', titolari: titH }, { lato: 'ospite', titolari: titA }], cambi, r.supplementari ? C.MINUTO_MASSIMO : C.BLOCCHI_REGOLAMENTARI * C.MINUTI_PER_BLOCCO);
    const cartellini = C.minutiCartellini(r.cartelliniInPartita, finestre, seed);
    C.adattaAiMinutiInCampo(eventi, finestre, C.creaRng(seed ^ 0x165667b1));
    eventi.sort((a, b) => a.minuto - b.minuto || a.blocco - b.blocco);
    C.minutiGiocati(finestre.get('casa'), r.perGiocatore?.casa.minuti); C.minutiGiocati(finestre.get('ospite'), r.perGiocatore?.ospite.minuti);
    r.perGiocatore.casa.marcatoriIds = eventi.filter((e) => e.lato === 'casa').map((e) => e.marcatore);
    r.perGiocatore.ospite.marcatoriIds = eventi.filter((e) => e.lato === 'ospite').map((e) => e.marcatore);
    const assist = new Map(); for (const e of eventi) if (e.assist !== null) assist.set(e.assist, (assist.get(e.assist) ?? 0) + 1);
    const stats = [...C.playerStats(1, r.perGiocatore.casa, r.statsCasa, assist), ...C.playerStats(2, r.perGiocatore.ospite, r.statsOspite, assist)];
    const portieri = (slot) => new Set([...(slot ?? new Map()).entries()].filter(([, x]) => x === 'GK').map(([id]) => id));
    C.rendiTiriCoerenti(stats.filter((x) => x.team_id === 1), r.statsCasa, portieri(r.perGiocatore?.casa.slot));
    C.rendiTiriCoerenti(stats.filter((x) => x.team_id === 2), r.statsOspite, portieri(r.perGiocatore?.ospite.slot));
    const cronaca = C.normalizzaCronaca(C.costruisciEventiPartita(eventi, [
      { lato: 'casa', teamId: 1, presenzePerBlocco: r.presenzePerBlocco.casa, stats: stats.filter((x) => x.team_id === 1) },
      { lato: 'ospite', teamId: 2, presenzePerBlocco: r.presenzePerBlocco.ospite, stats: stats.filter((x) => x.team_id === 2) },
    ], cambi, cartellini, finestre, seed));
    const gol = cronaca.filter((e) => e.tipo === 'gol');
    const conta = (lato, f) => gol.filter((e) => e.lato === lato && f(e)).length;
    if (conta('casa', () => true) !== r.golC || conta('ospite', () => true) !== r.golO) err.totale++;
    const c90 = conta('casa', (e) => e.minuto <= 90), o90 = conta('ospite', (e) => e.minuto <= 90);
    if (c90 !== r.golRegolamentari.casa || o90 !== r.golRegolamentari.ospite) err.novanta++;
    if (!r.supplementari && cronaca.some((e) => e.minuto > 90)) err.oltre90SenzaSupp++;
    if (r.supplementari) { supp++; if (scartoAndata + c90 - o90 !== 0) err.suppSenzaParita++; }
    for (const e of gol) { const w = finestre.get(e.lato)?.get(e.marcatore); if (w && !(e.minuto > w.da && e.minuto <= w.a) && !(w.da === 0 && e.minuto >= 1 && e.minuto <= w.a)) err.marcatoreFuori++; }
    if (C.verificaCronaca(cronaca, r, true, scartoAndata).length) err.reteScattataSuCronacaBuona++;
    const copia = cronaca.map((e) => ({ ...e }));
    const golExtra = copia.find((e) => e.tipo === 'gol' && e.minuto > 90), golReg = copia.find((e) => e.tipo === 'gol' && e.minuto <= 90);
    let guasto = false;
    if (golExtra) { golExtra.minuto = 85; golExtra.blocco = 6; guasto = true; }
    else if (!r.supplementari && golReg) { golReg.minuto = 100; golReg.blocco = 7; guasto = true; }
    if (guasto) {
      guasti++;
      if (!C.verificaCronaca(copia, r, true, scartoAndata).length) err.guastoNonRilevato++;
      C.correggiFasiCronaca(copia, r, seed);
      if (C.verificaCronaca(copia, r, true, scartoAndata).length) err.guastoNonCorretto++;
    }
  } catch (x) { err.eccezioni++; if (err.eccezioni < 3) console.error(x); }
}
fs.rmSync(fileModulo, { force: true });
console.log(`eliminatorie ${N}, con supplementari ${supp} (${(100 * supp / N).toFixed(1)}%), guasti provocati ${guasti}`);
console.log('errori:', JSON.stringify(err));
process.exitCode = Object.values(err).some((v) => v > 0) ? 1 : 0;
