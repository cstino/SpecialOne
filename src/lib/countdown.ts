import { useEffect, useState } from 'react'
import { supabase } from './supabase'

// I countdown usavano Date.now(), cioe' l'orologio del telefono: su un
// dispositivo avanti o indietro di qualche minuto mostravano un tempo
// sbagliato, e due partecipanti vedevano numeri diversi per lo stesso
// evento. Il server ha sempre deciso in base alla propria now() (le
// offerte fuori orario venivano rifiutate comunque), quindi l'unico
// problema era il numero mostrato: qui si misura lo scarto una volta e
// lo si applica a tutti i countdown.
//
// Lo scarto e' condiviso da tutta l'app (variabile di modulo, non stato
// di React): i cinque componenti che mostrano un countdown non fanno
// cinque sincronizzazioni diverse, e chi monta dopo parte gia' corretto.
let scartoMs = 0
let sincronizzazioneInCorso: Promise<void> | null = null

// Ogni 5 minuti: copre la deriva dell'orologio del dispositivo senza
// pesare (una chiamata da poche decine di byte).
const INTERVALLO_RISINCRONIZZAZIONE = 5 * 60 * 1000
let ultimaSincronizzazione = 0

async function sincronizzaOrologio() {
  // Se una sincronizzazione e' gia' in volo, ci si aggancia a quella
  // invece di aprirne una seconda (succede quando piu' componenti si
  // montano insieme).
  if (sincronizzazioneInCorso) return sincronizzazioneInCorso

  sincronizzazioneInCorso = (async () => {
    const partenza = Date.now()
    const { data, error } = await supabase.rpc('ora_server')
    const arrivo = Date.now()
    if (error || !data) return

    const oraServer = new Date(data as string).getTime()
    if (Number.isNaN(oraServer)) return

    // Il tempo di rete va tolto, altrimenti lo si scambierebbe per
    // scarto d'orologio. Si assume andata e ritorno simmetrici: quando
    // il server ha risposto "oraServer", noi eravamo a meta' strada fra
    // partenza e arrivo.
    const andataRitorno = arrivo - partenza
    scartoMs = oraServer - (partenza + andataRitorno / 2)
    ultimaSincronizzazione = Date.now()
  })()

  try {
    await sincronizzazioneInCorso
  } finally {
    sincronizzazioneInCorso = null
  }
}

/** Ora corrente corretta sull'orologio del server, non su quello del dispositivo. */
export function oraServerAdesso() {
  return Date.now() + scartoMs
}

export function useOraCorrente() {
  const [ora, setOra] = useState(() => oraServerAdesso())

  useEffect(() => {
    let vivo = true

    const risincronizzaSeServe = () => {
      if (Date.now() - ultimaSincronizzazione < INTERVALLO_RISINCRONIZZAZIONE) return
      void sincronizzaOrologio().then(() => {
        if (vivo) setOra(oraServerAdesso())
      })
    }

    risincronizzaSeServe()

    const timer = window.setInterval(() => {
      setOra(oraServerAdesso())
      risincronizzaSeServe()
    }, 1000)

    // Al risveglio del telefono l'orologio puo' essere andato alla
    // deriva e i timer restano fermi mentre la pagina e' nascosta: si
    // risincronizza appena l'app torna in primo piano, che sul telefono
    // e' il caso normale.
    const alRitorno = () => {
      if (document.visibilityState !== 'visible') return
      ultimaSincronizzazione = 0
      risincronizzaSeServe()
    }
    document.addEventListener('visibilitychange', alRitorno)

    return () => {
      vivo = false
      window.clearInterval(timer)
      document.removeEventListener('visibilitychange', alRitorno)
    }
  }, [])

  return ora
}

export function formatCountdown(millisecondi: number) {
  const secondi = Math.max(0, Math.floor(millisecondi / 1000))
  const giorni = Math.floor(secondi / 86400)
  const ore = Math.floor((secondi % 86400) / 3600)
  const minuti = Math.floor((secondi % 3600) / 60)
  const restanti = secondi % 60
  const orologio = `${String(ore).padStart(2, '0')}:${String(minuti).padStart(2, '0')}:${String(restanti).padStart(2, '0')}`
  return giorni > 0 ? `${giorni}g ${orologio}` : orologio
}
