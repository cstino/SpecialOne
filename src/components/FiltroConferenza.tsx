import type { Conferenza } from '../lib/conferenze'
import { NOME_CONFERENZA_BREVE } from '../lib/conferenze'
import { ConferenceBadge } from './ConferenceBadge'

export type FiltroConf = 'tutte' | Conferenza

// «Tutte» oppure una sola conferenza, col suo logo: serve a Partite e alle classifiche dei giocatori.
export function FiltroConferenza({ value, onChange }: { value: FiltroConf; onChange: (v: FiltroConf) => void }) {
  return <div className="filtro-conf" role="tablist" aria-label="Filtra per conferenza">
    <button type="button" role="tab" aria-selected={value === 'tutte'} className={value === 'tutte' ? 'is-attiva' : ''} onClick={() => onChange('tutte')}>Tutte</button>
    {(['est', 'ovest'] as const).map((c) => <button type="button" role="tab" aria-selected={value === c} key={c}
      className={`${value === c ? 'is-attiva ' : ''}filtro-conf--${c}`} onClick={() => onChange(c)}>
      <ConferenceBadge conferenza={c} /><span>{NOME_CONFERENZA_BREVE[c]}</span>
    </button>)}
  </div>
}
