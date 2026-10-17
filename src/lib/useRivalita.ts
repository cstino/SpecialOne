import { useEffect, useState } from 'react'
import { supabase } from './supabase'

// Le rivalita' della propria squadra: avversaria -> grado 0-100. Le righe le vede solo chi e' in una delle due
// squadre (RLS), quindi il risultato e' sempre e solo il tuo. Vuoto se la lega non ha le novita' (leagueAttiva false).
export function useRivalitaMie(leagueId: number, teamId: number, attiva: boolean) {
  const [gradi, setGradi] = useState<Map<number, number>>(new Map())
  useEffect(() => {
    if (!attiva) return
    let vivo = true
    void supabase.from('rivalita').select('team_a, team_b, grado').eq('league_id', leagueId).then(({ data }) => {
      if (!vivo) return
      const m = new Map<number, number>()
      for (const r of (data ?? []) as Array<{ team_a: number; team_b: number; grado: number }>) {
        const altra = r.team_a === teamId ? r.team_b : r.team_b === teamId ? r.team_a : null
        if (altra != null) m.set(altra, Number(r.grado))
      }
      setGradi(m)
    })
    return () => { vivo = false }
  }, [leagueId, teamId, attiva])
  return gradi
}

// Da questo grado in su una partita e' un derby.
export const SOGLIA_DERBY = 50
