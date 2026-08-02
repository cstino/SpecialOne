import { useEffect, useState } from 'react'

export type StatsStagione = {
  presenze: number
  minuti: number
  gol: number
  assist: number
  porteInviolate: number
  tiri: number
  tiriPorta: number
  passaggiTentati: number
  passaggiRiusciti: number
  contrastiVinti: number
  dribbling: number
}

export type DatiScheda = {
  nome: string
  club?: string | null
  nazionalita?: string | null
  posizioni: string[]
  overall: number
  eta: number
  piede?: string | null
  altezza?: number | null
  condizione?: number
  infortunatoFinoA?: number
  /** Ingaggio annuo in euro (design §5.1: la scala e' annuale). */
  ingaggio?: number
  attributi: Record<string, number | null>
}

type Props = {
  giocatore: DatiScheda
  fotoUrl?: string
  stagione?: StatsStagione
  azionePericolosa?: {
    etichetta: string
    descrizione: string
    inCorso?: boolean
    errore?: string | null
    onConferma: () => void
  }
  onClose: () => void
}

const ETICHETTE_ATTRIBUTI: Array<[string, string]> = [
  ['pace', 'Velocità'], ['shooting', 'Tiro'], ['passing', 'Passaggio'], ['dribbling_generale', 'Dribbling'], ['defending', 'Difesa'], ['physic', 'Fisico'],
  ['stamina', 'Resistenza'], ['finishing', 'Finalizzazione'], ['short_passing', 'Passaggi corti'], ['standing_tackle', 'Contrasti'],
  ['gk_diving', 'Tuffo'], ['gk_handling', 'Presa'], ['gk_kicking', 'Rinvio'], ['gk_positioning', 'Posizionamento'], ['gk_reflexes', 'Riflessi'],
]

function reparto(slot = '') {
  if (slot === 'GK') return 'GK'
  if (['CB', 'LB', 'RB', 'LWB', 'RWB'].includes(slot)) return 'DEF'
  if (['CDM', 'CM', 'CAM', 'LM', 'RM'].includes(slot)) return 'MID'
  return 'ATT'
}

function AnonymousPlayer() {
  return <span className="anonymous-player" aria-hidden="true"><svg viewBox="0 0 100 110" focusable="false"><circle cx="50" cy="33" r="22" /><path d="M12 108c2-31 16-48 38-48s36 17 38 48H12Z" /></svg></span>
}

function percentuale(parte: number, totale: number) {
  if (totale <= 0) return '—'
  return `${Math.round(parte / totale * 100)}%`
}

