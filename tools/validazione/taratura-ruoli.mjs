// Taratura dei profili di ruolo — node tools/validazione/taratura-ruoli.mjs [--scrivi]
//
// Calcola TARATURA_RUOLI (engine/ruoli.js) sui giocatori veri di
// pool-reale.json: per ogni ruolo, lo scarto di profilo atteso a ogni livello
// di overall (retta) e la deviazione intorno. Con --scrivi aggiorna la tabella
// nel motore; senza, verifica quella che c'e':
//   1. l'idoneita' non e' l'overall travestito (correlazione vicina a zero);
//   2. quanti colleghi finiscono "++", "+", neutri, "-", "--";
//   3. nessun ruolo della famiglia e' il migliore per quasi tutti.
import { readFileSync, writeFileSync } from 'fs';
import assert from 'assert';
import { RUOLI, scartoProfilo, idoneitaRuolo, TARATURA_RUOLI } from '../../engine/ruoli.js';

const RIF = 75;
const pool = JSON.parse(readFileSync(new URL('./pool-reale.json', import.meta.url), 'utf8'));
const colleghi = (r) => pool.filter((p) => r.per.includes(p.posizioni?.[0]));

const media = (a) => a.reduce((x, y) => x + y, 0) / a.length;
const corr = (a, b) => {
  const ma = media(a), mb = media(b);
  let n = 0, da = 0, db = 0;
  for (let i = 0; i < a.length; i++) { n += (a[i] - ma) * (b[i] - mb); da += (a[i] - ma) ** 2; db += (b[i] - mb) ** 2; }
  return n / Math.sqrt(da * db);
};

if (process.argv.includes('--scrivi')) {
  const righe = [];
  console.log('\n  ruolo                   n  atteso75  pendenza  dev   corr.grezza');
  for (const [k, r] of Object.entries(RUOLI)) {
    if (!r.profilo) continue;
    const d = colleghi(r).map((p) => [scartoProfilo(p.attributi, r.profilo), p.overall - RIF]).filter(([s]) => s !== null);
    const s = d.map(([v]) => v), x = d.map(([, v]) => v);
    const mx = media(x), ms = media(s);
    const b = x.reduce((t, xi, i) => t + (xi - mx) * (s[i] - ms), 0) / x.reduce((t, xi) => t + (xi - mx) ** 2, 0);
    const a = ms - b * mx;
    const res = s.map((si, i) => si - (a + b * x[i]));
    const dev = Math.sqrt(media(res.map((v) => v * v)));
    righe.push(`  ${k}: { atteso: ${a.toFixed(2)}, pendenza: ${b.toFixed(3)}, deviazione: ${dev.toFixed(2)} },`);
    console.log('  ' + k.padEnd(22) + String(s.length).padStart(4) + a.toFixed(1).padStart(9) + b.toFixed(3).padStart(10)
      + dev.toFixed(1).padStart(6) + corr(s, x).toFixed(2).padStart(12));
  }
  const file = new URL('../../engine/ruoli.js', import.meta.url);
  const src = readFileSync(file, 'utf8');
  const re = /export const TARATURA_RUOLI = \{[\s\S]*?\};/;
  assert.equal((src.match(new RegExp(re, 'g')) ?? []).length, 1, 'TARATURA_RUOLI deve comparire una volta sola');
  const nuovo = src.replace(re, `export const TARATURA_RUOLI = {\n${righe.join('\n')}\n};`);
  assert.ok(righe.every((r) => nuovo.includes(r)), 'la tabella scritta non e\' quella calcolata');
  writeFileSync(file, nuovo);

  // La copia per il frontend: stessi profili, stessa taratura, stessa formula.
  const fe = new URL('../../src/lib/tattica.ts', import.meta.url);
  const feSrc = readFileSync(fe, 'utf8');
  const INIZIO = '// --- IDONEITA\' AI RUOLI: generato da tools/validazione/taratura-ruoli.mjs ---';
  const FINE = '// --- fine idoneita\' ai ruoli ---';
  const profili = Object.fromEntries(Object.entries(RUOLI).filter(([, r]) => r.profilo).map(([k, r]) => [k, r.profilo]));
  const generali = [...new Set(Object.values(profili).flat())];
  const blocco = `${INIZIO}
export const PROFILI_RUOLI: Record<string, string[]> = ${JSON.stringify(profili, null, 2)}

const ATTRIBUTI_GENERALI: string[] = ${JSON.stringify(generali)}

export const TARATURA_RUOLI: Record<string, { atteso: number; pendenza: number; deviazione: number }> = {
${righe.join('\n')}
}

const mediaAttributi = (a: Record<string, number | null | undefined>, chiavi: string[]): number | null => {
  let somma = 0
  for (const k of chiavi) {
    const v = a[k]
    if (typeof v !== 'number' || !Number.isFinite(v)) return null
    somma += v
  }
  return somma / chiavi.length
}

/** Stessa formula di idoneitaRuolo in engine/ruoli.js: da -1 a +1, 0 se ruolo base o dati mancanti. */
export function idoneitaRuolo(attributi: Record<string, number | null | undefined> | null | undefined, overall: number, ruolo: string): number {
  const profilo = PROFILI_RUOLI[ruolo]
  const t = TARATURA_RUOLI[ruolo]
  if (!attributi || !profilo || !t) return 0
  const suo = mediaAttributi(attributi, profilo)
  const generale = mediaAttributi(attributi, ATTRIBUTI_GENERALI)
  if (suo === null || generale === null) return 0
  const atteso = t.atteso + t.pendenza * (overall - ${RIF})
  return Math.max(-1, Math.min(1, (suo - generale - atteso) / (t.deviazione * 1.5)))
}
${FINE}`;
  const reFe = new RegExp(`${INIZIO.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}[\\s\\S]*?${FINE.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}`);
  const nuovoFe = reFe.test(feSrc) ? feSrc.replace(reFe, blocco) : `${feSrc.trimEnd()}\n\n${blocco}\n`;
  writeFileSync(fe, nuovoFe);
  console.log('\n  engine/ruoli.js e src/lib/tattica.ts aggiornati: rilanciare senza --scrivi per la verifica.');
  process.exit(0);
}

