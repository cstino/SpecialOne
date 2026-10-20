import { useCallback, useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'
import type { useSeasonData } from '../lib/useSeasonData'
import { Crest } from './Crest'
import { Casino, Contatore, fmt } from './Casino'
import { CrazyOne, RUOTA, CASELLE } from './CrazyOne'
import { AviatOne, AEREO_URL } from './AviatOne'

// Pagina iniziale del BetOne Casino': una fila di copertine verticali (stile home di Netflix), una per gioco.
// I crediti sono gli stessi per tutti i giochi; la classifica e' unica (miglior colpo in un solo giro, qualsiasi gioco).

type Dati = ReturnType<typeof useSeasonData>
type RigaClassifica = { team_id: number; crediti: number; max_vincita: number; giri: number }
type Gioco = 'slot' | 'crazy' | 'aviat'

const GIOCHI: Array<{ id: Gioco; titolo: string; sotto: string; nuovo?: boolean }> = [
  { id: 'aviat', titolo: 'AviatOne', sotto: 'Incassa prima che voli via', nuovo: true },
  { id: 'crazy', titolo: 'CrazyOne', sotto: 'Ruota · 4 bonus' },
  { id: 'slot', titolo: 'SlotOne', sotto: '5 rulli · 10 linee' },
]

function CopertinaSlot() {
  return <div className="cas-poster__arte cas-poster__arte--slot" aria-hidden="true">
    <div className="cas-poster__luci">{Array.from({ length: 10 }, (_, i) => <i key={i} style={{ animationDelay: `${(i % 5) * 0.15}s` }} />)}</div>
    <div className="cas-poster__rulli"><span>7</span><span><img src="/specialone-mark.svg" alt="" /></span><span>7</span></div>
  </div>
}

function CopertinaCrazy() {
  const passo = 360 / RUOTA.length
  const sfondo = `conic-gradient(from ${-passo / 2}deg, ${RUOTA.map((c, i) => `${CASELLE[c].colore} ${i * passo}deg ${(i + 1) * passo}deg`).join(', ')})`
  return <div className="cas-poster__arte cas-poster__arte--crazy" aria-hidden="true">
    <div className="cas-poster__raggi" />
    <div className="cas-poster__ruota" style={{ background: sfondo }}><span><img src="/specialone-mark.svg" alt="" /></span></div>
  </div>
}

function CopertinaAviat() {
  return <div className="cas-poster__arte cas-poster__arte--aviat" aria-hidden="true">
    <div className="cas-poster__raggi cas-poster__raggi--aviat" />
    <svg className="cas-poster__curva" viewBox="0 0 100 100" preserveAspectRatio="none"><path d="M0 100 C45 98 70 80 92 22 L92 100 Z" fill="rgba(155,92,255,.45)" /><path d="M0 100 C45 98 70 80 92 22" fill="none" stroke="#f6c453" strokeWidth="2.4" /></svg>
    <img className="cas-poster__aereo" src={AEREO_URL} alt="" />
    <span className="cas-poster__x">2.47×</span>
  </div>
}

type Props = { leagueId: number; teamId: number; dati: Dati }

export function CasinoHub({ leagueId, teamId, dati }: Props) {
  const [gioco, setGioco] = useState<Gioco | null>(null)
  const [crediti, setCrediti] = useState<number | null>(null)
  const [classifica, setClassifica] = useState<RigaClassifica[]>([])
  const [errore, setErrore] = useState('')
  const [crazyone, setCrazyone] = useState(false)
  const [aviatone, setAviatone] = useState(false)

  const carica = useCallback(async () => {
    const { data, error } = await supabase.rpc('casino_stato', { p_league_id: leagueId })
    if (error) { setErrore(error.message); return }
    setCrediti((data as { crediti: number }).crediti)
    setCrazyone((data as { crazyone?: boolean }).crazyone === true)
    setAviatone((data as { aviatone?: boolean }).aviatone === true)
    const { data: cl } = await supabase.rpc('casino_classifica', { p_league_id: leagueId })
    setClassifica((cl ?? []) as RigaClassifica[])
  }, [leagueId])
  useEffect(() => { if (gioco == null) void carica() }, [carica, gioco])

  const aggiornaClassifica = () => { void supabase.rpc('casino_classifica', { p_league_id: leagueId }).then(({ data: cl }) => setClassifica((cl ?? []) as RigaClassifica[])) }
  const tabellaClassifica = <>
  <section className="slot-classifica">
    <h2>Classifica del casinò</h2>
    <p className="bet-nota">Conta la vincita più alta ottenuta in un solo giro{crazyone || aviatone ? ', in qualsiasi gioco' : ''}.</p>
    {classifica.length === 0 ? <p className="bet-nota">Ancora nessuno al tavolo.</p> : <ol>
      {classifica.map((r, i) => {
        const t = dati.teamById.get(r.team_id)
        return <li key={r.team_id} className={r.team_id === teamId ? 'is-mia' : ''}>
          <span className={`bet-pos${i < 3 ? ` bet-pos--${i + 1}` : ''}`}>{i + 1}</span>
          <span className="bet-giocatori__stemma"><Crest value={t?.stemma_url ?? null} imageUrl={dati.crestUrlByTeamId.get(r.team_id)} size="small" /></span>
          <span className="bet-classifica__nome"><strong>{t?.nome ?? '—'}</strong><small>{fmt(r.crediti)} crediti · {fmt(r.giri)} giri</small></span>
          <span className="slot-classifica__crediti"><b>{fmt(r.max_vincita)}</b><small>miglior colpo</small></span>
        </li>
      })}
    </ol>}
  </section>
  </>

  if (crediti == null) return <section className="slot-caricamento">{errore ? <p role="alert">{errore}</p> : <p>Accendo le luci del casinò…</p>}</section>
  // Dove CrazyOne e' spento il casino' resta com'era: la slot subito, con la classifica sotto.
  if (!crazyone && !aviatone) return <section className="cas-hub"><Casino leagueId={leagueId} dati={dati} onGiro={aggiornaClassifica} />{tabellaClassifica}</section>

  if (gioco) return <section className="cas-gioco">
    <button type="button" className="cas-indietro" onClick={() => setGioco(null)}><span aria-hidden="true">‹</span> Casinò</button>
    {gioco === 'slot' ? <Casino leagueId={leagueId} dati={dati} /> : gioco === 'aviat' ? <AviatOne leagueId={leagueId} dati={dati} /> : <CrazyOne leagueId={leagueId} dati={dati} />}
  </section>

  return <section className="cas-hub">
    <div className="slot-saldo">
      <div><small>I tuoi crediti</small><strong><Contatore valore={crediti} /></strong></div>
      <span className="slot-ricarica">+1.000 gratis alle 23:00</span>
    </div>
    {errore && <p className="slot-errore" role="alert">{errore}</p>}

    <section className="cas-fila">
      <h2>Giochi</h2>
      <div className="cas-fila__scorri">
        {GIOCHI.filter((g) => (g.id !== 'crazy' || crazyone) && (g.id !== 'aviat' || aviatone)).map((g) => <button key={g.id} type="button" className={`cas-poster cas-poster--${g.id}`} onClick={() => setGioco(g.id)}>
          {g.id === 'slot' ? <CopertinaSlot /> : g.id === 'aviat' ? <CopertinaAviat /> : <CopertinaCrazy />}
          {g.nuovo && <span className="cas-poster__nuovo">Nuovo</span>}
          <span className="cas-poster__titolo"><b>{g.titolo}</b><small>{g.sotto}</small></span>
        </button>)}
        <div className="cas-poster cas-poster--presto" aria-label="Altri giochi in arrivo">
          <span className="cas-poster__presto">Prossimamente</span>
        </div>
      </div>
    </section>

    {tabellaClassifica}
  </section>
}
