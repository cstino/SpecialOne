/*
THESIS: SpecialOne è una lavagna gara operativa, non un dashboard SaaS a card.
OWN-WORLD: carta da distinta, verde campo, inchiostro scuro, rosso arbitro; blocchi aperti e magneti-stemma.
STORY: l’utente accede, crea o raggiunge una lega, registra la squadra e vede subito chi manca.
FIRST VIEWPORT: su mobile domina il compito corrente; su desktop una grande fascia campo porta identità e stato.
FORM: direzione “lavagna gara”, settima opzione grounded; staging registration console, seed 459346e4.
*/
import { useCallback, useEffect, useMemo, useRef, useState, type ReactNode } from 'react'
import type { Session } from '@supabase/supabase-js'
import { Admin } from './components/Admin'
import { AlboDOro } from './components/AlboDOro'
import { Avvisi } from './components/Avvisi'
import { AuthScreen } from './components/AuthScreen'
import { Draft } from './components/Draft'
import { Finanza } from './components/Finanza'
import { Formazione } from './components/Formazione'
import { Help } from './components/Help'
import { Rosa } from './components/Rosa'
import { Matches } from './components/Matches'
import { MatchDetail } from './components/MatchDetail'
import { MatchReveal } from './components/MatchReveal'
import { Mercato } from './components/Mercato'
import { Offseason } from './components/Offseason'
import { SeasonOverview } from './components/SeasonOverview'
import { Standings } from './components/Standings'
import { TeamProfile } from './components/TeamProfile'
import type { GameView } from './components/GameNav'
import { Lobby } from './components/Lobby'
import { LoadingLogo } from './components/LoadingLogo'
import { MenuIniziale } from './components/MenuIniziale'
import { Onboarding } from './components/Onboarding'
import { ContestoHome, ContestoNotifiche } from './lib/navigazione'
import { useNotifiche, type Notifica } from './lib/notifiche'
import { configurationError, supabase } from './lib/supabase'
import { useSwipeIndietro } from './lib/swipeIndietro'
import type { League, Membership, RpcResult, Team } from './types'

// Istantanea di "dove sono" nell'app: viene spinta nella cronologia del
// browser a ogni cambio, cosi' il tasto/gesto indietro nativo (e lo swipe dal
// bordo, per chi usa l'app installata sulla home senza barra del browser)
// riporta esattamente alla schermata precedente invece di non fare nulla.
type IstantaneaNavigazione = {
  nelMenu: boolean
  showOnboarding: boolean
  modoOnboarding: 'choose' | 'create' | 'join'
  activeLeagueId: number | null
  gameView: GameView
  openMatch: { id: number; from: GameView } | null
  viewedTeamId: number | null
}

