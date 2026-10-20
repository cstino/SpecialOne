import { useCallback, useEffect, useRef, useState, type ReactNode } from 'react'
import { supabase } from '../lib/supabase'
import { useMusica } from '../lib/musicaCasino'
import type { useSeasonData } from '../lib/useSeasonData'
import { Contatore, Festa, fmt, ridotto, useSuoni } from './Casino'
import { Crest } from './Crest'

// BetOne Casino' › AviatOne LIVE, l'Aviator a tema SpecialOne (supabase/migrations/20261020140000_aviatone_live.sql).
// Un solo aereo per lega, uguale per tutti: 7 s per puntare, volo, crash, 3 s di pausa, giro successivo.
// Il moltiplicatore dipende solo dall'orologio del SERVER (m = e^(0,2·t), velocita' dell'Aviator vero); il crash e' segreto finche' l'aereo non
// vola via. La pagina chiede lo stato ogni mezzo secondo e disegna; incassi e crash li decide il server.

type Dati = ReturnType<typeof useSeasonData>
const K = 0.2
const moltAl = (secondi: number) => Math.min(1000, Math.floor(Math.exp(K * Math.max(0, secondi)) * 100) / 100)
const fx = (m: number) => `${m.toFixed(2)}×`
const AUTO = [1.1, 1.2, 1.3, 1.5, 1.75, 2, 2.5, 3, 4, 5, 7.5, 10, 15, 20, 25, 50, 100, 250, 500, 1000]
const FICHE = [10, 20, 50, 100]
const coloreCrash = (c: number) => (c < 2 ? '#3fb4ff' : c < 10 ? '#9b5cff' : '#e8399a')
// Il numero grande in volo prende gli stessi colori dello storico (piu' chiari, per leggerli sul viola).
const coloreMolt = (m: number) => (m < 2 ? '#5cc4ff' : m < 10 ? '#c49bff' : '#ff5cb8')

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

type Giocata = { team_id: number; puntata: number; incassato: number | null; vinto: number; mia: boolean; auto: number | null }
type Giro = { id: number; apre: number; parte: number; finito: boolean; crash: number | null }
type Stato = { adesso: number; giro: Giro; giocate: Giocata[]; crediti: number; storia: number[]; mio_incasso?: { giro: number; molt: number; vinto: number } | null }
type Fase = 'puntate' | 'volo' | 'esploso'
type Prenotata = { puntata: number; auto: number | null }

