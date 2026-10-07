import { supabase } from './supabase'

// Firma degli stemmi personalizzati (bucket privato team-crests).
//
// Prima ogni schermata chiedeva un indirizzo firmato per ogni squadra, a ogni caricamento: decine di
// richieste a Storage per utente, e un indirizzo sempre diverso, quindi il browser riscaricava anche
// le immagini. Ora:
//  - l'indirizzo firmato si riusa finche' e' valido (firmato per un'ora, riusato per 50 minuti):
//    stesso indirizzo = immagine gia' nella cache del browser;
//  - le richieste fatte quasi insieme (la lista di 24 squadre) partono come UNA sola chiamata
//    batch invece di 24;
//  - due richieste per lo stesso file mentre la prima e' in corso condividono la risposta.

const DURATA_FIRMA_S = 3600
const RIUSO_MS = 50 * 60 * 1000
const ATTESA_RACCOLTA_MS = 15

type Voce = { url: string; scade: number }
const firmati = new Map<string, Voce>()
const inCorso = new Map<string, Promise<string | null>>()
let coda: { percorso: string; risolvi: (url: string | null) => void }[] = []
let timer: number | null = null

async function svuotaCoda() {
  const lotto = coda
  coda = []
  timer = null
  const percorsi = [...new Set(lotto.map((voce) => voce.percorso))]
  const risultato = new Map<string, string>()
  try {
    const { data } = await supabase.storage.from('team-crests').createSignedUrls(percorsi, DURATA_FIRMA_S)
    for (const riga of data ?? []) {
      if (riga.path && riga.signedUrl) risultato.set(riga.path, riga.signedUrl)
    }
  } catch { /* si risolve con null: l'app mostra lo stemma di ripiego */ }
  const adesso = Date.now()
  for (const [percorso, url] of risultato) firmati.set(percorso, { url, scade: adesso + RIUSO_MS })
  for (const voce of lotto) voce.risolvi(risultato.get(voce.percorso) ?? null)
}

export function urlStemma(percorso: string): Promise<string | null> {
  const noto = firmati.get(percorso)
  if (noto && noto.scade > Date.now()) return Promise.resolve(noto.url)
  const attesa = inCorso.get(percorso)
  if (attesa) return attesa
  const promessa = new Promise<string | null>((risolvi) => {
    coda.push({ percorso, risolvi })
    if (timer === null) timer = window.setTimeout(() => { void svuotaCoda() }, ATTESA_RACCOLTA_MS)
  }).finally(() => { inCorso.delete(percorso) })
  inCorso.set(percorso, promessa)
  return promessa
}

// Stessa forma della risposta di createSignedUrl, cosi' i punti di chiamata cambiano di una riga sola.
export async function firmaStemma(percorso: string) {
  return { data: { signedUrl: await urlStemma(percorso) ?? undefined }, error: null }
}
