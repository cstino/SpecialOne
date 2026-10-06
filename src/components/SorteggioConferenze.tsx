import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { supabase } from '../lib/supabase'
import { firmaStemmi } from '../lib/premiAlbo'
import { NOME_CONFERENZA, NOME_CONFERENZA_BREVE, type Conferenza } from '../lib/conferenze'
import { stemmaPresetDaValore } from '../lib/teamCrests'
import type { League, Membership, Team } from '../types'
import { Crest } from './Crest'
import { ConferenceBadge } from './ConferenceBadge'

type DemoSorteggio = { stato: Stato; estrazioni: Estrazione[]; squadre: Team[]; adesso: number }
type Props = { membership: Membership; onFine: () => void; onMenu?: () => void; demo?: DemoSorteggio }

type Stato = {
  sorteggio_id: number; stagione: number; avviato_il: string; passo_secondi: number
  totale: number; rivelate: number; completato: boolean; ora_server: string
}
type Estrazione = { ordine: number; team_id: number; conferenza: Conferenza }

// L'estratta resta in scena per quasi tutto il turno; la roulette gira solo negli ultimi secondi.
const SECONDI_ROULETTE = 6

// Gli stemmi della roulette cambiano ogni decimo di secondo: se non sono gia' in
// cache il caricamento li fa lampeggiare e la roulette va a scatti.
function precaricaStemmi(squadre: Team[], firmati: Map<number, string>) {
  for (const t of squadre) {
    const src = firmati.get(t.id) ?? stemmaPresetDaValore(t.stemma_url)?.src
    if (src) { const img = new Image(); img.src = src }
  }
}

function Roulette({ candidati, stemmi, secondiRimasti }: { candidati: Team[]; stemmi: Map<number, string>; secondiRimasti: number }) {
  const [indice, setIndice] = useState(0)
  const ridotto = typeof window !== 'undefined' && window.matchMedia('(prefers-reduced-motion: reduce)').matches
  const rimasti = useRef(secondiRimasti)
  rimasti.current = secondiRimasti
  const gira = secondiRimasti <= SECONDI_ROULETTE
  // Ordine mescolato una volta sola: gli stemmi scorrono senza ripetersi di fila.
  const ordine = useMemo(() => {
    const o = candidati.map((_, i) => i)
    for (let i = o.length - 1; i > 0; i--) { const j = Math.floor(Math.random() * (i + 1)); [o[i], o[j]] = [o[j], o[i]] }
    return o
  }, [candidati.length]) // eslint-disable-line react-hooks/exhaustive-deps
  useEffect(() => {
    if (ridotto || !gira || candidati.length === 0) return
    let timer = 0
    const passo = () => {
      setIndice((i) => (i + 1) % Math.max(1, ordine.length))
      // Veloce all'inizio, poi rallenta piano fino a fermarsi: e' solo scena, l'estratta non e' ancora nota a nessuno.
      const avanzamento = 1 - Math.min(1, Math.max(0, rimasti.current / SECONDI_ROULETTE))
      timer = window.setTimeout(passo, 80 + 300 * avanzamento * avanzamento)
    }
    timer = window.setTimeout(passo, 80)
    return () => window.clearTimeout(timer)
  }, [candidati.length, ridotto, gira, ordine.length])
  const squadra = gira && !ridotto ? candidati[ordine[indice % Math.max(1, ordine.length)] ?? 0] : undefined
  return <div className={`sorteggio__roulette${gira ? ' is-gira' : ''}`} aria-hidden="true">
    <div className="sorteggio__roulette-carta">
      {squadra ? <Crest value={squadra.stemma_url} imageUrl={stemmi.get(squadra.id)} size="large" eager /> : <b>?</b>}
    </div>
  </div>
}

