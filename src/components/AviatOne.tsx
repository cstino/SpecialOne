import { useCallback, useEffect, useRef, useState } from 'react'
import { supabase } from '../lib/supabase'
import { Contatore, Festa, fmt, ridotto, useSuoni } from './Casino'

// BetOne Casino' › AviatOne, l'Aviator a tema SpecialOne (supabase/migrations/20261020110000_casino_aviatone.sql).
// Volo personale: una puntata, con incasso automatico opzionale (la seconda puntata dell'Aviator e' stata tolta il 20/10/2026). Il moltiplicatore dipende solo dal tempo
// sull'orologio del SERVER (m = e^(0,075·t)); il punto in cui l'aereo vola via e' segreto e lo scopre il server.
// Qui si disegna soltanto: il client chiede al server ogni 0,4 s come sta andando il volo.

const K = 0.075
const moltAl = (secondi: number) => Math.min(1000, Math.floor(Math.exp(K * Math.max(0, secondi)) * 100) / 100)
const fx = (m: number) => `${m.toFixed(2)}×`
const AUTO = [1.1, 1.2, 1.3, 1.5, 1.75, 2, 2.5, 3, 4, 5, 7.5, 10, 15, 20, 25, 50, 100, 250, 500, 1000]
const FICHE = [10, 20, 50, 100]
const coloreCrash = (c: number) => (c < 2 ? '#3fb4ff' : c < 10 ? '#9b5cff' : '#e8399a')

