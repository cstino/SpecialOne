import { useCallback, useEffect, useRef, useState } from 'react'
import { NOME_CONFERENZA, type Conferenza } from '../lib/conferenze'
import type { Standing, Team } from '../types'
import { ConferenceBadge } from './ConferenceBadge'
import { TeamLabel } from './SeasonUI'

type Props = {
  standings: Standing[]
  miaConferenza: Conferenza | null
  miaSquadraId: number
  teamById: Map<number, Team>
  crestUrlByTeamId: Map<number, string>
  onOpenTeam: (teamId: number) => void
}

const ATTESA_AUTOMATICA_MS = 5000
const RIPRESA_DOPO_TOCCO_MS = 8000
const RIGHE = 4

// «La vetta» con le conference: due schede, East e Western, che scorrono da sole una dopo l'altra. Si possono
// anche scorrere col dito o toccando i pallini; l'automatico si ferma mentre ci si interagisce e riparte dopo
// qualche secondo. Si parte dalla conference della propria squadra.
export function VettaConferenze({ standings, miaConferenza, miaSquadraId, teamById, crestUrlByTeamId, onOpenTeam }: Props) {
  const ordine: Conferenza[] = miaConferenza === 'ovest' ? ['ovest', 'est'] : ['est', 'ovest']
  const pista = useRef<HTMLDivElement | null>(null)
  const [indice, setIndice] = useState(0)
  const pausaFino = useRef(0)

  const vaiA = useCallback((i: number, dolce = true) => {
    const el = pista.current
    if (!el) return
    el.scrollTo({ left: i * el.clientWidth, behavior: dolce && !window.matchMedia('(prefers-reduced-motion: reduce)').matches ? 'smooth' : 'auto' })
  }, [])

  // Avanza da sola: una scheda ogni 5 secondi, salvo pausa (tocco, mouse sopra, scheda del browser nascosta).
  useEffect(() => {
    if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) return
    const timer = window.setInterval(() => {
      if (document.hidden || Date.now() < pausaFino.current) return
      vaiA((indice + 1) % ordine.length)
    }, ATTESA_AUTOMATICA_MS)
    return () => window.clearInterval(timer)
  }, [indice, ordine.length, vaiA])

  const metti = () => { pausaFino.current = Date.now() + RIPRESA_DOPO_TOCCO_MS }
  const alScorrimento = () => {
    const el = pista.current
    if (!el || !el.clientWidth) return
    setIndice(Math.max(0, Math.min(ordine.length - 1, Math.round(el.scrollLeft / el.clientWidth))))
  }

  const riepilogo = (c: Conferenza) => {
    const righe = standings.filter((riga) => riga.conferenza === c).sort((a, b) => (a.posizione ?? 99) - (b.posizione ?? 99))
    const vetta = righe.slice(0, RIGHE)
    const mia = righe.find((riga) => riga.team_id === miaSquadraId)
    return { vetta, miaFuori: mia && !vetta.includes(mia) ? mia : null }
  }

  const riga = (standing: Standing, index: number) => (
    <li key={standing.team_id} className={standing.team_id === miaSquadraId ? 'is-mia' : undefined} style={{ ['--i' as string]: index + 1 }}>
      <b className="dash-vetta__pos">{standing.posizione ?? index + 1}</b>
      <div className="dash-vetta__squadra"><TeamLabel team={teamById.get(standing.team_id)} imageUrl={crestUrlByTeamId.get(standing.team_id)} onClick={() => onOpenTeam(standing.team_id)} /></div>
      <strong className="dash-vetta__punti">{standing.punti}<small>pt</small></strong>
    </li>
  )

  return <div className="vetta-conf" onPointerDown={metti} onPointerEnter={metti} onFocusCapture={metti}>
    <div className="vetta-conf__pista" ref={pista} onScroll={alScorrimento} onTouchStart={metti} aria-roledescription="carosello" aria-label="La vetta delle due conference">
      {ordine.map((c, i) => {
        const { vetta, miaFuori } = riepilogo(c)
        return <section className="vetta-conf__scheda" key={c} aria-hidden={i !== indice} aria-label={NOME_CONFERENZA[c]} style={{ ['--c' as string]: c === 'est' ? '#4db3ff' : '#ff6b4a' }}>
          <header><ConferenceBadge conferenza={c} /><strong>{NOME_CONFERENZA[c]}</strong>{c === miaConferenza && <em>La tua</em>}</header>
          <ol className="dash-vetta">
            {vetta.map(riga)}
            {miaFuori && <li className="vetta-conf__separatore" aria-hidden="true">⋯</li>}
            {miaFuori && riga(miaFuori, vetta.length)}
          </ol>
        </section>
      })}
    </div>
    <div className="vetta-conf__pallini" role="tablist" aria-label="Conference">
      {ordine.map((c, i) => <button key={c} type="button" role="tab" aria-selected={i === indice} aria-label={NOME_CONFERENZA[c]}
        className={i === indice ? 'is-attivo' : ''} style={{ ['--c' as string]: c === 'est' ? '#4db3ff' : '#ff6b4a' }}
        onClick={() => { metti(); vaiA(i) }}><span /></button>)}
    </div>
  </div>
}
