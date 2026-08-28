import { useEffect, useMemo, useState } from 'react'
import { supabase } from '../lib/supabase'
import { cognome } from '../lib/nomi'
import { formatCountdown, useOraCorrente } from '../lib/countdown'
import type { League, Membership, SceltaDraft } from '../types'
import { GameNav, type GameView } from './GameNav'
import { SeasonState } from './SeasonUI'
import { Crest } from './Crest'
import { firmaFoto } from './RosaElenco'
import { useSeasonData } from '../lib/useSeasonData'

type Props = { membership: Membership; onNavigate: (view: GameView) => void }

const ETICHETTA_FINESTRA: Record<SceltaDraft['finestra'], string> = { on: 'ON-Season', off: 'OFF-Season' }
const ETICHETTA_STATO: Record<SceltaDraft['stato'], string> = {
  futura: 'Posizione da determinare',
  determinata: 'Pronta',
  usata: 'Usata',
  vuota: 'Andata a vuoto',
}

type GiocatorePool = { id: number; nome: string; posizioni: string[]; overall: number; eta: number; foto_url: string | null; ingaggio_teorico: number }
type FinestraScelte = {
  league_id: number; stagione: number; finestra: SceltaDraft['finestra']
  svelata_il: string; estrazione_il: string | null; risolta_il: string | null
}
type Preferenza = { scelta_id: number; ordine: number; player_id: number }

