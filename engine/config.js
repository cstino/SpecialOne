// ============================================================
//  COSTANTI DI BILANCIAMENTO
//  Tutto quello che si tara sta qui. Nessun numero magico altrove.
// ============================================================

export const CFG = {
  // --- Motore ---
  BLOCCHI_PARTITA: 6,
  // 30 minuti di supplementari = 2 blocchi da 15'. Costante NUOVA: si applica
  // solo alle eliminatorie di playoff/playout (design §10.7) quando chi chiama
  // passa opt.supplementariSeParita. Nessuna partita di campionato la usa.
  BLOCCHI_SUPPLEMENTARI: 2,
  XG_BASE_BLOCCO: 0.252,
  // xG = BASE * (ctrl/0.5) * exp(SENSIBILITA_FORZA * (ATT - DEF))
  // forma esponenziale sulla DIFFERENZA di overall, non sul rapporto:
  // 1 punto di overall di vantaggio = +SENS% circa di occasioni. Interpretabile.
  SENSIBILITA_FORZA: 0.090, // <-- parametro piu sensibile del sistema
  DIFF_CLAMP: 10,          // tetto al divario ATT-DEF: l'esponenziale e' illimitato,
                           // senza questo un mismatch estremo produce 4+ gol a partita
  AMPLIFICA_CONTROLLO: 1.4, // ctrl = 0.5 + AMPL * (MID_A - MID_B)/100
  CTRL_MIN: 0.22,
  CTRL_MAX: 0.78,
  BONUS_CASA_ATT: 2.0,      // in PUNTI di overall, non in %
  BONUS_CASA_MID: 2.0,
  DIVISORE_PORTIERE: 180,

  // --- Tattica ---
  // Il counter non e' piu una matrice: emerge dalla STRUTTURA del modulo.
  // La linea e' una media pesata, quindi 5 difensori non danno piu solidita di 4.
  // K_STRUTTURA converte il monte-pesi del modulo in punti di overall:
  // piu uomini impegnati in un reparto = quel reparto e' piu forte, e gli altri meno.
  K_STRUTTURA: 2.2,
  STRUTT_CLAMP: 3.5,
  COUNTER_BASE_ATT: 3, // attaccanti del modulo di riferimento
  COUNTER_BASE_DIF: 4, // difensori del modulo di riferimento
  FAM_MALUS_MAX: 3.5,       // punti di overall persi al primo utilizzo del modulo
  DAMPING_MARCATORE: 0.45,  // peso residuo di chi ha gia segnato in questa partita
  FAM_PARTITE_PIENA: 5,     // partite con lo stesso modulo/stile per azzerare il malus (deciso con l'utente, 3 settembre 2026: prima 15)

  // --- Statistiche ---
  CONVERSIONE_MEDIA: 0.105,
  CONVERSIONE_SIGMA: 0.015,
  TIRI_PORTA_MEDIA: 0.36,
  TIRI_PORTA_SIGMA: 0.07,
  PASSAGGI_BASE: 480,
  CONTRASTI_BASE: 18,
  DRIBBLING_BASE: 12,

  // --- Condizione ---
  // Modello "da partita" e non "da stagione": si consuma molto in campo e si
  // recupera quasi tutto dopo. Un titolare con stamina 80 finisce i 90 minuti
  // sotto 60, quindi nell'ultimo terzo il cambio conviene per davvero e le
  // sostituzioni avvengono in ogni giornata, non solo a stagione inoltrata.
  CONSUMO_BASE: 10.5,
  CONSUMO_MOD_STAMINA: 4.0, // la stamina ora pesa: 95 consuma il 15% meno di 60
  REC_TRIBUNA: 45,
  REC_PANCHINA: 40,
  REC_GIOCATO: 36,

  // --- Infortuni ---
  INFORTUNIO_BASE: 0.025,
  INFORTUNIO_DIV_COND: 50,

  // --- Cartellini ---
  // Media per squadra per blocco. Con 6 blocchi: ~1,8 gialli e ~0,08 rossi
  // diretti a partita per squadra (~3,6 gialli e ~0,16 rossi diretti in
  // totale, in linea con le medie dei campionati reali). Il doppio giallo
  // (seconda ammonizione nella stessa gara) non ha una propria costante:
  // e' un giallo normale che diventa espulsione perche' il giocatore ne ha
  // gia' uno.
  CARTELLINO_GIALLO_LAMBDA_BLOCCO: 0.30,
  CARTELLINO_ROSSO_DIRETTO_LAMBDA_BLOCCO: 0.009,
  // Chi ha gia' un giallo in questa partita gioca piu' attento: stesso
  // principio di DAMPING_MARCATORE, qui riduce il rischio di un secondo
  // cartellino (giallo o rosso) invece del peso di segnare ancora. Senza
  // questo smorzamento il peso per ruolo si concentra troppo su pochi slot
  // (CB/CDM) e il doppio giallo diventa implausibile: verificato che senza
  // smorzamento un'espulsione capitava nel 33% delle partite, contro il
  // 10-15% reale.
  DAMPING_AMMONITO: 0.18,

  // --- Sostituzioni ---
  FINESTRE_CAMBI: [3, 4, 5], // fine di questi blocchi
  MAX_CAMBI: 5,
  MAX_CAMBI_FINESTRA: 2,
  // Alzata da 55: col consumo nuovo un titolare arriva a ~78 alla prima
  // finestra e ~63 all'ultima. A 55 nessuna finestra si sarebbe mai aperta.
  SOGLIA_CAMBIO_COND: 75,
};

