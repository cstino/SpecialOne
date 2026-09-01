import { useCallback, useEffect, useState, type ReactNode } from 'react'
import { supabase } from '../lib/supabase'

// Una volta letta la riga da hint_visti (o scritta al primo "non mostrare
// più"), il risultato resta qui per il resto della sessione: aprendo e
// richiudendo la stessa pagina non si rifà mai la query.
const cacheSessione = new Map<string, boolean>()

function usePopupSpiegazione(userId: string, hintKey: string) {
  const inCache = cacheSessione.get(hintKey)
  const [visto, setVisto] = useState(inCache ?? false)
  const [pronto, setPronto] = useState(inCache !== undefined)

  useEffect(() => {
    if (cacheSessione.has(hintKey)) return
    let vivo = true
    async function carica() {
      const { data } = await supabase.from('hint_visti')
        .select('hint_key').eq('user_id', userId).eq('hint_key', hintKey).maybeSingle()
      if (!vivo) return
      const gia = !!data
      cacheSessione.set(hintKey, gia)
      setVisto(gia)
      setPronto(true)
    }
    void carica()
    return () => { vivo = false }
  }, [userId, hintKey])

  const chiudi = useCallback(async (nonMostrarePiu: boolean) => {
    setVisto(true)
    if (!nonMostrarePiu) return
    cacheSessione.set(hintKey, true)
    await supabase.from('hint_visti').insert({ user_id: userId, hint_key: hintKey })
  }, [userId, hintKey])

  return { pronto, visto, chiudi }
}

type Props = {
  userId: string
  hintKey: string
  titolo: string
  children: ReactNode
}

// Popup di spiegazione alla prima apertura di una pagina (deciso con
// l'utente il 1 settembre 2026). Non renderizza nulla finché non sa se
// l'utente l'ha già chiuso in passato, per evitare un lampo del popup a
// ogni caricamento; una volta saputo che è già stato visto, resta invisibile
// per sempre (a meno di cancellare la riga da hint_visti).
export function PopupSpiegazione({ userId, hintKey, titolo, children }: Props) {
  const { pronto, visto, chiudi } = usePopupSpiegazione(userId, hintKey)
  const [nonMostrare, setNonMostrare] = useState(true)

  if (!pronto || visto) return null

  return (
    <div className="popup-spiegazione-sfondo" role="dialog" aria-modal="true" aria-label={titolo}>
      <div className="popup-spiegazione">
        <h2>{titolo}</h2>
        <div className="popup-spiegazione__corpo">
          {children}
          <p className="popup-spiegazione__rimando">Se vuoi avere maggiori dettagli, consulta la sezione Aiuto.</p>
        </div>
        <label className="popup-spiegazione__checkbox">
          <input type="checkbox" checked={nonMostrare} onChange={(e) => setNonMostrare(e.target.checked)} />
          Non mostrare più
        </label>
        <button className="button button--primary" type="button" onClick={() => void chiudi(nonMostrare)}>Ho capito</button>
      </div>
    </div>
  )
}
