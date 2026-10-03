import { useEffect, useRef } from 'react'

const COLORI = ['#ffd34d', '#f6dd8c', '#e9c46a', '#fff3b0', '#c9a64b', '#f0a500']

type Particella = { x: number; y: number; vx: number; vy: number; w: number; h: number; ang: number; vang: number; fase: number; colore: string; vita: number }

// Esplosione di coriandoli dorati: parte ogni volta che `scatto` cambia (e
// vale piu' di 0). Con "riduci movimento" non disegna nulla.
export function CoriandoliOri({ scatto }: { scatto: number }) {
  const canvasRef = useRef<HTMLCanvasElement>(null)

  useEffect(() => {
    if (scatto <= 0) return
    if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) return
    const canvas = canvasRef.current
    const ctx = canvas?.getContext('2d')
    if (!canvas || !ctx) return
    const dpr = Math.min(window.devicePixelRatio || 1, 2)
    const larghezza = window.innerWidth
    const altezza = window.innerHeight
    canvas.width = larghezza * dpr
    canvas.height = altezza * dpr
    ctx.scale(dpr, dpr)

    const particelle: Particella[] = []
    const lanci = [[larghezza * 0.5, altezza * 0.52, 190], [larghezza * 0.08, altezza * 0.8, 70], [larghezza * 0.92, altezza * 0.8, 70]]
    for (const [ox, oy, quanti] of lanci) {
      for (let i = 0; i < quanti; i++) {
        const angolo = -Math.PI / 2 + (Math.random() - 0.5) * (ox === larghezza * 0.5 ? 2.4 : 1.1) + (ox < larghezza / 2 && ox !== larghezza * 0.5 ? 0.45 : ox > larghezza / 2 ? -0.45 : 0)
        const velocita = 7 + Math.random() * 11
        particelle.push({
          x: ox, y: oy, vx: Math.cos(angolo) * velocita, vy: Math.sin(angolo) * velocita,
          w: 5 + Math.random() * 7, h: 8 + Math.random() * 9, ang: Math.random() * 6.28, vang: (Math.random() - 0.5) * 0.35,
          fase: Math.random() * 6.28, colore: COLORI[Math.floor(Math.random() * COLORI.length)], vita: 170 + Math.random() * 90,
        })
      }
    }

    let frame = 0
    let id = 0
    function disegna() {
      ctx!.clearRect(0, 0, larghezza, altezza)
      let vive = 0
      for (const p of particelle) {
        if (p.vita <= 0) continue
        p.vita -= 1
        p.vx *= 0.985; p.vy = p.vy * 0.985 + 0.28
        p.x += p.vx; p.y += p.vy; p.ang += p.vang; p.fase += 0.18
        if (p.y > altezza + 30) { p.vita = 0; continue }
        vive += 1
        ctx!.save()
        ctx!.globalAlpha = Math.min(1, p.vita / 50)
        ctx!.translate(p.x, p.y)
        ctx!.rotate(p.ang)
        ctx!.scale(1, Math.cos(p.fase))
        ctx!.fillStyle = p.colore
        ctx!.fillRect(-p.w / 2, -p.h / 2, p.w, p.h)
        ctx!.restore()
      }
      frame += 1
      if (vive > 0 && frame < 600) id = requestAnimationFrame(disegna)
      else ctx!.clearRect(0, 0, larghezza, altezza)
    }
    id = requestAnimationFrame(disegna)
    return () => { cancelAnimationFrame(id); ctx.clearRect(0, 0, larghezza, altezza) }
  }, [scatto])

  return <canvas className="coriandoli-ori" ref={canvasRef} aria-hidden="true" />
}
