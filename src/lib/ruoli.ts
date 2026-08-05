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
