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
    return <span className="fixture-score"><b>{match.gol_home}</b><i>:</i><b>{match.gol_away}</b></span>
  }
  if (fixture.stato === 'in_corso') return <span className="fixture-status fixture-status--live">LIVE</span>
  if (fixture.stato === 'annullata') return <span className="fixture-status">ANN.</span>
  return <span className="fixture-time">00:00</span>
}

export function SeasonState({ loading, error, onRetry }: { loading: boolean; error: string | null; onRetry: () => void }) {
  if (loading) return <section className="season-state"><span className="season-loader" /><h2>Preparo la stagione…</h2><p>Recupero calendario, risultati e classifica.</p></section>
  if (error) return <section className="season-state"><span className="season-state__icon">!</span><h2>Dati non disponibili</h2><p>{error}</p><button className="button button--primary" type="button" onClick={onRetry}>Riprova</button></section>
  return null
}
