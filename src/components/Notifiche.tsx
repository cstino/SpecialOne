import { useEffect, useRef, useState } from 'react'
import { quandoRelativo, useNotifiche, type Notifica, type TipoNotifica } from '../lib/notifiche'

type NotificheProps = {
  userId: string
  // Portare la notifica dove e' successa la cosa: senza, il pallino dice che
  // e' successo qualcosa ma tocca all'utente cercarlo.
  onApriNotifica?: (notifica: Notifica) => void
  embedded?: boolean
}

const ICONE: Record<TipoNotifica, string> = {
  giornata_simulata: 'M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18m0 4 4.3 3.1-1.6 5h-5.4l-1.6-5z',
  formazione_mancante: 'M12 3.5v10m0 4.2v.3M4.2 19.5h15.6L12 4.5z',
  infortunio: 'M9.5 3h5v6.5H21v5h-6.5V21h-5v-6.5H3v-5h6.5z',
  mercato_proposta: 'M4 8h13m0 0-3.2-3.2M17 8l-3.2 3.2M20 16H7m0 0 3.2-3.2M7 16l3.2 3.2',
  mercato_esito: 'M4.5 12.5 9.5 17.5 19.5 6.5',
  mercato_asta: 'M6 20h8M9.5 16.5 16 10M4 9.5 9.5 4l4 4L8 13.5zM13.5 8 19 13.5',
  sistema: 'M12 8.5v4.2m0 3.1v.2M12 3.5a8.5 8.5 0 1 0 0 17 8.5 8.5 0 0 0 0-17',
}

export function IconaNotifica({ tipo }: { tipo: TipoNotifica }) {
  return <i aria-hidden="true" data-tipo={tipo}>
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
      <path d={ICONE[tipo] ?? ICONE.sistema} />
    </svg>
  </i>
}

export function Notifiche({ userId, onApriNotifica, embedded = false }: NotificheProps) {
  const { notifiche, nonLette, caricamento, segnaLette, elimina } = useNotifiche(userId)
  const [aperto, setAperto] = useState(false)
  const contenitore = useRef<HTMLDivElement>(null)

  // Aprire il pannello vale come averle viste: e' il gesto con cui si guarda
  // cosa e' arrivato, e chiedere un secondo tocco per spegnere il pallino
  // sarebbe solo attrito.
  useEffect(() => {
    if (aperto && nonLette > 0) void segnaLette()
  }, [aperto, nonLette, segnaLette])

  useEffect(() => {
    if (!aperto) return
    function fuori(evento: MouseEvent) {
      if (!contenitore.current?.contains(evento.target as Node)) setAperto(false)
    }
    function esc(evento: KeyboardEvent) { if (evento.key === 'Escape') setAperto(false) }
    document.addEventListener('mousedown', fuori)
    document.addEventListener('keydown', esc)
    return () => {
      document.removeEventListener('mousedown', fuori)
      document.removeEventListener('keydown', esc)
    }
  }, [aperto])

  const etichetta = nonLette > 0
    ? `Notifiche, ${nonLette} da leggere`
    : 'Notifiche'

  return (
    <div className={`notifiche ${embedded ? 'notifiche--embedded' : ''}`} ref={contenitore}>
      <button
        className={`notifiche__campana ${nonLette > 0 ? 'ha-novita' : ''}`}
        type="button"
        onClick={() => setAperto((stato) => !stato)}
        aria-label={etichetta}
        aria-expanded={aperto}
      >
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
          <path d="M18 9a6 6 0 1 0-12 0c0 4.5-1.5 5.6-2 6.5h16c-.5-.9-2-2-2-6.5" />
          <path d="M10 19a2.2 2.2 0 0 0 4 0" />
        </svg>
        {nonLette > 0 && <span className="notifiche__pallino">{nonLette > 9 ? '9+' : nonLette}</span>}
        {embedded && <span className="notifiche__etichetta">Avvisi</span>}
      </button>

      {aperto && (
        <div className="notifiche__pannello" role="dialog" aria-label="Notifiche">
          <header>
            <strong>Notifiche</strong>
            <button className="notifiche__chiudi" type="button" onClick={() => setAperto(false)} aria-label="Chiudi le notifiche">×</button>
          </header>

          {caricamento && <p className="notifiche__vuoto">Carico…</p>}

          {!caricamento && notifiche.length === 0 && (
            <p className="notifiche__vuoto">Ancora niente da segnalare.<br />Qui arriveranno i risultati delle giornate e le proposte di mercato.</p>
          )}

          <ul>
            {notifiche.map((notifica) => (
              <li key={notifica.id}>
                <button
                  className={`notifiche__voce ${notifica.letta_il ? '' : 'e-nuova'}`}
                  type="button"
                  onClick={() => { setAperto(false); onApriNotifica?.(notifica) }}
                >
                  <IconaNotifica tipo={notifica.tipo} />
                  <span>
                    <strong>{notifica.titolo}</strong>
                    {notifica.corpo && <small>{notifica.corpo}</small>}
                  </span>
                  <time dateTime={notifica.creata_il}>{quandoRelativo(notifica.creata_il)}</time>
                </button>
                <button
                  className="notifiche__elimina"
                  type="button"
                  aria-label={`Elimina: ${notifica.titolo}`}
                  title="Elimina avviso"
                  onClick={() => void elimina(notifica.id)}
                >×</button>
              </li>
            ))}
          </ul>
        </div>
      )}
    </div>
  )
}
