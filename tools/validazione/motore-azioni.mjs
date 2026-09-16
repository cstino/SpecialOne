// ============================================================
//  PROTOTIPO: MOTORE AZIONE PER AZIONE
//
//  NON E' IL MOTORE DEL GIOCO e non deve diventarlo senza passare dalla suite
//  di validazione. Sta in tools/ apposta: engine/ non lo importa, non lo
//  conosce, e resta quello tarato nella Fase 0.
//
//  PERCHE' ESISTE
//  Il motore attuale e' un modello a blocchi: riduce l'undici a quattro numeri
//  di reparto (DEF/MID/ATT/GK), calcola il controllo, l'xG per blocco e i gol
//  con Poisson. Gli attributi dei giocatori servono solo a distribuire tiri e
//  passaggi a fine partita — cinque su quaranta.
//
//  In Football Manager non esiste un punteggio unico: per ogni singola azione
//  il motore richiama gli attributi rilevanti, pesati per ruolo. Per un
//  passaggio, vision e decisions determinano quante opzioni il giocatore vede,
//  poi passing e composure se lo completa. I gol EMERGONO dalle azioni invece
//  di essere estratti da una distribuzione.
//
//  Questo file prova a fare lo stesso e chiede: i numeri che ne escono
//  reggono i 13 bersagli della Fase 0? Se non li reggono, un motore azione per
//  azione non e' piu' realistico del nostro — e' solo piu' complicato.
//
//  COSA USA DAVVERO: sedici attributi invece di cinque.
//    passaggio   short_passing, skill_long_passing, mentality_vision,
//                mentality_composure
//    difesa      mentality_interceptions, defending_marking_awareness,
//                standing_tackle, mentality_aggression
//    conclusione finishing, mentality_positioning, power_shot_power
//    portiere    gk_diving, gk_reflexes, gk_positioning
//    fisico      pace, physic
//
//  IL MODELLO
//  Il campo e' diviso in tre zone (difesa, centro, attacco) viste dal lato di
//  chi ha la palla. Ogni azione e' un duello logistico fra due valutazioni:
//  chi ha il pallone contro chi lo contrasta in quella zona. Il possesso passa
//  di piede in piede finche' qualcuno non tira, non sbaglia o non viene
//  intercettato. Il tempo avanza a ogni tocco: la partita finisce quando
//  finiscono i 90 minuti, non dopo un numero fisso di eventi.
// ============================================================

import { rnd, gauss } from '../../engine/random.js';

const clamp = (v, a, b) => Math.max(a, Math.min(b, v));

// ------------------------------------------------------------
//  Costanti da tarare. Tenute qui in cima apposta: sono l'unica cosa che si
//  tocca quando i numeri non tornano.
// ------------------------------------------------------------
export const CFG = {
  SECONDI_PARTITA: 90 * 60,
  SEC_PER_AZIONE: 5.0,      // quanto dura in media un tocco
  // Ripidita' della logistica. E' la costante piu' delicata di tutte: piu' e'
  // bassa, piu' ogni singolo duello premia il migliore — e siccome i duelli
  // sono centinaia, il vantaggio si moltiplica. A 11 la squadra piu' forte di
  // 8 punti vinceva il 93% invece dell'84% della Fase 0. A 15 la curva torna
  // vicina a quella validata senza perdere le metriche d'insieme.
  SCALA_DUELLO: 15,
  P_TIRO_IN_AREA: 0.051,    // probabilita' base di concludere invece di continuare, in zona d'attacco
  VANTAGGIO_CASA: 1.4,      // tarato: a 2.2 le vittorie interne salivano al 50%
  SOGLIA_AVANZA: 0.36,      // quanto spesso un passaggio riuscito guadagna una zona
  // Passare e' piu' facile che intercettare: a parita' di valutazione il
  // portatore la spunta quasi sempre. Senza questo margine la percentuale di
  // passaggi riusciti crollava al 62%, contro il 76-88 del calcio vero.
  BONUS_PASSAGGIO: 20,   // riscalato con SCALA_DUELLO: conta il rapporto fra i due
  MALUS_PRESSIONE_TIRO: 0.15,  // quanto la pressione sporca la conclusione
  VANTAGGIO_PORTIERE: 0,       // tarato: col duello cosi' com'e', gia' pari e' il giusto
  QUOTA_SPECCHIO: 0.40,        // frazione di tiri che finisce nello specchio
};

