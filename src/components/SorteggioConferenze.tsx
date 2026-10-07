import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { supabase } from '../lib/supabase'
import { firmaStemmi } from '../lib/premiAlbo'
import { ANTICIPO_PRIMA_ESTRAZIONE, NOME_CONFERENZA, NOME_CONFERENZA_BREVE, SECONDI_ROULETTE, type Conferenza } from '../lib/conferenze'
import type { League, Membership, Team } from '../types'
import { Crest } from './Crest'
import { ConferenceBadge } from './ConferenceBadge'
import { ReazioniLive } from './ReazioniLive'

type DemoSorteggio = { stato: Stato; estrazioni: Estrazione[]; squadre: Team[]; adesso: number }
type Props = { membership: Membership; onFine: () => void; onMenu?: () => void; demo?: DemoSorteggio }

type Stato = {
  sorteggio_id: number; stagione: number; avviato_il: string; passo_secondi: number
  totale: number; rivelate: number; completato: boolean; ora_server: string
}
type Estrazione = { ordine: number; team_id: number; conferenza: Conferenza }


// Caricamento dell'estrazione: anelli che girano nel colore della conference che sta per
// ricevere la squadra, un anello che si riempie negli ultimi secondi e, al termine, la
// squadra si rivela. Sostituisce la roulette dei loghi: l'estratta non e' nota a nessuno.
function Caricamento({ conferenza, secondiRimasti, attendi = false }: { conferenza: Conferenza; secondiRimasti: number; attendi?: boolean }) {
  const avanzamento = Math.min(100, Math.max(0, (1 - secondiRimasti / SECONDI_ROULETTE) * 100))
  // `attendi`: il turno e' scattato ma il nome non e' ancora arrivato dal server: gira senza numero.
  const gira = attendi || secondiRimasti <= SECONDI_ROULETTE
  return <div className={`sorteggio__carica sorteggio__carica--${conferenza}${gira ? ' is-gira' : ''}`} aria-hidden="true">
    <svg viewBox="0 0 200 200" className="sorteggio__carica-anelli">
      <circle className="sorteggio__carica-pista" cx="100" cy="100" r="92" />
      <circle className="sorteggio__carica-prog" cx="100" cy="100" r="92" pathLength="100" strokeDasharray={`${attendi ? 100 : avanzamento} ${attendi ? 0 : 100 - avanzamento}`} />
      <circle className="sorteggio__carica-tacche" cx="100" cy="100" r="80" />
      <circle className="sorteggio__carica-tacche sorteggio__carica-tacche--inverso" cx="100" cy="100" r="66" />
    </svg>
    <div className="sorteggio__carica-nucleo"><ConferenceBadge conferenza={conferenza} /></div>
    <b>{attendi ? '' : Math.ceil(secondiRimasti)}</b>
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
  const secondiAllAvvio = stato ? Math.max(0, (avviatoMs + ANTICIPO_PRIMA_ESTRAZIONE * 1000 - adesso) / 1000) : 0
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
    const timer = window.setInterval(() => { void aggiorna() }, attesa ? 500 : 5000)
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
  const perConferenza = (c: Conferenza) => estrazioni.filter((e) => e.conferenza === c)
  const meta = Math.max(1, Math.floor((stato?.totale ?? squadre.length) / 2))

  const ultima = estrazioni.length > 0 ? estrazioni[estrazioni.length - 1] : null
  const mostraCarta = Boolean(ultima) && dovute >= 1 && ultima!.ordine === dovute && secondiNelSlot < secondiCarta && !finito
  const prossimo = dovute + 1
  const prossimaConferenza: Conferenza = prossimo % 2 === 1 ? 'est' : 'ovest'
  const squadraUltima = ultima ? squadrePerId.get(ultima.team_id) : undefined
  // Turno scattato ma estratta non ancora arrivata: si mostra l'attesa della squadra che sta per uscire (non la prossima).
  const attendiDati = Boolean(stato) && !finito && !prima && dovute >= 1 && estrazioni.length < dovute
  const confInArrivo: Conferenza = dovute % 2 === 1 ? 'est' : 'ovest'

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
        <div className="sorteggio__estratta-stemma"><span className="sorteggio__onda" aria-hidden="true" /><Crest value={squadraUltima.stemma_url} imageUrl={stemmi.get(squadraUltima.id)} size="large" stelle={squadraUltima.titoli_title} /></div>
        <strong>{squadraUltima.nome}</strong>
        <span>{squadraUltima.sigla}{squadraUltima.id === membership.id ? ' · La tua squadra' : ''}</span>
      </div>}

      {stato && !finito && !prima && !mostraCarta && attendiDati && <div className={`sorteggio__suspense sorteggio__suspense--${confInArrivo}`}>
        <h1>La squadra estratta per la <em>{NOME_CONFERENZA[confInArrivo]}</em> è…</h1>
        <Caricamento conferenza={confInArrivo} secondiRimasti={0} attendi />
        <p className="sorteggio__carica-testo">Estrazione in corso<i>.</i><i>.</i><i>.</i></p>
      </div>}

      {stato && !finito && !prima && !mostraCarta && !attendiDati && <div className={`sorteggio__suspense sorteggio__suspense--${prossimaConferenza}`}>
        <h1>{estrazioni.length === 0 ? 'La prima squadra estratta per la' : 'La prossima squadra per la'} <em>{NOME_CONFERENZA[prossimaConferenza]}</em> è…</h1>
        <Caricamento conferenza={prossimaConferenza} secondiRimasti={secondiRimasti} />
        <p className="sorteggio__carica-testo">{secondiRimasti <= SECONDI_ROULETTE ? 'Estrazione in corso' : 'Preparo l\'estrazione'}<i>.</i><i>.</i><i>.</i></p>
      </div>}
    </section>

    <ReazioniLive leagueId={league.id} contesto="sorteggio" mioTeamId={membership.id} sigla={(id) => squadrePerId.get(id)?.sigla ?? '—'} demo={demo ? { teamIds: demo.squadre.map((t) => t.id) } : undefined} />

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
