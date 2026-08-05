import { useEffect, useState, type ReactNode } from 'react'
import { useNotificheContesto, useTornaAllaHome } from '../lib/navigazione'
import type { League } from '../types'

export type GameView = 'overview' | 'offseason' | 'draft' | 'squad' | 'team' | 'mercato' | 'matches' | 'table' | 'honors' | 'notifications' | 'admin'
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
  honors: <><path d="M8 4h8v4.5a4 4 0 0 1-8 0z" /><path d="M8 6H5.5v1.5A3 3 0 0 0 8.5 10M16 6h2.5v1.5a3 3 0 0 1-3 2.5M12 12.5V17M8.5 21h7M9.5 17h5" /></>,
  notifications: <><path d="M18 9a6 6 0 1 0-12 0c0 4.5-1.5 5.6-2 6.5h16c-.5-.9-2-2-2-6.5" /><path d="M10 19a2.2 2.2 0 0 0 4 0" /></>,
  mercato: <><path d="M4 8.5h12m0 0-3-3m3 3-3 3" /><path d="M20 15.5H8m0 0 3-3m-3 3 3 3" /></>,
  offseason: <><path d="M4 7h16M6 3v4m12-4v4" /><path d="M5 11h14v9H5z" /><path d="m9 15 2 2 4-4" /></>,
  admin: <><path d="M12 3.5 5 6.5v5c0 4.5 3 7.2 7 9 4-1.8 7-4.5 7-9v-5z" /><path d="m9.2 12 1.9 1.9 3.7-3.9" /></>,
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
  ['honors', "Albo d'oro"],
  ['notifications', 'Avvisi'],
] as const

const seasonItems = [
  ['overview', 'Overview'],
  ['squad', 'Rosa'],
  ['team', 'Squadra'],
  ['mercato', 'Mercato'],
  ['matches', 'Partite'],
  ['table', 'Classifica'],
  ['honors', "Albo d'oro"],
  ['notifications', 'Avvisi'],
] as const

const offseasonItems = [
  ['offseason', 'Off-season'],
  ['team', 'Squadra'],
  ['mercato', 'Mercato'],
  ['matches', 'Partite'],
  ['table', 'Classifica'],
  ['honors', "Albo d'oro"],
  ['notifications', 'Avvisi'],
] as const

const concludedItems = [
  ['offseason', 'Off-season'],
  ['overview', 'Overview'],
  ['team', 'Squadra'],
  ['matches', 'Partite'],
  ['table', 'Classifica'],
  ['honors', "Albo d'oro"],
  ['notifications', 'Avvisi'],
] as const

