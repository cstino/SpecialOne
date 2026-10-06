export type Conferenza = 'est' | 'ovest'

export const NOME_CONFERENZA: Record<Conferenza, string> = { est: 'Eastern Conference', ovest: 'Western Conference' }
// Per gli spazi stretti (tab della classifica, colonne del sorteggio): il logo dice gia' «Conference».
export const NOME_CONFERENZA_BREVE: Record<Conferenza, string> = { est: 'Eastern', ovest: 'Western' }
export const SIGLA_CONFERENZA: Record<Conferenza, string> = { est: 'EAST', ovest: 'WEST' }
// Loghi veri (5 ottobre 2026): completo con scritta per gli spazi grandi, solo emblema per quelli stretti.
export const LOGO_CONFERENZA: Record<Conferenza, string> = { est: '/loghi-conferenza/east.svg', ovest: '/loghi-conferenza/west.svg' }
export const LOGO_CONFERENZA_EMBLEMA: Record<Conferenza, string> = { est: '/loghi-conferenza/east-emblema.svg', ovest: '/loghi-conferenza/west-emblema.svg' }
