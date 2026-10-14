import { useEffect, useMemo, useRef, useState, type KeyboardEvent } from 'react'
import { percorsoCurva } from '../lib/pressione'
import type { Parte, Riga } from '../lib/telecronaca'
import type { Gol, Risultato } from './dati'

// La diretta sugli occhiali, a tutto schermo: tabellone, telecronaca dell'app (due righe alla volta, niente
// scorrimento), grafico della pressione, scena del gol, suoni e voce. Un minuto di partita ogni 0,7 secondi.
const PASSO_MS = 700
const SCENA_GOL_MS = 3200
const PAUSA_INTERVALLO_MS = 2000
const CHIAVE_VOCE = 'occhiali-voce'

function leggiVoce() { try { return localStorage.getItem(CHIAVE_VOCE) !== 'no' } catch { return true } }
function salvaVoce(v: boolean) { try { localStorage.setItem(CHIAVE_VOCE, v ? 'si' : 'no') } catch { /* niente */ } }

function parla(testo: string) {
  try {
    const s = window.speechSynthesis
    if (!s) return
    s.cancel()
    const u = new SpeechSynthesisUtterance(testo)
    u.lang = 'it-IT'; u.rate = 1.05
    s.speak(u)
  } catch { /* la voce e' un di piu' */ }
}

// Fischio dell'arbitro sintetizzato (non c'e' un file audio): due o tre colpi acuti.
function fischio(contesto: AudioContext | null, colpi: number) {
  if (!contesto) return
  for (let i = 0; i < colpi; i++) {
    const t = contesto.currentTime + i * 0.32
    const osc = contesto.createOscillator(), vib = contesto.createOscillator(), g = contesto.createGain(), gv = contesto.createGain()
    osc.type = 'sine'; osc.frequency.value = 2900
    vib.frequency.value = 38; gv.gain.value = 120
    vib.connect(gv); gv.connect(osc.frequency)
    g.gain.setValueAtTime(0, t); g.gain.linearRampToValueAtTime(0.18, t + 0.02)
    g.gain.setValueAtTime(0.18, t + (i === colpi - 1 ? 0.5 : 0.2)); g.gain.linearRampToValueAtTime(0, t + (i === colpi - 1 ? 0.6 : 0.26))
    osc.connect(g); g.connect(contesto.destination)
    osc.start(t); vib.start(t); osc.stop(t + 0.7); vib.stop(t + 0.7)
  }
}

function Testo({ parti }: { parti: Parte[] }) {
  return <>{parti.map((p, i) => typeof p === 'string' ? <span key={i}>{p}</span> : <b key={i}>{p.g}</b>)}</>
}

const ETICHETTA: Record<Riga['tipo'], string> = {
  gol: 'GOL', parata: 'Parata', fuori: 'Tiro', legno: 'Legno', giallo: 'Giallo', rosso: 'Rosso',
  cambio: 'Cambio', infortunio: 'Infortunio', fallo: 'Fallo', angolo: 'Angolo', fischio: 'Arbitro',
}

