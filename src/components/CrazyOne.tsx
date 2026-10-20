import { useCallback, useEffect, useMemo, useRef, useState, type ReactNode } from 'react'
import { createPortal } from 'react-dom'
import { supabase } from '../lib/supabase'
import type { useSeasonData } from '../lib/useSeasonData'
import { Contatore, Festa, fmt, ridotto, useSuoni } from './Casino'
import { Crest } from './Crest'

// BetOne Casino' › CrazyOne LIVE, il Crazy Time a tema SpecialOne (supabase/migrations/20261020190000_crazyone_live.sql).
// Una ruota per lega, uguale per tutti: 15 s per puntare, top slot, ruota, eventuale bonus; poi il giro successivo.
// Ruota a 54 spicchi: 1 (21), 2 (13), 5 (7), 10 (4), Testa o Croce (4), Mischia (2), Caccia allo Stemma (2), CrazyOne (1).
// I codici interni restano quelli del gioco originale: cf = coin flip, pa = pachinko, ch = cash hunt, ct = crazy time.
// Prima di ogni giro la top slot puo' accendere un moltiplicatore (×2-×50) su una casella.
// Tutto lo estrae il SERVER (casino_ct_gira / casino_ct_scegli): qui si anima soltanto il risultato.

export type Casella = '1' | '2' | '5' | '10' | 'cf' | 'pa' | 'ch' | 'ct'
// Stesso ordine di private.ct_ruota() nel database.
export const RUOTA: Casella[] = ['ct', '1', '2', '1', '5', '1', 'cf', '1', '2', '1', '2', '1', 'pa', '2', '5', '10', '5', '2', 'cf', '1', '5', '1', '2', '1',
  'ch', '1', '10', '1', '2', '1', 'cf', '1', '2', '1', '5', '1', 'pa', '2', '10', '2', '5', '2', 'cf', '1', '2', '1', '10', '1', 'ch', '1', '5', '1', '2', '1']
type Dati = ReturnType<typeof useSeasonData>
export const CASELLE: Record<Casella, { nome: string; corto: string; sigla: string; colore: string; scuro: string; testo: string; paga?: number }> = {
  '1': { nome: '1', corto: '1', sigla: '1', colore: '#2f9bea', scuro: '#13548a', testo: '#fff', paga: 1 },
  '2': { nome: '2', corto: '2', sigla: '2', colore: '#ffc93c', scuro: '#a7790b', testo: '#3a2600', paga: 2 },
  '5': { nome: '5', corto: '5', sigla: '5', colore: '#ff5fa8', scuro: '#a3245f', testo: '#fff', paga: 5 },
  '10': { nome: '10', corto: '10', sigla: '10', colore: '#8a5cff', scuro: '#4a24a8', testo: '#fff', paga: 10 },
  cf: { nome: 'Testa o Croce', corto: 'TESTA CROCE', sigla: 'TC', colore: '#1f5fd6', scuro: '#0d2f73', testo: '#fff' },
  pa: { nome: 'Mischia', corto: 'MISCHIA', sigla: 'MI', colore: '#c93bdc', scuro: '#6c1679', testo: '#fff' },
  ch: { nome: 'Caccia allo Stemma', corto: 'CACCIA', sigla: 'CS', colore: '#1fb85a', scuro: '#0b6430', testo: '#fff' },
  ct: { nome: 'CrazyOne', corto: 'CRAZYONE', sigla: 'C1', colore: '#e5262b', scuro: '#7a0d10', testo: '#fff' },
}
const ORDINE: Casella[] = ['1', '2', '5', '10', 'cf', 'pa', 'ch', 'ct']
const FICHE = [10, 20, 50, 100]
const VUOTE = (): Record<Casella, number> => ({ '1': 0, '2': 0, '5': 0, '10': 0, cf: 0, pa: 0, ch: 0, ct: 0 })
const MOLT_TOP = [2, 3, 5, 10, 15, 25, 50]
const OFFSET_BANDIERE = [0, 21, 43]
const BANDIERE = [{ nome: 'Verde', colore: '#2fe07a' }, { nome: 'Blu', colore: '#3d8bff' }, { nome: 'Gialla', colore: '#ffd23d' }]

type BonusCf = { rosso: number; blu: number; lato: 'rosso' | 'blu'; valore: number }
type BonusPa = { tavola: number[]; lanci: number[]; valore: number }

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
        <span>{puntata > 0 ? `Puntata ${fmt(puntata)}` : 'Non hai puntato su questo bonus'}{molt > 1 && <b className="ct-palco__molt">Top slot {molt}×</b>}</span>
      </header>
      {children}
    </div>
  </div>, document.body)
}