// I pesi dicono quanto ciascun attributo conta in quel gesto. Sommano a 1:
// cosi' il risultato resta sulla scala 1-99 degli attributi e si legge.
const PESI = {
  passaggio: { short_passing: 0.40, mentality_vision: 0.25, mentality_composure: 0.20, skill_long_passing: 0.15 },
  pressione: { mentality_interceptions: 0.35, defending_marking_awareness: 0.30, standing_tackle: 0.25, mentality_aggression: 0.10 },
  conclusione: { finishing: 0.55, mentality_positioning: 0.25, power_shot_power: 0.20 },
  parata: { gk_reflexes: 0.40, gk_diving: 0.35, gk_positioning: 0.25 },
  corsa: { pace: 0.6, physic: 0.4 },
};

function voto(g, gesto) {
  let somma = 0;
  for (const [k, w] of Object.entries(PESI[gesto])) somma += (g.a[k] ?? 40) * w;
  return somma;
}

// Duello logistico: quanto spesso A la spunta su B.
const duello = (a, b) => 1 / (1 + Math.exp(-(a - b) / CFG.SCALA_DUELLO));

// ------------------------------------------------------------
//  Chi tocca il pallone. Non tutti i giocatori partecipano allo stesso modo in
//  ogni zona: in difesa la palla passa dai difensori, in attacco dagli
//  attaccanti. Senza questi pesi il centrale segnerebbe quanto la punta.
// ------------------------------------------------------------
const PESO_ZONA = {
  //         difesa centro attacco
  GK:  [0.25, 0.01, 0.00],
  DEF: [0.50, 0.22, 0.07],
  MID: [0.20, 0.52, 0.35],
  ATT: [0.05, 0.25, 0.58],
};

function scegliPortatore(squadra, zona) {
  const pesi = squadra.inCampo.map((g) => PESO_ZONA[g.rep][zona] + 0.001);
  const tot = pesi.reduce((x, y) => x + y, 0);
  let r = rnd() * tot;
  for (let i = 0; i < pesi.length; i++) { r -= pesi[i]; if (r <= 0) return squadra.inCampo[i]; }
  return squadra.inCampo[squadra.inCampo.length - 1];
}

// Chi contrasta: la difesa avversaria nella zona speculare. Zona 2 per chi
// attacca e' zona 0 per chi difende, quindi l'indice si specchia.
function pressioneAvversaria(avversaria, zona) {
  const zonaDif = 2 - zona;
  let somma = 0, peso = 0;
  for (const g of avversaria.inCampo) {
    if (g.rep === 'GK') continue;
    const w = PESO_ZONA[g.rep][zonaDif] + 0.001;
    somma += voto(g, 'pressione') * w;
    peso += w;
  }
  return peso ? somma / peso : 45;
}

