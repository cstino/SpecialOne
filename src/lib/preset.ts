// Preset tattici: combinazioni pronte delle due pagine dello Schema Tattico
// (registro, punto 39). Per chi non vuole spendere tempo a personalizzare,
// come i Tactical Preset di EA FC: un tocco e la squadra prende un'identita'
// coerente, poi si puo' ritoccare tutto.
//
// File SOLO di dati e logica pura, senza import: lo usano sia l'app sia
// tools/validazione (Node lo legge cosi' com'e'), cosi' i numeri misurati sono
// quelli dell'app e non una copia.
//
// Regola di sicurezza (punto 26: chi non studia non deve essere punito): i
// RUOLI si assegnano solo se il giocatore che occupa il posto e' adatto
// (idoneita' > 0); altrimenti il posto resta senza indicazione. Cosi' un preset
// non puo' mai mettere un giocatore in un ruolo che non sa fare. Il portiere
// libero non e' mai incluso: conviene solo con un portiere adatto (punto 37) e
// va scelto a mano.

export type PresetCompito = 'difesa' | 'equilibrio' | 'attacco'

export type Preset = {
  id: string
  nome: string
  descrizione: string
  // Cosa chiede alla rosa, in una riga.
  chiede: string
  squadra: { stile: string; linea: string | null; ampiezza: string | null }
  // Per ogni posizione, i ruoli in ordine di preferenza: vince il primo per cui
  // il giocatore e' adatto.
  ruoli: Partial<Record<string, string[]>>
  // Compito fisso per posizione (le altre restano senza compito).
  compiti: Partial<Record<string, PresetCompito>>
}

const TERZINI = ['LB', 'RB', 'LWB', 'RWB']
const CENTRO = ['CDM', 'CM', 'CAM']
const ESTERNI = ['LM', 'RM', 'LW', 'RW']
const PUNTE = ['ST', 'CF']

function per(slots: string[], valore: string[]): Record<string, string[]> {
  return Object.fromEntries(slots.map((s) => [s, valore]))
}
function compitoPer(slots: string[], c: PresetCompito): Record<string, PresetCompito> {
  return Object.fromEntries(slots.map((s) => [s, c]))
}

export const PRESET: Preset[] = [
  {
    id: 'palleggio',
    nome: 'Palleggio',
    descrizione: 'Si tiene la palla e si costruisce da dietro, con la linea alta per restare vicini.',
    chiede: 'Centrocampisti tecnici e difensori che sanno impostare.',
    squadra: { stile: 'possesso_palla', linea: 'alta', ampiezza: 'stretta' },
    ruoli: {
      CB: ['centrale_impostatore'],
      ...per(TERZINI, ['terzino_interno']),
      ...per(CENTRO, ['regista', 'mezzala']),
      ...per(ESTERNI, ['esterno_a_rientrare']),
      ...per(PUNTE, ['punta_di_manovra']),
    },
    compiti: {},
  },
  {
    id: 'pressing',
    nome: 'Pressing alto',
    descrizione: 'Si riconquista la palla in avanti: linea alta e attaccanti che pressano.',
    chiede: 'Giocatori con fiato, aggressivi e bravi negli intercetti.',
    squadra: { stile: 'recupero_veloce', linea: 'alta', ampiezza: null },
    ruoli: {
      CB: ['centrale_marcatore'],
      ...per(CENTRO, ['mezzala', 'incursore']),
      ...per(PUNTE, ['punta_di_manovra']),
    },
    compiti: compitoPer(PUNTE, 'difesa'),
  },
  {
    id: 'contropiede',
    nome: 'Contropiede',
    descrizione: 'Si lascia palla e si riparte veloci: linea bassa, squadra stretta, punta pronta al lancio.',
    chiede: 'Attaccanti veloci e difensori solidi.',
    squadra: { stile: 'contropiede', linea: 'bassa', ampiezza: 'stretta' },
    ruoli: {
      CB: ['centrale_marcatore'],
      ...per(TERZINI, ['terzino_bloccato']),
      ...per(CENTRO, ['schermo']),
      ...per(PUNTE, ['finalizzatore']),
    },
    compiti: {},
  },
  {
    id: 'catenaccio',
    nome: 'Catenaccio',
    descrizione: 'Prima non prenderle: linea bassa, squadra stretta, marcature e schermi davanti alla difesa.',
    chiede: 'Difensori forti nelle marcature.',
    squadra: { stile: 'blocco_basso', linea: 'bassa', ampiezza: 'stretta' },
    ruoli: {
      CB: ['centrale_marcatore'],
      ...per(TERZINI, ['terzino_bloccato']),
      ...per(CENTRO, ['schermo']),
      ...per(ESTERNI, ['esterno_difensivo']),
    },
    compiti: {},
  },
  {
    id: 'fasce',
    nome: 'Gioco sulle fasce',
    descrizione: 'Si attacca largo: terzini che spingono e stile sulle fasce.',
    chiede: 'Terzini ed esterni che corrono e crossano.',
    squadra: { stile: 'fasce', linea: null, ampiezza: null },
    ruoli: {
      ...per(TERZINI, ['terzino_offensivo']),
    },
    compiti: {},
  },
  {
    id: 'verticale',
    nome: 'Verticale',
    descrizione: 'Si salta il centrocampo e si cerca subito la punta: gioco diretto, punte che fanno da sponda.',
    chiede: 'Punte forti di testa e fisicamente.',
    squadra: { stile: 'diretto', linea: null, ampiezza: null },
    ruoli: {
      ...per(PUNTE, ['finalizzatore', 'punta_di_manovra']),
      ...per(CENTRO, ['incursore']),
    },
    compiti: {},
  },
]

export type RisultatoPreset = {
  stile: string
  linea: string | null
  ampiezza: string | null
  portiere: null
  ruoli: (string | null)[]
  compiti: (string | null)[]
  // Quanti posti hanno un ruolo assegnato (gli altri restano senza indicazione).
  ruoliAssegnati: number
}

/**
 * Applica un preset a una formazione: `slots` sono le posizioni in ordine,
 * `idoneita(i, ruolo)` dice quanto il giocatore del posto i e' adatto a quel
 * ruolo (da -1 a 1; 0 se non lo si sa). Solo i ruoli con idoneita' > 0 vengono
 * assegnati, vedi la regola in testa al file.
 */
export function applicaPreset(preset: Preset, slots: string[], idoneita: (indice: number, ruolo: string) => number): RisultatoPreset {
  let ruoliAssegnati = 0
  const ruoli = slots.map((slot, i) => {
    for (const ruolo of preset.ruoli[slot] ?? []) {
      if (idoneita(i, ruolo) > 0) { ruoliAssegnati++; return ruolo }
    }
    return null
  })
  const compiti = slots.map((slot) => (slot === 'GK' ? null : preset.compiti[slot] ?? null))
  return { ...preset.squadra, portiere: null, ruoli, compiti, ruoliAssegnati }
}
