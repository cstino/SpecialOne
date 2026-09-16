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
  // 9 settembre 2026: da 0.252 a 0.1865, insieme al dimezzamento degli STILI
  // qui sotto. Non e' un ritocco "per realismo": la taratura originale era
  // stata fatta con il malus di familiarita' al massimo (-3.5 su ATT e MID)
  // sempre attivo, perche' le rose di tools/validazione nascono con
  // esperienzaModulo vuoto e non lo accumulano mai. Una squadra vera esce da
  // quello stato dopo 5 partite: in Serie F il malus medio della lega era
  // -0.31 su 3.5. A regime il motore produceva 4.08 gol a partita contro un
  // target di 2.50-2.90, ed era anche piu' spietato sul divario di forza di
  // quanto validato (a +4 di overall il piu' forte vinceva il 70% invece del
  // 63%). Con questo valore torna a 2.81 gol e la curva di competitivita' si
  // risovrappone a quella della Fase 0. Dettagli e misure in
  // docs/risultati-produzione.txt.
  XG_BASE_BLOCCO: 0.1299,
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
  CONVERSIONE_SIGMA: 0.011,  // 11 settembre 2026: era 0.015, vedi XG_RIFERIMENTO_TIRI
  // La qualita' media del tiro non e' costante: una squadra che domina crea
  // occasioni migliori, non solo piu' numerose, quindi converte di piu' per
  // ogni tiro. Prima di questa correzione i tiri erano proporzionali all'xG, e
  // nelle partite sbilanciate la squadra forte arrivava a 40-60 tiri: un numero
  // che nel calcio vero non esiste (il record e' intorno a 35). I due valori
  // qui sotto rendono la relazione tiri/xG concava. Non toccano i gol: le
  // statistiche sono calcolate a fine partita, quando il risultato e' gia' fatto.
  // xG per squadra a cui la conversione vale CONVERSIONE_MEDIA. DEVE seguire
  // l'xG medio reale: quando i piazzati hanno preso la loro quota e la manovra
  // e' scesa, lasciarlo a 1.35 faceva finire ogni squadra sotto il riferimento,
  // e la formula concava le assegnava piu' tiri del dovuto (15.0 invece di 13).
  XG_RIFERIMENTO_TIRI: 1.06,
  // xG di manovra a cui corrisponde una pressione "media", cioe' il numero
  // base di angoli e punizioni. Vedi engine/piazzati.js.
  XG_RIFERIMENTO_PIAZZATI: 0.696,
  ESPONENTE_QUALITA_TIRO: 0.55,   // quanto la conversione sale col dominio (0 = vecchio comportamento lineare)
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

// ============================================================
//  COMPITI — quello che in Football Manager sono le duties
//
//  Ogni titolare ha un compito: difendere, tenere l'equilibrio, o attaccare.
//  Non e' un bonus: SPOSTA il peso di quel giocatore da una linea all'altra.
//  Un terzino che si sovrappone toglie peso alla difesa e lo porta a
//  centrocampo e in attacco — e quel peso alla difesa manca davvero.
//
//  IL COSTO E' AUTOMATICO, ed e' la ragione per cui il modello e' questo e non
//  un elenco di bonus. Mettere tutti in attacco non da' una squadra fortissima
//  davanti: da' una squadra fortissima davanti e scoperta dietro, perche' i
//  pesi sono gli stessi che forzeLinee usa per calcolare DEF, MID e ATT. La
//  distribuzione dei compiti E' la forma della squadra, come in FM.
//
//  LO SPOSTAMENTO E' DI UNA LINEA, non un salto. Un compito d'attacco porta
//  una quota di peso da DEF a MID e da MID ad ATT. Cosi' funziona per ogni
//  ruolo senza casi speciali: un centrale che spinge entra a centrocampo, un
//  terzino arriva sulla trequarti, e una punta — che davanti non ha piu' nulla
//  — non guadagna quasi niente, perche' non c'e' dove avanzare.
// ============================================================
export const COMPITI = ['difesa', 'equilibrio', 'attacco'];

// Quanta parte del peso si sposta. A 0.22 un terzino che si sovrappone perde
// 0.165 di peso difensivo e ne guadagna 0.11 a centrocampo e 0.055 in attacco:
// si sente nella forma della squadra senza stravolgerla.
export const SPOSTAMENTO_COMPITO = 0.22;

// Quanto un giocatore e' adatto al compito che gli si chiede, da -1 a +1.
//
// Non serve un attributo nuovo: bastano quelli che il motore ha gia'. Uno che
// finalizza e salta l'uomo molto piu' di quanto contrasti e' un giocatore
// offensivo, chiunque sia il suo ruolo; il contrario vale per chi difende.
// Lo scarto e' fra le SUE qualita', quindi non premia semplicemente chi e'
// piu' forte.
export function idoneitaCompito(g, compito) {
  if (!g || compito === 'equilibrio' || !compito) return 0;
  const off = ((g.finishing ?? 50) + (g.dribbling ?? 50)) / 2;
  const dif = g.tackle ?? 50;
  const tilt = Math.max(-1, Math.min(1, (off - dif) / 25));
  return compito === 'attacco' ? tilt : -tilt;
}

