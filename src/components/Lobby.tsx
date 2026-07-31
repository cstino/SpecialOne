import { useEffect, useState } from 'react'
import type { User } from '@supabase/supabase-js'
import { supabase } from '../lib/supabase'
import type { League, Membership, Team } from '../types'
import { Crest } from './Crest'

type LobbyProps = {
  user: User
  membership: Membership
  memberships: Membership[]
  onSelectLeague: (leagueId: number) => void
  onNewLeague: () => void
  onRefresh: () => void
}

export function Lobby({ user, membership, memberships, onSelectLeague, onNewLeague, onRefresh }: LobbyProps) {
  const league = membership.league as League
  const [teams, setTeams] = useState<Team[]>([])
  const [imageUrls, setImageUrls] = useState<Record<string, string>>({})
  const [loading, setLoading] = useState(true)
  const [loadError, setLoadError] = useState<string | null>(null)
  const [copied, setCopied] = useState(false)
  const [refreshIndex, setRefreshIndex] = useState(0)

  useEffect(() => {
    let active = true
    async function load() {
      setLoading(true)
      setLoadError(null)
      const { data, error } = await supabase.from('teams').select('*').eq('league_id', league.id).order('creata_il')
      if (!active) return
      if (error) {
        setLoadError(`Non riesco a leggere i partecipanti. ${error.message}`)
        setLoading(false)
        return
      }
      const loadedTeams = (data ?? []) as Team[]
      setTeams(loadedTeams)

      const uploaded = loadedTeams.filter((team) => team.stemma_url && !team.stemma_url.startsWith('preset:'))
      const signed = await Promise.all(
        uploaded.map(async (team) => {
          const { data: signedData, error: signedError } = await supabase.storage.from('team-crests').createSignedUrl(team.stemma_url!, 3600)
          return [team.stemma_url!, signedData?.signedUrl, signedError] as const
        }),
      )
      if (active) {
        setImageUrls(signed.reduce<Record<string, string>>((result, [path, url]) => {
          if (url) result[path] = url
          return result
        }, {}))
        if (signed.some((entry) => entry[2])) setLoadError('Alcuni stemmi personalizzati non sono disponibili. Riprova tra poco.')
      }
      if (active) setLoading(false)
    }
    void load()
    return () => { active = false }
  }, [league.id, refreshIndex])

  async function copyCode() {
    await navigator.clipboard.writeText(league.codice_invito)
    setCopied(true)
    window.setTimeout(() => setCopied(false), 1800)
  }

  return (
    <main className="app-shell lobby-shell">
      <header className="topbar">
        <div className="brand-lockup brand-lockup--dark"><img src="/specialone-mark.svg" alt="" /><span>SpecialOne</span></div>
        <div className="topbar-actions">
          <span className="user-email">{user.email}</span>
          <button className="text-button" type="button" onClick={() => supabase.auth.signOut()}>Esci</button>
        </div>
      </header>

      <section className="lobby-hero">
        <div>
          <p className="kicker">Spogliatoio · Preparazione</p>
          <h1>{league.nome}</h1>
          <p>La lega partirà quando l’admin avrà completato i posti e aperto il draft.</p>
        </div>
        <div className="invite-board">
          <span>Codice invito</span>
          <button type="button" onClick={copyCode} aria-label="Copia codice invito">
            <strong>{league.codice_invito}</strong>
            <small>{copied ? 'Copiato' : 'Tocca per copiare'}</small>
          </button>
        </div>
      </section>

      <div className="lobby-grid">
        <section className="squad-list">
          <div className="section-heading-row">
            <div><p className="kicker">Partecipanti</p><h2>{teams.length} su {league.n_squadre} squadre</h2></div>
            <button className="text-button" type="button" onClick={() => { onRefresh(); setRefreshIndex((value) => value + 1) }}>Aggiorna</button>
          </div>
          {loadError && <p className="notice notice--error" role="alert">{loadError}</p>}
          {loading ? (
            <p className="empty-state">Sto leggendo la distinta…</p>
          ) : teams.length > 0 ? (
            <ol className="teams-roster">
              {teams.map((team, index) => (
                <li key={team.id}>
                  <span className="roster-number">{String(index + 1).padStart(2, '0')}</span>
                  <Crest value={team.stemma_url} imageUrl={team.stemma_url ? imageUrls[team.stemma_url] : null} />
                  <div><strong>{team.nome}</strong><span>{team.user_id === league.admin_id ? 'Admin della lega' : 'Partecipante'}</span></div>
                  {team.user_id === user.id && <span className="status-chip">La tua</span>}
                </li>
              ))}
              {Array.from({ length: Math.max(0, league.n_squadre - teams.length) }, (_, index) => (
                <li className="team-slot-empty" key={`empty-${index}`}>
                  <span className="roster-number">{String(teams.length + index + 1).padStart(2, '0')}</span>
                  <span className="empty-crest" aria-hidden="true">＋</span>
                  <div><strong>Posto libero</strong><span>In attesa del codice invito</span></div>
                </li>
              ))}
            </ol>
          ) : !loadError ? <p className="empty-state">Nessuna squadra registrata.</p> : null}
        </section>

        <aside className="league-sheet">
          <p className="kicker">Regole della stagione</p>
          <dl>
            <div><dt>Durata</dt><dd>{league.giornate_totali} giorni</dd></div>
            <div><dt>Gironi</dt><dd>{league.n_gironi}</dd></div>
            <div><dt>Budget</dt><dd>{league.budget_iniziale / 1_000_000} M€</dd></div>
            <div><dt>Rosa</dt><dd>{league.slot_rosa} giocatori</dd></div>
            <div><dt>Reroll</dt><dd>{league.reroll_draft}</dd></div>
          </dl>
          <div className="competition-summary">
            <span>Pool attivo</span>
            <strong>{league.campionati_attivi.length} campionati</strong>
          </div>
        </aside>
      </div>

      <footer className="league-switcher">
        {memberships.length > 1 && (
          <label>Le mie leghe
            <select value={league.id} onChange={(event) => onSelectLeague(Number(event.target.value))}>
              {memberships.map((item) => <option key={item.league_id} value={item.league_id}>{item.league?.nome}</option>)}
            </select>
          </label>
        )}
        <button className="button button--secondary" type="button" onClick={onNewLeague}>Crea o raggiungi un’altra lega</button>
      </footer>
    </main>
  )
}
