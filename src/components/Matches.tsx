import { useEffect, useMemo, useState } from 'react'
import { useSeasonData } from '../lib/useSeasonData'
import type { League, Membership } from '../types'
import { GameNav, type GameView } from './GameNav'
import { FixtureScore, formatMatchDate, SeasonState, TeamLabel } from './SeasonUI'

type Props = { membership: Membership; onNavigate: (view: GameView) => void; onOpenMatch: (matchId: number) => void; onOpenTeam: (teamId: number) => void }

export function Matches({ membership, onNavigate, onOpenMatch, onOpenTeam }: Props) {
  const league = membership.league as League
  const data = useSeasonData(membership)
  const [giornata, setGiornata] = useState(1)

  useEffect(() => { if (!data.loading) setGiornata(data.currentGiornata) }, [data.currentGiornata, data.loading])
  const fixtures = useMemo(() => data.fixtures.filter((fixture) => fixture.giornata === giornata), [data.fixtures, giornata])
  const simulated = fixtures.filter((fixture) => fixture.stato === 'simulata').length

  return <main className="app-shell season-shell">
    <GameNav league={league} active="matches" onNavigate={onNavigate} />
    <header className="topbar season-topbar"><div className="brand-lockup brand-lockup--dark"><img src="/specialone-mark.svg" alt="" /><span>SpecialOne</span></div><span>Calendario ufficiale</span></header>
    <SeasonState loading={data.loading} error={data.error} onRetry={data.reload} />
    {!data.loading && !data.error && <div className="season-page season-page--narrow">
      <section className="season-title-row"><div><p className="kicker">Stagione {league.stagione_corrente} · {league.nome}</p><h1>Partite.</h1><p>Una giornata ogni notte, alle 00:00 ora italiana.</p></div><div className="season-total"><strong>{data.fixtures.length}</strong><span>partite totali</span></div></section>

      <section className="matchday-panel">
        <div className="matchday-toolbar">
          <button type="button" disabled={giornata <= 1} onClick={() => setGiornata((value) => value - 1)} aria-label="Giornata precedente">←</button>
          <label><span>GIORNATA</span><select value={giornata} onChange={(event) => setGiornata(Number(event.target.value))}>{Array.from({ length: league.giornate_totali }, (_, index) => <option key={index + 1} value={index + 1}>{index + 1} di {league.giornate_totali}</option>)}</select></label>
          <button type="button" disabled={giornata >= league.giornate_totali} onClick={() => setGiornata((value) => value + 1)} aria-label="Giornata successiva">→</button>
        </div>
        <div className="matchday-meta"><span>{fixtures[0] ? formatMatchDate(fixtures[0].data_sim, false) : 'Turno di riposo'}</span><b>{simulated === fixtures.length && fixtures.length ? 'COMPLETATA' : giornata === data.currentGiornata ? 'PROSSIMA' : 'PROGRAMMATA'}</b></div>

        <div className="fixture-list">
          {fixtures.map((fixture) => { const match = data.matchByFixture.get(fixture.id); return <article className={`fixture-row ${(fixture.home_team_id === membership.id || fixture.away_team_id === membership.id) ? 'is-mine' : ''} ${match ? 'is-clickable' : ''}`} key={fixture.id} onClick={() => match && onOpenMatch(match.id)} onKeyDown={(event) => { if (match && (event.key === 'Enter' || event.key === ' ')) { event.preventDefault(); onOpenMatch(match.id) } }} role={match ? 'button' : undefined} tabIndex={match ? 0 : undefined}>
            <TeamLabel team={data.teamById.get(fixture.home_team_id)} imageUrl={data.crestUrlByTeamId.get(fixture.home_team_id)} reversed onClick={() => onOpenTeam(fixture.home_team_id)} />
            <FixtureScore fixture={fixture} match={match} />
            <TeamLabel team={data.teamById.get(fixture.away_team_id)} imageUrl={data.crestUrlByTeamId.get(fixture.away_team_id)} onClick={() => onOpenTeam(fixture.away_team_id)} />
            {(fixture.home_team_id === membership.id || fixture.away_team_id === membership.id) && <small>LA TUA PARTITA</small>}
          </article>})}
          {!fixtures.length && <p className="season-empty">Nessuna partita in questa giornata.</p>}
        </div>
      </section>
    </div>}
  </main>
}
