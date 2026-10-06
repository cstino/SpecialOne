import { useCallback, useEffect, useRef, useState } from 'react'
import { supabase } from './supabase'

// Reazioni in diretta: messaggi prefatti (testo ed emoji) che galleggiano per tutti gli spettatori della
// stessa lega (migrazione 20261006170000). Un messaggio ogni 5 secondi per persona, anche nel database.

export type Contesto = 'draft' | 'sorteggio' | 'on'

// Stessi codici di public.invia_reazione (da tenere allineati a mano). Il testo e' il messaggio cosi' com'e'
// (emoji comprese): lo scelgono i partecipanti.
export const REAZIONI = [
  { codice: 'fuoco', testo: '🔥🔥🔥' },
  { codice: 'drafto', testo: 'Ora Drafto Io' },
  { codice: 'eddai', testo: 'Eddai!!!' },
  { codice: 'complimenti', testo: 'Complimenti 👏👏' },
  { codice: 'pazzesco', testo: 'Pazzesco! 🤯' },
  { codice: 'nooo', testo: 'Ohhh Noo! 😡' },
  { codice: 'imbarazzo', testo: '🥺🥺🥺' },
  { codice: 'occhi', testo: '😳😳😳' },
  { codice: 'herewego', testo: 'HERE WE GO ❗' },
  { codice: 'shalom', testo: 'Shalom ✡️' },
  { codice: 'diavoli', testo: '👹👹👹' },
] as const
/** Solo emoji (nessuna lettera): si mostra in grande. */
export const soloEmoji = (testo: string) => !/[\p{L}\p{N}]/u.test(testo)
export type CodiceReazione = (typeof REAZIONI)[number]['codice']

export const ATTESA_REAZIONE_S = 5
const DURATA_BOLLA_MS = 3400
const MAX_BOLLE = 14

export type Bolla = { id: number; codice: CodiceReazione; teamId: number; x: number; ritardo: number }

let sequenzaBolle = 0
let sequenzaCanali = 0

type Opzioni = {
  leagueId: number
  contesto: Contesto
  mioTeamId: number
  // Anteprima con dati fittizi: niente database, le reazioni degli altri le inventa l'anteprima.
  demo?: { teamIds: number[] }
}

export function useReazioniLive({ leagueId, contesto, mioTeamId, demo }: Opzioni) {
  const [bolle, setBolle] = useState<Bolla[]>([])
  const [attesa, setAttesa] = useState(0)
  const [errore, setErrore] = useState<string | null>(null)
  const fineAttesa = useRef(0)
  const demoIds = useRef(demo?.teamIds ?? [])
  demoIds.current = demo?.teamIds ?? []

  const aggiungi = useCallback((codice: CodiceReazione, teamId: number) => {
    const id = ++sequenzaBolle
    const bolla: Bolla = { id, codice, teamId, x: 6 + Math.random() * 78, ritardo: Math.random() * 0.12 }
    setBolle((prima) => [...prima.slice(-(MAX_BOLLE - 1)), bolla])
    window.setTimeout(() => setBolle((prima) => prima.filter((b) => b.id !== id)), DURATA_BOLLA_MS + 200)
  }, [])

  // Le reazioni degli altri arrivano in tempo reale; la propria si mostra subito, senza aspettare la rete.
  useEffect(() => {
    if (demo) return
    const topic = `reazioni:${leagueId}:${contesto}:${Date.now()}:${++sequenzaCanali}`
    try {
      const canale = supabase
        .channel(topic)
        .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'reazioni_live', filter: `league_id=eq.${leagueId}` }, (payload) => {
          const r = payload.new as { team_id: number; contesto: string; codice: string }
          if (r.contesto !== contesto || r.team_id === mioTeamId) return
          if (REAZIONI.some((x) => x.codice === r.codice)) aggiungi(r.codice as CodiceReazione, r.team_id)
        })
        .subscribe()
      return () => { void supabase.removeChannel(canale) }
    } catch (e) {
      console.warn('Reazioni in tempo reale non disponibili:', e)
    }
  }, [leagueId, contesto, mioTeamId, demo, aggiungi])

  // Reazioni inventate dell'anteprima.
  useEffect(() => {
    if (!demo) return
    const timer = window.setInterval(() => {
      const ids = demoIds.current
      if (!ids.length) return
      aggiungi(REAZIONI[Math.floor(Math.random() * REAZIONI.length)].codice, ids[Math.floor(Math.random() * ids.length)])
    }, 1500)
    return () => window.clearInterval(timer)
  }, [demo, aggiungi])

  // Conto alla rovescia dei 5 secondi.
  useEffect(() => {
    if (attesa <= 0) return
    const timer = window.setInterval(() => {
      const restano = Math.max(0, (fineAttesa.current - Date.now()) / 1000)
      setAttesa(restano)
    }, 100)
    return () => window.clearInterval(timer)
  }, [attesa > 0]) // eslint-disable-line react-hooks/exhaustive-deps

  const invia = useCallback(async (codice: CodiceReazione) => {
    if (Date.now() < fineAttesa.current) return
    fineAttesa.current = Date.now() + ATTESA_REAZIONE_S * 1000
    setAttesa(ATTESA_REAZIONE_S)
    setErrore(null)
    aggiungi(codice, mioTeamId)
    if (demo) return
    const { error } = await supabase.rpc('invia_reazione', { p_league_id: leagueId, p_contesto: contesto, p_codice: codice })
    if (error) setErrore(error.message)
  }, [leagueId, contesto, mioTeamId, demo, aggiungi])

  return { bolle, attesa, errore, invia }
}