export default function App() {
  const [session, setSession] = useState<Session | null>(null)
  const [authLoading, setAuthLoading] = useState(true)
  const [memberships, setMemberships] = useState<Membership[]>([])
  const [dataLoading, setDataLoading] = useState(false)
  const [activeLeagueId, setActiveLeagueId] = useState<number | null>(null)
  const [showOnboarding, setShowOnboarding] = useState(false)
  const [gameView, setGameView] = useState<GameView>('overview')
  const [openMatch, setOpenMatch] = useState<{ id: number; from: GameView } | null>(null)
  const [revealMatch, setRevealMatch] = useState<{ id: number; from: GameView } | null>(null)
  const [partiteViste, setPartiteViste] = useState<Set<number>>(new Set())
  const [viewedTeamId, setViewedTeamId] = useState<number | null>(null)
  // Si atterra sempre nel menu iniziale: da li' si sceglie in quale lega
  // entrare, o se crearne una. Entrare d'ufficio nell'ultima lega toglieva
  // all'utente la scelta, e con piu' leghe era anche la scelta sbagliata.
  const [nelMenu, setNelMenu] = useState(true)
  const [modoOnboarding, setModoOnboarding] = useState<'choose' | 'create' | 'join'>('choose')
  const [error, setError] = useState<string | null>(null)
  const centroNotifiche = useNotifiche(session?.user.id)

  const apriMenu = useCallback(() => setNelMenu(true), [])

  // Ogni cambio di schermata diventa una voce della cronologia del browser:
  // e' quello che permette al gesto di swipe (e al back nativo Android) di
  // tornare esattamente alla schermata precedente, non solo alla home.
  const primaVoltaStorico = useRef(true)
  const ripristinoStoricoInCorso = useRef(false)
  useEffect(() => {
    const istantanea: IstantaneaNavigazione = { nelMenu, showOnboarding, modoOnboarding, activeLeagueId, gameView, openMatch, viewedTeamId }
    if (primaVoltaStorico.current) {
      primaVoltaStorico.current = false
      window.history.replaceState({ indice: 0, istantanea }, '')
      return
    }
    if (ripristinoStoricoInCorso.current) {
      ripristinoStoricoInCorso.current = false
      return
    }
    const indicePrecedente = (window.history.state as { indice?: number } | null)?.indice ?? 0
    window.history.pushState({ indice: indicePrecedente + 1, istantanea }, '')
  }, [nelMenu, showOnboarding, modoOnboarding, activeLeagueId, gameView, openMatch, viewedTeamId])

  useEffect(() => {
    function alPopstate(evento: PopStateEvent) {
      const istantanea = (evento.state as { istantanea?: IstantaneaNavigazione } | null)?.istantanea
      if (!istantanea) return
      ripristinoStoricoInCorso.current = true
      setNelMenu(istantanea.nelMenu)
      setShowOnboarding(istantanea.showOnboarding)
      setModoOnboarding(istantanea.modoOnboarding)
      setActiveLeagueId(istantanea.activeLeagueId)
      setGameView(istantanea.gameView)
      setOpenMatch(istantanea.openMatch)
      setViewedTeamId(istantanea.viewedTeamId)
    }
    window.addEventListener('popstate', alPopstate)
    return () => window.removeEventListener('popstate', alPopstate)
  }, [])

  // Nulla da fare se siamo gia' alla schermata piu' esterna: evita che lo
  // swipe richiami history.back() a vuoto e finisca per uscire dalla PWA.
  const tornaIndietroConGesto = useCallback(() => {
    const indice = (window.history.state as { indice?: number } | null)?.indice ?? 0
    if (indice <= 0) return
    window.history.back()
  }, [])
  useSwipeIndietro(tornaIndietroConGesto)

  // Toccare una notifica deve portare dove e' successa la cosa, non sulla
  // home: e' la differenza fra un avviso e un collegamento.
  const apriNotifica = useCallback((notifica: Notifica) => {
    const legaId = notifica.league_id
    if (legaId == null) return
    setActiveLeagueId(legaId)
    setNelMenu(false)
    setViewedTeamId(null)
    setGameView(notifica.dati?.view === 'squad' ? 'squad' : 'overview')
    const partita = notifica.dati?.match_id
    setOpenMatch(typeof partita === 'number' ? { id: partita, from: 'overview' } : null)
  }, [])

  const contestoNotifiche = useMemo(
    () => session?.user ? { userId: session.user.id, ...centroNotifiche, apri: apriNotifica } : null,
    [session, centroNotifiche, apriNotifica],
  )

  // Un tocco su una notifica push (public/sw.js) arriva qui come messaggio,
  // non come cambio di URL: la app era gia' aperta (o appena aperta sulla
  // home) e il service worker le passa dove andare. Stessa destinazione di
  // una notifica aperta dalla campanella in-app.
  useEffect(() => {
    if (!('serviceWorker' in navigator)) return
    function alMessaggio(evento: MessageEvent) {
      if (evento.data?.tipo !== 'notifica-push-click') return
      const dati = (evento.data.dati ?? {}) as Record<string, unknown>
      apriNotifica({
        id: Number(dati.notification_id) || 0,
        league_id: typeof dati.league_id === 'number' ? dati.league_id : null,
        tipo: 'sistema',
        titolo: '',
        corpo: null,
        dati,
        letta_il: null,
        creata_il: new Date().toISOString(),
      })
    }
    navigator.serviceWorker.addEventListener('message', alMessaggio)
    return () => navigator.serviceWorker.removeEventListener('message', alMessaggio)
  }, [apriNotifica])

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

  useEffect(() => {
    if (!session) { setPartiteViste(new Set()); return }
    let attivo = true
    async function caricaPartiteViste() {
      const { data } = await supabase.from('match_reveals').select('match_id')
      if (attivo) setPartiteViste(new Set((data ?? []).map((riga) => riga.match_id as number)))
    }
    void caricaPartiteViste()
    return () => { attivo = false }
  }, [session])

  const segnaPartitaVista = useCallback(async (matchId: number) => {
    // La UI passa subito allo stato "visto"; il database lo rende poi
    // persistente tra refresh e dispositivi appena la migrazione e' attiva.
    setPartiteViste((precedenti) => new Set(precedenti).add(matchId))
    if (!session) return
    const { error: revealError } = await supabase.from('match_reveals').upsert(
      { user_id: session.user.id, match_id: matchId },
      { onConflict: 'user_id,match_id', ignoreDuplicates: true },
    )
    if (revealError) console.warn('Impossibile salvare il reveal della partita:', revealError.message)
  }, [session])

  async function completed(result: RpcResult) {
    setActiveLeagueId(result.league_id)
    setShowOnboarding(false)
    setModoOnboarding('choose')
    setNelMenu(false)
    await loadMemberships()
  }

  if (configurationError) {
    return <main className="fatal-state"><img src="/specialone-mark.svg" alt="" /><h1>Configurazione incompleta</h1><p>{configurationError}</p></main>
  }
  if (authLoading) return <main className="loading-screen"><LoadingLogo /><p>Ingresso in campo…</p></main>
  if (!session) return <AuthScreen />
  if (dataLoading && memberships.length === 0) return <main className="loading-screen"><LoadingLogo /><p>Preparo la distinta…</p></main>
  if (error) return <main className="fatal-state"><h1>Qualcosa non torna</h1><p>{error}</p><button className="button button--primary" type="button" onClick={() => loadMemberships()}>Riprova</button></main>
  if (showOnboarding || memberships.length === 0) {
    return <Onboarding
      user={session.user}
      onComplete={completed}
      onCancel={memberships.length ? () => { setShowOnboarding(false); setModoOnboarding('choose') } : undefined}
      modoIniziale={modoOnboarding}
    />
  }

  const active = memberships.find((item) => item.league_id === activeLeagueId) ?? memberships[0]

  function selezionaLega(leagueId: number) {
    setActiveLeagueId(leagueId)
    setNelMenu(false)
    const selected = memberships.find(item => item.league_id === leagueId)
    setGameView(selected?.league?.stato === 'conclusa' || selected?.league?.fase_carriera === 'offseason' ? 'offseason' : 'overview')
    setOpenMatch(null)
    setViewedTeamId(null)
  }

  function apriOnboarding(modo: 'choose' | 'create' | 'join') {
    setModoOnboarding(modo)
    setShowOnboarding(true)
  }

  // I due contesti viaggiano sempre insieme e servono a ogni schermata di
  // lega: annidarli a mano in ognuna moltiplicherebbe solo il rumore.
  const conContesti = (nodo: ReactNode) => (
    <ContestoHome.Provider value={apriMenu}>
      <ContestoNotifiche.Provider value={contestoNotifiche}>{nodo}</ContestoNotifiche.Provider>
    </ContestoHome.Provider>
  )

  // Menu iniziale: e' la schermata di atterraggio dopo il login, e ci si torna
  // dal marchio in alto a sinistra. La Lobby resta la sala d'attesa della
  // singola lega prima del draft, non la schermata di casa.
  if (nelMenu) {
    return (
      <MenuIniziale
        user={session.user}
        memberships={memberships}
        onEntraNellaLega={selezionaLega}
        onCreaLega={() => apriOnboarding('create')}
        onEntraConCodice={() => apriOnboarding('join')}
        onRefresh={loadMemberships}
        onApriNotifica={apriNotifica}
      />
    )
  }

  // Una lega conclusa va alle schermate di stagione, non allo spogliatoio:
  // il campionato e' finito, ma classifica, partite e rose restano da
  // guardare. Prima finiva nel ramo della Lobby, che e' scritta per il
  // PRIMA del draft e diceva «la lega partira' quando l'admin avra'
  // completato i posti» a un campionato gia' giocato per intero.
  const legaGiocabile = active.league?.stato === 'stagione' || active.league?.stato === 'conclusa'
  if (active.league?.stato !== 'draft' && !legaGiocabile) {
    return conContesti(
      <Lobby
        user={session.user}
        membership={active}
        memberships={memberships}
        onSelectLeague={selezionaLega}
        onNewLeague={apriMenu}
        onRefresh={loadMemberships}
      />,
    )
  }

  if (active.league?.stato === 'draft') {
    if (gameView === 'squad') return conContesti(<Rosa membership={active} onNavigate={setGameView} />)
    if (gameView === 'admin') return conContesti(<Admin membership={active} onNavigate={setGameView} />)
    if (gameView === 'help') return conContesti(<Help membership={active} onNavigate={setGameView} />)
    return conContesti(<Draft user={session.user} membership={active} onNavigate={setGameView} onRefresh={loadMemberships} />)
  }

  if (gameView === 'offseason') {
    return conContesti(<Offseason user={session.user} membership={active} onNavigate={setGameView} onOpenTeam={openTeam} onRefresh={loadMemberships} />)
  }

  if (active.league?.fase_carriera === 'offseason' && gameView === 'draft') {
    return conContesti(<Draft user={session.user} membership={active} onNavigate={setGameView} onRefresh={loadMemberships} />)
  }

  function navigateGame(view: GameView) {
    setOpenMatch(null)
    setRevealMatch(null)
    setViewedTeamId(null)
    setGameView(view)
  }
  function openTeam(teamId: number) {
    setOpenMatch(null)
    setRevealMatch(null)
    setViewedTeamId(teamId)
    setGameView('team')
  }
  const schermata = openMatch
      ? <MatchDetail membership={active} matchId={openMatch.id} onBack={() => { setOpenMatch(null); setGameView(openMatch.from) }} onNavigate={navigateGame} onOpenTeam={openTeam} />
      : gameView === 'squad' ? <Formazione membership={active} onNavigate={navigateGame} />
      : gameView === 'team' ? <TeamProfile membership={active} teamId={viewedTeamId ?? active.id} onNavigate={navigateGame} onOpenMatch={(id) => setOpenMatch({ id, from: 'team' })} onTeamUpdated={loadMemberships} />
      : gameView === 'mercato' ? <Mercato membership={active} onNavigate={navigateGame} />
      : gameView === 'matches' ? <Matches membership={active} onNavigate={navigateGame} revealedMatchIds={partiteViste} onOpenMatch={(id) => setOpenMatch({ id, from: 'matches' })} onRevealMatch={(id) => setRevealMatch({ id, from: 'matches' })} onOpenTeam={openTeam} />
      : gameView === 'table' ? <Standings membership={active} onNavigate={navigateGame} onOpenTeam={openTeam} />
      : gameView === 'honors' ? <AlboDOro membership={active} onNavigate={navigateGame} />
      : gameView === 'notifications' ? <Avvisi membership={active} onNavigate={navigateGame} />
      : gameView === 'admin' ? <Admin membership={active} onNavigate={navigateGame} />
      : gameView === 'help' ? <Help membership={active} onNavigate={navigateGame} />
      : gameView === 'finanza' ? <Finanza membership={active} onNavigate={navigateGame} />
      : <SeasonOverview membership={active} onNavigate={navigateGame} revealedMatchIds={partiteViste} onOpenMatch={(id) => setOpenMatch({ id, from: 'overview' })} onRevealMatch={(id) => setRevealMatch({ id, from: 'overview' })} onOpenTeam={openTeam} />
  return conContesti(<>
    {schermata}
    {revealMatch && <MatchReveal membership={active} matchId={revealMatch.id} onClose={() => { void segnaPartitaVista(revealMatch.id); setRevealMatch(null) }} onRevealed={segnaPartitaVista} onOpenReport={() => { void segnaPartitaVista(revealMatch.id); setOpenMatch(revealMatch); setRevealMatch(null) }} />}
  </>)
}