function EsitoBonus({ valore, molt, vinto, nota, onFine }: { valore: number | null; molt: number; vinto: number; nota?: string; onFine: () => void }) {
  return <div className="ct-esito-bonus" role="status">
    {valore != null && <span className="ct-esito-bonus__molt">{valore}×{molt > 1 ? <i> · top slot {molt}×</i> : null}</span>}
    {vinto > 0 ? <><strong>+<Contatore valore={vinto} /></strong><small>crediti</small></> : <small>Non avevi puntato su questo bonus</small>}
    {nota && <small>{nota}</small>}
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
  }, []) // eslint-disable-line react-hooks/exhaustive-deps -- una volta sola per giro (componente con key = giro)
  return <Palco esito="cf" molt={molt} puntata={puntata}>
    <div className="ct-cf">
      <div className={`ct-cf__lato ct-cf__lato--rosso${fase === 'esito' && bonus.lato === 'rosso' ? ' is-vince' : ''}${fase === 'esito' && bonus.lato !== 'rosso' ? ' is-perde' : ''}`}><b>{bonus.rosso}×</b><small><img src="/specialone-mark.svg" alt="" />Testa</small></div>
      <div className="ct-cf__arena"><div ref={moneta} className={`ct-cf__moneta${fase !== 'valori' ? ' is-lanciata' : ''}`}>
        <span className="ct-cf__faccia ct-cf__faccia--rosso"><img src="/specialone-mark.svg" alt="" /><b>{bonus.rosso}×</b></span>
        <span className="ct-cf__faccia ct-cf__faccia--blu"><svg className="ct-cf__pallone" viewBox="-10 -10 20 20" aria-hidden="true"><circle r="9.2" fill="#fff" stroke="#111" strokeWidth=".9" /><path d="M0,-3.6 L3.42,-1.11 L2.11,2.91 L-2.11,2.91 L-3.42,-1.11 Z" fill="#111" /><path d="M0,-3.6 L0,-9 M3.42,-1.11 L8.6,-2.8 M2.11,2.91 L5.3,7.3 M-2.11,2.91 L-5.3,7.3 M-3.42,-1.11 L-8.6,-2.8" stroke="#111" strokeWidth=".9" /></svg><b>{bonus.blu}×</b></span>
      </div></div>
      <div className={`ct-cf__lato ct-cf__lato--blu${fase === 'esito' && bonus.lato === 'blu' ? ' is-vince' : ''}${fase === 'esito' && bonus.lato !== 'blu' ? ' is-perde' : ''}`}><b>{bonus.blu}×</b><small><svg className="ct-cf__pallone" viewBox="-10 -10 20 20" aria-hidden="true"><circle r="9.2" fill="#fff" stroke="#111" strokeWidth=".9" /><path d="M0,-3.6 L3.42,-1.11 L2.11,2.91 L-2.11,2.91 L-3.42,-1.11 Z" fill="#111" /><path d="M0,-3.6 L0,-9 M3.42,-1.11 L8.6,-2.8 M2.11,2.91 L5.3,7.3 M-2.11,2.91 L-5.3,7.3 M-3.42,-1.11 L-8.6,-2.8" stroke="#111" strokeWidth=".9" /></svg>Croce</small></div>
    </div>
    {fase === 'esito' ? <EsitoBonus valore={bonus.valore} molt={molt} vinto={vinto} onFine={onFine} /> : <p className="ct-palco__nota">{fase === 'valori' ? 'Due moltiplicatori: uno su testa, uno su croce…' : 'L\'arbitro lancia la monetina!'}</p>}
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
  const disco = useRef<SVGGElement>(null)
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
              disco.current?.setAttribute('transform', `translate(${x0 + (x1 - x0) * e} ${y0 + (y1 - y0) * e - Math.sin(Math.PI * e) * 7}) rotate(${(k + e) * 70})`)
              if (e < 1) requestAnimationFrame(f); else ok()
            }
            requestAnimationFrame(f)
          })
          if (k > 0) suoni.tick(k)
        }
        // Caduta nella buca.
        disco.current?.setAttribute('transform', `translate(${(arrivo + 0.5) * PA_L} ${PA_Y0 + PA_RIGHE * PA_DY + 34})`)
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
  }, []) // eslint-disable-line react-hooks/exhaustive-deps -- una volta sola per giro (componente con key = giro)
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
        <g ref={disco} className="ct-pa__pallone" transform={`translate(${8 * PA_L} 6)`}>
          <circle r="7.5" fill="#fff" stroke="#111" strokeWidth=".8" />
          <path d="M0,-3 L2.85,-0.93 L1.76,2.43 L-1.76,2.43 L-2.85,-0.93 Z" fill="#111" />
          <path d="M0,-3 L0,-7.2 M2.85,-0.93 L6.8,-2.2 M1.76,2.43 L4.2,5.8 M-1.76,2.43 L-4.2,5.8 M-2.85,-0.93 L-6.8,-2.2" stroke="#111" strokeWidth=".8" />
        </g>
      </svg>
      {doppi > 1 && <span className="ct-pa__doppi">Tutto ×{doppi}</span>}
    </div>
    {fine ? <EsitoBonus valore={bonus.valore} molt={molt} vinto={vinto} onFine={onFine} /> : <p className="ct-palco__nota">{flash ? 'DOUBLE! Tutti i premi raddoppiano, si rimette il pallone in area.' : 'Mischia in area: il pallone rimbalza tra i difensori…'}</p>}
  </Palco>
}

