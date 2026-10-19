import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { supabase } from '../lib/supabase'
import type { useSeasonData } from '../lib/useSeasonData'
import { urlFotoGiocatore } from '../lib/fotoGiocatore'
import { cognome } from '../lib/nomi'
import { macroRuolo, ruoloIt } from '../lib/ruoli'
import { Crest } from './Crest'

// Album delle figurine (docs/decisioni-conferenze-stampa.md §BetOne): una pagina per squadra, stemma + giocatori.
// Bustina da 100 crediti, 3 figurine; l'estrazione la fa il server (album_compra_bustina). Ultrarara = versione
// olografica; in Serie F anche le due conference. Doppioni riciclabili, pagina completa = 200 crediti.

type Dati = ReturnType<typeof useSeasonData>
type Figurina = { id: number; tipo: 'stemma' | 'giocatore' | 'conferenza'; team_id: number | null; player_id: number | null; conferenza: 'est' | 'ovest' | null; overall: number | null; aggiornamento: boolean }
type Possesso = { figurina_id: number; normali: number; ultra: number }
type Anagrafica = { id: number; nome: string; posizioni: string[]; foto_url: string | null }
type Uscita = { figurina_id: number; tipo: Figurina['tipo']; ultra: boolean; nuova: boolean }
type RigaClassifica = { team_id: number; attaccate: number; totale: number; ultra: number; pagine: number }

const PREZZO = 100
const ridotto = () => typeof window !== 'undefined' && window.matchMedia?.('(prefers-reduced-motion: reduce)').matches
const fmt = (n: number) => new Intl.NumberFormat('it-IT').format(n)

// ---------- Una figurina ----------
function Carta({ f, ana, dati, ultra, vuota, numero, piccola }: { f: Figurina; ana?: Anagrafica; dati: Dati; ultra: boolean; vuota?: boolean; numero?: number; piccola?: boolean }) {
  const team = f.team_id != null ? dati.teamById.get(f.team_id) : undefined
  const classe = `fig${ultra ? ' fig--ultra' : ''}${vuota ? ' fig--vuota' : ''}${piccola ? ' fig--piccola' : ''} fig--${f.tipo}`
  if (vuota) return <div className={classe} aria-label={`Figurina ${numero ?? ''} mancante`}><span className="fig__numero">{numero}</span></div>
  if (f.tipo === 'conferenza') {
    return <div className={classe} aria-label={`Figurina ultrarara ${f.conferenza === 'est' ? 'Eastern' : 'Western'} Conference`}>
      <div className="fig__olo" aria-hidden="true" />
      <div className="fig__conf"><img src={f.conferenza === 'est' ? '/loghi-conferenza/east.svg' : '/loghi-conferenza/west.svg'} alt="" /></div>
      <div className="fig__piede"><strong>{f.conferenza === 'est' ? 'EASTERN' : 'WESTERN'}</strong><small>Conference</small></div>
    </div>
  }
  if (f.tipo === 'stemma') {
    return <div className={classe} aria-label={`Stemma ${team?.nome ?? ''}`}>
      {ultra && <div className="fig__olo" aria-hidden="true" />}
      <div className="fig__stemma"><Crest value={team?.stemma_url ?? null} imageUrl={f.team_id != null ? dati.crestUrlByTeamId.get(f.team_id) : undefined} size="large" eager /></div>
      <div className="fig__piede"><strong>{team?.nome ?? '—'}</strong><small>Stemma</small></div>
    </div>
  }
  const ruolo = ana?.posizioni?.[0] ?? ''
  const foto = urlFotoGiocatore(ana?.foto_url)
  return <div className={`${classe} fig--${macroRuolo(ana?.posizioni ?? []).toLowerCase()}`} aria-label={`${ana?.nome ?? 'Giocatore'}${ultra ? ', ultrarara' : ''}`}>
    {ultra && <div className="fig__olo" aria-hidden="true" />}
    <div className="fig__testa"><b>{f.overall ?? ''}</b><span>{ruoloIt(ruolo)}</span></div>
    <div className="fig__foto">{foto ? <img src={foto} alt="" loading="lazy" /> : <span>👤</span>}</div>
    <div className="fig__piede">
      <strong>{ana ? cognome(ana.nome) : '—'}</strong>
      <span className="fig__club"><Crest value={team?.stemma_url ?? null} imageUrl={f.team_id != null ? dati.crestUrlByTeamId.get(f.team_id) : undefined} size="small" />{team?.nome ?? ''}</span>
    </div>
    {f.aggiornamento && <em className="fig__agg">AGG.</em>}
    {ultra && <em className="fig__stella">★</em>}
  </div>
}

