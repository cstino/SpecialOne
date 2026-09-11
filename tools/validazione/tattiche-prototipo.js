// ============================================================
//  IMPALCATURA DI PROVA PER IL SISTEMA TATTICO
//
//  ATTENZIONE: il MODELLO non abita piu' qui. Dall'11 settembre 2026 vive in
//  engine/tattiche.js, cioe' nel codice di produzione, e questo file contiene
//  solo cio' che serve a metterlo alla prova su rose sintetiche: dare un
//  profilo ai giocatori finti (che non hanno attributi FC 26) e costruire rose
//  fatte apposta — o apposta male — per un certo piano.
//
//  Prima c'erano due copie del modello, una qui e una da scrivere: bastava
//  ritoccarne una perche' i test misurassero qualcosa che il gioco non fa.
//  Ora la sorgente e' una sola e i test misurano il motore vero.
// ============================================================

import { gauss } from '../../engine/random.js';

export { ASSI, SCALE, PIANO_NEUTRO, tuttiGliAssetti, etichetta } from '../../engine/tattiche.js';

const clamp = (v, a, b) => Math.max(a, Math.min(b, v));

// ------------------------------------------------------------
//  Dev.std tarata sulle ROSE VERE, non sul catalogo: misura dell'11 settembre
//  2026 su 29 rose umane di stagione 1 (profili-rose-vere.js). Dentro una
//  singola rosa l'ampiezza p10-p90 del profilo e' 33-37 punti in tutti e tre i
//  reparti, che per una gaussiana vuol dire dev.std ~13.5. I valori precedenti
//  (16 e 20) venivano dal catalogo intero e sovrastimavano la leva, +46% sul
//  profilo rapido.
//
//  Le medie (+6 e -4) e i limiti riproducono l'asimmetria del catalogo vero.
// ------------------------------------------------------------
const DISPERSIONE = { tecnico: 13.5, rapido: 13.5 };

/**
 * Da' un profilo ai giocatori sintetici. Nel gioco vero i due tilt si
 * calcolano dagli attributi FC 26 (tiltTecnico/tiltRapido in
 * engine/tattiche.js); qui vanno generati, con la dispersione misurata e
 * SENZA correlazione con l'overall — che e' esattamente la proprieta' che li
 * rende leve tattiche e non overall travestito.
 */
export function arricchisci(rosa) {
  for (const g of rosa.giocatori) {
    if (g.tiltRapido !== undefined) continue;
    g.tiltTecnico = clamp(Math.round(gauss(6, DISPERSIONE.tecnico)), -40, 45);
    g.tiltRapido = clamp(Math.round(gauss(-4, DISPERSIONE.rapido)), -45, 40);
  }
  return rosa;
}

/**
 * Rosa costruita APPOSTA (verso +1) o apposta male (verso -1) per cio' che
 * un'opzione tattica chiede. Copia e non mutazione: la stessa rosa viene
 * riusata in confronti diversi, e mutarla accumulerebbe gli effetti di una
 * prova sulla successiva falsando tutto a valle.
 */
export function rosaPerProfilo(rosa, richiesta, verso) {
  if (!richiesta.profilo) return rosa;
  const campo = richiesta.profilo === 'tecnico' ? 'tiltTecnico' : 'tiltRapido';
  return {
    ...rosa,
    giocatori: rosa.giocatori.map((g) => ({
      ...g,
      [campo]: clamp(g[campo] + verso * richiesta.verso * 22, -45, 45),
    })),
  };
}
