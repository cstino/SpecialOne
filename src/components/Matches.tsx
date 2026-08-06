import { useMemo, useState } from 'react'
import { useSeasonData } from '../lib/useSeasonData'
import type { Fixture, League, Match, Membership, Team } from '../types'
import { GameNav, type GameView } from './GameNav'
import { FixtureScore, formatMatchDate, SeasonState, TeamLabel } from './SeasonUI'

type Props = { membership: Membership; onNavigate: (view: GameView) => void; revealedMatchIds: Set<number>; onOpenMatch: (matchId: number) => void; onRevealMatch: (matchId: number) => void; onOpenTeam: (teamId: number) => void }

type CardProps = {
  giornata: number
  fixtures: Fixture[]
  membership: Membership
  teamById: Map<number, Team>
  crestUrlByTeamId: Map<number, string>
  matchByFixture: Map<number, Match>
  revealedMatchIds: Set<number>
  onOpenMatch: (matchId: number) => void
  onRevealMatch: (matchId: number) => void
  onOpenTeam: (teamId: number) => void
  evidenza?: boolean
}

function GiornataCard({ giornata, fixtures, membership, teamById, crestUrlByTeamId, matchByFixture, revealedMatchIds, onOpenMatch, onRevealMatch, onOpenTeam, evidenza = false }: CardProps) {
  const simulate = fixtures.filter((fixture) => fixture.stato === 'simulata').length
  const completata = fixtures.length > 0 && simulate === fixtures.length

  return <article className={`giornata-card ${evidenza ? 'giornata-card--evidenza' : ''}`}>
    <header className="giornata-card__testa">
      <span className="giornata-card__numero">{giornata}</span>
      <span className="giornata-card__testo">
        <b>Giornata {giornata}</b>
        <small>{fixtures[0] ? formatMatchDate(fixtures[0].data_sim, false) : 'Turno di riposo'}</small>
      </span>
      <span className={`pillola-stato ${completata ? 'pillola-stato--fatta' : 'pillola-stato--attesa'}`}>{completata ? 'COMPLETATA' : 'DA GIOCARE'}</span>
    </header>

    <div className="fixture-list">
      {fixtures.map((fixture) => {
        const match = matchByFixture.get(fixture.id)
        const mia = fixture.home_team_id === membership.id || fixture.away_team_id === membership.id
        const revealAttivo = mia && fixture.giornata >= ((membership.league as League | undefined)?.reveal_dalla_giornata ?? 1)
        // Il reveal e' un momento personale: si anima soltanto la partita
        // della propria squadra. I risultati del resto della lega restano
        // subito consultabili, come un normale tabellino di giornata.
        const giaVista = !revealAttivo || Boolean(match && revealedMatchIds.has(match.id))
        const apriPartita = () => {
          if (!match) return
          if (giaVista) onOpenMatch(match.id)
          else onRevealMatch(match.id)
        }
        return <article
          className={`fixture-row ${mia ? 'is-mine' : ''} ${match ? 'is-clickable' : ''}`}
          key={fixture.id}
          onClick={apriPartita}
          onKeyDown={(event) => { if (match && (event.key === 'Enter' || event.key === ' ')) { event.preventDefault(); apriPartita() } }}
          role={match ? 'button' : undefined}
          tabIndex={match ? 0 : undefined}
        >
          <TeamLabel team={teamById.get(fixture.home_team_id)} imageUrl={crestUrlByTeamId.get(fixture.home_team_id)} reversed onClick={() => onOpenTeam(fixture.home_team_id)} />
          <FixtureScore fixture={fixture} match={match} reveal={!giaVista} />
          <TeamLabel team={teamById.get(fixture.away_team_id)} imageUrl={crestUrlByTeamId.get(fixture.away_team_id)} onClick={() => onOpenTeam(fixture.away_team_id)} />
          {mia && <small>LA TUA PARTITA</small>}
        </article>
      })}
      {!fixtures.length && <p className="season-empty">Turno di riposo.</p>}
    </div>
  </article>
}

