import { useEffect, useRef } from 'react'

// Musica di sottofondo del BetOne Casino', generata dal telefono (Web Audio): nessun file da scaricare.
// Uno stile per gioco: 'slot' lounge jazz, 'crazy' chill tropicale, 'aviat' lo-fi arioso, 'bj' jazz notturno da tavolo verde.
// Sequencer con anticipo (si programmano le note 0,15 s prima): 4 battute di accordi in loop, con piccole
// variazioni casuali della melodia a ogni giro. Volume basso, sotto gli effetti delle vincite.

export type Stile = 'slot' | 'crazy' | 'aviat' | 'bj'

type Brano = {
  bpm: number
  accordi: number[][]          // note MIDI per battuta (4 battute)
  bassi: number[]              // fondamentale per battuta
  scala: number[]              // note MIDI per la melodia
  swing: number                // 0 = dritto, 0.15-0.3 = swing sulle sedicesime
}

const BRANI: Record<Stile, Brano> = {
  // Dm9 - G13 - Cmaj9 - A7(b9)
  slot: { bpm: 86, swing: 0.22, accordi: [[53, 57, 60, 64], [53, 59, 64, 65], [52, 55, 59, 62], [55, 58, 61, 64]], bassi: [38, 43, 36, 45], scala: [62, 64, 65, 67, 69, 72, 74, 76] },
  // Fmaj7 - G6 - Em7 - Am7
  crazy: { bpm: 100, swing: 0.08, accordi: [[57, 60, 64, 65], [55, 59, 62, 64], [55, 59, 62, 64], [55, 57, 60, 64]], bassi: [41, 43, 40, 45], scala: [69, 72, 74, 76, 79, 81, 84] },
  // Ebmaj7 - Cm9 - Abmaj7 - Bbsus
  // Am9 - D9 - Gmaj9 - E7(b9): jazz notturno, piano e contrabbasso che cammina, piatto ride
  bj: { bpm: 92, swing: 0.25, accordi: [[55, 59, 60, 64], [54, 57, 60, 64], [54, 57, 59, 62], [56, 59, 62, 65]], bassi: [45, 38, 43, 40], scala: [69, 71, 72, 74, 76, 79, 81] },
  aviat: { bpm: 74, swing: 0.12, accordi: [[55, 58, 62, 63], [55, 58, 62, 63], [55, 60, 63, 67], [53, 58, 60, 65]], bassi: [39, 36, 44, 46], scala: [63, 65, 67, 70, 72, 75, 77, 79] },
}

const freq = (m: number) => 440 * Math.pow(2, (m - 69) / 12)

class Motore {
  ctx: AudioContext
  bus: AudioNode
  uscita: GainNode
  riverbero: ConvolverNode
  rumore: AudioBuffer
  stile: Stile
  passo = 0
  prossima = 0
  timer = 0
  variazione: number[] = []

  constructor(stile: Stile) {
    try { (navigator as Navigator & { audioSession?: { type: string } }).audioSession!.type = 'playback' } catch { /* non supportato */ }
    this.ctx = new (window.AudioContext ?? (window as unknown as { webkitAudioContext: typeof AudioContext }).webkitAudioContext)()
    this.stile = stile
    const c = this.ctx
    // Catena: strumenti -> filtro morbido -> volume generale; in parallelo un riverbero corto per dare spazio.
    const filtro = c.createBiquadFilter(); filtro.type = 'lowpass'; filtro.frequency.value = stile === 'aviat' ? 2600 : 4200
    this.uscita = c.createGain(); this.uscita.gain.value = 0
    this.riverbero = c.createConvolver(); this.riverbero.buffer = this.impulso(2.2)
    const umido = c.createGain(); umido.gain.value = stile === 'aviat' ? 0.45 : 0.25
    filtro.connect(this.uscita); filtro.connect(this.riverbero); this.riverbero.connect(umido); umido.connect(this.uscita)
    this.uscita.connect(c.destination)
    this.bus = filtro
    this.rumore = c.createBuffer(1, c.sampleRate, c.sampleRate)
    const d = this.rumore.getChannelData(0); for (let i = 0; i < d.length; i++) d[i] = Math.random() * 2 - 1
    this.nuovaVariazione()
  }

