import { useCallback, useEffect, useRef, useState } from 'react'
import { supabase } from './supabase'

// Stagione da rivelare a questo utente (una volta sola, dopo la mezzanotte
// successiva all'ultima partita): lo decide il database, qui si chiede e si
// riprova ogni minuto e al ritorno sull'app, cosi' a mezzanotte parte da sola.
export function useAlboRivelazione(leagueId: number | null | undefined, userId: string | undefined) {
  const [stagioneId, setStagioneId] = useState<number | null>(null)
  // Stagioni chiuse in questa sessione: il controllo periodico non deve
  // riproporle mentre il "visto" e' ancora in viaggio verso il database.
  const chiuse = useRef(new Set<number>())

  useEffect(() => {
    setStagioneId(null)
    if (!leagueId || !userId) return
    let vivo = true
    async function controlla() {
      const { data, error } = await supabase.rpc('albo_rivelazione_pendente', { p_league_id: leagueId })
      if (vivo && !error && typeof data === 'number' && !chiuse.current.has(data)) setStagioneId((attuale) => attuale ?? data)
    }
    void controlla()
    const timer = window.setInterval(() => { if (document.visibilityState === 'visible') void controlla() }, 60_000)
    const alRitorno = () => { if (document.visibilityState === 'visible') void controlla() }
    document.addEventListener('visibilitychange', alRitorno)
    return () => { vivo = false; window.clearInterval(timer); document.removeEventListener('visibilitychange', alRitorno) }
  }, [leagueId, userId])

  const segnaVista = useCallback(async (stagione: number) => {
    chiuse.current.add(stagione)
    setStagioneId(null)
    if (!userId) return
    const { error } = await supabase.from('albo_rivelazioni').upsert(
      { user_id: userId, season_id: stagione },
      { onConflict: 'user_id,season_id', ignoreDuplicates: true },
    )
    if (error) console.warn('Impossibile salvare la rivelazione dell\'albo:', error.message)
  }, [userId])

  return { stagioneId, segnaVista }
}