export function Matches({ membership, onNavigate, revealedMatchIds, onOpenMatch, onRevealMatch, onOpenTeam }: Props) {
  const league = membership.league as League
  const data = useSeasonData(membership)
  const [calendarioAperto, setCalendarioAperto] = useState(false)

  const giornate = useMemo(() => {
    const mappa = new Map<number, Fixture[]>()
    for (const fixture of data.fixtures) mappa.set(fixture.giornata, [...(mappa.get(fixture.giornata) ?? []), fixture])
    return [...mappa.entries()].sort((sinistra, destra) => sinistra[0] - destra[0])
  }, [data.fixtures])

  const prossima = giornate.find(([, fixtures]) => fixtures.some((fixture) => fixture.stato === 'programmata' || fixture.stato === 'in_corso'))
  // In ordine crescente: la freccia sinistra porta indietro nel tempo.
  const completate = useMemo(() => giornate.filter(([, fixtures]) => fixtures.length > 0 && fixtures.every((fixture) => fixture.stato === 'simulata')), [giornate])

  // Finche' non si tocca nulla si mostra l'ultima giocata, che e' quella che
  // interessa; l'indice esplicito vale solo dopo un passo con le frecce.
  const [indiceScelto, setIndiceScelto] = useState<number | null>(null)
  const indice = Math.min(indiceScelto ?? completate.length - 1, completate.length - 1)
  const completataCorrente = completate[indice]

  const proprieta = {
    membership,
    teamById: data.teamById,
    crestUrlByTeamId: data.crestUrlByTeamId,
    matchByFixture: data.matchByFixture,
    revealedMatchIds,
    onOpenMatch,
    onRevealMatch,
    onOpenTeam,
  }

  return <main className="app-shell season-shell">
    <GameNav league={league} active="matches" onNavigate={onNavigate} />
    <header className="topbar season-topbar"><div className="brand-lockup brand-lockup--dark"><img src="/specialone-mark.svg" alt="" /><span>SpecialOne</span></div><span>Calendario ufficiale</span></header>
    <SeasonState loading={data.loading} error={data.error} onRetry={data.reload} />
    {!data.loading && !data.error && <div className="season-page season-page--narrow">
      <section className="season-title-row"><div><p className="kicker">Stagione {league.stagione_corrente} · {league.nome}</p><h1>Partite.</h1><p>Una giornata ogni sera, alle 23:00 ora di Roma.</p></div><div className="season-total"><strong>{completate.length}</strong><span>di {league.giornate_totali} giornate</span></div></section>

      {calendarioAperto ? <>
        <div className="sezione-testa">
          <div><p className="kicker">Dalla prima all&#39;ultima</p><h2>Calendario completo</h2></div>
          <button className="button-fantasma" type="button" onClick={() => setCalendarioAperto(false)}>← Torna alla sintesi</button>
        </div>
        <div className="giornata-elenco">
          {giornate.map(([numero, fixtures]) => <GiornataCard key={numero} giornata={numero} fixtures={fixtures} evidenza={numero === prossima?.[0]} {...proprieta} />)}
        </div>
      </> : <>
        <div className="sezione-testa">
          <div><p className="kicker">Si gioca stanotte</p><h2>Prossima giornata</h2></div>
          <button className="button-fantasma" type="button" onClick={() => setCalendarioAperto(true)}>Calendario completo →</button>
        </div>
        {prossima
          ? <GiornataCard giornata={prossima[0]} fixtures={prossima[1]} evidenza {...proprieta} />
          : <p className="season-empty">La stagione è conclusa: non restano giornate da giocare.</p>}

        <div className="sezione-testa">
          <div><p className="kicker">Risultati</p><h2>Giornate completate</h2></div>
          {completate.length > 0 && <div className="giornata-passo">
            <button type="button" disabled={indice <= 0} onClick={() => setIndiceScelto(indice - 1)} aria-label="Giornata precedente">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="m14 6-6 6 6 6" /></svg>
            </button>
            <span aria-live="polite">{indice + 1} <i>/</i> {completate.length}</span>
            <button type="button" disabled={indice >= completate.length - 1} onClick={() => setIndiceScelto(indice + 1)} aria-label="Giornata successiva">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="m10 6 6 6-6 6" /></svg>
            </button>
          </div>}
        </div>
        {completataCorrente
          ? <GiornataCard giornata={completataCorrente[0]} fixtures={completataCorrente[1]} {...proprieta} />
          : <p className="season-empty">Nessuna giornata ancora simulata.</p>}
      </>}
    </div>}
  </main>
}
