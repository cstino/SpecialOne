import { useCallback, useEffect, useMemo, useRef, useState, type ReactNode } from 'react'
import { createPortal } from 'react-dom'
import { supabase } from '../lib/supabase'
import { Contatore, Festa, fmt, ridotto, useSuoni } from './Casino'

// BetOne Casino' › Crazy Time (supabase/migrations/20261020100000_casino_crazy_time.sql).
// Ruota a 54 spicchi: 1 (21), 2 (13), 5 (7), 10 (4), Coin Flip (4), Pachinko (2), Cash Hunt (2), Crazy Time (1).
// Prima di ogni giro la top slot puo' accendere un moltiplicatore (×2-×50) su una casella.
// Tutto lo estrae il SERVER (casino_ct_gira / casino_ct_scegli): qui si anima soltanto il risultato.

export type Casella = '1' | '2' | '5' | '10' | 'cf' | 'pa' | 'ch' | 'ct'
// Stesso ordine di private.ct_ruota() nel database.
export const RUOTA: Casella[] = ['ct', '1', '2', '1', '5', '1', 'cf', '1', '2', '1', '2', '1', 'pa', '2', '5', '10', '5', '2', 'cf', '1', '5', '1', '2', '1',
  'ch', '1', '10', '1', '2', '1', 'cf', '1', '2', '1', '5', '1', 'pa', '2', '10', '2', '5', '2', 'cf', '1', '2', '1', '10', '1', 'ch', '1', '5', '1', '2', '1']
export const CASELLE: Record<Casella, { nome: string; corto: string; colore: string; scuro: string; testo: string; paga?: number }> = {
  '1': { nome: '1', corto: '1', colore: '#2f9bea', scuro: '#13548a', testo: '#fff', paga: 1 },
  '2': { nome: '2', corto: '2', colore: '#ffc93c', scuro: '#a7790b', testo: '#3a2600', paga: 2 },
  '5': { nome: '5', corto: '5', colore: '#ff5fa8', scuro: '#a3245f', testo: '#fff', paga: 5 },
  '10': { nome: '10', corto: '10', colore: '#8a5cff', scuro: '#4a24a8', testo: '#fff', paga: 10 },
  cf: { nome: 'Coin Flip', corto: 'COIN FLIP', colore: '#1f5fd6', scuro: '#0d2f73', testo: '#fff' },
  pa: { nome: 'Pachinko', corto: 'PACHINKO', colore: '#c93bdc', scuro: '#6c1679', testo: '#fff' },
  ch: { nome: 'Cash Hunt', corto: 'CASH HUNT', colore: '#1fb85a', scuro: '#0b6430', testo: '#fff' },
  ct: { nome: 'Crazy Time', corto: 'CRAZY TIME', colore: '#e5262b', scuro: '#7a0d10', testo: '#fff' },
}
const ORDINE: Casella[] = ['1', '2', '5', '10', 'cf', 'pa', 'ch', 'ct']
const FICHE = [10, 20, 50, 100]
const VUOTE = (): Record<Casella, number> => ({ '1': 0, '2': 0, '5': 0, '10': 0, cf: 0, pa: 0, ch: 0, ct: 0 })
const MOLT_TOP = [2, 3, 5, 10, 15, 25, 50]
const OFFSET_BANDIERE = [0, 21, 43]
const BANDIERE = [{ nome: 'Verde', colore: '#2fe07a' }, { nome: 'Blu', colore: '#3d8bff' }, { nome: 'Gialla', colore: '#ffd23d' }]

type Attesa = { id: number; esito: 'ch' | 'ct'; puntata: number; molt: number; valori: number[] | null; ruota: number[] | null }
type BonusCf = { rosso: number; blu: number; lato: 'rosso' | 'blu'; valore: number }
type BonusPa = { tavola: number[]; lanci: number[]; valore: number }
type Giro = { id: number; spicchio: number; esito: Casella; top_casella: Casella | null; top_molt: number; puntate: Partial<Record<Casella, number>>; totale: number; vinto: number; crediti: number; attesa?: Attesa; bonus?: BonusCf | BonusPa }
type Scelta = { vinto: number; crediti: number; valore: number; molt: number; puntata: number; scelta: number; tavola?: number[]; rotazioni?: number[]; giri?: number }
type Fine = { vinto: number; crediti: number }

const aspetta = (ms: number) => new Promise<void>((ok) => window.setTimeout(ok, ridotto() ? Math.min(ms, 150) : ms))
const mod = (a: number, n: number) => ((a % n) + n) % n

// Rotazione di una ruota fino a portare lo spicchio `indice` sotto la lancetta in alto (rallenta come una ruota vera).
function giraRuota(el: HTMLElement, da: number, indice: number, spicchi: number, giri: number, durata: number, tick: () => void) {
  const passo = 360 / spicchi
  const scarto = (Math.random() - 0.5) * passo * 0.6
  const a = da + giri * 360 + mod(-indice * passo - da, 360) + scarto
  const d = ridotto() ? 200 : durata
  return new Promise<number>((ok) => {
    const t0 = performance.now(); let ultimo = Math.floor((da + passo / 2) / passo)
    const f = (t: number) => {
      const k = Math.min(1, (t - t0) / d)
      const ang = da + (a - da) * (1 - Math.pow(1 - k, 4))
      el.style.transform = `rotate(${ang}deg)`
      const s = Math.floor((ang + passo / 2) / passo)
      if (s !== ultimo) { ultimo = s; tick() }
      if (k < 1) requestAnimationFrame(f); else ok(a)
    }
    requestAnimationFrame(f)
  })
}

