import { useCallback, useEffect, useRef, useState } from 'react'
import { supabase } from '../lib/supabase'
import { useMusica } from '../lib/musicaCasino'
import type { useSeasonData } from '../lib/useSeasonData'
import { Contatore, Festa, fmt, ridotto, useSuoni } from './Casino'
import { Crest } from './Crest'
import { ChatCasino } from './ChatCasino'

// BetOne Casino' › RoulettOne LIVE, roulette europea a tema SpecialOne (supabase/migrations/20261109190000_casino_roulettone_live.sql).
// Una sola ruota per lega, uguale per tutti: 20 s per puntare, 9 s di ruota e pallina, 6 s col numero, giro successivo.
// Il numero lo decide il server alla creazione del giro e lo rivela quando la ruota parte; ruota e pallina sono
// disegnate dall'orologio del server, quindi tutti vedono la pallina cadere nello stesso momento.

type Dati = ReturnType<typeof useSeasonData>
type Giro = { id: number; apre: number; chiude: number; esito_il: number; fine: number; regolato: boolean; numero?: number }
type Giocata = { team_id: number; totale: number; mia: boolean; vinto: number | null; puntate?: Record<string, number> | null }
type Stato = { adesso: number; giro: Giro; giocate: Giocata[]; crediti: number; storia: number[] }
type Puntate = Record<string, number>

// Ordine dei numeri sulla ruota europea, in senso orario partendo dallo zero.
const RUOTA = [0, 32, 15, 19, 4, 21, 2, 25, 17, 34, 6, 27, 13, 36, 11, 30, 8, 23, 10, 5, 24, 16, 33, 1, 20, 14, 31, 9, 22, 18, 29, 7, 28, 12, 35, 3, 26]
const ROSSI = new Set([1, 3, 5, 7, 9, 12, 14, 16, 18, 19, 21, 23, 25, 27, 30, 32, 34, 36])
const colore = (n: number) => (n === 0 ? 'verde' : ROSSI.has(n) ? 'rosso' : 'nero')
const FICHE = [10, 20, 50, 100]
const MAX_CASELLA = 500
const MAX_GIRO = 2000
const SPICCHIO = (2 * Math.PI) / 37
const GIRO_RUOTA_MS = 14000   // la ruota fa un giro ogni 14 s, sempre: e' la stessa per tutti perche' dipende dall'ora del server

// Le caselle esterne e quanto pagano (puntata compresa).
const ESTERNE: Array<{ k: string; nome: string; paga: number }> = [
  { k: 'manque', nome: '1-18', paga: 2 }, { k: 'pari', nome: 'Pari', paga: 2 }, { k: 'rosso', nome: 'Rosso', paga: 2 },
  { k: 'nero', nome: 'Nero', paga: 2 }, { k: 'dispari', nome: 'Dispari', paga: 2 }, { k: 'passe', nome: '19-36', paga: 2 },
]
const DOZZINE = [{ k: 'd1', nome: '1ª 12' }, { k: 'd2', nome: '2ª 12' }, { k: 'd3', nome: '3ª 12' }]
const COLONNE = [{ k: 'c1', nome: '2:1' }, { k: 'c2', nome: '2:1' }, { k: 'c3', nome: '2:1' }]

// Stessa regola del server (private.rl_vincita): la casella vince col numero n?
function vince(k: string, n: number): boolean {
  if (k === `n${n}`) return true
  if (n === 0) return false
  switch (k) {
    case 'rosso': return ROSSI.has(n)
    case 'nero': return !ROSSI.has(n)
    case 'pari': return n % 2 === 0
    case 'dispari': return n % 2 === 1
    case 'manque': return n <= 18
    case 'passe': return n >= 19
    case 'd1': return n <= 12
    case 'd2': return n >= 13 && n <= 24
    case 'd3': return n >= 25
    case 'c1': return n % 3 === 1
    case 'c2': return n % 3 === 2
    case 'c3': return n % 3 === 0
    default: return false
  }
}

let scartoServer = 0
const oraServer = () => Date.now() + scartoServer
const facile = (p: number) => 1 - Math.pow(1 - p, 3)

