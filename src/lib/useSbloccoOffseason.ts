import { useEffect, useState } from 'react'
import { supabase } from './supabase'
import type { League } from '../types'

// L'off-season si apre 24 ore dopo l'ultima partita simulata, cosi' tutti
// hanno il tempo di guardare i risultati (finale compresa). L'orario lo
// calcola il database (public.sblocco_offseason), che fa rispettare la stessa
// regola anche a prepara_offseason.
export function useSbloccoOffseason(league: League) {
  const inAttesa = league.stato === 'conclusa' && league.fase_carriera === 'normale'
  const [sbloccoMs, setSbloccoMs] = useState<number | null | undefined>(undefined)
  const [adesso, setAdesso] = useState(Date.now())

  useEffect(() => {
    if (!inAttesa) return
    let vivo = true
    void supabase.rpc('sblocco_offseason', { p_league_id: league.id }).then(({ data, error }) => {
      if (!vivo) return
      setSbloccoMs(error || !data ? null : new Date(data as string).getTime())
    })
    return () => { vivo = false }
  }, [inAttesa, league.id])

  useEffect(() => {
    if (!sbloccoMs || sbloccoMs <= Date.now()) return
    const timer = window.setTimeout(() => setAdesso(Date.now()), Math.min(sbloccoMs - Date.now() + 500, 2_000_000_000))
    return () => window.clearTimeout(timer)
  }, [sbloccoMs, adesso])

  if (!inAttesa) return { aperto: true, apertoIl: null as Date | null }
  // Finche' la risposta non arriva si considera chiuso, per non far lampeggiare
  // l'off-season; se la chiamata fallisce si apre (il controllo vero e' nel database).
  if (sbloccoMs === undefined) return { aperto: false, apertoIl: null as Date | null }
  if (sbloccoMs === null) return { aperto: true, apertoIl: null as Date | null }
  return { aperto: adesso >= sbloccoMs, apertoIl: new Date(sbloccoMs) }
}