// ---------- Ruota in SVG (usata sia per la ruota principale sia per quella del bonus Crazy Time) ----------
type Spicchio = { colore: string; scuro: string; testo: string; etichetta: string; grande: boolean }
const punto = (gradi: number, r: number) => { const a = gradi * Math.PI / 180; return `${(r * Math.sin(a)).toFixed(2)},${(-r * Math.cos(a)).toFixed(2)}` }

function RuotaSvg({ spicchi, evidenzia }: { spicchi: Spicchio[]; evidenzia?: number | null }) {
  const passo = 360 / spicchi.length
  return <svg viewBox="-112 -112 224 224" className="ct-ruota__svg" aria-hidden="true">
    <defs>
      <radialGradient id="ctLuce" cx="0" cy="0" r="1" gradientUnits="userSpaceOnUse" gradientTransform="scale(100)">
        <stop offset=".25" stopColor="#000" stopOpacity=".45" /><stop offset=".7" stopColor="#000" stopOpacity="0" /><stop offset="1" stopColor="#fff" stopOpacity=".18" />
      </radialGradient>
      <linearGradient id="ctOro" x1="0" y1="-1" x2="0" y2="1" gradientUnits="objectBoundingBox"><stop offset="0" stopColor="#fff1b0" /><stop offset=".5" stopColor="#e7b23a" /><stop offset="1" stopColor="#8a5a12" /></linearGradient>
    </defs>
    <circle r="110" fill="url(#ctOro)" />
    <circle r="104" fill="#1a0b22" />
    {spicchi.map((s, i) => {
      const a0 = (i - 0.5) * passo, a1 = (i + 0.5) * passo
      return <g key={i} className={evidenzia === i ? 'is-evidenziato' : undefined}>
        <path d={`M0,0 L${punto(a0, 102)} A102,102 0 0 1 ${punto(a1, 102)} Z`} fill={s.colore} stroke={s.scuro} strokeWidth=".8" />
        <g transform={`rotate(${i * passo})`}>
          <text x="0" y={s.grande ? -82 : -68} transform={`rotate(-90 0 ${s.grande ? -82 : -68})`} fill={s.testo} className={s.grande ? 'ct-ruota__num' : 'ct-ruota__nome'}>{s.etichetta}</text>
        </g>
      </g>
    })}
    <circle r="102" fill="url(#ctLuce)" pointerEvents="none" />
    {Array.from({ length: 27 }, (_, i) => <circle key={i} className="ct-ruota__lampadina" cx={107 * Math.sin(i * 2 * Math.PI / 27)} cy={-107 * Math.cos(i * 2 * Math.PI / 27)} r="2.4" style={{ animationDelay: `${(i % 3) * 0.25}s` }} />)}
    <circle r="27" fill="url(#ctOro)" />
    <circle r="23" fill="#1a0b22" />
  </svg>
}

const SPICCHI_PRINCIPALI: Spicchio[] = RUOTA.map((c) => ({ colore: CASELLE[c].colore, scuro: CASELLE[c].scuro, testo: CASELLE[c].testo, etichetta: CASELLE[c].corto, grande: CASELLE[c].paga != null }))

// ---------- Top slot ----------
function TopSlot({ gira, casella, molt }: { gira: boolean; casella: Casella | null | undefined; molt: number | null }) {
  const [finta, setFinta] = useState<{ c: Casella; m: number }>({ c: '1', m: 2 })
  useEffect(() => {
    if (!gira) return
    const t = window.setInterval(() => setFinta({ c: ORDINE[Math.floor(Math.random() * 8)], m: MOLT_TOP[Math.floor(Math.random() * MOLT_TOP.length)] }), 70)
    return () => window.clearInterval(t)
  }, [gira])
  const c = gira ? finta.c : casella
  const mancato = !gira && casella === null
  return <div className={`ct-top${gira ? ' is-gira' : ''}${!gira && casella ? ' is-preso' : ''}`} aria-live="polite">
    <span className="ct-top__etichetta">TOP SLOT</span>
    <div className="ct-top__finestra">
      {mancato ? <span className="ct-top__vuoto">—</span> : c ? <span className="ct-top__casella" style={{ background: CASELLE[c].colore, color: CASELLE[c].testo }}>{CASELLE[c].corto}</span> : <span className="ct-top__vuoto">?</span>}
    </div>
    <div className="ct-top__finestra ct-top__finestra--molt">
      {mancato ? <span className="ct-top__vuoto">—</span> : <b>{gira ? `${finta.m}×` : casella ? `${molt}×` : '?'}</b>}
    </div>
  </div>
}

// ---------- Contenitore dei bonus (a schermo intero) ----------
function Palco({ esito, molt, puntata, children }: { esito: Casella; molt: number; puntata: number; children: ReactNode }) {
  return createPortal(<div className="ct-palco" role="dialog" aria-modal="true" aria-label={CASELLE[esito].nome}>
    <div className={`ct-palco__scena ct-palco__scena--${esito}`}>
      <header className="ct-palco__testa">
        <h2>{CASELLE[esito].nome}</h2>
        <span>Puntata {fmt(puntata)}{molt > 1 && <b className="ct-palco__molt">Top slot {molt}×</b>}</span>
      </header>
      {children}
    </div>
  </div>, document.body)
}