  impulso(sec: number) {
    const c = this.ctx, n = Math.floor(c.sampleRate * sec), b = c.createBuffer(2, n, c.sampleRate)
    for (let ch = 0; ch < 2; ch++) { const d = b.getChannelData(ch); for (let i = 0; i < n; i++) d[i] = (Math.random() * 2 - 1) * Math.pow(1 - i / n, 3) }
    return b
  }
  nuovaVariazione() { this.variazione = Array.from({ length: 64 }, () => Math.random()) }

  avvia() {
    if (this.timer) return
    const c = this.ctx
    if (c.state !== 'running') void c.resume()
    this.prossima = c.currentTime + 0.1
    this.uscita.gain.cancelScheduledValues(c.currentTime)
    this.uscita.gain.setTargetAtTime(0.11, c.currentTime, 0.8)   // entra piano
    this.timer = window.setInterval(() => this.programma(), 25)
  }
  ferma() {
    const c = this.ctx
    this.uscita.gain.setTargetAtTime(0, c.currentTime, 0.3)
    window.clearInterval(this.timer); this.timer = 0
  }
  chiudi() { this.ferma(); window.setTimeout(() => { void this.ctx.close() }, 1200) }

  programma() {
    const b = BRANI[this.stile], sedicesimo = 60 / b.bpm / 4
    while (this.prossima < this.ctx.currentTime + 0.15) {
      const s = this.passo % 64, battuta = Math.floor(s / 16), nel = s % 16
      const t = this.prossima + (nel % 2 === 1 ? b.swing * sedicesimo : 0)
      this.suona(b, battuta, nel, s, t, sedicesimo)
      this.prossima += sedicesimo; this.passo++
      if (this.passo % 64 === 0) this.nuovaVariazione()
    }
  }