// ============================================================
//  REPARTI E COMPATIBILITA RUOLI
// ============================================================

export const REPARTO = {
  GK: 'GK',
  CB: 'DEF', LB: 'DEF', RB: 'DEF', LWB: 'DEF', RWB: 'DEF',
  CDM: 'MID', CM: 'MID', CAM: 'MID', LM: 'MID', RM: 'MID',
  LW: 'ATT', RW: 'ATT', ST: 'ATT', CF: 'ATT',
};

const ADIACENTI = { DEF: ['MID'], MID: ['DEF', 'ATT'], ATT: ['MID'] };

// Eccezione mirata (decisa con l'utente, 30 agosto 2026): pochissimi
// giocatori del dataset hanno LWB/RWB come posizione elencata, quindi il
// 3-5-2 era quasi ingiocabile a piena efficacia. Un terzino o un esterno di
// centrocampo che gioca da quinto e' una scelta ragionevole nel calcio vero
// quanto una posizione secondaria elencata in scheda: stessa penalita' (0.98),
// non quella di reparto/adiacenza. Non tocca nessun'altra combinazione slot/ruolo.
const QUASI_NATURALI = { LWB: ['LB', 'LM'], RWB: ['RB', 'RM'] };

export function penalitaRuolo(posizioni, slot) {
  const repSlot = REPARTO[slot];
  const repNat = REPARTO[posizioni[0]];

  // portiere fuori ruolo / movimento in porta: gestiti dal chiamante
  if (repSlot === 'GK' || repNat === 'GK') return null;

  if (posizioni[0] === slot) return 1.00;
  if (posizioni.includes(slot)) return 0.98;
  if (QUASI_NATURALI[slot] && QUASI_NATURALI[slot].includes(posizioni[0])) return 0.98;
  if (repNat === repSlot) return 0.91;
  if (ADIACENTI[repNat] && ADIACENTI[repNat].includes(repSlot)) return 0.80;
  return 0.65;
}

// ============================================================
//  PESI SLOT -> LINEE (DEF / MID / ATT)
// ============================================================

export const PESI_SLOT = {
  CB:  { DEF: 1.00, MID: 0.10, ATT: 0.00 },
  LB:  { DEF: 0.75, MID: 0.25, ATT: 0.10 },
  RB:  { DEF: 0.75, MID: 0.25, ATT: 0.10 },
  LWB: { DEF: 0.60, MID: 0.40, ATT: 0.20 },
  RWB: { DEF: 0.60, MID: 0.40, ATT: 0.20 },
  CDM: { DEF: 0.55, MID: 0.75, ATT: 0.05 },
  CM:  { DEF: 0.30, MID: 1.00, ATT: 0.25 },
  CAM: { DEF: 0.10, MID: 0.65, ATT: 0.60 },
  LM:  { DEF: 0.25, MID: 0.75, ATT: 0.35 },
  RM:  { DEF: 0.25, MID: 0.75, ATT: 0.35 },
  LW:  { DEF: 0.05, MID: 0.30, ATT: 0.85 },
  RW:  { DEF: 0.05, MID: 0.30, ATT: 0.85 },
  ST:  { DEF: 0.00, MID: 0.05, ATT: 1.00 },
  CF:  { DEF: 0.00, MID: 0.05, ATT: 1.00 },
};

// ============================================================
//  MODULI
// ============================================================