export function GameNav({ league, active, onNavigate }: GameNavProps) {
  // A campionato concluso il mercato non ha piu' senso: non ci sono giornate
  // su cui schierare chi si compra, e le RPC lo rifiuterebbero comunque.
  const tornaAllaHome = useTornaAllaHome()
  const notifiche = useNotificheContesto()
  const baseItems = league.fase_carriera === 'offseason'
    ? offseasonItems
    : league.stato === 'draft'
    ? draftItems
    : league.stato === 'conclusa'
      ? concludedItems
      : seasonItems
  // Pannello admin: prima solo a stagione avviata (le tre azioni di
  // fallback su cron servono solo li'), ma "Elimina lega" ha senso in
  // qualunque fase — anche in draft, dove capita che una lega resti
  // bloccata e vada rifatta da capo. La voce di menu compare quindi sempre
  // per l'admin tranne in off-season, che ha gia' un pannello dedicato;
  // e' Admin.tsx a mostrare solo le azioni sensate per lo stato corrente.
  const eAdmin = league.admin_id === notifiche?.userId
  const items = eAdmin && league.fase_carriera !== 'offseason'
    ? [...baseItems, ['admin', 'Admin'] as const]
    : baseItems
  const [menuMobileAperto, setMenuMobileAperto] = useState(false)

  useEffect(() => {
    if (!menuMobileAperto) return
    const overflowPrecedente = document.body.style.overflow
    document.body.style.overflow = 'hidden'
    const chiudiConEscape = (evento: KeyboardEvent) => {
      if (evento.key === 'Escape') setMenuMobileAperto(false)
    }
    document.addEventListener('keydown', chiudiConEscape)
    return () => {
      document.body.style.overflow = overflowPrecedente
      document.removeEventListener('keydown', chiudiConEscape)
    }
  }, [menuMobileAperto])

  function vai(view: GameView) {
    setMenuMobileAperto(false)
    onNavigate?.(view)
  }

  // Il marchio riporta all'elenco delle leghe: e' l'unica via d'uscita da una
  // lega in corso per chi ne ha piu' di una.
  const marchio = (chiave: string) => tornaAllaHome
    ? <button className="game-sidebar__brand game-sidebar__brand--azione" type="button" key={chiave} onClick={tornaAllaHome} title="Torna alle tue leghe" aria-label="Torna alle tue leghe"><img src="/specialone-mark.svg" alt="" /><span>Special<span>One</span></span></button>
    : <div className="game-sidebar__brand" key={chiave}><img src="/specialone-mark.svg" alt="" /><span>Special<span>One</span></span></div>

  return (
    <>
      <aside className="game-sidebar">
        {marchio('desktop')}
        <div className="game-sidebar__league"><small>LEGA ATTIVA</small><strong>{league.nome}</strong><span>{league.fase_carriera === 'offseason' ? `Off-season · verso la S${league.stagione_corrente + 1}` : league.stato === 'draft' ? 'Draft in corso' : league.stato === 'conclusa' ? `Stagione ${league.stagione_corrente} conclusa` : `Stagione ${league.stagione_corrente} in corso`}</span></div>
        <nav aria-label="Navigazione lega">
          {items.map(([key, label]) => <button className={`game-nav-item ${active === key ? 'is-active' : ''}`} key={key} type="button" onClick={() => vai(key)} aria-current={active === key ? 'page' : undefined}><i aria-hidden="true"><Icona nome={key} /></i><span>{label}</span>{key === 'notifications' && notifiche && notifiche.nonLette > 0 && <em className="game-nav-item__badge">{notifiche.nonLette > 9 ? '9+' : notifiche.nonLette}</em>}{key === active && <b />}</button>)}
        </nav>
        <div className="game-sidebar__footer"><span className="game-online-dot" /> Server online<span className="game-version">S1 · BETA</span></div>
      </aside>
      <div className="game-mobilebar">
        {marchio('mobile')}
        <span className="game-mobilebar__league">{league.nome}</span>
        <button className="game-mobilebar__menu" type="button" onClick={() => setMenuMobileAperto(true)} aria-label="Apri menu" aria-expanded={menuMobileAperto}>
          <span /><span /><span />
        </button>
      </div>
      {menuMobileAperto && <div className="game-drawer-layer" role="presentation" onMouseDown={(evento) => { if (evento.target === evento.currentTarget) setMenuMobileAperto(false) }}>
        <aside className="game-drawer" role="dialog" aria-modal="true" aria-label="Menu della lega">
          <header className="game-drawer__header">
            <div><img src="/specialone-mark.svg" alt="" /><span><strong>{league.nome}</strong><small>Stagione {league.stagione_corrente}</small></span></div>
            <button type="button" onClick={() => setMenuMobileAperto(false)} aria-label="Chiudi menu">×</button>
          </header>
          <nav className="game-drawer__nav" aria-label="Navigazione lega mobile">
            {items.map(([key, label]) => <button className={`game-nav-item ${active === key ? 'is-active' : ''}`} key={key} type="button" onClick={() => vai(key)} aria-current={active === key ? 'page' : undefined}><i aria-hidden="true"><Icona nome={key} /></i><span>{key === 'squad' ? 'Rosa' : label}</span>{key === 'notifications' && notifiche && notifiche.nonLette > 0 && <em className="game-nav-item__badge">{notifiche.nonLette > 9 ? '9+' : notifiche.nonLette}</em>}{key === active && <b />}</button>)}
          </nav>
          {tornaAllaHome && <button className="game-drawer__home" type="button" onClick={() => { setMenuMobileAperto(false); tornaAllaHome() }}>Torna alle mie leghe <span>→</span></button>}
          <footer><span className="game-online-dot" /> Server online <small>S1 · BETA</small></footer>
        </aside>
      </div>}
    </>
  )
}
