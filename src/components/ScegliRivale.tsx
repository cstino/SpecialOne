import { useMemo, useState } from 'react'
import { supabase } from '../lib/supabase'
import { useSeasonData } from '../lib/useSeasonData'
import type { Membership } from '../types'
import { Crest } from './Crest'

// La squadra rivale (docs/decisioni-conferenze-stampa.md §2): ogni allenatore indica la squadra con cui ha la
// rivalita' piu' sentita. Quella partita e' sempre un derby, anche se a sceglierla e' stato l'altro. Si puo'
// cambiare una volta a stagione.

type Props = { membership: Membership; onFatto: () => void; onDopo: () => void }

export function ScegliRivale({ membership, onFatto, onDopo }: Props) {
  const dati = useSeasonData(membership)
  const [scelta, setScelta] = useState<number | null>(membership.rivale_id ?? null)
  const [invio, setInvio] = useState(false)
  const [errore, setErrore] = useState('')

  const squadre = useMemo(() => [...dati.teamById.values()]
    .filter((t) => t.id !== membership.id && t.attiva !== false)
    .sort((a, b) => a.nome.localeCompare(b.nome)), [dati.teamById, membership.id])

  async function conferma() {
    if (scelta == null) return
    setInvio(true)
    setErrore('')
    const { error } = await supabase.rpc('scegli_rivale', { p_team_id: membership.id, p_rivale_id: scelta })
    setInvio(false)
    if (error) { setErrore(error.message); return }
    onFatto()
  }

  const scelta_ = squadre.find((x) => x.id === scelta)
  // Chi ti ha gia' scelto come rivale (le squadre sono leggibili da tutta la lega).
  const sceltoDa = squadre.filter((x) => x.rivale_id === membership.id)

  return (
    <main className="scegli-rivale">
      <header className="scegli-rivale__testa">
        <p className="scegli-rivale__kicker">Rivalità</p>
        <h1>{membership.rivale_id ? 'Cambia il tuo rivale' : 'Il tuo derby'}</h1>
        <p>Scegli la squadra con cui hai la rivalità più sentita: la partita contro di lei sarà sempre un derby. Potrai cambiarla una volta a stagione. Con le altre squadre la rivalità cresce o scende in base a quello che dici in conferenza stampa.</p>
      </header>
      {sceltoDa.length > 0 && <div className="scegli-rivale__avviso" role="status">
        <strong>{sceltoDa.length === 1 ? `${sceltoDa[0].nome} ti ha scelto come rivale.` : `${sceltoDa.map((x) => x.nome).join(', ')} ti hanno scelto come rivale.`}</strong>
        <span>{sceltoDa.length === 1 ? 'La vostra partita è già un derby.' : 'Le vostre partite sono già derby.'} Tu puoi scegliere chi vuoi: anche una di loro.</span>
      </div>}
      <ul className="scegli-rivale__elenco">
        {squadre.map((s) => (
          <li key={s.id}>
            <button type="button" className={scelta === s.id ? 'attiva' : ''} aria-pressed={scelta === s.id} onClick={() => setScelta(s.id)}>
              <span className="scegli-rivale__stemma"><Crest value={s.stemma_url ?? null} stelle={s.titoli_title} imageUrl={dati.crestUrlByTeamId.get(s.id)} size="small" /></span>
              <span className="scegli-rivale__nome">{s.nome}</span>
              {s.rivale_id === membership.id && <em className="scegli-rivale__tag">ti ha scelto</em>}
              {scelta === s.id && <i className="scegli-rivale__spunta" aria-hidden="true">✓</i>}
            </button>
          </li>
        ))}
      </ul>
      <div className="scegli-rivale__barra">
        {errore && <p className="scegli-rivale__errore" role="alert">{errore}</p>}
        <p className="scegli-rivale__riepilogo">{scelta_ ? <>Il tuo derby: <strong>{scelta_.nome}</strong></> : 'Tocca una squadra per sceglierla'}</p>
        <button type="button" className="scegli-rivale__conferma" disabled={scelta == null || invio} onClick={() => void conferma()}>{invio ? 'Salvo…' : 'Conferma il rivale'}</button>
        <button type="button" className="scegli-rivale__dopo" onClick={onDopo}>Scelgo dopo</button>
      </div>
    </main>
  )
}
