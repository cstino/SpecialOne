import { useCallback, useEffect, useMemo, useState } from 'react'
import { supabase } from './supabase'

export type TipoNotifica =
  | 'giornata_simulata'
  | 'formazione_mancante'
  | 'infortunio'
  | 'mercato_proposta'
  | 'mercato_esito'
  | 'mercato_asta'
  | 'sistema'

export type Notifica = {
  id: number
  league_id: number | null
  tipo: TipoNotifica
  titolo: string
  corpo: string | null
  dati: Record<string, unknown>
  letta_il: string | null
  creata_il: string
}

// Quante se ne tengono in memoria. La campanella non e' un archivio: oltre
// questa soglia si scorre la cronologia della lega, non le notifiche.
const LIMITE = 30
let sequenzaCanali = 0

export function useNotifiche(userId: string | undefined) {
  const [notifiche, setNotifiche] = useState<Notifica[]>([])
  const [caricamento, setCaricamento] = useState(true)

  const carica = useCallback(async () => {
    if (!userId) {
      setNotifiche([])
      setCaricamento(false)
      return
    }
    const { data, error } = await supabase
      .from('notifications')
      .select('id, league_id, tipo, titolo, corpo, dati, letta_il, creata_il')
      .order('creata_il', { ascending: false })
      .order('id', { ascending: false })
      .limit(LIMITE)
    // Un errore qui non deve rompere la schermata: la campanella e' un
    // accessorio, e senza notifiche il gioco resta giocabile.
    if (!error) setNotifiche((data ?? []) as Notifica[])
    setCaricamento(false)
  }, [userId])

  useEffect(() => { void carica() }, [carica])

  // Consegna in tempo reale: senza, il pallino comparirebbe solo ricaricando
  // la pagina, e una proposta di mercato che scade in giornata la si
  // scoprirebbe scaduta.
  useEffect(() => {
    if (!userId) return
    // GameNav monta contemporaneamente la campanella desktop e quella mobile.
    // Da realtime-js 2.111 channel() riusa un canale con lo stesso topic:
    // il secondo .on() arriverebbe quindi dopo subscribe() e lancerebbe un
    // errore sincrono, abbattendo tutta la pagina. Anche StrictMode esegue
    // setup-cleanup-setup in sviluppo, prima che removeChannel sia terminato.
    // Ogni effetto usa percio' un topic distinto.
    const topic = `notifiche:${userId}:${Date.now()}:${++sequenzaCanali}`
    try {
      const canale = supabase
        .channel(topic)
        .on(
          'postgres_changes',
          { event: 'INSERT', schema: 'public', table: 'notifications', filter: `user_id=eq.${userId}` },
          (payload) => {
            const nuova = payload.new as Notifica
            setNotifiche((precedenti) => precedenti.some((n) => n.id === nuova.id)
              ? precedenti
              : [nuova, ...precedenti].slice(0, LIMITE))
          },
        )
        .subscribe()
      return () => { void supabase.removeChannel(canale) }
    } catch {
      // Le notifiche sono accessorie: un errore Realtime non deve mai rendere
      // inutilizzabile il gioco. Il riallineamento al visibilitychange resta.
      return
    }
  }, [userId])

  // Rete di sicurezza: se il socket cade mentre il telefono e' in tasca,
  // al ritorno sull'app si riallinea comunque.
  useEffect(() => {
    if (!userId) return
    function alRitorno() { if (document.visibilityState === 'visible') void carica() }
    document.addEventListener('visibilitychange', alRitorno)
    return () => document.removeEventListener('visibilitychange', alRitorno)
  }, [userId, carica])

  const nonLette = useMemo(() => notifiche.filter((n) => !n.letta_il).length, [notifiche])

  const segnaLette = useCallback(async (ids?: number[]) => {
    if (!userId) return
    const adesso = new Date().toISOString()
    // Ottimistico: il pallino sparisce subito. Se la RPC fallisce il prossimo
    // caricamento rimette le cose a posto.
    setNotifiche((precedenti) => precedenti.map((n) =>
      n.letta_il || (ids && !ids.includes(n.id)) ? n : { ...n, letta_il: adesso }))
    await supabase.rpc('segna_notifiche_lette', { p_ids: ids ?? null })
  }, [userId])

  const elimina = useCallback(async (id: number) => {
    if (!userId) return false
    const precedente = notifiche.find((notifica) => notifica.id === id)
    setNotifiche((correnti) => correnti.filter((notifica) => notifica.id !== id))
    const { data, error } = await supabase.rpc('elimina_notifica', { p_notifica_id: id })
    if (error || !data) {
      if (precedente) {
        setNotifiche((correnti) => [...correnti, precedente]
          .sort((a, b) => b.creata_il.localeCompare(a.creata_il) || b.id - a.id)
          .slice(0, LIMITE))
      }
      return false
    }
    return true
  }, [userId, notifiche])

  return { notifiche, nonLette, caricamento, ricarica: carica, segnaLette, elimina }
}

const MINUTO = 60_000
const ORA = 60 * MINUTO
const GIORNO = 24 * ORA

// "3 min", "2 h", "ieri", poi la data. La differenza fra due istanti non
// dipende dal fuso; la data assoluta si', e va letta in Europe/Rome come
// tutto il resto del progetto.
export function quandoRelativo(iso: string): string {
  const trascorso = Date.now() - new Date(iso).getTime()
  if (trascorso < MINUTO) return 'ora'
  if (trascorso < ORA) return `${Math.floor(trascorso / MINUTO)} min`
  if (trascorso < GIORNO) return `${Math.floor(trascorso / ORA)} h`
  if (trascorso < 2 * GIORNO) return 'ieri'
  if (trascorso < 7 * GIORNO) return `${Math.floor(trascorso / GIORNO)} g`
  return new Date(iso).toLocaleDateString('it-IT', {
    day: 'numeric', month: 'short', timeZone: 'Europe/Rome',
  })
}
