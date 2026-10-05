import { useState } from 'react'
import { LOGO_CONFERENZA, NOME_CONFERENZA, SIGLA_CONFERENZA, type Conferenza } from '../lib/conferenze'

// Logo della conferenza: l'immagine vera se esiste in public/loghi-conferenza/,
// altrimenti un distintivo disegnato (segnaposto finche' non arrivano i loghi).
export function ConferenceBadge({ conferenza, grande = false }: { conferenza: Conferenza; grande?: boolean }) {
  const [immagineOk, setImmagineOk] = useState(true)
  return <span className={`conf-badge conf-badge--${conferenza} ${grande ? 'conf-badge--grande' : ''}`} title={NOME_CONFERENZA[conferenza]}>
    {immagineOk
      ? <img src={LOGO_CONFERENZA[conferenza]} alt={NOME_CONFERENZA[conferenza]} onError={() => setImmagineOk(false)} />
      : <span className="conf-badge__segnaposto" aria-label={NOME_CONFERENZA[conferenza]}><b>{SIGLA_CONFERENZA[conferenza]}</b><small>CONFERENCE</small></span>}
  </span>
}
