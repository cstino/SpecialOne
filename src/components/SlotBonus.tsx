import { useCallback, useEffect, useRef, useState } from 'react'
import { supabase } from '../lib/supabase'
import { Contatore, Festa, fmt, ridotto } from './Casino'
import type { useSuoni } from './Casino'
import { Pallone, Scudo } from './SimboliBonus'

// Minigiochi di SlotOne: "Scegli lo stemma" (9 scudi, se ne scoprono 3, vince la somma) e "Calcio di rigore" (5 tiri, il
// primo parato chiude). L'esito lo estrae il SERVER quando scattano (casino_slot_bonus, segreto): qui si disegna soltanto
// quello che il server rivela mossa dopo mossa. Il premio e' gia' pagato quando il minigioco finisce (casino_slot_bonus_gioca).

type Suoni = ReturnType<typeof useSuoni>
type Mossa = { i?: number; v?: number; zona?: number; gol?: boolean; portiere?: number }
type Bonus = { id: number; tipo: 'stemma' | 'rigori'; puntata: number; finito: boolean; scade: number; mosse: Mossa[]; molt: number; premio: number | null; tavola?: number[] | null }
type Risposta = { bonus: Bonus | null; crediti: number }

const SCALA_RIGORI = [1, 2, 4, 8, 25, 120]   // premio (x puntata) per 0..5 gol, come private.casino_bonus_molt
const classeValore = (v: number) => (v >= 100 ? 'oro' : v >= 25 ? 'magenta' : v >= 5 ? 'ciano' : 'base')

// ---------- Disegni (i simboli stanno in SimboliBonus.tsx) ----------
function Portiere() {
  return <svg viewBox="0 0 60 90" className="sbr__portiere-svg" aria-hidden="true">
    <defs><linearGradient id="sbMaglia" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stopColor="#ffe27a" /><stop offset="1" stopColor="#d99b17" /></linearGradient></defs>
    <circle cx="30" cy="12" r="9" fill="#f1c9a0" stroke="#3a2a14" strokeWidth="1.5" />
    <path d="M22 9c2-6 14-6 16 0-3-2-13-2-16 0z" fill="#2b2118" />
    <path d="M16 24c0-4 4-6 14-6s14 2 14 6l4 26-10 3-2-14-6 2-6-2-2 14-10-3z" fill="url(#sbMaglia)" stroke="#6b4608" strokeWidth="1.6" strokeLinejoin="round" />
    <rect x="11" y="44" width="11" height="13" rx="5" fill="#fff" stroke="#999" strokeWidth="1.2" />
    <rect x="38" y="44" width="11" height="13" rx="5" fill="#fff" stroke="#999" strokeWidth="1.2" />
    <path d="M22 54h16l3 26H19z" fill="#1d1f3a" stroke="#0e1024" strokeWidth="1.5" strokeLinejoin="round" />
    <rect x="20" y="78" width="8" height="9" rx="3" fill="#fff" /><rect x="32" y="78" width="8" height="9" rx="3" fill="#fff" />
  </svg>
}

// ---------- Scegli lo stemma ----------
function Stemma({ b, puntata, occupato, resto, scegli }: { b: Bonus; puntata: number; occupato: boolean; resto: boolean; scegli: (i: number) => void }) {
  const aperti = new Map(b.mosse.map((m) => [m.i as number, m.v as number]))
  const mancano = 3 - b.mosse.length
  return <div className="sb-stemma">
    <div className="sb-contatori">
      <span className="sb-pallini" aria-label={`${mancano} scudi da scoprire`}>{[0, 1, 2].map((k) => <i key={k} className={k < b.mosse.length ? 'is-fatto' : ''} />)}</span>
      <span className="sb-somma"><small>Totale</small><strong>×{b.molt}</strong><em>{fmt(b.molt * puntata)} crediti</em></span>
    </div>
    <div className="sb-scudi" role="group" aria-label="Scudi">
      {Array.from({ length: 9 }, (_, i) => {
        const mio = aperti.has(i), valore = mio ? aperti.get(i)! : (resto && b.tavola ? b.tavola[i] : null)
        const girato = valore != null
        return <button key={i} type="button" className={`sb-scudo${mio ? ' is-mio' : ''}${girato && !mio ? ' is-resto' : ''}${girato ? ` sb-scudo--${classeValore(valore!)}` : ''}`} style={{ ['--r' as string]: `${(i * 0.37) % 1.4}s` }}
          disabled={occupato || b.finito || girato} onClick={() => scegli(i)} aria-label={girato ? `Scudo con ×${valore}` : 'Scudo coperto'}>
          <span className="sb-scudo__giro">
            <span className="sb-scudo__fronte"><Scudo /></span>
            <span className="sb-scudo__retro"><b>×{valore ?? ''}</b><small>{valore != null ? fmt(valore * puntata) : ''}</small></span>
          </span>
        </button>
      })}
    </div>
    <p className="sb-nota">{resto ? 'Gli altri scudi nascondevano questi premi.' : mancano === 3 ? 'Tocca uno scudo per scoprire il premio.' : `Ancora ${mancano} ${mancano === 1 ? 'scudo' : 'scudi'}.`}</p>
  </div>
}

