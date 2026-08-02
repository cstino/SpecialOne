import type { ReactNode } from 'react'
import { useNotificheContesto, useTornaAllaHome } from '../lib/navigazione'
import type { League } from '../types'
import { Notifiche } from './Notifiche'

export type GameView = 'overview' | 'draft' | 'squad' | 'team' | 'mercato' | 'matches' | 'table'
type GameNavProps = { league: League; active: GameView; onNavigate?: (view: GameView) => void }

// Icone disegnate a mano: i glifi Unicode di prima (▦ ♜ ♙ ◆ ◉ ≡) venivano resi dal
// font di sistema, quindi cambiavano forma su ogni dispositivo e non significavano nulla.
const ICONE: Record<string, ReactNode> = {
  overview: <><path d="M3 10.5 12 3l9 7.5" /><path d="M5.5 9.5V20h13V9.5" /></>,
  draft: <><path d="M12 3v7" /><path d="M8.5 6.5 12 3l3.5 3.5" /><circle cx="12" cy="15.5" r="5" /></>,
  squad: <><circle cx="12" cy="8" r="3.6" /><path d="M5 20c0-3.6 3.1-5.6 7-5.6s7 2 7 5.6" /></>,
  team: <><path d="M12 3 20 6v6.5c0 4.6-3.3 7.7-8 9-4.7-1.3-8-4.4-8-9V6z" /></>,
  matches: <><circle cx="12" cy="12" r="9" /><path d="m12 7 4.3 3.1-1.6 5h-5.4l-1.6-5z" /></>,
  table: <><path d="M5 20V11M12 20V4M19 20v-6" /></>,
  mercato: <><path d="M4 8.5h12m0 0-3-3m3 3-3 3" /><path d="M20 15.5H8m0 0 3-3m-3 3 3 3" /></>,
}

function Icona({ nome }: { nome: string }) {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true" focusable="false">
      {ICONE[nome]}
    </svg>
  )
}

const draftItems = [
  ['overview', 'Overview'],
  ['draft', 'Draft'],
  ['squad', 'La mia rosa'],
] as const

const seasonItems = [
  ['overview', 'Overview'],
  ['squad', 'Rosa'],
  ['team', 'Squadra'],
  ['mercato', 'Mercato'],
  ['matches', 'Partite'],
  ['table', 'Classifica'],
] as const

export function GameNav({ league, active, onNavigate }: GameNavProps) {
  // A campionato concluso il mercato non ha piu' senso: non ci sono giornate
  // su cui schierare chi si compra, e le RPC lo rifiuterebbero comunque.
  const items = league.stato === 'draft'
    ? draftItems
    : league.stato === 'conclusa'
      ? seasonItems.filter(([chiave]) => chiave !== 'mercato')
      : seasonItems
  const tornaAllaHome = useTornaAllaHome()
  const notifiche = useNotificheContesto()

  // Il marchio riporta all'elenco delle leghe: e' l'unica via d'uscita da una
  // lega in corso per chi ne ha piu' di una.
  const marchio = (chiave: string) => tornaAllaHome
    ? <button className="game-sidebar__brand game-sidebar__brand--azione" type="button" key={chiave} onClick={tornaAllaHome} title="Torna alle tue leghe" aria-label="Torna alle tue leghe"><img src="/specialone-mark.svg" alt="" /><span>Special<span>One</span></span></button>
    : <div className="game-sidebar__brand" key={chiave}><img src="/specialone-mark.svg" alt="" /><span>Special<span>One</span></span></div>

  return (
    <>
      <aside className="game-sidebar">
        {marchio('desktop')}
        <div className="game-sidebar__league"><small>LEGA ATTIVA</small><strong>{league.nome}</strong><span>{league.stato === 'draft' ? 'Draft in corso' : league.stato === 'conclusa' ? `Stagione ${league.stagione_corrente} conclusa` : `Stagione ${league.stagione_corrente} in corso`}</span>{notifiche && <Notifiche userId={notifiche.userId} onApriNotifica={notifiche.apri} />}</div>
        <nav aria-label="Navigazione lega">
          {items.map(([key, label]) => <button className={`game-nav-item ${active === key ? 'is-active' : ''}`} key={key} type="button" onClick={() => onNavigate?.(key)} aria-current={active === key ? 'page' : undefined}><i aria-hidden="true"><Icona nome={key} /></i><span>{label}</span>{key === active && <b />}</button>)}
        </nav>
        <div className="game-sidebar__footer"><span className="game-online-dot" /> Server online<span className="game-version">S1 · BETA</span></div>
      </aside>
      <>
        <div className="game-mobilebar">{marchio('mobile')}<span className="game-mobilebar__league">{league.nome}</span>{notifiche && <Notifiche userId={notifiche.userId} onApriNotifica={notifiche.apri} />}</div>
        <nav className="game-mobile-nav" aria-label="Navigazione lega mobile">
          {items.map(([key, label]) => <button className={active === key ? 'is-active' : ''} key={key} type="button" onClick={() => onNavigate?.(key)} aria-current={active === key ? 'page' : undefined}><i aria-hidden="true"><Icona nome={key} /></i><span>{key === 'squad' ? 'Rosa' : label}</span></button>)}
        </nav>
      </>
    </>
  )
}