function EsitoBonus({ valore, molt, vinto, onFine }: { valore: number; molt: number; vinto: number; onFine: () => void }) {
  return <div className="ct-esito-bonus" role="status">
    <span className="ct-esito-bonus__molt">{valore}×{molt > 1 ? <i> · top slot {molt}×</i> : null}</span>
    <strong>+<Contatore valore={vinto} /></strong>
    <small>crediti</small>
    <button type="button" className="ct-tasto-oro" onClick={onFine}>Continua</button>
  </div>
}

// ---------- Coin Flip ----------
function CoinFlip({ bonus, molt, puntata, vinto, suoni, onFine }: { bonus: BonusCf; molt: number; puntata: number; vinto: number; suoni: ReturnType<typeof useSuoni>; onFine: () => void }) {
  const [fase, setFase] = useState<'valori' | 'lancio' | 'esito'>('valori')
  const moneta = useRef<HTMLDivElement>(null)
  const audio = useRef(suoni); audio.current = suoni
  useEffect(() => {
    const suoni = audio.current
    let vivo = true
    void (async () => {
      await aspetta(1400); if (!vivo) return
      setFase('lancio'); suoni.leva()
      requestAnimationFrame(() => { if (moneta.current) moneta.current.style.transform = `rotateY(${bonus.lato === 'rosso' ? 1800 : 1980}deg)` })
      await aspetta(3000); if (!vivo) return
      suoni.coppe(); setFase('esito')
    })()
    return () => { vivo = false }
  }, [bonus])
  return <Palco esito="cf" molt={molt} puntata={puntata}>
    <div className="ct-cf">
      <div className={`ct-cf__lato ct-cf__lato--rosso${fase === 'esito' && bonus.lato === 'rosso' ? ' is-vince' : ''}${fase === 'esito' && bonus.lato !== 'rosso' ? ' is-perde' : ''}`}><b>{bonus.rosso}×</b><small>Rosso</small></div>
      <div className="ct-cf__arena"><div ref={moneta} className={`ct-cf__moneta${fase !== 'valori' ? ' is-lanciata' : ''}`}>
        <span className="ct-cf__faccia ct-cf__faccia--rosso"><b>{bonus.rosso}×</b></span>
        <span className="ct-cf__faccia ct-cf__faccia--blu"><b>{bonus.blu}×</b></span>
      </div></div>
      <div className={`ct-cf__lato ct-cf__lato--blu${fase === 'esito' && bonus.lato === 'blu' ? ' is-vince' : ''}${fase === 'esito' && bonus.lato !== 'blu' ? ' is-perde' : ''}`}><b>{bonus.blu}×</b><small>Blu</small></div>
    </div>
    {fase === 'esito' ? <EsitoBonus valore={bonus.valore} molt={molt} vinto={vinto} onFine={onFine} /> : <p className="ct-palco__nota">{fase === 'valori' ? 'Due moltiplicatori: uno rosso, uno blu…' : 'Lancio della moneta!'}</p>}
  </Palco>
}

// ---------- Pachinko ----------
const PA_L = 20, PA_RIGHE = 12, PA_Y0 = 30, PA_DY = 25
function percorsoPachinko(arrivo: number): number[] {
  const min = Math.max(0, arrivo - 6), max = Math.min(15, arrivo + 6)
  const partenza = min + Math.floor(Math.random() * (max - min + 1))
  const destra = 6 + (arrivo - partenza)
  for (let tentativo = 0; tentativo < 60; tentativo++) {
    const passi = [...Array(destra).fill(1), ...Array(PA_RIGHE - destra).fill(-1)].sort(() => Math.random() - 0.5)
    const pos = [partenza]; let ok = true
    for (const p of passi) { const x = pos[pos.length - 1] + p / 2; if (x < 0 || x > 15) { ok = false; break } pos.push(x) }
    if (ok) return pos
  }
  // Ripiego: prima verso l'arrivo, poi a zig-zag sul posto.
  const pos = [partenza]
  for (let i = 0; i < PA_RIGHE; i++) {
    const x = pos[pos.length - 1], resto = arrivo - x
    pos.push(resto > 0 ? x + 0.5 : resto < 0 ? x - 0.5 : (i % 2 === 0 ? (x > 0 ? x - 0.5 : x + 0.5) : x + (x > 0 ? 0.5 : -0.5)))
  }
  pos[pos.length - 1] = arrivo
  return pos
}

