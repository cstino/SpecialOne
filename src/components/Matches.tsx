import { useEffect, useMemo, useState } from 'react'
import { useSeasonData } from '../lib/useSeasonData'
import { supabase } from '../lib/supabase'
import { LOGO_FASE } from '../lib/faseSquadra'
import { nomeTurnoTabellone, titoloTabellone } from '../lib/playoff'
import type { Bracket, BracketTie, Fixture, League, Match, Membership, Team } from '../types'
import { GameNav, type GameView } from './GameNav'
import { FixtureScore, formatMatchDate, SeasonState, TeamLabel } from './SeasonUI'
import { SOGLIA_DERBY, useRivalitaMie } from '../lib/useRivalita'
import { ConferenceBadge } from './ConferenceBadge'
import { FiltroConferenza, type FiltroConf } from './FiltroConferenza'
import { NOME_CONFERENZA, type Conferenza } from '../lib/conferenze'

type Props = { membership: Membership; onNavigate: (view: GameView) => void; revealedMatchIds: Set<number>; onOpenMatch: (matchId: number) => void; onRevealMatch: (matchId: number) => void; onOpenTeam: (teamId: number) => void }

type CardProps = {
  // Rivalita' della propria squadra (solo leghe con le novita'): le sue partite con grado >= 50 sono derby.
  rivalita?: Map<number, number>
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
  // Con le conferenze: conferenza di una squadra (null = sconosciuta) e filtro scelto.
  confDiSquadra?: Map<number, Conferenza>
  filtro?: FiltroConf
  // Playoff: sfida e tabellone di ogni partita con bracket_tie_id.
  tieById?: Map<number, BracketTie>
  bracketById?: Map<number, Bracket>
  tiesPerBracket?: Map<number, BracketTie[]>
}

type Gruppo = { chiave: string; conf: Conferenza | null; fixtures: Fixture[]; playoff?: { tipo: Bracket['tipo']; titolo: string; sottotitolo: string } }

function GiornataCard({ giornata, fixtures, membership, teamById, crestUrlByTeamId, matchByFixture, revealedMatchIds, onOpenMatch, onRevealMatch, onOpenTeam, evidenza = false, confDiSquadra, filtro = 'tutte', rivalita, tieById, bracketById, tiesPerBracket }: CardProps) {
  const simulate = fixtures.filter((fixture) => fixture.stato === 'simulata').length
  const completata = fixtures.length > 0 && simulate === fixtures.length

  // Con le conferenze le partite si dividono per conferenza (stesso girone = stessa conferenza);
  // le sfide fra conferenze diverse (tabelloni) restano in un gruppo a parte, senza intestazione.
  // Nei playoff le partite si dividono per tabellone (prima il Title, poi il Draft), con turno e andata/ritorno;
  // il filtro di conferenza tiene le sfide in cui gioca almeno una squadra di quella conferenza.
  const gruppi = useMemo((): Gruppo[] => {
    if (fixtures.some((f) => f.bracket_tie_id != null)) {
      const perTabellone = new Map<number, Fixture[]>()
      for (const f of fixtures) {
        if (filtro !== 'tutte' && confDiSquadra?.get(f.home_team_id) !== filtro && confDiSquadra?.get(f.away_team_id) !== filtro) continue
        const tie = f.bracket_tie_id != null ? tieById?.get(f.bracket_tie_id) : undefined
        const chiave = tie?.bracket_id ?? 0
        perTabellone.set(chiave, [...(perTabellone.get(chiave) ?? []), f])
      }
      return [...perTabellone.entries()]
        .map(([bracketId, lista]): Gruppo => {
          const b = bracketById?.get(bracketId)
          const tie = lista[0].bracket_tie_id != null ? tieById?.get(lista[0].bracket_tie_id) : undefined
          if (!b || !tie) return { chiave: `playoff-${bracketId}`, conf: null, fixtures: lista }
          const gara = tie.gara_secca ? 'Gara unica' : lista[0].mano === 2 ? 'Ritorno' : 'Andata'
          return { chiave: `playoff-${bracketId}`, conf: null, fixtures: lista, playoff: { tipo: b.tipo, titolo: titoloTabellone(b), sottotitolo: `${nomeTurnoTabellone(b, tie.turno, tiesPerBracket?.get(b.id) ?? [])} · ${gara}` } }
        })
        .sort((a, b) => (a.playoff?.tipo === 'title' ? 0 : 1) - (b.playoff?.tipo === 'title' ? 0 : 1))
    }
    if (!confDiSquadra || confDiSquadra.size === 0) return fixtures.length ? [{ chiave: 'tutte', conf: null as Conferenza | null, fixtures }] : []
    const per: Record<string, Fixture[]> = { est: [], ovest: [], altre: [] }
    for (const f of fixtures) {
      const h = confDiSquadra.get(f.home_team_id), a = confDiSquadra.get(f.away_team_id)
      if (h && h === a) per[h].push(f)
      else per.altre.push(f)
    }
    const ordine: [string, Conferenza | null][] = [['est', 'est'], ['ovest', 'ovest'], ['altre', null]]
    return ordine
      .filter(([k]) => per[k].length > 0 && (filtro === 'tutte' || k === filtro || (k === 'altre' && per.altre.some((f) => confDiSquadra.get(f.home_team_id) === filtro || confDiSquadra.get(f.away_team_id) === filtro))))
      .map(([k, c]) => ({ chiave: k, conf: c, fixtures: k === 'altre' && filtro !== 'tutte' ? per.altre.filter((f) => confDiSquadra.get(f.home_team_id) === filtro || confDiSquadra.get(f.away_team_id) === filtro) : per[k] }))
  }, [fixtures, confDiSquadra, filtro, tieById, bracketById, tiesPerBracket])

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
      {gruppi.map((gruppo) => <div className="fixture-gruppo" key={gruppo.chiave}>
        {gruppo.playoff && <div className={`fixture-gruppo__testa fixture-gruppo__testa--${gruppo.playoff.tipo}`}><img className="fixture-gruppo__logo" src={LOGO_FASE[gruppo.playoff.tipo]} alt={gruppo.playoff.titolo} /><b>{gruppo.playoff.sottotitolo}</b></div>}
        {gruppo.conf && <div className={`fixture-gruppo__testa fixture-gruppo__testa--${gruppo.conf}`}><ConferenceBadge conferenza={gruppo.conf} /><b>{NOME_CONFERENZA[gruppo.conf]}</b></div>}
        {gruppo.fixtures.map((fixture) => {
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
          {mia && <small>LA TUA PARTITA{(rivalita?.get(fixture.home_team_id === membership.id ? fixture.away_team_id : fixture.home_team_id) ?? 0) > SOGLIA_DERBY && <b className="fixture-derby">DERBY</b>}</small>}
        </article>
        })}
      </div>)}
      {!fixtures.length && <p className="season-empty">Turno di riposo.</p>}
      {fixtures.length > 0 && !gruppi.length && <p className="season-empty">Nessuna partita di questa conferenza in questa giornata.</p>}
    </div>
  </article>
}

