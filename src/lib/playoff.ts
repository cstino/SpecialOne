import type { Bracket, BracketTie } from '../types'

// Nomi dei tabelloni e dei turni per le pagine fuori dal Tabellone (es. Partite).
// Stesse regole di Tabellone.tsx: con le conferenze (formato B) il turno 1 e' il play-in East/West e poi
// quarti, semifinali, finale; nel formato classico il turno si conta da quanti round ha davvero il tabellone.

export const titoloTabellone = (b: Bracket) =>
  b.formato === 'conferenze' ? (b.tipo === 'title' ? 'Title Playoff' : 'Draft Playoffs') : (b.tipo === 'title' ? 'Title Playoff' : 'Draft Playoff')

export function nomeTurnoTabellone(b: Bracket, turno: number, tiesDelTabellone: BracketTie[]): string {
  const turniTotali = b.formato === 'conferenze'
    ? 4
    : (() => { const primo = tiesDelTabellone.filter((t) => t.turno === 1).length; return primo > 0 ? Math.ceil(Math.log2(primo * 2)) : 0 })()
  if (b.formato === 'conferenze' && turno === 1) return 'Play-in'
  const mancanti = turniTotali - turno
  if (mancanti === 0) return 'Finale'
  if (mancanti === 1) return 'Semifinali'
  if (mancanti === 2) return 'Quarti'
  return `Turno ${turno}`
}
