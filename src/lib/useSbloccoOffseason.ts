import { useEffect, useState } from 'react'
import { supabase } from './supabase'
import type { League } from '../types'

type Sblocco = { aperto: boolean; apertoIl: Date | null; stagioneInCorso: boolean }

// L'off-season si apre 24 ore dopo l'ultima partita simulata, cosi' tutti
// hanno il tempo di guardare i risultati (finale compresa). L'orario lo
// calcola il database (public.sblocco_offseason), che fa rispettare la stessa
// regola anche a prepara_offseason.
// Lo stato della lega si rilegge qui dal database: quello in memoria puo'
// essere di prima della finale (app aperta da ore) e far sembrare aperta
// una stagione appena conclusa.
export function useSbloccoOffseason(league: League): Sblocco {
  const daControllare = league.fase_carriera === 'normale'
  const [stato, setStato] = useState<{ conclusa: boolean; sbloccoMs: number | null } | undefined>(undefined)
  const [adesso, setAdesso] = useState(Date.now())

  useEffect(() => {
    if (!daControllare) return
    let vivo = true
    async function carica() {
      const { data: lega } = await supabase.from('leagues').select('stato').eq('id', league.id).single()
      if (!vivo) return
      if (lega?.stato !== 'conclusa') { setStato({ conclusa: false, sbloccoMs: null }); return }
      const { data, error } = await supabase.rpc('sblocco_offseason', { p_league_id: league.id })
      if (!vivo) return
      setStato({ conclusa: true, sbloccoMs: error || !data ? null : new Date(data as string).getTime() })
    }
    void carica()
    return () => { vivo = false }
  }, [daControllare, league.id, league.stato])

  const sbloccoMs = stato?.sbloccoMs ?? null
  useEffect(() => {
    if (!sbloccoMs || sbloccoMs <= Date.now()) return
    const timer = window.setTimeout(() => setAdesso(Date.now()), Math.min(sbloccoMs - Date.now() + 500, 2_000_000_000))
    return () => window.clearTimeout(timer)
  }, [sbloccoMs, adesso])

  if (!daControllare) return { aperto: true, apertoIl: null, stagioneInCorso: false }
  // Finche' la risposta non arriva si considera chiuso, per non far lampeggiare
  // l'off-season.
  if (stato === undefined) return { aperto: false, apertoIl: null, stagioneInCorso: false }
  if (!stato.conclusa) return { aperto: false, apertoIl: null, stagioneInCorso: true }
  // Chiamata fallita: si apre, il controllo vero e' nel database.
  if (sbloccoMs === null) return { aperto: true, apertoIl: null, stagioneInCorso: false }
  return { aperto: adesso >= sbloccoMs, apertoIl: new Date(sbloccoMs), stagioneInCorso: false }
}
