import { useMemo } from 'react'
import { useSeasonData } from '../lib/useSeasonData'
import type { League, Membership } from '../types'
import { GameNav, type GameView } from './GameNav'
import { Forma, formaPerSquadra, SeasonState, TeamLabel } from './SeasonUI'

type Props = { membership: Membership; onNavigate: (view: GameView) => void; onOpenTeam: (teamId: number) => void }

export function Standings({ membership, onNavigate, onOpenTeam }: Props) {
  const league = membership.league as League
  const data = useSeasonData(membership)
  const forma = useMemo(() => formaPerSquadra(data.fixtures, data.matchByFixture), [data.fixtures, data.matchByFixture])

  return <main className="app-shell season-shell">
    <GameNav league={league} active="table" onNavigate={onNavigate} />
    <header className="topbar season-topbar"><div className="brand-lockup brand-lockup--dark"><img src="/specialone-mark.svg" alt="" /><span>SpecialOne</span></div><span>Aggiornata alla giornata {Math.max(0, data.currentGiornata - 1)}</span></header>
    <SeasonState loading={data.loading} error={data.error} onRetry={data.reload} />
    {!data.loading && !data.error && <div className="season-page season-page--narrow">
      <section className="season-title-row"><div><p className="kicker">Stagione {league.stagione_corrente} · {league.nome}</p><h1>Classifica.</h1><p>Punti, risultati e differenza reti aggiornati dopo ogni simulazione.</p></div><div className="season-total"><strong>{league.n_squadre}</strong><span>squadre</span></div></section>

      <section className="standings-panel">
        <div className="standings-head"><span>POS</span><span>SQUADRA</span><span>PG</span><span>V</span><span>N</span><span>P</span><span>GF</span><span>GS</span><span>DR</span><span>PT</span></div>
        <div className="standings-body">
          {data.standings.map((standing, index) => <div className={`standings-row ${standing.team_id === membership.id ? 'is-mine' : ''}`} key={standing.team_id}>
            <span className="standings-position">{standing.posizione ?? index + 1}</span>
            <div className="standings-squadra">
              <TeamLabel team={data.teamById.get(standing.team_id)} imageUrl={data.crestUrlByTeamId.get(standing.team_id)} onClick={() => onOpenTeam(standing.team_id)} />
              <Forma esiti={forma.get(standing.team_id)} />
            </div>
            <span>{standing.giocate}</span><span>{standing.vittorie}</span><span>{standing.pareggi}</span><span>{standing.sconfitte}</span><span>{standing.gol_fatti}</span><span>{standing.gol_subiti}</span><span>{standing.differenza_reti > 0 ? `+${standing.differenza_reti}` : standing.differenza_reti}</span><strong>{standing.punti}</strong>
          </div>)}
        </div>
        <footer><span><i /> La tua squadra</span><small>Ordine: punti · scontri diretti · differenza reti · gol fatti</small></footer>
      </section>
    </div>}
  </main>
}
