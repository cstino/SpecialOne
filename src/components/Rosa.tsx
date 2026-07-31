import { useEffect, useState } from 'react'
import type { League, Membership } from '../types'
import { supabase } from '../lib/supabase'
import { GameNav, type GameView } from './GameNav'

type Player = { id: number; nome: string; club: string; overall: number; eta: number; posizioni: string[]; ingaggio: number; foto_url: string | null }
type RosaProps = { membership: Membership; onNavigate: (view: GameView) => void }

export function Rosa({ membership, onNavigate }: RosaProps) {
  const league = membership.league as League
  const [players, setPlayers] = useState<Player[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    let active = true
    async function load() {
      const { data: instances, error: rosterError } = await supabase.from('player_instances')
        .select('id, player_id, ingaggio, overall_corrente, eta_corrente').eq('league_id', league.id).eq('team_id', membership.id).order('overall_corrente', { ascending: false })
      if (rosterError) { setError(rosterError.message); setLoading(false); return }
      const ids = (instances ?? []).map((item) => item.player_id)
      const { data: catalog, error: catalogError } = ids.length ? await supabase.from('players').select('id, nome, club, overall, eta, posizioni, foto_url').in('id', ids) : { data: [], error: null }
      if (catalogError) { setError(catalogError.message); setLoading(false); return }
      if (!active) return
      const byId = new Map((catalog ?? []).map((item) => [item.id, item]))
      setPlayers((instances ?? []).map((item) => ({ ...byId.get(item.player_id), id: item.id, ingaggio: item.ingaggio, overall: item.overall_corrente, eta: item.eta_corrente })) as Player[])
      setLoading(false)
    }
    void load()
    return () => { active = false }
  }, [league.id, membership.id])

  const wage = players.reduce((sum, player) => sum + player.ingaggio, 0)
  const progress = `${players.length} / ${league.slot_rosa}`
  return (
    <main className="app-shell roster-shell">
      <GameNav league={league} active="squad" onNavigate={onNavigate} />
      <header className="topbar"><div className="brand-lockup brand-lockup--dark"><img src="/specialone-mark.svg" alt="" /><span>SpecialOne</span></div><span className="kicker">La tua rosa</span></header>
      <section className="roster-hero"><div><p className="kicker">Squadra · {membership.nome}</p><h1>La mia rosa.</h1><p>Qui puoi controllare le scelte già fatte senza interrompere il draft.</p></div><div className="roster-summary"><span>Completamento</span><strong>{progress}</strong><small>{(wage / 1_000_000).toFixed(1)} M€ di ingaggi</small></div></section>
      {error && <p className="notice notice--error" role="alert">{error}</p>}
      <section className="roster-panel"><div className="section-heading-row"><div><p className="kicker">Giocatori selezionati</p><h2>{players.length} su {league.slot_rosa}</h2></div><button className="button button--primary" type="button" onClick={() => onNavigate('draft')}>Torna al draft</button></div>{loading ? <p className="empty-state">Carico la rosa…</p> : players.length ? <div className="roster-cards">{players.map((player) => <article className="roster-card" key={player.id}><span className="roster-card__ovr">{player.overall}</span><div><strong>{player.nome}</strong><span>{player.posizioni.join(' · ')} · {player.eta} anni</span><small>{player.club}</small></div><b>{(player.ingaggio / 1_000_000).toFixed(1)} M€</b></article>)}</div> : <p className="empty-state">Non hai ancora scelto giocatori.</p>}</section>
    </main>
  )
}