assert.ok(Object.keys(TARATURA_RUOLI).length, 'TARATURA_RUOLI vuota: lanciare con --scrivi');
const g = (p) => ({ attributi: p.attributi, ovr: p.overall });

// Frontend e motore devono dare lo stesso numero, giocatore per giocatore.
const fe = await import('../../src/lib/tattica.ts');
let confronti = 0;
for (const [k, r] of Object.entries(RUOLI)) {
  for (const p of pool) {
    const a = idoneitaRuolo(g(p), k), b = fe.idoneitaRuolo(p.attributi, p.overall, k);
    assert.ok(Math.abs(a - b) < 1e-9, `${k}, giocatore ${p.id}: motore ${a}, frontend ${b}`);
    confronti++;
  }
  assert.equal(!!r.profilo, !!fe.PROFILI_RUOLI[k], `${k}: profilo presente in uno solo dei due`);
}
console.log(`\n  frontend identico al motore su ${confronti} confronti`);

console.log('\n  ruolo                   corr.overall     ++     +  neutro     -    --');
for (const [k, r] of Object.entries(RUOLI)) {
  if (!r.profilo) continue;
  const gi = colleghi(r);
  const v = gi.map((p) => idoneitaRuolo(g(p), k));
  const q = (f) => (v.filter(f).length / v.length * 100).toFixed(0).padStart(5) + '%';
  console.log('  ' + k.padEnd(22) + corr(v, gi.map((p) => p.overall)).toFixed(2).padStart(13) + '  '
    + q((x) => x >= 0.6) + q((x) => x >= 0.25 && x < 0.6) + q((x) => x > -0.25 && x < 0.25).padStart(7)
    + q((x) => x <= -0.25 && x > -0.6) + q((x) => x <= -0.6));
}

console.log('\n  il ruolo migliore per ogni giocatore (nessuno deve prendersi tutto)');
const famiglie = {};
for (const [k, r] of Object.entries(RUOLI)) if (r.profilo) (famiglie[r.per.join('/')] ??= []).push(k);
for (const [fam, ruoli] of Object.entries(famiglie)) {
  const gi = colleghi(RUOLI[ruoli[0]]);
  const cont = Object.fromEntries(ruoli.map((k) => [k, 0]));
  for (const p of gi) cont[ruoli.reduce((a, b) => (idoneitaRuolo(g(p), b) > idoneitaRuolo(g(p), a) ? b : a))]++;
  console.log('  ' + fam.padEnd(14) + ruoli.map((k) => `${k} ${(cont[k] / gi.length * 100).toFixed(0)}%`).join('  '));
}
