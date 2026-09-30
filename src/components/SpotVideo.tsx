import { useEffect, useRef } from 'react'

// Spot a schermo intero prima dell'intro della partita. Parte da solo (il
// tocco su "Vedi risultato" ha gia' sbloccato l'audio) e non si puo' saltare.
// Se il browser lo blocca o il file non si carica si passa oltre: lo spot e'
// una sorpresa, mai un ostacolo fra il giocatore e il risultato.
export function SpotVideo({ src, onFine }: { src: string; onFine: () => void }) {
  const ref = useRef<HTMLVideoElement>(null)
  const fine = useRef(onFine)
  fine.current = onFine
  useEffect(() => {
    void ref.current?.play().catch(() => fine.current())
  }, [])
  return <div className="spot-video" role="dialog" aria-modal="true" aria-label="Spot">
    <video ref={ref} src={src} playsInline autoPlay preload="auto" onEnded={onFine} onError={onFine} />
  </div>
}
