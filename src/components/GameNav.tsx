import type { League } from '../types'

export type GameView = 'overview' | 'draft' | 'squad' | 'matches' | 'table'
type GameNavProps = { league: League; active: GameView; onNavigate?: (view: GameView) => void }

const items = [
  ['overview', '▦', 'Overview'],
  ['draft', '♜', 'Draft'],
  ['squad', '♙', 'La mia rosa'],
  ['matches', '◉', 'Partite'],
  ['table', '≡', 'Classifica'],
] as const

export function GameNav({ league, active, onNavigate }: GameNavProps) {
  return (
    <>
      <aside className="game-sidebar">
        <div className="game-sidebar__brand"><img src="/specialone-mark.svg" alt="" /><span>Special<span>One</span></span></div>
        <div className="game-sidebar__league"><small>LEGA ATTIVA</small><strong>{league.nome}</strong><span>{league.stato === 'draft' ? 'Draft in corso' : 'Preparazione'}</span></div>
        <nav aria-label="Navigazione lega">
          {items.map(([key, icon, label]) => <button className={`game-nav-item ${active === key ? 'is-active' : ''}`} key={key} type="button" onClick={() => onNavigate?.(key)}><i aria-hidden="true">{icon}</i><span>{label}</span>{key === active && <b />}</button>)}
        </nav>
        <div className="game-sidebar__footer"><span className="game-online-dot" /> Server online<span className="game-version">S1 · BETA</span></div>
      </aside>
      <>
        <div className="game-mobilebar"><div className="game-sidebar__brand"><img src="/specialone-mark.svg" alt="" /><span>Special<span>One</span></span></div><span className="game-mobilebar__league">{league.nome}</span></div>
        <nav className="game-mobile-nav" aria-label="Navigazione lega mobile">
          {items.slice(0, 3).map(([key, icon, label]) => <button className={active === key ? 'is-active' : ''} key={key} type="button" onClick={() => onNavigate?.(key)}><i aria-hidden="true">{icon}</i><span>{key === 'squad' ? 'Rosa' : label}</span></button>)}
        </nav>
      </>
    </>
  )
}