type Props = { leagueId: number; teamId: number; dati: Dati; conferenze: boolean }

export function Album({ leagueId, teamId, dati, conferenze }: Props) {
  const [stagione, setStagione] = useState<number | null>(null)
  const [crediti, setCrediti] = useState(0)
  const [figurine, setFigurine] = useState<Figurina[]>([])
  const [possesso, setPossesso] = useState<Map<number, Possesso>>(new Map())
  const [ana, setAna] = useState<Map<number, Anagrafica>>(new Map())
  const [errore, setErrore] = useState('')
  const [pagina, setPagina] = useState<number | 'conf' | null>(null)
  const [busta, setBusta] = useState<Uscita[] | null>(null)
  const [girate, setGirate] = useState(0)
  const [strappo, setStrappo] = useState(false)
  const [compro, setCompro] = useState(false)
  const [avviso, setAvviso] = useState('')
  const [classifica, setClassifica] = useState<RigaClassifica[]>([])
  const scheda = useRef<HTMLDivElement>(null)

  const carica = useCallback(async () => {
    const { data: a, error } = await supabase.rpc('album_apri', { p_league_id: leagueId })
    if (error) { setErrore(error.message); return }
    const st = (a as { stagione: number; crediti: number }).stagione
    setStagione(st); setCrediti((a as { crediti: number }).crediti)
    const [{ data: f }, { data: p }, { data: cl }] = await Promise.all([
      supabase.from('album_figurine').select('id, tipo, team_id, player_id, conferenza, overall, aggiornamento').eq('league_id', leagueId).eq('stagione', st).order('id'),
      supabase.from('album_possesso').select('figurina_id, normali, ultra').eq('league_id', leagueId),
      supabase.rpc('album_classifica', { p_league_id: leagueId }),
    ])
    const figs = (f ?? []) as Figurina[]
    setFigurine(figs)
    setPossesso(new Map(((p ?? []) as Possesso[]).map((x) => [x.figurina_id, x])))
    setClassifica((cl ?? []) as RigaClassifica[])
    const ids = [...new Set(figs.filter((x) => x.player_id != null).map((x) => x.player_id as number))]
    const mappa = new Map<number, Anagrafica>()
    for (let i = 0; i < ids.length; i += 300) {
      const { data: g } = await supabase.from('players').select('id, nome, posizioni, foto_url').in('id', ids.slice(i, i + 300))
      for (const x of (g ?? []) as Anagrafica[]) mappa.set(x.id, x)
    }
    setAna(mappa)
  }, [leagueId])
  useEffect(() => { void carica() }, [carica])

  const perSquadra = useMemo(() => {
    const m = new Map<number, Figurina[]>()
    for (const f of figurine) if (f.team_id != null) m.set(f.team_id, [...(m.get(f.team_id) ?? []), f])
    for (const [k, v] of m) m.set(k, v.sort((a, b) => (a.tipo === 'stemma' ? -1 : b.tipo === 'stemma' ? 1 : 0) || Number(a.aggiornamento) - Number(b.aggiornamento) || (b.overall ?? 0) - (a.overall ?? 0) || a.id - b.id))
    return m
  }, [figurine])
  const squadre = useMemo(() => [...perSquadra.keys()].sort((a, b) => (dati.teamById.get(a)?.nome ?? '').localeCompare(dati.teamById.get(b)?.nome ?? '')), [perSquadra, dati.teamById])
  const numeri = useMemo(() => { const m = new Map<number, number>(); let n = 1; for (const t of squadre) for (const f of perSquadra.get(t) ?? []) m.set(f.id, n++); for (const f of figurine.filter((x) => x.tipo === 'conferenza')) m.set(f.id, n++); return m }, [squadre, perSquadra, figurine])
  const conf = figurine.filter((f) => f.tipo === 'conferenza')

  const ce = (id: number) => { const p = possesso.get(id); return Boolean(p && p.normali + p.ultra > 0) }
  const ceUltra = (id: number) => (possesso.get(id)?.ultra ?? 0) > 0
  const base = figurine.filter((f) => f.tipo !== 'conferenza')
  const attaccate = base.filter((f) => ce(f.id)).length
  const ultraTot = figurine.filter((f) => ceUltra(f.id)).length
  const doppioni = [...possesso.values()].reduce((s, p) => s + Math.max(0, p.normali - 1) + Math.max(0, p.ultra - 1), 0)
  const valoreDoppioni = [...possesso.values()].reduce((s, p) => s + Math.max(0, p.normali - 1) * 10 + Math.max(0, p.ultra - 1) * 50, 0)

  async function compra() {
    if (compro) return
    setCompro(true); setErrore(''); setAvviso('')
    const { data, error } = await supabase.rpc('album_compra_bustina', { p_league_id: leagueId })
    setCompro(false)
    if (error) { setErrore(error.message); return }
    const r = data as { figurine: Uscita[]; premi: Array<{ pagina?: number; album?: boolean }>; crediti: number }
    setCrediti(r.crediti)
    setGirate(0); setStrappo(false); setBusta(r.figurine)
    window.setTimeout(() => setStrappo(true), ridotto() ? 0 : 650)
    const premi = r.premi.map((p) => p.album ? '📒 Album completato!' : `Pagina di ${dati.teamById.get(p.pagina ?? 0)?.nome ?? 'una squadra'} completa: +200 crediti`)
    if (premi.length) setAvviso(premi.join(' · '))
    void carica()
  }

  async function ricicla() {
    const { data, error } = await supabase.rpc('album_ricicla_doppioni', { p_league_id: leagueId })
    if (error) { setErrore(error.message); return }
    const r = data as { riciclati: number; crediti_guadagnati: number; crediti?: number }
    if (r.crediti != null) setCrediti(r.crediti)
    setAvviso(r.riciclati ? `Riciclati ${r.riciclati} doppioni: +${fmt(r.crediti_guadagnati)} crediti` : 'Nessun doppione da riciclare.')
    void carica()
  }

  if (errore && stagione == null) return <section className="alb-vuoto"><p role="alert">{errore}</p></section>
  if (stagione == null) return <section className="alb-vuoto"><p>Apro l'album…</p></section>

  const figPagina = pagina === 'conf' ? conf : pagina != null ? perSquadra.get(pagina) ?? [] : []
  const completaPagina = (t: number) => (perSquadra.get(t) ?? []).every((f) => ce(f.id))

  return <section className="alb">
    <div className="alb-testa">
      <div className="alb-testa__copertina" aria-hidden="true"><span>ALBUM</span><b>{stagione}</b></div>
      <div className="alb-testa__dati">
        <small>Stagione {stagione}</small>
        <strong>{attaccate}<span>/{base.length}</span></strong>
        <div className="alb-barra" aria-label={`Completamento ${Math.round(attaccate * 100 / Math.max(1, base.length))}%`}><i style={{ width: `${(attaccate * 100) / Math.max(1, base.length)}%` }} /></div>
        <p>{ultraTot} ultrarare · {fmt(crediti)} crediti</p>
      </div>
    </div>

    <div className="alb-azioni">
      <button type="button" className="alb-compra" disabled={compro || crediti < PREZZO} onClick={() => void compra()}>
        <span className="alb-compra__busta" aria-hidden="true" />
        <span><b>{compro ? 'Apro…' : 'Compra una bustina'}</b><small>{PREZZO} crediti · 3 figurine</small></span>
      </button>
      <button type="button" className="alb-ricicla" disabled={doppioni === 0} onClick={() => void ricicla()}>
        <b>{doppioni}</b><small>doppioni</small><em>{doppioni ? `+${fmt(valoreDoppioni)}` : 'ricicla'}</em>
      </button>
    </div>
    {crediti < PREZZO && <p className="bet-nota">Servono {PREZZO} crediti: si vincono con le schedine e al casinò, e ogni lunedì ne arrivano 1.000.</p>}
    {(avviso || errore) && <p className={errore ? 'alb-errore' : 'alb-avviso'} role="status">{errore || avviso}</p>}

    {pagina == null ? <>
      <h2 className="alb-titolo">Le pagine</h2>
      <ul className="alb-indice">
        {squadre.map((t) => {
          const figs = perSquadra.get(t) ?? []
          const n = figs.filter((f) => ce(f.id)).length
          const team = dati.teamById.get(t)
          return <li key={t}>
            <button type="button" className={`${completaPagina(t) ? 'is-completa' : ''}${t === teamId ? ' is-mia' : ''}`} onClick={() => { setPagina(t); window.requestAnimationFrame(() => scheda.current?.scrollIntoView({ behavior: 'smooth', block: 'start' })) }}>
              <span className="alb-indice__stemma"><Crest value={team?.stemma_url ?? null} imageUrl={dati.crestUrlByTeamId.get(t)} size="small" /></span>
              <span className="alb-indice__nome"><strong>{team?.nome ?? '—'}</strong><small>{n}/{figs.length}</small></span>
              <span className="alb-indice__barra" aria-hidden="true"><i style={{ width: `${(n * 100) / Math.max(1, figs.length)}%` }} /></span>
              {completaPagina(t) && <em aria-label="Pagina completa">✓</em>}
            </button>
          </li>
        })}
        {conferenze && conf.length > 0 && <li>
          <button type="button" className="alb-indice__conf" onClick={() => setPagina('conf')}>
            <span className="alb-indice__stemma">✨</span>
            <span className="alb-indice__nome"><strong>Conference</strong><small>{conf.filter((f) => ce(f.id)).length}/{conf.length} ultrarare</small></span>
          </button>
        </li>}
      </ul>
    </> : <div ref={scheda} className="alb-pagina">
      <div className="alb-pagina__testa">
        <button type="button" className="alb-indietro" onClick={() => setPagina(null)}>‹ Pagine</button>
        <strong>{pagina === 'conf' ? 'Conference' : dati.teamById.get(pagina)?.nome}</strong>
        <span>{figPagina.filter((f) => ce(f.id)).length}/{figPagina.length}</span>
      </div>
      <ul className="alb-griglia">
        {figPagina.map((f) => <li key={f.id}>
          <Carta f={f} ana={f.player_id != null ? ana.get(f.player_id) : undefined} dati={dati} ultra={ceUltra(f.id) || f.tipo === 'conferenza'} vuota={!ce(f.id)} numero={numeri.get(f.id)} />
          {(possesso.get(f.id)?.normali ?? 0) + (possesso.get(f.id)?.ultra ?? 0) > 1 && <span className="alb-doppio">×{(possesso.get(f.id)?.normali ?? 0) + (possesso.get(f.id)?.ultra ?? 0)}</span>}
        </li>)}
      </ul>
    </div>}

    <section className="alb-classifica">
      <h2>Collezionisti</h2>
      {classifica.length === 0 ? <p className="bet-nota">Ancora nessuno ha aperto una bustina.</p> : <ol>
        {classifica.map((r, i) => {
          const t = dati.teamById.get(r.team_id)
          return <li key={r.team_id} className={r.team_id === teamId ? 'is-mia' : ''}>
            <span className={`bet-pos${i < 3 ? ` bet-pos--${i + 1}` : ''}`}>{i + 1}</span>
            <span className="bet-giocatori__stemma"><Crest value={t?.stemma_url ?? null} imageUrl={dati.crestUrlByTeamId.get(r.team_id)} size="small" /></span>
            <span className="bet-classifica__nome"><strong>{t?.nome ?? '—'}</strong><small>{r.ultra} ultrarare · {r.pagine} pagine complete</small></span>
            <span className="slot-classifica__crediti"><b>{Math.round((r.attaccate * 100) / Math.max(1, r.totale))}%</b><small>{r.attaccate}/{r.totale}</small></span>
          </li>
        })}
      </ol>}
    </section>

    {busta && <div className="alb-apertura" role="dialog" aria-modal="true" aria-label="Bustina aperta">
      <div className={`alb-busta${strappo ? ' is-strappata' : ''}`} aria-hidden="true"><span>SPECIAL<b>ONE</b></span><i /></div>
      {strappo && <div className="alb-carte">
        {busta.map((u, i) => {
          const f = figurine.find((x) => x.id === u.figurina_id) ?? { id: u.figurina_id, tipo: u.tipo, team_id: null, player_id: null, conferenza: null, overall: null, aggiornamento: false } as Figurina
          const girata = i < girate
          return <button key={i} type="button" className={`alb-carta${girata ? ' is-girata' : ''}${u.ultra ? ' is-ultra' : ''}`} style={{ animationDelay: `${i * 0.12}s` }}
            onClick={() => setGirate((g) => Math.max(g, i + 1))} aria-label={girata ? 'Figurina' : 'Tocca per girare'}>
            <span className="alb-carta__retro" aria-hidden="true"><b>S1</b></span>
            <span className="alb-carta__fronte">
              <Carta f={f} ana={f.player_id != null ? ana.get(f.player_id) : undefined} dati={dati} ultra={u.ultra} />
              {girata && <em className={`alb-carta__etichetta${u.ultra ? ' is-ultra' : ''}`}>{u.ultra ? 'ULTRARARA!' : u.nuova ? 'NUOVA' : 'DOPPIONE'}</em>}
            </span>
          </button>
        })}
      </div>}
      {strappo && <div className="alb-apertura__azioni">
        {girate < busta.length ? <button type="button" className="button button--secondary" onClick={() => setGirate(busta.length)}>Gira tutte</button>
          : <>
            <button type="button" className="button button--secondary" onClick={() => setBusta(null)}>Chiudi</button>
            <button type="button" className="alb-compra alb-compra--piccola" disabled={compro || crediti < PREZZO} onClick={() => void compra()}><span><b>Un'altra</b><small>{PREZZO} crediti</small></span></button>
          </>}
      </div>}
    </div>}
  </section>
}
