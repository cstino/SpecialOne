import { useEffect, useMemo, useState, type FormEvent } from 'react'
import { formatoStemma, generaUuidV4, preparaStemma } from '../lib/crest'
import { supabase } from '../lib/supabase'
import { useSeasonData } from '../lib/useSeasonData'
import type { CrestChoice, League, MatchPlayerStat, Membership, Team } from '../types'
import { Crest } from './Crest'
import { CrestPicker } from './CrestPicker'
import { GameNav, type GameView } from './GameNav'
import { FixtureScore, SeasonState, TeamLabel } from './SeasonUI'

type Props = {
  membership: Membership
  teamId: number
  onNavigate: (view: GameView) => void
  onOpenMatch: (matchId: number) => void
  onTeamUpdated: () => Promise<void>
}

type RosterPlayer = {
  id: number
  nome: string
  club: string
  posizioni: string[]
  overall: number
  eta: number
  ingaggio: number
  minuti: number
  gol: number
  assist: number
}

const ROLE_ORDER: Record<string, number> = { GK: 0, DEF: 1, MID: 2, ATT: 3 }
const DEF = new Set(['LB', 'CB', 'RB', 'LWB', 'RWB'])
const MID = new Set(['CDM', 'CM', 'CAM', 'LM', 'RM'])

function department(position = '') {
  if (position === 'GK') return 'GK'
  if (DEF.has(position)) return 'DEF'
  if (MID.has(position)) return 'MID'
  return 'ATT'
}

function money(value: number) { return `${(value / 1_000_000).toFixed(1)} M€` }

