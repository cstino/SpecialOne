import { useEffect, useRef } from 'react'

// Gesto "torna indietro" custom, tenuto solo per i contesti senza equivalente
// nativo. Sia Android (gesture navigation di Android 10+, o il tasto back
// nella nav a 3 pulsanti) sia iOS 16.4+ (che dalla stessa versione ha esteso
// lo swipe-back nativo di Safari anche alle web app aggiunte alla Home)
// intercettano gia' da soli lo swipe dal bordo e chiamano history.back().
// Se anche il nostro handler risponde allo stesso tocco si ottiene un doppio
// back sulla stessa cronologia: la pagina "corretta" appare per un istante,
// resta bloccata mentre l'animazione nativa e' ancora in corso, poi quando
// quella finisce esegue il suo back e si finisce un passo oltre il previsto
// (a poche schermate dall'inizio, dritti al menu di scelta lega). Va quindi
// disattivato su entrambe le piattaforme e lasciato solo dove non esiste un
// gesto nativo equivalente (desktop, iOS vecchie prima della 16.4).
const SOGLIA_BORDO_PX = 24
const SOGLIA_TRASCINAMENTO_PX = 70
const TOLLERANZA_VERTICALE = 0.6

function haGestoNativo() {
  const ua = navigator.userAgent
  return /Android/i.test(ua) || /iPad|iPhone|iPod/i.test(ua) || (/Macintosh/i.test(ua) && navigator.maxTouchPoints > 1)
}

export function useSwipeIndietro(alTornaIndietro: () => void) {
  const partenza = useRef<{ x: number; y: number; valido: boolean } | null>(null)

  useEffect(() => {
    if (haGestoNativo()) return
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