// ---------- Caccia allo Stemma (live) ----------
// Tutti vedono i premi, poi gli stemmi li coprono e si mescolano; chi ha puntato sceglie uno stemma entro la scadenza
// (si puo' cambiare). Le posizioni dei premi le rivela il server solo a scelte chiuse.
function CashHuntLive({ giro, mia, molt, vinto, trascorso, dati, scegli, suoni, onChiudi }: {
  giro: GiroLive; mia: GiocataLive | undefined; molt: number; vinto: number | null; trascorso: number; dati: Dati
  scegli: (n: number) => void; suoni: ReturnType<typeof useSuoni>; onChiudi: () => void
}) {
  const puntata = mia?.puntate?.ch ?? 0
  const [fase, setFase] = useState<'mostra' | 'mescola' | 'scegli' | 'rivela' | 'tutti'>(trascorso > 4500 ? 'scegli' : 'mostra')
  const anteprima = useMemo(() => [...(giro.valori ?? [])].sort(() => Math.random() - 0.5), [giro.id]) // eslint-disable-line react-hooks/exhaustive-deps
  const audio = useRef(suoni); audio.current = suoni
  useEffect(() => {
    if (fase !== 'mostra') return
    let vivo = true
    void (async () => { await aspetta(2600); if (!vivo) return; setFase('mescola'); audio.current.leva(); await aspetta(1500); if (vivo) setFase('scegli') })()
    return () => { vivo = false }
  }, []) // eslint-disable-line react-hooks/exhaustive-deps
  // A scelte chiuse arrivano le posizioni: si scopre lo stemma scelto, poi tutti gli altri.
  useEffect(() => {
    if (!giro.tavola || fase === 'rivela' || fase === 'tutti') return
    let vivo = true
    setFase('rivela'); audio.current.coppe()
    void aspetta(1300).then(() => { if (vivo) setFase('tutti') })
    return () => { vivo = false }
  }, [giro.tavola]) // eslint-disable-line react-hooks/exhaustive-deps
  const scelta = mia?.scelta ?? null
  const coperte = fase === 'mescola' || fase === 'scegli'
  const squadre = dati.teams
  return <Palco esito="ch" molt={molt} puntata={puntata}>
    <div className={`ct-ch${fase === 'mescola' ? ' is-mescola' : ''}`}>
      {Array.from({ length: 108 }, (_, i) => {
        const scelto = scelta === i
        const valore = giro.tavola ? giro.tavola[i] : anteprima[i]
        const visibile = fase === 'mostra' || (fase === 'rivela' && scelto) || fase === 'tutti'
        return <button key={i} type="button" disabled={fase !== 'scegli' || puntata === 0} onClick={() => { scegli(i); audio.current.moneta(i) }}
          className={`ct-ch__bersaglio${visibile ? ' is-scoperto' : ''}${coperte ? ' is-coperto' : ''}${scelto ? ' is-scelto' : ''}${fase === 'tutti' && !scelto ? ' is-altro' : ''}`}
          style={{ animationDelay: `${(i % 9) * 0.03 + Math.floor(i / 9) * 0.02}s` }} aria-label={visibile ? `${valore}×` : `Bersaglio ${i + 1}`}>
          {visibile ? <b>{valore}×</b> : squadre.length ? <Crest value={squadre[i % squadre.length].stemma_url ?? null} imageUrl={dati.crestUrlByTeamId.get(squadre[i % squadre.length].id)} size="small" /> : <img src="/specialone-mark.svg" alt="" />}
        </button>
      })}
    </div>
    {fase === 'tutti'
      ? (puntata > 0 && giro.tavola && scelta != null && vinto != null
        ? <EsitoBonus valore={giro.tavola[scelta]} molt={molt} vinto={vinto} nota={mia?.scelta_auto ? 'Stemma scelto a caso: non avevi scelto in tempo.' : undefined} onFine={onChiudi} />
        : <EsitoBonus valore={null} molt={molt} vinto={0} onFine={onChiudi} />)
      : <p className="ct-palco__nota">{fase === 'mostra' ? 'Ecco i premi in palio: guardali bene…' : fase === 'mescola' ? 'Gli stemmi coprono i premi e si mescolano…'
        : fase === 'scegli' ? (puntata === 0 ? 'Non hai puntato su questo bonus: guardi gli altri scegliere.' : scelta != null ? 'Stemma scelto: puoi ancora cambiarlo finché il tempo non scade.' : 'Tocca uno stemma: dietro c\'è il tuo premio.') : ''}
        {fase === 'scegli' && <Scadenza fino={giro.scelta_fine ?? 0} />}</p>}
  </Palco>
}

// Secondi che mancano a una scadenza (orologio allineato al server).
function Scadenza({ fino }: { fino: number }) {
  const [, aggiorna] = useState(0)
  useEffect(() => { const t = window.setInterval(() => aggiorna((n) => n + 1), 250); return () => window.clearInterval(t) }, [])
  const resto = Math.max(0, Math.ceil((fino - oraServer()) / 1000))
  return <b className="ct-scadenza"> {resto}s</b>
}

// ---------- CrazyOne (bonus, live) ----------
const COLORI_CRAZY = ['#e5262b', '#ffc93c', '#2f9bea', '#1fb85a', '#ff5fa8', '#8a5cff', '#ff8a1f', '#13c5c9']
// Stesso cammino di private.ct_cammino_crazy: la bandierina legge lo spicchio sotto di se', DOUBLE/TRIPLE moltiplicano e si rigira.
function camminoCrazy(ruota: number[], rot: number[], flag: number) {
  let m = 1
  for (let i = 0; i < rot.length; i++) {
    const v = ruota[mod(rot[i] + OFFSET_BANDIERE[flag], 64)]
    if (v === -2) m *= 2
    else if (v === -3) m *= 3
    else return { valore: Math.min(v * m, 2000), giri: i + 1 }
  }
  return { valore: Math.min(200 * m, 2000), giri: rot.length }
}