export const MODULI = {
  '4-3-3':            ['GK','LB','CB','CB','RB','CM','CM','CM','LW','ST','RW'],
  '4-3-3 offensivo':  ['GK','LB','CB','CB','RB','CM','CM','CAM','LW','ST','RW'],
  '4-3-3 difensivo':  ['GK','LB','CB','CB','RB','CM','CM','CDM','LW','ST','RW'],
  '4-4-2':   ['GK','LB','CB','CB','RB','LM','CM','CM','RM','ST','ST'],
  '4-2-3-1': ['GK','LB','CB','CB','RB','CDM','CDM','CAM','LW','RW','ST'],
  '3-5-2':   ['GK','CB','CB','CB','LWB','CM','CM','CM','RWB','ST','ST'],
  '3-4-3':   ['GK','CB','CB','CB','LM','CM','CM','RM','LW','ST','RW'],
  '5-3-2':   ['GK','LB','CB','CB','CB','RB','CM','CM','CM','ST','ST'],
  '4-2-4':   ['GK','LB','CB','CB','RB','CM','CM','LW','ST','ST','RW'],
};

// conteggi nominali per la formula di counter
export const CONTEGGI = {};
for (const [nome, slots] of Object.entries(MODULI)) {
  const c = { DEF: 0, MID: 0, ATT: 0 };
  for (const s of slots) if (s !== 'GK') c[REPARTO[s]]++;
  // wing-back: nominalmente contano come centrocampisti nel nome del modulo
  if (nome === '3-5-2') { c.DEF = 3; c.MID = 5; c.ATT = 2; }
  if (nome === '5-3-2') { c.DEF = 5; c.MID = 3; c.ATT = 2; }
  CONTEGGI[nome] = c;
}

// ============================================================
//  STILI DI GIOCO
//  Leva tattica indipendente dal modulo: redistribuzione a somma zero tra
//  DEF/MID/ATT, in punti di overall, stessa unita' del profilo strutturale
//  e del bonus casa. Nessuno stile e' un buff netto, solo uno spostamento
//  di enfasi. Chiavi tenute in sync a mano con private.stili_validi() lato
//  DB e con STILE_LABEL/STILE_DESCRIZIONI nel frontend (design.md §6.8) —
//  stesso pattern gia' in uso per MODULI/moduli_validi().
// ============================================================

export const STILI = {
  equilibrato:     { DEF: 0,    MID: 0,    ATT: 0 },
  contropiede:     { DEF: 3.0,  MID: -3.0, ATT: 0 },
  possesso_palla:  { DEF: -1.5, MID: 3.0,  ATT: -1.5 },
  fasce:           { DEF: -1.5, MID: -1.0, ATT: 2.5 },
  recupero_veloce: { DEF: -3.0, MID: 1.5,  ATT: 1.5 },
  diretto:         { DEF: 0,    MID: -3.0, ATT: 3.0 },
  blocco_basso:    { DEF: 4.0,  MID: -2.0, ATT: -2.0 },
};

// ============================================================
//  PESI STATISTICHE PER RUOLO
// ============================================================

export const PESI_STAT = {
  tiri:      { ATT: 3.0, CAM: 1.8, LW: 2.2, RW: 2.2, LM: 1.0, RM: 1.0, CM: 0.8, CDM: 0.4, DEF: 0.25, GK: 0 },
  passaggi:  { CM: 1.6, CDM: 1.5, CAM: 1.4, CB: 1.3, LB: 1.2, RB: 1.2, LWB: 1.2, RWB: 1.2, LM: 1.1, RM: 1.1, LW: 0.7, RW: 0.7, ATT: 0.6, GK: 0.35 },
  contrasti: { CB: 1.7, CDM: 1.6, LB: 1.4, RB: 1.4, LWB: 1.4, RWB: 1.4, CM: 1.1, LM: 0.9, RM: 0.9, CAM: 0.6, LW: 0.5, RW: 0.5, ATT: 0.4, GK: 0 },
  dribbling: { LW: 2.0, RW: 2.0, CAM: 1.6, ATT: 1.2, LM: 1.3, RM: 1.3, CM: 0.7, LWB: 0.6, RWB: 0.6, CDM: 0.35, DEF: 0.15, GK: 0 },
};

export function pesoStat(tipo, slot) {
  const t = PESI_STAT[tipo];
  if (t[slot] !== undefined) return t[slot];
  const rep = REPARTO[slot];
  if (t[rep] !== undefined) return t[rep];
  return 0.5;
}
