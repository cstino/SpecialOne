// ============================================================
//  PAGELLE — il voto di ogni giocatore, stile SofaScore
//
//  Registro tattico, punti 27 e 31. Il voto non e' estratto a caso: nasce
//  dalle AZIONI che il giocatore fa in partita, riuscite e sbagliate, e da
//  come e' andata la partita. Tutti i reparti pesano uguale: un difensore o un
//  portiere possono essere il migliore in campo.
//
//  FUORI DAL MOTORE VALIDATO, come engine/rigori.js: si calcola DOPO la
//  partita, con un generatore casuale suo (seed separato), e non cambia ne' i
//  gol ne' il risultato. Le azioni partono dai conteggi che il motore ha gia'
//  distribuito fra i giocatori (tiri, passaggi, contrasti, dribbling): qui si
//  decide quali riescono.
//
//  La riuscita dipende da tre cose:
//    1. l'attributo del giocatore per quel gesto;
//    2. il reparto avversario che ha davanti (un'ala contro la loro difesa);
//    3. lo scarto tattico del giocatore (lineup.tattica: ruolo, indicazioni di
//       squadra, morale). E' il pezzo che fa emergere, nella MEDIA VOTO, chi
//       e' adatto al proprio metodo di gioco e chi no.
// ============================================================

import { REPARTO } from './config.js';

