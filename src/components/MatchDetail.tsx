import { useEffect, useMemo, useState } from 'react'
import { supabase } from '../lib/supabase'
import { cognome } from '../lib/nomi'
import { useSeasonData } from '../lib/useSeasonData'
import type { EventoGol, League, MatchPlayerStat, MatchTeamStats, Membership } from '../types'
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

// Come sul tabellone di uno stadio: i marcatori stanno sotto la propria squadra.
function ScorerList({ eventi, lato, players }: { eventi: EventoGol[]; lato: 'casa' | 'ospite'; players: Map<number, PlayerIdentity> }) {
  const propri = eventi.filter((evento) => evento.lato === lato)
  if (propri.length === 0) return null
  return <ul className={`match-scorers match-scorers--${lato}`}>
    {propri.map((evento, indice) => {
      const assistman = evento.assist === null ? undefined : players.get(evento.assist)
      return <li key={`${evento.minuto}-${evento.marcatore}-${indice}`}>
        <b>{cognome(players.get(evento.marcatore)?.nome ?? `Giocatore ${evento.marcatore}`)}</b>
        <time>{evento.minuto}&#39;</time>
        {assistman && <em title={`Assist di ${assistman.nome}`}>({cognome(assistman.nome)})</em>}
      </li>
    })}
  </ul>
}

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
  const [titolariByTeam, setTitolariByTeam] = useState<Map<number, Set<number>>>(new Map())
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

  // Serve solo a sapere chi era titolare, per dividere la lista sotto.
  useEffect(() => {
    let active = true
    async function loadLineups() {
      if (!fixture) return
      const { data: rows } = await supabase.from('lineups').select('team_id, titolari')
        .eq('league_id', fixture.league_id).eq('giornata', fixture.giornata)
        .in('team_id', [fixture.home_team_id, fixture.away_team_id])
      if (!active) return
      const mappa = new Map<number, Set<number>>()
      for (const row of rows ?? []) mappa.set(row.team_id, new Set(row.titolari as number[]))
      setTitolariByTeam(mappa)
    }
    void loadLineups()
    return () => { active = false }
  }, [fixture])

  // Le partite simulate prima dell'introduzione della cronaca hanno blocchi vuoto.
  const eventi = useMemo(() => {
    const registrati = match?.blocchi
    if (!Array.isArray(registrati)) return []
    return [...registrati].sort((sinistra, destra) => sinistra.minuto - destra.minuto)
  }, [match])

  const byTeam = useMemo(() => {
    const grouped = new Map<number, MatchPlayerStat[]>()
    for (const row of stats) grouped.set(row.team_id, [...(grouped.get(row.team_id) ?? []), row])
    for (const rows of grouped.values()) rows.sort((left, right) => right.gol - left.gol || right.assist - left.assist || right.tiri_porta - left.tiri_porta || right.minuti - left.minuti)
    return grouped
  }, [stats])

  // Titolari e subentrati in due gruppi separati, ciascuno gia' ordinato come
  // sopra. Chi e' uscito si riconosce senza ambiguita' solo fra i titolari
  // (minuti < 90): per un subentrato gli stessi minuti ridotti potrebbero
  // significare solo che e' entrato tardi, non che sia uscito a sua volta.
  const gruppiByTeam = useMemo(() => {
    const risultato = new Map<number, { titolari: MatchPlayerStat[]; subentrati: MatchPlayerStat[] }>()
    for (const [teamId, rows] of byTeam) {
      const titolariSet = titolariByTeam.get(teamId) ?? new Set<number>()
      // Chi ha giocato tutti i 90' non puo' essere un vero subentrato: succede
      // quando il titolare designato era infortunato al fischio d'inizio e il
      // motore lo ha rimpiazzato dalla panchina prima che la partita iniziasse,
      // uno scambio che "lineups.titolari" (la scelta salvata prima della
      // partita) non registra mai.
      const eTitolare = (row: MatchPlayerStat) => titolariSet.has(row.player_instance_id) || row.minuti === 90
      risultato.set(teamId, {
        titolari: rows.filter(eTitolare),
        subentrati: rows.filter((row) => !eTitolare(row)),
      })
    }
    return risultato
  }, [byTeam, titolariByTeam])

  function navigate(view: GameView) { onNavigate(view) }

  // mostraUscita e' vero solo per i titolari: e' l'unico caso in cui minuti
  // ridotti significano senza ambiguita' "sostituito", non "entrato tardi".
  function rigaGiocatore(row: MatchPlayerStat, mostraUscita: boolean) {
    const identita = players.get(row.player_instance_id)
    return <div key={row.id}>
      <span><strong>{identita?.nome ?? `Giocatore ${row.player_instance_id}`}</strong><small>{identita?.posizioni.join(' · ')}</small></span>
      <b>{row.minuti}{mostraUscita && row.minuti < 90 && <i className="match-player-uscita" title={`Uscito al ${row.minuti}'`}>↓</i>}</b>
      <b className={row.gol ? 'is-highlight' : ''}>{row.gol}</b>
      <b className={row.assist ? 'is-assist' : ''}>{row.assist}</b>
      <b>{row.tiri}</b>
      <b>{row.passaggi_riusciti}/{row.passaggi_tentati}</b>
    </div>
  }

  return <main className="app-shell season-shell">
    <GameNav league={league} active="matches" onNavigate={navigate} />
    <header className="topbar season-topbar"><button className="match-detail-back" type="button" onClick={onBack}>← Torna alle partite</button><span>Rapporto partita</span></header>
    <SeasonState loading={data.loading} error={data.error} onRetry={data.reload} />
    {!data.loading && !data.error && (!match || !fixture) && <section className="season-state"><span className="season-state__icon">!</span><h2>Partita non trovata</h2><button className="button button--primary" type="button" onClick={onBack}>Torna indietro</button></section>}
    {!data.loading && !data.error && match && fixture && <div className="season-page season-page--narrow match-detail-page">
      <section className="match-report-hero">
        <p className="kicker">Giornata {fixture.giornata} · Stagione {league.stagione_corrente}</p>
        {/* Stemmi e punteggio stanno sulla prima riga della griglia, i marcatori
            sulla seconda: cosi' la lista puo' crescere senza spostare gli stemmi. */}
        <div className="match-report-score">
          <div><TeamLabel team={data.teamById.get(fixture.home_team_id)} imageUrl={data.crestUrlByTeamId.get(fixture.home_team_id)} onClick={() => onOpenTeam(fixture.home_team_id)} /></div>
          <strong><span>{match.gol_home}</span><i>-</i><span>{match.gol_away}</span></strong>
          <div><TeamLabel team={data.teamById.get(fixture.away_team_id)} imageUrl={data.crestUrlByTeamId.get(fixture.away_team_id)} reversed onClick={() => onOpenTeam(fixture.away_team_id)} /></div>
          <ScorerList eventi={eventi} lato="casa" players={players} />
          <ScorerList eventi={eventi} lato="ospite" players={players} />
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
          {[fixture.home_team_id, fixture.away_team_id].map((teamId) => {
            const gruppi = gruppiByTeam.get(teamId)
            return <div className="match-player-team" key={teamId}>
              <h3>{data.teamById.get(teamId)?.nome ?? 'Squadra'}</h3>
              <div className="match-player-table">
                <div className="match-player-table__head"><span>Giocatore</span><span>MIN</span><span>G</span><span>A</span><span>T</span><span>PASS</span></div>
                {gruppi && gruppi.titolari.length > 0 && <>
                  <p className="match-player-group">Titolari</p>
                  {gruppi.titolari.map((row) => rigaGiocatore(row, true))}
                </>}
                {gruppi && gruppi.subentrati.length > 0 && <>
                  <p className="match-player-group">Subentrati</p>
                  {gruppi.subentrati.map((row) => rigaGiocatore(row, false))}
                </>}
              </div>
            </div>
          })}
        </div>}
      </section>
    </div>}
  </main>
}
