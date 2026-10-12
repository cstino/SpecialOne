import { useCallback, useEffect, useRef, useState } from 'react'
import { configurationError, supabase } from './supabase'

export type StatoManutenzione = {
  attiva: boolean
  // 'manuale' = interruttore acceso dall'admin, 'irraggiungibile' = il server non risponde
  motivo: 'manuale' | 'irraggiungibile' | null
  messaggio: string | null
  riprova: () => void
}

const OGNI_MS = 45_000
const TIMEOUT_MS = 8_000
// Un solo errore puo' essere una cella che salta: serve che falliscano due controlli di fila.
const ERRORI_PER_SCATTO = 2

export function useManutenzione(): StatoManutenzione {
  const [manuale, setManuale] = useState(false)
  const [messaggio, setMessaggio] = useState<string | null>(null)
  const [irraggiungibile, setIrraggiungibile] = useState(false)
  const errori = useRef(0)

  const controlla = useCallback(async () => {
    if (configurationError) return
    const stop = new AbortController()
    const timer = setTimeout(() => stop.abort(), TIMEOUT_MS)
    try {
      const { data, error } = await supabase
        .from('stato_app')
        .select('manutenzione, messaggio')
        .eq('id', true)
        .abortSignal(stop.signal)
        .maybeSingle()
      if (error) throw error
      errori.current = 0
      setIrraggiungibile(false)
      setManuale(Boolean(data?.manutenzione))
      setMessaggio(data?.messaggio ?? null)
    } catch {
      errori.current += 1
      if (errori.current >= ERRORI_PER_SCATTO) setIrraggiungibile(true)
    } finally {
      clearTimeout(timer)
    }
  }, [])

  useEffect(() => {
    void controlla()
    const giro = setInterval(() => void controlla(), OGNI_MS)
    const alRitorno = () => { if (document.visibilityState === 'visible') void controlla() }
    document.addEventListener('visibilitychange', alRitorno)
    window.addEventListener('online', alRitorno)
    return () => {
      clearInterval(giro)
      document.removeEventListener('visibilitychange', alRitorno)
      window.removeEventListener('online', alRitorno)
    }
  }, [controlla])

  return {
    attiva: manuale || irraggiungibile,
    motivo: manuale ? 'manuale' : irraggiungibile ? 'irraggiungibile' : null,
    messaggio,
    riprova: () => { errori.current = 0; void controlla() },
  }
}
