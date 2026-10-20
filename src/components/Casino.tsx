import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { supabase } from '../lib/supabase'
import type { useSeasonData } from '../lib/useSeasonData'
import { Crest } from './Crest'

// BetOne Casino' (docs/decisioni-conferenze-stampa.md §BetOne): una slot a tema SpecialOne, minigioco interno senza
// effetti sul gioco vero. Ogni giro lo estrae il SERVER (casino_gira): qui si anima soltanto il risultato.
// Simboli 0-7 = gli stemmi della giornata (0-2 pagano poco, 3-5 medio, 6-7 molto), 8 = logo SpecialOne (jolly),
// 9 = coppa (3 o piu' ovunque: giri gratis con vincite doppie). 10 linee, 1.000 crediti gratis ogni giorno alle 23:00.

type Dati = ReturnType<typeof useSeasonData>
type Vincita = { linea: number; simbolo: number; n: number; vinto: number }
type Esito = { griglia: number[]; vincite: Vincita[]; coppe: number; scatter: number; vinto: number; gratis: boolean; molt: number; puntata: number; nuovi_gratis: number; crediti: number; giri_gratis: number; max_vincita: number; bustine?: number; bustine_vinte?: number; bustine_gratis?: number }
type Stato = { crediti: number; giri_gratis: number; puntata_gratis: number | null; simboli: number[]; max_vincita: number; giri: number; prossima_ricarica: string; bustine_gratis?: number; album?: boolean }

const PUNTATE = [10, 20, 50, 100]
const LINEE = [[1,1,1,1,1],[0,0,0,0,0],[2,2,2,2,2],[0,1,2,1,0],[2,1,0,1,2],[0,0,1,2,2],[2,2,1,0,0],[1,0,0,0,1],[1,2,2,2,1],[0,1,1,1,0]]
const PESI = [9, 9, 9, 7, 7, 7, 4, 4, 3, 2, 0]
const PAGA_BASE: Record<string, number[]> = { basso: [8, 26, 100], medio: [14, 52, 200], alto: [26, 125, 500] }
// Dove c'e' l'album (e quindi la bustina sui rulli) gli stemmi pagano un po' di piu'.
const PAGA_ALBUM: Record<string, number[]> = { basso: [9, 29, 110], medio: [16, 56, 222], alto: [29, 136, 550] }
const COLORI_LINEE = ['#ffd84d', '#ff5ad1', '#4de2ff', '#7dff6b', '#ff8a3d', '#b78bff', '#ff4d6d', '#3dffb5', '#ffe9a8', '#6bb7ff']
export const fmt = (n: number) => new Intl.NumberFormat('it-IT').format(Math.round(n))
const pescaSimbolo = () => { let x = Math.random() * 61; for (let i = 0; i < 11; i++) { x -= PESI[i]; if (x < 0) return i } return 0 }
export const ridotto = () => typeof window !== 'undefined' && window.matchMedia?.('(prefers-reduced-motion: reduce)').matches