function CrazyBonusLive({ giro, mia, molt, vinto, scegli, suoni, onChiudi }: {
  giro: GiroLive; mia: GiocataLive | undefined; molt: number; vinto: number | null
  scegli: (n: number) => void; suoni: ReturnType<typeof useSuoni>; onChiudi: () => void
}) {
  const ruota = useMemo(() => giro.ruota ?? [], [giro.ruota])
  const puntata = mia?.puntate?.ct ?? 0
  const [fase, setFase] = useState<'scegli' | 'gira' | 'esito'>('scegli')
  const [fattore, setFattore] = useState(1)
  const [annuncio, setAnnuncio] = useState('')
  const [evidenzia, setEvidenzia] = useState<number | null>(null)
  const giroRef = useRef<HTMLDivElement>(null)
  const angolo = useRef(0)
  const audio = useRef(suoni); audio.current = suoni
  const bandiera = mia?.scelta ?? null
  const spicchi: Spicchio[] = useMemo(() => ruota.map((v, i) => v === -2 ? { colore: '#f7d04a', scuro: '#8a6410', testo: '#3a2600', etichetta: 'DOUBLE', grande: false }
    : v === -3 ? { colore: '#ff9f1c', scuro: '#8a4a00', testo: '#3a1600', etichetta: 'TRIPLE', grande: false }
      : { colore: COLORI_CRAZY[i % COLORI_CRAZY.length], scuro: '#1a0b22', testo: '#fff', etichetta: `${v * fattore}×`, grande: false }), [ruota, fattore])

  // A scelte chiuse arrivano le rotazioni: la ruota gira per la mia bandierina (chi guarda segue la verde).
  useEffect(() => {
    const rot = giro.rotazioni
    if (!rot || fase !== 'scegli') return
    let vivo = true
    setFase('gira')
    const f = puntata > 0 ? (mia?.scelta ?? 0) : 0
    const percorso = camminoCrazy(ruota, rot, f)
    void (async () => {
      let fatt = 1
      for (let i = 0; i < percorso.giri; i++) {
        if (!vivo || !giroRef.current) return
        setEvidenzia(null); setAnnuncio('')
        let n = 0
        angolo.current = await giraRuota(giroRef.current, angolo.current, rot[i], 64, 4, 6500, () => audio.current.tick(n++))
        if (!vivo) return
        const seg = mod(rot[i] + OFFSET_BANDIERE[f], 64)
        setEvidenzia(seg); audio.current.stop(3)
        const v = ruota[seg]
        if (v === -2 || v === -3) {
          audio.current.coppe(); setAnnuncio(v === -2 ? 'DOUBLE! Tutti i premi ×2, si rigira' : 'TRIPLE! Tutti i premi ×3, si rigira')
          await aspetta(1400)
          fatt *= v === -2 ? 2 : 3; setFattore(fatt)
          await aspetta(700)
        }
      }
      await aspetta(600)
      if (vivo) setFase('esito')
    })()
    return () => { vivo = false }
  }, [giro.rotazioni]) // eslint-disable-line react-hooks/exhaustive-deps

  const valore = giro.rotazioni ? camminoCrazy(ruota, giro.rotazioni, puntata > 0 ? (mia?.scelta ?? 0) : 0).valore : 0
  return <Palco esito="ct" molt={molt} puntata={puntata}>
    <div className="ct-crazy">
      <div className="ct-crazy__ruota">
        <div className="ct-crazy__giro" ref={giroRef}><RuotaSvg spicchi={spicchi} evidenzia={evidenzia} /></div>
        <span className="ct-ruota__centro" aria-hidden="true"><img src="/specialone-mark.svg" alt="" /></span>
        {OFFSET_BANDIERE.map((o, f) => <span key={f} className={`ct-crazy__bandiera${bandiera === f ? ' is-mia' : ''}${bandiera != null && bandiera !== f ? ' is-spenta' : ''}`}
          style={{ ['--ang' as string]: `${o * 360 / 64}deg`, ['--col' as string]: BANDIERE[f].colore }} />)}
      </div>
      {annuncio && <p className="ct-crazy__annuncio" role="status">{annuncio}</p>}
    </div>
    {fase === 'scegli' ? <div className="ct-crazy__scelta">
      <p className="ct-palco__nota">{puntata === 0 ? 'Non hai puntato su questo bonus: guardi gli altri scegliere.' : bandiera != null ? `Bandierina ${BANDIERE[bandiera].nome.toLowerCase()}: puoi ancora cambiarla.` : 'Scegli la tua bandierina: il premio è lo spicchio che indica quando la ruota si ferma.'}<Scadenza fino={giro.scelta_fine ?? 0} /></p>
      {puntata > 0 && <div>{BANDIERE.map((b, f) => <button key={f} type="button" className={bandiera === f ? 'is-scelta' : ''} style={{ ['--col' as string]: b.colore }} onClick={() => { scegli(f); audio.current.moneta(f) }}>{b.nome}</button>)}</div>}
    </div>
      : fase === 'esito'
        ? (puntata > 0 && vinto != null
          ? <EsitoBonus valore={valore} molt={molt} vinto={vinto} nota={mia?.scelta_auto ? 'Bandierina scelta a caso: non avevi scelto in tempo.' : undefined} onFine={onChiudi} />
          : <EsitoBonus valore={puntata > 0 ? valore : null} molt={molt} vinto={0} onFine={onChiudi} />)
        : !annuncio && <p className="ct-palco__nota">La ruota gira…</p>}
  </Palco>
}

