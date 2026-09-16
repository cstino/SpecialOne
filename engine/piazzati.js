// ============================================================
//  CALCI PIAZZATI — angoli e punizioni
//
//  I gol da palla inattiva non si AGGIUNGONO al totale: ne prendono una quota.
//  Il motore e' tarato su 2,50-2,90 gol a partita e quella taratura resta; cio'
//  che cambia e' da dove arrivano. Per compensare, l'xG di manovra scende della
//  stessa frazione (vedi XG_BASE_BLOCCO in config.js).
//
//  I NUMERI DI RIFERIMENTO sono della Premier League 2025-26:
//    - 28,3% dei gol viene da angoli, punizioni e rimesse
//    - 0,50 gol da angolo a partita (le due squadre insieme)
//    - ~0,18 gol da punizione diretta a partita
//  Qui si modellano angoli e punizioni, non le rimesse: valgono insieme circa
//  0,68 gol a partita, cioe' un quarto del totale.
//
//  PERCHE' VALE LA PENA, e non e' solo realismo: i piazzati usano attributi
//  COMPLETAMENTE DIVERSI dalla manovra. Colpo di testa, elevazione e fisico da
//  una parte, marcatura e presa alta dall'altra, precisione sui calci per chi
//  batte. Una squadra modesta palla a terra puo' essere temibile sui corner, e
//  viceversa. E' una seconda dimensione su cui costruire una rosa, non una
//  variante della prima.
//
//  Sta in engine/ accanto a rigori.js e come quello NON e' il nucleo tarato
//  nella Fase 0 — ma a differenza dei rigori tocca i gol di ogni partita,
//  quindi la suite di validazione va rilanciata a ogni modifica di queste
//  costanti.
// ============================================================

import { rnd, gauss, poisson } from './random.js';

const clamp = (v, a, b) => Math.max(a, Math.min(b, v));

export const CFG_PIAZZATI = {
  // Angoli per squadra a partita, per una squadra di pressione media. Il
  // numero vero varia con quanto si attacca: chi domina batte piu' corner.
  CORNER_BASE: 5.2,
  // Punizioni da posizione battibile. Non tutti i falli lo sono: questi sono
  // quelli da cui si tira in porta.
  PUNIZIONI_BASE: 2.0,

  // Conversione a parita' di valutazione fra chi attacca e chi difende.
  // Tarate per arrivare a 0,50 gol da angolo e 0,18 da punizione a partita.
  CORNER_CONVERSIONE: 0.048,
  PUNIZIONE_CONVERSIONE: 0.045,

  // Quanto lo scarto di valutazione sposta la conversione. Su un angolo, dieci
  // punti di vantaggio aereo valgono circa il 30% di gol in piu' — molto, ma i
  // piazzati sono per definizione il momento in cui la specializzazione conta.
  K_AEREO: 0.026,
  K_PUNIZIONE: 0.030,

  // Limiti: nemmeno la squadra piu' forte segna su un angolo su cinque.
  MIN_CONV: 0.008,
  MAX_CONV: 0.16,

  // Non tutti gli angoli producono una conclusione: molti finiscono in un
  // rinvio o in fallo in attacco. Quelli che la producono vanno contati fra i
  // tiri, perche' un colpo di testa su angolo E' un tiro — senza, le
  // statistiche raccontavano una partita con meno conclusioni di quante ne
  // erano davvero avvenute.
  CORNER_CON_TIRO: 0.30,
  PUNIZIONE_CON_TIRO: 0.55,
};

// ------------------------------------------------------------
//  Le valutazioni di reparto sui piazzati.
//
//  Su un angolo salgono in quattro o cinque, non undici: si prendono i
//  MIGLIORI di testa, non la media della squadra. E' la differenza fra avere
//  due torri e avere undici giocatori di media statura.
// ------------------------------------------------------------
function migliori(lineup, campo, quanti) {
  const valori = [];
  for (let i = 0; i < lineup.titolari.length; i++) {
    const g = lineup.titolari[i];
    if (!g || lineup.slots[i] === 'GK') continue;
    const v = g.piazzati?.[campo];
    if (typeof v === 'number' && Number.isFinite(v)) valori.push(v);
  }
  if (!valori.length) return 50;
  valori.sort((a, b) => b - a);
  const presi = valori.slice(0, Math.min(quanti, valori.length));
  return presi.reduce((a, b) => a + b, 0) / presi.length;
}

