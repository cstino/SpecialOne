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

// Il peso di ogni gesto sul voto. Scala da giornale italiano (9/11/2026,
// richiesta del committente: "ho perso e ho piu' sufficienti che
// insufficienti"): il 6 e' una partita normale, chi perde va quasi sempre
// sotto. Prima la scala era quella di SofaScore (media 6,7, base 6,4, chi
// perdeva prendeva in media 6,38 e solo il 13% sotto il 6).
// Tarati con tools/validazione/prova-pagelle.mjs.
export const PESI = {
  base: 6.05,
  // Il risultato: vittoria/sconfitta, piu' un tanto per ogni gol di scarto
  // oltre il primo (al massimo tre). Perdere 0-4 non e' perdere 1-2.
  vittoria: 0.3, sconfitta: -0.3, perGolDiScarto: 0.1,
  gol: { ATT: 1.0, MID: 1.1, DEF: 1.2, GK: 1.5 },
  assist: 0.6,
  tiroInPorta: 0.15, tiroFuori: -0.1,
  // Le azioni contano per il SALDO fra riuscite e sbagliate, misurato sulla
  // riuscita media della lega (attesa): chi sta nella media non guadagna
  // niente, ogni gesto riuscito in piu' sale, ogni errore in piu' scende. Con
  // l'attesa dei passaggi a 0,82 un passaggio sbagliato costa quanto 4-5
  // riusciti. Niente piu' punti per il solo numero di passaggi tentati.
  attesa: { pass: 0.82, int: 0.64, duelli: 0.63, dri: 0.62 },
  saldo: { pass: 0.09, int: 0.45, duelli: 0.45, dri: 0.35 },
  parata: 0.12,
  golSubito: { GK: -0.3, DEF: -0.12, MID: -0.04, ATT: 0 },
  // Aggiustamento di base per reparto: medie vicine fra i reparti.
  basePerReparto: { GK: -0.1, DEF: 0.12, MID: 0.04, ATT: -0.1 },
  portaInviolata: { GK: 0.4, DEF: 0.4, MID: 0.1, ATT: 0 },
  giallo: -0.3, rosso: -1.5, tettoRosso: 5.0,
  // Errore individuale su un gol subito (solo nel rendimento live): quota di
  // gol che nascono da un errore, penalita' e chi ne risponde per reparto.
  errore: -0.9, quotaGolConErrore: 0.3, pesoErrore: { GK: 1.2, DEF: 2.5, MID: 1, ATT: 0.1 },
  rumore: 0.15,
  // Quanto lo scarto tattico (punti di overall) sposta la riuscita dei gesti.
  tattica: 0.02,
};

// Il saldo delle azioni: riuscite meno quelle attese con la riuscita media.
export function saldoAzioni(ok, att) {
  let v = 0;
  for (const k of ['pass', 'int', 'duelli', 'dri']) v += PESI.saldo[k] * ((ok[k] ?? 0) - PESI.attesa[k] * (att[k] ?? 0));
  return v;
}

// Il peso del risultato per chi ha giocato tutta la partita.
export function pesoRisultato(golFatti, golSubiti) {
  const scarto = golFatti - golSubiti;
  if (scarto === 0) return 0;
  const extra = PESI.perGolDiScarto * Math.min(3, Math.abs(scarto) - 1);
  return scarto > 0 ? PESI.vittoria + extra : PESI.sconfitta - extra;
}

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
 * MINUTI_MINIMI o ha segnato/fatto assist; gli altri ricevono { voto: null }.
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
    const risultato = pesoRisultato(L.golFatti, L.golSubiti);

    for (const [id, minuti] of L.stats.minuti) {
      const g = L.giocatori.get(id);
      const slot = L.stats.slot?.get(id) ?? g?.posizioni?.[0] ?? 'CM';
      // Sotto MINUTI_MINIMI "senza voto", tranne chi ha segnato o fatto assist (21/10/2026, decisione del committente:
      // chi entra e decide la partita deve avere il voto, come al fantacalcio).
      const decisivo = (gol.get(id) ?? 0) > 0 || (L.assist?.get(id) ?? 0) > 0;
      if (!g || (minuti < MINUTI_MINIMI && !decisivo)) { out.set(id, { voto: null, lato }); continue; }
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

      // interventi difensivi: tanti quanti l'avversario ne provoca attaccando
      const pressione = clamp(Number(A.squadra.tiri ?? 12) / 12, 0.5, 1.8);
      const interventi = Math.round((INTERVENTI[slot] ?? 0) * pressione * quota + (rng() - 0.5));
      const difesa = ((a.standing_tackle ?? g.tackle ?? 60) + (a.mentality_interceptions ?? g.tackle ?? 60) + (a.defending_marking_awareness ?? g.tackle ?? 60)) / 3;
      const pInt = clamp(0.62 + (difesa - 62) / 170 - (contro - 70) / 220 + spinta, 0.3, 0.92);
      d.interventiRiusciti = quante(rng, Math.max(0, interventi), pInt); d.interventi = Math.max(0, interventi);

      // contrasti: i duelli difensivi che il motore gli ha assegnato
      const duelli = L.stats.contrasti?.get(id) ?? 0;
      const pDuello = clamp(0.6 + ((a.standing_tackle ?? g.tackle ?? 60) - 62) / 170 - (contro - 70) / 220 + spinta, 0.3, 0.9);
      d.contrastiVinti = quante(rng, duelli, pDuello); d.contrasti = duelli;

      // dribbling
      const dri = L.stats.dribbling?.get(id) ?? 0;
      const pDri = clamp(0.55 + ((a.dribbling ?? g.dribbling ?? 60) - 65) / 160 - (contro - 70) / 220 + spinta, 0.25, 0.88);
      d.dribblingRiusciti = quante(rng, dri, pDri); d.dribbling = dri;
      voto += saldoAzioni(
        { pass: d.passaggiRiusciti, int: d.interventiRiusciti, duelli: d.contrastiVinti, dri: d.dribblingRiusciti },
        { pass, int: d.interventi, duelli, dri });

      // tiri: quelli in porta ripartiti in proporzione, i gol a parte
      const tiri = L.stats.tiri?.get(id) ?? 0;
      const golSuoi = gol.get(id) ?? 0;
      const inPorta = Math.max(golSuoi, Math.min(tiri, Math.round(tiri * tiriInPortaMiei / tiriMiei)));
      d.tiri = tiri; d.tiriInPorta = inPorta; d.gol = golSuoi;
      voto += (inPorta - golSuoi) * PESI.tiroInPorta + (tiri - inPorta) * PESI.tiroFuori;
      d.assist = L.assist?.get(id) ?? 0;
      // Gol e assist contano per intero anche a chi gioca poco: fuori dalla riduzione verso il 6 (21/10/2026).
      const decisivi = golSuoi * (PESI.gol[rep] ?? 1) + d.assist * PESI.assist;

      // la porta: portiere e difesa rispondono dei gol subiti
      if (rep === 'GK') { d.parate = parateTotali; voto += parateTotali * PESI.parata; }
      if (minuti >= 60 && L.golSubiti === 0) voto += PESI.portaInviolata[rep] ?? 0;
      voto += L.golSubiti * quota * (PESI.golSubito[rep] ?? 0);

      voto += risultato * quota;
      const c = cart.get(id);
      if (c === 'giallo') voto += PESI.giallo;
      else if (c) voto += PESI.rosso;

      // Chi gioca poco resta vicino al 6: ha avuto meno occasioni per farsi notare.
      voto = 6 + (voto - 6) * (0.45 + 0.55 * quota) + decisivi;
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