export function Matches({ membership, onNavigate, revealedMatchIds, onOpenMatch, onRevealMatch, onOpenTeam }: Props) {
  const league = membership.league as League
  const data = useSeasonData(membership)
  const [calendarioAperto, setCalendarioAperto] = useState(false)
  // Conferenza di ogni squadra (dalla classifica): attiva solo se la lega ha le conferenze.
  const confDiSquadra = useMemo(() => {
    const m = new Map<number, Conferenza>()
    for (const r of data.standings) if (r.conferenza) m.set(r.team_id, r.conferenza as Conferenza)
    return m
  }, [data.standings])
  const [filtro, setFiltro] = useState<FiltroConf>('tutte')

  // Tabelloni e sfide dei playoff, caricati solo se la stagione ha partite di playoff.
  const conPlayoff = data.fixtures.some((f) => f.bracket_tie_id != null)
  const [brackets, setBrackets] = useState<Bracket[]>([])
  const [ties, setTies] = useState<BracketTie[]>([])
  useEffect(() => {
    if (!conPlayoff) return
    let vivo = true
    void Promise.all([
      supabase.from('brackets').select('*').eq('league_id', league.id),
      supabase.from('bracket_ties').select('*').eq('league_id', league.id),
    ]).then(([bRes, tRes]) => {
      if (!vivo) return
      setBrackets((bRes.data ?? []) as Bracket[])
      setTies((tRes.data ?? []) as BracketTie[])
    })
    return () => { vivo = false }
  }, [conPlayoff, league.id, data.season?.id])
  const tieById = useMemo(() => new Map(ties.map((t) => [t.id, t])), [ties])
  const bracketById = useMemo(() => new Map(brackets.map((b) => [b.id, b])), [brackets])
  const tiesPerBracket = useMemo(() => {
    const m = new Map<number, BracketTie[]>()
    for (const t of ties) m.set(t.bracket_id, [...(m.get(t.bracket_id) ?? []), t])
    return m
  }, [ties])

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

  const rivalita = useRivalitaMie(league.id, membership.id, Boolean(league.conferenze_stampa))
  const proprieta = {
    rivalita,
    membership,
    teamById: data.teamById,
    crestUrlByTeamId: data.crestUrlByTeamId,
    matchByFixture: data.matchByFixture,
    revealedMatchIds,
    onOpenMatch,
    onRevealMatch,
    onOpenTeam,
    confDiSquadra,
    filtro,
    tieById,
    bracketById,
    tiesPerBracket,
  }

  return <main className="app-shell season-shell">
    <GameNav league={league} active="matches" onNavigate={onNavigate} />
    <header className="topbar season-topbar"><div className="brand-lockup brand-lockup--dark"><img src="/specialone-mark.svg" alt="" /><span>SpecialOne</span></div><span>Calendario ufficiale</span></header>
    <SeasonState loading={data.loading} error={data.error} onRetry={data.reload} />
    {!data.loading && !data.error && <div className="season-page season-page--narrow">
      <section className="season-title-row"><div><p className="kicker">Stagione {league.stagione_corrente} · {league.nome}</p><h1>Partite.</h1><p>Una giornata ogni sera, alle 23:00 ora di Roma.</p></div><div className="season-total"><strong>{completate.length}</strong><span>di {data.giornateStagione} giornate</span></div></section>

      {confDiSquadra.size > 0 && <FiltroConferenza value={filtro} onChange={setFiltro} />}

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
