import { useMemo } from 'react'
import { useSeasonData } from '../lib/useSeasonData'
import { formatCountdown, useOraCorrente } from '../lib/countdown'
import type { League, Membership } from '../types'
import { GameNav, type GameView } from './GameNav'
import { Crest } from './Crest'
import { FixtureScore, Forma, formaPerSquadra, formatMatchDate, SeasonState, TeamLabel, TitoloAdattivo } from './SeasonUI'
import { LeagueNews } from './LeagueNews'

type Props = { membership: Membership; onNavigate: (view: GameView) => void; revealedMatchIds: Set<number>; onOpenMatch: (matchId: number) => void; onRevealMatch: (matchId: number) => void; onOpenTeam: (teamId: number) => void }

export function SeasonOverview({ membership, onNavigate, revealedMatchIds, onOpenMatch, onRevealMatch, onOpenTeam }: Props) {
  const league = membership.league as League
  const data = useSeasonData(membership)
  const adesso = useOraCorrente()
  const forma = useMemo(() => formaPerSquadra(data.fixtures, data.matchByFixture), [data.fixtures, data.matchByFixture])
  const miaSquadra = data.teamById.get(membership.id)
  const miaClassifica = data.standings.find((riga) => riga.team_id === membership.id)
  const ultimaPartita = data.lastFixture ? data.matchByFixture.get(data.lastFixture.id) : undefined
  const revealAttivo = Boolean(data.lastFixture && data.lastFixture.giornata >= (league.reveal_dalla_giornata ?? 1))
  const ultimaVista = !revealAttivo || Boolean(ultimaPartita && revealedMatchIds.has(ultimaPartita.id))
  const millisecondiAllaPartita = data.nextFixture ? Math.max(0, new Date(data.nextFixture.data_sim).getTime() - adesso) : 0
  const apriUltimaPartita = () => {
    if (!ultimaPartita) return
    if (ultimaVista) onOpenMatch(ultimaPartita.id)
    else onRevealMatch(ultimaPartita.id)
  }

  return <main className="app-shell season-shell">
    <GameNav league={league} active="overview" onNavigate={onNavigate} />
    <header className="topbar season-topbar"><div className="brand-lockup brand-lockup--dark"><img src="/specialone-mark.svg" alt="" /><span>SpecialOne</span></div><span>Stagione {league.stagione_corrente}</span></header>
    <SeasonState loading={data.loading} error={data.error} onRetry={data.reload} />
    {!data.loading && !data.error && <div className="season-page">
      {/* L'eroe porta l'identita' della squadra, non uno slogan: posizione,
          punti e forma sono le tre cose che si cercano per prime. */}
      <section className="season-hero">
        <div className="season-hero__squadra">
          <Crest value={miaSquadra?.stemma_url ?? null} imageUrl={data.crestUrlByTeamId.get(membership.id)} size="large" />
          <div>
            <p className="kicker">{league.nome} · Stagione {league.stagione_corrente}</p>
            <TitoloAdattivo testo={miaSquadra?.nome ?? 'La tua squadra'} />
            <div className="season-hero__stato">
              <span className="season-hero__posizione"><small>Posizione</small><b>{miaClassifica?.posizione ?? '—'}<sup>ª</sup></b></span>
              <span className="season-hero__punti">{miaClassifica?.punti ?? 0} punti</span>
              <Forma esiti={forma.get(membership.id)} />
            </div>
          </div>
        </div>
        <div className="season-round-stamp"><small>GIORNATA</small><strong>{data.currentGiornata}</strong><span>di {league.giornate_totali}</span></div>
      </section>

      <section className="season-dashboard">
        {data.lastFixture && ultimaPartita && <article className={`season-card season-card--last ${ultimaVista ? 'is-revealed' : ''}`} onClick={apriUltimaPartita} onKeyDown={(event) => { if (event.key === 'Enter' || event.key === ' ') { event.preventDefault(); apriUltimaPartita() } }} role="button" tabIndex={0}>
          <div className="season-card__heading"><div><p className="kicker">Ultima partita</p><h2>Giornata {data.lastFixture.giornata}</h2></div><span className="matchday-chip">{ultimaVista ? 'DETTAGLI ›' : 'VEDI RISULTATO ›'}</span></div>
          <div className="last-match-duel">
            <TeamLabel team={data.teamById.get(data.lastFixture.home_team_id)} imageUrl={data.crestUrlByTeamId.get(data.lastFixture.home_team_id)} onClick={() => onOpenTeam(data.lastFixture!.home_team_id)} />
            <FixtureScore fixture={data.lastFixture} match={ultimaPartita} reveal={!ultimaVista} />
            <TeamLabel team={data.teamById.get(data.lastFixture.away_team_id)} imageUrl={data.crestUrlByTeamId.get(data.lastFixture.away_team_id)} reversed onClick={() => onOpenTeam(data.lastFixture!.away_team_id)} />
          </div>
        </article>}
        <article className="season-card season-card--next">
          <div className="season-card__heading"><div><p className="kicker">Prossima partita</p><h2>{data.nextFixture ? formatMatchDate(data.nextFixture.data_sim) : 'Calendario concluso'}</h2>{data.nextFixture && <p className="season-countdown">Si gioca tra <strong>{formatCountdown(millisecondiAllaPartita)}</strong></p>}</div><span className="matchday-chip">G{data.nextFixture?.giornata ?? league.giornate_totali}</span></div>
          {data.nextFixture ? <div className="next-match-duel">
            <TeamLabel team={data.teamById.get(data.nextFixture.home_team_id)} imageUrl={data.crestUrlByTeamId.get(data.nextFixture.home_team_id)} onClick={() => onOpenTeam(data.nextFixture!.home_team_id)} />
            <FixtureScore fixture={data.nextFixture} match={data.matchByFixture.get(data.nextFixture.id)} />
            <TeamLabel team={data.teamById.get(data.nextFixture.away_team_id)} imageUrl={data.crestUrlByTeamId.get(data.nextFixture.away_team_id)} reversed onClick={() => onOpenTeam(data.nextFixture!.away_team_id)} />
          </div> : <p className="season-empty">Non ci sono altre partite programmate.</p>}
          <div className="season-card__actions"><button className="button button--primary" type="button" onClick={() => onNavigate('squad')}>Prepara formazione</button><button className="season-link" type="button" onClick={() => onNavigate('matches')}>Tutto il calendario →</button></div>
        </article>

        <LeagueNews leagueId={league.id} fixtures={data.fixtures} matches={data.matches} standings={data.standings} teamById={data.teamById} crestUrlByTeamId={data.crestUrlByTeamId} onOpenMatch={onOpenMatch} onOpenTeam={onOpenTeam} />

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
