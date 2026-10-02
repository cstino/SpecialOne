import { useLayoutEffect, useRef, type ReactNode } from 'react'

// Un testo su una riga che non viene mai troncato coi puntini: se non entra,
// si rimpicciolisce quanto basta (fino a `minimo` della dimensione normale).
// Deciso col committente il 2 ottobre 2026 per i nomi dei giocatori.
// Misura lo spazio del contenitore (il genitore) e lo rimisura quando cambia
// la sua larghezza o quando finiscono di caricarsi i font.
export function TestoAdattato({ children, minimo = 0.5, className }: { children: ReactNode; minimo?: number; className?: string }) {
  const ref = useRef<HTMLSpanElement>(null)
  useLayoutEffect(() => {
    const el = ref.current
    const genitore = el?.parentElement
    if (!el || !genitore) return
    const adatta = () => {
      el.style.fontSize = '1em'
      el.style.letterSpacing = ''
      const stile = getComputedStyle(genitore)
      // La spaziatura fra le lettere arriva dal contenitore gia' in pixel: va
      // scalata insieme al testo, altrimenti le lettere si stringono e gli
      // spazi no, e il nome continua a non entrare.
      const spaziatura = parseFloat(stile.letterSpacing) || 0
      const disponibile = genitore.clientWidth - parseFloat(stile.paddingLeft) - parseFloat(stile.paddingRight)
      const naturale = el.offsetWidth
      if (naturale <= 0 || disponibile <= 0) return
      const scala = Math.max(minimo, Math.min(1, disponibile / naturale))
      const finale = scala < 1 ? scala * 0.97 : 1
      el.style.fontSize = finale < 1 ? `${finale.toFixed(3)}em` : '1em'
      if (finale < 1 && spaziatura) el.style.letterSpacing = `${(spaziatura * finale).toFixed(3)}px`
    }
    adatta()
    const osservatore = new ResizeObserver(adatta)
    osservatore.observe(genitore)
    void document.fonts?.ready.then(adatta)
    return () => osservatore.disconnect()
  }, [children, minimo])
  return <span ref={ref} className={`testo-adattato${className ? ` ${className}` : ''}`}>{children}</span>
}
