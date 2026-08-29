import { useEffect, useMemo, useState } from 'react'
import { supabase } from '../lib/supabase'
import { cognome } from '../lib/nomi'
import { formatCountdown, useOraCorrente } from '../lib/countdown'
import type { League, Membership, SceltaDraft } from '../types'
import { GameNav, type GameView } from './GameNav'
import { SeasonState } from './SeasonUI'
import { Crest } from './Crest'
import { firmaFoto } from './RosaElenco'
import { macroRuolo } from '../lib/ruoli'
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
type GiocatoreAssegnato = { nome: string; posizioni: string[]; overall: number; foto: string | null }
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
  const [giocatoriAssegnati, setGiocatoriAssegnati] = useState<Map<number, GiocatoreAssegnato>>(new Map())
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
  // Una volta risolta la finestra, il ticket "usata"/"vuota" ha esaurito il suo
  // scopo di asset scambiabile: sparisce da qui (badge e lista), ma la riga
  // resta in scelte_draft — è la fonte del riepilogo dell'ultima sessione più sotto.
  const mieScelte = useMemo(
    () => scelte.filter((s) => s.team_proprietario_id === membership.id && s.stato !== 'usata' && s.stato !== 'vuota')
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

  // L'ultima sessione conclusa: la finestra con la risoluzione più recente,
  // per mostrare chi ha preso chi anche dopo che i ticket "usata"/"vuota"
  // di quella finestra spariscono dalla lista "Le mie scelte" (v. sotto).
  const ultimaFinestraRisolta = useMemo(() => {
    const risolte = finestre.filter((f): f is FinestraScelte & { risolta_il: string } => f.risolta_il != null)
    if (risolte.length === 0) return null
    return risolte.reduce((a, b) => (new Date(a.risolta_il) > new Date(b.risolta_il) ? a : b))
  }, [finestre])

  const scelteUltimaSessione = useMemo(() => {
    if (!ultimaFinestraRisolta) return []
    return scelte.filter((s) => s.stagione === ultimaFinestraRisolta.stagione && s.finestra === ultimaFinestraRisolta.finestra
        && (s.stato === 'usata' || s.stato === 'vuota'))
      .sort((a, b) => (a.posizione ?? 0) - (b.posizione ?? 0))
  }, [scelte, ultimaFinestraRisolta])

  // Anagrafica dei giocatori assegnati nell'ultima sessione: player_instance_id
  // (fissato su scelte_draft alla risoluzione) -> player_id -> nome/foto/overall.
  useEffect(() => {
    let vivo = true
    async function carica() {
      const idIstanze = [...new Set(scelteUltimaSessione.map((s) => s.player_instance_id).filter((id): id is number => id != null))]
      if (idIstanze.length === 0) { setGiocatoriAssegnati(new Map()); return }
      const { data: istanze } = await supabase.from('player_instances').select('id, player_id').in('id', idIstanze)
      if (!vivo) return
      const idGiocatori = [...new Set((istanze ?? []).map((i) => i.player_id))]
      const { data: anagrafica } = idGiocatori.length
        ? await supabase.from('players').select('id, nome, posizioni, overall, foto_url').in('id', idGiocatori)
        : { data: [] }
      if (!vivo) return
      const fotoFirmate = await Promise.all((anagrafica ?? []).filter((p) => p.foto_url)
        .map(async (p) => [p.id, await firmaFoto(p.foto_url)] as const))
      if (!vivo) return
      const fotoPerGiocatore = new Map(fotoFirmate.filter((v): v is [number, string] => Boolean(v[1])))
      const anagraficaPerId = new Map((anagrafica ?? []).map((p) => [p.id, p]))
      const mappa = new Map<number, GiocatoreAssegnato>()
      for (const i of istanze ?? []) {
        const p = anagraficaPerId.get(i.player_id)
        if (p) mappa.set(i.id, { nome: p.nome, posizioni: p.posizioni, overall: p.overall, foto: fotoPerGiocatore.get(p.id) ?? null })
      }
      setGiocatoriAssegnati(mappa)
    }
    void carica()
    return () => { vivo = false }
  }, [scelteUltimaSessione])

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
          <span>ticket</span>
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
                    <span className={`scelte-preferenze__conteggio ${bozza.length >= (s.posizione ?? 0) ? 'is-completo' : ''}`}>
                      {bozza.length}<i>/{s.posizione}</i> {s.posizione === 1 ? 'preferenza' : 'preferenze'}
                    </span>
                  </div>

                  <ol className="scelte-preferenze__lista">
                    {bozza.length === 0
                      ? <li className="scelte-preferenze__vuota">Nessuna preferenza indicata: se nessuno viene esercitato, resti senza giocatore.</li>
                      : bozza.map((id, indice) => {
                          const g = giocatore(id)
                          const [primario, ...secondari] = g?.posizioni ?? []
                          const macro = macroRuolo(g?.posizioni ?? [])
                          return <li key={id}>
                            <span className="scelte-preferenze__rango">{indice + 1}</span>
                            <div className="scelte-preferenze__foto">
                              {g && foto.get(g.id)
                                ? <img src={foto.get(g.id)} alt="" loading="lazy" />
                                : <span aria-hidden="true">{g ? g.nome.charAt(0) : '?'}</span>}
                            </div>
                            {g
                              ? <>
                                  <b>{g.overall}</b>
                                  <div className="scelte-preferenze__dettagli">
                                    <strong>{cognome(g.nome)}</strong>
                                    <div className="scelte-preferenze__ruoli">
                                      <span className={`role-pill role-pill--${macro.toLowerCase()}`}>{primario ?? '—'}</span>
                                      {secondari.length > 0 && <small>{secondari.join(' / ')}</small>}
                                    </div>
                                    <span className="scelte-preferenze__meta">{g.eta} anni · {(g.ingaggio_teorico / 1_000_000).toFixed(1)} M€</span>
                                  </div>
                                </>
                              : <div className="scelte-preferenze__dettagli"><strong>#{id}</strong></div>}
                            <div className="scelte-preferenze__azioni">
                              <button type="button" disabled={congelate || indice === 0} onClick={() => sposta(indice, -1)} aria-label="Sposta su">↑</button>
                              <button type="button" disabled={congelate || indice === bozza.length - 1} onClick={() => sposta(indice, 1)} aria-label="Sposta giù">↓</button>
                              <button type="button" disabled={congelate} onClick={() => rimuovi(indice)} aria-label="Rimuovi">✕</button>
                            </div>
                          </li>
                        })}
                  </ol>

                  {!congelate && bozza.length < (s.posizione ?? 0) && <details className="scelte-preferenze__aggiungi">
                    <summary><span>Aggiungi dal pool</span><b>{poolFinestra.length - bozza.length} disponibili</b></summary>
                    <ul className="mt-2.5 flex max-h-[620px] list-none flex-col divide-y divide-white/10 overflow-y-auto p-0">
                      {poolFinestra.filter((g) => !bozza.includes(g.id)).map((g) => {
                        const [primario, ...secondari] = g.posizioni ?? []
                        const macro = macroRuolo(g.posizioni ?? [])
                        return <li className="flex items-center gap-3 py-3.5 pr-1.5" key={g.id}>
                          <div className="h-14 w-12 flex-none">
                            {foto.get(g.id)
                              ? <img className="h-full w-full object-contain object-bottom" src={foto.get(g.id)} alt="" loading="lazy" />
                              : <div className="grid h-full w-full place-items-center rounded-lg bg-white/[0.05] text-lg font-extrabold text-white/25" aria-hidden="true">{g.nome.charAt(0)}</div>}
                          </div>
                          <span className="w-9 flex-none text-center text-xl font-extrabold text-purple-300">{g.overall}</span>
                          <div className="flex min-w-0 flex-1 flex-col items-start gap-1.5">
                            <strong className="truncate text-[.92rem] font-extrabold text-white">{cognome(g.nome)}</strong>
                            <div className="flex flex-wrap items-center gap-1.5">
                              <span className={`role-pill role-pill--${macro.toLowerCase()}`}>{primario ?? '—'}</span>
                              {secondari.length > 0 && <span className="text-[.68rem] font-semibold text-white/35">{secondari.join(' / ')}</span>}
                            </div>
                            <span className="text-[.72rem] font-semibold text-white/45">{g.eta} anni</span>
                            <span className="text-[.74rem] font-extrabold text-purple-300">{(g.ingaggio_teorico / 1_000_000).toFixed(1)} M€</span>
                          </div>
                          <button type="button" className="scelte-pool__add" aria-label={`Aggiungi ${cognome(g.nome)} alla lista`} onClick={() => aggiungi(g.id)}>+</button>
                        </li>
                      })}
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

      {ultimaFinestraRisolta && scelteUltimaSessione.length > 0 && <section className="mercato-blocco">
        <div className="sezione-testa">
          <div>
            <p className="kicker">Ultima sessione</p>
            <h2>{ETICHETTA_FINESTRA[ultimaFinestraRisolta.finestra]} {ultimaFinestraRisolta.stagione}</h2>
          </div>
        </div>
        <ul className="riepilogo-scelte">
          {scelteUltimaSessione.map((s) => {
            const squadra = teamById.get(s.team_proprietario_id)
            const g = s.player_instance_id != null ? giocatoriAssegnati.get(s.player_instance_id) : undefined
            const [primario] = g?.posizioni ?? []
            return <li className="riepilogo-scelte__riga" key={s.id}>
              <span className="riepilogo-scelte__posizione">{s.posizione}ª</span>
              <div className="riepilogo-scelte__squadra">
                <Crest value={squadra?.stemma_url ?? null} imageUrl={squadra ? dati.crestUrlByTeamId.get(squadra.id) : undefined} />
                <small>{squadra?.nome ?? 'Squadra sconosciuta'}</small>
              </div>
              {g
                ? <div className="riepilogo-scelte__giocatore">
                    <div className="riepilogo-scelte__foto">
                      {g.foto ? <img src={g.foto} alt="" loading="lazy" /> : <span aria-hidden="true">{g.nome.charAt(0)}</span>}
                    </div>
                    <div className="riepilogo-scelte__dettagli">
                      <strong>{cognome(g.nome)}</strong>
                      <span className={`role-pill role-pill--${macroRuolo(g.posizioni ?? []).toLowerCase()}`}>{primario ?? '—'}</span>
                    </div>
                    <b>{g.overall}</b>
                  </div>
                : <span className="riepilogo-scelte__vuota">Andata a vuoto</span>}
            </li>
          })}
        </ul>
      </section>}
      </>}
    </div>
  </main>
}
