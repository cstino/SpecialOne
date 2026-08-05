import type { Fixture, Match, Team } from '../types'
import { Crest } from './Crest'

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

export function FixtureScore({ fixture, match }: { fixture: Fixture; match?: Match }) {
  if (fixture.stato === 'simulata' && match) {
    return <span className="fixture-score"><b>{match.gol_home}</b><i>-</i><b>{match.gol_away}</b></span>
  }
  if (fixture.stato === 'in_corso') return <span className="fixture-status fixture-status--live">LIVE</span>
  if (fixture.stato === 'annullata') return <span className="fixture-status">ANN.</span>
  // L'orario e' gia' nell'intestazione della giornata: qui serve solo il segno
  // che separa le due squadre.
  return <span className="fixture-time">VS</span>
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
  if (loading) return <section className="season-state"><span className="season-loader" /><h2>Preparo la stagione…</h2><p>Recupero calendario, risultati e classifica.</p></section>
  if (error) return <section className="season-state"><span className="season-state__icon">!</span><h2>Dati non disponibili</h2><p>{error}</p><button className="button button--primary" type="button" onClick={onRetry}>Riprova</button></section>
  return null
}