export function SchedaGiocatore({ giocatore, fotoUrl, stagione, azionePericolosa, onClose }: Props) {
  const [confermaAperta, setConfermaAperta] = useState(false)
  useEffect(() => {
    const chiudiConEsc = (evento: KeyboardEvent) => { if (evento.key === 'Escape') onClose() }
    document.addEventListener('keydown', chiudiConEsc)
    const overflowPrecedente = document.body.style.overflow
    document.body.style.overflow = 'hidden'
    return () => { document.removeEventListener('keydown', chiudiConEsc); document.body.style.overflow = overflowPrecedente }
  }, [onClose])

  const rep = reparto(giocatore.posizioni[0])

  return <div className="player-modal-backdrop" role="presentation" onPointerDown={(evento) => { if (evento.target === evento.currentTarget) onClose() }}>
    <section className="player-modal" role="dialog" aria-modal="true" aria-labelledby="player-modal-title">
      <button className="player-modal__close" type="button" onClick={onClose} aria-label="Chiudi dettagli giocatore">×</button>
      <div className="player-modal__hero">
        <div className={`player-modal__photo player-modal__photo--${rep} ${fotoUrl ? 'has-photo' : ''}`}>
          <AnonymousPlayer />
          {fotoUrl && <img src={fotoUrl} alt={giocatore.nome} onError={(evento) => { evento.currentTarget.hidden = true; evento.currentTarget.parentElement?.classList.remove('has-photo') }} />}
        </div>
        <div>
          <p className="kicker">Scheda giocatore</p>
          <h2 id="player-modal-title">{giocatore.nome}</h2>
          <p>{[giocatore.club, giocatore.nazionalita].filter(Boolean).join(' · ') || '—'}</p>
        </div>
        <strong className="player-modal__overall"><span>OVR</span>{giocatore.overall}</strong>
      </div>

      <dl className="player-modal__facts">
        <div><dt>Età</dt><dd>{giocatore.eta}</dd></div>
        <div><dt>Ruoli</dt><dd>{giocatore.posizioni.join(' · ') || '—'}</dd></div>
        <div><dt>Piede</dt><dd>{giocatore.piede ?? '—'}</dd></div>
        <div><dt>Altezza</dt><dd>{giocatore.altezza ? `${giocatore.altezza} cm` : '—'}</dd></div>
        {typeof giocatore.ingaggio === 'number' && <div className="fatto-ingaggio"><dt>Ingaggio</dt><dd>{(giocatore.ingaggio / 1_000_000).toFixed(1)} M€ <small>/ anno</small></dd></div>}
      </dl>

      {typeof giocatore.condizione === 'number' && <section className={`player-modal__fitness ${(giocatore.infortunatoFinoA ?? 0) > 0 ? 'is-injured' : ''}`}>
        <div>
          <span>Forma fisica</span>
          {(giocatore.infortunatoFinoA ?? 0) > 0
            ? <strong>Infortunato</strong>
            : <strong>{giocatore.condizione}%</strong>}
        </div>
        {(giocatore.infortunatoFinoA ?? 0) > 0
          ? <p>Rientro previsto tra {giocatore.infortunatoFinoA} {giocatore.infortunatoFinoA === 1 ? 'giornata' : 'giornate'}.</p>
          : <><div className="player-modal__fitness-bar"><i style={{ width: `${giocatore.condizione}%` }} /></div><p>{giocatore.condizione >= 75 ? 'Pronto per giocare.' : giocatore.condizione >= 55 ? 'Condizione da gestire.' : 'Rischio elevato di sostituzione.'}</p></>}
      </section>}

      {stagione && <div className="player-modal__stats">
        <h3>Stagione</h3>
        {stagione.presenze === 0
          ? <p className="season-empty">Non ha ancora giocato in questa stagione.</p>
          : <>
            <div className="scheda-numeri">
              <div><b>{stagione.presenze}</b><span>Presenze</span></div>
              <div><b>{stagione.minuti}</b><span>Minuti</span></div>
              <div><b>{stagione.gol}</b><span>Gol</span></div>
              <div><b>{stagione.assist}</b><span>Assist</span></div>
              <div><b>{stagione.porteInviolate}</b><span>Porta inviolata</span></div>
              <div><b>{stagione.minuti > 0 ? ((stagione.gol + stagione.assist) * 90 / stagione.minuti).toFixed(2) : '—'}</b><span>G+A ogni 90&#39;</span></div>
            </div>
            <div className="scheda-quote">
              <div><span>Tiri in porta</span><b>{percentuale(stagione.tiriPorta, stagione.tiri)}</b><small>{stagione.tiriPorta} su {stagione.tiri}</small></div>
              <div><span>Passaggi riusciti</span><b>{percentuale(stagione.passaggiRiusciti, stagione.passaggiTentati)}</b><small>{stagione.passaggiRiusciti} su {stagione.passaggiTentati}</small></div>
              <div><span>Contrasti vinti</span><b>{stagione.contrastiVinti}</b><small>totali</small></div>
              <div><span>Dribbling riusciti</span><b>{stagione.dribbling}</b><small>totali</small></div>
            </div>
          </>}
      </div>}

      <div className="player-modal__stats">
        <h3>Attributi</h3>
        <div className="player-stats-grid">
          {ETICHETTE_ATTRIBUTI.map(([chiave, etichetta]) => {
            const valore = giocatore.attributi[chiave]
            return typeof valore === 'number'
              ? <div className="player-stat" key={chiave}><span>{etichetta}</span><b>{valore}</b><i><span style={{ width: `${valore}%` }} /></i></div>
              : null
          })}
        </div>
      </div>

      {azionePericolosa && <div className="player-modal__danger">
        {!confermaAperta
          ? <button className="button button--danger-ghost" type="button" onClick={() => setConfermaAperta(true)}>{azionePericolosa.etichetta}</button>
          : <div className="player-modal__confirm">
              <div><strong>Confermi lo svincolo?</strong><p>{azionePericolosa.descrizione}</p></div>
              {azionePericolosa.errore && <p className="notice notice--error">{azionePericolosa.errore}</p>}
              <div>
                <button className="button button--danger" type="button" disabled={azionePericolosa.inCorso} onClick={azionePericolosa.onConferma}>{azionePericolosa.inCorso ? 'Svincolo…' : 'Svincola definitivamente'}</button>
                <button className="button button--secondary" type="button" disabled={azionePericolosa.inCorso} onClick={() => setConfermaAperta(false)}>Annulla</button>
              </div>
            </div>}
      </div>}
    </section>
  </div>
}
