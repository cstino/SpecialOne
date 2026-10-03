// ============================================================
//  RUOLI — quello che in Football Manager sono i player roles
//
//  Un COMPITO dice quanto un giocatore si sbilancia in avanti. Un RUOLO dice
//  DOVE va: dentro o largo. Sono due assi indipendenti, e il secondo esisteva
//  solo da quando il campo ha le corsie (engine/corsie.js).
//
//  E' la distinzione che mancava. Il terzino che si sovrappone e quello che
//  rientra a centrocampo avanzano uguale, ma lasciano scoperte due cose
//  diverse: il primo la sua fascia in profondita', il secondo la fascia e
//  basta. L'avversario puo' leggerli in modo diverso, ed e' per questo che i
//  ruoli aggiungono profondita' dove i soli compiti non ne aggiungevano
//  (registro, punti 13 e 14).
//
//  DUE NUMERI, NON UN ELENCO DI CASI. Ogni ruolo e' una coppia:
//    dentro      -1 = si allarga, +1 = rientra verso il centro
//    avanti      -1 = arretra,    +1 = si spinge in avanti
//  Cosi' un ruolo nuovo e' due numeri e una riga di commento, non un blocco di
//  codice — e si compone con i compiti invece di sovrapporsi a loro.
//
//  Il PROFILO dice chi sa interpretarlo: attributi FC 26, letti come
//  sbilanciamento e non come valore assoluto (registro, punti 1 e 27). Il
//  ruolo base di ogni posizione non ha profilo ed e' neutro: chi non tocca
//  niente non guadagna e non perde.
//
//  La resistenza non entra in nessun profilo: la conta gia' il motore nella
//  fatica, e i compiti di corsa la usano come idoneita'. Metterla anche qui
//  la premierebbe due volte.
// ============================================================

// Le chiavi sono quelle del catalogo (tools/importazione/normalizza.py).
const MARCATURA = 'defending_marking_awareness';
const CONTRASTO = 'standing_tackle';
const FORZA = 'power_strength';
const TESTA = 'attacking_heading_accuracy';
const PASS_CORTO = 'short_passing';
const PASS_LUNGO = 'skill_long_passing';
const VISIONE = 'mentality_vision';
const FREDDEZZA = 'mentality_composure';
const CROSS = 'attacking_crossing';
const VELOCITA = 'movement_sprint_speed';
const ACCELERAZIONE = 'movement_acceleration';
const DRIBBLING = 'dribbling';
const CONTROLLO = 'skill_ball_control';
const INTERCETTI = 'mentality_interceptions';
const AGGRESSIVITA = 'mentality_aggression';
const INSERIMENTO = 'mentality_positioning';
const TIRO = 'finishing';
const TIRO_LONTANO = 'power_long_shots';
const EFFETTO = 'skill_curve';
const AGILITA = 'movement_agility';
const REATTIVITA = 'movement_reactions';

