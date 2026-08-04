import { useEffect } from 'react'
import { useNotificheContesto } from '../lib/navigazione'
import { quandoRelativo } from '../lib/notifiche'
import type { League, Membership } from '../types'
import { GameNav, type GameView } from './GameNav'
import { IconaNotifica } from './Notifiche'

type Props = { membership: Membership; onNavigate: (view: GameView) => void }

export function Avvisi({ membership, onNavigate }: Props) {
  const league = membership.league as League
  const centro = useNotificheContesto()

  // Come nel vecchio pannello, entrare nel centro avvisi equivale a guardarli.
  // L'azione e' esplicita nel layout, ma il badge si spegne senza un secondo tap.
  useEffect(() => {
    if (centro && centro.nonLette > 0) void centro.segnaLette()
  }, [centro])

  const notifiche = centro?.notifiche ?? []
  return <main className="app-shell season-shell alerts-shell">
    <GameNav league={league} active="notifications" onNavigate={onNavigate} />
    <header className="topbar season-topbar"><div className="brand-lockup brand-lockup--dark"><img src="/specialone-mark.svg" alt="" /><span>SpecialOne</span></div><span>Centro avvisi</span></header>
    <div className="season-page season-page--narrow alerts-page">
      <section className="alerts-heading">
        <div><p className="kicker">{league.nome}</p><h1>Avvisi.</h1><p>Risultati, mercato e aggiornamenti della tua carriera, tutti nello stesso posto.</p></div>
        <div className="alerts-heading__count"><strong>{notifiche.length}</strong><span>{notifiche.length === 1 ? 'avviso' : 'avvisi'}</span></div>
      </section>

      {centro?.caricamento ? <section className="alerts-empty"><span className="season-loader" /><h2>Carico gli avvisi…</h2></section>
        : notifiche.length === 0 ? <section className="alerts-empty"><span aria-hidden="true">◎</span><h2>Nessun avviso per ora.</h2><p>Qui arriveranno i risultati delle giornate, le proposte di mercato e gli aggiornamenti importanti.</p></section>
          : <section className="alerts-list" aria-label="Elenco avvisi"><ol>{notifiche.map((notifica) => <li className={notifica.letta_il ? '' : 'is-new'} key={notifica.id}>
            <button className="alerts-list__open" type="button" onClick={() => centro?.apri(notifica)}>
              <IconaNotifica tipo={notifica.tipo} />
              <span><strong>{notifica.titolo}</strong>{notifica.corpo && <small>{notifica.corpo}</small>}</span>
              <time dateTime={notifica.creata_il}>{quandoRelativo(notifica.creata_il)}</time>
            </button>
            <button className="alerts-list__delete" type="button" aria-label={`Elimina: ${notifica.titolo}`} title="Elimina avviso" onClick={() => void centro?.elimina(notifica.id)}>×</button>
          </li>)}</ol></section>}
    </div>
  </main>
}