export function Scelte({ membership, onNavigate }: Props) {
  const league = membership.league as League
  const dati = useSeasonData(membership)
  const adesso = useOraCorrente()
  const [scelte, setScelte] = useState<SceltaDraft[]>([])
  const [finestre, setFinestre] = useState<FinestraScelte[]>([])
  const [preferenze, setPreferenze] = useState<Preferenza[]>([])
  const [pool, setPool] = useState<Map<string, GiocatorePool[]>>(new Map())
  const [foto, setFoto] = useState<Map<number, string>>(new Map())
  const [loading, setLoading] = useState(true)
  const [errore, setErrore] = useState<string | null>(null)
  const [esito, setEsito] = useState<string | null>(null)
  const [salvataggioInCorso, setSalvataggioInCorso] = useState<number | null>(null)
  // Bozze locali: scelta_id -> lista ordinata di player_id, inizializzate
  // dalle preferenze già salvate e poi editate liberamente finché non si
  // preme "Salva" (che sostituisce integralmente la lista sul server).
  const [bozze, setBozze] = useState<Record<number, number[]>>({})

  const carica = async () => {
    setLoading(true)
    const [sceltaRes, finestreRes, prefRes] = await Promise.all([
      supabase.from('scelte_draft').select('*').eq('league_id', league.id).order('stagione').order('finestra'),
      supabase.from('finestre_scelte').select('*').eq('league_id', league.id),
      supabase.from('scelte_preferenze').select('scelta_id, ordine, player_id').order('ordine'),
    ])
    const primoErrore = sceltaRes.error ?? finestreRes.error ?? prefRes.error
    if (primoErrore) { setErrore(primoErrore.message); setLoading(false); return }
    setScelte((sceltaRes.data ?? []) as SceltaDraft[])
    setFinestre((finestreRes.data ?? []) as FinestraScelte[])
    setPreferenze((prefRes.data ?? []) as Preferenza[])
    setLoading(false)
  }

  useEffect(() => { void carica() }, [league.id])

  const teamById = useMemo(() => new Map(dati.teams.map((t) => [t.id, t])), [dati.teams])
  const ordineFinestra: Record<SceltaDraft['finestra'], number> = { on: 0, off: 1 }
  const mieScelte = useMemo(
    () => scelte.filter((s) => s.team_proprietario_id === membership.id)
      .sort((a, b) => a.stagione - b.stagione || ordineFinestra[a.finestra] - ordineFinestra[b.finestra]),
    [scelte, membership.id],
  )

  // Le finestre "attive" sono quelle svelate e non ancora risolte: e' li'
  // che si possono ancora comporre le preferenze. Di solito una sola alla
  // volta, ma niente impedisce (per un attimo) di averne due.
  const finestreAttive = useMemo(
    () => finestre.filter((f) => f.risolta_il == null)
      .sort((a, b) => a.stagione - b.stagione || ordineFinestra[a.finestra] - ordineFinestra[b.finestra]),
    [finestre],
  )

  // Il pool non è "tutti gli svincolati overall>75": è l'estrazione dedicata
  // alla finestra (private.estrai_pool_scelte, 10 per ruolo), stabile finché
  // la finestra non si risolve.
  useEffect(() => {
    let vivo = true
    async function caricaPool() {
      const mappa = new Map<string, GiocatorePool[]>()
      await Promise.all(finestreAttive.map(async (f) => {
        const chiave = `${f.stagione}-${f.finestra}`
        const { data, error } = await supabase.from('scelte_pool')
          .select('ingaggio_teorico, players(id, nome, posizioni, overall, eta, foto_url)')
          .eq('league_id', league.id).eq('stagione', f.stagione).eq('finestra', f.finestra)
        if (error) { if (vivo) setErrore(error.message); return }
        mappa.set(chiave, (data ?? [])
          .map((r) => {
            const p = r.players as unknown as Omit<GiocatorePool, 'ingaggio_teorico'> | null
            return p ? { ...p, ingaggio_teorico: r.ingaggio_teorico as number } : null
          })
          .filter((g): g is GiocatorePool => g != null)
          .sort((a, b) => b.overall - a.overall))
      }))
      if (vivo) setPool(mappa)
    }
    void caricaPool()
    return () => { vivo = false }
  }, [league.id, finestreAttive.map((f) => `${f.stagione}-${f.finestra}`).join(',')])

  // Stesse firme del modale del draft e della rosa: senza, il pool
  // mostrerebbe sempre gli iniziali al posto delle foto.
  useEffect(() => {
    let vivo = true
    async function firma() {
      const tutti = [...pool.values()].flat()
      const voci = await Promise.all(tutti.map(async (g) => [g.id, await firmaFoto(g.foto_url)] as const))
      if (vivo) setFoto(new Map(voci.filter((v): v is [number, string] => Boolean(v[1]))))
    }
    void firma()
    return () => { vivo = false }
  }, [pool])

  // Inizializza le bozze dalle preferenze già salvate, una sola volta per
  // scelta (non deve sovrascrivere cio' che l'utente sta ancora editando).
  useEffect(() => {
    setBozze((correnti) => {
      const nuove = { ...correnti }
      for (const s of mieScelte) {
        if (nuove[s.id] !== undefined) continue
        nuove[s.id] = preferenze.filter((p) => p.scelta_id === s.id).sort((a, b) => a.ordine - b.ordine).map((p) => p.player_id)
      }
      return nuove
    })
  }, [mieScelte, preferenze])

  async function salvaPreferenze(sceltaId: number) {
    setSalvataggioInCorso(sceltaId)
    setEsito(null)
    const { error } = await supabase.rpc('salva_preferenze_scelta', {
      p_scelta_id: sceltaId, p_player_ids: bozze[sceltaId] ?? [],
    })
    setEsito(error ? error.message : 'Preferenze salvate.')
    if (!error) await carica()
    setSalvataggioInCorso(null)
  }

  return <main className="app-shell season-shell">
    <GameNav league={league} active="scelte" onNavigate={onNavigate} />
    <header className="topbar season-topbar">
      <div className="brand-lockup brand-lockup--dark"><img src="/specialone-mark.svg" alt="" /><span>SpecialOne</span></div>
      <span>Draft</span>
    </header>
    <div className="season-page season-page--narrow">
      <section className="season-title-row">
        <div>
          <p className="kicker">{league.nome}</p>
          <h1>Draft.</h1>
          <p>
            Ogni ticket rappresenta una scelta in un mercato ON-Season o OFF-Season futuro. Lo
            stemma è sempre quello della squadra che l'ha guadagnata con il proprio piazzamento
            nei playoff — non cambia se la scelta viene scambiata, solo il proprietario cambia.
          </p>
        </div>
        <div className="season-total">
          <strong>{mieScelte.length}</strong>
          <span>{mieScelte.length === 1 ? 'scelta' : 'scelte'}</span>
        </div>
      </section>

      {esito && <p className="notice">{esito}</p>}

      {(dati.loading || loading || dati.error || errore) && <SeasonState loading={dati.loading || loading} error={dati.error ?? errore} onRetry={dati.reload} />}

      {!dati.loading && !loading && !dati.error && !errore && <>

      {finestreAttive.length === 0 && <section className="offseason-card">
        <p className="kicker">Nessuna finestra aperta</p>
        <h2>Prossima finestra non ancora iniziata</h2>
        <p>L'ON-Season si apre a metà stagione, l'OFF-Season durante l'ultima fase dell'off-season.</p>
      </section>}

      {finestreAttive.map((f) => {
        const chiave = `${f.stagione}-${f.finestra}`
        const label = `${ETICHETTA_FINESTRA[f.finestra]} ${f.stagione}`
        const scadenza = f.estrazione_il ? new Date(f.estrazione_il) : null
        const congelate = scadenza != null && adesso >= scadenza.getTime() - 60 * 60 * 1000
        const poolFinestra = pool.get(chiave) ?? []
        const mieScelteFinestra = mieScelte.filter((s) => s.stagione === f.stagione && s.finestra === f.finestra && s.stato === 'determinata')

        return <section className="offseason-card offseason-card--accent" key={chiave}>
          <p className="kicker">Finestra aperta</p>
          <h2>{label}</h2>
          {scadenza
            ? <>
                <p className="scelte-countdown">{formatCountdown(Math.max(0, scadenza.getTime() - adesso))}</p>
                <p>{congelate
                  ? 'Le preferenze sono congelate: mancano meno di un\'ora all\'estrazione.'
                  : 'Le preferenze restano modificabili fino a un\'ora prima dell\'estrazione.'}</p>
              </>
            : <p>La scadenza non è ancora fissata (l'off-season non è ancora iniziata): le preferenze restano modificabili liberamente.</p>}

          {mieScelteFinestra.length === 0
            ? <p className="season-empty">Non hai scelte pronte in questa finestra.</p>
            : mieScelteFinestra.map((s) => {
                const bozza = bozze[s.id] ?? []
                const salvate = preferenze.filter((p) => p.scelta_id === s.id).sort((a, b) => a.ordine - b.ordine).map((p) => p.player_id)
                const modificata = JSON.stringify(bozza) !== JSON.stringify(salvate)
                function giocatore(id: number) { return poolFinestra.find((g) => g.id === id) }
                function aggiungi(id: number) {
                  setBozze((correnti) => ({ ...correnti, [s.id]: [...(correnti[s.id] ?? []), id] }))
                }
                function rimuovi(indice: number) {
                  setBozze((correnti) => ({ ...correnti, [s.id]: (correnti[s.id] ?? []).filter((_, i) => i !== indice) }))
                }
                function sposta(indice: number, delta: number) {
                  setBozze((correnti) => {
                    const lista = [...(correnti[s.id] ?? [])]
                    const target = indice + delta
                    if (target < 0 || target >= lista.length) return correnti
                    ;[lista[indice], lista[target]] = [lista[target], lista[indice]]
                    return { ...correnti, [s.id]: lista }
                  })
                }
                return <div className="scelte-preferenze" key={s.id}>
                  <div className="scelte-preferenze__testa">
                    <strong>{s.posizione}ª scelta</strong>
                    <span>fino a {s.posizione} {s.posizione === 1 ? 'preferenza' : 'preferenze'}</span>
                  </div>

                  <ol className="scelte-preferenze__lista">
                    {bozza.length === 0
                      ? <li className="scelte-preferenze__vuota">Nessuna preferenza indicata: se nessuno viene esercitato, resti senza giocatore.</li>
                      : bozza.map((id, indice) => {
                          const g = giocatore(id)
                          return <li key={id}>
                            <b>{indice + 1}</b>
                            <span>{g ? `${cognome(g.nome)} · ${g.overall}` : `#${id}`}</span>
                            <div className="scelte-preferenze__azioni">
                              <button type="button" disabled={congelate || indice === 0} onClick={() => sposta(indice, -1)} aria-label="Sposta su">↑</button>
                              <button type="button" disabled={congelate || indice === bozza.length - 1} onClick={() => sposta(indice, 1)} aria-label="Sposta giù">↓</button>
                              <button type="button" disabled={congelate} onClick={() => rimuovi(indice)} aria-label="Rimuovi">✕</button>
                            </div>
                          </li>
                        })}
                  </ol>

                  {!congelate && bozza.length < (s.posizione ?? 0) && <details className="scelte-preferenze__aggiungi">
                    <summary>Aggiungi dal pool ({poolFinestra.length - bozza.length} disponibili)</summary>
                    <ul className="scelte-pool scelte-pool--scelta">
                      {poolFinestra.filter((g) => !bozza.includes(g.id)).map((g) => <li key={g.id}>
                        <div className="modale-rosa__foto">
                          {foto.get(g.id) ? <img src={foto.get(g.id)} alt="" loading="lazy" /> : <span aria-hidden="true">{g.nome.charAt(0)}</span>}
                        </div>
                        <b>{g.overall}</b>
                        <span><strong>{cognome(g.nome)}</strong><small>{(g.posizioni ?? []).join(' / ')} · {g.eta} anni · {(g.ingaggio_teorico / 1_000_000).toFixed(1)} M€</small></span>
                        <button type="button" className="button button--secondary" onClick={() => aggiungi(g.id)}>Aggiungi</button>
                      </li>)}
                    </ul>
                  </details>}

                  <button className="button button--primary" type="button"
                    disabled={congelate || !modificata || salvataggioInCorso === s.id}
                    onClick={() => void salvaPreferenze(s.id)}>
                    {salvataggioInCorso === s.id ? 'Salvo…' : 'Salva preferenze'}
                  </button>
                </div>
              })}
        </section>
      })}

      <section className="mercato-blocco">
        <div className="sezione-testa">
          <div><p className="kicker">Le mie scelte</p><h2>{mieScelte.length} ticket</h2></div>
        </div>
        {mieScelte.length === 0
          ? <p className="season-empty">Nessuna scelta ancora assegnata a questa squadra.</p>
          : <ul className="scelte-lista">
              {mieScelte.map((s) => {
                const origine = teamById.get(s.team_origine_id)
                return <li className={`scelta-ticket scelta-ticket--${s.finestra}`} key={s.id}>
                  <div className="scelta-ticket__taglio" aria-hidden="true">
                    <span className="scelta-ticket__stagione">S{s.stagione}</span>
                    <span className={`scelta-ticket__finestra scelta-ticket__finestra--${s.finestra}`}>{ETICHETTA_FINESTRA[s.finestra].toUpperCase()}</span>
                  </div>
                  <div className="scelta-ticket__corpo">
                    <div className="scelta-ticket__origine">
                      <Crest value={origine?.stemma_url ?? null} imageUrl={origine ? dati.crestUrlByTeamId.get(origine.id) : undefined} />
                      <small>{origine?.nome ?? 'Squadra sconosciuta'}</small>
                    </div>
                    <div className="scelta-ticket__dettagli">
                      <strong>{s.posizione != null ? `${s.posizione}ª scelta` : 'Posizione da determinare'}</strong>
                      <span className={`scelta-ticket__stato scelta-ticket__stato--${s.stato}`}>{ETICHETTA_STATO[s.stato]}</span>
                    </div>
                  </div>
                </li>
              })}
            </ul>}
      </section>
      </>}
    </div>
  </main>
}