// ---------- Calcio di rigore ----------
type Anim = { zona: number; portiere: number | null; gol: boolean | null; fase: 'volo' | 'esito' }

function Rigori({ b, puntata, anim, tira, occupato }: { b: Bonus; puntata: number; anim: Anim | null; tira: (zona: number) => void; occupato: boolean }) {
  const gol = b.mosse.filter((m) => m.gol).length
  const attuale = SCALA_RIGORI[Math.min(gol, 5)]
  return <div className="sb-rigori">
    <div className="sbr__tiri" aria-label={`Rigore ${Math.min(b.mosse.length + (b.finito ? 0 : 1), 5)} di 5`}>
      {Array.from({ length: 5 }, (_, k) => { const m = b.mosse[k]; return <i key={k} className={m ? (m.gol ? 'is-gol' : 'is-parato') : k === b.mosse.length && !b.finito ? 'is-ora' : ''}>{m ? (m.gol ? '✓' : '✕') : ''}</i> })}
    </div>
    <div className="sbr__campo" data-tiro={anim?.zona} data-tuffo={anim?.portiere ?? undefined} data-fase={anim?.fase}>
      <div className={`sbr__porta${anim?.fase === 'esito' && anim.gol ? ' is-gol' : ''}`}>
        <div className="sbr__rete" />
        <span className="sbr__portiere"><Portiere /></span>
        {[0, 1, 2].map((z) => <button key={z} type="button" className="sbr__zona" disabled={occupato || b.finito} onClick={() => tira(z)} aria-label={['Tira a sinistra', 'Tira al centro', 'Tira a destra'][z]}><i /></button>)}
      </div>
      <span className="sbr__pallone"><Pallone className="sbr__pallone-svg" /></span>
      {anim?.fase === 'esito' && <div className={`sbr__esito ${anim.gol ? 'is-gol' : 'is-parato'}`} role="status">{anim.gol ? 'GOL!' : 'PARATO!'}</div>}
    </div>
    <ol className="sbr__scala" aria-label="Premi">
      {SCALA_RIGORI.map((m, k) => <li key={k} className={k === Math.min(gol, 5) ? 'is-attuale' : k < gol ? 'is-fatto' : ''}><b>×{m}</b><small>{k} gol</small></li>)}
    </ol>
    <p className="sb-nota">{b.finito ? 'Il rigore finale è stato calciato.' : b.mosse.length === 0 ? 'Scegli dove tirare. Se il portiere para, il bonus finisce.' : <>Se ti fermi ora vinci <b>{fmt(attuale * puntata)}</b> crediti.</>}</p>
  </div>
}

