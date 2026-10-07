import { useCallback, useEffect, useRef, useState } from 'react'
import { supabase } from './supabase'
import { ANTICIPO_PRIMA_ESTRAZIONE } from './conferenze'

// Il draft OFF-Season in diretta (migrazione 20261006110000): il server ha gia'
// risolto le scelte, ma ogni giocatore si legge solo da quando viene rivelato
// (scelte_live_stato). Qui si sincronizza l'orologio col server e si tiene
// aggiornato lo stato, cosi' tutti vedono lo stesso istante.

export type ScelteLiveGiocatore = {
  player_id: number; nome: string; overall: number; eta: number; posizioni: string[]
  foto_url: string | null; ingaggio: number; nazionalita: string | null; club: string | null
}
export type ScelteLivePick = {
  n: number; posizione: number; team_id: number; team_origine_id: number
  intro_il: string; reveal_il: string
  esito: 'usata' | 'vuota' | null
  giocatore: ScelteLiveGiocatore | null
}
export type ScelteLiveStato = {
  ora_server: string; stagione: number; finestra: 'on' | 'off'
  avviato_il: string; passo_secondi: number; intro_secondi: number; totale: number
  fine_il: string; sorteggio_il: string | null; picks: ScelteLivePick[]
}

export type StadioLive = 'prima' | 'intro' | 'reveal' | 'fine'
export type FaseLive = {
  stadio: StadioLive
  // Scelta in corso (1..totale); 0 prima dell'avvio.
  n: number
  // Secondi mancanti alla fine della fase corrente (o all'avvio, prima).
  rimasti: number
  // Secondi trascorsi dentro la fase corrente.
  trascorsi: number
  durataFase: number
}

export function faseLive(stato: ScelteLiveStato, adesso: number): FaseLive {
  const avvio = Date.parse(stato.avviato_il)
  const passo = stato.passo_secondi * 1000
  const intro = stato.intro_secondi * 1000
  const trascorso = adesso - avvio
  if (trascorso < 0) return { stadio: 'prima', n: 0, rimasti: -trascorso / 1000, trascorsi: 0, durataFase: 0 }
  if (trascorso >= stato.totale * passo) return { stadio: 'fine', n: stato.totale, rimasti: 0, trascorsi: 0, durataFase: 0 }
  const slot = Math.floor(trascorso / passo)
  const nelSlot = trascorso - slot * passo
  if (nelSlot < intro) return { stadio: 'intro', n: slot + 1, rimasti: (intro - nelSlot) / 1000, trascorsi: nelSlot / 1000, durataFase: stato.intro_secondi }
  return { stadio: 'reveal', n: slot + 1, rimasti: (passo - nelSlot) / 1000, trascorsi: (nelSlot - intro) / 1000, durataFase: stato.passo_secondi - stato.intro_secondi }
}

/** undefined = sto caricando; null = in questa lega non c'e' nessun draft in diretta. */
export function useScelteLive(leagueId: number) {
  const [stato, setStato] = useState<ScelteLiveStato | null | undefined>(undefined)
  const [adesso, setAdesso] = useState(() => Date.now())
  const offset = useRef(0)
  const inCorso = useRef(false)

  const aggiorna = useCallback(async () => {
    if (inCorso.current) return
    inCorso.current = true
    try {
      const prima = Date.now()
      const { data, error } = await supabase.rpc('scelte_live_stato', { p_league_id: leagueId })
      // Funzione non ancora presente (migrazione non applicata): come se non ci fosse draft in diretta.
      if (error) { if (error.code === 'PGRST202' || error.code === '42883') setStato(null); return }
      if (!data) { setStato(null); return }
      const nuovo = data as ScelteLiveStato
      offset.current = Date.parse(nuovo.ora_server) - (prima + Date.now()) / 2
      // L'avvio visibile del sorteggio e' quando comincia il caricamento della prima squadra.
      if (nuovo.sorteggio_il) nuovo.sorteggio_il = new Date(Date.parse(nuovo.sorteggio_il) + ANTICIPO_PRIMA_ESTRAZIONE * 1000).toISOString()
      setStato(nuovo)
    } finally {
      inCorso.current = false
    }
  }, [leagueId])

  useEffect(() => {
    void aggiorna()
    const orologio = window.setInterval(() => setAdesso(Date.now() + offset.current), 250)
    return () => window.clearInterval(orologio)
  }, [aggiorna])

  // Se manca un reveal che il tempo dice gia' scattato lo si richiede ogni 600 ms; altrimenti ci si risincronizza
  // ogni 5 secondi. Il ciclo legge stato e orologio da riferimenti: NON dipende da `adesso`, che cambia ogni
  // 250 ms (con quella dipendenza l'intervallo veniva ricreato di continuo e non scattava mai: la carta del
  // giocatore non compariva al reveal. Difetto visto nella diretta del 7 ottobre).
  const statoRif = useRef(stato)
  statoRif.current = stato
  const adessoRif = useRef(adesso)
  adessoRif.current = adesso
  useEffect(() => {
    let vivo = true
    let timer = 0
    const ciclo = () => {
      const s = statoRif.current
      let attesa = 5000
      if (s) {
        const adesso = adessoRif.current
        const inSospeso = s.picks.filter((p) => p.esito === null)
        if (inSospeso.some((p) => Date.parse(p.reveal_il) <= adesso)) {
          attesa = 600 // il reveal e' gia' scattato: si richiede finche' non arriva
        } else if (inSospeso.length > 0) {
          // Si guarda subito dopo il prossimo reveal, senza aspettare il giro da 5 secondi.
          const alProssimo = Math.min(...inSospeso.map((p) => Date.parse(p.reveal_il) - adesso))
          attesa = Math.max(300, Math.min(5000, alProssimo + 150))
        }
      }
      timer = window.setTimeout(async () => {
        await aggiorna()
        if (vivo) ciclo()
      }, attesa)
    }
    ciclo()
    return () => { vivo = false; window.clearTimeout(timer) }
  }, [aggiorna])

  return { stato, adesso, aggiorna }
}

export const mmss = (secondi: number) => {
  const s = Math.max(0, Math.ceil(secondi))
  return `${String(Math.floor(s / 60)).padStart(2, '0')}:${String(s % 60).padStart(2, '0')}`
}
