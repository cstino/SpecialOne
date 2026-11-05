import { useEffect, useState } from 'react'

// I due colori principali di uno stemma, per lo sfondo delle figurine FUT (Season 3). Si leggono dall'immagine con un
// canvas piccolo: pixel opachi raggruppati per tinta e luminosita', il gruppo piu' numeroso e' il primo colore, il
// secondo e' il piu' numeroso fra quelli abbastanza diversi dal primo. Il bianco puro conta solo se non c'e' altro
// (molti stemmi hanno un fondo bianco). Risultato in memoria per tutta la sessione: e' solo grafica.

// chiaro: il primo colore (parte alta della carta) e' chiaro; chiaroBasso: lo e' il secondo, su cui stanno nome e
// statistiche. Su fondo chiaro il testo diventa scuro.
export type ColoriStemma = { primo: string; secondo: string; chiaro: boolean; chiaroBasso: boolean }

export const COLORI_PREDEFINITI: ColoriStemma = { primo: '#3b2a6b', secondo: '#120c24', chiaro: false, chiaroBasso: false }
const cache = new Map<string, Promise<ColoriStemma>>()

function hex(r: number, g: number, b: number) {
  return '#' + [r, g, b].map((v) => Math.round(v).toString(16).padStart(2, '0')).join('')
}

function hsl(r: number, g: number, b: number): [number, number, number] {
  r /= 255; g /= 255; b /= 255
  const max = Math.max(r, g, b), min = Math.min(r, g, b), l = (max + min) / 2
  if (max === min) return [0, 0, l]
  const d = max - min
  const s = l > 0.5 ? d / (2 - max - min) : d / (max + min)
  const h = max === r ? (g - b) / d + (g < b ? 6 : 0) : max === g ? (b - r) / d + 2 : (r - g) / d + 4
  return [h * 60, s, l]
}

// Luminanza percepita: sopra 0,6 lo sfondo e' chiaro e il testo della carta diventa scuro.
function luminanza(colore: string) {
  const n = parseInt(colore.slice(1), 16)
  return (0.299 * (n >> 16) + 0.587 * ((n >> 8) & 255) + 0.114 * (n & 255)) / 255
}

function estrai(img: HTMLImageElement): ColoriStemma {
  const lato = 40
  const canvas = document.createElement('canvas')
  canvas.width = lato; canvas.height = lato
  const ctx = canvas.getContext('2d', { willReadFrequently: true })
  if (!ctx) return COLORI_PREDEFINITI
  ctx.drawImage(img, 0, 0, lato, lato)
  const dati = ctx.getImageData(0, 0, lato, lato).data
  type Gruppo = { n: number; r: number; g: number; b: number; h: number; s: number; l: number }
  const gruppi = new Map<string, Gruppo>()
  for (let i = 0; i < dati.length; i += 4) {
    if (dati[i + 3] < 200) continue
    const [r, g, b] = [dati[i], dati[i + 1], dati[i + 2]]
    const [h, s, l] = hsl(r, g, b)
    // Grigi (poca saturazione) per luminosita', colori per tinta e luminosita'.
    const chiave = s < 0.18 ? `g${Math.round(l * 4)}` : `c${Math.round(h / 24)}:${Math.round(l * 3)}`
    const x = gruppi.get(chiave) ?? { n: 0, r: 0, g: 0, b: 0, h, s, l }
    x.n++; x.r += r; x.g += g; x.b += b
    gruppi.set(chiave, x)
  }
  const lista = [...gruppi.values()].map((x) => {
    const r = x.r / x.n, g = x.g / x.n, b = x.b / x.n
    const [h, s, l] = hsl(r, g, b)
    return { n: x.n, colore: hex(r, g, b), h, s, l }
  }).sort((a, b) => b.n - a.n)
  if (!lista.length) return COLORI_PREDEFINITI
  const bianco = (c: { s: number; l: number }) => c.l > 0.9 && c.s < 0.25
  const primo = lista.find((c) => !bianco(c)) ?? lista[0]
  const diverso = (c: typeof primo) => {
    const dh = Math.min(Math.abs(c.h - primo.h), 360 - Math.abs(c.h - primo.h))
    return (c.s > 0.18 && primo.s > 0.18 ? dh > 35 : false) || Math.abs(c.l - primo.l) > 0.3
  }
  const secondo = lista.find((c) => c !== primo && diverso(c) && c.n >= lista[0].n * 0.06)
  const scuro = hex(...[1, 3, 5].map((k) => parseInt(primo.colore.slice(k, k + 2), 16) * 0.35) as [number, number, number])
  const coppia = { primo: primo.colore, secondo: secondo?.colore ?? scuro }
  return { ...coppia, chiaro: luminanza(coppia.primo) > 0.6, chiaroBasso: luminanza(coppia.secondo) > 0.6 }
}

export function coloriStemma(url: string): Promise<ColoriStemma> {
  let p = cache.get(url)
  if (!p) {
    p = new Promise((risolvi) => {
      const img = new Image()
      img.crossOrigin = 'anonymous'
      img.onload = () => { try { risolvi(estrai(img)) } catch { risolvi(COLORI_PREDEFINITI) } }
      img.onerror = () => risolvi(COLORI_PREDEFINITI)
      img.src = url
    })
    cache.set(url, p)
  }
  return p
}

export function useColoriStemma(url: string | undefined): ColoriStemma {
  const [colori, setColori] = useState<ColoriStemma>(COLORI_PREDEFINITI)
  useEffect(() => {
    if (!url) { setColori(COLORI_PREDEFINITI); return }
    let vivo = true
    void coloriStemma(url).then((c) => { if (vivo) setColori(c) })
    return () => { vivo = false }
  }, [url])
  return colori
}
