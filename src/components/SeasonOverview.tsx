import { useState } from 'react'
import { useSeasonData } from '../lib/useSeasonData'
import { supabase } from '../lib/supabase'
import type { League, Membership } from '../types'
import { GameNav, type GameView } from './GameNav'
import { FixtureScore, formatMatchDate, SeasonState, TeamLabel } from './SeasonUI'

type Props = { membership: Membership; onNavigate: (view: GameView) => void; onOpenMatch: (matchId: number) => void; onOpenTeam: (teamId: number) => void }

export function SeasonOverview({ membership, onNavigate, onOpenMatch, onOpenTeam }: Props) {
  const league = membership.league as League
  const data = useSeasonData(membership)
  const [simulating, setSimulating] = useState(false)
  const [simulationError, setSimulationError] = useState<string | null>(null)

  async function simulateNextRound() {
    if (!window.confirm(`Simulare ora la giornata ${data.currentGiornata}? I risultati diventeranno definitivi.`)) return
    setSimulating(true)
    setSimulationError(null)
    const { error } = await supabase.functions.invoke('simula-giornata', { body: { league_id: league.id } })
    if (error) {
      let message = error.message
      if ('context' in error && error.context instanceof Response) {
        const payload = await error.context.clone().json().catch(() => null) as { error?: string; message?: string } | null
        message = payload?.error ?? payload?.message ?? message
      }
      setSimulationError(message)
    } else await data.reload()
    setSimulating(false)
  }

  return <main className="app-shell season-shell">
    <GameNav league={league} active="overview" onNavigate={onNavigate} />
    <header className="topbar season-topbar"><div className="brand-lockup brand-lockup--dark"><img src="/specialone-mark.svg" alt="" /><span>SpecialOne</span></div><span>Stagione {league.stagione_corrente}</span></header>
    <SeasonState loading={data.loading} error={data.error} onRetry={data.reload} />
    {!data.loading && !data.error && <div className="season-page">
      {simulationError && <p className="notice notice--error season-notice" role="alert">{simulationError}</p>}
      <section className="season-hero">
        <div><p className="kicker">Stagione {league.stagione_corrente} · {league.nome}</p><h1>La corsa è iniziata.</h1><p>Calendario pronto. Prepara la formazione prima della prossima simulazione notturna.</p></div>
        <div className="season-round-stamp"><small>GIORNATA</small><strong>{data.currentGiornata}</strong><span>di {league.giornate_totali}</span></div>
      </section>

      <section className="season-dashboard">
        {data.lastFixture && data.matchByFixture.get(data.lastFixture.id) && <article className="season-card season-card--last" onClick={() => onOpenMatch(data.matchByFixture.get(data.lastFixture!.id)!.id)} onKeyDown={(event) => { if (event.key === 'Enter' || event.key === ' ') { event.preventDefault(); onOpenMatch(data.matchByFixture.get(data.lastFixture!.id)!.id) } }} role="button" tabIndex={0}>
          <div className="season-card__heading"><div><p className="kicker">Ultima partita</p><h2>Giornata {data.lastFixture.giornata}</h2></div><span className="matchday-chip">DETTAGLI ›</span></div>
          <div className="last-match-duel">
            <TeamLabel team={data.teamById.get(data.lastFixture.home_team_id)} imageUrl={data.crestUrlByTeamId.get(data.lastFixture.home_team_id)} onClick={() => onOpenTeam(data.lastFixture!.home_team_id)} />
            <FixtureScore fixture={data.lastFixture} match={data.matchByFixture.get(data.lastFixture.id)} />
            <TeamLabel team={data.teamById.get(data.lastFixture.away_team_id)} imageUrl={data.crestUrlByTeamId.get(data.lastFixture.away_team_id)} reversed onClick={() => onOpenTeam(data.lastFixture!.away_team_id)} />
          </div>
        </article>}
        <article className="season-card season-card--next">
          <div className="season-card__heading"><div><p className="kicker">Prossima partita</p><h2>{data.nextFixture ? formatMatchDate(data.nextFixture.data_sim) : 'Calendario concluso'}</h2></div><span className="matchday-chip">G{data.nextFixture?.giornata ?? league.giornate_totali}</span></div>
          {data.nextFixture ? <div className="next-match-duel">
            <TeamLabel team={data.teamById.get(data.nextFixture.home_team_id)} imageUrl={data.crestUrlByTeamId.get(data.nextFixture.home_team_id)} onClick={() => onOpenTeam(data.nextFixture!.home_team_id)} />
            <FixtureScore fixture={data.nextFixture} match={data.matchByFixture.get(data.nextFixture.id)} />
            <TeamLabel team={data.teamById.get(data.nextFixture.away_team_id)} imageUrl={data.crestUrlByTeamId.get(data.nextFixture.away_team_id)} reversed onClick={() => onOpenTeam(data.nextFixture!.away_team_id)} />
          </div> : <p className="season-empty">Non ci sono altre partite programmate.</p>}
          <div className="season-card__actions"><button className="button button--primary" type="button" onClick={() => onNavigate('squad')}>Prepara formazione</button><button className="season-link" type="button" onClick={() => onNavigate('matches')}>Tutto il calendario →</button></div>
        </article>

        <article className="season-card season-card--progress">
          <p className="kicker">Campionato</p><div className="season-progress-number"><strong>{data.fixtures.filter((fixture) => fixture.stato === 'simulata').length}</strong><span>/ {data.fixtures.length}<small>partite giocate</small></span></div>
          <div className="season-progress"><i style={{ width: `${data.fixtures.length ? data.fixtures.filter((fixture) => fixture.stato === 'simulata').length / data.fixtures.length * 100 : 0}%` }} /></div>
          <button className="season-link" type="button" onClick={() => onNavigate('matches')}>Apri Partite</button>
          {league.admin_id === membership.user_id && data.nextFixture && <button className="simulate-round-button" type="button" disabled={simulating} onClick={simulateNextRound}>{simulating ? 'Simulazione…' : `Simula giornata ${data.currentGiornata}`}</button>}
        </article>

        <article className="season-card season-card--table">
          <div className="season-card__heading"><div><p className="kicker">Classifica</p><h2>La vetta</h2></div><button className="season-link" type="button" onClick={() => onNavigate('table')}>Vedi tutta →</button></div>
          <div className="mini-table">
            {data.standings.slice(0, 4).map((standing, index) => <div className={standing.team_id === membership.id ? 'is-mine' : ''} key={standing.team_id}><b>{standing.posizione ?? index + 1}</b><TeamLabel team={data.teamById.get(standing.team_id)} imageUrl={data.crestUrlByTeamId.get(standing.team_id)} onClick={() => onOpenTeam(standing.team_id)} /><strong>{standing.punti}</strong><small>PT</small></div>)}
          </div>
        </article>
      </section>
    </div>}
  </main>
}