function Pachinko({ bonus, molt, puntata, vinto, suoni, onFine }: { bonus: BonusPa; molt: number; puntata: number; vinto: number; suoni: ReturnType<typeof useSuoni>; onFine: () => void }) {
  const [doppi, setDoppi] = useState(1)
  const [buca, setBuca] = useState<number | null>(null)
  const [flash, setFlash] = useState(false)
  const [fine, setFine] = useState(false)
  const disco = useRef<SVGCircleElement>(null)
  const altezza = PA_Y0 + PA_RIGHE * PA_DY + 70
  const audio = useRef(suoni); audio.current = suoni
  useEffect(() => {
    const suoni = audio.current
    let vivo = true
    void (async () => {
      await aspetta(900)
      for (let n = 0; n < bonus.lanci.length; n++) {
        if (!vivo) return
        const arrivo = bonus.lanci[n]
        const pos = percorsoPachinko(arrivo)
        setBuca(null)
        for (let k = 0; k < pos.length; k++) {
          const x0 = (pos[Math.max(0, k - 1)] + 0.5) * PA_L, x1 = (pos[k] + 0.5) * PA_L
          const y0 = PA_Y0 + Math.max(0, k - 1) * PA_DY, y1 = PA_Y0 + k * PA_DY
          await new Promise<void>((ok) => {
            const t0 = performance.now(), d = ridotto() ? 10 : k === 0 ? 1 : 150
            const f = (t: number) => {
              const e = Math.min(1, (t - t0) / d)
              disco.current?.setAttribute('cx', String(x0 + (x1 - x0) * e))
              disco.current?.setAttribute('cy', String(y0 + (y1 - y0) * e - Math.sin(Math.PI * e) * 7))
              if (e < 1) requestAnimationFrame(f); else ok()
            }
            requestAnimationFrame(f)
          })
          if (k > 0) suoni.tick(k)
        }
        // Caduta nella buca.
        disco.current?.setAttribute('cy', String(PA_Y0 + PA_RIGHE * PA_DY + 34))
        setBuca(arrivo); suoni.stop(2)
        if (bonus.tavola[arrivo] === -2 && n < bonus.lanci.length - 1) {
          suoni.coppe(); setFlash(true)
          await aspetta(700); if (!vivo) return
          setDoppi((d) => d * 2); setFlash(false)
          await aspetta(900)
        }
      }
      if (!vivo) return
      await aspetta(500); suoni.vincita(); setFine(true)
    })()
    return () => { vivo = false }
  }, [bonus])
  return <Palco esito="pa" molt={molt} puntata={puntata}>
    <div className={`ct-pa${flash ? ' is-double' : ''}`}>
      <svg viewBox={`-4 0 ${16 * PA_L + 8} ${altezza}`} className="ct-pa__svg" aria-hidden="true">
        <rect x="-4" y="0" width={16 * PA_L + 8} height={altezza} rx="10" className="ct-pa__fondo" />
        {Array.from({ length: PA_RIGHE }, (_, k) => Array.from({ length: k % 2 === 0 ? 16 : 17 }, (_, j) => <circle key={`${k}-${j}`} className="ct-pa__chiodo"
          cx={(j + (k % 2 === 0 ? 0.5 : 0)) * PA_L} cy={PA_Y0 + (k + 1) * PA_DY - 9} r="2.2" />))}
        {bonus.tavola.map((v, i) => <g key={i} className={`ct-pa__buca${v === -2 ? ' is-double' : ''}${buca === i ? ' is-presa' : ''}`}>
          <rect x={i * PA_L + 1} y={PA_Y0 + PA_RIGHE * PA_DY + 14} width={PA_L - 2} height="52" rx="3" />
          <text x={i * PA_L + PA_L / 2} y={PA_Y0 + PA_RIGHE * PA_DY + 40} transform={`rotate(-90 ${i * PA_L + PA_L / 2} ${PA_Y0 + PA_RIGHE * PA_DY + 40})`}>{v === -2 ? 'DOUBLE' : `${v * doppi}×`}</text>
        </g>)}
        <circle ref={disco} className="ct-pa__disco" cx={8 * PA_L} cy={6} r="7" />
      </svg>
      {doppi > 1 && <span className="ct-pa__doppi">Tutto ×{doppi}</span>}
    </div>
    {fine ? <EsitoBonus valore={bonus.valore} molt={molt} vinto={vinto} onFine={onFine} /> : <p className="ct-palco__nota">{flash ? 'DOUBLE! Tutti i premi raddoppiano, si rilancia.' : 'Il disco scende…'}</p>}
  </Palco>
}