// ------------------------------------------------------------
//  Una partita
// ------------------------------------------------------------
export function simulaAzioni(casa, ospite, opt = {}) {
  const squadre = [casa, ospite];
  const stato = squadre.map(() => ({
    gol: 0, tiri: 0, inPorta: 0, passaggiT: 0, passaggiR: 0, tocchi: 0, marcatori: new Map(),
  }));

  let possesso = rnd() < 0.5 ? 0 : 1;
  let zona = 1;
  let t = 0;

  while (t < CFG.SECONDI_PARTITA) {
    const att = squadre[possesso], dif = squadre[1 - possesso];
    const s = stato[possesso];
    const casaBonus = possesso === 0 && !opt.campoNeutro ? CFG.VANTAGGIO_CASA : 0;

    const portatore = scegliPortatore(att, zona);
    s.tocchi++;
    t += CFG.SEC_PER_AZIONE * (0.6 + rnd() * 0.8);

    const press = pressioneAvversaria(dif, zona);

    // ---- conclusione ----
    if (zona === 2 && portatore.rep !== 'GK') {
      const voglia = CFG.P_TIRO_IN_AREA * (0.5 + voto(portatore, 'conclusione') / 120);
      if (rnd() < voglia) {
        s.tiri++;
        const portiere = dif.inCampo.find((g) => g.rep === 'GK') ?? dif.inCampo[0];
        const qualita = voto(portatore, 'conclusione') + casaBonus - press * CFG.MALUS_PRESSIONE_TIRO;
        const parata = voto(portiere, 'parata');
        // Due passaggi: prima se il tiro e' nello specchio, poi se il portiere
        // ci arriva. Senza il primo, un attaccante scarso segnerebbe comunque
        // troppo: nel calcio vero il grosso dei tiri finisce fuori.
        if (rnd() < duello(qualita, 62) * 2 * CFG.QUOTA_SPECCHIO) {
          s.inPorta++;
          if (rnd() < duello(qualita, parata + CFG.VANTAGGIO_PORTIERE)) {
            s.gol++;
            s.marcatori.set(portatore.id, (s.marcatori.get(portatore.id) ?? 0) + 1);
          }
        }
        possesso = 1 - possesso; zona = 0; t += 25;
        continue;
      }
    }

    // ---- passaggio ----
    s.passaggiT++;
    const avanza = rnd() < CFG.SOGLIA_AVANZA && zona < 2;
    // Un passaggio che guadagna campo e' piu' difficile: lo si tenta in avanti,
    // dove l'avversario e' schierato. E' il motivo per cui il possesso sterile
    // esiste anche nel calcio vero.
    const malusAvanzamento = avanza ? 9 : 0;
    const riesce = rnd() < duello(voto(portatore, 'passaggio') + CFG.BONUS_PASSAGGIO + casaBonus - malusAvanzamento, press);

    if (riesce) {
      s.passaggiR++;
      if (avanza) zona++;
    } else {
      possesso = 1 - possesso;
      // Chi recupera riparte piu' indietro: la zona si specchia.
      zona = clamp(2 - zona, 0, 2);
      t += 3;
    }
  }

  const perSquadra = stato.map((s, i) => ({
    gol: s.gol, tiri: s.tiri, inPorta: s.inPorta,
    passaggiT: s.passaggiT, passaggiR: s.passaggiR,
    passaggiPct: s.passaggiT ? s.passaggiR / s.passaggiT : 0,
    possesso: 0,
    marcatori: [...s.marcatori.entries()],
  }));
  const tocchiTot = stato[0].tocchi + stato[1].tocchi;
  perSquadra[0].possesso = tocchiTot ? stato[0].tocchi / tocchiTot : 0.5;
  perSquadra[1].possesso = 1 - perSquadra[0].possesso;

  return { golC: perSquadra[0].gol, golO: perSquadra[1].gol, casa: perSquadra[0], ospite: perSquadra[1] };
}

// ------------------------------------------------------------
//  Rose di prova da giocatori VERI
// ------------------------------------------------------------
const REP = { GK:'GK', CB:'DEF', LB:'DEF', RB:'DEF', LWB:'DEF', RWB:'DEF',
  CDM:'MID', CM:'MID', CAM:'MID', LM:'MID', RM:'MID', LW:'ATT', RW:'ATT', ST:'ATT', CF:'ATT' };

export function creaSquadraReale(pool, modulo, ovrTarget, nome) {
  const inCampo = [];
  for (const slot of modulo) {
    const candidati = pool.filter((p) => p.posizioni[0] === slot && Math.abs(p.overall - ovrTarget) <= 4);
    const scelti = candidati.length ? candidati : pool.filter((p) => REP[p.posizioni[0]] === REP[slot]);
    const p = scelti[Math.floor(rnd() * scelti.length)];
    inCampo.push({ id: p.id, nome: p.nome, ovr: p.overall, rep: REP[slot], slot, a: p.attributi });
  }
  return { nome, inCampo };
}