export function RoulettOne({ leagueId, dati }: { leagueId: number; dati: Dati }) {
  const [stato, setStato] = useState<Stato | null>(null)
  const [puntate, setPuntate] = useState<Puntate>({})
  const [mosse, setMosse] = useState<Puntate[]>([])
  const [ultime, setUltime] = useState<Puntate | null>(null)
  const [fiche, setFiche] = useState(10)
  const [, setTic] = useState(0)
  const [errore, setErrore] = useState('')
  const [festa, setFesta] = useState(0)
  const [regole, setRegole] = useState(false)
  const [audio, setAudio] = useState(() => { try { return localStorage.getItem('slot-audio') !== '0' } catch { return true } })
  const suoni = useSuoni(audio)
  const sbloccaMusica = useMusica('bj', audio)
  const suoniRef = useRef(suoni); suoniRef.current = suoni
  const statoRef = useRef<Stato | null>(null)
  const puntateRef = useRef(puntate); puntateRef.current = puntate
  const inAttesa = useRef(false)
  const invio = useRef<number | null>(null)
  const ruotaRef = useRef<SVGGElement>(null)
  const pallinaRef = useRef<SVGCircleElement>(null)
  const vincitaSuonata = useRef<number | null>(null)
  const fermataSuonata = useRef<number | null>(null)

  useEffect(() => { try { localStorage.setItem('slot-audio', audio ? '1' : '0') } catch { /* preferenza solo locale */ } }, [audio])

  const applica = useCallback((s: Stato, t0: number, t1: number) => {
    scartoServer = s.adesso - (t0 + t1) / 2
    const prima = statoRef.current
    if (prima && prima.giro.id !== s.giro.id) {
      // Giro nuovo: le fiche si tolgono dal tavolo (si possono rimettere con "Ripeti").
      const mie = prima.giocate.find((q) => q.mia)?.puntate
      if (mie) setUltime({ ...mie })
      setPuntate({}); setMosse([])
    } else if (!prima) {
      const mie = s.giocate.find((q) => q.mia)?.puntate
      if (mie) setPuntate({ ...mie })
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

  // Stato del giro ogni secondo; il tempo della pagina avanza ogni 200 ms per cambiare fase al momento giusto.
  useEffect(() => {
    let vivo = true
    const giro = async () => {
      if (!vivo || inAttesa.current || document.hidden) return
      inAttesa.current = true
      await chiedi('casino_rl_live')
      inAttesa.current = false
    }
    void giro()
    const t = window.setInterval(() => void giro(), 1000)
    const t2 = window.setInterval(() => setTic((n) => n + 1), 200)
    return () => { vivo = false; window.clearInterval(t); window.clearInterval(t2) }
  }, [chiedi])

  const g = stato?.giro
  const adesso = oraServer()
  const fase: 'puntate' | 'ruota' | 'esito' = !g || adesso < g.chiude ? 'puntate' : adesso < g.esito_il ? 'ruota' : 'esito'
  const mia = stato?.giocate.find((q) => q.mia)
  const numero = fase === 'esito' ? g?.numero ?? null : null

  // ---------- Ruota e pallina, disegnate dall'ora del server ----------
  const caricato = stato != null
  useEffect(() => {
    if (!caricato) return
    const fermo = ridotto()
    let raf = 0, ultimoTick = -1
    const R_PISTA = 132, R_TASCA = 98
    const passo = () => {
      const s = statoRef.current, t = oraServer()
      const angRuota = fermo ? 0 : ((t % GIRO_RUOTA_MS) / GIRO_RUOTA_MS) * 2 * Math.PI
      if (ruotaRef.current) ruotaRef.current.setAttribute('transform', `rotate(${(angRuota * 180) / Math.PI} 160 160)`)
      const p = pallinaRef.current
      if (s && p) {
        const gg = s.giro
        // dove si ferma la pallina: la tasca del numero, che gira con la ruota
        const tasca = (n: number, quando: number) => ((fermo ? 0 : ((quando % GIRO_RUOTA_MS) / GIRO_RUOTA_MS) * 2 * Math.PI)) + RUOTA.indexOf(n) * SPICCHIO
        let ang = 0, r = R_TASCA, visibile = true
        if (t < gg.chiude || gg.numero == null) {
          // puntate aperte: la pallina riposa nella tasca dell'ultimo numero uscito
          const prec = s.storia[0]
          if (prec == null) visibile = false
          else ang = tasca(prec, t)
        } else if (t < gg.esito_il) {
          const pr = (t - gg.chiude) / (gg.esito_il - gg.chiude)
          const fine = tasca(gg.numero, gg.esito_il)
          // la pallina gira al contrario della ruota e rallenta; nell'ultimo quarto scende nella tasca con due rimbalzi
          ang = fine - 9 * 2 * Math.PI * (1 - facile(pr))
          const discesa = Math.max(0, (pr - 0.72) / 0.28)
          r = R_PISTA - (R_PISTA - R_TASCA) * discesa + (discesa > 0 && discesa < 1 ? Math.abs(Math.sin(discesa * Math.PI * 3)) * 9 * (1 - discesa) : 0)
          // il ticchettio della pallina sui diamanti, sempre piu' rado
          const tick = Math.floor(9 * 37 * facile(pr) / 3)
          if (tick !== ultimoTick && pr > 0.4 && pr < 0.97) { ultimoTick = tick; suoniRef.current.tick(tick) }
        } else {
          ang = tasca(gg.numero, t)
        }
        p.style.opacity = visibile ? '1' : '0'
        p.setAttribute('cx', String(160 + r * Math.sin(ang)))
        p.setAttribute('cy', String(160 - r * Math.cos(ang)))
      }
      raf = requestAnimationFrame(passo)
    }
    raf = requestAnimationFrame(passo)
    return () => cancelAnimationFrame(raf)
  }, [caricato])

  // Suono quando la pallina si ferma, poi la vincita.
  useEffect(() => {
    if (!g || fase !== 'esito' || fermataSuonata.current === g.id) return
    fermataSuonata.current = g.id
    if (adesso - g.esito_il < 1500) suoniRef.current.stop(3)
  }, [fase, g?.id]) // eslint-disable-line react-hooks/exhaustive-deps
  useEffect(() => {
    if (!g || !g.regolato || !mia || vincitaSuonata.current === g.id || fase !== 'esito') return
    vincitaSuonata.current = g.id
    if ((mia.vinto ?? 0) >= mia.totale * 20) { suoniRef.current.grande(); setFesta((x) => x + 1) } else if ((mia.vinto ?? 0) > 0) suoniRef.current.vincita()
  }, [g?.regolato, fase]) // eslint-disable-line react-hooks/exhaustive-deps

  // ---------- Puntate ----------
  // Le fiche si mandano al server mezzo secondo dopo l'ultimo tocco (sostituiscono quelle registrate).
  function manda(nuove: Puntate) {
    if (invio.current) window.clearTimeout(invio.current)
    const giroOra = statoRef.current?.giro
    const subito = giroOra != null && giroOra.chiude - oraServer() < 2000
    invio.current = window.setTimeout(async () => {
      invio.current = null
      const mappa = Object.fromEntries(Object.entries(nuove).filter(([, v]) => v > 0))
      const r = await chiedi('casino_rl_punta', { p_puntate: mappa })
      if (!r) setPuntate({ ...(statoRef.current?.giocate.find((q) => q.mia)?.puntate ?? {}) })
      else setErrore('')
    }, subito ? 0 : 450)
  }
  const aperte = fase === 'puntate'
  const totale = Object.values(puntate).reduce((t, v) => t + v, 0)
  const crediti = stato ? stato.crediti + (mia?.totale ?? 0) : 0   // i crediti gia' puntati in questo giro tornano disponibili per cambiare
  function cambia(nuove: Puntate) { setMosse((m) => [...m, puntateRef.current]); setPuntate(nuove); manda(nuove) }
  function metti(k: string) {
    if (!aperte) return
    const ora = puntate[k] ?? 0
    const aggiunta = Math.min(fiche, MAX_CASELLA - ora, MAX_GIRO - totale, crediti - totale)
    if (aggiunta <= 0) { setErrore(ora >= MAX_CASELLA ? 'Al massimo 500 crediti per casella.' : totale >= MAX_GIRO ? 'Al massimo 2.000 crediti a giro.' : 'Crediti insufficienti.'); return }
    setErrore('')
    suoniRef.current.moneta(1)
    cambia({ ...puntate, [k]: ora + aggiunta })
  }
  function annulla() { if (!aperte || mosse.length === 0) return; const p = mosse[mosse.length - 1]; setMosse((m) => m.slice(0, -1)); setPuntate(p); manda(p) }
  function cancella() { if (!aperte || totale === 0) return; cambia({}) }
  function ripeti() {
    if (!aperte || !ultime || totale > 0) return
    const tot = Object.values(ultime).reduce((t, v) => t + v, 0)
    if (tot > crediti) { setErrore('Crediti insufficienti per ripetere.'); return }
    cambia({ ...ultime })
  }
  function raddoppia() {
    if (!aperte || totale === 0) return
    const doppie = Object.fromEntries(Object.entries(puntate).map(([k, v]) => [k, Math.min(MAX_CASELLA, v * 2)]))
    const tot = Object.values(doppie).reduce((t, v) => t + v, 0)
    if (tot > MAX_GIRO || tot > crediti) { setErrore(tot > MAX_GIRO ? 'Al massimo 2.000 crediti a giro.' : 'Crediti insufficienti per raddoppiare.'); return }
    cambia(doppie)
  }

  if (!stato || !g) return <section className="slot-caricamento">{errore ? <p role="alert">{errore}</p> : <p>Lancio la pallina…</p>}</section>

  const resto = Math.max(0, g.chiude - adesso)
  const vinta = (k: string) => numero != null && vince(k, numero)
  const casella = (k: string, testo: string, classe: string) => {
    const p = puntate[k] ?? 0
    return <button key={k} type="button" className={`rl-casella ${classe}${vinta(k) ? ' is-vincente' : ''}${p > 0 ? ' has-fiche' : ''}`}
      disabled={!aperte} onClick={() => metti(k)} aria-label={`${testo}${p > 0 ? `, puntati ${p}` : ''}`}>
      <span>{testo}</span>
      {p > 0 && <i className={`rl-fiche fiche-casino fiche-casino--${p >= 100 ? 100 : p >= 50 ? 50 : p >= 20 ? 20 : 10}`}><b>{fmt(p)}</b></i>}
    </button>
  }
  const messaggio = errore ? <span className="slot-errore">{errore}</span>
    : fase === 'puntate' ? (totale > 0 ? `Hai puntato ${fmt(totale)} crediti. Puoi cambiare finché il tempo non scade.` : 'Puntate aperte: scegli la fiche e tocca le caselle.')
      : fase === 'ruota' ? 'Puntate chiuse: la pallina gira…'
        : mia ? ((mia.vinto ?? 0) > 0 ? `Esce il ${numero}: vinci ${fmt(mia.vinto ?? 0)} crediti!` : `Esce il ${numero}. Questa volta niente.`) : `Esce il ${numero}.`
  const puntatoTot = stato.giocate.reduce((t, q) => t + q.totale, 0)

  return <section className="rl" onPointerDown={() => { suoni.sblocca(); sbloccaMusica() }}>
    <div className="slot-saldo">
      <div><small>I tuoi crediti</small><strong><Contatore valore={stato.crediti} /></strong></div>
      <span className="slot-ricarica av-dal-vivo"><i aria-hidden="true" />LIVE</span>
      <button type="button" className="slot-audio" aria-pressed={audio} aria-label={audio ? 'Togli i suoni' : 'Attiva i suoni'} onClick={() => setAudio((a) => !a)}>{audio ? '🔊' : '🔇'}</button>
    </div>

    <ol className="rl-storia" aria-label="Ultimi numeri usciti">
      {stato.storia.length === 0 ? <li className="rl-storia__vuota">Ancora nessun numero</li>
        : stato.storia.map((n, i) => <li key={i} className={`is-${colore(n)}`}>{n}</li>)}
    </ol>

    <div className="rl-palco">
      <div className="rl-insegna"><img src="/specialone-mark.svg" alt="" /><span>ROULETT</span><b>ONE</b></div>
      <svg className="rl-ruota" viewBox="0 0 320 320" aria-hidden="true">
        <defs>
          <radialGradient id="rl-legno" cx="50%" cy="50%" r="50%"><stop offset=".78" stopColor="#2a1650" /><stop offset=".9" stopColor="#5b2fa3" /><stop offset="1" stopColor="#1a0d33" /></radialGradient>
          <radialGradient id="rl-centro" cx="50%" cy="45%" r="55%"><stop offset="0" stopColor="#f6dd8c" /><stop offset=".55" stopColor="#bd932a" /><stop offset="1" stopColor="#6b4a10" /></radialGradient>
        </defs>
        <circle cx="160" cy="160" r="158" fill="url(#rl-legno)" />
        <circle cx="160" cy="160" r="140" fill="#120a22" stroke="#bd932a" strokeWidth="2" />
        <g ref={ruotaRef}>
          {RUOTA.map((n, i) => {
            const a0 = i * SPICCHIO - SPICCHIO / 2, a1 = a0 + SPICCHIO
            const p = (r: number, a: number) => `${160 + r * Math.sin(a)} ${160 - r * Math.cos(a)}`
            return <g key={n}>
              <path d={`M ${p(126, a0)} A 126 126 0 0 1 ${p(126, a1)} L ${p(88, a1)} A 88 88 0 0 0 ${p(88, a0)} Z`} className={`rl-spicchio is-${colore(n)}`} />
              <text x={160} y={160 - 113} transform={`rotate(${(i * 360) / 37} 160 160)`} className="rl-spicchio__numero">{n}</text>
            </g>
          })}
          <circle cx="160" cy="160" r="88" fill="none" stroke="#bd932a" strokeWidth="1.5" />
          <circle cx="160" cy="160" r="70" fill="#1d1036" stroke="#bd932a" strokeWidth="1.5" />
          {Array.from({ length: 8 }, (_, i) => <line key={i} x1="160" y1="160" x2={160 + 66 * Math.sin((i * Math.PI) / 4)} y2={160 - 66 * Math.cos((i * Math.PI) / 4)} stroke="#bd932a" strokeWidth="3" strokeLinecap="round" />)}
          <circle cx="160" cy="160" r="22" fill="url(#rl-centro)" />
        </g>
        <image href="/specialone-mark.svg" x="146" y="141" width="28" height="38" />
        <circle ref={pallinaRef} cx="160" cy="30" r="6.5" className="rl-pallina" />
      </svg>
      <div className={`rl-esito rl-esito--${fase}`} aria-live="polite">
        {fase === 'puntate' && <><em>Puntate aperte</em><b>{Math.ceil(resto / 1000)}</b><div className="rl-barra"><i style={{ transform: `scaleX(${1 - resto / Math.max(1, g.chiude - g.apre)})` }} /></div></>}
        {fase === 'ruota' && <em>Rien ne va plus</em>}
        {fase === 'esito' && numero != null && <span className={`rl-numero is-${colore(numero)}`}>{numero}</span>}
      </div>
      <Festa key={festa} attiva={festa > 0} />
    </div>

    <p className="slot-messaggio" role="status">{messaggio}</p>

    <div className="rl-fiches" role="radiogroup" aria-label="Valore della fiche">
      {FICHE.map((f) => <button key={f} type="button" role="radio" aria-checked={fiche === f} className={`fiche-casino fiche-casino--${f}${fiche === f ? ' is-scelta' : ''}`} onClick={() => setFiche(f)}><span>{f}</span></button>)}
      <span className="rl-totale"><small>Puntato</small><b>{fmt(totale)}</b></span>
    </div>

    <div className={`rl-tavolo${aperte ? '' : ' is-chiuso'}`}>
      {casella('n0', '0', 'rl-casella--zero is-verde')}
      <div className="rl-numeri">
        {Array.from({ length: 36 }, (_, i) => i + 1).map((n) => casella(`n${n}`, String(n), `is-${colore(n)}`))}
      </div>
      <div className="rl-riga rl-riga--3">{COLONNE.map((c) => casella(c.k, c.nome, 'rl-casella--fuori'))}</div>
      <div className="rl-riga rl-riga--3">{DOZZINE.map((d) => casella(d.k, d.nome, 'rl-casella--fuori'))}</div>
      <div className="rl-riga rl-riga--3">{ESTERNE.map((e) => casella(e.k, e.nome, `rl-casella--fuori${e.k === 'rosso' ? ' is-rosso' : e.k === 'nero' ? ' is-nero' : ''}`))}</div>
    </div>

    <div className="rl-comandi">
      <button type="button" disabled={!aperte || mosse.length === 0} onClick={annulla}>Annulla</button>
      <button type="button" disabled={!aperte || totale === 0} onClick={cancella}>Cancella</button>
      <button type="button" disabled={!aperte || totale === 0} onClick={raddoppia}>Raddoppia</button>
      <button type="button" disabled={!aperte || !ultime || totale > 0} onClick={ripeti}>Ripeti</button>
    </div>

    <section className="av-giocate">
      <header><h2>Al tavolo</h2><span>{stato.giocate.length} {stato.giocate.length === 1 ? 'giocatore' : 'giocatori'} · {fmt(puntatoTot)} crediti</span></header>
      {stato.giocate.length === 0 ? <p className="bet-nota">Nessuno ha ancora puntato.</p> : <ol>
        {stato.giocate.map((q, i) => {
          const t = dati.teamById.get(q.team_id)
          const esito = fase === 'esito' && g.regolato ? q.vinto ?? 0 : null
          return <li key={`${q.team_id}-${i}`} className={`${q.mia ? 'is-mia' : ''}${esito != null && esito > 0 ? ' is-incassata' : ''}${esito === 0 ? ' is-persa' : ''}`}>
            <span className="bet-giocatori__stemma"><Crest value={t?.stemma_url ?? null} imageUrl={dati.crestUrlByTeamId.get(q.team_id)} size="small" /></span>
            <span className="av-giocate__nome">{t?.nome ?? '—'}</span>
            <span className="av-giocate__puntata">{fmt(q.totale)}</span>
            <span className="av-giocate__esito">{esito != null ? (esito > 0 ? <i>+{fmt(esito)}</i> : '—') : ''}</span>
          </li>
        })}
      </ol>}
    </section>

    <ChatCasino leagueId={leagueId} canale="roul" dati={dati} titolo="Chat RoulettOne" />

    <section className="slot-pannello">
      <button type="button" className="slot-pannello__tasto" aria-expanded={regole} onClick={() => setRegole((v) => !v)}>Come si gioca <span aria-hidden="true">{regole ? '−' : '+'}</span></button>
      {regole && <div className="slot-premi">
        <p>RoulettOne è una <b>roulette europea live</b>: la ruota è una sola per tutta la lega e tutti vedono lo stesso giro. Ci sono <b>20 secondi per puntare</b>, poi la pallina gira e cade in un numero da 0 a 36; dopo pochi secondi riparte il giro successivo.</p>
        <p>Scegli il valore della fiche e tocca le caselle, anche più di una: al massimo 500 crediti per casella e 2.000 a giro. Le puntate si registrano da sole e puoi cambiarle finché il tempo non scade; al giro dopo puoi rimetterle uguali con <b>Ripeti</b>.</p>
        <p><b>Quanto paga</b>, oltre alla puntata che torna indietro: numero secco 35 volte; dozzina o colonna (2:1) 2 volte; rosso, nero, pari, dispari, 1-18 e 19-36 una volta. Con lo <b>0</b> perdono tutte le puntate tranne quella sullo 0.</p>
        <p>Il numero lo estrae il server prima che si chiudano le puntate e nessuno lo vede prima. In media si recupera il 97,3% di quello che si punta, qualunque casella si scelga.</p>
      </div>}
    </section>
  </section>
}
