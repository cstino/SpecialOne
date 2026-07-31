/*
THESIS: SpecialOne è una lavagna gara operativa, non un dashboard SaaS a card.
OWN-WORLD: carta da distinta, verde campo, inchiostro scuro, rosso arbitro; blocchi aperti e magneti-stemma.
STORY: l’utente accede, crea o raggiunge una lega, registra la squadra e vede subito chi manca.
FIRST VIEWPORT: su mobile domina il compito corrente; su desktop una grande fascia campo porta identità e stato.
FORM: direzione “lavagna gara”, settima opzione grounded; staging registration console, seed 459346e4.
*/
import { useCallback, useEffect, useState } from 'react'
import type { Session } from '@supabase/supabase-js'
import { AuthScreen } from './components/AuthScreen'
import { Draft } from './components/Draft'
import { Formazione } from './components/Formazione'
import { Rosa } from './components/Rosa'
import type { GameView } from './components/GameNav'
import { Lobby } from './components/Lobby'
import { Onboarding } from './components/Onboarding'
import { configurationError, supabase } from './lib/supabase'
import type { League, Membership, RpcResult, Team } from './types'

export default function App() {
  const [session, setSession] = useState<Session | null>(null)
  const [authLoading, setAuthLoading] = useState(true)
  const [memberships, setMemberships] = useState<Membership[]>([])
  const [dataLoading, setDataLoading] = useState(false)
  const [activeLeagueId, setActiveLeagueId] = useState<number | null>(null)
  const [showOnboarding, setShowOnboarding] = useState(false)
  const [gameView, setGameView] = useState<GameView>('overview')
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => {
      setSession(data.session)
      setAuthLoading(false)
    })
    const { data: listener } = supabase.auth.onAuthStateChange((_event, nextSession) => {
      setSession(nextSession)
      setAuthLoading(false)
      if (!nextSession) {
        setMemberships([])
        setActiveLeagueId(null)
      }
    })
    return () => listener.subscription.unsubscribe()
  }, [])

  const loadMemberships = useCallback(async () => {
    if (!session?.user) return
    setDataLoading(true)
    setError(null)
    const { data: teamData, error: teamError } = await supabase
      .from('teams')
      .select('*')
      .eq('user_id', session.user.id)
      .order('creata_il', { ascending: false })

    if (teamError) {
      setError(teamError.message)
      setDataLoading(false)
      return
    }

    const teams = (teamData ?? []) as Team[]
    if (teams.length === 0) {
      setMemberships([])
      setDataLoading(false)
      return
    }

    const { data: leagueData, error: leagueError } = await supabase
      .from('leagues')
      .select('*')
      .in('id', teams.map((team) => team.league_id))

    if (leagueError) {
      setError(leagueError.message)
      setDataLoading(false)
      return
    }

    const leagues = (leagueData ?? []) as League[]
    const joined = teams.map((team) => ({
      ...team,
      league: leagues.find((league) => league.id === team.league_id),
    })).filter((item) => item.league) as Membership[]
    setMemberships(joined)
    setActiveLeagueId((current) => current && joined.some((item) => item.league_id === current) ? current : joined[0]?.league_id ?? null)
    setDataLoading(false)
  }, [session])

  useEffect(() => { void loadMemberships() }, [loadMemberships])

  async function completed(result: RpcResult) {
    setActiveLeagueId(result.league_id)
    setShowOnboarding(false)
    await loadMemberships()
  }

  if (configurationError) {
    return <main className="fatal-state"><img src="/specialone-mark.svg" alt="" /><h1>Configurazione incompleta</h1><p>{configurationError}</p></main>
  }
  if (authLoading) return <main className="loading-screen"><span className="loading-mark">S1</span><p>Ingresso in campo…</p></main>
  if (!session) return <AuthScreen />
  if (dataLoading && memberships.length === 0) return <main className="loading-screen"><span className="loading-mark">S1</span><p>Preparo la distinta…</p></main>
  if (error) return <main className="fatal-state"><h1>Qualcosa non torna</h1><p>{error}</p><button className="button button--primary" type="button" onClick={() => loadMemberships()}>Riprova</button></main>
  if (showOnboarding || memberships.length === 0) {
    return <Onboarding user={session.user} onComplete={completed} onCancel={memberships.length ? () => setShowOnboarding(false) : undefined} />
  }

  const active = memberships.find((item) => item.league_id === activeLeagueId) ?? memberships[0]
  if (active.league?.stato === 'draft') {
    if (gameView === 'squad') return <Rosa membership={active} onNavigate={setGameView} />
    return <Draft user={session.user} membership={active} onNavigate={setGameView} />
  }
  if (active.league?.stato === 'stagione') {
    if (gameView === 'squad') return <Rosa membership={active} onNavigate={setGameView} />
    return <Formazione membership={active} onNavigate={setGameView} />
  }
  return (
    <Lobby
      user={session.user}
      membership={active}
      memberships={memberships}
      onSelectLeague={setActiveLeagueId}
      onNewLeague={() => setShowOnboarding(true)}
      onRefresh={loadMemberships}
    />
  )
}
