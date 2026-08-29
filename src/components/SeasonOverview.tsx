import { useMemo } from 'react'
import { useSeasonData } from '../lib/useSeasonData'
import { formatCountdown, useOraCorrente } from '../lib/countdown'
import { LOGO_FASE, SFONDO_FASE, useFaseSquadra, type FaseSquadra } from '../lib/faseSquadra'
import type { League, Membership } from '../types'
import { GameNav, type GameView } from './GameNav'
import { Crest } from './Crest'
import { FixtureScore, Forma, formaPerSquadra, formatMatchDate, SeasonState, TeamLabel, TitoloAdattivo } from './SeasonUI'
import { LeagueNews } from './LeagueNews'

type Props = { membership: Membership; onNavigate: (view: GameView) => void; revealedMatchIds: Set<number>; onOpenMatch: (matchId: number) => void; onRevealMatch: (matchId: number) => void; onOpenTeam: (teamId: number) => void }

const ACCENT_FASE: Record<FaseSquadra, string> = { regular: '#2fd07e', title: '#4d7bff', draft: '#f2954a' }
const LABEL_FASE: Record<FaseSquadra, string> = { regular: 'Stagione regolare', title: 'Title Playoff', draft: 'Draft Playoff' }

export function SeasonOverview({ membership, onNavigate, revealedMatchIds, onOpenMatch, onRevealMatch, onOpenTeam }: Props) {
  const league = membership.league as League
  const data = useSeasonData(membership)
  const adesso = useOraCorrente()
  const forma = useMemo(() => formaPerSquadra(data.fixtures, data.matchByFixture), [data.fixtures, data.matchByFixture])
  const fase = useFaseSquadra(league.id, membership.id, data.season?.id)
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
    {!data.loading && !data.error && <>
      {/* Eroe a piena larghezza, come una copertina editoriale: l'immagine
          tocca i bordi, il testo poggia in basso su un velo scuro, una
          sola striscia di colore (per fase) fa da unica decorazione. */}
      <section
        className="overview-hero relative isolate flex w-full items-end overflow-hidden bg-cover bg-center"
        style={{ backgroundImage: `url(${SFONDO_FASE[fase]})` }}
      >
        <div className="pointer-events-none absolute inset-0 -z-10 bg-gradient-to-b from-black/10 via-black/45 to-black/95" />
        <div className="pointer-events-none absolute inset-x-0 bottom-0 h-[3px]" style={{ background: ACCENT_FASE[fase], boxShadow: `0 0 20px 1px ${ACCENT_FASE[fase]}99` }} />

        <div className="mx-auto flex w-full max-w-[1180px] flex-col gap-6 px-5 pb-7 pt-8 md:flex-row md:items-end md:justify-between md:px-8 md:pb-9">
          <div className="min-w-0">
            <img src={LOGO_FASE[fase]} alt={LABEL_FASE[fase]} className="mt-4 h-9 w-auto md:h-11" />
            <div className="mt-2 flex min-w-0 items-center gap-5">
              <Crest value={miaSquadra?.stemma_url ?? null} imageUrl={data.crestUrlByTeamId.get(membership.id)} size="large" />
              <div className="min-w-0 flex-1">
                <TitoloAdattivo
                  testo={miaSquadra?.nome ?? 'La tua squadra'}
                  className="font-display leading-none tracking-tight text-white drop-shadow-[0_4px_20px_rgba(0,0,0,.5)]"
                />
              </div>
            </div>
            <div className="mt-4 flex flex-wrap items-center gap-x-5 gap-y-2">
              <span className="flex items-baseline gap-1">
                <b className="font-display text-2xl font-extrabold tabular-nums text-white">{miaClassifica?.posizione ?? '—'}</b>
                <sup className="text-[.6rem] font-bold text-white/50">ª</sup>
                <small className="ml-1 text-[.62rem] font-extrabold uppercase tracking-[.1em] text-white/50">posizione</small>
              </span>
              <span className="flex items-baseline gap-1">
                <b className="font-display text-2xl font-extrabold tabular-nums text-white">{miaClassifica?.punti ?? 0}</b>
                <small className="ml-1 text-[.62rem] font-extrabold uppercase tracking-[.1em] text-white/50">punti</small>
              </span>
              <Forma esiti={forma.get(membership.id)} nascondiUltimo={!ultimaVista} />
            </div>
          </div>

          {fase === 'regular'
            ? <div className="flex shrink-0 items-center gap-3 self-start rounded-full border border-white/15 bg-black/30 py-2 pl-4 pr-2 backdrop-blur-sm md:self-auto">
                <span className="text-[.6rem] font-extrabold uppercase tracking-[.14em] text-white/55">Giornata</span>
                <span className="font-display text-xl font-extrabold text-white">{data.currentGiornata}</span>
                <span className="text-[.7rem] font-semibold text-white/45">di {data.giornateStagione}</span>
              </div>
            : <div className="flex shrink-0 items-center self-start rounded-full border border-white/15 bg-black/30 px-4 py-2 backdrop-blur-sm md:self-auto">
                {/* Fuori dalla stagione regolare la numerazione delle giornate
                    non e' piu' un dato utile da mostrare qui: le partite di
                    tabellone continuano a incrementarla oltre giornate_totali
                    (docs/decisioni-draft-picks.md), producendo cose come
                    "17 di 14". Meglio lo stato del tabellone di questa squadra. */}
                <span className="text-[.68rem] font-extrabold uppercase tracking-[.1em] text-white">{LABEL_FASE[fase]} in corso</span>
              </div>}
        </div>
      </section>

      <div className="mx-auto flex w-full max-w-[1180px] flex-col gap-10 px-5 py-10 md:px-8 md:py-14">
        {data.lastFixture && ultimaPartita && (
          <button
            type="button"
            onClick={apriUltimaPartita}
            className="group flex flex-col gap-5 border-b border-white/10 pb-10 text-left"
          >
            <div className="flex items-start justify-between gap-3">
              <div>
                <p className="text-[.62rem] font-extrabold uppercase tracking-[.14em] text-purple-300/80">Ultima partita</p>
                <h2 className="font-display mt-1 text-2xl font-extrabold text-white">Giornata {data.lastFixture.giornata}</h2>
              </div>
              <span className="whitespace-nowrap text-[.66rem] font-extrabold uppercase tracking-wide text-purple-200 transition group-hover:text-white">
                {ultimaVista ? 'Dettagli ›' : 'Vedi risultato ›'}
              </span>
            </div>
            <div className="overview-fixture-teams flex items-center justify-between gap-3">
              <TeamLabel team={data.teamById.get(data.lastFixture.home_team_id)} imageUrl={data.crestUrlByTeamId.get(data.lastFixture.home_team_id)} onClick={() => onOpenTeam(data.lastFixture!.home_team_id)} />
              <FixtureScore fixture={data.lastFixture} match={ultimaPartita} reveal={!ultimaVista} />
              <TeamLabel team={data.teamById.get(data.lastFixture.away_team_id)} imageUrl={data.crestUrlByTeamId.get(data.lastFixture.away_team_id)} reversed onClick={() => onOpenTeam(data.lastFixture!.away_team_id)} />
            </div>
          </button>
        )}

        <article className="flex flex-col gap-5 border-b border-white/10 pb-10">
          <div className="flex items-start justify-between gap-3">
            <div>
              <p className="text-[.62rem] font-extrabold uppercase tracking-[.14em] text-purple-300/80">Prossima partita</p>
              <h2 className="font-display mt-1 text-2xl font-extrabold text-white">{data.nextFixture ? formatMatchDate(data.nextFixture.data_sim) : 'Calendario concluso'}</h2>
              {data.nextFixture && <p className="mt-1 text-[.78rem] text-white/55">Si gioca tra <strong className="text-white">{formatCountdown(millisecondiAllaPartita)}</strong></p>}
            </div>
            <span className="whitespace-nowrap text-[.66rem] font-extrabold uppercase tracking-wide text-purple-200">
              G{data.nextFixture?.giornata ?? data.giornateStagione}
            </span>
          </div>
          {data.nextFixture ? (
            <div className="overview-fixture-teams flex items-center justify-between gap-3">
              <TeamLabel team={data.teamById.get(data.nextFixture.home_team_id)} imageUrl={data.crestUrlByTeamId.get(data.nextFixture.home_team_id)} onClick={() => onOpenTeam(data.nextFixture!.home_team_id)} />
              <FixtureScore fixture={data.nextFixture} match={data.matchByFixture.get(data.nextFixture.id)} />
              <TeamLabel team={data.teamById.get(data.nextFixture.away_team_id)} imageUrl={data.crestUrlByTeamId.get(data.nextFixture.away_team_id)} reversed onClick={() => onOpenTeam(data.nextFixture!.away_team_id)} />
            </div>
          ) : <p className="text-sm text-white/40">Non ci sono altre partite programmate.</p>}
          <div className="mt-1 flex items-center justify-center gap-4">
            <button className="overview-cta-button button button--primary" type="button" onClick={() => onNavigate('squad')}>Prepara formazione</button>
            <button className="text-[.76rem] font-bold text-white/60 transition hover:text-white" type="button" onClick={() => onNavigate('matches')}>Tutto il calendario →</button>
          </div>
        </article>

        <LeagueNews leagueId={league.id} fixtures={data.fixtures} matches={data.matches} standings={data.standings} teamById={data.teamById} crestUrlByTeamId={data.crestUrlByTeamId} onOpenMatch={onOpenMatch} onOpenTeam={onOpenTeam} />

        <article className="flex flex-col gap-4">
          <div className="flex items-center justify-between gap-3">
            <div>
              <p className="text-[.62rem] font-extrabold uppercase tracking-[.14em] text-purple-300/80">Classifica</p>
              <h2 className="font-display mt-1 text-2xl font-extrabold text-white">La vetta</h2>
            </div>
            <button className="text-[.76rem] font-bold text-white/60 transition hover:text-white" type="button" onClick={() => onNavigate('table')}>Vedi tutta →</button>
          </div>
          <div className="flex flex-col divide-y divide-white/10">
            {data.standings.slice(0, 4).map((standing, index) => (
              <div key={standing.team_id} className={`flex items-center gap-3 py-3 ${standing.team_id === membership.id ? 'text-purple-200' : ''}`}>
                <b className="font-display w-6 shrink-0 text-lg font-extrabold text-white/70">{standing.posizione ?? index + 1}</b>
                <div className="min-w-0 flex-1"><TeamLabel team={data.teamById.get(standing.team_id)} imageUrl={data.crestUrlByTeamId.get(standing.team_id)} onClick={() => onOpenTeam(standing.team_id)} /></div>
                <strong className="font-display text-lg font-extrabold text-white">{standing.punti}</strong>
                <small className="text-[.6rem] font-extrabold uppercase text-white/40">pt</small>
              </div>
            ))}
          </div>
        </article>
      </div>
    </>}
  </main>
}
