import { REAZIONI, ATTESA_REAZIONE_S, useReazioniLive, type Contesto } from '../lib/reazioni'

type Props = {
  leagueId: number
  contesto: Contesto
  mioTeamId: number
  // Sigla da mostrare accanto alla reazione di una squadra (3 lettere).
  sigla: (teamId: number) => string
  demo?: { teamIds: number[] }
}

// Le reazioni stanno in una fascia riservata (spazio vuoto fra la scena e il resto), non sopra la pagina:
// le emoji salgono da li' e non coprono mai i dati del draft o del sorteggio.
export function ReazioniLive({ leagueId, contesto, mioTeamId, sigla, demo }: Props) {
  const { bolle, attesa, errore, invia } = useReazioniLive({ leagueId, contesto, mioTeamId, demo })
  const inAttesa = attesa > 0
  return <section className="reazioni" aria-label="Reazioni in diretta">
    <div className="reazioni__cielo" aria-hidden="true">
      {bolle.map((b) => {
        const r = REAZIONI.find((x) => x.codice === b.codice)
        if (!r) return null
        return <span key={b.id} className={`reazioni__bolla${b.teamId === mioTeamId ? ' is-mia' : ''}`} style={{ left: `${b.x}%`, animationDelay: `${b.ritardo}s` }}>
          <i>{r.emoji}</i><b>{r.testo}</b><small>{b.teamId === mioTeamId ? 'Tu' : sigla(b.teamId)}</small>
        </span>
      })}
    </div>
    <div className="reazioni__pulsanti" role="group" aria-label="Manda una reazione">
      {REAZIONI.map((r) => <button key={r.codice} type="button" disabled={inAttesa} onClick={() => void invia(r.codice)} aria-label={r.testo}>
        <i aria-hidden="true">{r.emoji}</i><span>{r.testo}</span>
      </button>)}
    </div>
    <div className="reazioni__stato" role="status">
      <span className="reazioni__barra" style={{ ['--p' as string]: `${inAttesa ? (1 - attesa / ATTESA_REAZIONE_S) * 100 : 100}%` }} />
      <small>{errore ?? (inAttesa ? `Puoi rimandarne una tra ${Math.ceil(attesa)} s` : 'Tocca per reagire: una ogni 5 secondi')}</small>
    </div>
  </section>
}