// ---------- Suoni sintetizzati (nessun file audio) ----------
export function useSuoni(attivi: boolean) {
  const ctx = useRef<AudioContext | null>(null)
  const prendi = () => {
    if (!attivi) return null
    if (!ctx.current) {
      // iPhone: con audioSession 'playback' i suoni si sentono anche con l'interruttore del silenzioso (iOS 17+).
      try { (navigator as Navigator & { audioSession?: { type: string } }).audioSession!.type = 'playback' } catch { /* non supportato */ }
      try { ctx.current = new (window.AudioContext ?? (window as unknown as { webkitAudioContext: typeof AudioContext }).webkitAudioContext)() } catch { return null }
      // Sblocco: un suono muto suonato dentro il tocco, cosi' il primo vero suono non si perde.
      const b = ctx.current.createBuffer(1, 1, 22050), src = ctx.current.createBufferSource()
      src.buffer = b; src.connect(ctx.current.destination); src.start(0)
    }
    if (ctx.current.state !== 'running') void ctx.current.resume()
    return ctx.current
  }
  const tono = (freq: number, durata: number, tipo: OscillatorType = 'square', volume = 0.06, ritardo = 0, scivola?: number) => {
    const c = prendi(); if (!c) return
    const t = c.currentTime + ritardo
    const o = c.createOscillator(), g = c.createGain()
    o.type = tipo; o.frequency.setValueAtTime(freq, t)
    if (scivola) o.frequency.exponentialRampToValueAtTime(scivola, t + durata)
    g.gain.setValueAtTime(volume, t); g.gain.exponentialRampToValueAtTime(0.0001, t + durata)
    o.connect(g).connect(c.destination); o.start(t); o.stop(t + durata + 0.02)
  }
  return {
    sblocca: () => { prendi() },
    leva: () => { tono(180, 0.25, 'sawtooth', 0.05, 0, 520) },
    tick: (i: number) => tono(700 + (i % 4) * 60, 0.03, 'square', 0.02),
    stop: (i: number) => { tono(120 + i * 25, 0.12, 'triangle', 0.12); tono(60, 0.08, 'sine', 0.15) },
    vincita: () => [523, 659, 784, 1047].forEach((f, i) => tono(f, 0.18, 'square', 0.05, i * 0.08)),
    grande: () => { [523, 659, 784, 1047, 1319, 1568].forEach((f, i) => tono(f, 0.3, 'square', 0.05, i * 0.09)); [262, 330, 392].forEach((f) => tono(f, 1.2, 'sawtooth', 0.03, 0.55)) },
    coppe: () => [880, 1175, 1568, 2093].forEach((f, i) => tono(f, 0.22, 'triangle', 0.07, i * 0.12)),
    moneta: (i: number) => tono(1800 + (i % 5) * 120, 0.06, 'square', 0.025),
  }
}

// ---------- Coriandoli e monete per le vincite grosse ----------
export function Festa({ attiva }: { attiva: boolean }) {
  const ref = useRef<HTMLCanvasElement>(null)
  useEffect(() => {
    if (!attiva || ridotto()) return
    const cv = ref.current; if (!cv) return
    const c = cv.getContext('2d'); if (!c) return
    const W = cv.width = cv.offsetWidth * devicePixelRatio, H = cv.height = cv.offsetHeight * devicePixelRatio
    const pezzi = Array.from({ length: 140 }, () => ({
      x: Math.random() * W, y: -Math.random() * H * 0.6, vx: (Math.random() - 0.5) * 3 * devicePixelRatio, vy: (2 + Math.random() * 4) * devicePixelRatio,
      r: (4 + Math.random() * 6) * devicePixelRatio, a: Math.random() * Math.PI, va: (Math.random() - 0.5) * 0.3,
      col: Math.random() < 0.35 ? '#ffd84d' : COLORI_LINEE[Math.floor(Math.random() * COLORI_LINEE.length)], moneta: Math.random() < 0.35,
    }))
    let raf = 0, t0 = performance.now()
    const passo = (t: number) => {
      c.clearRect(0, 0, W, H)
      for (const p of pezzi) {
        p.x += p.vx; p.y += p.vy; p.vy += 0.05 * devicePixelRatio; p.a += p.va
        c.save(); c.translate(p.x, p.y); c.rotate(p.a); c.fillStyle = p.col
        if (p.moneta) { c.beginPath(); c.ellipse(0, 0, p.r, p.r * Math.abs(Math.cos(p.a)) + 1, 0, 0, Math.PI * 2); c.fill(); c.strokeStyle = '#a8761c'; c.lineWidth = devicePixelRatio; c.stroke() }
        else c.fillRect(-p.r / 2, -p.r / 4, p.r, p.r / 2)
        c.restore()
      }
      if (t - t0 < 3600) raf = requestAnimationFrame(passo); else c.clearRect(0, 0, W, H)
    }
    raf = requestAnimationFrame(passo)
    return () => cancelAnimationFrame(raf)
  }, [attiva])
  return <canvas ref={ref} className="slot-festa" aria-hidden="true" />
}

