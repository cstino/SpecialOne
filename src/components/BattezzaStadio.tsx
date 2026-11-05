import { useEffect, useState, type FormEvent } from 'react'
import { supabase } from '../lib/supabase'
import { NOME_STADIO_MAX, immagineStadio } from '../lib/stadio'
import type { Membership } from '../types'

// Battesimo dello stadio (5/11/2026): al primo ingresso nella lega con lo stadio acceso l'allenatore sceglie il
// nome del suo stadio. Il campo parte dal nome di default: confermarlo cosi' com'e' vale come scelta. Dopo, il nome
// si cambia da Club > Modifica squadra a stagione in corso.

type Props = { membership: Membership; onFatto: () => void }

export function BattezzaStadio({ membership, onFatto }: Props) {
  const [nome, setNome] = useState(membership.nome_stadio ?? '')
  const [livello, setLivello] = useState(0)
  const [invio, setInvio] = useState(false)
  const [errore, setErrore] = useState('')

  useEffect(() => {
    let vivo = true
    void supabase.from('team_risorse').select('livello_stadio').eq('team_id', membership.id).maybeSingle().then(({ data }) => {
      if (vivo && data) setLivello((data as { livello_stadio: number }).livello_stadio)
    })
    return () => { vivo = false }
  }, [membership.id])

  async function conferma(evento: FormEvent) {
    evento.preventDefault()
    setInvio(true)
    setErrore('')
    const { error } = await supabase.rpc('battezza_stadio', { p_team_id: membership.id, p_nome: nome })
    setInvio(false)
    if (error) { setErrore(error.message); return }
    onFatto()
  }

  const pulito = nome.trim()

  return (
    <main className="battezza-stadio">
      <div className="battezza-stadio__foto"><img src={immagineStadio(livello)} alt="" /></div>
      <header className="battezza-stadio__testa">
        <p className="battezza-stadio__kicker">{membership.nome} · Stadio</p>
        <h1>Dai un nome al tuo stadio</h1>
        <p>È la casa della tua squadra: il nome comparirà sulla locandina di ogni partita in casa. Puoi tenere quello proposto o scriverne uno tuo. Potrai cambiarlo da Club, a stagione in corso.</p>
      </header>
      <form className="battezza-stadio__form" onSubmit={(e) => void conferma(e)}>
        <label htmlFor="battezza-stadio-nome">Nome dello stadio</label>
        <input
          id="battezza-stadio-nome" type="text" value={nome} maxLength={NOME_STADIO_MAX} autoComplete="off"
          disabled={invio} onChange={(e) => setNome(e.target.value.slice(0, NOME_STADIO_MAX))}
        />
        <small>{pulito.length}/{NOME_STADIO_MAX} caratteri</small>
        {errore && <p className="battezza-stadio__errore" role="alert">{errore}</p>}
        <button type="submit" className="battezza-stadio__conferma" disabled={pulito.length < 3 || invio}>{invio ? 'Salvo…' : 'Inaugura lo stadio'}</button>
      </form>
    </main>
  )
}
