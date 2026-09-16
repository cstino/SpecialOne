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
  // Si dividono meta' da destra e meta' da sinistra.
  CORNER_BASE: 5.2,

  // Le punizioni sono due cose diverse, non una.
  //   CORTA  dalla distanza da cui si calcia in porta: decide la precisione
  //          sul pallone fermo e la potenza.
  //   LUNGA  da lontano, dove non si tira: si mette dentro e si attacca di
  //          testa, quindi vale come un angolo con meno gente in area.
  PUNIZIONI_CORTE_BASE: 0.9,
  PUNIZIONI_LUNGHE_BASE: 2.4,

  // ANGOLI A RIENTRARE E A USCIRE
  //
  // Un destro che batte dalla bandierina di sinistra fa rientrare il pallone
  // verso la porta; dalla destra lo fa uscire. Per un mancino e' l'inverso.
  // In Premier League 2025-26 i gol da angolo a rientrare sono stati 77
  // contro 11 a uscire: e' la differenza piu' netta di tutto il repertorio
  // dei piazzati.
  //
  // I due fattori qui sotto NON sono il rapporto 7:1 di quei gol, che e'
  // gonfiato dal fatto che gli angoli a rientrare si battono molto piu'
  // spesso proprio perche' rendono. Sono una stima prudente del vantaggio a
  // parita' di occasioni, e restano da rifinire se un giorno avremo dati
  // nostri: e' la costante meno solida di questo file.
  RIENTRARE: 1.35,
  USCIRE: 0.70,

  // Conversione a parita' di valutazione fra chi attacca e chi difende.
  // Tarate per arrivare a 0,50 gol da angolo e 0,18 da punizione a partita.
  CORNER_CONVERSIONE: 0.047,
  PUNIZIONE_CORTA_CONVERSIONE: 0.050,
  // Una punizione messa in area rende MENO di un angolo, non di piu': la
  // difesa ha tempo di schierarsi e c'e' il fuorigioco, che sull'angolo non
  // esiste. Tarata con la corta per arrivare insieme a 0,18 gol da punizione
  // a partita, che e' il dato Premier (70 gol dirette e indirette su 380).
  PUNIZIONE_LUNGA_CONVERSIONE: 0.019,

  // Quanto lo scarto di valutazione sposta la conversione. Su un angolo, dieci
  // punti di vantaggio aereo valgono circa il 30% di gol in piu' — molto, ma i
  // piazzati sono per definizione il momento in cui la specializzazione conta.
  K_AEREO: 0.026,
  K_PUNIZIONE: 0.030,
  MAX_CONV_CORTA: 0.22,

  // Limiti: nemmeno la squadra piu' forte segna su un angolo su cinque.
  MIN_CONV: 0.008,
  MAX_CONV: 0.16,

  // Non tutti gli angoli producono una conclusione: molti finiscono in un
  // rinvio o in fallo in attacco. Quelli che la producono vanno contati fra i
  // tiri, perche' un colpo di testa su angolo E' un tiro — senza, le
  // statistiche raccontavano una partita con meno conclusioni di quante ne
  // erano davvero avvenute.
  CORNER_CON_TIRO: 0.26,
  PUNIZIONE_CORTA_CON_TIRO: 0.90,
  PUNIZIONE_LUNGA_CON_TIRO: 0.20,
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

/**
 * Chi batte. Se l'allenatore ha designato qualcuno e quel giocatore e' ancora
 * in campo, batte lui: e' una sua scelta e va rispettata anche quando non e'
 * la migliore sulla carta. Altrimenti — nessuna designazione, oppure il
 * designato e' uscito per infortunio o sostituzione — si torna al migliore
 * rimasto, che e' cio' che farebbe una squadra vera.
 */
