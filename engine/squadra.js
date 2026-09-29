// ============================================================
//  INDICAZIONI DI SQUADRA — la seconda pagina dello schema
//
//  Registro tattico, punti 27 e 30. La tattica e' l'identita' della squadra:
//  ogni indicazione vale se la rosa e' adatta a quello che chiede. Stessa
//  regola dei ruoli:
//    - l'opzione predefinita (equilibrato, linea media, ampiezza normale,
//      portiere normale) e' NEUTRA: chi non tocca niente sta a zero;
//    - le altre spostano forza fra i reparti A SOMMA ZERO (piu' o meno,
//      sui gol l'xG e' esponenziale: lo dice la misura, non questo file) e
//      aggiungono un bonus o un malus per chi deve eseguirle, secondo il suo
//      profilo rispetto al collega tipico dello stesso livello.
//
//  Il motore resta quello validato: qui si produce solo uno scarto in punti di
//  overall per giocatore, come ruoli e morale (lineup.tattica). Lo stile di
//  gioco continua a spostare le linee nel motore (STILI in config.js); qui si
//  aggiunge solo quanto la rosa e' adatta a giocarlo.
// ============================================================

import { REPARTO } from './config.js';
import { idoneitaProfilo } from './ruoli.js';

const MARCATURA = 'defending_marking_awareness';
const CONTRASTO = 'standing_tackle';
const FORZA = 'power_strength';
const TESTA = 'attacking_heading_accuracy';
const PASS_CORTO = 'short_passing';
const VISIONE = 'mentality_vision';
const CROSS = 'attacking_crossing';
const VELOCITA = 'movement_sprint_speed';
const ACCELERAZIONE = 'movement_acceleration';
const DRIBBLING = 'dribbling';
const CONTROLLO = 'skill_ball_control';
const INTERCETTI = 'mentality_interceptions';
const AGGRESSIVITA = 'mentality_aggression';

// Il metro interno di un portiere sono i suoi attributi da portiere: con quelli
// di movimento ogni portiere sembrerebbe "piu' portiere-libero che altro".
export const ATTRIBUTI_PORTIERE = ['gk_diving', 'gk_handling', 'gk_kicking', 'gk_positioning', 'gk_reflexes', 'goalkeeping_speed'];

// Le famiglie di posizioni a cui un'indicazione chiede qualcosa.
export const FAMIGLIE = {
  DIFESA: ['CB', 'LB', 'RB', 'LWB', 'RWB'],
  CENTRO: ['CDM', 'CM', 'CAM'],
  FASCE: ['LB', 'RB', 'LWB', 'RWB', 'LM', 'RM', 'LW', 'RW'],
  ATTACCO: ['ST', 'CF', 'LW', 'RW'],
  PUNTE: ['ST', 'CF'],
  RECUPERO: ['CDM', 'CM', 'CAM', 'LM', 'RM', 'LW', 'RW', 'ST', 'CF'],
  PORTIERE: ['GK'],
};

// Ogni profilo: gli attributi che chiede e la famiglia su cui si misura il
// collega tipico. La taratura (TARATURA_SQUADRA) e' generata sui giocatori veri
// da tools/validazione/taratura-ruoli.mjs.
export const PROFILI_SQUADRA = {
  difesa_veloce:    { famiglia: 'DIFESA', attributi: [VELOCITA, ACCELERAZIONE] },
  difesa_fisica:    { famiglia: 'DIFESA', attributi: [MARCATURA, FORZA, TESTA, CONTRASTO] },
  fasce_spinta:     { famiglia: 'FASCE', attributi: [CROSS, VELOCITA, DRIBBLING] },
  centro_tecnico:   { famiglia: 'CENTRO', attributi: [PASS_CORTO, CONTROLLO, VISIONE] },
  attacco_veloce:   { famiglia: 'ATTACCO', attributi: [VELOCITA, ACCELERAZIONE] },
  recupero:         { famiglia: 'RECUPERO', attributi: [AGGRESSIVITA, INTERCETTI] },
  punte_fisiche:    { famiglia: 'PUNTE', attributi: [TESTA, FORZA] },
  portiere_libero:  { famiglia: 'PORTIERE', attributi: ['goalkeeping_speed', 'gk_positioning', 'gk_kicking'], generali: ATTRIBUTI_PORTIERE },
};

// GENERATA da tools/validazione/taratura-ruoli.mjs --scrivi.
export const TARATURA_SQUADRA = {
  difesa_veloce: { atteso: 5.47, pendenza: -0.758, deviazione: 8.80 },
  difesa_fisica: { atteso: 5.11, pendenza: 0.416, deviazione: 6.84 },
  fasce_spinta: { atteso: 7.13, pendenza: -0.018, deviazione: 3.93 },
  centro_tecnico: { atteso: 5.61, pendenza: 0.229, deviazione: 2.72 },
  attacco_veloce: { atteso: 10.77, pendenza: -0.602, deviazione: 8.84 },
  recupero: { atteso: -9.43, pendenza: 0.070, deviazione: 11.64 },
  punte_fisiche: { atteso: 9.19, pendenza: 0.099, deviazione: 7.50 },
  portiere_libero: { atteso: -6.16, pendenza: -0.042, deviazione: 1.94 },
};

/** Quanto un giocatore e' adatto a un profilo di squadra, da -1 a +1. */
export function idoneitaSquadra(g, profilo) {
  const p = PROFILI_SQUADRA[profilo];
  if (!p) return 0;
  return idoneitaProfilo(g, p.attributi, TARATURA_SQUADRA[profilo], p.generali);
}

