import { useEffect, useRef } from 'react'

// Gesto "torna indietro" in stile iOS/Android: si parte col dito vicino al
// bordo sinistro dello schermo e si trascina verso destra. Attivo solo da
// quel bordo per non entrare in conflitto con gli scroll orizzontali interni
// (panchina in formazione, tabelle classifica, ecc.), che non partono mai li'.
const SOGLIA_BORDO_PX = 24
const SOGLIA_TRASCINAMENTO_PX = 70
const TOLLERANZA_VERTICALE = 0.6

export function useSwipeIndietro(alTornaIndietro: () => void) {
  const partenza = useRef<{ x: number; y: number; valido: boolean } | null>(null)

  useEffect(() => {
    function alTouchStart(evento: TouchEvent) {
      const tocco = evento.touches[0]
      if (!tocco) return
      partenza.current = { x: tocco.clientX, y: tocco.clientY, valido: tocco.clientX <= SOGLIA_BORDO_PX }
    }
    function alTouchEnd(evento: TouchEvent) {
      const inizio = partenza.current
      partenza.current = null
      if (!inizio?.valido) return
      const tocco = evento.changedTouches[0]
      if (!tocco) return
      const dx = tocco.clientX - inizio.x
      const dy = Math.abs(tocco.clientY - inizio.y)
      if (dx >= SOGLIA_TRASCINAMENTO_PX && dy < dx * TOLLERANZA_VERTICALE) {
        alTornaIndietro()
      }
    }
    document.addEventListener('touchstart', alTouchStart, { passive: true })
    document.addEventListener('touchend', alTouchEnd, { passive: true })
    return () => {
      document.removeEventListener('touchstart', alTouchStart)
      document.removeEventListener('touchend', alTouchEnd)
    }
  }, [alTornaIndietro])
}
