import { useEffect, useMemo, useRef, useState } from 'react'
import type { Membership } from '../types'
import { DEMO_AVVIO_SORTEGGIO, DEMO_FINE, DEMO_FINE_DRAFT, MIA_DEMO, SQUADRE_DEMO, sorteggioDemo, statoDraftDemo } from '../lib/demoOffseason'
import { OffseasonLiveView } from './OffseasonLive'

// Anteprima FITTIZIA delle due dirette di fine off-season (draft dei giocatori e
// sorteggio delle conference). Si apre con ?anteprima=offseason; non scrive
// niente. Orologio virtuale: si puo' accelerare e saltare a un punto preciso.
const MEMBERSHIP_DEMO = { id: MIA_DEMO, league: { id: 0, nome: 'Serie F · anteprima', stagione_corrente: 2 } } as unknown as Membership
const SALTI: [string, number][] = [
  ['Inizio', 0], ['Draft: scelta 1', 10], ['Draft: metà', 10 + 8 * 30], ['Fine draft', DEMO_FINE_DRAFT - 3],
  ['Sorteggio: inizio', DEMO_AVVIO_SORTEGGIO - 5], ['Sorteggio: metà', DEMO_AVVIO_SORTEGGIO + 12 * 20], ['Fine', DEMO_FINE - 25],
]
const VELOCITA = [1, 5, 15]

export function AnteprimaOffseason() {
  const origine = useRef(Date.now()).current
  const riferimento = useRef({ virtuale: 0, reale: Date.now() })
  const [velocita, setVelocita] = useState(1)
  const [virtuale, setVirtuale] = useState(0)

  useEffect(() => {
    const timer = window.setInterval(() => {
      const r = riferimento.current
      setVirtuale(r.virtuale + ((Date.now() - r.reale) / 1000) * velocita)
    }, 200)
    return () => window.clearInterval(timer)
  }, [velocita])

  const vai = (secondi: number) => { riferimento.current = { virtuale: secondi, reale: Date.now() }; setVirtuale(secondi) }
  const cambiaVelocita = (v: number) => { riferimento.current = { virtuale, reale: Date.now() }; setVelocita(v) }

  const adesso = origine + virtuale * 1000
  const stato = useMemo(() => statoDraftDemo(origine, adesso), [origine, adesso])
  const demo = useMemo(() => ({ squadre: SQUADRE_DEMO, sorteggio: (a: number) => sorteggioDemo(origine, a) }), [origine])

  return <>
    <OffseasonLiveView membership={MEMBERSHIP_DEMO} onFine={() => vai(0)} stato={stato} adesso={adesso} demo={demo} />
    <nav className="anteprima" aria-label="Controlli dell'anteprima">
      <strong>Anteprima fittizia</strong>
      <div>
        {VELOCITA.map((v) => <button key={v} type="button" className={v === velocita ? 'is-attiva' : ''} onClick={() => cambiaVelocita(v)}>×{v}</button>)}
      </div>
      <div className="anteprima__salti">
        {SALTI.map(([nome, s]) => <button key={nome} type="button" onClick={() => vai(s)}>{nome}</button>)}
      </div>
      <a href="/">Esci</a>
    </nav>
  </>
}
