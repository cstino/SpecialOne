// ============================================================
//  RENDIMENTO IN PARTITA — il voto che cresce mentre si gioca
//
//  Registro tattico, punto 46. Il voto in pagella non nasce piu' solo dopo il
//  fischio finale: ogni giocatore in campo accumula, blocco per blocco, le sue
//  azioni (passaggi, interventi, contrasti, dribbling), i gol e gli assist, i
//  cartellini e i gol subiti mentre era in campo. E' la STESSA formula delle
//  pagelle (engine/pagelle.js, stessi PESI): il voto che il mister vede a meta'
//  gara e quello che compare a fine partita sono la stessa linea, che arriva
//  fino al 90'. Il mister (engine.js, sostituzioni) lo legge per cambiare chi
//  sta giocando male, anche se e' ancora fresco.
//
//  Fuori dal motore validato, come pagelle.js e rigori.js: generatori casuali
//  PROPRI (seme separato), quindi i flussi di xG, gol, infortuni e cartellini
//  non si spostano di una virgola. Non c'e' nessuna "forma del giorno": il
//  caso entra solo dove entrava gia', cioe' nella riuscita di ogni gesto, che
//  dipende dall'attributo del giocatore, dal reparto avversario e dallo scarto
//  tattico.
// ============================================================

import { CFG, REPARTO, PESI_SLOT, pesoStat } from './config.js';
import { PESI, INTERVENTI, AVVERSARIO, mediaReparto, generatore, quante, clamp } from './pagelle.js';

// Quanti gol non hanno un assist (rigori, tiri da fuori, ribattute, azioni
// personali) e quanto pesa ogni ruolo come uomo-assist. Erano nella Edge
// Function: ora il motore sceglie marcatore e assist nel blocco in cui il gol
// cade, e la Edge Function si limita a raccontarlo.
export const QUOTA_GOL_SENZA_ASSIST = 0.28;
export const PESO_ASSIST = {
  GK: 0.02,
  CB: 0.15, LB: 0.75, RB: 0.75, LWB: 0.90, RWB: 0.90,
  CDM: 0.50, CM: 0.95, CAM: 1.60, LM: 1.20, RM: 1.20,
  LW: 1.70, RW: 1.70, ST: 1.00, CF: 1.10,
};

// I gesti seguiti blocco per blocco: chiave dello stato, tipo di statistica
// del motore (per i pesi di ruolo) e attributo del giocatore.
const GESTI = [
  ['pass', 'passaggi', 'short_passing'],
  ['duelli', 'contrasti', 'tackle'],
  ['dri', 'dribbling', 'dribbling'],
];