// ---------- Gioco (live) ----------
type GiocataLive = { team_id: number; totale: number; mia: boolean; vinto: number | null; puntate: Partial<Record<Casella, number>> | null; scelta: number | null; scelta_auto: boolean }
type GiroLive = {
  id: number; apre: number; chiude: number; esito_il: number; fine: number; scelta_fine: number | null; regolato: boolean
  top_casella?: Casella | null; top_molt?: number; spicchio?: number; esito?: Casella
  bonus?: BonusCf | BonusPa; valori?: number[]; tavola?: number[]; ruota?: number[]; rotazioni?: number[]
}
type StatoLive = { adesso: number; giro: GiroLive; giocate: GiocataLive[]; crediti: number; storia: Casella[] }
type FaseLive = 'puntate' | 'top' | 'ruota' | 'esito'

// Orologio del server condiviso dai componenti di questa pagina (scarto aggiornato a ogni risposta).
let scartoServer = 0
const oraServer = () => Date.now() + scartoServer

export function CrazyOne({ leagueId, dati }: { leagueId: number; dati: Dati }) {
  const [stato, setStato] = useState<StatoLive | null>(null)
  const [puntate, setPuntate] = useState<Record<Casella, number>>(VUOTE)
  const [mosse, setMosse] = useState<Array<Record<Casella, number>>>([])
  const [ultime, setUltime] = useState<Record<Casella, number> | null>(null)
  const [fiche, setFiche] = useState(10)
  const [, setTic] = useState(0)
  const [errore, setErrore] = useState('')
  const [festa, setFesta] = useState(0)
  const [bonusChiuso, setBonusChiuso] = useState<number | null>(null)
  const [spicchioFermo, setSpicchioFermo] = useState<number | null>(null)
  const [regole, setRegole] = useState(false)
  const [audio, setAudio] = useState(() => { try { return localStorage.getItem('slot-audio') !== '0' } catch { return true } })
  const suoni = useSuoni(audio)
  const suoniRef = useRef(suoni); suoniRef.current = suoni
  const ruotaRef = useRef<HTMLDivElement>(null)
  const angolo = useRef(0)
  const statoRef = useRef<StatoLive | null>(null)
  const inAttesa = useRef(false)
  const invio = useRef<number | null>(null)
  const giroAnimato = useRef<number | null>(null)
  const vincitaSuonata = useRef<number | null>(null)
  const puntateRef = useRef(puntate); puntateRef.current = puntate

  useEffect(() => { try { localStorage.setItem('slot-audio', audio ? '1' : '0') } catch { /* preferenza solo locale */ } }, [audio])

  const applica = useCallback((s: StatoLive, t0: number, t1: number) => {
    scartoServer = s.adesso - (t0 + t1) / 2
    const prima = statoRef.current
    if (prima && prima.giro.id !== s.giro.id) {
      // Giro nuovo: le fiche si tolgono dal tavolo (si possono rimettere con "Ripeti").
      const mie = prima.giocate.find((q) => q.mia)?.puntate
      if (mie) setUltime({ ...VUOTE(), ...mie } as Record<Casella, number>)
      setPuntate(VUOTE()); setMosse([]); setSpicchioFermo(null); setBonusChiuso(null)
    } else if (!prima) {
      const mie = s.giocate.find((q) => q.mia)?.puntate
      if (mie) setPuntate({ ...VUOTE(), ...mie } as Record<Casella, number>)
    }
    // I dati del bonus, una volta rivelati, non cambiano piu': si tiene lo stesso oggetto tra un aggiornamento e
    // l'altro, altrimenti le animazioni li scambiano per dati nuovi e ripartono (pallone che spariva a meta').
    if (prima && prima.giro.id === s.giro.id) {
      for (const k of ['bonus', 'valori', 'tavola', 'ruota', 'rotazioni'] as const) {
        if (prima.giro[k] != null && s.giro[k] != null) (s.giro as Record<string, unknown>)[k] = prima.giro[k]
      }
    }
    statoRef.current = s; setStato(s)
  }, [])

  const chiedi = useCallback(async (rpc: string, args: Record<string, unknown> = {}) => {
    const t0 = Date.now()
    const { data, error } = await supabase.rpc(rpc, { p_league_id: leagueId, ...args })
    const t1 = Date.now()
    if (error) { setErrore(error.message); return null }
    applica(data as StatoLive, t0, t1)
    return data as StatoLive
  }, [leagueId, applica])

  // Stato del giro ogni secondo; il tempo della pagina avanza ogni 200 ms per cambiare fase al momento giusto.
  useEffect(() => {
    let vivo = true
    const giro = async () => {
      if (!vivo || inAttesa.current || document.hidden) return
      inAttesa.current = true
      await chiedi('casino_ctl_live')
      inAttesa.current = false
    }
    void giro()
    const t = window.setInterval(() => void giro(), 1000)
    const t2 = window.setInterval(() => setTic((n) => n + 1), 200)
    return () => { vivo = false; window.clearInterval(t); window.clearInterval(t2) }
  }, [chiedi])

  const g = stato?.giro
  const adesso = oraServer()
  const fase: FaseLive = !g || adesso < g.chiude ? 'puntate' : adesso < g.chiude + 2000 ? 'top' : adesso < g.esito_il ? 'ruota' : 'esito'
  const mia = stato?.giocate.find((q) => q.mia)

  // Ruota: gira dalla fine della top slot fino all'esito (chi arriva dopo la vede gia' ferma).
  useEffect(() => {
    if (!g || g.spicchio == null || giroAnimato.current === g.id || !ruotaRef.current) return
    if (fase !== 'ruota' && fase !== 'esito') return
    giroAnimato.current = g.id
    const durata = Math.max(250, g.esito_il - oraServer())
    let n = 0
    const tardi = fase === 'esito'
    void giraRuota(ruotaRef.current, angolo.current, g.spicchio, 54, tardi ? 1 : 5, tardi ? 300 : durata, () => { if (!tardi) suoniRef.current.tick(n++) }).then((a) => {
      angolo.current = a; setSpicchioFermo(g.spicchio ?? null)
      if (!tardi) { suoniRef.current.stop(4); if (g.esito && CASELLE[g.esito].paga == null) suoniRef.current.coppe() }
    })
  }, [fase, g?.id, g?.spicchio]) // eslint-disable-line react-hooks/exhaustive-deps

  // Suono della top slot quando si ferma su una casella.
  const topVisto = useRef<number | null>(null)
  useEffect(() => {
    if (fase === 'ruota' && g && topVisto.current !== g.id) { topVisto.current = g.id; suoniRef.current.stop(1); if (g.top_casella) suoniRef.current.coppe() }
  }, [fase, g?.id]) // eslint-disable-line react-hooks/exhaustive-deps

  // Vincita sui numeri (i bonus la mostrano nel loro palco).
  useEffect(() => {
    if (!g || !g.regolato || !mia || vincitaSuonata.current === g.id || spicchioFermo == null) return
    if (g.esito && CASELLE[g.esito].paga == null) return
    vincitaSuonata.current = g.id
    if ((mia.vinto ?? 0) >= mia.totale * 20) { suoniRef.current.grande(); setFesta((x) => x + 1) } else if ((mia.vinto ?? 0) > 0) suoniRef.current.vincita()
  }, [g?.regolato, spicchioFermo]) // eslint-disable-line react-hooks/exhaustive-deps

  // Le fiche si mandano al server mezzo secondo dopo l'ultimo tocco (sostituiscono quelle registrate).
  function manda(nuove: Record<Casella, number>) {
    if (invio.current) window.clearTimeout(invio.current)
    // Negli ultimi 2 secondi le fiche partono subito, altrimenti arriverebbero a puntate chiuse.
    const giroOra = statoRef.current?.giro
    const subito = giroOra != null && giroOra.chiude - oraServer() < 2000
    invio.current = window.setTimeout(async () => {
      invio.current = null
      const mappa = Object.fromEntries(ORDINE.filter((c) => nuove[c] > 0).map((c) => [c, nuove[c]]))
      const r = await chiedi('casino_ctl_punta', { p_puntate: mappa })
      if (!r) { const reg = statoRef.current?.giocate.find((q) => q.mia)?.puntate; setPuntate({ ...VUOTE(), ...(reg ?? {}) } as Record<Casella, number>) }
      else setErrore('')
    }, subito ? 0 : 450)
  }
  function cambia(nuove: Record<Casella, number>) { setMosse((m) => [...m, puntateRef.current]); setPuntate(nuove); manda(nuove) }

  const totale = ORDINE.reduce((t, c) => t + puntate[c], 0)
  const disponibili = (stato?.crediti ?? 0) + (mia?.totale ?? 0)
  const aperte = fase === 'puntate'

  function aggiungi(c: Casella) {
    if (!aperte) return
    if (puntate[c] + fiche > 500) { setErrore('Al massimo 500 crediti su una casella.'); return }
    if (totale + fiche > 2000) { setErrore('Al massimo 2.000 crediti a giro.'); return }
    if (totale + fiche > disponibili) { setErrore('Crediti insufficienti.'); return }
    setErrore(''); suoni.moneta(ORDINE.indexOf(c)); cambia({ ...puntate, [c]: puntate[c] + fiche })
  }
  function annulla() { if (!aperte || mosse.length === 0) return; const p = mosse[mosse.length - 1]; setMosse((m) => m.slice(0, -1)); setPuntate(p); manda(p) }
  function raddoppia() {
    if (totale * 2 > 2000 || totale * 2 > disponibili || ORDINE.some((c) => puntate[c] * 2 > 500)) { setErrore('Raddoppiando superi un limite (500 per casella, 2.000 a giro, i tuoi crediti).'); return }
    cambia(Object.fromEntries(ORDINE.map((c) => [c, puntate[c] * 2])) as Record<Casella, number>)
  }
  function ripeti() {
    if (!ultime) return
    const tot = ORDINE.reduce((t, c) => t + ultime[c], 0)
    if (tot > disponibili) { setErrore('Crediti insufficienti per ripetere le puntate.'); return }
    cambia(ultime)
  }
  function svuota() { cambia(VUOTE()) }
  async function scegli(n: number) { await chiedi('casino_ctl_scegli', { p_scelta: n }) }

  if (!stato || !g) return <section className="slot-caricamento">{errore ? <p role="alert">{errore}</p> : <p>Accendo la ruota…</p>}</section>

  const esito = adesso >= g.chiude + 2000 || fase === 'esito' ? g.esito : undefined
  const moltBonus = g.esito && g.top_casella === g.esito ? g.top_molt ?? 1 : 1
  const restoPuntate = Math.max(0, Math.ceil((g.chiude - adesso) / 1000))
  const inBonus = fase === 'esito' && g.esito != null && CASELLE[g.esito].paga == null && adesso >= g.esito_il + 2000 && bonusChiuso !== g.id
  const registrate = mia?.puntate ?? {}
  const sincronizzate = ORDINE.every((c) => (registrate[c] ?? 0) === puntate[c])
  const nome = g.esito ? CASELLE[g.esito].nome : ''
  const messaggio = errore ? <span className="slot-errore">{errore}</span>
    : fase === 'puntate' ? (totale > 0 ? (sincronizzate ? `Puntate registrate: ${fmt(totale)} crediti. Puoi cambiarle finché il tempo non scade.` : 'Registro le puntate…') : 'Metti le fiche sulle caselle prima che scada il tempo.')
      : fase === 'top' ? 'Top slot…'
        : fase === 'ruota' ? 'La ruota gira…'
          : spicchioFermo == null ? 'La ruota gira…'
            : CASELLE[g.esito!].paga == null ? `${nome}!${mia?.puntate?.[g.esito!] ? '' : ' Non avevi puntato su questo bonus.'}`
              : mia ? ((mia.vinto ?? 0) > 0 ? `È uscito ${nome}: +${fmt(mia.vinto ?? 0)} crediti!` : `È uscito ${nome}. Niente stavolta.`) : `È uscito ${nome}.`
  const vincitori = g.regolato ? stato.giocate.filter((q) => (q.vinto ?? 0) > 0) : []

  return <section className="ct" onPointerDown={() => suoni.sblocca()}>
    <div className="slot-saldo">
      <div><small>I tuoi crediti</small><strong><Contatore valore={stato.crediti} /></strong></div>
      <span className="slot-ricarica av-dal-vivo"><i aria-hidden="true" />LIVE</span>
      <button type="button" className="slot-audio" aria-pressed={audio} aria-label={audio ? 'Togli i suoni' : 'Attiva i suoni'} onClick={() => setAudio((a) => !a)}>{audio ? '🔊' : '🔇'}</button>
    </div>

    <div className="ct-studio">
      <div className="ct-insegna"><img src="/specialone-mark.svg" alt="" /><span>CRAZY</span><b>ONE</b></div>
      <TopSlot gira={fase === 'top'} casella={fase === 'ruota' || fase === 'esito' ? (g.top_casella ?? null) : undefined} molt={g.top_molt ?? null} />
      <div className="ct-ruota">
        <span className="ct-ruota__lancetta" aria-hidden="true" />
        <div className="ct-ruota__giro" ref={ruotaRef}><RuotaSvg spicchi={SPICCHI_PRINCIPALI} evidenzia={spicchioFermo} /></div>
        <span className="ct-ruota__centro" aria-hidden="true"><img src="/specialone-mark.svg" alt="" /></span>
        {fase === 'puntate' && <div className="ct-conto"><small>Puntate aperte</small><b>{restoPuntate}</b></div>}
      </div>
      <ol className="ct-storia" aria-label="Ultimi risultati della lega">
        {stato.storia.length === 0 ? <li className="ct-storia__vuota">Ancora nessun giro</li>
          : stato.storia.map((c, i) => <li key={i} style={{ background: CASELLE[c].colore, color: CASELLE[c].testo }}>{CASELLE[c].sigla}</li>)}
      </ol>
      <Festa key={festa} attiva={festa > 0} />
    </div>

    <p className="slot-messaggio" role="status">{messaggio}</p>

    <div className="ct-tavolo" role="group" aria-label="Caselle su cui puntare">
      {ORDINE.map((c) => {
        const m = (fase === 'ruota' || fase === 'esito') && g.top_casella === c ? g.top_molt : null
        return <button key={c} type="button" className={`ct-casella ct-casella--${CASELLE[c].paga != null ? 'num' : 'bonus'}${spicchioFermo != null && esito === c ? ' is-uscita' : ''}`}
          style={{ ['--col' as string]: CASELLE[c].colore, ['--scuro' as string]: CASELLE[c].scuro, color: CASELLE[c].testo }}
          disabled={!aperte} onClick={() => aggiungi(c)} aria-label={`${CASELLE[c].nome}: puntata ${puntate[c]}`}>
          <b>{CASELLE[c].paga != null ? c : CASELLE[c].nome}</b>
          <small>{CASELLE[c].paga != null ? `paga ${CASELLE[c].paga}:1` : 'bonus'}</small>
          {puntate[c] > 0 && <span className="ct-casella__fiche">{puntate[c]}</span>}
          {m && <span className="ct-casella__molt">{m}×</span>}
        </button>
      })}
    </div>

    <div className="ct-comandi">
      <div className="ct-fiche" role="group" aria-label="Valore della fiche">
        {FICHE.map((f) => <button key={f} type="button" className={`fiche-casino fiche-casino--${f}${fiche === f ? ' is-scelta' : ''}`} aria-pressed={fiche === f} onClick={() => setFiche(f)}><span>{f}</span></button>)}
      </div>
      <div className="ct-azioni ct-azioni--quattro">
        <button type="button" disabled={!aperte || mosse.length === 0} onClick={annulla}>Annulla</button>
        <button type="button" disabled={!aperte || totale === 0} onClick={raddoppia}>×2</button>
        <button type="button" disabled={!aperte || !ultime || totale > 0} onClick={ripeti}>Ripeti</button>
        <button type="button" disabled={!aperte || totale === 0} onClick={svuota}>Svuota</button>
      </div>
      <div className="ct-totale"><small>{aperte ? 'Sul tavolo' : 'Puntato'}</small><b>{fmt(aperte ? totale : mia?.totale ?? 0)}</b></div>
    </div>

    <section className="av-giocate">
      <header><h2>Al tavolo</h2><span>{stato.giocate.length} {stato.giocate.length === 1 ? 'giocatore' : 'giocatori'} · {fmt(stato.giocate.reduce((t, q) => t + q.totale, 0))} crediti</span></header>
      {stato.giocate.length === 0 ? <p className="bet-nota">Nessuno ha ancora puntato su questo giro.</p> : <ol>
        {stato.giocate.map((q, i) => {
          const t = dati.teamById.get(q.team_id)
          const vinto = g.regolato && spicchioFermo != null ? q.vinto ?? 0 : null
          return <li key={`${q.team_id}-${i}`} className={`${q.mia ? 'is-mia' : ''}${vinto ? ' is-incassata' : ''}${vinto === 0 ? ' is-persa' : ''}`}>
            <span className="bet-giocatori__stemma"><Crest value={t?.stemma_url ?? null} imageUrl={dati.crestUrlByTeamId.get(q.team_id)} size="small" /></span>
            <span className="av-giocate__nome">{t?.nome ?? '—'}</span>
            <span className="av-giocate__puntata">{fmt(q.totale)}</span>
            <span className="av-giocate__esito">{vinto ? <i>+{fmt(vinto)}</i> : vinto === 0 ? '—' : ''}</span>
          </li>
        })}
      </ol>}
      {vincitori.length > 0 && spicchioFermo != null && <p className="bet-nota">{vincitori.length === 1 ? 'Ha vinto' : 'Hanno vinto'} {vincitori.map((q) => dati.teamById.get(q.team_id)?.nome ?? '—').join(', ')}.</p>}
    </section>

    <section className="slot-pannello">
      <button type="button" className="slot-pannello__tasto" aria-expanded={regole} onClick={() => setRegole((v) => !v)}>Come si gioca <span aria-hidden="true">{regole ? '−' : '+'}</span></button>
      {regole && <div className="slot-premi ct-regole">
        <p>CrazyOne è <b>live</b>: la ruota è una sola per tutta la lega e tutti vedono lo stesso giro. Ci sono <b>15 secondi per puntare</b>: scegli il valore della fiche e tocca le caselle (anche più di una; al massimo 500 crediti per casella e 2.000 a giro). Le puntate si registrano da sole e puoi cambiarle finché il tempo non scade. Al giro dopo puoi rimetterle uguali con <b>Ripeti</b>.</p>
        <p><b>Numeri.</b> Se la ruota si ferma sul tuo numero vinci la puntata moltiplicata per il numero, più la puntata indietro: 10 crediti sul 5 diventano 60. Sulla ruota ci sono 21 spicchi da 1, 13 da 2, 7 da 5 e 4 da 10.</p>
        <p><b>Top slot.</b> Quando si chiudono le puntate la top slot può accendere un moltiplicatore da 2× a 50× su una casella: se la ruota si ferma proprio lì, la vincita si moltiplica.</p>
        <p><b>Bonus.</b> Quando esce un bonus lo guardano tutti; vince chi ci aveva puntato (la puntata per il premio del bonus, più la puntata indietro):</p>
        <ul>
          <li><b>Testa o Croce</b> (4 spicchi): due moltiplicatori, uno su testa (faccia rossa col logo SpecialOne) e uno su croce (faccia blu col pallone); la monetina dell'arbitro decide quale vince.</li>
          <li><b>Mischia</b> (2 spicchi): il pallone rimbalza in area tra i difensori e finisce in una porta. Se è DOUBLE, tutti i premi raddoppiano e si rimette il pallone in area.</li>
          <li><b>Caccia allo Stemma</b> (2 spicchi): 108 premi si coprono con gli stemmi della lega e si mescolano; ognuno tocca il suo stemma e prende quello che c'è dietro.</li>
          <li><b>CrazyOne</b> (1 spicchio): ognuno sceglie una bandierina e la ruota gigante gira; DOUBLE e TRIPLE moltiplicano tutti i premi e si rigira.</li>
        </ul>
        <p>Nella Caccia allo Stemma e nel CrazyOne c'è un tempo per scegliere: chi non sceglie riceve una scelta a caso. Tutto il giro lo estrae il server prima che si chiudano le puntate; in media la ruota restituisce circa il 97% di quello che si punta.</p>
      </div>}
    </section>

    {inBonus && g.esito === 'cf' && g.bonus && <CoinFlip key={g.id} bonus={g.bonus as BonusCf} molt={moltBonus} puntata={mia?.puntate?.cf ?? 0} vinto={mia?.vinto ?? 0} suoni={suoni} onFine={() => setBonusChiuso(g.id)} />}
    {inBonus && g.esito === 'pa' && g.bonus && <Pachinko key={g.id} bonus={g.bonus as BonusPa} molt={moltBonus} puntata={mia?.puntate?.pa ?? 0} vinto={mia?.vinto ?? 0} suoni={suoni} onFine={() => setBonusChiuso(g.id)} />}
    {inBonus && g.esito === 'ch' && g.valori && <CashHuntLive key={g.id} giro={g} mia={mia} molt={moltBonus} vinto={g.regolato ? mia?.vinto ?? 0 : null} trascorso={adesso - g.esito_il - 2000} dati={dati} scegli={(n) => void scegli(n)} suoni={suoni} onChiudi={() => setBonusChiuso(g.id)} />}
    {inBonus && g.esito === 'ct' && g.ruota && <CrazyBonusLive key={g.id} giro={g} mia={mia} molt={moltBonus} vinto={g.regolato ? mia?.vinto ?? 0 : null} scegli={(n) => void scegli(n)} suoni={suoni} onChiudi={() => setBonusChiuso(g.id)} />}
  </section>
}
