import { useLayoutEffect, useRef, useState } from 'react'
import type { Fixture, Match, Team } from '../types'
import { Crest } from './Crest'
import { LoadingLogo } from './LoadingLogo'

// Canvas condiviso solo per misurare il testo (mai disegnato/allegato al
// DOM): measureText e' molto piu' economico di un reflow reale, e un solo
// canvas basta per tutte le misurazioni della sessione.
let canvasMisura: HTMLCanvasElement | null = null
function larghezzaTesto(testo: string, font: string) {
  if (!canvasMisura) canvasMisura = document.createElement('canvas')
  const ctx = canvasMisura.getContext('2d')
  if (!ctx) return testo.length * 20
  ctx.font = font
  return ctx.measureText(testo).width
}

// Titolo che sta sempre su una riga, riducendo la dimensione del carattere
// finche' non entra nel contenitore (con un margine di sicurezza), invece
// di andare a capo o uscire dai bordi come un h1 a clamp() fisso. Pensato
// per nomi squadra di lunghezza qualsiasi.
export function TitoloAdattivo({ testo, className, taglioMassimo = 67, taglioMinimo = 22 }: { testo: string; className?: string; taglioMassimo?: number; taglioMinimo?: number }) {
  const ref = useRef<HTMLHeadingElement>(null)
  const [taglia, setTaglia] = useState<number | null>(null)

  useLayoutEffect(() => {
    const nodo = ref.current
    const contenitore = nodo?.parentElement
    if (!nodo || !contenitore) return

    function adatta() {
      const larghezzaDisponibile = contenitore!.clientWidth * 0.96 // margine di sicurezza
      if (larghezzaDisponibile <= 0) return
      const stile = getComputedStyle(nodo!)
      let candidata = taglioMassimo
      while (candidata > taglioMinimo && larghezzaTesto(testo, `${stile.fontWeight} ${candidata}px ${stile.fontFamily}`) > larghezzaDisponibile) {
        candidata -= 1
      }
      setTaglia(candidata)
    }

    adatta()
    const osservatore = new ResizeObserver(adatta)
    osservatore.observe(contenitore)
    return () => osservatore.disconnect()
  }, [testo, taglioMassimo, taglioMinimo])

  return <h1 ref={ref} className={className} style={taglia ? { fontSize: taglia, whiteSpace: 'nowrap' } : { whiteSpace: 'nowrap', visibility: 'hidden' }}>{testo}</h1>
}

export function formatMatchDate(value: string, withTime = true) {
  return new Intl.DateTimeFormat('it-IT', {
    weekday: 'short', day: '2-digit', month: 'short',
    ...(withTime ? { hour: '2-digit', minute: '2-digit' } : {}),
    timeZone: 'Europe/Rome',
  }).format(new Date(value))
}

export function TeamLabel({ team, imageUrl, reversed = false, onClick }: { team?: Team; imageUrl?: string | null; reversed?: boolean; onClick?: () => void }) {
  const content = <><Crest value={team?.stemma_url ?? null} imageUrl={imageUrl} size="small" /><strong>{team?.nome ?? 'Squadra'}</strong></>
  if (onClick) return <button className={`season-team season-team-button ${reversed ? 'season-team--reversed' : ''}`} type="button" onClick={(event) => { event.stopPropagation(); onClick() }}>{content}</button>
  return <span className={`season-team ${reversed ? 'season-team--reversed' : ''}`}>{content}</span>
}

export function FixtureScore({ fixture, match, reveal = false }: { fixture: Fixture; match?: Match; reveal?: boolean }) {
  const esito = fixture.stato === 'simulata' && match
    ? reveal ? <span className="fixture-reveal">VEDI<br />RISULTATO</span> : <span className="fixture-score"><b>{match.gol_home}</b><i>-</i><b>{match.gol_away}</b></span>
    : fixture.stato === 'in_corso' ? <span className="fixture-status fixture-status--live">LIVE</span>
    : fixture.stato === 'annullata' ? <span className="fixture-status">ANN.</span>
    // L'orario e' gia' nell'intestazione della giornata: qui serve solo il
    // segno che separa le due squadre.
    : <span className="fixture-time">VS</span>
  // Un solo elemento radice in ogni caso (mai un Fragment con due figli),
  // perche' i contenitori chiamanti sono griglie a 3 colonne fisse che si
  // aspettano esattamente un elemento qui in mezzo.
  const mostraRisultato = fixture.stato === 'simulata' && match && !reveal
  // Playoff/playout (design §10.7): il punteggio dai dischetti e i
  // supplementari cambiano la lettura del risultato, vanno detti.
  const nota = !mostraRisultato ? null
    : match.rigori_home !== null && match.rigori_away !== null
      ? `Rigori ${match.rigori_home}-${match.rigori_away}`
      : match.gol_home_90 !== null ? 'Dopo i supplementari'
      // Ultimo girone di un campionato a gironi dispari (design.md §6.6):
      // niente vantaggio casa. Nelle finali di tabellone e' la norma.
      : fixture.campo_neutro ? 'Campo neutro'
      : null
  const notaFuoriPartita = !mostraRisultato && fixture.campo_neutro ? 'Campo neutro' : null
  const testo = nota ?? notaFuoriPartita
  if (!testo) return esito
  return <span className="fixture-score-wrap">{esito}<em className="fixture-neutral">{testo}</em></span>
}

export type Esito = 'V' | 'N' | 'P'

// Ultimi cinque risultati di ogni squadra, in ordine cronologico. Le fixture
// arrivano gia' ordinate per giornata, quindi la coda e' la parte recente.
export function formaPerSquadra(fixtures: Fixture[], matchByFixture: Map<number, Match>) {
  const mappa = new Map<number, Esito[]>()
  for (const fixture of fixtures) {
    if (fixture.stato !== 'simulata') continue
    const match = matchByFixture.get(fixture.id)
    if (!match) continue
    const lati = [
      [fixture.home_team_id, match.gol_home, match.gol_away],
      [fixture.away_team_id, match.gol_away, match.gol_home],
    ] as const
    for (const [teamId, propri, subiti] of lati) {
      const esito: Esito = propri > subiti ? 'V' : propri < subiti ? 'P' : 'N'
      mappa.set(teamId, [...(mappa.get(teamId) ?? []), esito])
    }
  }
  for (const [teamId, lista] of mappa) mappa.set(teamId, lista.slice(-5))
  return mappa
}

export function Forma({ esiti, slot = 5 }: { esiti?: Esito[]; slot?: number }) {
  const lista = esiti ?? []
  return <span className="forma-chip">
    {lista.map((esito, indice) => <span className={`esito esito--${esito}`} key={`e${indice}`}>{esito}</span>)}
    {Array.from({ length: Math.max(0, slot - lista.length) }).map((_, indice) => <span className="esito esito--vuoto" key={`v${indice}`} aria-hidden="true">·</span>)}
  </span>
}

export function SeasonState({ loading, error, onRetry }: { loading: boolean; error: string | null; onRetry: () => void }) {
  if (loading) return <section className="season-state"><LoadingLogo compatto /><h2>Preparo la stagione…</h2><p>Recupero calendario, risultati e classifica.</p></section>
  if (error) return <section className="season-state"><span className="season-state__icon">!</span><h2>Dati non disponibili</h2><p>{error}</p><button className="button button--primary" type="button" onClick={onRetry}>Riprova</button></section>
  return null
}