// --- generatore casuale proprio (mulberry32): non tocca quello del motore ---
export function generatore(seme) {
  let a = seme >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

export const clamp = (v, a, b) => Math.max(a, Math.min(b, v));

// Sotto questi minuti non si da' il voto: "senza voto", come sui giornali.
export const MINUTI_MINIMI = 15;

// Il peso di ogni gesto sul voto. Tarati con tools/validazione/prova-pagelle.mjs:
// media intorno a 6,7, scarto intorno a 0,6, migliore in campo fra 7,5 e 8,5,
// e l'MVP distribuito su tutti i reparti.
export const PESI = {
  base: 6.4,
  vittoria: 0.15, sconfitta: -0.15,
  gol: { ATT: 1.0, MID: 1.1, DEF: 1.2, GK: 1.5 },
  assist: 0.7,
  tiroInPorta: 0.12, tiroFuori: -0.06,
  // I passaggi sono tanti (un centrocampista ne tenta 60): pesano per la
  // PRECISIONE rispetto all'attesa, non uno per uno, piu' un poco di volume.
  precisione: 0.04, attesaPassaggi: 0.82, volumePassaggi: 0.003,
  contrastoVinto: 0.14, contrastoPerso: -0.1,
  intervento: 0.11, interventoMancato: -0.12,
  dribblingRiuscito: 0.1, dribblingFallito: -0.06,
  parata: 0.17,
  // DEF era -0,14: nelle partite vere si segna molto (Serie F 4,3 gol a
  // partita) e i difensori avevano la media piu' bassa di tutti (6,49 contro
  // 6,81 degli attaccanti su 20.000 voti di LegaBot). Registro, punto 38.
  golSubito: { GK: -0.3, DEF: -0.11, MID: -0.03, ATT: 0 },
  // Aggiustamento di base per reparto, tarato sui voti veri: medie vicine fra
  // i reparti come su SofaScore, con gli attaccanti piu' estremi.
  basePerReparto: { GK: 0, DEF: 0.04, MID: 0, ATT: -0.08 },
  portaInviolata: { GK: 0.4, DEF: 0.35, MID: 0.08, ATT: 0 },
  giallo: -0.3, rosso: -1.5,
  rumore: 0.15,
  // Quanto lo scarto tattico (punti di overall) sposta la riuscita dei gesti.
  tattica: 0.02,
};

// Gli interventi difensivi (chiusure, intercetti, anticipi) per posizione, a
// pressione avversaria media. Il motore non li distribuisce: senza, un
// difensore aveva due contrasti a partita e poteva solo perdere punti.
export const INTERVENTI = { CB: 7, LB: 4.5, RB: 4.5, LWB: 3.5, RWB: 3.5, CDM: 3.5, CM: 2, CAM: 1, LM: 1.5, RM: 1.5, LW: 0.5, RW: 0.5, ST: 0.3, CF: 0.3 };

// Il reparto avversario contro cui si gioca ogni gesto.
export const AVVERSARIO = { DEF: 'ATT', MID: 'MID', ATT: 'DEF', GK: 'ATT' };

export function mediaReparto(titolari, slots, reparto) {
  let s = 0, n = 0;
  slots.forEach((sl, i) => { const g = titolari[i]; if (g && REPARTO[sl] === reparto) { s += g.ovr; n++; } });
  return n ? s / n : 70;
}

export function quante(rng, n, p) {
  let ok = 0;
  for (let i = 0; i < n; i++) if (rng() < p) ok++;
  return ok;
}

/**
 * I voti di una partita.
 *
 * lati = { casa, ospite }, ognuno:
 *   giocatori: Map id -> giocatore (con ovr, attributi o i cinque attributi del motore)
 *   lineup:    il lineup di partenza (slots, titolari, tattica)
 *   stats:     result.perGiocatore[lato] (minuti, tiri, passaggi, contrasti, dribbling, marcatoriIds, slot)
 *   squadra:   result.statsCasa / statsOspite (tiri, inPorta)
 *   golFatti, golSubiti
 *   assist:    Map id -> assist (dalla cronaca)
 *   cartellini: [{ giocatore, tipo }]
 *
 * Restituisce una Map id -> { voto, dettaglio } per chi ha giocato almeno
 * MINUTI_MINIMI; gli altri ricevono { voto: null }.
 */
export function pagelle(lati, seme) {
  const rng = generatore(seme);
  const gauss = () => {
    const u = 1 - rng(), v = rng();
    return Math.sqrt(-2 * Math.log(u)) * Math.cos(2 * Math.PI * v);
  };
  const out = new Map();
  for (const [lato, avv] of [['casa', 'ospite'], ['ospite', 'casa']]) {
    const L = lati[lato], A = lati[avv];
    const forzaAvv = {
      DEF: mediaReparto(A.lineup.titolari, A.lineup.slots, 'DEF'),
      MID: mediaReparto(A.lineup.titolari, A.lineup.slots, 'MID'),
      ATT: mediaReparto(A.lineup.titolari, A.lineup.slots, 'ATT'),
    };
    const gol = new Map();
    for (const id of L.stats.marcatoriIds ?? []) gol.set(id, (gol.get(id) ?? 0) + 1);
    const cart = new Map();
    for (const c of L.cartellini ?? []) cart.set(c.giocatore, c.tipo);
    // Le parate le fa chi sta in porta: tiri in porta avversari non diventati gol.
    const parateTotali = Math.max(0, Number(A.squadra.inPorta ?? 0) - L.golSubiti);
    const tiriInPortaMiei = Number(L.squadra.inPorta ?? 0);
    const tiriMiei = Math.max(1, Number(L.squadra.tiri ?? 0));
    const risultato = L.golFatti > L.golSubiti ? PESI.vittoria : L.golFatti < L.golSubiti ? PESI.sconfitta : 0;

    for (const [id, minuti] of L.stats.minuti) {
      const g = L.giocatori.get(id);
      const slot = L.stats.slot?.get(id) ?? g?.posizioni?.[0] ?? 'CM';
      if (!g || minuti < MINUTI_MINIMI) { out.set(id, { voto: null, lato }); continue; }
      const rep = REPARTO[slot] ?? 'MID';
      const quota = Math.min(1, minuti / 90);

      // Partita con rendimento in campo (engine/rendimento.js): il voto e' la
      // linea che il mister ha visto crescere durante la gara, completata solo
      // da cio' che si sa a fine partita (tiri, parate, porta inviolata,
      // risultato). Nessuna estrazione in piu': niente rumore.
      const dettaglioLive = L.live?.dettaglio(id);
      if (dettaglioLive) {
        const tiriL = L.stats.tiri?.get(id) ?? 0;
        const golL = gol.get(id) ?? 0;
        const inPortaL = Math.max(golL, Math.min(tiriL, Math.round(tiriL * tiriInPortaMiei / tiriMiei)));
        let extra = (inPortaL - golL) * PESI.tiroInPorta + (tiriL - inPortaL) * PESI.tiroFuori;
        const dl = { ...dettaglioLive, tiri: tiriL, tiriInPorta: inPortaL, gol: golL, assist: L.assist?.get(id) ?? 0 };
        if (rep === 'GK') { dl.parate = parateTotali; extra += parateTotali * PESI.parata; }
        if (minuti >= 60 && L.golSubiti === 0) extra += PESI.portaInviolata[rep] ?? 0;
        extra += risultato * quota;
        const votoL = L.live.votoFinale(id, { gol: golL, assist: dl.assist, minuti, extra });
        out.set(id, { voto: Math.round(clamp(votoL, 3, 10) * 10) / 10, dettaglio: dl, lato });
        continue;
      }
      const a = g.attributi ?? {};
      const delta = L.lineup.tattica ? L.lineup.tattica(g, slot) : 0;
      const spinta = PESI.tattica * delta;
      const contro = forzaAvv[AVVERSARIO[rep]] ?? 70;
      let voto = PESI.base + (PESI.basePerReparto[rep] ?? 0);
      const d = {};

      // passaggi
      const pass = L.stats.passaggi?.get(id) ?? 0;
      const pPass = clamp(0.8 + ((a.short_passing ?? g.short_passing ?? 65) - 68) / 220 - (contro - 70) / 260 + spinta, 0.55, 0.96);
      d.passaggiRiusciti = quante(rng, pass, pPass); d.passaggi = pass;
      voto += (d.passaggiRiusciti - pass * PESI.attesaPassaggi) * PESI.precisione + pass * PESI.volumePassaggi;

      // interventi difensivi: tanti quanti l'avversario ne provoca attaccando
      const pressione = clamp(Number(A.squadra.tiri ?? 12) / 12, 0.5, 1.8);
      const interventi = Math.round((INTERVENTI[slot] ?? 0) * pressione * quota + (rng() - 0.5));
      const difesa = ((a.standing_tackle ?? g.tackle ?? 60) + (a.mentality_interceptions ?? g.tackle ?? 60) + (a.defending_marking_awareness ?? g.tackle ?? 60)) / 3;
      const pInt = clamp(0.62 + (difesa - 62) / 170 - (contro - 70) / 220 + spinta, 0.3, 0.92);
      d.interventiRiusciti = quante(rng, Math.max(0, interventi), pInt); d.interventi = Math.max(0, interventi);
      voto += d.interventiRiusciti * PESI.intervento + (d.interventi - d.interventiRiusciti) * PESI.interventoMancato;

      // contrasti: i duelli difensivi che il motore gli ha assegnato
      const duelli = L.stats.contrasti?.get(id) ?? 0;
      const pDuello = clamp(0.6 + ((a.standing_tackle ?? g.tackle ?? 60) - 62) / 170 - (contro - 70) / 220 + spinta, 0.3, 0.9);
      d.contrastiVinti = quante(rng, duelli, pDuello); d.contrasti = duelli;
      voto += d.contrastiVinti * PESI.contrastoVinto + (duelli - d.contrastiVinti) * PESI.contrastoPerso;

      // dribbling
      const dri = L.stats.dribbling?.get(id) ?? 0;
      const pDri = clamp(0.55 + ((a.dribbling ?? g.dribbling ?? 60) - 65) / 160 - (contro - 70) / 220 + spinta, 0.25, 0.88);
      d.dribblingRiusciti = quante(rng, dri, pDri); d.dribbling = dri;
      voto += d.dribblingRiusciti * PESI.dribblingRiuscito + (dri - d.dribblingRiusciti) * PESI.dribblingFallito;

      // tiri: quelli in porta ripartiti in proporzione, i gol a parte
      const tiri = L.stats.tiri?.get(id) ?? 0;
      const golSuoi = gol.get(id) ?? 0;
      const inPorta = Math.max(golSuoi, Math.min(tiri, Math.round(tiri * tiriInPortaMiei / tiriMiei)));
      d.tiri = tiri; d.tiriInPorta = inPorta; d.gol = golSuoi;
      voto += (inPorta - golSuoi) * PESI.tiroInPorta + (tiri - inPorta) * PESI.tiroFuori;
      voto += golSuoi * (PESI.gol[rep] ?? 1);

      d.assist = L.assist?.get(id) ?? 0;
      voto += d.assist * PESI.assist;

      // la porta: portiere e difesa rispondono dei gol subiti
      if (rep === 'GK') { d.parate = parateTotali; voto += parateTotali * PESI.parata; }
      if (minuti >= 60 && L.golSubiti === 0) voto += PESI.portaInviolata[rep] ?? 0;
      voto += L.golSubiti * quota * (PESI.golSubito[rep] ?? 0);

      voto += risultato * quota;
      const c = cart.get(id);
      if (c === 'giallo') voto += PESI.giallo;
      else if (c) voto += PESI.rosso;

      // Chi gioca poco resta vicino al 6: ha avuto meno occasioni per farsi notare.
      voto = 6 + (voto - 6) * (0.45 + 0.55 * quota);
      voto += gauss() * PESI.rumore;
      out.set(id, { voto: Math.round(clamp(voto, 3, 10) * 10) / 10, dettaglio: d, lato });
    }
  }
  return out;
}

/** Il migliore in campo: il voto piu' alto della partita (a parita', il primo). */
export function migliorInCampo(voti) {
  let id = null, max = -1;
  for (const [k, v] of voti) if (v.voto !== null && v.voto > max) { max = v.voto; id = k; }
  return id;
}
