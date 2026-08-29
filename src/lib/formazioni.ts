// Moduli e disposizione a righe sul campo: unico posto per non far divergere
// Formazione.tsx (schieramento) e MatchIntro.tsx (presentazione partita).
// L'ordine degli slot in ogni modulo e' significativo: coincide con l'ordine
// di engine/config.js, lo stesso a cui punta lineups.titolari[i]. Andare in
// ordine di array equivale quindi ad andare dal portiere agli attaccanti.

export const MODULI: Record<string, string[]> = {
  '4-3-3': ['GK', 'LB', 'CB', 'CB', 'RB', 'CM', 'CM', 'CM', 'LW', 'ST', 'RW'],
  '4-3-3 offensivo': ['GK', 'LB', 'CB', 'CB', 'RB', 'CM', 'CM', 'CAM', 'LW', 'ST', 'RW'],
  '4-3-3 difensivo': ['GK', 'LB', 'CB', 'CB', 'RB', 'CM', 'CM', 'CDM', 'LW', 'ST', 'RW'],
  '4-4-2': ['GK', 'LB', 'CB', 'CB', 'RB', 'LM', 'CM', 'CM', 'RM', 'ST', 'ST'],
  '4-2-3-1': ['GK', 'LB', 'CB', 'CB', 'RB', 'CDM', 'CDM', 'CAM', 'LW', 'RW', 'ST'],
  '3-5-2': ['GK', 'CB', 'CB', 'CB', 'LWB', 'CM', 'CM', 'CM', 'RWB', 'ST', 'ST'],
  '3-4-3': ['GK', 'CB', 'CB', 'CB', 'LM', 'CM', 'CM', 'RM', 'LW', 'ST', 'RW'],
  '5-3-2': ['GK', 'LB', 'CB', 'CB', 'CB', 'RB', 'CM', 'CM', 'CM', 'ST', 'ST'],
  '4-2-4': ['GK', 'LB', 'CB', 'CB', 'RB', 'CM', 'CM', 'LW', 'ST', 'ST', 'RW'],
}

export function reparto(slot: string): 'GK' | 'DEF' | 'MID' | 'ATT' {
  if (slot === 'GK') return 'GK'
  if (['CB', 'LB', 'RB', 'LWB', 'RWB'].includes(slot)) return 'DEF'
  if (['CDM', 'CM', 'CAM', 'LM', 'RM'].includes(slot)) return 'MID'
  return 'ATT'
}

// Disposizione a righe pensata a mano per modulo: il raggruppamento generico
// per reparto (GK/DEF/MID/ATT) da solo non basta, perche' alcuni moduli hanno
// piu' righe nello stesso reparto (es. 4-2-3-1: mediani e trequartisti sono
// entrambi centrocampo, ma sul campo sono due linee separate).
const RIGHE_PER_MODULO: Record<string, string[][]> = {
  '4-2-3-1': [['GK'], ['LB', 'CB', 'RB'], ['CDM'], ['LW', 'CAM', 'RW'], ['ST']],
  '4-3-3': [['GK'], ['LB', 'CB', 'RB'], ['CM'], ['LW', 'ST', 'RW']],
  '4-4-2': [['GK'], ['LB', 'CB', 'RB'], ['LM', 'CM', 'RM'], ['ST']],
  '3-4-3': [['GK'], ['CB'], ['LM', 'CM', 'RM'], ['LW', 'ST', 'RW']],
  '3-5-2': [['GK'], ['CB'], ['LWB', 'CM', 'RWB'], ['ST']],
  '5-3-2': [['GK'], ['LB', 'CB', 'RB'], ['CM'], ['ST']],
  // Senza questo caso il modulo cadeva nel gruppo generico ['LW','RW','ST','CF'],
  // che ordina RW prima di entrambi gli ST: sul campo comparivano scambiati,
  // con l'ala destra stretta al centro invece che larga sulla fascia.
  '4-2-4': [['GK'], ['LB', 'CB', 'RB'], ['CM'], ['LW', 'ST', 'RW']],
  '4-3-3 offensivo': [['GK'], ['LB', 'CB', 'RB'], ['CM', 'CAM', 'CDM'], ['LW', 'ST', 'RW']],
  '4-3-3 difensivo': [['GK'], ['LB', 'CB', 'RB'], ['CM', 'CAM', 'CDM'], ['LW', 'ST', 'RW']],
}
const RIGHE_GENERICHE: string[][] = [['GK'], ['LB', 'CB', 'RB', 'LWB', 'RWB'], ['CDM', 'CM', 'CAM', 'LM', 'RM'], ['LW', 'RW', 'ST', 'CF']]

export type SlotFormazione<T> = { slot: string; index: number; valore: T | undefined }

// Combina modulo + titolari (o qualunque array parallelo agli slot, es. i
// player_instance_id) nelle righe da disegnare sul campo, dal portiere agli
// attaccanti. Un array vuoto per riga se il modulo non e' mappato: meglio un
// campo incompleto che un errore a runtime su un modulo storico non piu' in uso.
export function righeFormazione<T>(modulo: string, valori: readonly T[]): SlotFormazione<T>[][] {
  const slots = MODULI[modulo]
  if (!slots) return []
  const gruppi = RIGHE_PER_MODULO[modulo] ?? RIGHE_GENERICHE
  return gruppi.map((gruppo) => slots
    .map((slot, index) => ({ slot, index, valore: valori[index] }))
    .filter((item) => gruppo.includes(item.slot))
    .sort((sinistra, destra) => gruppo.indexOf(sinistra.slot) - gruppo.indexOf(destra.slot)))
}