export const RUOLI = {
  // --- difensori centrali ---
  centrale:            { per: ['CB'], dentro:  0.0, avanti:  0.0, profilo: null },
  centrale_marcatore:  { per: ['CB'], dentro:  0.2, avanti: -0.5, profilo: [MARCATURA, CONTRASTO, FORZA, TESTA] },
  centrale_impostatore:{ per: ['CB'], dentro:  0.0, avanti:  0.5, profilo: [PASS_CORTO, PASS_LUNGO, VISIONE, FREDDEZZA] },

  // --- terzini ---
  terzino:             { per: ['LB','RB','LWB','RWB'], dentro:  0.0, avanti:  0.0, profilo: null },
  terzino_offensivo:   { per: ['LB','RB','LWB','RWB'], dentro: -0.3, avanti:  0.8, profilo: [CROSS, VELOCITA, DRIBBLING, ACCELERAZIONE] },
  terzino_interno:     { per: ['LB','RB','LWB','RWB'], dentro:  0.8, avanti:  0.4, profilo: [PASS_CORTO, CONTROLLO, VISIONE, INTERCETTI] },
  terzino_bloccato:    { per: ['LB','RB','LWB','RWB'], dentro:  0.1, avanti: -0.6, profilo: [MARCATURA, CONTRASTO, INTERCETTI, FORZA] },

  // --- centrocampisti centrali ---
  mediano:             { per: ['CDM','CM','CAM'], dentro:  0.0, avanti:  0.0, profilo: null },
  regista:             { per: ['CDM','CM','CAM'], dentro:  0.4, avanti: -0.2, profilo: [VISIONE, PASS_LUNGO, PASS_CORTO, FREDDEZZA] },
  mezzala:             { per: ['CDM','CM','CAM'], dentro: -0.5, avanti:  0.4, profilo: [DRIBBLING, CONTROLLO, PASS_CORTO, AGILITA] },
  incursore:           { per: ['CDM','CM','CAM'], dentro:  0.1, avanti:  0.8, profilo: [INSERIMENTO, TIRO, ACCELERAZIONE, TIRO_LONTANO] },
  schermo:             { per: ['CDM','CM','CAM'], dentro:  0.3, avanti: -0.7, profilo: [INTERCETTI, CONTRASTO, MARCATURA, AGGRESSIVITA] },

  // --- esterni ---
  esterno:             { per: ['LM','RM','LW','RW'], dentro:  0.0, avanti:  0.0, profilo: null },
  ala_pura:            { per: ['LM','RM','LW','RW'], dentro: -0.5, avanti:  0.4, profilo: [VELOCITA, ACCELERAZIONE, CROSS, DRIBBLING] },
  esterno_a_rientrare: { per: ['LM','RM','LW','RW'], dentro:  0.8, avanti:  0.3, profilo: [TIRO, EFFETTO, DRIBBLING, AGILITA] },
  esterno_difensivo:   { per: ['LM','RM','LW','RW'], dentro:  0.2, avanti: -0.5, profilo: [CONTRASTO, INTERCETTI, VELOCITA, MARCATURA] },

  // --- punte ---
  punta:               { per: ['ST','CF'], dentro:  0.0, avanti:  0.0, profilo: null },
  finalizzatore:       { per: ['ST','CF'], dentro:  0.3, avanti:  0.4, profilo: [TIRO, INSERIMENTO, REATTIVITA, FREDDEZZA] },
  punta_di_manovra:    { per: ['ST','CF'], dentro:  0.0, avanti: -0.6, profilo: [PASS_CORTO, VISIONE, CONTROLLO, FORZA] },
};

// Il metro di paragone interno al giocatore: tutti gli attributi che un
// profilo puo' chiedere. Il profilo e' la differenza fra la media dei suoi
// attributi e questa, cioe' "in cosa e' piu' bravo di quanto sia in generale".
export const ATTRIBUTI_GENERALI = [...new Set(Object.values(RUOLI).flatMap((r) => r.profilo ?? []))];

function media(attributi, chiavi) {
  let somma = 0;
  for (const k of chiavi) {
    const v = attributi?.[k];
    if (typeof v !== 'number' || !Number.isFinite(v)) return null;
    somma += v;
  }
  return somma / chiavi.length;
}

/**
 * Lo sbilanciamento grezzo verso un profilo, in punti di attributo. null se
 * mancano dati. `generali` e' il metro interno al giocatore: per i portieri si
 * passano gli attributi da portiere (engine/squadra.js).
 */
export function scartoProfilo(attributi, profilo, generali = ATTRIBUTI_GENERALI) {
  if (!profilo?.length) return null;
  const suo = media(attributi, profilo);
  const generale = media(attributi, generali);
  return suo === null || generale === null ? null : suo - generale;
}