// ---------- Contatore che sale ----------
export function Contatore({ valore }: { valore: number }) {
  const [mostrato, setMostrato] = useState(valore)
  const da = useRef(valore)
  useEffect(() => {
    const inizio = da.current, delta = valore - inizio
    if (delta === 0 || ridotto()) { setMostrato(valore); da.current = valore; return }
    const durata = Math.min(1600, 300 + Math.abs(delta) * 2)
    let raf = 0; const t0 = performance.now()
    const passo = (t: number) => {
      const k = Math.min(1, (t - t0) / durata)
      setMostrato(Math.round(inizio + delta * (1 - Math.pow(1 - k, 3))))
      if (k < 1) raf = requestAnimationFrame(passo); else da.current = valore
    }
    raf = requestAnimationFrame(passo)
    return () => { cancelAnimationFrame(raf); da.current = valore }
  }, [valore])
  return <>{fmt(mostrato)}</>
}

function Simbolo({ s, simboli, dati }: { s: number; simboli: number[]; dati: Dati }) {
  if (s === 8) return <span className="slot-sim slot-sim--jolly"><img src="/specialone-mark.svg" alt="Jolly SpecialOne" /></span>
  if (s === 10) return <span className="slot-sim slot-sim--bustina" aria-label="Bustina">
    <span className="mini-busta"><span className="mini-busta__sald" /><img src="/specialone-mark.svg" alt="" /><span className="mini-busta__sald mini-busta__sald--giu" /></span>
  </span>
  if (s === 9) return <span className="slot-sim slot-sim--coppa" aria-label="Coppa">
    <svg viewBox="0 0 48 48" width="100%" height="100%"><defs><linearGradient id="coppaOro" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stopColor="#fff2b0" /><stop offset=".5" stopColor="#ffcc33" /><stop offset="1" stopColor="#b8801a" /></linearGradient></defs>
      <path d="M15 8h18v8c0 7-4 12-9 12s-9-5-9-12z" fill="url(#coppaOro)" stroke="#7a5310" strokeWidth="1.5" /><path d="M15 11H9c0 6 3 9 7 9M33 11h6c0 6-3 9-7 9" fill="none" stroke="#ffcc33" strokeWidth="2.5" strokeLinecap="round" />
      <path d="M21 28h6v6h-6z" fill="#e0a92a" /><path d="M14 40c0-4 4-6 10-6s10 2 10 6z" fill="url(#coppaOro)" stroke="#7a5310" strokeWidth="1.5" /><path d="M19 13l2 5" stroke="#fff" strokeWidth="2" strokeLinecap="round" opacity=".7" /></svg>
  </span>
  const teamId = simboli[s]
  const t = dati.teamById.get(teamId)
  return <span className={`slot-sim slot-sim--${s <= 2 ? 'basso' : s <= 5 ? 'medio' : 'alto'}`}>
    <Crest value={t?.stemma_url ?? null} imageUrl={dati.crestUrlByTeamId.get(teamId)} size="small" eager />
  </span>
}

type Props = { leagueId: number; dati: Dati; onGiro?: () => void }

