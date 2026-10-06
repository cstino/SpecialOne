import { useEffect, useState } from 'react'
import { REAZIONI, ATTESA_REAZIONE_S, useReazioniLive, type Contesto } from '../lib/reazioni'

type Props = {
  leagueId: number
  contesto: Contesto
  mioTeamId: number
  // Sigla da mostrare accanto alla reazione di una squadra (3 lettere).
  sigla: (teamId: number) => string
  // true: il pulsante resta fisso in basso a destra dello schermo (schermate dedicate alle dirette);
  // false: sta nell'angolo della fascia, dentro la pagina (card in home).
  fisso?: boolean
  demo?: { teamIds: number[] }
}

// Un pulsante tondo apre la finestrella con tutte le reazioni. Le emoji degli altri (e le tue) salgono in una
// fascia riservata dentro la pagina, fra la scena e il resto: non coprono mai i dati del draft o del sorteggio.
export function ReazioniLive({ leagueId, contesto, mioTeamId, sigla, fisso = true, demo }: Props) {
  const { bolle, attesa, errore, invia } = useReazioniLive({ leagueId, contesto, mioTeamId, demo })
  const [aperto, setAperto] = useState(false)
  const inAttesa = attesa > 0

  useEffect(() => {
    if (!aperto) return
    const chiudiConEsc = (e: KeyboardEvent) => { if (e.key === 'Escape') setAperto(false) }
    window.addEventListener('keydown', chiudiConEsc)
    return () => window.removeEventListener('keydown', chiudiConEsc)
  }, [aperto])

  return <section className={`reazioni${fisso ? ' reazioni--fisso' : ''}`} aria-label="Reazioni in diretta">
    <div className="reazioni__cielo" aria-hidden="true">
      {bolle.length === 0 && <span className="reazioni__suggerimento">Le reazioni di tutti compaiono qui</span>}
      {bolle.map((b) => {
        const r = REAZIONI.find((x) => x.codice === b.codice)
        if (!r) return null
        return <span key={b.id} className={`reazioni__bolla${b.teamId === mioTeamId ? ' is-mia' : ''}`} style={{ left: `${b.x}%`, animationDelay: `${b.ritardo}s` }}>
          <i>{r.emoji}</i><b>{r.testo}</b><small>{b.teamId === mioTeamId ? 'Tu' : sigla(b.teamId)}</small>
        </span>
      })}
    </div>

    {aperto && <>
      <button type="button" className="reazioni__scrim" aria-label="Chiudi le reazioni" onClick={() => setAperto(false)} />
      <div className="reazioni__pannello" role="dialog" aria-label="Manda una reazione">
        <header>
          <strong>Reagisci</strong>
          <small>{errore ?? (inAttesa ? `Puoi rimandarne una tra ${Math.ceil(attesa)} s` : 'Una ogni 5 secondi')}</small>
        </header>
        <div className="reazioni__griglia">
          {REAZIONI.map((r) => <button key={r.codice} type="button" disabled={inAttesa} onClick={() => { void invia(r.codice); setAperto(false) }}>
            <i aria-hidden="true">{r.emoji}</i><span>{r.testo}</span>
          </button>)}
        </div>
      </div>
    </>}

    <button type="button" className={`reazioni__fab${inAttesa ? ' is-attesa' : ''}${aperto ? ' is-aperto' : ''}`}
      style={{ ['--p' as string]: `${inAttesa ? (1 - attesa / ATTESA_REAZIONE_S) * 100 : 100}%` }}
      onClick={() => setAperto((a) => !a)} aria-expanded={aperto} aria-label={inAttesa ? `Reazioni: puoi rimandarne una tra ${Math.ceil(attesa)} secondi` : 'Manda una reazione'}>
      <span>{inAttesa ? Math.ceil(attesa) : aperto ? '✕' : '😀'}</span>
    </button>
  </section>
}