// ------------------------------------------------------------
//  LE OPZIONI
//
//  sposta: punti di overall aggiunti a ogni giocatore di quel reparto (o di
//  quel gruppo di posizioni). Un punto su tutti i centrocampisti alza la linea
//  MID di un punto: forzeLinee() fa una media pesata.
//  chiede: il profilo, la famiglia che deve eseguirlo e quanto vale a idoneita'
//  piena (punti di overall, in piu' o in meno).
//
//  Numeri di partenza, da tarare sul sistema intero (task 4): stessa scala dei
//  ruoli (VALORE_IDONEITA = 2) e degli stili (spostamenti da 0,75 a 2).
// ------------------------------------------------------------
export const OPZIONI_SQUADRA = {
  linea: {
    media: null,
    // Squadra corta: il centrocampo e' piu' vicino e pressa meglio, ma dietro
    // c'e' campo. Regge con difensori veloci.
    alta:  { sposta: { DEF: -1.0, MID: 1.0 }, chiede: { profilo: 'difesa_veloce', valore: 2.0 } },
    // Si difende l'area: dietro si e' piu' solidi, il resto della squadra e'
    // lontano. Regge con difensori forti e bravi a marcare.
    bassa: { sposta: { DEF: 1.0, MID: -0.5, ATT: -0.5 }, chiede: { profilo: 'difesa_fisica', valore: 2.0 } },
  },
  ampiezza: {
    normale: null,
    // Si allarga il campo: le fasce contano di piu', il centro e' piu' solo.
    larga:   { spostaPosizioni: { FASCE: 0.8, CENTRO: -0.8 }, chiede: { profilo: 'fasce_spinta', valore: 2.0 } },
    // Si stringe: superiorita' in mezzo, fasce lasciate agli altri.
    stretta: { spostaPosizioni: { CENTRO: 0.8, FASCE: -0.8 }, chiede: { profilo: 'centro_tecnico', valore: 2.0 } },
  },
  // Lo stile sposta gia' le linee nel motore: qui solo chi e' adatto a giocarlo.
  stile: {
    equilibrato: null,
    contropiede:     { chiede: { profilo: 'attacco_veloce', valore: 2.0 } },
    possesso_palla:  { chiede: { profilo: 'centro_tecnico', valore: 2.0 } },
    fasce:           { chiede: { profilo: 'fasce_spinta', valore: 2.0 } },
    recupero_veloce: { chiede: { profilo: 'recupero', valore: 2.0 } },
    diretto:         { chiede: { profilo: 'punte_fisiche', valore: 2.0 } },
    blocco_basso:    { chiede: { profilo: 'difesa_fisica', valore: 2.0 } },
  },
  portiere: {
    normale: null,
    // Esce dai pali e gioca coi piedi. Da solo vale poco; con la linea alta
    // copre la profondita' dietro i difensori (COPERTURA_LIBERO).
    libero: { chiede: { profilo: 'portiere_libero', valore: 1.5 } },
  },
};

// Con la linea alta un portiere-libero copre lo spazio alle spalle: i
// difensori ricevono questo, per quanto lui sia adatto (anche in meno).
export const COPERTURA_LIBERO = 1.0;

export const PREDEFINITE = { stile: 'equilibrato', linea: 'media', ampiezza: 'normale', portiere: 'normale' };

const gruppiDi = (slot) => Object.entries(FAMIGLIE).filter(([, l]) => l.includes(slot)).map(([k]) => k);

/**
 * Lo scarto di overall delle indicazioni di squadra: (giocatore, slot) =>
 * punti. null se sono tutte predefinite, cosi' chi non tocca niente non passa
 * nemmeno da qui.
 *
 * indicazioni = { stile, linea, ampiezza, portiere }; valori mancanti o
 * sconosciuti valgono come predefiniti.
 */
export function deltaSquadra(indicazioni) {
  const scelte = [];
  for (const asse of ['linea', 'ampiezza', 'stile', 'portiere']) {
    const o = OPZIONI_SQUADRA[asse][indicazioni?.[asse] ?? PREDEFINITE[asse]];
    if (o) scelte.push(o);
  }
  if (!scelte.length) return null;

  return (g, slot) => {
    if (!g) return 0;
    const reparto = REPARTO[slot];
    const gruppi = gruppiDi(slot);
    let punti = 0;
    for (const o of scelte) {
      if (o.sposta?.[reparto]) punti += o.sposta[reparto];
      for (const gr of gruppi) if (o.spostaPosizioni?.[gr]) punti += o.spostaPosizioni[gr];
      const c = o.chiede;
      if (c && FAMIGLIE[PROFILI_SQUADRA[c.profilo].famiglia].includes(slot)) {
        punti += c.valore * idoneitaSquadra(g, c.profilo);
      }
    }
    return punti;
  };
}

/**
 * La copertura del portiere-libero sui difensori, con la linea alta. Serve il
 * portiere in campo, quindi si calcola sul lineup e non sul singolo.
 */
export function deltaCoperturaLibero(lineup, indicazioni) {
  if (indicazioni?.linea !== 'alta' || indicazioni?.portiere !== 'libero') return null;
  const i = lineup?.slots?.indexOf('GK') ?? -1;
  const gk = i >= 0 ? lineup.titolari?.[i] : null;
  const cop = COPERTURA_LIBERO * idoneitaSquadra(gk, 'portiere_libero');
  if (!cop) return null;
  return (g, slot) => (g && REPARTO[slot] === 'DEF' ? cop : 0);
}