export function TeamProfile({ membership, teamId, onNavigate, onOpenMatch, onTeamUpdated }: Props) {
  const league = membership.league as League
  const seasonData = useSeasonData(membership)
  const [teamOverride, setTeamOverride] = useState<Team | null>(null)
  const [crestUrl, setCrestUrl] = useState<string | null>(null)
  const [players, setPlayers] = useState<RosterPlayer[]>([])
  const [rosterLoading, setRosterLoading] = useState(true)
  const [rosterError, setRosterError] = useState<string | null>(null)
  const [editing, setEditing] = useState(false)
  const [teamName, setTeamName] = useState('')
  const [crest, setCrest] = useState<CrestChoice>({ type: 'preset', value: 'preset:scudo' })
  const [saving, setSaving] = useState(false)
  const [saveError, setSaveError] = useState<string | null>(null)
  const team = teamOverride?.id === teamId ? teamOverride : seasonData.teamById.get(teamId)
  const ownTeam = teamId === membership.id

  useEffect(() => {
    let active = true
    async function loadCrest() {
      if (!team?.stemma_url || team.stemma_url.startsWith('preset:')) { setCrestUrl(null); return }
      const { data } = await supabase.storage.from('team-crests').createSignedUrl(team.stemma_url, 3600)
      if (active) setCrestUrl(data?.signedUrl ?? null)
    }
    void loadCrest()
    return () => { active = false }
  }, [team?.stemma_url])

  useEffect(() => {
    if (!team) return
    setTeamName(team.nome)
    setCrest(team.stemma_url?.startsWith('preset:')
      ? { type: 'preset', value: team.stemma_url }
      : team.stemma_url && crestUrl
        ? { type: 'existing', value: team.stemma_url, previewUrl: crestUrl }
        : { type: 'preset', value: 'preset:scudo' })
  }, [team, crestUrl])

  useEffect(() => {
    let active = true
    async function loadRoster() {
      setRosterLoading(true)
      setRosterError(null)
      const [instancesResult, statsResult] = await Promise.all([
        supabase.from('player_instances').select('id, player_id, overall_corrente, eta_corrente, ingaggio').eq('league_id', league.id).eq('team_id', teamId),
        supabase.from('match_stats').select('player_instance_id, minuti, gol, assist').eq('league_id', league.id).eq('team_id', teamId),
      ])
      const firstError = instancesResult.error ?? statsResult.error
      if (firstError) { if (active) { setRosterError(firstError.message); setRosterLoading(false) }; return }
      const instances = instancesResult.data ?? []
      const playerIds = instances.map((item) => item.player_id)
      const { data: catalog, error: catalogError } = playerIds.length
        ? await supabase.from('players').select('id, nome, club, posizioni').in('id', playerIds)
        : { data: [], error: null }
      if (catalogError) { if (active) { setRosterError(catalogError.message); setRosterLoading(false) }; return }
      const catalogById = new Map((catalog ?? []).map((item) => [item.id, item]))
      const totals = new Map<number, { minuti: number; gol: number; assist: number }>()
      for (const stat of (statsResult.data ?? []) as Pick<MatchPlayerStat, 'player_instance_id' | 'minuti' | 'gol' | 'assist'>[]) {
        const total = totals.get(stat.player_instance_id) ?? { minuti: 0, gol: 0, assist: 0 }
        total.minuti += stat.minuti; total.gol += stat.gol; total.assist += stat.assist
        totals.set(stat.player_instance_id, total)
      }
      const loaded = instances.map((instance) => {
        const info = catalogById.get(instance.player_id)
        const total = totals.get(instance.id) ?? { minuti: 0, gol: 0, assist: 0 }
        return { id: instance.id, nome: info?.nome ?? `Giocatore ${instance.id}`, club: info?.club ?? '—', posizioni: info?.posizioni ?? [], overall: instance.overall_corrente, eta: instance.eta_corrente, ingaggio: instance.ingaggio, ...total }
      }).sort((left, right) => ROLE_ORDER[department(left.posizioni[0])] - ROLE_ORDER[department(right.posizioni[0])] || right.overall - left.overall || left.nome.localeCompare(right.nome, 'it'))
      if (active) { setPlayers(loaded); setRosterLoading(false) }
    }
    void loadRoster()
    return () => { active = false }
  }, [league.id, teamId])

  const standing = seasonData.standings.find((item) => item.team_id === teamId)
  const recentFixtures = useMemo(() => [...seasonData.fixtures].reverse().filter((fixture) => fixture.stato === 'simulata' && (fixture.home_team_id === teamId || fixture.away_team_id === teamId)).slice(0, 5), [seasonData.fixtures, teamId])
  const totalWage = players.reduce((sum, player) => sum + player.ingaggio, 0)

  async function saveProfile(event: FormEvent) {
    event.preventDefault()
    if (!team) return
    setSaving(true); setSaveError(null)
    let uploadedPath: string | null = null
    try {
      let crestPath = crest.type === 'upload' ? '' : crest.value
      if (crest.type === 'upload') {
        const blob = await preparaStemma(crest.file)
        const formato = formatoStemma(blob)
        uploadedPath = `${membership.user_id}/${generaUuidV4()}.${formato.extension}`
        const { error } = await supabase.storage.from('team-crests').upload(uploadedPath, blob, { contentType: formato.contentType, cacheControl: '31536000', upsert: false })
        if (error) throw error
        crestPath = uploadedPath
      }
      const { data, error } = await supabase.rpc('aggiorna_profilo_squadra', { p_team_id: team.id, p_nome: teamName, p_stemma_url: crestPath })
      if (error) throw error
      const updated = data as Team
      setTeamOverride(updated)
      if (team.stemma_url && !team.stemma_url.startsWith('preset:') && team.stemma_url !== crestPath) await supabase.storage.from('team-crests').remove([team.stemma_url])
      await onTeamUpdated()
      setEditing(false)
    } catch (caught) {
      if (uploadedPath) await supabase.storage.from('team-crests').remove([uploadedPath])
      setSaveError(caught instanceof Error ? caught.message : 'Modifica della squadra non riuscita.')
    }
    setSaving(false)
  }

  return <main className="app-shell season-shell">
    <GameNav league={league} active="team" onNavigate={onNavigate} />
    <header className="topbar season-topbar"><div className="brand-lockup brand-lockup--dark"><img src="/specialone-mark.svg" alt="" /><span>SpecialOne</span></div><span>{ownTeam ? 'La tua squadra' : 'Profilo avversario'}</span></header>
    <SeasonState loading={seasonData.loading} error={seasonData.error} onRetry={seasonData.reload} />
    {!seasonData.loading && !seasonData.error && team && <div className="season-page team-profile-page">
      <section className="team-profile-hero">
        <div className="team-profile-crest"><Crest value={team.stemma_url} imageUrl={crestUrl} size="large" /></div>
        <div><p className="kicker">{league.nome} · Stagione {league.stagione_corrente}</p><h1>{team.nome}</h1><p>{ownTeam ? 'Identità, rendimento e rosa completa della tua squadra.' : 'Rendimento e rosa pubblica della squadra avversaria.'}</p></div>
        {ownTeam && <button className="button team-edit-button" type="button" onClick={() => setEditing((value) => !value)}>{editing ? 'Chiudi modifica' : 'Modifica squadra'}</button>}
      </section>

      {ownTeam && editing && <form className="team-settings-panel" onSubmit={saveProfile}>
        <div><p className="kicker">Impostazioni squadra</p><h2>Nome e logo</h2><label>Nome squadra<input type="text" minLength={2} maxLength={40} required value={teamName} onChange={(event) => setTeamName(event.target.value)} /></label></div>
        <CrestPicker value={crest} onChange={setCrest} disabled={saving} />
        {saveError && <p className="notice notice--error">{saveError}</p>}
        <button className="button button--primary" type="submit" disabled={saving}>{saving ? 'Salvataggio…' : 'Salva modifiche'}</button>
      </form>}

      <section className="team-profile-stats">
        <article><span>Posizione</span><strong>{standing?.posizione ?? '—'}<small>ª</small></strong></article>
        <article><span>Punti</span><strong>{standing?.punti ?? 0}</strong></article>
        <article><span>Bilancio</span><strong>{standing ? `${standing.vittorie}-${standing.pareggi}-${standing.sconfitte}` : '0-0-0'}</strong><small>V · N · P</small></article>
        <article><span>Differenza reti</span><strong>{standing && standing.differenza_reti > 0 ? `+${standing.differenza_reti}` : standing?.differenza_reti ?? 0}</strong></article>
      </section>

      <section className="team-profile-grid">
        <article className="team-profile-panel team-recent-panel"><div className="season-card__heading"><div><p className="kicker">Forma recente</p><h2>Ultime partite</h2></div></div>{recentFixtures.length ? recentFixtures.map((fixture) => { const match = seasonData.matchByFixture.get(fixture.id); return <button type="button" key={fixture.id} onClick={() => match && onOpenMatch(match.id)}><TeamLabel team={seasonData.teamById.get(fixture.home_team_id)} imageUrl={seasonData.crestUrlByTeamId.get(fixture.home_team_id)} /><FixtureScore fixture={fixture} match={match} /><TeamLabel team={seasonData.teamById.get(fixture.away_team_id)} imageUrl={seasonData.crestUrlByTeamId.get(fixture.away_team_id)} reversed /></button> }) : <p className="season-empty">Nessuna partita disputata.</p>}</article>
        <article className="team-profile-panel team-budget-panel"><p className="kicker">Gestione rosa</p><h2>{players.length} giocatori</h2><dl><div><dt>Valore ingaggi</dt><dd>{money(totalWage)}</dd></div>{ownTeam ? <div><dt>Budget disponibile</dt><dd>{money(team.budget)}</dd></div> : <div><dt>Gol segnati</dt><dd>{standing?.gol_fatti ?? 0}</dd></div>}<div><dt>Overall medio</dt><dd>{players.length ? (players.reduce((sum, player) => sum + player.overall, 0) / players.length).toFixed(1) : '—'}</dd></div></dl></article>
      </section>

      <section className="team-roster-panel">
        <div className="season-card__heading"><div><p className="kicker">Rosa completa</p><h2>Dal portiere all’attacco</h2></div><span>{players.length} / {league.slot_rosa}</span></div>
        {rosterError && <p className="notice notice--error">{rosterError}</p>}
        {rosterLoading ? <p className="season-empty">Carico la rosa…</p> : <div className="team-roster-list">{players.map((player) => <article className={`team-roster-player team-roster-player--${department(player.posizioni[0])}`} key={player.id}><i /><span className="team-roster-role">{player.posizioni[0] ?? '—'}</span><div><strong>{player.nome}</strong><small>{player.posizioni.join(' · ')} · {player.eta} anni · {player.club}</small></div><b>{player.overall}</b><dl><span>{player.minuti}<small>MIN</small></span><span>{player.gol}<small>GOL</small></span><span>{player.assist}<small>ASS</small></span></dl></article>)}</div>}
      </section>
    </div>}
  </main>
}
