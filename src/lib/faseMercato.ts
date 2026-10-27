import { useEffect, useState } from 'react'
import { supabase } from './supabase'

// In che fase e' il mercato (27/10/2026, public.stato_mercato): svincolati e under chiusi dall'inizio dei playoff fino
// alla nuova stagione; scambi chiusi durante i playoff e a stagione finita, riaperti con l'off-season. La regola vera la
// applica il database; qui serve solo a non mostrare "Mercato aperto" quando non lo e'.
export type FaseMercato = { fase: 'stagione' | 'playoff' | 'fine_stagione' | 'offseason'; giocatoriChiuso: boolean; scambiChiuso: boolean }

export function useFaseMercato(leagueId: number): FaseMercato | null {
  const [stato, setStato] = useState<FaseMercato | null>(null)
  useEffect(() => {
    let vivo = true
    void supabase.rpc('stato_mercato', { p_league_id: leagueId }).then(({ data }) => {
      if (!vivo || !data) return
      const d = data as { fase: FaseMercato['fase']; giocatori_chiuso_per_fase: boolean; scambi_chiuso_per_fase: boolean }
      setStato({ fase: d.fase, giocatoriChiuso: d.giocatori_chiuso_per_fase, scambiChiuso: d.scambi_chiuso_per_fase })
    })
    return () => { vivo = false }
  }, [leagueId])
  return stato
}

export const ETICHETTA_GIOCATORI_CHIUSO = 'Mercato chiuso · riapre con la nuova stagione'
export const ETICHETTA_SCAMBI_CHIUSO = 'Mercato scambi chiuso · riapre con l\'off-season'