  suona(b: Brano, battuta: number, nel: number, s: number, t: number, sed: number) {
    const acc = b.accordi[battuta], basso = b.bassi[battuta], v = this.variazione[s]
    if (this.stile === 'slot') {
      // Piano elettrico sugli accordi (1 e il "e" del 3), contrabbasso a semiminime, spazzole.
      if (nel === 0 || nel === 10) acc.forEach((m, i) => this.epiano(freq(m), t + i * 0.012, sed * (nel === 0 ? 9 : 5), 0.05))
      if (nel % 4 === 0) this.basso(freq(nel === 12 && v > 0.5 ? basso + 7 : basso), t, sed * 3.4, 0.16)
      if (nel % 4 === 2 || (nel % 2 === 1 && v > 0.7)) this.spazzola(t, nel % 4 === 2 ? 0.05 : 0.025)
      if (nel === 4 || nel === 12) this.spazzola(t, 0.035, 0.18)
      if ((nel === 6 || nel === 14 || nel === 3) && v > 0.55) this.epiano(freq(b.scala[Math.floor(v * 97) % b.scala.length]), t, sed * 3, 0.04)
    } else if (this.stile === 'bj') {
      // Piano a "comping" in levare, contrabbasso che cammina sui quarti, ride swing e rim leggero.
      if (nel === 2 || nel === 7 || (nel === 11 && v > 0.4)) acc.forEach((m, i) => this.epiano(freq(m), t + i * 0.01, sed * 2.5, 0.038))
      if (nel % 4 === 0) {
        const passo = [0, 3, 7, 10][nel / 4] + (v > 0.6 ? 2 : 0)
        this.basso(freq(basso + passo - (nel === 12 && v > 0.5 ? 1 : 0)), t, sed * 3.6, 0.17)
      }
      if (nel % 4 === 0 || nel % 4 === 3) this.colpoRumore(t, nel % 4 === 0 ? 0.03 : 0.018, 'highpass', 9000, 0.22)
      if (nel === 4 || nel === 12) this.rim(t, 0.03)
      if ((nel === 1 || nel === 9 || nel === 14) && v > 0.62) this.epiano(freq(b.scala[Math.floor(v * 79) % b.scala.length]), t, sed * 3, 0.04)
    } else if (this.stile === 'crazy') {
      // Marimba in arpeggio, cassa morbida sui quarti, charleston in levare, basso pulsante.
      if (nel % 2 === 0) { const m = acc[(nel / 2 + battuta) % acc.length] + (nel % 8 === 6 ? 12 : 0); this.marimba(freq(m), t, 0.045) }
      if (nel % 4 === 0) this.cassa(t, 0.22)
      if (nel % 4 === 2) this.charleston(t, 0.04)
      if (nel === 4 || nel === 12) this.rim(t, 0.05)
      if (nel === 0 || nel === 6 || nel === 10) this.basso(freq(basso + (nel === 10 && v > 0.5 ? 12 : 0)), t, sed * 1.6, 0.14)
      if ((nel === 3 || nel === 11 || nel === 15) && v > 0.6) this.marimba(freq(b.scala[Math.floor(v * 89) % b.scala.length]), t, 0.04)
    } else {
      // Tappeto lento su ogni battuta, basso lungo, melodia rada, cassa e charleston lo-fi a basso volume.
      if (nel === 0) { acc.forEach((m) => this.tappeto(freq(m), t, sed * 16, 0.035)); this.basso(freq(basso), t, sed * 12, 0.13) }
      if (nel === 0 || nel === 10) this.cassa(t, 0.13)
      if (nel === 4 || nel === 12) this.rim(t, 0.03)
      if (nel % 2 === 0) this.charleston(t, nel % 4 === 2 ? 0.025 : 0.012)
      if ((nel === 2 || nel === 7 || nel === 11) && v > 0.5) this.epiano(freq(b.scala[Math.floor(v * 83) % b.scala.length]), t, sed * 6, 0.035)
      if (v > 0.93) this.crepitio(t)
    }
  }

  inviluppo(g: GainNode, t: number, attacco: number, picco: number, durata: number, rilascio = 0.3) {
    g.gain.setValueAtTime(0.0001, t)
    g.gain.exponentialRampToValueAtTime(picco, t + attacco)
    g.gain.exponentialRampToValueAtTime(Math.max(0.0001, picco * 0.35), t + attacco + durata * 0.5)
    g.gain.exponentialRampToValueAtTime(0.0001, t + durata + rilascio)
  }
  osc(tipo: OscillatorType, f: number, t: number, fine: number, g: GainNode) { const o = this.ctx.createOscillator(); o.type = tipo; o.frequency.value = f; o.connect(g); o.start(t); o.stop(fine) }

