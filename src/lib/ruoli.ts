export type MacroRuolo = 'ALL' | 'GK' | 'DEF' | 'MID' | 'ATT'

// La prima voce di "posizioni" e' sempre la posizione primaria di EA (FC 26):
// l'ordine viene preservato cosi' com'e' fin dall'importazione, mai riordinato.
// Guardare solo quella (invece di controllare se una qualsiasi delle posizioni
// ricade in un reparto) evita di classificare come difensore un centrocampista
// che sa anche giocare terzino. Stessa logica di private.macro_ruolo lato DB.
export function macroRuolo(posizioni: string[] = []): MacroRuolo {
  const primaria = posizioni[0]
  if (primaria === 'GK') return 'GK'
  if (['CB', 'LB', 'RB', 'LWB', 'RWB'].includes(primaria)) return 'DEF'
  if (['CDM', 'CM', 'CAM', 'LM', 'RM'].includes(primaria)) return 'MID'
  if (['ST', 'CF', 'LW', 'RW'].includes(primaria)) return 'ATT'
  return 'MID'
}

export const MACRO_LABEL: Record<MacroRuolo, string> = {
  ALL: 'Tutti',
  GK: 'Portieri',
  DEF: 'Difensori',
  MID: 'Centrocampisti',
  ATT: 'Attaccanti',
}

export const ORDINE_MACRO_RUOLO: MacroRuolo[] = ['GK', 'DEF', 'MID', 'ATT']

// Stessi colori di .role-pill--gk/def/mid/att in styles.css: un solo posto
// da cui prenderli quando serve il colore del reparto fuori da quella classe
// (es. il tab attivo del selettore ruolo nel mercato svincolati).
export const MACRO_COLORE: Record<MacroRuolo, string> = {
  ALL: '#c58cff',
  GK: '#ffa33f',
  DEF: '#55c7ee',
  MID: '#5be08c',
  ATT: '#ff5972',
}

// Ordine di reparto fine, GK -> ST, per liste che vogliono seguire la
// progressione classica del campo invece dei soli 4 macro-reparti (es. il
// tabellino partita). Le posizioni non elencate finiscono in coda.
const ORDINE_RUOLO_FINE = [
  'GK',
  'CB', 'LB', 'RB', 'LWB', 'RWB',
  'CDM', 'CM', 'LM', 'RM', 'CAM',
  'LW', 'RW', 'CF', 'ST',
]

export function ordineRuolo(posizioni: string[] = []): number {
  const indice = ORDINE_RUOLO_FINE.indexOf(posizioni[0])
  return indice === -1 ? ORDINE_RUOLO_FINE.length : indice
}
