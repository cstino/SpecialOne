import { useState } from 'react'
import { LOGO_CONFERENZA, LOGO_CONFERENZA_EMBLEMA, NOME_CONFERENZA, SIGLA_CONFERENZA, type Conferenza } from '../lib/conferenze'

// Logo della conferenza: grande = logo completo con la scritta, piccolo = solo emblema.
// Se l'immagine non carica resta un distintivo disegnato.
export function ConferenceBadge({ conferenza, grande = false }: { conferenza: Conferenza; grande?: boolean }) {
  const [immagineOk, setImmagineOk] = useState(true)
  return <span className={`conf-badge conf-badge--${conferenza} ${grande ? 'conf-badge--grande' : ''}`} title={NOME_CONFERENZA[conferenza]}>
    {immagineOk
      ? <img src={(grande ? LOGO_CONFERENZA : LOGO_CONFERENZA_EMBLEMA)[conferenza]} alt={NOME_CONFERENZA[conferenza]} onError={() => setImmagineOk(false)} />
      : <span className="conf-badge__segnaposto" aria-label={NOME_CONFERENZA[conferenza]}><b>{SIGLA_CONFERENZA[conferenza]}</b><small>CONFERENCE</small></span>}
  </span>
}