/** Chi batte: il migliore in campo su quel gesto. */
export function incaricato(lineup, campo) {
  let best = null;
  for (let i = 0; i < lineup.titolari.length; i++) {
    const g = lineup.titolari[i];
    if (!g || lineup.slots[i] === 'GK') continue;
    const v = g.piazzati?.[campo];
    if (typeof v !== 'number' || !Number.isFinite(v)) continue;
    if (!best || v > best.v) best = { g, v };
  }
  return best ? best.g : null;
}

/** Chi la mette dentro: pesato sul colpo di testa, non a caso. */
function scegliFinalizzatore(lineup) {
  const cand = [];
  for (let i = 0; i < lineup.titolari.length; i++) {
    const g = lineup.titolari[i];
    if (!g || lineup.slots[i] === 'GK') continue;
    cand.push({ g, peso: Math.max(1, (g.piazzati?.testa ?? 40) - 30) ** 2 });
  }
  if (!cand.length) return null;
  const tot = cand.reduce((s, c) => s + c.peso, 0);
  let r = rnd() * tot;
  for (const c of cand) { r -= c.peso; if (r <= 0) return c.g; }
  return cand[cand.length - 1].g;
}

/**
 * Angoli e punizioni di UNA squadra in UNA partita.
 *
 * @param lineup        chi attacca, a fine partita
 * @param lineupDif     chi difende
 * @param pressione     quanto ha attaccato, 1 = pressione media
 */
export function calcolaPiazzati(lineup, lineupDif, pressione = 1) {
  const p = clamp(pressione, 0.35, 2.2);

  // --- angoli ---
  const corner = Math.max(0, poisson(CFG_PIAZZATI.CORNER_BASE * p));
  const attaccoAereo = migliori(lineup, 'testa', 4);
  const battuta = incaricato(lineup, 'battuta')?.piazzati?.battuta ?? 50;
  const difesaAerea = migliori(lineupDif, 'marcatura', 4);
  const portiere = lineupDif.titolari[lineupDif.slots.indexOf('GK')];
  const presa = portiere?.piazzati?.presa ?? 55;

  // Chi batte pesa meno di chi attacca il pallone: un cross perfetto non serve
  // senza nessuno che ci arrivi, ma il contrario e' ancora piu' vero.
  const forzaAttacco = attaccoAereo * 0.7 + battuta * 0.3;
  const forzaDifesa = difesaAerea * 0.75 + presa * 0.25;

  const convCorner = clamp(
    CFG_PIAZZATI.CORNER_CONVERSIONE * (1 + CFG_PIAZZATI.K_AEREO * (forzaAttacco - forzaDifesa)),
    CFG_PIAZZATI.MIN_CONV, CFG_PIAZZATI.MAX_CONV);

  let golCorner = 0, tiri = 0, inPorta = 0;
  const marcatori = [];
  for (let i = 0; i < corner; i++) {
    if (rnd() < convCorner) {
      golCorner++; tiri++; inPorta++;
      const chi = scegliFinalizzatore(lineup);
      if (chi) marcatori.push({ id: chi.id, nome: chi.nome, tipo: 'angolo' });
    } else if (rnd() < CFG_PIAZZATI.CORNER_CON_TIRO) {
      tiri++;
      if (rnd() < 0.35) inPorta++;
    }
  }

  // --- punizioni ---
  const punizioni = Math.max(0, poisson(CFG_PIAZZATI.PUNIZIONI_BASE * p));
  const specialista = incaricato(lineup, 'punizione');
  const forzaPunizione = specialista?.piazzati?.punizione ?? 45;
  const convPunizione = clamp(
    CFG_PIAZZATI.PUNIZIONE_CONVERSIONE * (1 + CFG_PIAZZATI.K_PUNIZIONE * (forzaPunizione - presa)),
    CFG_PIAZZATI.MIN_CONV, CFG_PIAZZATI.MAX_CONV);

  let golPunizione = 0;
  for (let i = 0; i < punizioni; i++) {
    if (rnd() < convPunizione) {
      golPunizione++; tiri++; inPorta++;
      if (specialista) marcatori.push({ id: specialista.id, nome: specialista.nome, tipo: 'punizione' });
    } else if (rnd() < CFG_PIAZZATI.PUNIZIONE_CON_TIRO) {
      tiri++;
      if (rnd() < 0.40) inPorta++;
    }
  }

  return {
    corner, golCorner, punizioni, golPunizione,
    gol: golCorner + golPunizione, tiri, inPorta,
    marcatori,
    battutoDa: incaricato(lineup, 'battuta')?.nome ?? null,
    punizioniDa: specialista?.nome ?? null,
  };
}
