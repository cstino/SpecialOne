// Sottofondo dello stadio che si ripete senza stacco.
//
// Il lettore audio del browser, messo in ripetizione, lascia un buco di silenzio a ogni giro. Qui i
// lettori sono due e suonano lo stesso file sfasati: quando al primo mancano SOVRAPPOSIZIONE secondi
// parte il secondo. Il file (preparato con tools/suoni/prepara-loop.py) entra ed esce in dissolvenza
// per quella stessa durata, quindi la somma resta a volume costante senza toccare il volume dei
// lettori, che sull'iPhone non si puo' cambiare.

export const SUONO_STADIO = '/suoni-effetti/stadio-sottofondo-ciclo.m4a'
const SOVRAPPOSIZIONE = 2

export function creaSottofondo(a: HTMLAudioElement, b: HTMLAudioElement) {
  let attivo = a
  let acceso = false
  const altro = (x: HTMLAudioElement) => (x === a ? b : a)
  const suona = (x: HTMLAudioElement) => { x.muted = false; void x.play().catch(() => {}) }
  const cambia = () => { const y = altro(attivo); y.currentTime = 0; attivo = y; suona(y) }
  const avanza = (e: Event) => {
    const x = e.currentTarget as HTMLAudioElement
    if (!acceso || x !== attivo) return
    // 'ended' e' la rete di sicurezza se la durata non era ancora nota.
    if (e.type === 'ended' || (Number.isFinite(x.duration) && x.duration - x.currentTime <= SOVRAPPOSIZIONE)) cambia()
  }
  for (const x of [a, b]) { x.addEventListener('timeupdate', avanza); x.addEventListener('ended', avanza) }
  return {
    accendi() {
      if (acceso) return
      acceso = true
      suona(attivo)
      // Se la pausa era caduta a meta' passaggio, riprende anche la coda dell'altro lettore.
      const coda = altro(attivo)
      if (coda.currentTime > 0 && !coda.ended) suona(coda)
    },
    spegni() { acceso = false; a.pause(); b.pause() },
    daCapo() { acceso = false; a.pause(); b.pause(); a.currentTime = 0; b.currentTime = 0; attivo = a; this.accendi() },
    smonta() {
      acceso = false
      for (const x of [a, b]) { x.pause(); x.removeEventListener('timeupdate', avanza); x.removeEventListener('ended', avanza) }
    },
  }
}
