import { useEffect, useState } from 'react'
import type { User } from '@supabase/supabase-js'
import { supabase } from '../lib/supabase'
import type { League, Membership } from '../types'
import { GameNav } from './GameNav'
import type { GameView } from './GameNav'

type DraftState = { pick_numero: number; club_corrente: string | null; stato: 'in_corso' | 'concluso' }
type DraftPlayer = { id: number; nome: string; overall: number; eta: number; posizioni: string[]; ingaggio: number; squadra_id: number | null; selezionabile: boolean; motivo: string | null }
type DraftPayload = { club: string; budget: number; reroll_rimasti: number; slot_occupati: number; pick_numero: number; giocatori: DraftPlayer[] }
type DraftProps = { user: User; membership: Membership; onNavigate: (view: GameView) => void }

export function Draft({ user, membership, onNavigate }: DraftProps) {
  const league = membership.league as League
  const [state, setState] = useState<DraftState | null>(null)
  const [payload, setPayload] = useState<DraftPayload | null>(null)
  const [loading, setLoading] = useState(true)
  const [pending, setPending] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [refresh, setRefresh] = useState(0)

  useEffect(() => {
    let active = true
    async function load() {
      setLoading(true); setError(null)
      const { data: teamState, error: stateError } = await supabase.from('draft_team_state').select('*').eq('team_id', membership.id).maybeSingle()
      if (!active) return
      if (stateError || !teamState) { setError(stateError?.message ?? 'Stato del tuo draft non disponibile.'); setLoading(false); return }
      const nextState = teamState as DraftState
      setState(nextState)
      if (nextState.club_corrente && nextState.stato === 'in_corso') {
        const result = await supabase.rpc('draft_spin', { p_league_id: league.id })
        if (!active) return
        if (result.error) setError(result.error.message)
        else setPayload(result.data as DraftPayload)
      } else setPayload(null)
      setLoading(false)
    }
    void load()
    return () => { active = false }
  }, [league.id, membership.id, refresh])

  async function action(name: 'draft_spin' | 'draft_reroll') {
    setPending(true); setError(null)
    const result = await supabase.rpc(name, { p_league_id: league.id })
    if (result.error) setError(result.error.message)
    else setPayload(result.data as DraftPayload)
    setPending(false)
  }

  async function pick(player: DraftPlayer) {
    setPending(true); setError(null)
    const result = await supabase.rpc('draft_pick', { p_league_id: league.id, p_player_id: player.id })
    if (result.error) setError(result.error.message)
    else { setPayload(null); setRefresh((value) => value + 1) }
    setPending(false)
  }

  if (loading) return <main className="loading-screen"><img className="loading-mark" src="/specialone-mark.svg" alt="" /><p>Preparo il draft…</p></main>
  if (error && !state) return <main className="fatal-state"><h1>Draft non disponibile</h1><p>{error}</p></main>

  const picks = state?.pick_numero ?? 0
  const total = league.slot_rosa
  return (
    <main className="app-shell draft-shell">
      <GameNav league={league} active="draft" onNavigate={onNavigate} />
      <header className="topbar"><div className="brand-lockup brand-lockup--dark"><img src="/specialone-mark.svg" alt="" /><span>SpecialOne</span></div><span className="user-email">{user.email}</span></header>
      <section className="draft-hero">
        <div><p className="kicker">Draft indipendente · {league.nome}</p><h1>{state?.stato === 'concluso' ? 'Rosa completa.' : 'Scegli bene.'}</h1><p>La tua squadra è al pick {Math.min(picks + 1, total)} su {total}. Le altre squadre possono draftare contemporaneamente.</p></div>
        <div className="draft-turn-board"><span>La tua squadra</span><strong>{membership.nome}</strong><small>{state?.stato === 'concluso' ? 'Draft completato' : `${picks} / ${total} giocatori`}</small></div>
      </section>
      {error && <p className="notice notice--error" role="alert">{error}</p>}
      {state?.stato !== 'concluso' && !payload && <section className="draft-action-panel"><p className="kicker">Il tuo prossimo giocatore</p><h2>Estrai un club.</h2><p>Non devi aspettare nessuno. Se due squadre scelgono lo stesso giocatore, vale il primo pick registrato.</p><button className="button button--primary" type="button" disabled={pending} onClick={() => action('draft_spin')}>SPIN</button></section>}
      {payload && state?.stato !== 'concluso' && <section className="draft-club-panel"><div className="section-heading-row"><div><p className="kicker">Club estratto</p><h2>{payload.club}</h2></div><button className="button button--secondary" type="button" disabled={pending || payload.reroll_rimasti < 1} onClick={() => action('draft_reroll')}>Reroll · {payload.reroll_rimasti}</button></div><p>Scegli subito. Un giocatore già preso resta visibile ma non è selezionabile.</p><div className="draft-player-list">{payload.giocatori.map((player) => <button className="draft-player" key={player.id} type="button" disabled={pending || !player.selezionabile} onClick={() => pick(player)}><span className="draft-player__ovr">{player.overall}</span><span><strong>{player.nome}</strong><small>{player.posizioni.join(' · ')} · {player.eta} anni</small></span><span className="draft-player__wage">{(player.ingaggio / 1_000_000).toFixed(1)} M€<small>{player.selezionabile ? 'Scegli' : player.motivo === 'gia_scelto' ? 'Già scelto' : 'Non sostenibile'}</small></span></button>)}</div></section>}
      {state?.stato === 'concluso' && <section className="draft-action-panel"><p className="kicker">Draft concluso</p><h2>La rosa è pronta.</h2><p>Il prossimo passaggio sarà la scelta della formazione.</p></section>}
      {state?.stato !== 'concluso' && !payload && <button className="text-button draft-refresh" type="button" onClick={() => setRefresh((value) => value + 1)}>Aggiorna stato</button>}
    </main>
  )
}
