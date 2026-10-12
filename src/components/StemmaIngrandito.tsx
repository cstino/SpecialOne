import { useEffect } from 'react'
import { createPortal } from 'react-dom'
import { Crest } from './Crest'

type Props = {
  value: string | null
  imageUrl?: string | null
  stelle?: number | null
  nome: string
  onChiudi: () => void
}

// Lo stemma a centro pagina: si chiude con la X, toccando fuori o con Esc.
export function StemmaIngrandito({ value, imageUrl, stelle, nome, onChiudi }: Props) {
  useEffect(() => {
    const tasto = (e: KeyboardEvent) => { if (e.key === 'Escape') onChiudi() }
    window.addEventListener('keydown', tasto)
    const prima = document.body.style.overflow
    document.body.style.overflow = 'hidden'
    return () => {
      window.removeEventListener('keydown', tasto)
      document.body.style.overflow = prima
    }
  }, [onChiudi])

  return createPortal(
    <div className="stemma-zoom" role="dialog" aria-modal="true" aria-label={`Stemma di ${nome}`} onClick={onChiudi}>
      <button type="button" className="stemma-zoom__chiudi" aria-label="Chiudi" onClick={onChiudi}>
        <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M6 6l12 12M18 6L6 18" /></svg>
      </button>
      <div className="stemma-zoom__logo" onClick={(e) => e.stopPropagation()}>
        <Crest value={value} imageUrl={imageUrl} stelle={stelle} size="large" eager />
      </div>
      <p className="stemma-zoom__nome">{nome}</p>
    </div>,
    document.body,
  )
}
