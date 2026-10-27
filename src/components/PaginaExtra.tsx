import { useEffect } from 'react'
import { useNotificheContesto } from '../lib/navigazione'
import type { League, Membership } from '../types'
import { GameNav, type GameView } from './GameNav'
import { RichiesteGiocatori } from './RichiesteGiocatori'
import { SalaStampa } from './SalaStampa'

// Le pagine "Sala stampa" e "Spogliatoio" (menu Extra campo). Prima stavano nella home, che con le
// novita' era diventata troppo piena (richiesta del committente, 17 ottobre 2026).

type Props = { membership: Membership; onNavigate: (view: GameView) => void }

// Aprire la pagina equivale a guardare gli avvisi che portano qui: il pallino sulla voce di menu si spegne.
function useSegnaLette(view: 'salastampa' | 'spogliatoio', leagueId: number) {
  const centro = useNotificheContesto()
  useEffect(() => {
    const daSegnare = (centro?.notifiche ?? []).filter((n) => !n.letta_il && n.dati?.view === view && (n.league_id === leagueId || n.league_id === null)).map((n) => n.id)
    if (centro && daSegnare.length) void centro.segnaLette(daSegnare)
  }, [centro, view, leagueId])
}

function Vuota({ titolo, testo }: { titolo: string; testo: string }) {
  return <section className="alerts-empty"><span aria-hidden="true">◎</span><h2>{titolo}</h2><p>{testo}</p></section>
}

export function PaginaSalaStampa({ membership, onNavigate, revealedMatchIds }: Props & { revealedMatchIds: Set<number> }) {
  const league = membership.league as League
  useSegnaLette('salastampa', league.id)
  return <main className="app-shell season-shell alerts-shell">
    <GameNav league={league} active="salastampa" onNavigate={onNavigate} />
    <header className="topbar season-topbar"><div className="brand-lockup brand-lockup--dark"><img src="/specialone-mark.svg" alt="" /><span>SpecialOne</span></div><span>Sala stampa</span></header>
    <div className="season-page season-page--narrow alerts-page">
      <section className="alerts-heading">
        <div><p className="kicker">{league.nome}</p><h1>Sala stampa.</h1>
          <p>Dopo ogni partita i giornalisti ti fanno una domanda: le tue risposte muovono il morale della rosa, l'umore del pubblico e le rivalità. Le domande compaiono dopo che hai guardato la partita. Nelle risposte puoi nominare qualsiasi squadra della lega: attaccarla fa salire la rivalità con lei, elogiarla la fa scendere.</p></div>
      </section>
      <SalaStampa teamId={membership.id} revealedMatchIds={revealedMatchIds} senzaTitolo
        quandoVuota={<Vuota titolo="Nessuna domanda per ora." testo="Dopo la prossima partita i giornalisti ti aspettano in sala stampa." />} />
    </div>
  </main>
}

export function PaginaSpogliatoio({ membership, onNavigate }: Props) {
  const league = membership.league as League
  useSegnaLette('spogliatoio', league.id)
  return <main className="app-shell season-shell alerts-shell">
    <GameNav league={league} active="spogliatoio" onNavigate={onNavigate} />
    <header className="topbar season-topbar"><div className="brand-lockup brand-lockup--dark"><img src="/specialone-mark.svg" alt="" /><span>SpecialOne</span></div><span>Spogliatoio</span></header>
    <div className="season-page season-page--narrow alerts-page">
      <section className="alerts-heading">
        <div><p className="kicker">{league.nome}</p><h1>Spogliatoio.</h1>
          <p>Ogni tanto un giocatore ti scrive con una richiesta: giocare titolare, avere più minuti, riposare. Rispondi come vuoi, ma se prometti qualcosa a fine partita si controlla.</p></div>
      </section>
      <RichiesteGiocatori teamId={membership.id} senzaTitolo
        quandoVuota={<Vuota titolo="Nessuna richiesta aperta." testo="Quando un giocatore avrà qualcosa da chiederti, te lo dirà con una notifica." />} />
    </div>
  </main>
}