export function creaRendimento(seme) {
  const rng = generatore(seme);
  // Un flusso a parte per marcatori e assist: se cambia il numero di azioni
  // tentate non devono cambiare i gol.
  const rngGol = generatore((seme ^ 0x9e3779b9) >>> 0);
  const stati = new Map();
  const golDiSquadra = { casa: new Map(), ospite: new Map() };

  const statoDi = (g, lato, slot) => {
    let s = stati.get(g.id);
    if (!s) {
      s = {
        lato, slot, blocchi: 0,
        esp: { pass: 0, duelli: 0, dri: 0, int: 0 },
        att: { pass: 0, duelli: 0, dri: 0, int: 0 },
        ok: { pass: 0, duelli: 0, dri: 0, int: 0 },
        gol: 0, assist: 0, golSubiti: 0, giallo: false, rosso: false,
      };
      stati.set(g.id, s);
    }
    s.lato = lato; s.slot = slot;
    return s;
  };

  // Il voto da uno stato. `extra` lo completa a fine partita (gol e assist
  // definitivi, minuti veri, tiri, parate, porta inviolata, risultato).
  function votoDa(s, extra = {}) {
    const rep = REPARTO[s.slot] ?? 'MID';
    const minuti = extra.minuti ?? s.blocchi * 90 / CFG.BLOCCHI_PARTITA;
    const quota = Math.min(1, minuti / 90);
    let v = PESI.base + (PESI.basePerReparto[rep] ?? 0);
    v += (s.ok.pass - s.att.pass * PESI.attesaPassaggi) * PESI.precisione + s.att.pass * PESI.volumePassaggi;
    v += s.ok.int * PESI.intervento + (s.att.int - s.ok.int) * PESI.interventoMancato;
    v += s.ok.duelli * PESI.contrastoVinto + (s.att.duelli - s.ok.duelli) * PESI.contrastoPerso;
    v += s.ok.dri * PESI.dribblingRiuscito + (s.att.dri - s.ok.dri) * PESI.dribblingFallito;
    v += (extra.gol ?? s.gol) * (PESI.gol[rep] ?? 1) + (extra.assist ?? s.assist) * PESI.assist;
    v += s.golSubiti * (PESI.golSubito[rep] ?? 0);
    if (s.rosso) v += PESI.rosso; else if (s.giallo) v += PESI.giallo;
    v += extra.extra ?? 0;
    // Chi gioca poco resta vicino al 6: ha avuto meno occasioni per farsi notare.
    return 6 + (v - 6) * (0.45 + 0.55 * quota);
  }

  return {
    stati,

    // Un blocco giocato. `presenti` = chi era in campo a inizio blocco
    // ({ g, slot }), `avversari` = la formazione avversaria, `possesso` = il
    // possesso del lato nel blocco, `volumi` = passaggi, contrasti e dribbling
    // di SQUADRA del blocco (stesse formule delle statistiche di squadra),
    // `xgAvversario` = quanto ha attaccato l'avversario (pressione sui difensori).
    aggiornaBlocco({ lato, presenti, avversari, volumi, xgAvversario, golSubitiBlocco, tattica }) {
      const nb = CFG.BLOCCHI_PARTITA;
      const contro = {
        DEF: mediaReparto(avversari.titolari, avversari.slots, 'DEF'),
        MID: mediaReparto(avversari.titolari, avversari.slots, 'MID'),
        ATT: mediaReparto(avversari.titolari, avversari.slots, 'ATT'),
      };
      // Stessa idea di Number(tiri)/12 delle pagelle (una squadra tira in media
      // ~10 volte: 0,85): quanto l'avversario ha attaccato nel blocco rispetto a
      // un blocco "medio", cioe' a XG_BASE_BLOCCO.
      const pressione = clamp(0.85 * xgAvversario / CFG.XG_BASE_BLOCCO, 0.5, 1.8);

      const pesiPerGesto = GESTI.map(([, tipo, attr]) => {
        const pesi = presenti.map(({ g, slot }) => pesoStat(tipo, slot) * ((g[attr] ?? 60) / 100));
        return { pesi, tot: pesi.reduce((a, b) => a + b, 0) || 1 };
      });

      presenti.forEach(({ g, slot }, i) => {
        const s = statoDi(g, lato, slot);
        s.blocchi++;
        const rep = REPARTO[slot] ?? 'MID';
        const a = g.attributi ?? {};
        const delta = tattica ? tattica(g, slot) : 0;
        const spinta = PESI.tattica * delta;
        const avv = contro[AVVERSARIO[rep]] ?? 70;

        GESTI.forEach(([chiave], k) => {
          s.esp[chiave] += volumi[chiave] * pesiPerGesto[k].pesi[i] / pesiPerGesto[k].tot;
        });
        s.esp.int += (INTERVENTI[slot] ?? 0) * pressione / nb;

        const prova = (chiave, p) => {
          const n = Math.floor(s.esp[chiave] + 0.5) - s.att[chiave];
          if (n <= 0) return;
          s.att[chiave] += n;
          s.ok[chiave] += quante(rng, n, p);
        };
        prova('pass', clamp(0.8 + ((a.short_passing ?? g.short_passing ?? 65) - 68) / 220 - (avv - 70) / 260 + spinta, 0.55, 0.96));
        const difesa = ((a.standing_tackle ?? g.tackle ?? 60) + (a.mentality_interceptions ?? g.tackle ?? 60) + (a.defending_marking_awareness ?? g.tackle ?? 60)) / 3;
        prova('int', clamp(0.62 + (difesa - 62) / 170 - (avv - 70) / 220 + spinta, 0.3, 0.92));
        prova('duelli', clamp(0.6 + ((a.standing_tackle ?? g.tackle ?? 60) - 62) / 170 - (avv - 70) / 220 + spinta, 0.3, 0.9));
        prova('dri', clamp(0.55 + ((a.dribbling ?? g.dribbling ?? 60) - 65) / 160 - (avv - 70) / 220 + spinta, 0.25, 0.88));

        if (golSubitiBlocco > 0) s.golSubiti += golSubitiBlocco;
      });
    },

    // Marcatore e assist di un gol su azione, scelti fra chi e' in campo ADESSO.
    // Stessi pesi di prima (engine.js marcatori() e Edge Function scegliAssist).
    assegnaGol(lato, L) {
      const gia = golDiSquadra[lato];
      const candidati = [], pesi = [];
      L.slots.forEach((slot, i) => {
        const g = L.titolari[i];
        if (!g || slot === 'GK') return;
        candidati.push({ g, slot });
        pesi.push((PESI_SLOT[slot]?.ATT ?? 0.1) * Math.pow(g.finishing / 100, 1.5) * Math.pow(CFG.DAMPING_MARCATORE, gia.get(g.id) ?? 0) + 0.001);
      });
      if (!candidati.length) return null;
      const scegli = (lista, w) => {
        const tot = w.reduce((a, b) => a + b, 0);
        if (tot <= 0) return lista[Math.floor(rngGol() * lista.length)];
        let r = rngGol() * tot;
        for (let i = 0; i < lista.length; i++) { r -= w[i]; if (r <= 0) return lista[i]; }
        return lista[lista.length - 1];
      };
      const marcatore = scegli(candidati, pesi).g;
      gia.set(marcatore.id, (gia.get(marcatore.id) ?? 0) + 1);
      let assist = null;
      if (rngGol() >= QUOTA_GOL_SENZA_ASSIST) {
        // Anche il portiere puo' dare l'assist (peso minimo), come nella Edge Function.
        const tutti = [], pesiAssist = [];
        L.slots.forEach((slot, i) => {
          const g = L.titolari[i];
          if (!g || g.id === marcatore.id) return;
          tutti.push(g);
          pesiAssist.push((PESO_ASSIST[slot] ?? 0.5) * ((g.short_passing ?? 60) / 100));
        });
        if (tutti.length) assist = scegli(tutti, pesiAssist).id;
      }
      return { marcatore: marcatore.id, assist };
    },

    gol(id, assistId) {
      const s = stati.get(id);
      if (s) s.gol++;
      if (assistId != null) { const a = stati.get(assistId); if (a) a.assist++; }
    },

    cartellino(id, tipo) {
      const s = stati.get(id);
      if (!s) return;
      if (tipo === 'giallo') s.giallo = true;
      else s.rosso = true; // doppio giallo e rosso diretto
    },

    // Il voto di adesso (solo cio' che e' successo finora).
    voto(id) {
      const s = stati.get(id);
      return s ? votoDa(s) : null;
    },
    blocchiGiocati(id) { return stati.get(id)?.blocchi ?? 0; },

    // A fine partita: voto completo e dettaglio coerenti con il live.
    votoFinale(id, extra) {
      const s = stati.get(id);
      return s ? votoDa(s, extra) : null;
    },
    dettaglio(id) {
      const s = stati.get(id);
      if (!s) return null;
      return {
        passaggi: s.att.pass, passaggiRiusciti: s.ok.pass,
        interventi: s.att.int, interventiRiusciti: s.ok.int,
        contrasti: s.att.duelli, contrastiVinti: s.ok.duelli,
        dribbling: s.att.dri, dribblingRiusciti: s.ok.dri,
      };
    },

    // Tentativi per giocatore: le statistiche individuali del motore.
    tentativi(lato, chiave) {
      const out = new Map();
      for (const [id, s] of stati) if (s.lato === lato && s.att[chiave] > 0) out.set(id, s.att[chiave]);
      return out;
    },
  };
}
