export type Conferenza = 'est' | 'ovest'

export const NOME_CONFERENZA: Record<Conferenza, string> = { est: 'East Conference', ovest: 'West Conference' }
export const SIGLA_CONFERENZA: Record<Conferenza, string> = { est: 'EAST', ovest: 'WEST' }
// Quando arrivano i loghi veri basta metterli in public/loghi-conferenza/ con questi nomi.
export const LOGO_CONFERENZA: Record<Conferenza, string> = { est: '/loghi-conferenza/east.png', ovest: '/loghi-conferenza/west.png' }