// Sorteggio East / West in diretta. Il server ha gia' deciso l'ordine, ma ogni
// estrazione si puo' leggere solo da quando viene rivelata (RLS): questa
// schermata si limita a mostrare, in sincronia per tutti, quello che e' uscito.
export function SorteggioConferenze({ membership, onFine, onMenu, demo }: Props) {
  const league = membership.league as League
  const [statoReale, setStato] = useState<Stato | null>(null)
  const [estrazioniReali, setEstrazioni] = useState<Estrazione[]>([])
  const [squadreReali, setSquadre] = useState<Team[]>([])
  const [stemmi, setStemmi] = useState<Map<number, string>>(new Map())
  const [adessoReale, setAdesso] = useState(() => Date.now())
  // Anteprima con dati fittizi: stato, estrazioni, squadre e orologio arrivano da fuori.
  const stato = demo ? demo.stato : statoReale
  const estrazioni = demo ? demo.estrazioni : estrazioniReali
  const squadre = demo ? demo.squadre : squadreReali
  const adesso = demo ? demo.adesso : adessoReale
  const offset = useRef(0)
  const inCorso = useRef(false)

  useEffect(() => {
    if (demo) return
    let vivo = true
    void (async () => {
      const { data } = await supabase.from('teams').select('*').eq('league_id', league.id).eq('attiva', true)
      const elenco = (data ?? []) as Team[]
      const firmati = await firmaStemmi(elenco)
      if (!vivo) return
      setSquadre(elenco)
      setStemmi(firmati)
      precaricaStemmi(elenco, firmati)
    })()
    return () => { vivo = false }
  }, [league.id, demo])

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
    if (demo) return
    void aggiorna()
    const orologio = window.setInterval(() => setAdesso(Date.now() + offset.current), 250)
    return () => window.clearInterval(orologio)
  }, [aggiorna, demo])

  const passoMs = (stato?.passo_secondi ?? 20) * 1000
  const avviatoMs = stato ? Date.parse(stato.avviato_il) : 0
  // Dopo il draft in diretta il sorteggio parte piu' tardi: finche' non e' l'ora, conto alla rovescia.
  const secondiAllAvvio = stato ? Math.max(0, (avviatoMs - adesso) / 1000) : 0
  const prima = Boolean(stato) && secondiAllAvvio > 0
  const trascorso = stato ? Math.max(0, adesso - avviatoMs) : 0
  const dovute = stato ? Math.min(stato.totale, Math.floor(trascorso / passoMs)) : 0
  const finito = Boolean(stato) && dovute >= (stato?.totale ?? 0)
  const secondiNelSlot = stato ? (trascorso % passoMs) / 1000 : 0
  const secondiRimasti = Math.max(0, (stato?.passo_secondi ?? 20) - secondiNelSlot)
  const secondiCarta = (stato?.passo_secondi ?? 20) - SECONDI_ROULETTE

  // Se manca una estrazione che il tempo dice gia' rivelata la si chiede ogni secondo;
  // altrimenti si risincronizza ogni 5. A sorteggio finito si guarda quando la lega riparte.
  useEffect(() => {
    if (!stato || demo) return
    const attesa = dovute > estrazioni.length
    const timer = window.setInterval(() => { void aggiorna() }, attesa ? 1000 : 5000)
    return () => window.clearInterval(timer)
  }, [stato, dovute, estrazioni.length, aggiorna, demo])

  useEffect(() => {
    if (!finito || demo) return
    let vivo = true
    const timer = window.setInterval(async () => {
      const { data } = await supabase.from('leagues').select('fase_carriera').eq('id', league.id).single()
      if (vivo && data && data.fase_carriera !== 'sorteggio') onFine()
    }, 3000)
    return () => { vivo = false; window.clearInterval(timer) }
  }, [finito, league.id, onFine, demo])

  const squadrePerId = useMemo(() => new Map(squadre.map((t) => [t.id, t])), [squadre])
  const uscite = useMemo(() => new Set(estrazioni.map((e) => e.team_id)), [estrazioni])
  const candidati = useMemo(() => squadre.filter((t) => !uscite.has(t.id)), [squadre, uscite])
  const perConferenza = (c: Conferenza) => estrazioni.filter((e) => e.conferenza === c)
  const meta = Math.max(1, Math.floor((stato?.totale ?? squadre.length) / 2))

  const ultima = estrazioni.length > 0 ? estrazioni[estrazioni.length - 1] : null
  const mostraCarta = Boolean(ultima) && dovute >= 1 && ultima!.ordine === dovute && secondiNelSlot < secondiCarta && !finito
  const prossimo = dovute + 1
  const prossimaConferenza: Conferenza = prossimo % 2 === 1 ? 'est' : 'ovest'
  const squadraUltima = ultima ? squadrePerId.get(ultima.team_id) : undefined

  return <main className="sorteggio">
    <header className="sorteggio__testa">
      <div className="brand-lockup brand-lockup--dark"><img src="/specialone-mark.svg" alt="" /><span>SpecialOne</span></div>
      {onMenu ? <button type="button" className="dlive__menu" onClick={onMenu}>‹ Menu</button> : <span>{league.nome} · Stagione {stato?.stagione ?? league.stagione_corrente}</span>}
    </header>

    <section className="sorteggio__scena">
      <p className="sorteggio__occhiello">Sorteggio delle conferenze</p>
      <div className="sorteggio__versus"><ConferenceBadge conferenza="est" grande /><b>VS</b><ConferenceBadge conferenza="ovest" grande /></div>

      {!stato && <p className="sorteggio__attesa">Preparo il sorteggio…</p>}

      {stato && prima && <div className="dlive__attesa">
        <h1>Il sorteggio parte tra</h1>
        <div className="dlive__conto-grande">{String(Math.floor(Math.ceil(secondiAllAvvio) / 60)).padStart(2, '0')}:{String(Math.ceil(secondiAllAvvio) % 60).padStart(2, '0')}</div>
        <p>Si estrae una squadra alla volta, alternando Eastern e Western.</p>
      </div>}

      {stato && finito && <div className="sorteggio__fine">
        <h1>Sorteggio completato.</h1>
        <p>Le conferenze sono pronte. Sto preparando il calendario: tra pochissimo parte la stagione.</p>
      </div>}

      {stato && !finito && !prima && mostraCarta && squadraUltima && ultima && <div className={`sorteggio__estratta sorteggio__estratta--${ultima.conferenza}`} key={ultima.ordine}>
        <small>Estratta per la {NOME_CONFERENZA[ultima.conferenza]}</small>
        <div className="sorteggio__estratta-stemma"><Crest value={squadraUltima.stemma_url} imageUrl={stemmi.get(squadraUltima.id)} size="large" stelle={squadraUltima.titoli_title} /></div>
        <strong>{squadraUltima.nome}</strong>
        <span>{squadraUltima.sigla}{squadraUltima.id === membership.id ? ' · La tua squadra' : ''}</span>
      </div>}

      {stato && !finito && !prima && !mostraCarta && <div className={`sorteggio__suspense sorteggio__suspense--${prossimaConferenza}`}>
        <h1>{estrazioni.length === 0 ? 'La prima squadra estratta per la' : 'La prossima squadra per la'} <em>{NOME_CONFERENZA[prossimaConferenza]}</em> è…</h1>
        <Roulette candidati={candidati} stemmi={stemmi} secondiRimasti={secondiRimasti} />
        <div className="sorteggio__conto" style={{ ['--p' as string]: `${Math.min(100, Math.max(0, 1 - secondiRimasti / SECONDI_ROULETTE) * 100)}%` }}>
          <b>{Math.ceil(secondiRimasti)}</b>
        </div>
      </div>}
    </section>

    <section className="sorteggio__colonne" aria-label="Conferenze">
      {(['est', 'ovest'] as const).map((c) => {
        const squadreConf = perConferenza(c)
        return <div className={`sorteggio__colonna sorteggio__colonna--${c}`} key={c}>
          <header><ConferenceBadge conferenza={c} /><strong>{NOME_CONFERENZA_BREVE[c]}</strong><span>{squadreConf.length}<i>/{meta}</i></span></header>
          <ol>
            {Array.from({ length: meta }, (_, i) => {
              const e = squadreConf[i]
              const t = e ? squadrePerId.get(e.team_id) : undefined
              const nuova = Boolean(e) && e!.ordine === dovute && secondiNelSlot < secondiCarta && !finito
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