// IL PESO CHE SE NE VA, SE NE VA SEMPRE. Quello che ARRIVA dipende da quanto
// il giocatore e' adatto.
//
// E' la regola che rende i compiti una decisione invece di un regalo. Un
// terzino lento che si sovrappone abbandona comunque la sua zona — la squadra
// resta scoperta di la' — ma davanti non porta niente, perche' li' non sa
// starci. Chi invece ha il profilo giusto porta tutto.
//
// Senza questa asimmetria mettere tutti all'attacco conveniva sempre: si
// guadagnava davanti quanto si perdeva dietro, e in un modello dove i gol
// contano piu' dei gol subiti il saldo era positivo per chiunque.
export function pesiConCompito(w, compito, giocatore, extra = 0) {
  // extra e' lo spostamento che aggiunge il RUOLO (engine/ruoli.js): un
  // incursore avanza anche a compito equilibrio, uno schermo arretra. Ruolo e
  // compito sono due assi indipendenti che si sommano su questo stesso canale.
  const base = (compito === 'attacco' ? 1 : compito === 'difesa' ? -1 : 0) * SPOSTAMENTO_COMPITO;
  const netto = base + extra;
  if (!w || Math.abs(netto) < 0.001) return w;
  const compitoEff = netto > 0 ? 'attacco' : 'difesa';
  const k = Math.min(0.5, Math.abs(netto));
  const resa = 0.15 + 0.85 * ((idoneitaCompito(giocatore, compitoEff) + 1) / 2);
  if (compitoEff === 'attacco') {
    return {
      DEF: w.DEF * (1 - k),
      MID: w.MID * (1 - k) + w.DEF * k * resa,
      ATT: w.ATT + w.MID * k * resa,
    };
  }
  return {
    DEF: w.DEF + w.MID * k * resa,
    MID: w.MID * (1 - k) + w.ATT * k * resa,
    ATT: w.ATT * (1 - k),
  };
}

// ============================================================
//  CORSIE — la seconda dimensione del campo
//
//  Fino a qui il motore conosceva solo le linee: DEF, MID, ATT. Una squadra
//  era tre numeri in verticale e niente in orizzontale, e questo rendeva
//  impossibile qualunque scontro di posizione: "rientrare dentro" o
//  "allargarsi" non avevano un posto dove andare.
//
//  Con le corsie una fascia forte contro una fascia debole diventa un
//  vantaggio reale, e soprattutto diventa un vantaggio CHE DIPENDE
//  DALL'AVVERSARIO — che e' esattamente cio' che mancava ai compiti (punto 13
//  del registro: leggere l'avversario valeva +0,0).
//
//  Il mio attacco a sinistra incontra la loro difesa a destra: e' cosi' che si
//  guarda una partita vera, ed e' il piu' piccolo pezzo di geometria che serve
//  perche' i ruoli abbiano senso.
// ============================================================
export const CORSIE = ['SX', 'CEN', 'DX'];

export const PESI_CORSIA = {
  GK:  { SX: 0.15, CEN: 0.70, DX: 0.15 },
  CB:  { SX: 0.20, CEN: 0.60, DX: 0.20 },
  LB:  { SX: 0.85, CEN: 0.15, DX: 0.00 },
  RB:  { SX: 0.00, CEN: 0.15, DX: 0.85 },
  LWB: { SX: 0.90, CEN: 0.10, DX: 0.00 },
  RWB: { SX: 0.00, CEN: 0.10, DX: 0.90 },
  CDM: { SX: 0.15, CEN: 0.70, DX: 0.15 },
  CM:  { SX: 0.20, CEN: 0.60, DX: 0.20 },
  CAM: { SX: 0.20, CEN: 0.60, DX: 0.20 },
  LM:  { SX: 0.80, CEN: 0.20, DX: 0.00 },
  RM:  { SX: 0.00, CEN: 0.20, DX: 0.80 },
  LW:  { SX: 0.80, CEN: 0.20, DX: 0.00 },
  RW:  { SX: 0.00, CEN: 0.20, DX: 0.80 },
  ST:  { SX: 0.15, CEN: 0.70, DX: 0.15 },
  CF:  { SX: 0.15, CEN: 0.70, DX: 0.15 },
};

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

// 9 settembre 2026: tutte le ampiezze dimezzate. La redistribuzione e' a
// somma zero in PUNTI di overall, ma non sui GOL: l'xG e' esponenziale nel
// differenziale ATT-DEF, quindi spostare peso sull'attacco ne aggiunge piu'
// di quanti la difesa ne tolga. Misurato a familiarita' piena, l'escursione
// fra l'accoppiamento piu' prolifico e il piu' avaro era di 3.20 gol
// (2.01-5.21): lo stile pesava piu' del divario di forza fra le squadre, e i
// partecipanti sceglievano di conseguenza (53% di stili offensivi in Serie F,
// blocco_basso usato 1 volta su 160). Dimezzate, l'escursione scende a 1.24:
// lo stile resta una leva che si sente, senza essere la piu' importante.
// La matrice completa e' il TEST B di tools/validazione/simulate-reale.js.
export const STILI = {
  equilibrato:     { DEF: 0,     MID: 0,     ATT: 0 },
  contropiede:     { DEF: 1.5,   MID: -1.5,  ATT: 0 },
  possesso_palla:  { DEF: -0.75, MID: 1.5,   ATT: -0.75 },
  fasce:           { DEF: -0.75, MID: -0.5,  ATT: 1.25 },
  recupero_veloce: { DEF: -1.5,  MID: 0.75,  ATT: 0.75 },
  diretto:         { DEF: 0,     MID: -1.5,  ATT: 1.5 },
  blocco_basso:    { DEF: 2.0,   MID: -1.0,  ATT: -1.0 },
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
