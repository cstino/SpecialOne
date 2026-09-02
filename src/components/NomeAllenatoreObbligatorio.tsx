import { useCallback, useEffect, useState, type FormEvent } from 'react'
import { supabase } from '../lib/supabase'

// Richiesto dall'utente il 2 settembre 2026: 13 dei 18 allenatori con una
// squadra non avevano mai impostato un nome (restava un'impostazione
// facoltativa nella scheda Profilo, facile da non notare mai). Non è più
// facoltativo: un utente senza nome_allenatore vede questo schermo intero
// prima di qualunque altra cosa, la prossima volta che apre l'app — prima
// ancora dell'onboarding, perché è la sua identità di base in ogni lega.
export function useNomeAllenatoreObbligatorio(userId: string | undefined) {
  const [pronto, setPronto] = useState(false)
  const [manca, setManca] = useState(false)

  useEffect(() => {
    if (!userId) { setPronto(true); setManca(false); return }
    let vivo = true
    async function controlla() {
      const { data } = await supabase.from('profiles').select('nome_allenatore').eq('user_id', userId).maybeSingle()
      if (!vivo) return
      setManca(!(data as { nome_allenatore: string } | null)?.nome_allenatore)
      setPronto(true)
    }
    void controlla()
    return () => { vivo = false }
  }, [userId])

  const impostato = useCallback(() => setManca(false), [])

  return { pronto, manca, impostato }
}

export function NomeAllenatoreObbligatorio({ onImpostato }: { onImpostato: () => void }) {
  const [nome, setNome] = useState('')
  const [inCorso, setInCorso] = useState(false)
  const [errore, setErrore] = useState<string | null>(null)

  async function salva(evento: FormEvent) {
    evento.preventDefault()
    setInCorso(true)
    setErrore(null)
    const { error } = await supabase.rpc('aggiorna_nome_allenatore', { p_nome: nome })
    setInCorso(false)
    if (error) { setErrore(error.message); return }
    onImpostato()
  }

  return <main className="fatal-state" role="dialog" aria-modal="true" aria-label="Scegli il nome allenatore">
    <img src="/specialone-mark.svg" alt="" />
    <h1>Come ti chiamano in panchina?</h1>
    <p>Prima di continuare, scegli il nome con cui gli altri allenatori della lega ti vedranno —
      nelle trattative, nei rinnovi, nel draft. Puoi cambiarlo quando vuoi dal tuo profilo.</p>
    <form className="profilo-form nome-allenatore-form" onSubmit={salva}>
      <label>
        Nome allenatore
        <input
          type="text" value={nome} minLength={2} maxLength={30} required autoFocus
          disabled={inCorso} placeholder="Es. Mister Rossi"
          onChange={(evento) => setNome(evento.target.value)}
        />
      </label>
      {errore && <p className="notice notice--error">{errore}</p>}
      <button className="button button--primary" type="submit" disabled={inCorso}>
        {inCorso ? 'Salvo…' : 'Continua'}
      </button>
    </form>
  </main>
}
