import { useCallback, useEffect, useRef, useState } from 'react'
import { supabase } from './supabase'

// Con ?provaAlbo nell'indirizzo la rivelazione parte sempre, sull'ultima
// stagione conclusa della lega, e non scrive il "visto": serve a provarla.
const MODO_PROVA = typeof window !== 'undefined' && new URLSearchParams(window.location.search).has('provaAlbo')

// Stagione da rivelare a questo utente (una volta sola, 30 minuti dopo l'ultima
// partita, e per chi ha giocato quell'ultima giornata solo dopo aver visto il
// proprio risultato): lo decide il database, qui si chiede e si riprova ogni
// minuto, al ritorno sull'app e quando l'utente guarda un risultato.
export function useAlboRivelazione(leagueId: number | null | undefined, userId: string | undefined) {
  const [stagioneId, setStagioneId] = useState<number | null>(null)
  // Stagioni chiuse in questa sessione: il controllo periodico non deve
  // riproporle mentre il "visto" e' ancora in viaggio verso il database.
  const chiuse = useRef(new Set<number>())

  const controlla = useCallback(async () => {
    if (!leagueId || !userId) return
    let trovata: number | null = null
    if (MODO_PROVA) {
      const { data, error } = await supabase.from('seasons').select('id').eq('league_id', leagueId)
        .eq('stato', 'conclusa').order('numero', { ascending: false }).limit(1).maybeSingle()
      if (error) console.warn('Albo (prova): stagione non letta:', error.message)
      trovata = (data as { id: number } | null)?.id ?? null
    } else {
      const { data, error } = await supabase.rpc('albo_rivelazione_pendente', { p_league_id: leagueId })
      if (error) { console.warn('Albo: controllo non riuscito:', error.message); return }
      trovata = typeof data === 'number' ? data : null
    }
    if (trovata != null && !chiuse.current.has(trovata)) setStagioneId((attuale) => attuale ?? trovata)
  }, [leagueId, userId])

  useEffect(() => {
    setStagioneId(null)
    if (!leagueId || !userId) return
    void controlla()
    const timer = window.setInterval(() => { if (document.visibilityState === 'visible') void controlla() }, 60_000)
    const alRitorno = () => { if (document.visibilityState === 'visible') void controlla() }
    document.addEventListener('visibilitychange', alRitorno)
    return () => { window.clearInterval(timer); document.removeEventListener('visibilitychange', alRitorno) }
  }, [leagueId, userId, controlla])

  const segnaVista = useCallback(async (stagione: number) => {
    chiuse.current.add(stagione)
    setStagioneId(null)
    if (!userId || MODO_PROVA) return
    const { error } = await supabase.from('albo_rivelazioni').upsert(
      { user_id: userId, season_id: stagione },
      { onConflict: 'user_id,season_id', ignoreDuplicates: true },
    )
    if (error) console.warn('Impossibile salvare la rivelazione dell\'albo:', error.message)
  }, [userId])

  return { stagioneId, segnaVista, ricontrolla: controlla }
}
