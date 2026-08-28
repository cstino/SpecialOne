import { useEffect, useState } from 'react'
import { supabase } from './supabase'

// Le tre fasi della stagione, ciascuna con la propria identità visiva
// (sfondo hero): stagione regolare, poi — solo per chi ci arriva — Title
// Playoff o Draft Playoff (docs/decisioni-draft-picks.md §1).
export type FaseSquadra = 'regular' | 'title' | 'draft'

export const SFONDO_FASE: Record<FaseSquadra, string> = {
  regular: '/sfondi-fase/regular_season.png',
  title: '/sfondi-fase/title_playoffs.png',
  draft: '/sfondi-fase/draft_playoffs.png',
}

// In quale fase si trova una squadra: guarda se partecipa a un tabellone
// ancora in corso per la stagione data. Nessun tabellone attivo (stagione
// regolare, o tabelloni già tutti conclusi) ricade su 'regular'.
export function useFaseSquadra(leagueId: number, teamId: number, seasonId: number | null | undefined): FaseSquadra {
  const [fase, setFase] = useState<FaseSquadra>('regular')

  useEffect(() => {
    let vivo = true
    if (!seasonId) { setFase('regular'); return }

    async function carica() {
      const { data: brackets } = await supabase.from('brackets')
        .select('id, tipo').eq('league_id', leagueId).eq('season_id', seasonId).neq('stato', 'concluso')
      if (!vivo) return
      if (!brackets || brackets.length === 0) { setFase('regular'); return }

      const { data: ties } = await supabase.from('bracket_ties')
        .select('bracket_id')
        .in('bracket_id', brackets.map((b) => b.id))
        .or(`alta_team_id.eq.${teamId},bassa_team_id.eq.${teamId}`)
      if (!vivo) return

      const idsPropri = new Set((ties ?? []).map((t) => t.bracket_id))
      const proprio = brackets.find((b) => idsPropri.has(b.id))
      setFase(proprio ? (proprio.tipo as FaseSquadra) : 'regular')
    }
    void carica()
    return () => { vivo = false }
  }, [leagueId, teamId, seasonId])

  return fase
}
