import { useCallback, useEffect, useRef, useState, type PointerEvent as ReactPointerEvent, type RefObject } from 'react'
import { flushSync } from 'react-dom'

// Scambio di due titolari trascinando: si tiene premuto su una card in campo (circa un terzo di
// secondo, col mouse basta muoversi), la card si solleva e segue il dito; avvicinandosi a un altro
// titolare viene attirata (calamita) e quello si illumina; rilasciando i due si scambiano di posto
// con un movimento unico, senza salti. Rilasciando altrove la card torna al suo posto.
//
// Tutto il movimento e' fatto sul DOM (proprieta' CSS `translate` e `scale`, che si compongono col
// transform di posizionamento delle card) e non con lo stato di React, cosi' resta fluido: lo stato
// serve solo per le classi (chi e' in mano, chi e' il bersaglio).

const ATTESA_TOCCO_MS = 320
const SOGLIA_MOVIMENTO_TOCCO = 9
const SOGLIA_MOVIMENTO_MOUSE = 6
const DURATA_RILASCIO_MS = 190
const SCALA_IN_MANO = 1.08

type Bersaglio = { indice: number; el: HTMLElement; cx: number; cy: number }
type Sessione = {
  indice: number; pointerId: number; tipo: string; x0: number; y0: number
  avviato: boolean; timer: number; el: HTMLElement
  origine: { cx: number; cy: number }; bersagli: Bersaglio[]; raggio: number
  verso: number | null; x: number; y: number; frame: number
}

type Opzioni = {
  campo: RefObject<HTMLElement | null>
  // Posti che possono scambiarsi (occupati e disponibili).
  scambiabili: number[]
  onScambia: (da: number, verso: number) => void
}

const liscia = (k: number) => k * k * (3 - 2 * k)

