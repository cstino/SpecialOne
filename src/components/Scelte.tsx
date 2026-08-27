import { useEffect, useMemo, useState } from 'react'
import { supabase } from '../lib/supabase'
import type { League, Membership, SceltaDraft } from '../types'
import { GameNav, type GameView } from './GameNav'
import { SeasonState } from './SeasonUI'
import { Crest } from './Crest'
import { useSeasonData } from '../lib/useSeasonData'

type Props = { membership: Membership; onNavigate: (view: GameView) => void }

const ETICHETTA_FINESTRA: Record<SceltaDraft['finestra'], string> = { on: 'ON-Season', off: 'OFF-Season' }
const ETICHETTA_STATO: Record<SceltaDraft['stato'], string> = {
  futura: 'Posizione da determinare',
  determinata: 'Pronta',
  usata: 'Usata',
  vuota: 'Andata a vuoto',
}

export function Scelte({ membership, onNavigate }: Props) {
  const league = membership.league as League
  const dati = useSeasonData(membership)
  const [scelte, setScelte] = useState<SceltaDraft[]>([])
  const [loading, setLoading] = useState(true)
  const [errore, setErrore] = useState<string | null>(null)

  useEffect(() => {
    let vivo = true
    async function carica() {
      setLoading(true)
      const { data, error } = await supabase.from('scelte_draft').select('*').eq('league_id', league.id)
        .order('stagione').order('finestra')
      if (!vivo) return
      if (error) { setErrore(error.message); setLoading(false); return }
      setScelte((data ?? []) as SceltaDraft[])
      setLoading(false)
    }
    void carica()
    return () => { vivo = false }
  }, [league.id])

  const teamById = useMemo(() => new Map(dati.teams.map((t) => [t.id, t])), [dati.teams])
  const mieScelte = useMemo(
    () => scelte.filter((s) => s.team_proprietario_id === membership.id)
      .sort((a, b) => a.stagione - b.stagione || a.finestra.localeCompare(b.finestra)),
    [scelte, membership.id],
  )

  return <main className="app-shell season-shell">
    <GameNav league={league} active="scelte" onNavigate={onNavigate} />
    <header className="topbar season-topbar">
      <div className="brand-lockup brand-lockup--dark"><img src="/specialone-mark.svg" alt="" /><span>SpecialOne</span></div>
      <span>Draft</span>
    </header>
    <div className="season-page season-page--narrow">
      <section className="help-heading">
        <p className="kicker">{league.nome}</p>
        <h1>Le tue scelte.</h1>
        <p>
          Ogni ticket rappresenta una scelta in un mercato ON-Season o OFF-Season futuro. Lo
          stemma è sempre quello della squadra che l'ha guadagnata con il proprio piazzamento
          nei playoff — non cambia se la scelta viene scambiata, solo il proprietario cambia.
        </p>
      </section>

      <section className="offseason-card">
        <p className="kicker">In arrivo</p>
        <h2>Pool giocatori e liste di preferenze</h2>
        <p>
          Questa pagina mostra per ora solo l'inventario delle scelte. Il pool dei giocatori
          per ogni finestra (overall &gt; 75), il countdown alla scadenza e la sezione per
          indicare le preferenze arrivano in un passo successivo.
        </p>
      </section>

      {(dati.loading || loading || dati.error || errore) && <SeasonState loading={dati.loading || loading} error={dati.error ?? errore} onRetry={dati.reload} />}

      {!dati.loading && !loading && !dati.error && !errore && <section className="mercato-blocco">
        <div className="sezione-testa">
          <div><p className="kicker">Le mie scelte</p><h2>{mieScelte.length} ticket</h2></div>
        </div>
        {mieScelte.length === 0
          ? <p className="season-empty">Nessuna scelta ancora assegnata a questa squadra.</p>
          : <ul className="scelte-lista">
              {mieScelte.map((s) => {
                const origine = teamById.get(s.team_origine_id)
                return <li className="scelta-ticket" key={s.id}>
                  <div className="scelta-ticket__origine">
                    <Crest value={origine?.stemma_url ?? null} imageUrl={origine ? dati.crestUrlByTeamId.get(origine.id) : undefined} />
                    <small>{origine?.nome ?? 'Squadra sconosciuta'}</small>
                  </div>
                  <div className="scelta-ticket__info">
                    <strong>S{s.stagione} · {ETICHETTA_FINESTRA[s.finestra]}</strong>
                    <span>{s.posizione != null ? `${s.posizione}ª scelta` : ETICHETTA_STATO[s.stato]}</span>
                  </div>
                  <div className={`scelta-ticket__stato scelta-ticket__stato--${s.stato}`}>{ETICHETTA_STATO[s.stato]}</div>
                </li>
              })}
            </ul>}
      </section>}
    </div>
  </main>
}
