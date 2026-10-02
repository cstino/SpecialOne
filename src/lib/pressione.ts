import { isEventoGol, type EventoPartita } from '../types'

// La pressione offensiva minuto per minuto, per il grafico sotto la
// telecronaca: sopra lo zero attacca la squadra di casa, sotto l'ospite.
// Il motore non segue la posizione del pallone, quindi la pressione e'
// ricavata dalle occasioni vere della partita (TUTTI i tiri, anche quelli che
// la telecronaca non racconta): ogni gol, tiro parato o tiro fuori spinge la
// curva dalla parte di chi l'ha costruito, con un'onda che sale qualche
// minuto prima e cala dopo. Una piccola ondulazione fissa per partita evita
// che i minuti senza occasioni sembrino un elettrocardiogramma piatto.

const PESO = { gol: 1.6, tiro_parato: 1.0, tiro_fuori: 0.65 } as const
const SIGMA = 3.2 // minuti: larghezza dell'onda attorno a un'occasione

export function curvaPressione(eventi: EventoPartita[], fine: number, seme: number): number[] {
  const valori = new Array(fine + 1).fill(0)
  for (const e of eventi) {
    const peso = isEventoGol(e) ? PESO.gol : e.tipo === 'tiro_parato' ? PESO.tiro_parato : e.tipo === 'tiro_fuori' ? PESO.tiro_fuori : 0
    if (!peso) continue
    const segno = e.lato === 'casa' ? 1 : -1
    // L'azione cresce prima dell'occasione e si spegne dopo: l'onda e'
    // centrata un minuto prima del tiro.
    const centro = e.minuto - 1
    for (let m = Math.max(0, Math.floor(centro - 3 * SIGMA)); m <= Math.min(fine, Math.ceil(centro + 3 * SIGMA)); m++) {
      valori[m] += segno * peso * Math.exp(-((m - centro) ** 2) / (2 * SIGMA * SIGMA))
    }
  }
  // Ondulazione di fondo, fissa per partita.
  const fasi = [0, 1, 2].map((k) => ((Math.imul(seme + k * 7919, 2654435761) >>> 0) / 4294967296) * Math.PI * 2)
  for (let m = 0; m <= fine; m++) {
    valori[m] += 0.12 * Math.sin(m / 3.1 + fasi[0]) + 0.08 * Math.sin(m / 1.7 + fasi[1]) + 0.05 * Math.sin(m / 6.3 + fasi[2])
  }
  // Scala fissa per tutta la partita (non cambia mentre la curva cresce).
  const massimo = Math.max(1.2, ...valori.map(Math.abs))
  return valori.map((v) => Math.max(-1, Math.min(1, v / massimo)))
}

// Percorso SVG morbido (Catmull-Rom) fino al minuto corrente.
export function percorsoCurva(valori: number[], finoA: number, larghezza: number, altezza: number, fine: number) {
  const x = (m: number) => (m / fine) * larghezza
  const y = (v: number) => altezza / 2 - v * (altezza / 2 - 3)
  const punti = valori.slice(0, Math.max(1, Math.min(valori.length, finoA + 1))).map((v, m) => [x(m), y(v)] as const)
  if (punti.length < 2) return { linea: '', area: '' }
  let linea = `M${punti[0][0].toFixed(1)},${punti[0][1].toFixed(1)}`
  for (let i = 0; i < punti.length - 1; i++) {
    const p0 = punti[Math.max(0, i - 1)], p1 = punti[i], p2 = punti[i + 1], p3 = punti[Math.min(punti.length - 1, i + 2)]
    const c1 = [p1[0] + (p2[0] - p0[0]) / 6, p1[1] + (p2[1] - p0[1]) / 6]
    const c2 = [p2[0] - (p3[0] - p1[0]) / 6, p2[1] - (p3[1] - p1[1]) / 6]
    linea += ` C${c1[0].toFixed(1)},${c1[1].toFixed(1)} ${c2[0].toFixed(1)},${c2[1].toFixed(1)} ${p2[0].toFixed(1)},${p2[1].toFixed(1)}`
  }
  const ultimo = punti[punti.length - 1][0]
  const area = `${linea} L${ultimo.toFixed(1)},${(altezza / 2).toFixed(1)} L${punti[0][0].toFixed(1)},${(altezza / 2).toFixed(1)} Z`
  return { linea, area }
}

// Il colore dominante di uno stemma (per il grafico, al posto dei colori
// sociali che il gioco non salva): si scarta il quasi bianco, il quasi nero e
// il trasparente, e vince la tinta piu' frequente fra quelle sature.
export async function coloreStemma(url: string | undefined | null): Promise<string | null> {
  if (!url) return null
  try {
    const img = new Image()
    img.crossOrigin = 'anonymous'
    img.src = url
    await img.decode()
    const lato = 32
    const canvas = document.createElement('canvas')
    canvas.width = lato; canvas.height = lato
    const ctx = canvas.getContext('2d', { willReadFrequently: true })
    if (!ctx) return null
    ctx.drawImage(img, 0, 0, lato, lato)
    const { data } = ctx.getImageData(0, 0, lato, lato)
    const conteggio = new Map<string, { n: number; r: number; g: number; b: number }>()
    for (let i = 0; i < data.length; i += 4) {
      const [r, g, b, a] = [data[i], data[i + 1], data[i + 2], data[i + 3]]
      if (a < 200) continue
      const max = Math.max(r, g, b), min = Math.min(r, g, b)
      if (max < 40 || (min > 215) || max - min < 40) continue
      const chiave = `${r >> 5}-${g >> 5}-${b >> 5}`
      const c = conteggio.get(chiave) ?? { n: 0, r: 0, g: 0, b: 0 }
      c.n++; c.r += r; c.g += g; c.b += b
      conteggio.set(chiave, c)
    }
    const migliore = [...conteggio.values()].sort((a, b) => b.n - a.n)[0]
    if (!migliore || migliore.n < 12) return null
    return `rgb(${Math.round(migliore.r / migliore.n)}, ${Math.round(migliore.g / migliore.n)}, ${Math.round(migliore.b / migliore.n)})`
  } catch {
    return null
  }
}

// Due colori troppo simili non si distinguono nel grafico.
export function coloriDistinti(a: string, b: string) {
  const num = (c: string) => (c.match(/\d+/g) ?? []).map(Number)
  const [x, y] = [num(a), num(b)]
  if (x.length < 3 || y.length < 3) return a !== b
  return Math.hypot(x[0] - y[0], x[1] - y[1], x[2] - y[2]) > 90
}
