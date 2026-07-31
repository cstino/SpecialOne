// ============================================================
//  UTILITY CASUALI
//  Estratte da roster.js: engine.js ne dipende e non puo importare
//  da tools/validazione (file di test, fuori dal bundle di produzione).
//  In produzione basta sostituire rnd() con Math.random se non serve
//  la riproducibilita da seed (ma tenerla e' utile per il debug).
// ============================================================

let _seed = 12345;
export function setSeed(s) { _seed = s; }
export function rnd() {
  _seed = (_seed * 1664525 + 1013904223) % 4294967296;
  return _seed / 4294967296;
}
export function gauss(mu, sigma) {
  const u1 = Math.max(rnd(), 1e-9), u2 = rnd();
  return mu + sigma * Math.sqrt(-2 * Math.log(u1)) * Math.cos(2 * Math.PI * u2);
}
export function poisson(lambda) {
  if (lambda <= 0) return 0;
  if (lambda > 25) return Math.max(0, Math.round(gauss(lambda, Math.sqrt(lambda))));
  const L = Math.exp(-lambda);
  let k = 0, p = 1;
  do { k++; p *= rnd(); } while (p > L);
  return k - 1;
}
export function scegliPesato(items, pesi) {
  const tot = pesi.reduce((a, b) => a + b, 0);
  if (tot <= 0) return items[Math.floor(rnd() * items.length)];
  let r = rnd() * tot;
  for (let i = 0; i < items.length; i++) { r -= pesi[i]; if (r <= 0) return items[i]; }
  return items[items.length - 1];
}
