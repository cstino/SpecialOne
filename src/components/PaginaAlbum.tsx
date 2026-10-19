import { useSeasonData } from '../lib/useSeasonData'
import type { League, Membership } from '../types'
import { Album } from './Album'
import { GameNav, type GameView } from './GameNav'
import { LoadingLogo } from './LoadingLogo'

// L'Album delle figurine come pagina a se', nel menu Altro (docs/decisioni-conferenze-stampa.md §BetOne).
export function PaginaAlbum({ membership, onNavigate }: { membership: Membership; onNavigate: (view: GameView) => void }) {
  const league = membership.league as League
  const dati = useSeasonData(membership)
  return <main className="app-shell season-shell bet-shell">
    <GameNav league={league} active="album" onNavigate={onNavigate} />
    <header className="topbar season-topbar"><div className="brand-lockup brand-lockup--dark"><img src="/specialone-mark.svg" alt="" /><span>SpecialOne</span></div><span>Album</span></header>
    <div className="season-page season-page--narrow bet-page alb-pagina-intera">
      <section className="bet-hero">
        <div className="bet-hero__testo">
          <p className="bet-kicker">{league.nome}</p>
          <h1>Al<b>bum</b></h1>
          <p className="bet-sottotitolo">Compra le bustine con i crediti vinti a BetOne e completa l'album della stagione: stemmi, giocatori e figurine ultrarare.</p>
        </div>
      </section>
      {dati.loading ? <section className="season-state is-caricamento"><LoadingLogo compatto /><h2>Apro l'album…</h2></section>
        : <Album leagueId={league.id} teamId={membership.id} dati={dati} conferenze={Boolean(league.conferenze_attive)} />}
    </div>
  </main>
}
