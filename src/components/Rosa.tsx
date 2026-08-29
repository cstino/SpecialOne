import { useEffect, useState } from 'react'
import type { League, Membership } from '../types'
import { supabase } from '../lib/supabase'
import { GameNav, type GameView } from './GameNav'
import { firmaFoto, RosaElenco, type RosterPlayer } from './RosaElenco'

type RosaProps = { membership: Membership; onNavigate: (view: GameView) => void }

export function Rosa({ membership, onNavigate }: RosaProps) {
  const league = membership.league as League
  const [players, setPlayers] = useState<RosterPlayer[]>([])
  const [foto, setFoto] = useState<Map<number, string>>(new Map())
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
      const elenco = (instances ?? []).map((item) => ({ ...byId.get(item.player_id), id: item.id, ingaggio: item.ingaggio, overall: item.overall_corrente, eta: item.eta_corrente })) as RosterPlayer[]
      setPlayers(elenco)

      // Stesse firme del modale del draft: senza, la rosa qui resterebbe
      // sempre con gli iniziali al posto delle foto (debito noto, risolto).
      const voci = await Promise.all(elenco.map(async (g) => [g.id, await firmaFoto(g.foto_url)] as const))
      if (active) setFoto(new Map(voci.filter((v): v is [number, string] => Boolean(v[1]))))
      if (active) setLoading(false)
    }
    void load()
    return () => { active = false }
  }, [league.id, membership.id])

  const wage = players.reduce((sum, player) => sum + player.ingaggio, 0)
  const progress = `${players.length} / ${league.slot_rosa}`
  return (
    <main className="app-shell season-shell">
      <GameNav league={league} active="squad" onNavigate={onNavigate} />
      <header className="topbar season-topbar"><div className="brand-lockup brand-lockup--dark"><img src="/specialone-mark.svg" alt="" /><span>SpecialOne</span></div><span>La tua rosa</span></header>
      <section className="roster-hero"><div><p className="kicker">Squadra · {membership.nome}</p><h1>La mia rosa.</h1><p>Qui puoi controllare le scelte già fatte senza interrompere il draft.</p></div><div className="roster-summary"><span>Completamento</span><strong>{progress}</strong><small>{(wage / 1_000_000).toFixed(1)} M€ di ingaggi</small></div></section>
      {error && <p className="notice notice--error" role="alert">{error}</p>}
      {/* Stessa lista raggruppata per reparto del modale nel draft: era l'unica
          richiesta esplicita, prima erano due marcature diverse che divergevano. */}
      <section className="roster-panel"><div className="section-heading-row"><div><p className="kicker">Giocatori selezionati</p><h2>{players.length} su {league.slot_rosa}</h2></div><button className="button button--primary" type="button" onClick={() => onNavigate('draft')}>Torna al draft</button></div><RosaElenco giocatori={players} foto={foto} loading={loading} /></section>
    </main>
  )
}