// Dove sta il collega tipico, per ruolo: fra i giocatori veri la cui posizione
// principale e' nella famiglia del ruolo, lo scarto atteso a ogni livello di
// overall (retta: atteso a 75 + pendenza per punto) e la deviazione intorno.
// GENERATA da tools/validazione/taratura-ruoli.mjs su pool-reale.json: se
// cambiano i profili, va rigenerata.
//
// Due confronti, due trappole evitate. Senza il collega tipico un centrale
// sarebbe sempre "piu' marcatore che altro" e il marcatore converrebbe a tutti.
// Senza il livello, fra le punte i finalizzatori sarebbero quasi sempre le piu'
// forti (correlazione 0,52): overall travestito, di nuovo.
export const TARATURA_RUOLI = {
  centrale_marcatore: { atteso: 11.71, pendenza: 0.363, deviazione: 3.93 },
  centrale_impostatore: { atteso: 2.13, pendenza: 0.284, deviazione: 3.51 },
  terzino_offensivo: { atteso: 5.81, pendenza: -0.260, deviazione: 3.84 },
  terzino_interno: { atteso: 1.63, pendenza: 0.164, deviazione: 1.94 },
  terzino_bloccato: { atteso: 1.64, pendenza: -0.071, deviazione: 3.82 },
  regista: { atteso: 4.68, pendenza: 0.244, deviazione: 2.56 },
  mezzala: { atteso: 5.07, pendenza: 0.028, deviazione: 3.65 },
  incursore: { atteso: -1.89, pendenza: -0.004, deviazione: 5.19 },
  schermo: { atteso: -2.15, pendenza: -0.063, deviazione: 9.26 },
  ala_pura: { atteso: 10.65, pendenza: -0.120, deviazione: 4.33 },
  esterno_a_rientrare: { atteso: 8.15, pendenza: 0.096, deviazione: 4.00 },
  esterno_difensivo: { atteso: -14.11, pendenza: -0.305, deviazione: 7.93 },
  finalizzatore: { atteso: 9.72, pendenza: 0.409, deviazione: 2.91 },
  punta_di_manovra: { atteso: 6.79, pendenza: 0.175, deviazione: 3.07 },
};

const OVERALL_RIFERIMENTO = 75;

// A quante deviazioni dal collega tipico si e' l'interprete perfetto (o il
// peggiore). 1,5 lascia il 13% circa dei giocatori oltre i due estremi.
const DEVIAZIONI_PIENE = 1.5;

/** I ruoli che uno slot puo' assumere. */
export function ruoliPerSlot(slot) {
  return Object.entries(RUOLI).filter(([, r]) => r.per.includes(slot)).map(([k]) => k);
}

/** Il ruolo di partenza di uno slot: il primo della sua famiglia. */
export function ruoloNaturale(slot) {
  const l = ruoliPerSlot(slot);
  return l.length ? l[0] : null;
}

// Quanto pesa uno spostamento pieno. Tarati per restare nello stesso ordine di
// grandezza dei compiti: un ruolo sposta quanto un compito, non di piu'.
export const SCALA_DENTRO = 0.13;
export const SCALA_AVANTI = 0.09;

/**
 * Quanto un giocatore sa interpretare il ruolo, da -1 a +1, rispetto al
 * collega tipico. Vale anche fuori posizione: un centrale schierato da schermo
 * e' confrontato con i centrocampisti. 0 se il ruolo e' quello base o se
 * mancano attributi: mai un profilo inventato (registro, punto 8).
 */
export function idoneitaRuolo(g, ruolo) {
  const r = RUOLI[ruolo];
  const t = TARATURA_RUOLI[ruolo];
  if (!r?.profilo) return 0;
  return idoneitaProfilo(g, r.profilo, t);
}

/**
 * Il cuore comune a ruoli e indicazioni di squadra: quanto il giocatore e'
 * sbilanciato verso un profilo rispetto al collega tipico del suo livello
 * (taratura: retta sull'overall + deviazione). Da -1 a +1, 0 se mancano dati.
 */
