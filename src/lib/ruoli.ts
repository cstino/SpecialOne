export type MacroRuolo = 'ALL' | 'GK' | 'DEF' | 'MID' | 'ATT'

export function macroRuolo(posizioni: string[] = []): MacroRuolo {
  if (posizioni.includes('GK')) return 'GK'
  if (posizioni.some((r) => ['CB', 'LB', 'RB', 'LWB', 'RWB'].includes(r))) return 'DEF'
  if (posizioni.some((r) => ['CDM', 'CM', 'CAM', 'LM', 'RM'].includes(r))) return 'MID'
  if (posizioni.some((r) => ['ST', 'CF', 'LW', 'RW'].includes(r))) return 'ATT'
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
