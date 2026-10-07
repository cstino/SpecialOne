import { supabase } from './supabase'
import { urlFotoGiocatore } from './fotoGiocatore'
import type { Team } from '../types'
import { firmaStemma } from './stemmiFirmati'

export type Premio = {
  stagioneId: number
  fase: 'regular' | 'title'
  premio: 'marcatore' | 'assistman' | 'portiere'
  nome: string
  foto?: string
  squadra: Team | null
  stemmaFirmato?: string
  valore: number
}

export const PREMI: Array<{ chiave: Premio['premio']; titolo: string; unita: [string, string] }> = [
  { chiave: 'marcatore', titolo: 'Miglior marcatore', unita: ['gol', 'gol'] },
  { chiave: 'assistman', titolo: 'Miglior assistman', unita: ['assist', 'assist'] },
  { chiave: 'portiere', titolo: 'Miglior portiere', unita: ['porta inviolata', 'porte inviolate'] },
]

export async function firmaStemmi(squadre: Team[]) {
  const firmati = await Promise.all(squadre
    .filter((squadra) => squadra.stemma_url && !squadra.stemma_url.startsWith('preset:'))
    .map(async (squadra) => {
      const { data } = await firmaStemma(squadra.stemma_url!)
      return [squadra.id, data?.signedUrl] as const
    }))
  return new Map(firmati.filter((voce): voce is readonly [number, string] => Boolean(voce[1])))
}

// Premi individuali di tutte le stagioni concluse della lega (funzione SQL che
// aggrega), con squadra e stemma di chi li ha vinti. Un errore non lancia: i
// premi sono un di piu' e non devono nascondere il resto.
export async function caricaPremi(leagueId: number): Promise<Premio[]> {
  const { data } = await supabase.rpc('premi_individuali_lega', { p_league_id: leagueId })
  const grezzi = (data ?? []) as Array<{ season_id: number; fase: Premio['fase']; premio: Premio['premio']; nome: string; foto_url: string | null; team_id: number; valore: number }>
  const idsSquadre = [...new Set(grezzi.map((riga) => riga.team_id))]
  const { data: squadre } = idsSquadre.length
    ? await supabase.from('teams').select('*').in('id', idsSquadre)
    : { data: [] }
  const elenco = (squadre ?? []) as Team[]
  const perId = new Map(elenco.map((squadra) => [squadra.id, squadra]))
  const stemmi = await firmaStemmi(elenco)
  return grezzi.map((riga) => ({
    stagioneId: riga.season_id, fase: riga.fase, premio: riga.premio, nome: riga.nome, valore: riga.valore,
    foto: urlFotoGiocatore(riga.foto_url),
    squadra: perId.get(riga.team_id) ?? null,
    stemmaFirmato: stemmi.get(riga.team_id),
  }))
}
