import { useEffect, useMemo, useState } from 'react'
import { supabase } from '../lib/supabase'
import { useSeasonData } from '../lib/useSeasonData'
import type { League, MatchPlayerStat, MatchTeamStats, Membership } from '../types'
import { GameNav, type GameView } from './GameNav'
import { SeasonState, TeamLabel } from './SeasonUI'

type Props = {
  membership: Membership
  matchId: number
  onBack: () => void
  onNavigate: (view: GameView) => void
  onOpenTeam: (teamId: number) => void
}

type PlayerIdentity = { id: number; nome: string; posizioni: string[] }

const STAT_ROWS: Array<[string, keyof MatchTeamStats, (value: number) => string]> = [
  ['Possesso', 'possesso', (value) => `${Math.round(value * 100)}%`],
  ['Tiri', 'tiri', String],
  ['Tiri in porta', 'inPorta', String],
  ['Precisione passaggi', 'passaggiPct', (value) => `${Math.round(value * 100)}%`],
  ['Passaggi riusciti', 'passaggiR', String],
  ['Contrasti', 'contrasti', String],
  ['Dribbling', 'dribbling', String],
]

export function MatchDetail({ membership, matchId, onBack, onNavigate, onOpenTeam }: Props) {
  const league = membership.league as League
  const data = useSeasonData(membership)
  const [stats, setStats] = useState<MatchPlayerStat[]>([])
  const [players, setPlayers] = useState<Map<number, PlayerIdentity>>(new Map())
  const [statsLoading, setStatsLoading] = useState(true)
  const [statsError, setStatsError] = useState<string | null>(null)
  const match = data.matches.find((item) => item.id === matchId)
  const fixture = match ? data.fixtures.find((item) => item.id === match.fixture_id) : undefined

  useEffect(() => {
    let active = true
    async function loadStats() {
      setStatsLoading(true)
      setStatsError(null)
      const { data: statRows, error } = await supabase.from('match_stats').select('*').eq('match_id', matchId)
      if (error) { if (active) { setStatsError(error.message); setStatsLoading(false) }; return }
      const loadedStats = (statRows ?? []) as MatchPlayerStat[]
      const instanceIds = loadedStats.map((item) => item.player_instance_id)
      const { data: instances, error: instanceError } = instanceIds.length
        ? await supabase.from('player_instances').select('id, player_id').in('id', instanceIds)
        : { data: [], error: null }
      if (instanceError) { if (active) { setStatsError(instanceError.message); setStatsLoading(false) }; return }
      const playerIds = [...new Set((instances ?? []).map((item) => item.player_id))]
      const { data: catalog, error: catalogError } = playerIds.length
        ? await supabase.from('players').select('id, nome, posizioni').in('id', playerIds)
        : { data: [], error: null }
      if (catalogError) { if (active) { setStatsError(catalogError.message); setStatsLoading(false) }; return }
      const catalogById = new Map((catalog ?? []).map((player) => [player.id, player as PlayerIdentity]))
      const instancePlayers = new Map<number, PlayerIdentity>()
      for (const instance of instances ?? []) {
        const player = catalogById.get(instance.player_id)
        if (player) instancePlayers.set(instance.id, player)
      }
      if (active) { setStats(loadedStats); setPlayers(instancePlayers); setStatsLoading(false) }
    }
    void loadStats()
    return () => { active = false }
  }, [matchId])

  const byTeam = useMemo(() => {
    const grouped = new Map<number, MatchPlayerStat[]>()
    for (const row of stats) grouped.set(row.team_id, [...(grouped.get(row.team_id) ?? []), row])
    for (const rows of grouped.values()) rows.sort((left, right) => right.gol - left.gol || right.tiri_porta - left.tiri_porta || right.minuti - left.minuti)
    return grouped
  }, [stats])

  function navigate(view: GameView) { onNavigate(view) }

  return <main className="app-shell season-shell">
    <GameNav league={league} active="matches" onNavigate={navigate} />
    <header className="topbar season-topbar"><button className="match-detail-back" type="button" onClick={onBack}>← Torna alle partite</button><span>Rapporto partita</span></header>
    <SeasonState loading={data.loading} error={data.error} onRetry={data.reload} />
    {!data.loading && !data.error && (!match || !fixture) && <section className="season-state"><span className="season-state__icon">!</span><h2>Partita non trovata</h2><button className="button button--primary" type="button" onClick={onBack}>Torna indietro</button></section>}
    {!data.loading && !data.error && match && fixture && <div className="season-page season-page--narrow match-detail-page">
      <section className="match-report-hero">
        <p className="kicker">Giornata {fixture.giornata} · Stagione {league.stagione_corrente}</p>
        <div className="match-report-score">
          <div><TeamLabel team={data.teamById.get(fixture.home_team_id)} imageUrl={data.crestUrlByTeamId.get(fixture.home_team_id)} onClick={() => onOpenTeam(fixture.home_team_id)} /><small>{match.modulo_home}</small></div>
          <strong><span>{match.gol_home}</span><i>:</i><span>{match.gol_away}</span></strong>
          <div><TeamLabel team={data.teamById.get(fixture.away_team_id)} imageUrl={data.crestUrlByTeamId.get(fixture.away_team_id)} reversed onClick={() => onOpenTeam(fixture.away_team_id)} /><small>{match.modulo_away}</small></div>
        </div>
        <span className="match-report-final">RISULTATO FINALE</span>
      </section>

      <section className="match-report-panel">
        <div className="match-report-heading"><p className="kicker">Numeri della gara</p><h2>Statistiche squadre</h2></div>
        <div className="match-team-stats">
          {STAT_ROWS.map(([label, key, format]) => {
            const home = Number(match.stats_squadra.home[key] ?? 0)
            const away = Number(match.stats_squadra.away[key] ?? 0)
            const total = home + away || 1
            return <div className="match-stat-row" key={key}>
              <b>{format(home)}</b><span>{label}</span><b>{format(away)}</b>
              <i><span style={{ width: `${home / total * 100}%` }} /><span style={{ width: `${away / total * 100}%` }} /></i>
            </div>
          })}
        </div>
      </section>

      <section className="match-report-panel">
        <div className="match-report-heading"><p className="kicker">Prestazioni</p><h2>Statistiche giocatori</h2></div>
        {statsError && <p className="notice notice--error">{statsError}</p>}
        {statsLoading ? <p className="season-empty">Carico le prestazioni…</p> : <div className="match-player-columns">
          {[fixture.home_team_id, fixture.away_team_id].map((teamId) => <div className="match-player-team" key={teamId}>
            <h3>{data.teamById.get(teamId)?.nome ?? 'Squadra'}</h3>
            <div className="match-player-table"><div className="match-player-table__head"><span>Giocatore</span><span>MIN</span><span>G</span><span>T</span><span>PASS</span></div>
              {(byTeam.get(teamId) ?? []).map((row) => <div key={row.id}><span><strong>{players.get(row.player_instance_id)?.nome ?? `Giocatore ${row.player_instance_id}`}</strong><small>{players.get(row.player_instance_id)?.posizioni.join(' · ')}</small></span><b>{row.minuti}</b><b className={row.gol ? 'is-highlight' : ''}>{row.gol}</b><b>{row.tiri}</b><b>{row.passaggi_riusciti}/{row.passaggi_tentati}</b></div>)}
            </div>
          </div>)}
        </div>}
      </section>
    </div>}
  </main>
}
