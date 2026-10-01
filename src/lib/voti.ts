// ============================================================
//  VOTI IN PAGELLA — le fasce di colore, stile SofaScore
//
//  I voti li calcola engine/pagelle.js nella Edge Function e stanno nella
//  tabella pagelle. Qui solo come si leggono: blu dall'8, verde dal 7,
//  verde chiaro dal 6,5, arancio dal 6, rosso sotto.
// ============================================================

export type FasciaVoto = 'top' | 'ottimo' | 'buono' | 'sufficiente' | 'insufficiente'

export function fasciaVoto(voto: number): FasciaVoto {
  if (voto >= 8) return 'top'
  if (voto >= 7) return 'ottimo'
  if (voto >= 6.5) return 'buono'
  if (voto >= 6) return 'sufficiente'
  return 'insufficiente'
}

export const formatoVoto = (voto: number) => voto.toFixed(1).replace('.', ',')