// ---------- Cash Hunt ----------
function CashHunt({ attesa, scegli, suoni, onFine }: { attesa: Attesa; scegli: (n: number) => Promise<Scelta | null>; suoni: ReturnType<typeof useSuoni>; onFine: (f: Fine) => void }) {
  const [fase, setFase] = useState<'mostra' | 'mescola' | 'scegli' | 'attendi' | 'rivela' | 'tutti'>('mostra')
  const anteprima = useMemo(() => [...(attesa.valori ?? [])].sort(() => Math.random() - 0.5), [attesa])
  const [esito, setEsito] = useState<Scelta | null>(null)
  const audio = useRef(suoni); audio.current = suoni
  useEffect(() => {
    let vivo = true
    void (async () => { await aspetta(2600); if (!vivo) return; setFase('mescola'); audio.current.leva(); await aspetta(1500); if (vivo) setFase('scegli') })()
    return () => { vivo = false }
  }, [])
  async function tocca(i: number) {
    if (fase !== 'scegli') return
    setFase('attendi')
    const r = await scegli(i)
    if (!r) { setFase('scegli'); return }
    setEsito(r); setFase('rivela'); suoni.coppe()
    await aspetta(1300); setFase('tutti')
  }
  const coperte = fase === 'mescola' || fase === 'scegli' || fase === 'attendi'
  return <Palco esito="ch" molt={attesa.molt} puntata={attesa.puntata}>
    <div className={`ct-ch${fase === 'mescola' ? ' is-mescola' : ''}`}>
      {Array.from({ length: 108 }, (_, i) => {
        const scelto = esito?.scelta === i
        const valore = esito?.tavola ? esito.tavola[i] : anteprima[i]
        const visibile = fase === 'mostra' || (fase === 'rivela' && scelto) || fase === 'tutti'
        return <button key={i} type="button" disabled={fase !== 'scegli'} onClick={() => void tocca(i)}
          className={`ct-ch__bersaglio${visibile ? ' is-scoperto' : ''}${coperte ? ' is-coperto' : ''}${scelto ? ' is-scelto' : ''}${fase === 'tutti' && !scelto ? ' is-altro' : ''}`}
          style={{ animationDelay: `${(i % 9) * 0.03 + Math.floor(i / 9) * 0.02}s` }} aria-label={visibile ? `${valore}×` : `Bersaglio ${i + 1}`}>
          {visibile ? <b>{valore}×</b> : <img src="/specialone-mark.svg" alt="" />}
        </button>
      })}
    </div>
    {fase === 'tutti' && esito ? <EsitoBonus valore={esito.valore} molt={esito.molt} vinto={esito.vinto} onFine={() => onFine({ vinto: esito.vinto, crediti: esito.crediti })} />
      : <p className="ct-palco__nota">{fase === 'mostra' ? 'Ecco i premi in palio: guardali bene…' : fase === 'mescola' ? 'Si coprono e si mescolano…' : fase === 'scegli' ? 'Tocca un bersaglio: dietro c\'è il tuo premio.' : fase === 'attendi' ? 'Mira…' : ''}</p>}
  </Palco>
}

// ---------- Crazy Time (bonus) ----------
const COLORI_CRAZY = ['#e5262b', '#ffc93c', '#2f9bea', '#1fb85a', '#ff5fa8', '#8a5cff', '#ff8a1f', '#13c5c9']
function CrazyBonus({ attesa, scegli, suoni, onFine }: { attesa: Attesa; scegli: (n: number) => Promise<Scelta | null>; suoni: ReturnType<typeof useSuoni>; onFine: (f: Fine) => void }) {
  const ruota = attesa.ruota ?? []
  const [fase, setFase] = useState<'scegli' | 'gira' | 'esito'>('scegli')
  const [bandiera, setBandiera] = useState<number | null>(null)
  const [fattore, setFattore] = useState(1)
  const [annuncio, setAnnuncio] = useState('')
  const [evidenzia, setEvidenzia] = useState<number | null>(null)
  const [esito, setEsito] = useState<Scelta | null>(null)
  const giro = useRef<HTMLDivElement>(null)
  const angolo = useRef(0)
  const spicchi: Spicchio[] = useMemo(() => ruota.map((v, i) => v === -2 ? { colore: '#f7d04a', scuro: '#8a6410', testo: '#3a2600', etichetta: 'DOUBLE', grande: false }
    : v === -3 ? { colore: '#ff9f1c', scuro: '#8a4a00', testo: '#3a1600', etichetta: 'TRIPLE', grande: false }
      : { colore: COLORI_CRAZY[i % COLORI_CRAZY.length], scuro: '#1a0b22', testo: '#fff', etichetta: `${v * fattore}×`, grande: false }), [ruota, fattore])

  async function scegliBandiera(f: number) {
    if (fase !== 'scegli') return
    setBandiera(f); setFase('gira'); suoni.leva()
    const r = await scegli(f)
    if (!r || !r.rotazioni) { setFase('scegli'); setBandiera(null); return }
    let fatt = 1
    for (let i = 0; i < r.rotazioni.length; i++) {
      setEvidenzia(null); setAnnuncio('')
      if (!giro.current) return
      let n = 0
      angolo.current = await giraRuota(giro.current, angolo.current, r.rotazioni[i], 64, 4, 6500, () => suoni.tick(n++))
      const seg = mod(r.rotazioni[i] + OFFSET_BANDIERE[f], 64)
      setEvidenzia(seg); suoni.stop(3)
      const v = ruota[seg]
      if (v === -2 || v === -3) {
        suoni.coppe(); setAnnuncio(v === -2 ? 'DOUBLE! Tutti i premi ×2, si rigira' : 'TRIPLE! Tutti i premi ×3, si rigira')
        await aspetta(1400)
        fatt *= v === -2 ? 2 : 3; setFattore(fatt)
        await aspetta(700)
      }
    }
    await aspetta(600)
    setEsito(r); setFase('esito')
    if (r.vinto >= r.puntata * 100) suoni.grande(); else suoni.vincita()
  }

  return <Palco esito="ct" molt={attesa.molt} puntata={attesa.puntata}>
    <div className="ct-crazy">
      <div className="ct-crazy__ruota">
        <div className="ct-crazy__giro" ref={giro}><RuotaSvg spicchi={spicchi} evidenzia={evidenzia} /></div>
        {OFFSET_BANDIERE.map((o, f) => <span key={f} className={`ct-crazy__bandiera${bandiera === f ? ' is-mia' : ''}${bandiera != null && bandiera !== f ? ' is-spenta' : ''}`}
          style={{ ['--ang' as string]: `${o * 360 / 64}deg`, ['--col' as string]: BANDIERE[f].colore }} />)}
      </div>
      {annuncio && <p className="ct-crazy__annuncio" role="status">{annuncio}</p>}
    </div>
    {fase === 'scegli' ? <div className="ct-crazy__scelta">
      <p className="ct-palco__nota">Scegli la tua bandierina: il premio è lo spicchio che indica quando la ruota si ferma.</p>
      <div>{BANDIERE.map((b, f) => <button key={f} type="button" style={{ ['--col' as string]: b.colore }} onClick={() => void scegliBandiera(f)}>{b.nome}</button>)}</div>
    </div>
      : fase === 'esito' && esito ? <EsitoBonus valore={esito.valore} molt={esito.molt} vinto={esito.vinto} onFine={() => onFine({ vinto: esito.vinto, crediti: esito.crediti })} />
        : !annuncio && <p className="ct-palco__nota">Bandierina {BANDIERE[bandiera ?? 0].nome.toLowerCase()}: la ruota gira…</p>}
  </Palco>
}

