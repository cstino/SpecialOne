// Lettura del database di produzione per gli script di analisi.
// Sola lettura: nessuno script in tools/validazione/ deve scrivere.
import { readFileSync } from 'fs';

const env = Object.fromEntries(
  readFileSync(new URL('../../.env.local', import.meta.url), 'utf8')
    .split('\n').filter(r => r.includes('='))
    .map(r => { const i = r.indexOf('='); return [r.slice(0, i).trim(), r.slice(i + 1).trim()]; }));

export const URL_SB = env.VITE_SUPABASE_URL;
export const KEY = env.SUPABASE_SERVICE_ROLE_KEY;

export async function sel(tabella, query) {
  const r = await fetch(`${URL_SB}/rest/v1/${tabella}?${query}`, {
    headers: { apikey: KEY, Authorization: `Bearer ${KEY}` } });
  if (!r.ok) throw new Error(`${tabella}: ${r.status} ${await r.text()}`);
  return r.json();
}
