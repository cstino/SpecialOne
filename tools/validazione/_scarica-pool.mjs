// Scarica una volta un campione di giocatori VERI con tutti gli attributi, e lo
// salva in tools/validazione/pool-reale.json. Serve al prototipo del motore
// azione per azione: roster.js genera cinque attributi, qui ne servono quindici.
// Sola lettura. Rilanciare solo se il catalogo cambia.
import { writeFileSync } from 'fs';
import { sel } from './_db-produzione.js';

const RUOLI = ['GK','CB','LB','RB','CDM','CM','CAM','LM','RM','LW','RW','ST'];
const out = [];
for (const r of RUOLI) {
  for (let off = 0; off < 600; off += 200) {
    const b = await sel('players',
      `select=id,nome,posizioni,overall,piede,attributi&overall=gte.58&overall=lte.86` +
      `&origine_vivaio=is.false&posizioni=cs.{${r}}&order=id&offset=${off}&limit=200`);
    if (!b.length) break;
    for (const p of b) if (p.posizioni?.[0] === r && p.attributi?.pace != null || (r === 'GK' && p.posizioni?.[0] === 'GK')) out.push(p);
  }
}
const unici = [...new Map(out.map(p => [p.id, p])).values()];
writeFileSync(new URL('./pool-reale.json', import.meta.url), JSON.stringify(unici));
const per = {};
for (const p of unici) per[p.posizioni[0]] = (per[p.posizioni[0]] ?? 0) + 1;
console.log(`  salvati ${unici.length} giocatori`);
console.log('  per ruolo:', Object.entries(per).map(([k,v]) => `${k}:${v}`).join(' '));