// ---------- Finestra dei minigiochi ----------
export default function SlotBonus({ leagueId, bonusId, tipoIniziale, suoni, onFine }: { leagueId: number; bonusId: number; tipoIniziale: 'stemma' | 'rigori'; suoni: Suoni; onFine: (crediti: number) => void }) {
  const [b, setB] = useState<Bonus | null>(null)
  const [crediti, setCrediti] = useState<number | null>(null)
  const [occupato, setOccupato] = useState(false)
  const [errore, setErrore] = useState('')
  const [anim, setAnim] = useState<Anim | null>(null)
  const [fine, setFine] = useState(false)             // pannello "Hai vinto" dopo le animazioni
  const [resto, setResto] = useState(false)           // scudi non scelti: si girano un attimo dopo l'ultima scelta
  const [festa, setFesta] = useState(0)
  const chiuso = useRef(false)

  useEffect(() => {
    let vivo = true
    void supabase.rpc('casino_slot_bonus_stato', { p_league_id: leagueId }).then(({ data, error }) => {
      if (!vivo) return
      if (error) { setErrore(error.message); return }
      const r = data as Risposta
      setCrediti(r.crediti)
      if (!r.bonus) { chiuso.current = true; onFine(r.crediti); return }   // gia' chiuso dal server (scaduto): premio gia' pagato
      setB(r.bonus)
      if (r.bonus.finito) { setFine(true); setResto(true) }
    })
    return () => { vivo = false }
  }, [leagueId]) // eslint-disable-line react-hooks/exhaustive-deps

  const chiama = useCallback(async (mossa: number) => {
    const { data, error } = await supabase.rpc('casino_slot_bonus_gioca', { p_league_id: leagueId, p_bonus_id: bonusId, p_mossa: mossa })
    if (error) { setErrore(error.message); return null }
    return data as Risposta
  }, [leagueId, bonusId])

  const veloce = ridotto()
  const finisci = (r: Risposta, b2: Bonus) => {
    setCrediti(r.crediti)
    window.setTimeout(() => setResto(true), veloce ? 100 : 700)
    window.setTimeout(() => {
      setFine(true)
      if (b2.molt >= 20) { suoni.grande(); setFesta((n) => n + 1) } else suoni.vincita()
    }, veloce ? 200 : b2.tipo === 'stemma' ? 1300 : 1500)
  }

  async function scegli(i: number) {
    if (occupato || !b || b.finito) return
    setOccupato(true); setErrore(''); suoni.tick(i)
    const r = await chiama(i)
    if (!r || !r.bonus) { setOccupato(false); return }
    setB(r.bonus)
    const m = r.bonus.mosse.find((x) => x.i === i)
    if (m?.v != null) { suoni.moneta(Math.min(8, m.v)); if (m.v >= 25) suoni.coppe() }
    setOccupato(false)
    if (r.bonus.finito) finisci(r, r.bonus)
  }

  async function tira(zona: number) {
    if (occupato || !b || b.finito) return
    setOccupato(true); setErrore('')
    suoni.leva(); setAnim({ zona, portiere: null, gol: null, fase: 'volo' })
    const r = await chiama(zona)
    if (!r || !r.bonus) { setAnim(null); setOccupato(false); return }
    const m = r.bonus.mosse[r.bonus.mosse.length - 1]
    setAnim({ zona, portiere: m.portiere ?? zona, gol: m.gol ?? false, fase: 'volo' })
    window.setTimeout(() => {
      setB(r.bonus)
      setAnim({ zona, portiere: m.portiere ?? zona, gol: m.gol ?? false, fase: 'esito' })
      if (m.gol) { suoni.vincita(); suoni.moneta(3) } else suoni.stop(0)
    }, veloce ? 100 : 700)
    window.setTimeout(() => {
      setAnim(null); setOccupato(false)
      if (r.bonus!.finito) finisci(r, r.bonus!)
    }, veloce ? 400 : 2100)
  }

  const chiudi = () => { if (chiuso.current) return; chiuso.current = true; onFine(crediti ?? 0) }
  const tipo = b?.tipo ?? tipoIniziale
  const vinto = (b?.premio ?? 0)

  return <div className={`sb sb--${tipo}`} role="dialog" aria-modal="true" aria-label={tipo === 'stemma' ? 'Scegli lo stemma' : 'Calcio di rigore'}>
    <div className="sb__luci" aria-hidden="true" />
    <div className="sb__scena">
      <header className="sb__testa">
        <small>BONUS SLOTONE</small>
        <h2>{tipo === 'stemma' ? <>SCEGLI LO <b>STEMMA</b></> : <>CALCIO DI <b>RIGORE</b></>}</h2>
        <p>{tipo === 'stemma' ? 'Scopri 3 scudi: vinci la somma dei premi.' : '5 rigori: ogni gol alza il premio, un parato ti ferma.'}</p>
      </header>

      {!b ? <p className="sb-nota">{errore || 'Preparo il bonus…'}</p>
        : tipo === 'stemma' ? <Stemma b={b} puntata={b.puntata} occupato={occupato} resto={resto} scegli={(i) => void scegli(i)} />
          : <Rigori b={b} puntata={b.puntata} anim={anim} tira={(z) => void tira(z)} occupato={occupato} />}

      {errore && b && <p className="sb-errore" role="alert">{errore}</p>}

      {fine && b && <div className="sb-fine" role="status">
        <small>{vinto > 0 ? 'HAI VINTO' : 'BONUS FINITO'}</small>
        <strong>+<Contatore valore={vinto} /></strong>
        <span>{b.tipo === 'stemma' ? `×${b.molt} sulla puntata di ${fmt(b.puntata)}` : `${b.mosse.filter((m) => m.gol).length} gol su ${b.mosse.length} ${b.mosse.length === 1 ? 'rigore' : 'rigori'}, ×${b.molt}`}</span>
        <button type="button" className="sb-incassa" onClick={chiudi}>INCASSA</button>
      </div>}
      {!fine && b && <p className="sb-timer">Hai 3 minuti per giocare: poi le mosse restanti si fanno da sole.</p>}
    </div>
    <Festa key={festa} attiva={festa > 0} />
  </div>
}