// automatica = partita alle 23:00 senza averla aperta: a fine partita si chiude da sola dopo qualche secondo
// (cosi' parte la diretta della lega successiva, se c'e').
export function DirettaLive({ partita, onEsci, automatica = false }: { partita: Risultato; onEsci: () => void; automatica?: boolean }) {
  const [minuto, setMinuto] = useState(0)
  const [scena, setScena] = useState<Gol | null>(null)
  const [voce, setVoce] = useState(leggiVoce)
  const radice = useRef<HTMLElement>(null)
  const audio = useRef<{ ctx: AudioContext | null; stadio: HTMLAudioElement; esultanza: HTMLAudioElement } | null>(null)
  const golMostrati = useRef(new Set<number>())
  const fine = partita.fine

  // Audio: parte qui perche' la diretta si apre con Invio (un gesto: il browser lo permette).
  useEffect(() => {
    radice.current?.focus()
    const stadio = new Audio('/suoni-effetti/stadio-sottofondo.m4a'); stadio.loop = true; stadio.volume = 0.25
    const esultanza = new Audio('/suoni-effetti/esultanza-gol.m4a'); esultanza.volume = 0.9
    let ctx: AudioContext | null = null
    try { ctx = new AudioContext() } catch { ctx = null }
    audio.current = { ctx, stadio, esultanza }
    void stadio.play().catch(() => {})
    fischio(ctx, 1)
    return () => { stadio.pause(); esultanza.pause(); void ctx?.close(); window.speechSynthesis?.cancel() }
  }, [])

  // Avanzamento: si ferma durante la scena del gol e un attimo all'intervallo.
  useEffect(() => {
    if (scena || minuto >= fine) return
    const attesa = minuto === 45 ? PAUSA_INTERVALLO_MS : PASSO_MS
    const t = window.setTimeout(() => setMinuto((m) => m + 1), attesa)
    return () => window.clearTimeout(t)
  }, [minuto, scena, fine])

  const golFinora = useMemo(() => partita.gol.filter((g) => g.minuto <= minuto), [partita.gol, minuto])
  const golCasa = golFinora.filter((g) => g.lato === 'casa').length
  const golOspite = golFinora.length - golCasa

  // Gol nuovi in questo minuto: scena, esultanza, voce.
  useEffect(() => {
    const nuovo = partita.gol.findIndex((g, i) => g.minuto === minuto && !golMostrati.current.has(i))
    if (nuovo < 0) return
    golMostrati.current.add(nuovo)
    const g = partita.gol[nuovo]
    setScena(g)
    const a = audio.current
    if (a) { a.esultanza.currentTime = 0; void a.esultanza.play().catch(() => {}) }
    if (voce) {
      const gc = partita.gol.filter((x, i) => i <= nuovo && x.lato === 'casa').length
      const go = partita.gol.filter((x, i) => i <= nuovo && x.lato === 'ospite').length
      parla(`Gol! ${g.marcatore}! ${partita.casa.nome} ${gc}, ${partita.ospite.nome} ${go}.`)
    }
    const t = window.setTimeout(() => setScena(null), SCENA_GOL_MS)
    return () => window.clearTimeout(t)
  }, [minuto, partita, voce])

  // Fischi e voce a intervallo e fine partita.
  useEffect(() => {
    const ctx = audio.current?.ctx ?? null
    if (minuto === 45) { fischio(ctx, 2); if (voce) parla(`Fine primo tempo. ${partita.casa.nome} ${golCasa}, ${partita.ospite.nome} ${golOspite}.`) }
    if (minuto === 46) fischio(ctx, 1)
    if (minuto === fine) {
      fischio(ctx, 3)
      audio.current?.stadio.pause()
      if (voce) parla(`Triplice fischio! Finisce ${partita.casa.nome} ${golCasa}, ${partita.ospite.nome} ${golOspite}.`)
    }
  }, [minuto]) // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => {
    if (!automatica || minuto < fine) return
    const t = window.setTimeout(onEsci, 12_000)
    return () => window.clearTimeout(t)
  }, [automatica, minuto, fine, onEsci])

  const righe = useMemo(() => partita.telecronaca.filter((r) => r.minuto <= minuto), [partita.telecronaca, minuto])
  const ultime = righe.slice(-2).reverse()
  const W = 540, H = 70
  const { linea, area } = percorsoCurva(partita.curva, minuto, W, H, fine)

  const tasti = (e: KeyboardEvent) => {
    if (e.key === 'Escape') { e.preventDefault(); onEsci() }
    else if (e.key === 'ArrowUp' || e.key === 'ArrowDown') {
      e.preventDefault(); setVoce((v) => { salvaVoce(!v); if (v) window.speechSynthesis?.cancel(); return !v })
    } else if (e.key === 'Enter' && minuto >= fine) {
      e.preventDefault(); golMostrati.current.clear(); setScena(null); setMinuto(0)
      const a = audio.current; if (a) { a.stadio.currentTime = 0; void a.stadio.play().catch(() => {}); fischio(a.ctx, 1) }
    }
  }

  return <main className="oc oc-live" ref={radice} tabIndex={0} onKeyDown={tasti} aria-label="Diretta della partita">
    <div className="oc-live__tabellone">
      <span className="oc-live__squadra">{partita.casa.stemma ? <img src={partita.casa.stemma} alt="" /> : null}<small>{partita.casa.nome}</small></span>
      <span className="oc-live__centro">
        <b className="oc-live__punteggio">{golCasa} : {golOspite}</b>
        <em className={minuto >= fine ? 'oc-live__minuto is-finale' : 'oc-live__minuto'}>{minuto >= fine ? 'FINALE' : minuto === 45 ? 'INTERVALLO' : `${minuto}'`}</em>
      </span>
      <span className="oc-live__squadra">{partita.ospite.stemma ? <img src={partita.ospite.stemma} alt="" /> : null}<small>{partita.ospite.nome}</small></span>
    </div>
    <div className="oc-live__barra"><span style={{ width: `${Math.min(100, (minuto / fine) * 100)}%` }} /></div>

    <ul className="oc-live__cronaca">
      {ultime.map((r, i) => <li key={r.chiave} className={`oc-riga-live oc-riga-live--${r.tipo}${i === 0 ? ' is-nuova' : ''}`}>
        <span className="oc-riga-live__testa"><b>{r.minuto}'</b><em>{ETICHETTA[r.tipo]}</em></span>
        <p><Testo parti={r.testo} /></p>
      </li>)}
    </ul>

    <svg className="oc-live__pressione" viewBox={`0 0 ${W} ${H}`} preserveAspectRatio="none" aria-hidden="true">
      <line x1="0" y1={H / 2} x2={W} y2={H / 2} className="oc-p-zero" />
      <line x1={(45 / fine) * W} y1="2" x2={(45 / fine) * W} y2={H - 2} className="oc-p-tempo" />
      <path d={area} className="oc-p-area" />
      <path d={linea} className="oc-p-linea" />
    </svg>
    <footer className="oc-piede">Esc esci · ▲▼ voce {voce ? 'sì' : 'no'}{minuto >= fine ? ' · Invio rivedi' : ''}</footer>

    {scena && <div className="oc-gol" role="alert">
      <span className="oc-gol__scritta">GOL!</span>
      {(scena.lato === 'casa' ? partita.casa : partita.ospite).stemma && <img src={(scena.lato === 'casa' ? partita.casa : partita.ospite).stemma!} alt="" />}
      <b className="oc-gol__nome">{scena.marcatore.toUpperCase()}</b>
      {scena.assist && <span className="oc-gol__assist">assist {scena.assist}</span>}
      <span className="oc-gol__risultato">{golCasa} : {golOspite}</span>
    </div>}
  </main>
}
