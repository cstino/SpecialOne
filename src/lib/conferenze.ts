export type Conferenza = 'est' | 'ovest'

// Il sorteggio estrae una squadra ogni PASSO secondi; la squadra esce allo scoccare del turno e il
// caricamento dura solo gli ultimi SECONDI_ROULETTE. Il primo turno non ha un'estratta prima:
// l'«avvio» che si vede (conto alla rovescia, menu) e' quando comincia il suo caricamento,
// cioe' ANTICIPO secondi dopo l'avviato_il del database. Cosi' anche la prima squadra aspetta 6 secondi, non 20.
export const PASSO_SORTEGGIO = 20
export const SECONDI_ROULETTE = 6
export const ANTICIPO_PRIMA_ESTRAZIONE = PASSO_SORTEGGIO - SECONDI_ROULETTE

export const NOME_CONFERENZA: Record<Conferenza, string> = { est: 'Eastern Conference', ovest: 'Western Conference' }
// Per gli spazi stretti (tab della classifica, colonne del sorteggio): il logo dice gia' «Conference».
export const NOME_CONFERENZA_BREVE: Record<Conferenza, string> = { est: 'Eastern', ovest: 'Western' }
export const SIGLA_CONFERENZA: Record<Conferenza, string> = { est: 'EAST', ovest: 'WEST' }
// Loghi veri (5 ottobre 2026): completo con scritta per gli spazi grandi, solo emblema per quelli stretti.
export const LOGO_CONFERENZA: Record<Conferenza, string> = { est: '/loghi-conferenza/east.svg', ovest: '/loghi-conferenza/west.svg' }
export const LOGO_CONFERENZA_EMBLEMA: Record<Conferenza, string> = { est: '/loghi-conferenza/east-emblema.svg', ovest: '/loghi-conferenza/west-emblema.svg' }