export function idoneitaProfilo(g, profilo, t, generali = ATTRIBUTI_GENERALI) {
  if (!g || !profilo?.length || !t || typeof g.ovr !== 'number') return 0;
  const s = scartoProfilo(g.attributi, profilo, generali);
  if (s === null) return 0;
  const atteso = t.atteso + t.pendenza * (g.ovr - OVERALL_RIFERIMENTO);
  return Math.max(-1, Math.min(1, (s - atteso) / (t.deviazione * DEVIAZIONI_PIENE)));
}

/** I pesi di corsia dopo il ruolo. */
export function corsiaConRuolo(wc, ruolo, giocatore) {
  const r = RUOLI[ruolo];
  if (!wc || !r || !r.dentro) return wc;
  const resa = 0.25 + 0.75 * ((idoneitaRuolo(giocatore, ruolo) + 1) / 2);
  const k = r.dentro * SCALA_DENTRO;
  if (k > 0) {
    // rientra: lascia la fascia e porta peso al centro, ma solo se sa starci
    return { SX: wc.SX * (1 - k), CEN: wc.CEN + (wc.SX + wc.DX) * k * resa, DX: wc.DX * (1 - k) };
  }
  const a = -k;
  // si allarga: lascia il centro e va sulla sua fascia naturale
  const versoSX = wc.SX >= wc.DX;
  return {
    SX: wc.SX + (versoSX ? wc.CEN * a * resa : 0),
    CEN: wc.CEN * (1 - a),
    DX: wc.DX + (versoSX ? 0 : wc.CEN * a * resa),
  };
}

// Quanto vale interpretare il ruolo, in punti di overall efficace, a idoneita'
// piena: in piu' per l'interprete giusto, in meno per quello sbagliato.
// Era 2,0: i ruoli valevano +6,2 punti su 38 da soli, piu' di tutte le altre
// leve insieme. Ridotto nel riequilibrio del task 4 (registro, punto 36).
export const VALORE_IDONEITA = 1.5;

/**
 * Lo scarto di overall efficace dovuto ai ruoli, nella forma che il motore si
 * aspetta: (giocatore, slot) => punti. Si somma agli altri canali tattici.
 *
 * Vale solo per i titolari, e per posizione: chi entra dal cambio eredita il
 * ruolo dello slot in cui entra, non quello di chi esce — e' la posizione in
 * campo ad avere un ruolo, non la persona.
 */
export function deltaRuoli(lineup) {
  const ruoli = lineup?.ruoli;
  if (!ruoli || !ruoli.some(Boolean)) return null;
  const perSlot = new Map();
  (lineup.titolari || []).forEach((g, i) => { if (g && ruoli[i]) perSlot.set(i, ruoli[i]); });
  if (!perSlot.size) return null;
  // Indice di slot per giocatore: il motore passa (g, slot) e lo slot e' il
  // nome della posizione, che in un modulo puo' ripetersi (due CB, due CM).
  // Si tiene quindi l'associazione per identita' del giocatore.
  const perGiocatore = new Map();
  (lineup.titolari || []).forEach((g, i) => { if (g && ruoli[i]) perGiocatore.set(g, ruoli[i]); });
  return (g) => {
    const r = perGiocatore.get(g);
    if (!r) return 0;
    // Bonus e malus (registro, punto 27): la tattica e' l'identita' della
    // squadra, e il suo valore sta nell'accordo fra metodo e giocatori. Il
    // ruolo base resta neutro, quindi chi non tocca niente sta a zero; che chi
    // sceglie a caso non ci guadagni lo verifica prova-default-non-svantaggiato.
    return idoneitaRuolo(g, r) * VALORE_IDONEITA;
  };
}

/** Somma piu' canali tattici in un solo scarto. */
export function sommaDelta(...fn) {
  const attivi = fn.filter(Boolean);
  if (!attivi.length) return undefined;
  if (attivi.length === 1) return attivi[0];
  return (g, slot) => attivi.reduce((t, f) => t + f(g, slot), 0);
}

/** Lo spostamento di linea che il ruolo aggiunge al compito. */
export function avanzamentoRuolo(ruolo) {
  const r = RUOLI[ruolo];
  return r ? r.avanti * SCALA_AVANTI : 0;
}