export function incaricato(lineup, campo, ruolo) {
  const designato = ruolo ? lineup.incaricati?.[ruolo] : null;
  if (designato != null) {
    const g = lineup.titolari.find((t) => t && t.id === designato);
    if (g) return g;
  }
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

  // --- angoli, uno per lato ---
  const attaccoAereo = migliori(lineup, 'testa', 4);
  const difesaAerea = migliori(lineupDif, 'marcatura', 4);
  const portiere = lineupDif.titolari[lineupDif.slots.indexOf('GK')];
  const presa = portiere?.piazzati?.presa ?? 55;
  const forzaDifesa = difesaAerea * 0.75 + presa * 0.25;

  let corner = 0, golCorner = 0, tiri = 0, inPorta = 0;
  const marcatori = [];

  for (const lato of ['dx', 'sx']) {
    const quanti = Math.max(0, poisson(CFG_PIAZZATI.CORNER_BASE * p / 2));
    corner += quanti;
    if (!quanti) continue;

    const chi = incaricato(lineup, 'battuta', lato === 'dx' ? 'angolo_dx' : 'angolo_sx');
    const battuta = chi?.piazzati?.battuta ?? 50;

    // A rientrare o a uscire: dipende dal piede di chi batte e dalla
    // bandierina. Destro da sinistra e mancino da destra fanno rientrare il
    // pallone verso la porta; il contrario lo fa uscire.
    const mancino = chi?.piede === 'sinistro';
    const rientra = lato === 'dx' ? mancino : !mancino;
    const traiettoria = rientra ? CFG_PIAZZATI.RIENTRARE : CFG_PIAZZATI.USCIRE;

    const forzaAttacco = attaccoAereo * 0.7 + battuta * 0.3;
    const conv = clamp(
      CFG_PIAZZATI.CORNER_CONVERSIONE * traiettoria
        * (1 + CFG_PIAZZATI.K_AEREO * (forzaAttacco - forzaDifesa)),
      CFG_PIAZZATI.MIN_CONV, CFG_PIAZZATI.MAX_CONV);

    for (let i = 0; i < quanti; i++) {
      if (rnd() < conv) {
        golCorner++; tiri++; inPorta++;
        const f = scegliFinalizzatore(lineup);
        if (f) marcatori.push({ id: f.id, nome: f.nome, tipo: `angolo_${lato}` });
      } else if (rnd() < CFG_PIAZZATI.CORNER_CON_TIRO) {
        tiri++;
        if (rnd() < 0.35) inPorta++;
      }
    }
  }

  // --- punizioni corte: si calcia in porta ---
  const corte = Math.max(0, poisson(CFG_PIAZZATI.PUNIZIONI_CORTE_BASE * p));
  const specialista = incaricato(lineup, 'punizione', 'punizione_corta');
  const forzaPunizione = specialista?.piazzati?.punizione ?? 45;
  const convCorta = clamp(
    CFG_PIAZZATI.PUNIZIONE_CORTA_CONVERSIONE * (1 + CFG_PIAZZATI.K_PUNIZIONE * (forzaPunizione - presa)),
    CFG_PIAZZATI.MIN_CONV, CFG_PIAZZATI.MAX_CONV_CORTA);

  let golPunizione = 0;
  for (let i = 0; i < corte; i++) {
    if (rnd() < convCorta) {
      golPunizione++; tiri++; inPorta++;
      if (specialista) marcatori.push({ id: specialista.id, nome: specialista.nome, tipo: 'punizione_corta' });
    } else if (rnd() < CFG_PIAZZATI.PUNIZIONE_CORTA_CON_TIRO) {
      tiri++;
      if (rnd() < 0.42) inPorta++;
    }
  }

  // --- punizioni lunghe: si mette dentro e si attacca di testa ---
  const lunghe = Math.max(0, poisson(CFG_PIAZZATI.PUNIZIONI_LUNGHE_BASE * p));
  const crossatore = incaricato(lineup, 'battuta', 'punizione_lunga');
  const forzaCross = attaccoAereo * 0.7 + (crossatore?.piazzati?.battuta ?? 50) * 0.3;
  const convLunga = clamp(
    CFG_PIAZZATI.PUNIZIONE_LUNGA_CONVERSIONE * (1 + CFG_PIAZZATI.K_AEREO * (forzaCross - forzaDifesa)),
    CFG_PIAZZATI.MIN_CONV, CFG_PIAZZATI.MAX_CONV);

  for (let i = 0; i < lunghe; i++) {
    if (rnd() < convLunga) {
      golPunizione++; tiri++; inPorta++;
      const f = scegliFinalizzatore(lineup);
      if (f) marcatori.push({ id: f.id, nome: f.nome, tipo: 'punizione_lunga' });
    } else if (rnd() < CFG_PIAZZATI.PUNIZIONE_LUNGA_CON_TIRO) {
      tiri++;
      if (rnd() < 0.35) inPorta++;
    }
  }

  const punizioni = corte + lunghe;

  return {
    corner, golCorner, punizioni, golPunizione,
    gol: golCorner + golPunizione, tiri, inPorta,
    marcatori,
    angoliDx: incaricato(lineup, 'battuta', 'angolo_dx')?.nome ?? null,
    angoliSx: incaricato(lineup, 'battuta', 'angolo_sx')?.nome ?? null,
    punizioniDa: specialista?.nome ?? null,
  };
}
