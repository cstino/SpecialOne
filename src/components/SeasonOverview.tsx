import { useMemo } from 'react'
import { useSeasonData } from '../lib/useSeasonData'
import { formatCountdown, useOraCorrente } from '../lib/countdown'
import { LOGO_FASE, SFONDO_FASE, useFaseSquadra, type FaseSquadra } from '../lib/faseSquadra'
import type { League, Membership } from '../types'
import { GameNav, type GameView } from './GameNav'
import { Crest } from './Crest'
import { FixtureScore, Forma, formaPerSquadra, formatMatchDate, SeasonState, TeamLabel, TitoloAdattivo } from './SeasonUI'
import { LeagueNews } from './LeagueNews'
import { DraftLive } from './DraftLive'

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
              <Crest value={miaSquadra?.stemma_url ?? null} stelle={miaSquadra?.titoli_title} imageUrl={data.crestUrlByTeamId.get(membership.id)} size="large" />
              <div className="min-w-0 flex-1">
                <TitoloAdattivo
                  testo={miaSquadra?.nome ?? 'La tua squadra'}
                  className="font-display leading-none tracking-tight text-white drop-shadow-[0_4px_20px_rgba(0,0,0,.5)]"
                />
              </div>
            </div>
            <div className="mt-4 flex flex-wrap items-center gap-x-5 gap-y-2">
              <span className="flex items-baseline gap-1">
                <b className="font-display text-2xl font-extrabold tabular-nums text-white">{ultimaVista ? miaClassifica?.posizione ?? '—' : '?'}</b>
                {ultimaVista && <sup className="text-[.6rem] font-bold text-white/50">ª</sup>}
                <small className="ml-1 text-[.62rem] font-extrabold uppercase tracking-[.1em] text-white/50">posizione</small>
              </span>
              <span className="flex items-baseline gap-1">
                <b className="font-display text-2xl font-extrabold tabular-nums text-white">{ultimaVista ? miaClassifica?.punti ?? 0 : '?'}</b>
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

      {/* Sotto la copertina, lo stile broadcast (2 ottobre 2026): schede in
          vetro nel colore della fase, titoli a linguetta inclinata, risultati
          come un tabellone. La copertina sopra resta com'era. */}
      <div className={`dashboard-broadcast formazione-broadcast formazione-broadcast--${fase} mx-auto flex w-full max-w-[1180px] flex-col gap-7 px-4 py-8 md:px-8 md:py-12`}>
        {/* Primo in colonna mentre e' in corso: un draft in diretta dura una
            ventina di minuti e non deve stare sotto la classifica. Il
            componente si nasconde da solo quando non c'e' niente da vedere. */}
        <DraftLive
          leagueId={league.id}
          teamById={data.teamById}
          crestUrlByTeamId={data.crestUrlByTeamId}
          mioTeamId={membership.id}
          onNavigate={onNavigate}
        />

        {data.lastFixture && ultimaPartita && (
          <section className="dash-sezione">
            <header className="dash-testa">
              <h2 className="dash-linguetta">Ultima partita</h2>
              <span className="dash-sotto">Giornata {data.lastFixture.giornata}</span>
            </header>
            <button type="button" onClick={apriUltimaPartita} className="dash-card dash-partita">
              <div className="overview-fixture-teams dash-partita__squadre">
                <TeamLabel team={data.teamById.get(data.lastFixture.home_team_id)} imageUrl={data.crestUrlByTeamId.get(data.lastFixture.home_team_id)} onClick={() => onOpenTeam(data.lastFixture!.home_team_id)} />
                <FixtureScore fixture={data.lastFixture} match={ultimaPartita} reveal={!ultimaVista} />
                <TeamLabel team={data.teamById.get(data.lastFixture.away_team_id)} imageUrl={data.crestUrlByTeamId.get(data.lastFixture.away_team_id)} reversed onClick={() => onOpenTeam(data.lastFixture!.away_team_id)} />
              </div>
              <span className="dash-partita__azione">{ultimaVista ? 'Rapporto partita' : 'Guarda la partita'} ›</span>
            </button>
          </section>
        )}

        <section className="dash-sezione">
          <header className="dash-testa">
            <h2 className="dash-linguetta">Prossima partita</h2>
            <span className="dash-sotto">G{data.nextFixture?.giornata ?? data.giornateStagione}</span>
          </header>
          <article className="dash-card dash-partita">
            <div className="dash-partita__quando">
              <strong>{data.nextFixture ? formatMatchDate(data.nextFixture.data_sim) : 'Calendario concluso'}</strong>
              {data.nextFixture && <span className="dash-countdown"><i aria-hidden="true" />{formatCountdown(millisecondiAllaPartita)}</span>}
            </div>
            {data.nextFixture ? (
              <div className="overview-fixture-teams dash-partita__squadre">
                <TeamLabel team={data.teamById.get(data.nextFixture.home_team_id)} imageUrl={data.crestUrlByTeamId.get(data.nextFixture.home_team_id)} onClick={() => onOpenTeam(data.nextFixture!.home_team_id)} />
                <FixtureScore fixture={data.nextFixture} match={data.matchByFixture.get(data.nextFixture.id)} />
                <TeamLabel team={data.teamById.get(data.nextFixture.away_team_id)} imageUrl={data.crestUrlByTeamId.get(data.nextFixture.away_team_id)} reversed onClick={() => onOpenTeam(data.nextFixture!.away_team_id)} />
              </div>
            ) : <p className="dash-vuoto">Non ci sono altre partite programmate.</p>}
            <div className="dash-azioni">
              <button className="overview-cta-button dash-cta" type="button" onClick={() => onNavigate('squad')}>Prepara formazione</button>
              <button className="dash-link" type="button" onClick={() => onNavigate('matches')}>Calendario ›</button>
            </div>
          </article>
        </section>

        <LeagueNews leagueId={league.id} fixtures={data.fixtures} matches={data.matches} standings={data.standings} teamById={data.teamById} crestUrlByTeamId={data.crestUrlByTeamId} onOpenMatch={onOpenMatch} onOpenTeam={onOpenTeam} />

        <section className="dash-sezione">
          <header className="dash-testa">
            <h2 className="dash-linguetta">La vetta</h2>
            <button className="dash-link" type="button" onClick={() => onNavigate('table')}>Classifica ›</button>
          </header>
          <ol className="dash-vetta">
            {data.standings.slice(0, 4).map((standing, index) => (
              <li key={standing.team_id} className={standing.team_id === membership.id ? 'is-mia' : undefined} style={{ ['--i' as string]: index + 1 }}>
                <b className="dash-vetta__pos">{standing.posizione ?? index + 1}</b>
                <div className="dash-vetta__squadra"><TeamLabel team={data.teamById.get(standing.team_id)} imageUrl={data.crestUrlByTeamId.get(standing.team_id)} onClick={() => onOpenTeam(standing.team_id)} /></div>
                <strong className="dash-vetta__punti">{standing.punti}<small>pt</small></strong>
              </li>
            ))}
          </ol>
        </section>
      </div>
    </>}
  </main>
}
