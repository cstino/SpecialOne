import type { League } from '../types'

// Contratti pluriennali con opzione +1 (docs/DIARIO-SEASON3.md §12). Regole e prezzi stanno nel database
// (public.offri_rinnovo, private.moltiplicatore_durata); qui solo cosa mostrare.

export type OpzioneContratto = 'squadra' | 'giocatore'

/** Da questa stagione della lega si rinnova per 1-3 stagioni con l'opzione. */
export function pluriennaliAttivi(league: Pick<League, 'stagione_corrente' | 'contratti_pluriennali_dalla'>): boolean {
  return typeof league.contratti_pluriennali_dalla === 'number' && league.stagione_corrente >= league.contratti_pluriennali_dalla
}

export const NOME_OPZIONE: Record<OpzioneContratto, string> = { squadra: 'opzione squadra', giocatore: 'opzione giocatore' }

/** «+1 opzione squadra (stagione 6)»: la stagione in piu' che l'opzione puo' aggiungere. */
export function testoOpzione(opzione: OpzioneContratto, scadenza: number): string {
  return `+1 ${NOME_OPZIONE[opzione]} (stagione ${scadenza + 1})`
}