export function useScambioTrascinando({ campo, scambiabili, onScambia }: Opzioni) {
  const [stato, setStato] = useState<{ da: number | null; verso: number | null }>({ da: null, verso: null })
  const viva = useRef({ scambiabili, onScambia })
  viva.current = { scambiabili, onScambia }
  const sessione = useRef<Sessione | null>(null)
  const soppresso = useRef(false)
  const pulizia = useRef<(() => void) | null>(null)

  useEffect(() => () => pulizia.current?.(), [])

  const premuto = useCallback((evento: ReactPointerEvent<HTMLElement>, indice: number) => {
    if (sessione.current || (evento.pointerType === 'mouse' && evento.button !== 0)) return
    if (!viva.current.scambiabili.includes(indice) || viva.current.scambiabili.length < 2) return
    const el = evento.currentTarget
    const s: Sessione = {
      indice, pointerId: evento.pointerId, tipo: evento.pointerType, x0: evento.clientX, y0: evento.clientY,
      avviato: false, timer: 0, el, origine: { cx: 0, cy: 0 }, bersagli: [], raggio: 0, verso: null, x: evento.clientX, y: evento.clientY, frame: 0,
    }
    sessione.current = s

    const blocca = (e: Event) => { if (e.cancelable) e.preventDefault() }
    const rimuoviAscoltatori = () => {
      window.removeEventListener('pointermove', muovi)
      window.removeEventListener('pointerup', rilascia)
      window.removeEventListener('pointercancel', annulla)
      window.removeEventListener('touchmove', blocca)
      window.clearTimeout(s.timer)
      window.cancelAnimationFrame(s.frame)
    }
    pulizia.current = () => { rimuoviAscoltatori(); ripristina(); sessione.current = null }

    const ripristina = () => {
      for (const b of s.bersagli) { b.el.classList.remove('is-rilascio'); b.el.style.translate = ''; b.el.style.scale = '' }
      s.el.classList.remove('is-trascinato', 'is-rilascio'); s.el.style.translate = ''; s.el.style.scale = ''
      document.body.classList.remove('sta-trascinando')
    }

    const avvia = () => {
      if (s.avviato) return
      s.avviato = true
      const r = s.el.getBoundingClientRect()
      s.origine = { cx: r.left + r.width / 2, cy: r.top + r.height / 2 }
      s.raggio = Math.max(70, r.width * 1.05)
      const radice = campo.current
      s.bersagli = []
      radice?.querySelectorAll<HTMLElement>('[data-posto]').forEach((el) => {
        const i = Number(el.dataset.posto)
        if (i === indice || !viva.current.scambiabili.includes(i)) return
        const q = el.getBoundingClientRect()
        s.bersagli.push({ indice: i, el, cx: q.left + q.width / 2, cy: q.top + q.height / 2 })
      })
      try { s.el.setPointerCapture(s.pointerId) } catch { /* il browser puo' rifiutare: si va avanti con la finestra */ }
      window.addEventListener('touchmove', blocca, { passive: false })
      document.body.classList.add('sta-trascinando')
      s.el.classList.add('is-trascinato')
      s.el.style.scale = String(SCALA_IN_MANO)
      soppresso.current = true
      navigator.vibrate?.(12)
      setStato({ da: indice, verso: null })
      aggiorna()
    }

    // Posizione della card: segue il dito; vicino a un bersaglio viene attirata verso di lui, in modo
    // continuo (nessun salto quando entra o esce dal raggio).
    const aggiorna = () => {
      s.frame = 0
      const cx = s.origine.cx + (s.x - s.x0)
      const cy = s.origine.cy + (s.y - s.y0)
      let migliore: Bersaglio | null = null
      let distanza = Infinity
      for (const b of s.bersagli) {
        const d = Math.hypot(cx - b.cx, cy - b.cy)
        if (d < distanza) { distanza = d; migliore = b }
      }
      let t = 0
      if (migliore && distanza < s.raggio) t = 0.8 * liscia(Math.min(1, Math.max(0, (s.raggio - distanza) / (s.raggio * 0.65))))
      const px = migliore ? cx + (migliore.cx - cx) * t : cx
      const py = migliore ? cy + (migliore.cy - cy) * t : cy
      s.el.style.translate = `${px - s.origine.cx}px ${py - s.origine.cy}px`
      // Bersaglio con un po' di isteresi: si sceglie entrando a 0,85 del raggio e si lascia oltre 1,0.
      let verso = s.verso
      if (verso !== null) {
        const attuale = s.bersagli.find((b) => b.indice === verso)
        if (!attuale || Math.hypot(cx - attuale.cx, cy - attuale.cy) > s.raggio) verso = null
      }
      if (verso === null && migliore && distanza < s.raggio * 0.85) verso = migliore.indice
      if (verso !== s.verso) {
        s.verso = verso
        if (verso !== null) navigator.vibrate?.(8)
        setStato({ da: indice, verso })
      }
    }

    const muovi = (e: PointerEvent) => {
      if (e.pointerId !== s.pointerId) return
      s.x = e.clientX; s.y = e.clientY
      if (!s.avviato) {
        const spostamento = Math.hypot(e.clientX - s.x0, e.clientY - s.y0)
        if (s.tipo === 'mouse') { if (spostamento > SOGLIA_MOVIMENTO_MOUSE) avvia() }
        else if (spostamento > SOGLIA_MOVIMENTO_TOCCO) { annullaSenzaAnimazione() }
        return
      }
      if (!s.frame) s.frame = window.requestAnimationFrame(aggiorna)
    }

    const annullaSenzaAnimazione = () => {
      rimuoviAscoltatori(); sessione.current = null; pulizia.current = null
    }

    const concludi = (scambia: boolean) => {
      rimuoviAscoltatori()
      pulizia.current = null
      if (!s.avviato) { sessione.current = null; return }
      window.setTimeout(() => { soppresso.current = false }, 450)
      const bersaglio = scambia ? s.bersagli.find((b) => b.indice === s.verso) : undefined
      s.el.classList.add('is-rilascio')
      if (bersaglio) {
        bersaglio.el.classList.add('is-rilascio')
        s.el.style.translate = `${bersaglio.cx - s.origine.cx}px ${bersaglio.cy - s.origine.cy}px`
        s.el.style.scale = '1'
        bersaglio.el.style.translate = `${s.origine.cx - bersaglio.cx}px ${s.origine.cy - bersaglio.cy}px`
      } else {
        s.el.style.translate = '0px 0px'
        s.el.style.scale = '1'
      }
      window.setTimeout(() => {
        // Le due card arrivano al posto dell'altra: si scambiano i contenuti e si tolgono i movimenti
        // nello stesso istante, cosi' non si vede nessun salto.
        flushSync(() => {
          if (bersaglio) viva.current.onScambia(s.indice, bersaglio.indice)
          setStato({ da: null, verso: null })
        })
        ripristina()
        sessione.current = null
      }, DURATA_RILASCIO_MS)
    }
    const rilascia = (e: PointerEvent) => { if (e.pointerId === s.pointerId) concludi(true) }
    const annulla = (e: PointerEvent) => { if (e.pointerId === s.pointerId) concludi(false) }

    window.addEventListener('pointermove', muovi)
    window.addEventListener('pointerup', rilascia)
    window.addEventListener('pointercancel', annulla)
    if (s.tipo === 'mouse') return
    s.timer = window.setTimeout(avvia, ATTESA_TOCCO_MS)
  }, [campo])

  // Dopo un trascinamento il browser manda comunque un click: va ignorato.
  const clickSoppresso = useCallback(() => soppresso.current, [])
  return { stato, premuto, clickSoppresso }
}
