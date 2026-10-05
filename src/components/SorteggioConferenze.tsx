import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { supabase } from '../lib/supabase'
import { firmaStemmi } from '../lib/premiAlbo'
import { NOME_CONFERENZA, type Conferenza } from '../lib/conferenze'
import type { League, Membership, Team } from '../types'
import { Crest } from './Crest'
import { ConferenceBadge } from './ConferenceBadge'

type Props = { membership: Membership; onFine: () => void }

type Stato = {
  sorteggio_id: number; stagione: number; avviato_il: string; passo_secondi: number
  totale: number; rivelate: number; completato: boolean; ora_server: string
}
type Estrazione = { ordine: number; team_id: number; conferenza: Conferenza }

const SECONDI_CARTA = 8

function Roulette({ candidati, stemmi, secondiRimasti }: { candidati: Team[]; stemmi: Map<number, string>; secondiRimasti: number }) {
  const [indice, setIndice] = useState(0)
  const ridotto = typeof window !== 'undefined' && window.matchMedia('(prefers-reduced-motion: reduce)').matches
  const rimasti = useRef(secondiRimasti)
  rimasti.current = secondiRimasti
  useEffect(() => {
    if (ridotto || candidati.length === 0) return
    let timer = 0
    const passo = () => {
      setIndice((i) => (i + 1 + Math.floor(Math.random() * Math.max(1, candidati.length - 1))) % candidati.length)
      // Gira veloce e rallenta negli ultimi secondi: e' solo scena, l'estratta non e' ancora nota a nessuno.
      const r = rimasti.current
      timer = window.setTimeout(passo, r > 5 ? 90 : 90 + (5 - Math.max(0, r)) * 150)
    }
    timer = window.setTimeout(passo, 90)
    return () => window.clearTimeout(timer)
  }, [candidati.length, ridotto])
  const squadra = candidati[indice % Math.max(1, candidati.length)]
  return <div className="sorteggio__roulette" aria-hidden="true">
    <div className="sorteggio__roulette-carta" key={squadra?.id ?? 0}>
      {ridotto || !squadra ? <b>?</b> : <Crest value={squadra.stemma_url} imageUrl={stemmi.get(squadra.id)} size="large" />}
    </div>
  </div>
}