// ---------- Gioco ----------
export function CrazyTime({ leagueId }: { leagueId: number }) {
  const [crediti, setCrediti] = useState<number | null>(null)
  const [storia, setStoria] = useState<Casella[]>([])
  const [puntate, setPuntate] = useState<Record<Casella, number>>(VUOTE)
  const [mosse, setMosse] = useState<Array<Record<Casella, number>>>([])
  const [fiche, setFiche] = useState(10)
  const [inCorsa, setInCorsa] = useState(false)
  const [topGira, setTopGira] = useState(false)
  const [top, setTop] = useState<{ casella: Casella | null; molt: number } | null>(null)
  const [giro, setGiro] = useState<Giro | null>(null)
  const [attesa, setAttesa] = useState<Attesa | null>(null)
  const [bonusAperto, setBonusAperto] = useState(false)
  const [messaggio, setMessaggio] = useState('Metti le fiche sulle caselle e gira la ruota.')
  const [vinto, setVinto] = useState<number | null>(null)
  const [errore, setErrore] = useState('')
  const [festa, setFesta] = useState(0)
  const [regole, setRegole] = useState(false)
  const [audio, setAudio] = useState(() => { try { return localStorage.getItem('slot-audio') !== '0' } catch { return true } })
  const suoni = useSuoni(audio)
  const ruotaRef = useRef<HTMLDivElement>(null)
  const angolo = useRef(0)
  const [spicchioUscito, setSpicchioUscito] = useState<number | null>(null)

  const carica = useCallback(async () => {
    const { data, error } = await supabase.rpc('casino_ct_stato', { p_league_id: leagueId })
    if (error) { setErrore(error.message); return }
    const s = data as { crediti: number; attesa: Attesa | null; storia: Casella[] }
    setCrediti(s.crediti); setStoria(s.storia ?? [])
    // Bonus lasciato a meta' (app chiusa durante la scelta): si riprende da dove era.
    if (s.attesa) { setAttesa(s.attesa); setBonusAperto(true); setMessaggio(`Hai un ${CASELLE[s.attesa.esito].nome} da giocare!`) }
  }, [leagueId])
  useEffect(() => { void carica() }, [carica])
  useEffect(() => { try { localStorage.setItem('slot-audio', audio ? '1' : '0') } catch { /* preferenza solo locale */ } }, [audio])

  const totale = ORDINE.reduce((s, c) => s + puntate[c], 0)
  const puoiGirare = !inCorsa && !bonusAperto && crediti != null && totale > 0 && totale <= crediti

  function aggiungi(c: Casella) {
    if (inCorsa || bonusAperto) return
    if (puntate[c] + fiche > 500) { setErrore('Al massimo 500 crediti su una casella.'); return }
    if (totale + fiche > 2000) { setErrore('Al massimo 2.000 crediti a giro.'); return }
    setErrore(''); setMosse((m) => [...m, puntate]); setPuntate((p) => ({ ...p, [c]: p[c] + fiche })); suoni.moneta(ORDINE.indexOf(c))
  }
  function annulla() { setMosse((m) => { if (m.length) setPuntate(m[m.length - 1]); return m.slice(0, -1) }) }
  function raddoppia() {
    if (totale * 2 > 2000 || ORDINE.some((c) => puntate[c] * 2 > 500)) { setErrore('Raddoppiando superi il limite (500 per casella, 2.000 a giro).'); return }
    setErrore(''); setMosse((m) => [...m, puntate]); setPuntate((p) => Object.fromEntries(ORDINE.map((c) => [c, p[c] * 2])) as Record<Casella, number>)
  }
  function svuota() { setMosse((m) => [...m, puntate]); setPuntate(VUOTE()) }

  function chiudi(f: Fine, tot: number) {
    setCrediti(f.crediti); setVinto(f.vinto)
    if (f.vinto > 0) {
      if (f.vinto >= tot * 20) { suoni.grande(); setFesta((n) => n + 1) } else suoni.vincita()
    }
  }

  async function gira() {
    if (!puoiGirare || crediti == null) return
    setErrore(''); setVinto(null); setGiro(null); setTop(null); setSpicchioUscito(null)
    suoni.leva(); setInCorsa(true); setMessaggio('Top slot…')
    const giocate = Object.fromEntries(ORDINE.filter((c) => puntate[c] > 0).map((c) => [c, puntate[c]]))
    setCrediti(crediti - totale)
    const { data, error } = await supabase.rpc('casino_ct_gira', { p_league_id: leagueId, p_puntate: giocate })
    if (error) { setErrore(error.message); setInCorsa(false); setCrediti(crediti); setMessaggio('Metti le fiche sulle caselle e gira la ruota.'); return }
    const r = data as Giro
    setTopGira(true)
    await aspetta(1500)
    setTopGira(false); setTop({ casella: r.top_casella, molt: r.top_molt }); suoni.stop(1)
    if (r.top_casella) suoni.coppe()
    setMessaggio(r.top_casella ? `Top slot: ${CASELLE[r.top_casella].nome} vale ${r.top_molt}× in questo giro!` : 'Top slot: niente moltiplicatore stavolta.')
    await aspetta(900)
    setMessaggio('La ruota gira…')
    let n = 0
    if (ruotaRef.current) angolo.current = await giraRuota(ruotaRef.current, angolo.current, r.spicchio, 54, 5, 6200, () => suoni.tick(n++))
    setSpicchioUscito(r.spicchio); suoni.stop(4)
    setStoria((s) => [r.esito, ...s].slice(0, 14))
    setGiro(r)
    const nome = CASELLE[r.esito].nome
    const puntato = (r.puntate[r.esito] ?? 0) > 0
    if (r.attesa) {
      setMessaggio(`${nome}!`); suoni.coppe()
      await aspetta(1200)
      setAttesa(r.attesa); setBonusAperto(true)
    } else if (r.bonus && puntato) {
      setMessaggio(`${nome}!`); suoni.coppe()
      await aspetta(1200)
      setBonusAperto(true)
    } else {
      setMessaggio(r.vinto > 0 ? `È uscito ${nome}: +${fmt(r.vinto)} crediti!` : CASELLE[r.esito].paga == null ? `È uscito ${nome}, ma non avevi puntato su questo bonus.` : `È uscito ${nome}. Niente stavolta, ritenta!`)
      chiudi({ vinto: r.vinto, crediti: r.crediti }, r.totale)
    }
    setInCorsa(false)
  }

  async function scegli(n: number): Promise<Scelta | null> {
    const { data, error } = await supabase.rpc('casino_ct_scegli', { p_league_id: leagueId, p_scelta: n })
    if (error) { setErrore(error.message); return null }
    return data as Scelta
  }

  function fineBonus(f: Fine) {
    const esito = attesa?.esito ?? giro?.esito
    setBonusAperto(false); setAttesa(null)
    setMessaggio(`${esito ? CASELLE[esito].nome : 'Bonus'}: +${fmt(f.vinto)} crediti!`)
    chiudi(f, giro?.totale ?? attesa?.puntata ?? 1)
  }

  if (crediti == null) return <section className="slot-caricamento">{errore ? <p role="alert">{errore}</p> : <p>Accendo la ruota…</p>}</section>

  const molt = (c: Casella) => (top?.casella === c ? top.molt : null)
  const moltBonus = giro && top?.casella === giro.esito ? top.molt : 1

  return <section className="ct" onPointerDown={() => suoni.sblocca()}>
    <div className="slot-saldo">
      <div><small>I tuoi crediti</small><strong><Contatore valore={crediti} /></strong></div>
      {vinto != null && vinto > 0 ? <span className="slot-gratis">+{fmt(vinto)}</span> : <span className="slot-ricarica">+1.000 gratis alle 23:00</span>}
      <button type="button" className="slot-audio" aria-pressed={audio} aria-label={audio ? 'Togli i suoni' : 'Attiva i suoni'} onClick={() => setAudio((a) => !a)}>{audio ? '🔊' : '🔇'}</button>
    </div>

    <div className="ct-studio">
      <div className="ct-insegna"><span>CRAZY</span><b>TIME</b></div>
      <TopSlot gira={topGira} casella={top ? top.casella : undefined} molt={top?.molt ?? null} />
      <div className="ct-ruota">
        <span className="ct-ruota__lancetta" aria-hidden="true" />
        <div className="ct-ruota__giro" ref={ruotaRef}><RuotaSvg spicchi={SPICCHI_PRINCIPALI} evidenzia={inCorsa ? null : spicchioUscito} /></div>
        <span className="ct-ruota__centro" aria-hidden="true"><img src="/specialone-mark.svg" alt="" /></span>
      </div>
      {storia.length > 0 && <ol className="ct-storia" aria-label="Ultimi risultati">
        {storia.map((c, i) => <li key={i} style={{ background: CASELLE[c].colore, color: CASELLE[c].testo }}>{CASELLE[c].paga != null ? c : CASELLE[c].corto.split(' ').map((p) => p[0]).join('')}</li>)}
      </ol>}
      <Festa key={festa} attiva={festa > 0} />
    </div>

    <p className="slot-messaggio" role="status">{errore ? <span className="slot-errore">{errore}</span> : messaggio}</p>

    <div className="ct-tavolo" role="group" aria-label="Caselle su cui puntare">
      {ORDINE.map((c) => {
        const m = molt(c)
        return <button key={c} type="button" className={`ct-casella ct-casella--${CASELLE[c].paga != null ? 'num' : 'bonus'}${giro && !inCorsa && giro.esito === c ? ' is-uscita' : ''}`}
          style={{ ['--col' as string]: CASELLE[c].colore, ['--scuro' as string]: CASELLE[c].scuro, color: CASELLE[c].testo }}
          disabled={inCorsa || bonusAperto} onClick={() => aggiungi(c)} aria-label={`${CASELLE[c].nome}: puntata ${puntate[c]}`}>
          <b>{CASELLE[c].paga != null ? c : CASELLE[c].nome}</b>
          <small>{CASELLE[c].paga != null ? `paga ${CASELLE[c].paga}:1` : 'bonus'}</small>
          {puntate[c] > 0 && <span className="ct-casella__fiche">{puntate[c]}</span>}
          {m && <span className="ct-casella__molt">{m}×</span>}
        </button>
      })}
    </div>

    <div className="ct-comandi">
      <div className="ct-fiche" role="group" aria-label="Valore della fiche">
        {FICHE.map((f) => <button key={f} type="button" className={`ct-fiche__f ct-fiche__f--${f}${fiche === f ? ' is-scelta' : ''}`} aria-pressed={fiche === f} onClick={() => setFiche(f)}>{f}</button>)}
      </div>
      <div className="ct-azioni">
        <button type="button" disabled={inCorsa || mosse.length === 0} onClick={annulla}>Annulla</button>
        <button type="button" disabled={inCorsa || totale === 0} onClick={raddoppia}>×2</button>
        <button type="button" disabled={inCorsa || totale === 0} onClick={svuota}>Svuota</button>
      </div>
      <button type="button" className="slot-gira" disabled={!puoiGirare} onClick={() => void gira()}>
        <span>GIRA</span><small>{totale > 0 ? `${fmt(totale)} crediti` : 'metti le fiche'}</small>
      </button>
    </div>

    <section className="slot-pannello">
      <button type="button" className="slot-pannello__tasto" aria-expanded={regole} onClick={() => setRegole((v) => !v)}>Come si gioca <span aria-hidden="true">{regole ? '−' : '+'}</span></button>
      {regole && <div className="slot-premi ct-regole">
        <p>Scegli il valore della fiche e tocca le caselle su cui vuoi puntare: puoi puntare su più caselle nello stesso giro (al massimo 500 crediti per casella e 2.000 a giro). Le fiche restano sul tavolo anche dopo il giro: per rigiocare basta toccare GIRA.</p>
        <p><b>Numeri.</b> Se la ruota si ferma sul tuo numero vinci la puntata moltiplicata per il numero, più la puntata indietro: 10 crediti sul 5 diventano 60. Sulla ruota ci sono 21 spicchi da 1, 13 da 2, 7 da 5 e 4 da 10.</p>
        <p><b>Top slot.</b> Prima di ogni giro la top slot può accendere un moltiplicatore da 2× a 50× su una casella: se la ruota si ferma proprio lì, la vincita si moltiplica.</p>
        <p><b>Bonus.</b> Se esce un bonus su cui hai puntato parte il minigioco, e vinci la puntata moltiplicata per il premio del minigioco (più la puntata indietro):</p>
        <ul>
          <li><b>Coin Flip</b> (4 spicchi): due moltiplicatori, uno rosso e uno blu; la moneta decide quale vinci.</li>
          <li><b>Pachinko</b> (2 spicchi): un disco cade tra i chiodi e finisce in una buca. Se è DOUBLE, tutti i premi raddoppiano e si rilancia.</li>
          <li><b>Cash Hunt</b> (2 spicchi): 108 premi si coprono e si mescolano; tocchi un bersaglio e prendi quello che c'è dietro.</li>
          <li><b>Crazy Time</b> (1 spicchio): scegli una bandierina e la ruota gigante gira; DOUBLE e TRIPLE moltiplicano tutti i premi e si rigira.</li>
        </ul>
        <p>Se il bonus esce ma non ci avevi puntato, non vinci niente. Se chiudi l'app durante un bonus, lo ritrovi qui. Ogni giro lo estrae il server; in media la ruota restituisce circa il 94% di quello che si punta.</p>
      </div>}
    </section>

    {bonusAperto && attesa?.esito === 'ch' && <CashHunt attesa={attesa} scegli={scegli} suoni={suoni} onFine={fineBonus} />}
    {bonusAperto && attesa?.esito === 'ct' && <CrazyBonus attesa={attesa} scegli={scegli} suoni={suoni} onFine={fineBonus} />}
    {bonusAperto && !attesa && giro?.esito === 'cf' && giro.bonus && <CoinFlip bonus={giro.bonus as BonusCf} molt={moltBonus} puntata={giro.puntate.cf ?? 0} vinto={giro.vinto} suoni={suoni} onFine={() => fineBonus({ vinto: giro.vinto, crediti: giro.crediti })} />}
    {bonusAperto && !attesa && giro?.esito === 'pa' && giro.bonus && <Pachinko bonus={giro.bonus as BonusPa} molt={moltBonus} puntata={giro.puntate.pa ?? 0} vinto={giro.vinto} suoni={suoni} onFine={() => fineBonus({ vinto: giro.vinto, crediti: giro.crediti })} />}
  </section>
}