// L'aereo (anche per la copertina): fusoliera viola SpecialOne, ali oro, muso verso destra.
export const AEREO_SVG = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 120 60">
<defs><linearGradient id="f" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#b98cff"/><stop offset=".55" stop-color="#7b3fe4"/><stop offset="1" stop-color="#3d1680"/></linearGradient>
<linearGradient id="o" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fff1b0"/><stop offset=".5" stop-color="#f6c453"/><stop offset="1" stop-color="#a8761c"/></linearGradient></defs>
<path d="M12 31 L5 11 L19 11 L30 28 Z" fill="url(#o)" stroke="#6b4a10" stroke-width="1"/>
<path d="M10 32 C20 21 70 19 96 25 L108 29.5 C111 31 111 34 108 35.5 L96 39 C70 45 20 43 10 32 Z" fill="url(#f)" stroke="#2a0f5c" stroke-width="1.2"/>
<path d="M18 33 L100 33" stroke="#fff" stroke-width="1.6" opacity=".55"/>
<path d="M66 25 C70 16 83 16 87 25 Z" fill="#bfe6ff" stroke="#2a0f5c" stroke-width="1"/>
<path d="M11 34 L2 40 L22 38 Z" fill="url(#o)" stroke="#6b4a10" stroke-width=".8"/>
<path d="M50 35 L37 53 L54 53 L68 36 Z" fill="url(#o)" stroke="#6b4a10" stroke-width="1"/>
<circle cx="109" cy="32.5" r="3.4" fill="url(#o)" stroke="#6b4a10" stroke-width=".8"/>
</svg>`
export const AEREO_URL = `data:image/svg+xml;charset=utf-8,${encodeURIComponent(AEREO_SVG)}`

type Puntata = { puntata: number; auto: number | null; incassato: number | null }
type Volo = { id: number; puntate: Puntata[]; totale: number; vinto: number; finito: boolean; trascorso: number; molt: number; crash: number | null; crediti?: number }
type Pannello = { attivo: boolean; puntata: number; autoOn: boolean; auto: number }
type Fase = 'pronto' | 'volo' | 'esploso'

export function AviatOne({ leagueId }: { leagueId: number }) {
  const [crediti, setCrediti] = useState<number | null>(null)
  const [storia, setStoria] = useState<number[]>([])
  const [pannelli, setPannelli] = useState<Pannello[]>([
    { attivo: true, puntata: 50, autoOn: false, auto: 2 },
  ])
  const [fase, setFase] = useState<Fase>('pronto')
  const [volo, setVolo] = useState<Volo | null>(null)
  const [errore, setErrore] = useState('')
  const [messaggio, setMessaggio] = useState('Scegli le puntate e fai decollare l\'aereo.')
  const [festa, setFesta] = useState(0)
  const [audio, setAudio] = useState(() => { try { return localStorage.getItem('slot-audio') !== '0' } catch { return true } })
  const suoni = useSuoni(audio)
  const suoniRef = useRef(suoni); suoniRef.current = suoni

  const tela = useRef<HTMLCanvasElement>(null)
  const scritta = useRef<HTMLDivElement>(null)
  const valoriIncassa = useRef<Array<HTMLSpanElement | null>>([])
  const faseRef = useRef<Fase>('pronto')
  const inizio = useRef(0)               // performance.now() del decollo (allineato all'orologio del server)
  const crashRef = useRef<number | null>(null)
  const esplosoAl = useRef(0)
  const voloRef = useRef<Volo | null>(null)
  const inAttesa = useRef(false)

  useEffect(() => { faseRef.current = fase }, [fase])
  useEffect(() => { voloRef.current = volo }, [volo])
  useEffect(() => { try { localStorage.setItem('slot-audio', audio ? '1' : '0') } catch { /* preferenza solo locale */ } }, [audio])

  // Allinea l'orologio locale a quello del server: trascorso = secondi di volo quando il server ha risposto.
  const allinea = (trascorso: number, t0: number, t1: number) => { inizio.current = t1 - trascorso * 1000 - (t1 - t0) / 2 }

  const applica = useCallback((v: Volo) => {
    const prima = voloRef.current
    // Incassi nuovi (anche quelli automatici scoperti dal controllo).
    v.puntate.forEach((p, i) => {
      if (p.incassato != null && prima?.puntate[i]?.incassato == null) {
        suoniRef.current.vincita()
        setMessaggio(`Puntata ${i + 1} incassata a ${fx(p.incassato)}: +${fmt(Math.floor(p.puntata * p.incassato))} crediti!`)
      }
    })
    setVolo(v); voloRef.current = v
    if (v.crediti != null) setCrediti(v.crediti)
    if (v.finito && v.crash != null && faseRef.current === 'volo') {
      crashRef.current = v.crash; esplosoAl.current = performance.now()
      faseRef.current = 'esploso'; setFase('esploso')
      setStoria((s) => [v.crash as number, ...s].slice(0, 20))
      const aperte = v.puntate.some((p) => p.incassato == null)
      suoniRef.current.stop(0)
      if (aperte) setMessaggio(v.vinto > 0 ? `Volato via a ${fx(v.crash)}. In tutto +${fmt(v.vinto)} crediti.` : `Volato via a ${fx(v.crash)}!`)
      else setMessaggio(`Volato via a ${fx(v.crash)}. Hai incassato +${fmt(v.vinto)} crediti.`)
      if (v.vinto >= v.totale * 20) { suoniRef.current.grande(); setFesta((n) => n + 1) }
      window.setTimeout(() => { if (faseRef.current === 'esploso') { faseRef.current = 'pronto'; setFase('pronto') } }, ridotto() ? 600 : 2600)
    }
  }, [])

  const carica = useCallback(async () => {
    const t0 = performance.now()
    const { data, error } = await supabase.rpc('casino_av_stato', { p_league_id: leagueId })
    const t1 = performance.now()
    if (error) { setErrore(error.message); return }
    const s = data as { crediti: number; volo: Volo | null; storia: number[] }
    setCrediti(s.crediti); setStoria((s.storia ?? []).map(Number))
    // Volo lasciato in aria (app chiusa): si riprende da dove e'.
    if (s.volo) {
      const pv = s.volo.puntate
      setPannelli((ps) => [
        { ...ps[0], attivo: true, puntata: pv[0].puntata, autoOn: pv[0].auto != null, auto: pv[0].auto ?? ps[0].auto },
      ])
      allinea(s.volo.trascorso, t0, t1); setVolo(s.volo); voloRef.current = s.volo; faseRef.current = 'volo'; setFase('volo'); setMessaggio('Il tuo aereo è ancora in volo!')
    }
  }, [leagueId])
  useEffect(() => { void carica() }, [carica])

  // Controllo del volo ogni 0,4 s (incassi automatici e crash li decide il server).
  useEffect(() => {
    if (fase !== 'volo') return
    const t = window.setInterval(async () => {
      if (inAttesa.current) return
      inAttesa.current = true
      const t0 = performance.now()
      const { data, error } = await supabase.rpc('casino_av_controlla', { p_league_id: leagueId, p_salta: false })
      const t1 = performance.now()
      inAttesa.current = false
      if (error) return
      const v = data as Volo
      if (!v.finito) allinea(v.trascorso, t0, t1)
      applica(v)
    }, 400)
    return () => window.clearInterval(t)
  }, [fase, leagueId, applica])

  // ---------- Disegno ----------
  // Parte quando la tela esiste davvero (durante il caricamento c'e' solo la scritta "Accendo i motori").
  const caricato = crediti != null
  useEffect(() => {
    const cv = tela.current; if (!cv) return
    const c = cv.getContext('2d'); if (!c) return
    const aereo = new Image(); aereo.src = AEREO_URL
    const logo = new Image(); logo.src = '/specialone-mark.svg'
    let raf = 0, W = 0, H = 0
    const misura = () => { const dpr = devicePixelRatio || 1; W = cv.offsetWidth; H = cv.offsetHeight; cv.width = W * dpr; cv.height = H * dpr; c.setTransform(dpr, 0, 0, dpr, 0, 0) }
    misura()
    const ro = new ResizeObserver(misura); ro.observe(cv)
    const fermo = ridotto()

    const disegnaAereo = (x: number, y: number, ang: number, t: number) => {
      const w = Math.min(96, W * 0.24), h = w / 2
      c.save(); c.translate(x, y); c.rotate(ang)
      if (aereo.complete && aereo.naturalWidth) c.drawImage(aereo, -w * 0.9, -h * 0.55, w, h)
      if (logo.complete && logo.naturalWidth) c.drawImage(logo, -w * 0.9 + w * 0.045, -h * 0.55 + h * 0.2, w * 0.12, w * 0.12)
      // elica che gira
      const s = Math.abs(Math.sin(t / 30))
      c.fillStyle = 'rgba(255,241,176,.75)'
      c.beginPath(); c.ellipse(-w * 0.9 + w * 0.93, -h * 0.55 + h * 0.54, 1.6, h * 0.42 * (0.3 + 0.7 * s), 0, 0, Math.PI * 2); c.fill()
      c.restore()
    }

    const passo = (adesso: number) => {
      const f = faseRef.current
      c.clearRect(0, 0, W, H)
      // Raggi che ruotano dal basso a sinistra (come la pista di Aviator), viola SpecialOne.
      const g = c.createRadialGradient(0, H, 0, 0, H, Math.max(W, H) * 1.3)
      g.addColorStop(0, '#3a1466'); g.addColorStop(1, '#0d0518')
      c.fillStyle = g; c.fillRect(0, 0, W, H)
      c.save(); c.translate(0, H); c.rotate(fermo ? 0 : (adesso / 9000) % (Math.PI * 2))
      c.fillStyle = 'rgba(155,92,255,.07)'
      for (let i = 0; i < 24; i++) { c.beginPath(); c.moveTo(0, 0); c.arc(0, 0, Math.max(W, H) * 1.6, i * Math.PI / 12, i * Math.PI / 12 + Math.PI / 30); c.closePath(); c.fill() }
      c.restore()

      const pad = 14, base = H - 18, sinistra = 18
      // puntini degli assi
      c.fillStyle = 'rgba(255,255,255,.25)'
      for (let i = 0; i < 10; i++) { c.beginPath(); c.arc(sinistra + i * (W - sinistra - pad) / 9, H - 7, 1.5, 0, Math.PI * 2); c.fill() }
      for (let i = 0; i < 6; i++) { c.beginPath(); c.arc(7, base - i * (base - pad) / 5, 1.5, 0, Math.PI * 2); c.fill() }

      let testo = '', colore = '#fff'
      if (f === 'pronto') {
        disegnaAereo(sinistra + Math.min(96, W * 0.24) * 0.95, base - 6, 0, adesso)
        testo = ''
      } else {
        const t = f === 'volo' ? (adesso - inizio.current) / 1000 : Math.log(Math.max(1, crashRef.current ?? 1)) / K
        const m = f === 'volo' ? moltAl(t) : (crashRef.current ?? 1)
        const maxT = Math.max(9, t * 1.18), maxM = Math.max(1.8, m * 1.22)
        const px = (s: number) => sinistra + (s / maxT) * (W - sinistra - pad)
        const py = (mm: number) => base - ((mm - 1) / (maxM - 1)) * (base - pad)
        // curva e area sotto
        c.beginPath(); c.moveTo(px(0), py(1))
        const n = 60
        for (let i = 1; i <= n; i++) { const s = t * i / n; c.lineTo(px(s), py(Math.min(m, Math.exp(K * s)))) }
        const xt = px(t), yt = py(m)
        c.lineTo(xt, base); c.lineTo(px(0), base); c.closePath()
        const ga = c.createLinearGradient(0, yt, 0, base); ga.addColorStop(0, 'rgba(155,92,255,.55)'); ga.addColorStop(1, 'rgba(155,92,255,.05)')
        c.fillStyle = ga; c.fill()
        c.beginPath(); c.moveTo(px(0), py(1))
        for (let i = 1; i <= n; i++) { const s = t * i / n; c.lineTo(px(s), py(Math.min(m, Math.exp(K * s)))) }
        c.strokeStyle = '#f6c453'; c.lineWidth = 3.5; c.lineJoin = 'round'; c.shadowColor = 'rgba(246,196,83,.6)'; c.shadowBlur = 10; c.stroke(); c.shadowBlur = 0
        // aereo in punta (in volo ondeggia un po'; quando esplode scappa in alto a destra)
        const pend = Math.atan2(py(Math.exp(K * Math.max(0, t - 0.3))) - yt, xt - px(Math.max(0, t - 0.3)))
        if (f === 'volo') {
          const dondola = fermo ? 0 : Math.sin(adesso / 400) * 3
          disegnaAereo(xt, yt + dondola, Math.max(-0.6, Math.min(0, pend)), adesso)
          testo = fx(m)
        } else {
          const dt = adesso - esplosoAl.current
          if (dt < 900) disegnaAereo(xt + dt * 0.7, yt - dt * 0.45, -0.5, adesso)
          testo = fx(m); colore = '#ff4d5e'
        }
      }
      if (scritta.current) {
        scritta.current.dataset.fase = f
        const numero = scritta.current.querySelector('b'); if (numero && numero.textContent !== testo) numero.textContent = testo
        scritta.current.style.color = colore
      }
      // valori sui bottoni INCASSA
      const v = voloRef.current
      if (f === 'volo' && v) {
        const m = moltAl((adesso - inizio.current) / 1000)
        v.puntate.forEach((p, i) => { const el = valoriIncassa.current[i]; if (el && p.incassato == null) el.textContent = fmt(Math.floor(p.puntata * m)) })
      }
      raf = requestAnimationFrame(passo)
    }
    raf = requestAnimationFrame(passo)
    return () => { cancelAnimationFrame(raf); ro.disconnect() }
  }, [caricato])

  // ---------- Azioni ----------
  const scelte = pannelli.filter((p) => p.attivo)
  const totale = scelte.reduce((s, p) => s + p.puntata, 0)
  const puoiPartire = fase === 'pronto' && crediti != null && scelte.length > 0 && totale <= crediti

  const cambia = (i: number, f: (p: Pannello) => Pannello) => setPannelli((ps) => ps.map((p, k) => (k === i ? f(p) : p)))

  async function decolla() {
    if (!puoiPartire || crediti == null) return
    setErrore(''); suoni.leva()
    const t0 = performance.now()
    const { data, error } = await supabase.rpc('casino_av_parti', { p_league_id: leagueId, p_puntate: scelte.map((p) => ({ puntata: p.puntata, auto: p.autoOn ? p.auto : null })) })
    const t1 = performance.now()
    if (error) { setErrore(error.message); return }
    const v = data as Volo
    allinea(v.trascorso, t0, t1)
    crashRef.current = null
    setVolo(v); voloRef.current = v
    if (v.crediti != null) setCrediti(v.crediti)
    faseRef.current = 'volo'; setFase('volo')
    setMessaggio('Decollo! Incassa prima che voli via.')
  }

  async function incassa(i: number) {
    const v = voloRef.current
    if (fase !== 'volo' || !v || v.puntate[i]?.incassato != null) return
    const { data, error } = await supabase.rpc('casino_av_incassa', { p_league_id: leagueId, p_indice: i })
    if (error) { setErrore(error.message); return }
    applica(data as Volo)
  }

  async function salta() {
    const { data, error } = await supabase.rpc('casino_av_controlla', { p_league_id: leagueId, p_salta: true })
    if (!error) applica(data as Volo)
  }

  if (crediti == null) return <section className="slot-caricamento">{errore ? <p role="alert">{errore}</p> : <p>Accendo i motori…</p>}</section>

  const tutteIncassate = fase === 'volo' && volo != null && volo.puntate.every((p) => p.incassato != null)
  // Durante il volo i pannelli mostrano le puntate davvero giocate (nell'ordine dei pannelli attivi).
  const giocataDi = (i: number) => {
    if (!volo || fase === 'pronto') return null
    const k = pannelli.slice(0, i + 1).filter((p) => p.attivo).length - 1
    return pannelli[i].attivo ? { indice: k, p: volo.puntate[k] } : null
  }

  return <section className="av" onPointerDown={() => suoni.sblocca()}>
    <div className="slot-saldo">
      <div><small>I tuoi crediti</small><strong><Contatore valore={crediti} /></strong></div>
      <span className="slot-ricarica">+1.000 gratis alle 23:00</span>
      <button type="button" className="slot-audio" aria-pressed={audio} aria-label={audio ? 'Togli i suoni' : 'Attiva i suoni'} onClick={() => setAudio((a) => !a)}>{audio ? '🔊' : '🔇'}</button>
    </div>

    {storia.length > 0 && <ol className="av-storia" aria-label="Ultimi voli">
      {storia.map((c, i) => <li key={i} style={{ color: coloreCrash(c) }}>{fx(c)}</li>)}
    </ol>}

    <div className="av-cielo">
      <div className="av-insegna"><img src="/specialone-mark.svg" alt="" /><span>AVIAT</span><b>ONE</b></div>
      <canvas ref={tela} className="av-tela" aria-hidden="true" />
      <div ref={scritta} className="av-molt" aria-live="off">
        {fase === 'esploso' && <em>VOLATO VIA!</em>}
        <b />
        {fase === 'pronto' && <span className="av-molt__pronto">Pronto al decollo</span>}
      </div>
      <Festa key={festa} attiva={festa > 0} />
    </div>

    <p className="slot-messaggio" role="status">{errore ? <span className="slot-errore">{errore}</span> : messaggio}</p>

    <div className="av-pannelli">
      {pannelli.map((p, i) => {
        const g = giocataDi(i)
        const inVolo = fase !== 'pronto'
        return <div key={i} className={`av-pannello${p.attivo ? ' is-attivo' : ''}`}>
          <div className="av-pannello__testa"><span>La tua puntata</span></div>
          <div className="av-pannello__corpo">
            <div className="av-importo">
              <button type="button" aria-label="Meno" disabled={inVolo || p.puntata <= 10} onClick={() => cambia(i, (x) => ({ ...x, puntata: Math.max(10, x.puntata - 10) }))}>−</button>
              <b>{fmt(p.puntata)}</b>
              <button type="button" aria-label="Più" disabled={inVolo || p.puntata >= 500} onClick={() => cambia(i, (x) => ({ ...x, puntata: Math.min(500, x.puntata + 10) }))}>+</button>
            </div>
            <div className="av-fiche">{FICHE.map((f) => <button key={f} type="button" disabled={inVolo} aria-pressed={p.puntata === f} className={`fiche-casino fiche-casino--${f}${p.puntata === f ? ' is-scelta' : ''}`} onClick={() => cambia(i, (x) => ({ ...x, puntata: f }))}><span>{f}</span></button>)}</div>
            <div className="av-auto">
              <button type="button" role="switch" aria-checked={p.autoOn} className="av-interruttore av-interruttore--piccolo" disabled={inVolo} onClick={() => cambia(i, (x) => ({ ...x, autoOn: !x.autoOn }))}><i /></button>
              <span>Incasso auto</span>
              <button type="button" aria-label="Meno" disabled={inVolo || !p.autoOn || p.auto <= AUTO[0]} onClick={() => cambia(i, (x) => ({ ...x, auto: AUTO[Math.max(0, AUTO.indexOf(x.auto) - 1)] }))}>−</button>
              <b className={p.autoOn ? '' : 'is-spento'}>{fx(p.auto)}</b>
              <button type="button" aria-label="Più" disabled={inVolo || !p.autoOn || p.auto >= 1000} onClick={() => cambia(i, (x) => ({ ...x, auto: AUTO[Math.min(AUTO.length - 1, AUTO.indexOf(x.auto) + 1)] }))}>+</button>
            </div>
          </div>
          {g && (g.p?.incassato != null
            ? <div className="av-esito av-esito--vinto">Incassata a {fx(g.p.incassato)} · +{fmt(Math.floor(g.p.puntata * g.p.incassato))}</div>
            : fase === 'volo'
              ? <button type="button" className="av-incassa" onClick={() => void incassa(g.indice)}>
                <small>INCASSA</small><b><span ref={(el) => { valoriIncassa.current[g.indice] = el }}>{fmt(g.p?.puntata ?? 0)}</span></b>
                {g.p?.auto != null && <i>auto a {fx(g.p.auto)}</i>}
              </button>
              : <div className="av-esito av-esito--perso">Persa</div>)}
        </div>
      })}
    </div>

    {fase === 'volo'
      ? <button type="button" className="av-decolla av-decolla--salta" disabled={!tutteIncassate} onClick={() => void salta()}>{tutteIncassate ? 'Fallo volare via' : 'In volo…'}</button>
      : <button type="button" className="av-decolla" disabled={!puoiPartire} onClick={() => void decolla()}>
        <span>DECOLLA</span><small>{fmt(totale)} crediti</small>
      </button>}

    <section className="slot-pannello">
      <AviatOneRegole />
    </section>
  </section>
}

function AviatOneRegole() {
  const [aperte, setAperte] = useState(false)
  return <>
    <button type="button" className="slot-pannello__tasto" aria-expanded={aperte} onClick={() => setAperte((v) => !v)}>Come si gioca <span aria-hidden="true">{aperte ? '−' : '+'}</span></button>
    {aperte && <div className="slot-premi">
      <p>Scegli quanto puntare (da 10 a 500 crediti) e premi <b>DECOLLA</b>. L'aereo parte e il moltiplicatore sale: 1,00×, 1,50×, 2×… finché a un certo punto l'aereo <b>vola via</b>.</p>
      <p>Premi <b>INCASSA</b> quando vuoi: vinci la puntata per il moltiplicatore di quel momento. Se l'aereo vola via prima che incassi, la puntata è persa.</p>
      <p><b>Incasso automatico</b>: se lo accendi, la puntata si incassa da sola appena il moltiplicatore arriva al valore scelto (se l'aereo ci arriva).</p>
      <p>Il moltiplicatore cresce sempre alla stessa velocità (2× dopo circa 9 secondi, 10× dopo circa 31). Il punto in cui l'aereo vola via lo estrae il server al decollo e nessuno lo vede prima: a volte esplode subito, a volte arriva a 100× e oltre. Qualunque strategia tu usi, in media si recupera circa il 94% di quello che si punta.</p>
      <p>In alto ci sono i tuoi ultimi voli: in azzurro sotto 2×, in viola fino a 10×, in rosa sopra.</p>
    </div>}
  </>
}