// Sorteggio East / West in diretta. Il server ha gia' deciso l'ordine, ma ogni
// estrazione si puo' leggere solo da quando viene rivelata (RLS): questa
// schermata si limita a mostrare, in sincronia per tutti, quello che e' uscito.
export function SorteggioConferenze({ membership, onFine }: Props) {
  const league = membership.league as League
  const [stato, setStato] = useState<Stato | null>(null)
  const [estrazioni, setEstrazioni] = useState<Estrazione[]>([])
  const [squadre, setSquadre] = useState<Team[]>([])
  const [stemmi, setStemmi] = useState<Map<number, string>>(new Map())
  const [adesso, setAdesso] = useState(() => Date.now())
  const offset = useRef(0)
  const inCorso = useRef(false)

  useEffect(() => {
    let vivo = true
    void (async () => {
      const { data } = await supabase.from('teams').select('*').eq('league_id', league.id).eq('attiva', true)
      const elenco = (data ?? []) as Team[]
      const firmati = await firmaStemmi(elenco)
      if (!vivo) return
      setSquadre(elenco)
      setStemmi(firmati)
    })()
    return () => { vivo = false }
  }, [league.id])

  const aggiorna = useCallback(async () => {
    if (inCorso.current) return
    inCorso.current = true
    try {
      const prima = Date.now()
      const { data, error } = await supabase.rpc('sorteggio_conferenze_stato', { p_league_id: league.id })
      if (error || !data) return
      const nuovo = data as Stato
      offset.current = Date.parse(nuovo.ora_server) - (prima + Date.now()) / 2
      setStato(nuovo)
      const { data: righe } = await supabase.from('sorteggio_estrazioni')
        .select('ordine, team_id, conferenza').eq('sorteggio_id', nuovo.sorteggio_id).order('ordine')
      setEstrazioni((righe ?? []) as Estrazione[])
    } finally {
      inCorso.current = false
    }
  }, [league.id])

  useEffect(() => {
    void aggiorna()
    const orologio = window.setInterval(() => setAdesso(Date.now() + offset.current), 250)
    return () => window.clearInterval(orologio)
  }, [aggiorna])

  const passoMs = (stato?.passo_secondi ?? 20) * 1000
  const avviatoMs = stato ? Date.parse(stato.avviato_il) : 0
  const trascorso = stato ? Math.max(0, adesso - avviatoMs) : 0
  const dovute = stato ? Math.min(stato.totale, Math.floor(trascorso / passoMs)) : 0
  const finito = Boolean(stato) && dovute >= (stato?.totale ?? 0)
  const secondiNelSlot = stato ? (trascorso % passoMs) / 1000 : 0
  const secondiRimasti = Math.max(0, (stato?.passo_secondi ?? 20) - secondiNelSlot)

  // Se manca una estrazione che il tempo dice gia' rivelata la si chiede ogni secondo;
  // altrimenti si risincronizza ogni 5. A sorteggio finito si guarda quando la lega riparte.
  useEffect(() => {
    if (!stato) return
    const attesa = dovute > estrazioni.length
    const timer = window.setInterval(() => { void aggiorna() }, attesa ? 1000 : 5000)
    return () => window.clearInterval(timer)
  }, [stato, dovute, estrazioni.length, aggiorna])

  useEffect(() => {
    if (!finito) return
    let vivo = true
    const timer = window.setInterval(async () => {
      const { data } = await supabase.from('leagues').select('fase_carriera').eq('id', league.id).single()
      if (vivo && data && data.fase_carriera !== 'sorteggio') onFine()
    }, 3000)
    return () => { vivo = false; window.clearInterval(timer) }
  }, [finito, league.id, onFine])

  const squadrePerId = useMemo(() => new Map(squadre.map((t) => [t.id, t])), [squadre])
  const uscite = useMemo(() => new Set(estrazioni.map((e) => e.team_id)), [estrazioni])
  const candidati = useMemo(() => squadre.filter((t) => !uscite.has(t.id)), [squadre, uscite])
  const perConferenza = (c: Conferenza) => estrazioni.filter((e) => e.conferenza === c)
  const meta = Math.max(1, Math.floor((stato?.totale ?? squadre.length) / 2))

  const ultima = estrazioni.length > 0 ? estrazioni[estrazioni.length - 1] : null
  const mostraCarta = Boolean(ultima) && dovute >= 1 && ultima!.ordine === dovute && secondiNelSlot < SECONDI_CARTA && !finito
  const prossimo = dovute + 1
  const prossimaConferenza: Conferenza = prossimo % 2 === 1 ? 'est' : 'ovest'
  const squadraUltima = ultima ? squadrePerId.get(ultima.team_id) : undefined

  return <main className="sorteggio">
    <header className="sorteggio__testa">
      <div className="brand-lockup brand-lockup--dark"><img src="/specialone-mark.svg" alt="" /><span>SpecialOne</span></div>
      <span>{league.nome} · Stagione {stato?.stagione ?? league.stagione_corrente}</span>
    </header>

    <section className="sorteggio__scena">
      <p className="sorteggio__occhiello">Sorteggio delle conferenze</p>
      <div className="sorteggio__versus"><ConferenceBadge conferenza="est" grande /><b>VS</b><ConferenceBadge conferenza="ovest" grande /></div>

      {!stato && <p className="sorteggio__attesa">Preparo il sorteggio…</p>}

      {stato && finito && <div className="sorteggio__fine">
        <h1>Sorteggio completato.</h1>
        <p>Le conferenze sono pronte. Sto preparando il calendario: tra pochissimo parte la stagione.</p>
      </div>}

      {stato && !finito && mostraCarta && squadraUltima && ultima && <div className={`sorteggio__estratta sorteggio__estratta--${ultima.conferenza}`} key={ultima.ordine}>
        <small>Estratta per la {NOME_CONFERENZA[ultima.conferenza]}</small>
        <div className="sorteggio__estratta-stemma"><Crest value={squadraUltima.stemma_url} imageUrl={stemmi.get(squadraUltima.id)} size="large" stelle={squadraUltima.titoli_title} /></div>
        <strong>{squadraUltima.nome}</strong>
        <span>{squadraUltima.sigla}{squadraUltima.id === membership.id ? ' · La tua squadra' : ''}</span>
      </div>}

      {stato && !finito && !mostraCarta && <div className={`sorteggio__suspense sorteggio__suspense--${prossimaConferenza}`}>
        <h1>{estrazioni.length === 0 ? 'La prima squadra estratta per la' : 'La prossima squadra per la'} <em>{NOME_CONFERENZA[prossimaConferenza]}</em> è…</h1>
        <Roulette candidati={candidati} stemmi={stemmi} secondiRimasti={secondiRimasti} />
        <div className="sorteggio__conto" style={{ ['--p' as string]: `${Math.min(100, (secondiNelSlot / (stato.passo_secondi || 20)) * 100)}%` }}>
          <b>{Math.ceil(secondiRimasti)}</b>
        </div>
      </div>}
    </section>

    <section className="sorteggio__colonne" aria-label="Conferenze">
      {(['est', 'ovest'] as const).map((c) => {
        const squadreConf = perConferenza(c)
        return <div className={`sorteggio__colonna sorteggio__colonna--${c}`} key={c}>
          <header><ConferenceBadge conferenza={c} /><strong>{NOME_CONFERENZA[c]}</strong><span>{squadreConf.length}<i>/{meta}</i></span></header>
          <ol>
            {Array.from({ length: meta }, (_, i) => {
              const e = squadreConf[i]
              const t = e ? squadrePerId.get(e.team_id) : undefined
              const nuova = Boolean(e) && e!.ordine === dovute && secondiNelSlot < SECONDI_CARTA && !finito
              return <li key={i} className={`${t ? 'is-piena' : ''} ${nuova ? 'is-nuova' : ''} ${t && t.id === membership.id ? 'is-mia' : ''}`}>
                <span className="sorteggio__n">{i + 1}</span>
                {t
                  ? <><Crest value={t.stemma_url} imageUrl={stemmi.get(t.id)} stelle={t.titoli_title} /><strong>{t.nome}</strong></>
                  : <em>—</em>}
              </li>
            })}
          </ol>
        </div>
      })}
    </section>
  </main>
}