  epiano(f: number, t: number, dur: number, vol: number) {
    const g = this.ctx.createGain(); g.connect(this.bus)
    this.inviluppo(g, t, 0.008, vol, dur, 0.5)
    this.osc('sine', f, t, t + dur + 0.6, g)
    const g2 = this.ctx.createGain(); g2.connect(this.bus); this.inviluppo(g2, t, 0.004, vol * 0.25, 0.15, 0.1)
    this.osc('sine', f * 4, t, t + 0.3, g2)   // "campanella" del piano elettrico
  }
  tappeto(f: number, t: number, dur: number, vol: number) {
    const c = this.ctx, g = c.createGain(), lp = c.createBiquadFilter(); lp.type = 'lowpass'; lp.frequency.value = 900
    g.connect(lp); lp.connect(this.bus)
    g.gain.setValueAtTime(0.0001, t); g.gain.exponentialRampToValueAtTime(vol, t + dur * 0.3); g.gain.exponentialRampToValueAtTime(0.0001, t + dur * 1.05)
    this.osc('sawtooth', f, t, t + dur * 1.1, g); this.osc('sawtooth', f * 1.004, t, t + dur * 1.1, g)
  }
  basso(f: number, t: number, dur: number, vol: number) {
    const g = this.ctx.createGain(); g.connect(this.bus); this.inviluppo(g, t, 0.01, vol, dur, 0.12)
    this.osc('sine', f, t, t + dur + 0.2, g)
    const g2 = this.ctx.createGain(); g2.connect(this.bus); this.inviluppo(g2, t, 0.01, vol * 0.3, dur * 0.5, 0.05); this.osc('triangle', f * 2, t, t + dur, g2)
  }
  marimba(f: number, t: number, vol: number) {
    const g = this.ctx.createGain(); g.connect(this.bus); this.inviluppo(g, t, 0.003, vol, 0.25, 0.15)
    this.osc('sine', f, t, t + 0.5, g)
    const g2 = this.ctx.createGain(); g2.connect(this.bus); this.inviluppo(g2, t, 0.002, vol * 0.4, 0.05, 0.03); this.osc('sine', f * 3.99, t, t + 0.12, g2)
  }
  cassa(t: number, vol: number) {
    const c = this.ctx, o = c.createOscillator(), g = c.createGain()
    o.frequency.setValueAtTime(110, t); o.frequency.exponentialRampToValueAtTime(42, t + 0.18)
    g.gain.setValueAtTime(vol, t); g.gain.exponentialRampToValueAtTime(0.0001, t + 0.32)
    o.connect(g); g.connect(this.uscita); o.start(t); o.stop(t + 0.35)
  }
  colpoRumore(t: number, vol: number, tipo: BiquadFilterType, f: number, dur: number, q = 1) {
    const c = this.ctx, s = c.createBufferSource(), fl = c.createBiquadFilter(), g = c.createGain()
    s.buffer = this.rumore; fl.type = tipo; fl.frequency.value = f; fl.Q.value = q
    g.gain.setValueAtTime(vol, t); g.gain.exponentialRampToValueAtTime(0.0001, t + dur)
    s.connect(fl); fl.connect(g); g.connect(this.bus); s.start(t, Math.random() * 0.5); s.stop(t + dur + 0.02)
  }
  charleston(t: number, vol: number) { this.colpoRumore(t, vol, 'highpass', 7500, 0.05) }
  spazzola(t: number, vol: number, dur = 0.09) { this.colpoRumore(t, vol, 'bandpass', 5200, dur, 0.7) }
  rim(t: number, vol: number) { this.colpoRumore(t, vol, 'bandpass', 1900, 0.06, 3) }
  crepitio(t: number) { this.colpoRumore(t, 0.02, 'highpass', 3000, 0.012) }
}

// Musica del gioco aperto: parte al primo tocco (regola di iPhone), si ferma uscendo dal gioco, spegnendo l'audio
// o mettendo l'app in secondo piano. Restituisce la funzione da chiamare nel tocco per sbloccarla.
export function useMusica(stile: Stile, attiva: boolean) {
  const motore = useRef<Motore | null>(null)
  const voluta = useRef(attiva); voluta.current = attiva

  useEffect(() => {
    const visibile = () => {
      const m = motore.current; if (!m) return
      if (document.hidden) m.ferma(); else if (voluta.current) m.avvia()
    }
    document.addEventListener('visibilitychange', visibile)
    return () => { document.removeEventListener('visibilitychange', visibile); motore.current?.chiudi(); motore.current = null }
  }, [])

  useEffect(() => {
    const m = motore.current
    if (!m) return
    if (attiva && !document.hidden) m.avvia(); else m.ferma()
  }, [attiva])

  return () => {
    if (!voluta.current) return
    try {
      if (!motore.current) motore.current = new Motore(stile)
      if (!document.hidden) motore.current.avvia()
    } catch { /* audio non disponibile */ }
  }
}