export function AviatOne({ leagueId, dati }: { leagueId: number; dati: Dati }) {
  const [stato, setStato] = useState<Stato | null>(null)
  const [fase, setFase] = useState<Fase>('puntate')
  const [puntata, setPuntata] = useState(50)
  const [autoOn, setAutoOn] = useState(false)
  const [auto, setAuto] = useState(2)
  const [prenotata, setPrenotata] = useState<Prenotata | null>(null)
  const [errore, setErrore] = useState('')
  const [invio, setInvio] = useState(false)
  const [festa, setFesta] = useState(0)
  const [avviso, setAvviso] = useState('')
  const [audio, setAudio] = useState(() => { try { return localStorage.getItem('slot-audio') !== '0' } catch { return true } })
  const suoni = useSuoni(audio)
  const sbloccaMusica = useMusica('aviat', audio)
  const suoniRef = useRef(suoni); suoniRef.current = suoni

  const tela = useRef<HTMLCanvasElement>(null)
  const scritta = useRef<HTMLDivElement>(null)
  const barra = useRef<HTMLDivElement>(null)
  const valoreIncassa = useRef<HTMLSpanElement | null>(null)
  const scarto = useRef(0)               // orologio del server - orologio del telefono (ms)
  const statoRef = useRef<Stato | null>(null)
  const faseRef = useRef<Fase>('puntate')
  const esplosoAl = useRef(0)
  const prenotataRef = useRef<Prenotata | null>(null)
  const inAttesa = useRef(false)

  useEffect(() => { prenotataRef.current = prenotata }, [prenotata])
  useEffect(() => { try { localStorage.setItem('slot-audio', audio ? '1' : '0') } catch { /* preferenza solo locale */ } }, [audio])
  const oraServer = () => Date.now() + scarto.current

  const esplodi = () => { esplosoAl.current = performance.now(); faseRef.current = 'esploso'; setFase('esploso'); suoniRef.current.stop(0) }

  // Nuovo stato dal server: fasi del giro, suoni, incassi, prenotazione per il volo successivo.
  const applica = useCallback((arrivato: Stato, t0: number, t1: number) => {
    scarto.current = arrivato.adesso - (t0 + t1) / 2
    const prima = statoRef.current
    const nuovoGiro = !prima || prima.giro.id !== arrivato.giro.id
    // Una risposta partita prima del crash non deve cancellare il crash gia' avvisato da aviatone-volo.
    const s = !nuovoGiro && prima && prima.giro.crash != null && arrivato.giro.crash == null ? { ...arrivato, giro: prima.giro } : arrivato
    const miaPrima = prima && !nuovoGiro ? prima.giocate.find((q) => q.mia) : undefined
    const mia = s.giocate.find((q) => q.mia)
    if (mia?.incassato != null && miaPrima && miaPrima.incassato == null) {
      suoniRef.current.vincita()
      if (mia.vinto >= mia.puntata * 20) { suoniRef.current.grande(); setFesta((n) => n + 1) }
    }
    if (prima && !nuovoGiro) {
      const nuoviIncassi = s.giocate.filter((q) => !q.mia && q.incassato != null).length - prima.giocate.filter((q) => !q.mia && q.incassato != null).length
      if (nuoviIncassi > 0) suoniRef.current.moneta(nuoviIncassi)
    }
    if (s.giro.crash != null && faseRef.current !== 'esploso') {
      esplodi()
    } else if (s.giro.crash == null && nuovoGiro) {
      faseRef.current = 'puntate'; setFase('puntate')
    }
    statoRef.current = s; setStato(s)
  }, [])

  const chiedi = useCallback(async (rpc: string, args: Record<string, unknown> = {}) => {
    const t0 = Date.now()
    const { data, error } = await supabase.rpc(rpc, { p_league_id: leagueId, ...args })
    const t1 = Date.now()
    if (error) { setErrore(error.message); return null }
    applica(data as Stato, t0, t1)
    return data as Stato
  }, [leagueId, applica])

  // Il giro della lega si segue chiedendo lo stato ogni mezzo secondo (si ferma se l'app e' in secondo piano).
  useEffect(() => {
    let vivo = true
    const giro = async () => {
      if (!vivo || inAttesa.current || document.hidden) return
      inAttesa.current = true
      const s = await chiedi('casino_av_live')
      inAttesa.current = false
      // Puntata prenotata durante il volo: si piazza appena si aprono le puntate del giro dopo.
      const p = prenotataRef.current
      if (s && p && !s.giro.finito && s.adesso < s.giro.parte - 400 && !s.giocate.some((q) => q.mia)) {
        setPrenotata(null); prenotataRef.current = null
        await chiedi('casino_av_punta', { p_puntata: p.puntata, p_auto: p.auto })
      }
    }
    void giro()
    const t = window.setInterval(() => void giro(), 500)
    return () => { vivo = false; window.clearInterval(t) }
  }, [chiedi])

  // Decollo: la fase passa a "volo" sull'orologio (allineato al server), senza aspettare la risposta successiva.
  useEffect(() => {
    if (fase !== 'puntate' || !stato) return
    const resto = stato.giro.parte - oraServer()
    const t = window.setTimeout(() => { if (faseRef.current === 'puntate' && statoRef.current?.giro.id === stato.giro.id) { faseRef.current = 'volo'; setFase('volo'); suoniRef.current.leva() } }, Math.max(0, resto))
    return () => window.clearTimeout(t)
  }, [fase, stato?.giro.id]) // eslint-disable-line react-hooks/exhaustive-deps

  // Durante il volo si aspetta l'avviso del crash dalla funzione aviatone-volo, che risponde nell'istante esatto in cui
  // l'aereo vola via (il controllo ogni mezzo secondo arriverebbe fino a 0,6 s dopo e il numero salirebbe oltre il crash).
  useEffect(() => {
    if (fase !== 'volo' || !stato) return
    const id = stato.giro.id
    let vivo = true
    void (async () => {
      for (let tentativi = 0; vivo && tentativi < 20; tentativi++) {
        const { data, error } = await supabase.functions.invoke('aviatone-volo', { body: { giro: id } })
        if (!vivo || error || !data) return   // in caso di problemi resta il controllo ogni mezzo secondo
        if (data.finito) {
          const s = statoRef.current
          if (s && s.giro.id === id && faseRef.current !== 'esploso') {
            const nuovo = { ...s, giro: { ...s.giro, finito: true, crash: Number(data.crash) } }
            statoRef.current = nuovo; setStato(nuovo); esplodi()
          }
          return
        }
      }
    })()
    return () => { vivo = false }
  }, [fase, stato?.giro.id]) // eslint-disable-line react-hooks/exhaustive-deps

  // ---------- Disegno ----------
  const caricato = stato != null
  useEffect(() => {
    const cv = tela.current; if (!cv) return
    const c = cv.getContext('2d'); if (!c) return
    const aereo = new Image(); aereo.src = AEREO_URL
    const logo = new Image(); logo.src = '/specialone-mark.svg'
    // Logo scuro per la coda oro (il logo originale e' bianco e non si leggeva): lo si ricolora una volta su una tela a parte.
    let logoScuro: HTMLCanvasElement | null = null
    logo.onload = () => {
      const t = document.createElement('canvas'); t.width = t.height = 96
      const x = t.getContext('2d'); if (!x) return
      x.drawImage(logo, 0, 0, 96, 96); x.globalCompositeOperation = 'source-in'; x.fillStyle = '#3a1670'; x.fillRect(0, 0, 96, 96)
      logoScuro = t
    }
    let raf = 0, W = 0, H = 0
    const misura = () => { const dpr = Math.min(2, devicePixelRatio || 1); W = cv.offsetWidth; H = cv.offsetHeight; cv.width = W * dpr; cv.height = H * dpr; c.setTransform(dpr, 0, 0, dpr, 0, 0) }
    misura()
    const ro = new ResizeObserver(misura); ro.observe(cv)
    const fermo = ridotto()

    const disegnaAereo = (x: number, y: number, ang: number, t: number) => {
      const w = Math.min(96, W * 0.24), h = w / 2
      c.save(); c.translate(x, y); c.rotate(ang)
      if (aereo.complete && aereo.naturalWidth) c.drawImage(aereo, -w * 0.9, -h * 0.55, w, h)
      // centrato sulla deriva di coda (nel disegno 120×60 sta intorno a x 15, y 19)
      if (logoScuro) { const l = w * 0.085; c.drawImage(logoScuro, -w * 0.9 + w * 0.13 - l / 2, -h * 0.55 + h * 0.33 - l / 2, l, l) }
      const s = Math.abs(Math.sin(t / 30))
      c.fillStyle = 'rgba(255,241,176,.75)'
      c.beginPath(); c.ellipse(-w * 0.9 + w * 0.93, -h * 0.55 + h * 0.54, 1.6, h * 0.42 * (0.3 + 0.7 * s), 0, 0, Math.PI * 2); c.fill()
      c.restore()
    }

    const passo = (adesso: number) => {
      const f = faseRef.current, s = statoRef.current
      c.clearRect(0, 0, W, H)
      const g = c.createRadialGradient(0, H, 0, 0, H, Math.max(W, H) * 1.3)
      g.addColorStop(0, '#3a1466'); g.addColorStop(1, '#0d0518')
      c.fillStyle = g; c.fillRect(0, 0, W, H)
      c.save(); c.translate(0, H); c.rotate(fermo ? 0 : (adesso / 9000) % (Math.PI * 2))
      c.fillStyle = 'rgba(155,92,255,.07)'
      for (let i = 0; i < 24; i++) { c.beginPath(); c.moveTo(0, 0); c.arc(0, 0, Math.max(W, H) * 1.6, i * Math.PI / 12, i * Math.PI / 12 + Math.PI / 30); c.closePath(); c.fill() }
      c.restore()

      const pad = 14, base = H - 18, sinistra = 18
      c.fillStyle = 'rgba(255,255,255,.25)'
      for (let i = 0; i < 10; i++) { c.beginPath(); c.arc(sinistra + i * (W - sinistra - pad) / 9, H - 7, 1.5, 0, Math.PI * 2); c.fill() }
      for (let i = 0; i < 6; i++) { c.beginPath(); c.arc(7, base - i * (base - pad) / 5, 1.5, 0, Math.PI * 2); c.fill() }

      let testo = '', colore = '#fff', avanzamento = -1
      if (!s || f === 'puntate') {
        disegnaAereo(sinistra + Math.min(96, W * 0.24) * 0.95, base - 6, 0, adesso)
        if (s) {
          const resto = Math.max(0, s.giro.parte - oraServer())
          testo = `${Math.ceil(resto / 1000)}`
          avanzamento = 1 - resto / Math.max(1, s.giro.parte - s.giro.apre)
        }
      } else {
        const crash = s.giro.crash
        const t = f === 'volo' ? (oraServer() - s.giro.parte) / 1000 : Math.log(Math.max(1, crash ?? 1)) / K
        const m = f === 'volo' ? moltAl(t) : (crash ?? 1)
        const maxT = Math.max(9, t * 1.18), maxM = Math.max(1.8, m * 1.22)
        const px = (x: number) => sinistra + (x / maxT) * (W - sinistra - pad)
        const py = (mm: number) => base - ((mm - 1) / (maxM - 1)) * (base - pad)
        const n = 60
        const curva = () => { c.beginPath(); c.moveTo(px(0), py(1)); for (let i = 1; i <= n; i++) { const x = t * i / n; c.lineTo(px(x), py(Math.min(m, Math.exp(K * x)))) } }
        const xt = px(t), yt = py(m)
        curva(); c.lineTo(xt, base); c.lineTo(px(0), base); c.closePath()
        const ga = c.createLinearGradient(0, yt, 0, base); ga.addColorStop(0, 'rgba(155,92,255,.55)'); ga.addColorStop(1, 'rgba(155,92,255,.05)')
        c.fillStyle = ga; c.fill()
        // bagliore finto con una seconda linea larga e trasparente (lo shadowBlur pesava troppo sui telefoni meno potenti)
        curva(); c.lineJoin = 'round'; c.strokeStyle = 'rgba(246,196,83,.22)'; c.lineWidth = 9; c.stroke()
        c.strokeStyle = '#f6c453'; c.lineWidth = 3.5; c.stroke()
        const pend = Math.atan2(py(Math.exp(K * Math.max(0, t - 0.3))) - yt, xt - px(Math.max(0, t - 0.3)))
        if (f === 'volo') {
          disegnaAereo(xt, yt + (fermo ? 0 : Math.sin(adesso / 400) * 3), Math.max(-0.6, Math.min(0, pend)), adesso)
          testo = fx(m); colore = coloreMolt(m)
          if (valoreIncassa.current) valoreIncassa.current.textContent = fmt(Math.floor((s.giocate.find((q) => q.mia)?.puntata ?? 0) * m))
        } else {
          const dt = adesso - esplosoAl.current
          if (dt < 900) disegnaAereo(xt + dt * 0.7, yt - dt * 0.45, -0.5, adesso)
          testo = fx(m); colore = '#ff4d5e'
        }
      }
      if (scritta.current) {
        const numero = scritta.current.querySelector('b'); if (numero && numero.textContent !== testo) numero.textContent = testo
        scritta.current.style.color = colore
      }
      if (barra.current) barra.current.style.transform = `scaleX(${Math.max(0, Math.min(1, avanzamento))})`
      raf = requestAnimationFrame(passo)
    }
    raf = requestAnimationFrame(passo)
    return () => { cancelAnimationFrame(raf); ro.disconnect() }
  }, [caricato])

  // ---------- Azioni ----------
  async function punta() {
    if (invio) return
    setErrore('')
    if (fase !== 'puntate') { setPrenotata({ puntata, auto: autoOn ? auto : null }); return }
    setInvio(true); await chiedi('casino_av_punta', { p_puntata: puntata, p_auto: autoOn ? auto : null }); setInvio(false)
  }
  async function ritira() { if (invio) return; setInvio(true); await chiedi('casino_av_ritira'); setInvio(false) }
  // Il tocco arriva sia come pointerdown sia come click: una sola richiesta per volo.
  const incassoMandato = useRef<number | null>(null)
  async function incassa() {
    const id = statoRef.current?.giro.id ?? null
    if (incassoMandato.current === id) return
    incassoMandato.current = id
    const tocco = Math.round(oraServer())   // solo per misurare il ritardo di rete: il server paga all'orario di arrivo
    setInvio(true)
    const r = await chiedi('casino_av_incassa_live', { p_tocco: tocco })
    setInvio(false)
    // Incasso valido al momento del tocco: se la risposta arriva a volo gia' finito, l'esito si mostra qui.
    const inc = r?.mio_incasso
    if (inc && inc.giro !== r?.giro.id) {
      suoni.vincita(); setAvviso(`Incassata a ${fx(inc.molt)}: +${fmt(inc.vinto)} crediti!`)
      window.setTimeout(() => setAvviso(''), 5000)
    } else if (!inc && r && id === r.giro.id && r.giro.crash != null && r.giocate.find((q) => q.mia)?.incassato == null) {
      setAvviso('Troppo tardi: l\'aereo era già volato via quando hai toccato.'); window.setTimeout(() => setAvviso(''), 5000)
    }
  }

  if (!stato) return <section className="slot-caricamento">{errore ? <p role="alert">{errore}</p> : <p>Accendo i motori…</p>}</section>

  const mia = stato.giocate.find((q) => q.mia)
  const crediti = stato.crediti
  const bloccati = fase !== 'puntate' || mia != null
  const puntatoTot = stato.giocate.reduce((t, q) => t + q.puntata, 0)
  const messaggio = errore ? <span className="slot-errore">{errore}</span>
    : avviso ? avviso
    : fase === 'puntate' ? (mia ? `Sei a bordo con ${fmt(mia.puntata)} crediti${mia.auto ? `, incasso automatico a ${fx(mia.auto)}` : ''}.` : 'Puntate aperte: sali a bordo prima del decollo!')
      : fase === 'volo' ? (mia ? (mia.incassato != null ? `Incassato a ${fx(mia.incassato)}: +${fmt(mia.vinto)} crediti!` : 'Incassa prima che voli via!') : prenotata ? 'Puntata prenotata per il prossimo volo.' : 'Volo in corso: puoi prenotare la puntata per il prossimo.')
        : (mia ? (mia.incassato != null ? `Volato via a ${fx(stato.giro.crash ?? 1)}. Hai incassato +${fmt(mia.vinto)} crediti.` : `Volato via a ${fx(stato.giro.crash ?? 1)}! Puntata persa.`) : `Volato via a ${fx(stato.giro.crash ?? 1)}.`)

  let azione: ReactNode
  if (fase === 'puntate' && mia) azione = <button type="button" className="av-azione av-azione--annulla" disabled={invio} onClick={() => void ritira()}><small>A BORDO</small><b>Annulla</b></button>
  else if (fase === 'volo' && mia && mia.incassato == null) azione = <button type="button" className="av-azione av-azione--incassa" disabled={invio} onPointerDown={(e) => { e.preventDefault(); void incassa() }} onClick={() => void incassa()}><small>INCASSA</small><b><span ref={valoreIncassa}>{fmt(mia.puntata)}</span></b>{mia.auto != null && <i>auto a {fx(mia.auto)}</i>}</button>
  else if (mia && mia.incassato != null) azione = <div className="av-azione av-azione--vinto"><small>INCASSATA</small><b>{fx(mia.incassato)}</b><i>+{fmt(mia.vinto)}</i></div>
  else if (fase === 'esploso' && mia && invio) azione = <div className="av-azione av-azione--perso"><small>INCASSO</small><b>Verifico…</b></div>
  else if (fase === 'esploso' && mia) azione = <div className="av-azione av-azione--perso"><small>VOLATO VIA</small><b>Persa</b></div>
  else if (prenotata) azione = <button type="button" className="av-azione av-azione--annulla" onClick={() => setPrenotata(null)}><small>PRENOTATA</small><b>Annulla</b></button>
  else azione = <button type="button" className="av-azione av-azione--punta" disabled={puntata > crediti} onClick={() => void punta()}>
    <small>{fase === 'puntate' ? 'PUNTA' : 'PROSSIMO VOLO'}</small><b>{fmt(puntata)}</b>
  </button>

  return <section className="av" onPointerDown={() => { suoni.sblocca(); sbloccaMusica() }}>
    <div className="slot-saldo">
      <div><small>I tuoi crediti</small><strong><Contatore valore={crediti} /></strong></div>
      <span className="slot-ricarica av-dal-vivo"><i aria-hidden="true" />LIVE</span>
      <button type="button" className="slot-audio" aria-pressed={audio} aria-label={audio ? 'Togli i suoni' : 'Attiva i suoni'} onClick={() => setAudio((a) => !a)}>{audio ? '🔊' : '🔇'}</button>
    </div>

    <ol className="av-storia" aria-label="Ultimi voli della lega">
      {stato.storia.length === 0 ? <li className="av-storia__vuota">Ancora nessun volo precedente</li>
        : stato.storia.map((c, i) => <li key={i} style={{ color: coloreCrash(Number(c)) }}>{fx(Number(c))}</li>)}
    </ol>

    <div className="av-cielo">
      <div className="av-insegna"><img src="/specialone-mark.svg" alt="" /><span>AVIAT</span><b>ONE</b></div>
      <canvas ref={tela} className="av-tela" aria-hidden="true" />
      <div ref={scritta} className={`av-molt av-molt--${fase}`} aria-live="off">
        {fase === 'esploso' && <em>VOLATO VIA!</em>}
        {fase === 'puntate' && <em className="av-molt__pronto">Decollo tra</em>}
        <b />
        {fase === 'puntate' && <div className="av-molt__barra"><div ref={barra} /></div>}
      </div>
      <Festa key={festa} attiva={festa > 0} />
    </div>

    <p className="slot-messaggio" role="status">{messaggio}</p>

    <div className="av-pannello is-attivo">
      <div className="av-pannello__corpo">
        <div className="av-importo">
          <button type="button" aria-label="Meno" disabled={bloccati || puntata <= 10} onClick={() => setPuntata((x) => Math.max(10, x - 10))}>−</button>
          <b>{fmt(puntata)}</b>
          <button type="button" aria-label="Più" disabled={bloccati || puntata >= 500} onClick={() => setPuntata((x) => Math.min(500, x + 10))}>+</button>
        </div>
        <div className="av-fiche">{FICHE.map((f) => <button key={f} type="button" disabled={bloccati} aria-pressed={puntata === f} className={`fiche-casino fiche-casino--${f}${puntata === f ? ' is-scelta' : ''}`} onClick={() => setPuntata(f)}><span>{f}</span></button>)}</div>
        <div className="av-auto">
          <button type="button" role="switch" aria-checked={autoOn} className="av-interruttore av-interruttore--piccolo" disabled={bloccati} onClick={() => setAutoOn((x) => !x)}><i /></button>
          <span>Incasso auto</span>
          <button type="button" aria-label="Meno" disabled={bloccati || !autoOn || auto <= AUTO[0]} onClick={() => setAuto((x) => AUTO[Math.max(0, AUTO.indexOf(x) - 1)])}>−</button>
          <b className={autoOn ? '' : 'is-spento'}>{fx(auto)}</b>
          <button type="button" aria-label="Più" disabled={bloccati || !autoOn || auto >= 1000} onClick={() => setAuto((x) => AUTO[Math.min(AUTO.length - 1, AUTO.indexOf(x) + 1)])}>+</button>
        </div>
      </div>
      {azione}
    </div>

    <section className="av-giocate">
      <header><h2>Puntate del volo</h2><span>{stato.giocate.length} a bordo · {fmt(puntatoTot)} crediti</span></header>
      {stato.giocate.length === 0 ? <p className="bet-nota">Nessuno a bordo per ora.</p> : <ol>
        {stato.giocate.map((q, i) => {
          const t = dati.teamById.get(q.team_id)
          const persa = fase === 'esploso' && q.incassato == null
          return <li key={`${q.team_id}-${i}`} className={`${q.mia ? 'is-mia' : ''}${q.incassato != null ? ' is-incassata' : ''}${persa ? ' is-persa' : ''}`}>
            <span className="bet-giocatori__stemma"><Crest value={t?.stemma_url ?? null} imageUrl={dati.crestUrlByTeamId.get(q.team_id)} size="small" /></span>
            <span className="av-giocate__nome">{t?.nome ?? '—'}</span>
            <span className="av-giocate__puntata">{fmt(q.puntata)}</span>
            <span className="av-giocate__esito">{q.incassato != null ? <><b>{fx(q.incassato)}</b><i>+{fmt(q.vinto)}</i></> : persa ? '—' : ''}</span>
          </li>
        })}
      </ol>}
    </section>

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
      <p>AviatOne è <b>live</b>: l'aereo è uno solo per tutta la lega e tutti vedono lo stesso volo. I voli si susseguono senza sosta: <b>7 secondi per puntare</b>, poi il decollo, poi l'aereo vola via e dopo 3 secondi si riparte.</p>
      <p>Scegli quanto puntare (da 10 a 500 crediti) e premi <b>PUNTA</b> prima del decollo; finché le puntate sono aperte puoi annullare. Se il volo è già partito, puoi <b>prenotare</b> la puntata per il volo successivo.</p>
      <p>Durante il volo il moltiplicatore sale: premi <b>INCASSA</b> quando vuoi e vinci la puntata per il moltiplicatore del momento in cui hai toccato (vale il tocco, anche se la connessione è lenta). Se l'aereo vola via prima del tuo tocco, la puntata è persa. Con l'<b>incasso automatico</b> la puntata si incassa da sola appena il moltiplicatore arriva al valore scelto.</p>
      <p>Il moltiplicatore cresce sempre alla stessa velocità (2× dopo circa 3,5 secondi, 10× dopo circa 11, 100× dopo circa 23). Il punto in cui l'aereo vola via lo estrae il server prima che si chiudano le puntate e nessuno lo vede prima. In media si recupera circa il 97% di quello che si punta.</p>
      <p>Sotto vedi chi è a bordo, quanto ha puntato e a che moltiplicatore incassa. In alto gli ultimi voli della lega: in azzurro sotto 2×, in viola fino a 10×, in rosa sopra.</p>
    </div>}
  </>
}
