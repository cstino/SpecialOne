import { useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'
import { faseLive, mmss, useScelteLive, type ScelteLiveStato } from '../lib/useScelteLive'
import type { Team } from '../types'
import type { League, Membership } from '../types'
import { DraftScelteLive } from './DraftScelteLive'
import { SorteggioConferenze } from './SorteggioConferenze'

type Props = { membership: Membership; onFine: () => void }
type DemoOffseason = { squadre: Team[]; sorteggio: (adesso: number) => NonNullable<Parameters<typeof SorteggioConferenze>[0]['demo']> }
type ViewProps = Props & { stato: ScelteLiveStato | null | undefined; adesso: number; demo?: DemoOffseason }
type Vista = 'menu' | 'draft' | 'sorteggio'

// Dopo la chiusura dell'off-season, con le conferenze: due dirette una dopo
// l'altra. Prima il draft dei giocatori, poi il sorteggio Eastern/Western. Il menu ha
// un pulsante per ciascuna (il secondo compare quando il draft e' finito) e da
// ognuna si esce e si rientra: tutto e' sincronizzato sull'orologio del server.
export function OffseasonLive({ membership, onFine }: Props) {
  const league = membership.league as League
  const { stato, adesso } = useScelteLive(league.id)
  return <OffseasonLiveView membership={membership} onFine={onFine} stato={stato} adesso={adesso} />
}

// La vista non sa da dove arrivano i dati: dal database (OffseasonLive) o dall'anteprima fittizia.
export function OffseasonLiveView({ membership, onFine, stato, adesso, demo }: ViewProps) {
  const league = membership.league as League
  const [vista, setVista] = useState<Vista>('menu')

  // Se si resta nel menu o nel draft quando la stagione parte, si ricarica la lega.
  const draftFinito = Boolean(stato) && adesso >= Date.parse(stato!.fine_il)
  useEffect(() => {
    if (demo || !draftFinito || vista === 'sorteggio') return
    let vivo = true
    const timer = window.setInterval(async () => {
      const { data } = await supabase.from('leagues').select('fase_carriera').eq('id', league.id).single()
      if (vivo && data && data.fase_carriera !== 'sorteggio') onFine()
    }, 5000)
    return () => { vivo = false; window.clearInterval(timer) }
  }, [draftFinito, vista, league.id, onFine, demo])

  if (stato === undefined) {
    return <main className="sorteggio"><p className="sorteggio__attesa" style={{ textAlign: 'center', marginTop: '30vh' }}>Preparo la diretta…</p></main>
  }
  // Nessun draft in diretta in questa lega: solo il sorteggio.
  if (stato === null) return <SorteggioConferenze membership={membership} onFine={onFine} />

  const fase = faseLive(stato, adesso)
  const sorteggioInizio = stato.sorteggio_il ? Date.parse(stato.sorteggio_il) : null
  const secondiSorteggio = sorteggioInizio !== null ? (sorteggioInizio - adesso) / 1000 : null

  if (vista === 'draft') {
    return <DraftScelteLive membership={membership} stato={stato} adesso={adesso} onMenu={() => setVista('menu')}
      onVaiSorteggio={draftFinito ? () => setVista('sorteggio') : null} squadreDemo={demo?.squadre} />
  }
  if (vista === 'sorteggio') {
    return <SorteggioConferenze membership={membership} onFine={onFine} onMenu={() => setVista('menu')} demo={demo?.sorteggio(adesso)} />
  }

  const inDirettaDraft = fase.stadio === 'intro' || fase.stadio === 'reveal'
  const inDirettaSorteggio = draftFinito && secondiSorteggio !== null && secondiSorteggio <= 0
  const nomeFinestra = `${stato.finestra === 'off' ? 'OFF-Season' : 'ON-Season'} ${stato.stagione}`

  return <main className="sorteggio dlive-menu">
    <header className="sorteggio__testa">
      <div className="brand-lockup brand-lockup--dark"><img src="/specialone-mark.svg" alt="" /><span>SpecialOne</span></div>
      <span>{league.nome} · Stagione {league.stagione_corrente}</span>
    </header>

    <section className="dlive-menu__titolo">
      <p className="sorteggio__occhiello">L'off-season è chiusa</p>
      <h1>Si riparte, tutti insieme.</h1>
      <p>Prima il draft dei giocatori, poi il sorteggio delle conference.</p>
    </section>

    <section className="dlive-menu__carte">
      <button type="button" className={`dlive-menu__carta${inDirettaDraft ? ' is-live' : ''}`} onClick={() => setVista('draft')}>
        <span className="dlive-menu__stato">
          {fase.stadio === 'prima' && <>Parte tra <b>{mmss(fase.rimasti)}</b></>}
          {inDirettaDraft && <><i className="dlive-menu__punto" />In diretta · scelta {fase.n} di {stato.totale}</>}
          {fase.stadio === 'fine' && 'Concluso · rivedi il riepilogo'}
        </span>
        <strong>Draft giocatori</strong>
        <small>{nomeFinestra} · {stato.totale} scelte, una ogni 30 secondi</small>
        <span className="dlive-menu__vai">Vai al draft {nomeFinestra}</span>
      </button>

      {draftFinito
        ? <button type="button" className={`dlive-menu__carta dlive-menu__carta--conf${inDirettaSorteggio ? ' is-live' : ''}`} onClick={() => setVista('sorteggio')}>
          <span className="dlive-menu__stato">
            {!inDirettaSorteggio && secondiSorteggio !== null && <>Parte tra <b>{mmss(secondiSorteggio)}</b></>}
            {inDirettaSorteggio && <><i className="dlive-menu__punto" />In diretta</>}
          </span>
          <strong>Sorteggio conference</strong>
          <small>Eastern e Western, una squadra ogni 20 secondi</small>
          <span className="dlive-menu__vai">Vai al sorteggio delle conference</span>
        </button>
        : <div className="dlive-menu__carta dlive-menu__carta--bloccata" aria-hidden="true">
          <span className="dlive-menu__stato">Dopo il draft</span>
          <strong>Sorteggio conference</strong>
          <small>Compare quando il draft è concluso</small>
        </div>}
    </section>
  </main>
}