export function Casino({ leagueId, dati, onGiro }: Props) {
  const [stato, setStato] = useState<Stato | null>(null)
  const [errore, setErrore] = useState('')
  const [puntata, setPuntata] = useState(10)
  const [griglia, setGriglia] = useState<number[]>(() => Array.from({ length: 15 }, pescaSimbolo))
  const [strisce, setStrisce] = useState<number[][] | null>(null)
  const [inCorsa, setInCorsa] = useState(false)
  const [fermati, setFermati] = useState<boolean[]>([true, true, true, true, true])
  const [esito, setEsito] = useState<Esito | null>(null)
  const [lineaVista, setLineaVista] = useState(0)
  const [crediti, setCrediti] = useState(0)
  const [festa, setFesta] = useState(0)
  const [audio, setAudio] = useState(() => { try { return localStorage.getItem('slot-audio') !== '0' } catch { return true } })
  const [tabella, setTabella] = useState(false)
  const suoni = useSuoni(audio)

  const carica = useCallback(async () => {
    const { data, error } = await supabase.rpc('casino_stato', { p_league_id: leagueId })
    if (error) { setErrore(error.message); return }
    const s = data as Stato
    setStato(s); setCrediti(s.crediti)
  }, [leagueId])
  useEffect(() => { void carica() }, [carica])
  useEffect(() => { try { localStorage.setItem('slot-audio', audio ? '1' : '0') } catch { /* preferenza solo locale */ } }, [audio])

  // Le linee vincenti si accendono una alla volta.
  useEffect(() => {
    if (!esito || esito.vincite.length < 2) return
    const t = window.setInterval(() => setLineaVista((i) => (i + 1) % esito.vincite.length), 1100)
    return () => window.clearInterval(t)
  }, [esito])

  const simboli = stato?.simboli ?? []
  const giriGratis = stato?.giri_gratis ?? 0
  const puoiGirare = !inCorsa && stato != null && (giriGratis > 0 || crediti >= puntata)

  async function gira() {
    if (!puoiGirare) return
    setErrore(''); setEsito(null); setLineaVista(0)
    suoni.leva()
    setInCorsa(true)
    if (giriGratis === 0) setCrediti((c) => c - puntata)
    const { data, error } = await supabase.rpc('casino_gira', { p_league_id: leagueId, p_puntata: puntata })
    if (error) { setErrore(error.message); setInCorsa(false); setCrediti(stato?.crediti ?? 0); return }
    const r = data as Esito
    const veloce = ridotto()
    // Strisce: i tre simboli di adesso in cima, simboli a caso, e il risultato in fondo.
    const nuove = [0, 1, 2, 3, 4].map((c) => [
      ...griglia.slice(c * 3, c * 3 + 3),
      ...Array.from({ length: veloce ? 0 : 14 + c * 4 }, pescaSimbolo),
      ...r.griglia.slice(c * 3, c * 3 + 3),
    ])
    setFermati([false, false, false, false, false])
    setStrisce(nuove)
    const durate = [0, 1, 2, 3, 4].map((c) => (veloce ? 120 : 900 + c * 320))
    let tick = 0
    const ticker = veloce ? 0 : window.setInterval(() => suoni.tick(tick++), 70)
    durate.forEach((d, c) => window.setTimeout(() => {
      suoni.stop(c)
      setFermati((f) => f.map((x, i) => (i === c ? true : x)))
      if (c === 4) {
        window.clearInterval(ticker)
        setGriglia(r.griglia); setStrisce(null); setInCorsa(false); setEsito(r)
        setCrediti(r.crediti)
        setStato((s) => (s ? { ...s, crediti: r.crediti, giri_gratis: r.giri_gratis, max_vincita: r.max_vincita, bustine_gratis: r.bustine_gratis ?? s.bustine_gratis } : s))
        if (r.coppe >= 3 || (r.bustine_vinte ?? 0) > 0) suoni.coppe()
        if (r.vinto >= r.puntata * 20) { suoni.grande(); setFesta((n) => n + 1); for (let i = 0; i < 18; i++) window.setTimeout(() => suoni.moneta(i), 400 + i * 60) }
        else if (r.vinto > 0) suoni.vincita()
        onGiro?.()
      }
    }, d))
  }

  const celleVincenti = useMemo(() => {
    const set = new Set<number>()
    if (!esito) return set
    const v = esito.vincite[lineaVista]
    if (v) LINEE[v.linea].slice(0, v.n).forEach((riga, rullo) => set.add(rullo * 3 + riga))
    if (esito.coppe >= 3) esito.griglia.forEach((s, i) => { if (s === 9) set.add(i) })
    if ((esito.bustine ?? 0) >= 3) esito.griglia.forEach((s, i) => { if (s === 10) set.add(i) })
    return set
  }, [esito, lineaVista])

  const livello = esito ? (esito.vinto >= esito.puntata * 100 ? 'mega' : esito.vinto >= esito.puntata * 20 ? 'grande' : esito.vinto > 0 ? 'piccola' : 'nulla') : 'nulla'
  const lineaAttiva = esito?.vincite[lineaVista]

  if (!stato) return <section className="slot-caricamento">{errore ? <p role="alert">{errore}</p> : <p>Accendo le luci del casinò…</p>}</section>

  return <section className="slot" onPointerDown={() => suoni.sblocca()}>
    <div className="slot-saldo">
      <div><small>I tuoi crediti</small><strong><Contatore valore={crediti} /></strong></div>
      {giriGratis > 0 ? <span className="slot-gratis">🏆 {giriGratis} giri gratis · ×2</span> : <span className="slot-ricarica">+1.000 gratis alle 23:00</span>}
      <button type="button" className="slot-audio" aria-pressed={audio} aria-label={audio ? 'Togli i suoni' : 'Attiva i suoni'} onClick={() => setAudio((a) => !a)}>{audio ? '🔊' : '🔇'}</button>
    </div>

    <div className={`slot-macchina slot-macchina--${livello}${inCorsa ? ' is-in-corsa' : ''}`}>
      <div className="slot-luci" aria-hidden="true">{Array.from({ length: 14 }, (_, i) => <i key={i} style={{ animationDelay: `${(i % 7) * 0.12}s` }} />)}</div>
      <div className="slot-insegna"><span>SLOT</span><b>ONE</b></div>
      <div className="slot-finestra">
        <div className="slot-rulli">
          {[0, 1, 2, 3, 4].map((c) => {
            const striscia = strisce?.[c]
            const lista = striscia ?? griglia.slice(c * 3, c * 3 + 3)
            const corre = Boolean(striscia)
            return <div key={c} className={`slot-rullo${fermati[c] ? '' : ' is-gira'}`}>
              <div className={`slot-nastro${corre ? ' is-corre' : ''}`}
                style={corre ? { ['--passi' as string]: lista.length - 3, ['--durata' as string]: `${ridotto() ? 120 : 900 + c * 320}ms` } : undefined}>
                {lista.map((s, i) => {
                  const idx = c * 3 + i
                  return <div key={i} className={`slot-cella${!corre && celleVincenti.has(idx) ? ' is-vincente' : ''}${!corre && esito && celleVincenti.size > 0 && !celleVincenti.has(idx) ? ' is-spenta' : ''}`}>
                    <Simbolo s={s} simboli={simboli} dati={dati} />
                  </div>
                })}
              </div>
            </div>
          })}
          {lineaAttiva && !inCorsa && <svg className="slot-linea" viewBox="0 0 500 300" preserveAspectRatio="none" aria-hidden="true">
            <polyline points={LINEE[lineaAttiva.linea].map((riga, rullo) => `${rullo * 100 + 50},${riga * 100 + 50}`).join(' ')}
              stroke={COLORI_LINEE[lineaAttiva.linea]} />
          </svg>}
        </div>
        {esito && (esito.vinto > 0 || (esito.bustine_vinte ?? 0) > 0) && !inCorsa && <div className={`slot-vinto slot-vinto--${livello}`} role="status">
          {livello === 'mega' && <em>MEGA WIN</em>}{livello === 'grande' && <em>BIG WIN</em>}
          {esito.vinto > 0 && <strong>+<Contatore valore={esito.vinto} /></strong>}
          {(esito.bustine_vinte ?? 0) > 0 && <span className="slot-vinto__bustina">🎁 {esito.bustine_vinte === 1 ? 'BUSTINA IN REGALO!' : `${esito.bustine_vinte} BUSTINE IN REGALO!`}</span>}
          {esito.nuovi_gratis > 0 && <span>🏆 {esito.nuovi_gratis} giri gratis!</span>}
        </div>}
      </div>
      <Festa key={festa} attiva={festa > 0} />
    </div>

    <p className="slot-messaggio" role="status">
      {errore ? <span className="slot-errore">{errore}</span>
        : inCorsa ? 'Buona fortuna…'
        : esito && (esito.bustine_vinte ?? 0) > 0 ? `Hai vinto ${esito.bustine_vinte === 1 ? 'una bustina' : `${esito.bustine_vinte} bustine`} per l'album: la trovi in Altro › Album.`
        : esito ? (esito.vinto > 0 ? (lineaAttiva ? `Linea ${lineaAttiva.linea + 1}: ${lineaAttiva.n} simboli, +${fmt(lineaAttiva.vinto)}` : `Coppe: +${fmt(esito.scatter)}`) : 'Niente stavolta. Ritenta!')
        : giriGratis > 0 ? 'Hai dei giri gratis: tutte le vincite valgono doppio.' : 'Scegli la puntata e tira la leva.'}
    </p>

    <div className="slot-comandi">
      <div className="slot-puntate" role="group" aria-label="Puntata">
        {PUNTATE.map((p) => <button key={p} type="button" className={puntata === p ? 'is-scelta' : ''} aria-pressed={puntata === p} disabled={inCorsa || giriGratis > 0} onClick={() => setPuntata(p)}>{p}</button>)}
      </div>
      <button type="button" className="slot-gira" disabled={!puoiGirare} onClick={() => void gira()}>
        <span>{giriGratis > 0 ? 'GRATIS' : 'GIRA'}</span><small>{giriGratis > 0 ? `${stato.puntata_gratis ?? puntata} ×2` : `${puntata} crediti`}</small>
      </button>
    </div>

    <section className="slot-pannello">
      <button type="button" className="slot-pannello__tasto" aria-expanded={tabella} onClick={() => setTabella((v) => !v)}>Tabella dei premi <span aria-hidden="true">{tabella ? '−' : '+'}</span></button>
      {tabella && <div className="slot-premi">
        <p>Vinci quando su una <b>linea</b> escono <b>3, 4 o 5 stemmi uguali</b> consecutivi, partendo dal <b>primo rullo a sinistra</b>. I premi qui sotto sono in crediti <b>con la tua puntata di {puntata}</b>: se cambi puntata cambiano anche loro. Se escono più linee vincenti, si sommano.</p>
        {([['alto', [6, 7]], ['medio', [3, 4, 5]], ['basso', [0, 1, 2]]] as Array<[string, number[]]>).map(([fascia, idx]) => <div key={fascia} className="slot-premi__riga">
          <span className="slot-premi__simboli">{idx.map((i) => <span key={i}><Simbolo s={i} simboli={simboli} dati={dati} /></span>)}</span>
          <span className="slot-premi__valori">{(stato.album ? PAGA_ALBUM : PAGA_BASE)[fascia].map((v, k) => <b key={k}>{k + 3} uguali <i>{fmt(v * puntata / 10)}</i></b>)}</span>
        </div>)}
        <div className="slot-premi__riga"><span className="slot-premi__simboli"><span><Simbolo s={8} simboli={simboli} dati={dati} /></span></span><span className="slot-premi__testo"><b>Jolly</b>: vale come qualsiasi stemma e aiuta a completare le linee. Cinque jolly sulla stessa linea: <b>{fmt(400 * puntata / 10)}</b> crediti.</span></div>
        {stato.album && <div className="slot-premi__riga"><span className="slot-premi__simboli"><span><Simbolo s={10} simboli={simboli} dati={dati} /></span></span><span className="slot-premi__testo"><b>Bustina</b>: conta ovunque, come la coppa. 3 bustine: <b>una bustina gratis</b> per l'album; 4: due; 5: tre. Le trovi in Altro › Album.</span></div>}
        <div className="slot-premi__riga"><span className="slot-premi__simboli"><span><Simbolo s={9} simboli={simboli} dati={dati} /></span></span><span className="slot-premi__testo"><b>Coppa</b>: conta in qualsiasi posizione, anche fuori dalle linee. 3 coppe: <b>{fmt(2 * puntata)}</b> crediti e <b>8 giri gratis</b>; 4 coppe: {fmt(5 * puntata)} e 12 giri; 5 coppe: {fmt(20 * puntata)} e 20 giri. Nei giri gratis non paghi e le vincite valgono doppio.</span></div>
        <p>Le <b>linee</b> sono 10: le tre righe orizzontali più sette percorsi a zig-zag. Quando vinci, la linea si illumina sui rulli. Gli stemmi cambiano a ogni giornata e pagano di più le squadre meglio piazzate in classifica (prima riga). Ogni giro lo estrae il server.</p>
      </div>}
    </section>

  </section>
}
