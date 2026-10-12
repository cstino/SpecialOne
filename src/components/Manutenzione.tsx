import type { StatoManutenzione } from '../lib/useManutenzione'

export function Manutenzione({ stato }: { stato: StatoManutenzione }) {
  const manuale = stato.motivo === 'manuale'
  return (
    <main className="man" role="alert">
      <div className="man-sfondo" aria-hidden="true" />
      <div className="man-colonna">
        <img className="man-logo" src="/specialone-mark.svg" alt="" />
        <p className="man-occhiello">{manuale ? 'Manutenzione in corso' : 'Connessione assente'}</p>
        <h1>{manuale ? 'Server in manutenzione' : 'Il server non risponde'}</h1>
        <p className="man-testo">
          {stato.messaggio
            ?? (manuale
              ? 'Stiamo sistemando alcune cose. Le tue squadre sono al sicuro: torna tra poco.'
              : 'Controlla la connessione. Se è tutto a posto, probabilmente stiamo lavorando al server: riprova tra poco.')}
        </p>
        <button className="man-riprova" type="button" onClick={stato.riprova}>Riprova ora</button>
        <p className="man-nota">La pagina si riaggiorna da sola appena il server torna disponibile.</p>
      </div>
    </main>
  )
}
