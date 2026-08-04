import { useCallback, useEffect, useMemo, useState, type FormEvent } from 'react'
import { formatoStemma, generaUuidV4, preparaStemma } from '../lib/crest'
import { ROSA_MASSIMA, ROSA_MINIMA } from '../lib/league'
import { supabase } from '../lib/supabase'
import { STEMMA_SQUADRA_DEFAULT } from '../lib/teamCrests'
import { useSeasonData } from '../lib/useSeasonData'
import type { CrestChoice, Fixture, League, MatchPlayerStat, Membership, Team } from '../types'
import { Crest } from './Crest'
import { CrestPicker } from './CrestPicker'
import { GameNav, type GameView } from './GameNav'
import { SchedaGiocatore, type StatsStagione } from './SchedaGiocatore'
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
  nazionalita: string | null
  posizioni: string[]
  overall: number
  eta: number
  ingaggio: number
  condizione: number
  infortunatoFinoA: number
  piede: string | null
  altezza: number | null
  attributi: Record<string, number | null>
  foto_url: string | null
  ritiroAnnunciato: boolean
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
  const [statRows, setStatRows] = useState<MatchPlayerStat[]>([])
  const [schedaAperta, setSchedaAperta] = useState<RosterPlayer | null>(null)
  const [fotoScheda, setFotoScheda] = useState<string | undefined>(undefined)
  const [allenatore, setAllenatore] = useState<string | null>(null)
  const [rosterLoading, setRosterLoading] = useState(true)
  const [rosterError, setRosterError] = useState<string | null>(null)
  const [editing, setEditing] = useState(false)
  const [teamName, setTeamName] = useState('')
  const [crest, setCrest] = useState<CrestChoice>({ type: 'preset', value: STEMMA_SQUADRA_DEFAULT })
  const [saving, setSaving] = useState(false)
  const [saveError, setSaveError] = useState<string | null>(null)
  const [releasePending, setReleasePending] = useState(false)
  const [releaseError, setReleaseError] = useState<string | null>(null)
  const [rosterNotice, setRosterNotice] = useState<string | null>(null)
  const team = teamOverride?.id === teamId ? teamOverride : seasonData.teamById.get(teamId)
  const ownTeam = teamId === membership.id

  // Il nome dell'allenatore e' leggibile solo fra chi condivide una lega
  // (policy profiles_lettura): fuori dalla lega la query non restituisce nulla.
  useEffect(() => {
    let active = true
    async function loadAllenatore() {
      if (!team?.user_id) { setAllenatore(null); return }
      const { data } = await supabase.from('profiles').select('nome_allenatore').eq('user_id', team.user_id).maybeSingle()
      if (active) setAllenatore((data as { nome_allenatore: string } | null)?.nome_allenatore ?? null)
    }
    void loadAllenatore()
    return () => { active = false }
  }, [team?.user_id])

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
        : { type: 'preset', value: STEMMA_SQUADRA_DEFAULT })
  }, [team, crestUrl])

  useEffect(() => {
    let active = true
    async function loadRoster() {
      setRosterLoading(true)
      setRosterError(null)
      const [instancesResult, statsResult] = await Promise.all([
        supabase.from('player_instances').select('id, player_id, overall_corrente, eta_corrente, ingaggio, condizione, infortunato_fino_a, ritiro_annunciato').eq('league_id', league.id).eq('team_id', teamId),
        supabase.from('match_stats').select('match_id, player_instance_id, minuti, gol, assist, tiri, tiri_porta, passaggi_tentati, passaggi_riusciti, contrasti_vinti, dribbling').eq('league_id', league.id).eq('team_id', teamId),
      ])
      const firstError = instancesResult.error ?? statsResult.error
      if (firstError) { if (active) { setRosterError(firstError.message); setRosterLoading(false) }; return }
      const instances = instancesResult.data ?? []
      const playerIds = instances.map((item) => item.player_id)
      const { data: catalog, error: catalogError } = playerIds.length
        ? await supabase.from('players').select('id, nome, club, nazionalita, posizioni, piede, altezza, attributi, foto_url').in('id', playerIds)
        : { data: [], error: null }
      if (catalogError) { if (active) { setRosterError(catalogError.message); setRosterLoading(false) }; return }
      const catalogById = new Map((catalog ?? []).map((item) => [item.id, item]))
      const totals = new Map<number, { minuti: number; gol: number; assist: number }>()
      for (const stat of (statsResult.data ?? []) as MatchPlayerStat[]) {
        const total = totals.get(stat.player_instance_id) ?? { minuti: 0, gol: 0, assist: 0 }
        total.minuti += stat.minuti; total.gol += stat.gol; total.assist += stat.assist
        totals.set(stat.player_instance_id, total)
      }
      const loaded = instances.map((instance) => {
        const info = catalogById.get(instance.player_id)
        const total = totals.get(instance.id) ?? { minuti: 0, gol: 0, assist: 0 }
        return {
          id: instance.id, nome: info?.nome ?? `Giocatore ${instance.id}`, club: info?.club ?? '—',
          nazionalita: info?.nazionalita ?? null, posizioni: info?.posizioni ?? [],
          overall: instance.overall_corrente, eta: instance.eta_corrente, ingaggio: instance.ingaggio,
          condizione: instance.condizione, infortunatoFinoA: instance.infortunato_fino_a, piede: info?.piede ?? null, altezza: info?.altezza ?? null,
          attributi: (info?.attributi ?? {}) as Record<string, number | null>, foto_url: info?.foto_url ?? null,
          ritiroAnnunciato: instance.ritiro_annunciato,
          ...total,
        }
      }).sort((left, right) => ROLE_ORDER[department(left.posizioni[0])] - ROLE_ORDER[department(right.posizioni[0])] || right.overall - left.overall || left.nome.localeCompare(right.nome, 'it'))
      if (active) { setPlayers(loaded); setStatRows((statsResult.data ?? []) as MatchPlayerStat[]); setRosterLoading(false) }
    }
    void loadRoster()
    return () => { active = false }
  }, [league.id, teamId])

  const standing = seasonData.standings.find((item) => item.team_id === teamId)
  const recentFixtures = useMemo(() => [...seasonData.fixtures].reverse().filter((fixture) => fixture.stato === 'simulata' && (fixture.home_team_id === teamId || fixture.away_team_id === teamId)).slice(0, 5), [seasonData.fixtures, teamId])

  // Esito dal punto di vista di questa squadra: serve sia ai chip della forma
  // sia alla striscia colorata di ogni risultato.
  const esitoDi = useCallback((fixture: Fixture) => {
    const match = seasonData.matchByFixture.get(fixture.id)
    if (!match) return null
    const inCasa = fixture.home_team_id === teamId
    const propri = inCasa ? match.gol_home : match.gol_away
    const subiti = inCasa ? match.gol_away : match.gol_home
    return propri > subiti ? 'V' : propri < subiti ? 'P' : 'N'
  }, [seasonData.matchByFixture, teamId])

  const forma = useMemo(() => [...recentFixtures].reverse().map(esitoDi).filter((esito): esito is 'V' | 'N' | 'P' => esito !== null), [recentFixtures, esitoDi])
  const totalWage = players.reduce((sum, player) => sum + player.ingaggio, 0)

  // Gol subiti dalla squadra in ogni partita: serve per la porta inviolata,
  // che non e' un dato del singolo giocatore ma della squadra in cui giocava.
  const subitiPerPartita = useMemo(() => {
    const mappa = new Map<number, number>()
    for (const match of seasonData.matches) {
      const fixture = seasonData.fixtures.find((item) => item.id === match.fixture_id)
      if (!fixture) continue
      if (fixture.home_team_id === teamId) mappa.set(match.id, match.gol_away)
      else if (fixture.away_team_id === teamId) mappa.set(match.id, match.gol_home)
    }
    return mappa
  }, [seasonData.matches, seasonData.fixtures, teamId])

  const statsPerGiocatore = useMemo(() => {
    const mappa = new Map<number, StatsStagione>()
    for (const riga of statRows) {
      const corrente = mappa.get(riga.player_instance_id) ?? {
        presenze: 0, minuti: 0, gol: 0, assist: 0, porteInviolate: 0,
        tiri: 0, tiriPorta: 0, passaggiTentati: 0, passaggiRiusciti: 0, contrastiVinti: 0, dribbling: 0,
      }
      if (riga.minuti > 0) {
        corrente.presenze += 1
        if (subitiPerPartita.get(riga.match_id) === 0) corrente.porteInviolate += 1
      }
      corrente.minuti += riga.minuti
      corrente.gol += riga.gol
      corrente.assist += riga.assist
      corrente.tiri += riga.tiri
      corrente.tiriPorta += riga.tiri_porta
      corrente.passaggiTentati += riga.passaggi_tentati
      corrente.passaggiRiusciti += riga.passaggi_riusciti
      corrente.contrastiVinti += riga.contrasti_vinti
      corrente.dribbling += riga.dribbling
      mappa.set(riga.player_instance_id, corrente)
    }
    return mappa
  }, [statRows, subitiPerPartita])

  useEffect(() => {
    let active = true
    async function firmaFoto() {
      if (!schedaAperta?.foto_url) { setFotoScheda(undefined); return }
      const { data } = await supabase.storage.from('player-photos').createSignedUrl(schedaAperta.foto_url, 3600)
      if (active) setFotoScheda(data?.signedUrl ?? undefined)
    }
    void firmaFoto()
    return () => { active = false }
  }, [schedaAperta])

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

  function openPlayer(player: RosterPlayer) {
    setReleaseError(null)
    setRosterNotice(null)
    setSchedaAperta(player)
  }

  async function releasePlayer() {
    if (!schedaAperta || !ownTeam) return
    setReleasePending(true)
    setReleaseError(null)
    const player = schedaAperta
    const { error } = await supabase.rpc('svincola_giocatore', { p_instance_id: player.id })
    if (error) {
      setReleaseError(error.message)
      setReleasePending(false)
      return
    }
    setPlayers((current) => current.filter((item) => item.id !== player.id))
    setStatRows((current) => current.filter((item) => item.player_instance_id !== player.id))
    setSchedaAperta(null)
    setRosterNotice(`${player.nome} è stato svincolato. Nessun rimborso è stato accreditato.`)
    setReleasePending(false)
  }

  return <main className="app-shell season-shell">
    <GameNav league={league} active="team" onNavigate={onNavigate} />
    <header className="topbar season-topbar"><div className="brand-lockup brand-lockup--dark"><img src="/specialone-mark.svg" alt="" /><span>SpecialOne</span></div><span>{ownTeam ? 'La tua squadra' : 'Profilo avversario'}</span></header>
    <SeasonState loading={seasonData.loading} error={seasonData.error} onRetry={seasonData.reload} />
    {!seasonData.loading && !seasonData.error && team && <div className="season-page team-profile-page">
      <section className="team-profile-hero">
        <div className="team-profile-crest"><Crest value={team.stemma_url} imageUrl={crestUrl} size="large" /></div>
        <div>
          <p className="kicker">{league.nome} · Stagione {league.stagione_corrente}</p>
          <h1>{team.nome}</h1>
          {allenatore && <p className="team-allenatore">Allenatore · <b>{allenatore}</b></p>}
          <div className="team-form">
            <span className="team-form__eti">FORMA</span>
            {forma.map((esito, indice) => <span className={`esito esito--${esito}`} key={`e${indice}`}>{esito}</span>)}
            {Array.from({ length: Math.max(0, 5 - forma.length) }).map((_, indice) => <span className="esito esito--vuoto" key={`v${indice}`} aria-hidden="true">·</span>)}
          </div>
        </div>
        {ownTeam && <button className="button team-edit-button" type="button" onClick={() => setEditing((value) => !value)}>{editing ? 'Chiudi modifica' : 'Modifica squadra'}</button>}
      </section>

      {ownTeam && editing && <form className="team-settings-panel" onSubmit={saveProfile}>
        <div><p className="kicker">Impostazioni squadra</p><h2>Nome e logo</h2><label>Nome squadra<input type="text" minLength={2} maxLength={40} required value={teamName} onChange={(event) => setTeamName(event.target.value)} /></label></div>
        <CrestPicker value={crest} onChange={setCrest} disabled={saving} />
        {saveError && <p className="notice notice--error">{saveError}</p>}
        <button className="button button--primary" type="submit" disabled={saving}>{saving ? 'Salvataggio…' : 'Salva modifiche'}</button>
      </form>}

      {/* Una statistica domina, le altre servono: quattro riquadri identici
          appiattivano la pagina e non dicevano cosa guardare per primo. */}
      <section className="team-profile-stats">
        <article className="stat-guida">
          <span className="stat-guida__numero">{standing?.posizione ?? '—'}<sup>ª</sup></span>
          <span className="stat-guida__testo">
            <b>Posizione in classifica</b>
            <span>{standing?.punti ?? 0} punti · {standing?.vittorie ?? 0} {standing?.vittorie === 1 ? 'vittoria' : 'vittorie'}</span>
          </span>
        </article>
        <div className="stat-fila">
          <article><small>Bilancio</small><b>{standing ? `${standing.vittorie}-${standing.pareggi}-${standing.sconfitte}` : '0-0-0'}</b></article>
          <article><small>Reti</small><b className={(standing?.differenza_reti ?? 0) < 0 ? 'is-negativo' : (standing?.differenza_reti ?? 0) > 0 ? 'is-positivo' : ''}>{standing && standing.differenza_reti > 0 ? `+${standing.differenza_reti}` : standing?.differenza_reti ?? 0}</b></article>
          <article><small>Overall</small><b>{players.length ? (players.reduce((sum, player) => sum + player.overall, 0) / players.length).toFixed(1) : '—'}</b></article>
        </div>
      </section>

      <section className="team-profile-grid">
        <article className="team-profile-panel team-recent-panel"><div className="season-card__heading"><div><p className="kicker">Forma recente</p><h2>Ultime partite</h2></div></div>{recentFixtures.length ? recentFixtures.map((fixture) => { const match = seasonData.matchByFixture.get(fixture.id); return <button className={`esito-riga esito-riga--${esitoDi(fixture) ?? 'N'}`} type="button" key={fixture.id} onClick={() => match && onOpenMatch(match.id)}><TeamLabel team={seasonData.teamById.get(fixture.home_team_id)} imageUrl={seasonData.crestUrlByTeamId.get(fixture.home_team_id)} /><FixtureScore fixture={fixture} match={match} /><TeamLabel team={seasonData.teamById.get(fixture.away_team_id)} imageUrl={seasonData.crestUrlByTeamId.get(fixture.away_team_id)} reversed /></button> }) : <p className="season-empty">Nessuna partita disputata.</p>}</article>
        <article className="team-profile-panel team-budget-panel"><p className="kicker">Gestione rosa</p><h2>{players.length} giocatori</h2><dl><div><dt>Valore ingaggi</dt><dd>{money(totalWage)}</dd></div>{ownTeam ? <div><dt>Budget disponibile</dt><dd>{money(team.budget)}</dd></div> : <div><dt>Gol segnati</dt><dd>{standing?.gol_fatti ?? 0}</dd></div>}<div><dt>Overall medio</dt><dd>{players.length ? (players.reduce((sum, player) => sum + player.overall, 0) / players.length).toFixed(1) : '—'}</dd></div></dl></article>
      </section>

      <section className="team-roster-panel">
        <div className="season-card__heading"><div><p className="kicker">Rosa completa</p><h2>Dal portiere all’attacco</h2></div><span>{players.length} giocatori · min {ROSA_MINIMA} · max {ROSA_MASSIMA}</span></div>
        {rosterNotice && <p className="notice notice--success">{rosterNotice}</p>}
        {rosterError && <p className="notice notice--error">{rosterError}</p>}
        {rosterLoading ? <p className="season-empty">Carico la rosa…</p> : <div className="team-roster-list">{players.map((player) => <button className={`team-roster-player team-roster-player--${department(player.posizioni[0])}`} type="button" key={player.id} onClick={() => openPlayer(player)} aria-label={`Scheda di ${player.nome}`}><i /><span className="team-roster-role">{player.posizioni[0] ?? '—'}</span><div><strong>{player.nome}</strong><small>{player.posizioni.join(' · ')} · {player.eta} anni · <em>{money(player.ingaggio)}/anno</em></small></div><b>{player.overall}</b><dl><span>{player.minuti}<small>MIN</small></span><span>{player.gol}<small>GOL</small></span><span>{player.assist}<small>ASS</small></span></dl></button>)}</div>}
      </section>

      {schedaAperta && <SchedaGiocatore
        giocatore={{
          nome: schedaAperta.nome,
          nazionalita: schedaAperta.nazionalita,
          posizioni: schedaAperta.posizioni,
          overall: schedaAperta.overall,
          eta: schedaAperta.eta,
          piede: schedaAperta.piede,
          altezza: schedaAperta.altezza,
          ingaggio: schedaAperta.ingaggio,
          condizione: schedaAperta.condizione,
          infortunatoFinoA: schedaAperta.infortunatoFinoA,
          ritiroAnnunciato: schedaAperta.ritiroAnnunciato,
          attributi: schedaAperta.attributi,
        }}
        fotoUrl={fotoScheda}
        stagione={statsPerGiocatore.get(schedaAperta.id) ?? {
          presenze: 0, minuti: 0, gol: 0, assist: 0, porteInviolate: 0,
          tiri: 0, tiriPorta: 0, passaggiTentati: 0, passaggiRiusciti: 0, contrastiVinti: 0, dribbling: 0,
        }}
        azionePericolosa={ownTeam && league.stato === 'stagione' ? {
          etichetta: 'Svincola giocatore',
          descrizione: schedaAperta.ritiroAnnunciato
            ? `${schedaAperta.nome} ha già annunciato il ritiro: lo svincolo è definitivo, non tornerà disponibile per nessuna squadra. Non riceverai alcun rimborso e le formazioni future che lo contengono dovranno essere salvate di nuovo.`
            : `${schedaAperta.nome} uscirà subito dalla rosa. Devi mantenere almeno ${ROSA_MINIMA} giocatori. Non riceverai alcun rimborso e le formazioni future che lo contengono dovranno essere salvate di nuovo.`,
          inCorso: releasePending,
          errore: releaseError,
          onConferma: releasePlayer,
        } : undefined}
        onClose={() => setSchedaAperta(null)}
      />}
    </div>}
  </main>
}
