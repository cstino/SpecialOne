import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { motion, AnimatePresence } from 'motion/react'
import { cognome } from '../lib/nomi'
import { macroRuolo } from '../lib/ruoli'
import { supabase } from '../lib/supabase'
import { useSeasonData } from '../lib/useSeasonData'
import { formatCountdown, useOraCorrente } from '../lib/countdown'
import type { League, Membership } from '../types'
import { Crest } from './Crest'
import { GameNav, type GameView } from './GameNav'
import { LoadingLogo } from './LoadingLogo'
import { PopupSpiegazione } from './PopupSpiegazione'
import { SchedaGiocatore } from './SchedaGiocatore'
import { UnderlineTabs } from './ui/underline-tabs'

type Props = { membership: Membership; onNavigate: (view: GameView) => void }

type StatoProposta = 'in_attesa' | 'accettata' | 'rifiutata' | 'ritirata' | 'scaduta'

type Proposta = {
  id: number
  da_team_id: number
  a_team_id: number
  giocatori_offerti: number[]
  giocatori_richiesti: number[]
  scelte_offerte: number[]
  scelte_richieste: number[]
  messaggio: string | null
  stato: StatoProposta
  creata_il: string
  scade_il: string
  risolta_il?: string | null
  controproposta_di?: number | null
}

type Giocatore = {
  id: number
  player_id: number
  team_id: number
  overall: number
  eta: number
  ingaggio: number
  nome: string
  ruolo: string
  club?: string
  nazionalita?: string | null
  posizioni?: string[]
  piede?: string | null
  altezza?: number | null
  attributi?: Record<string, number | null>
  foto_firmata?: string
  condizione?: number
  infortunatoFinoA?: number
  ritiroAnnunciato?: boolean
}

type StatoScelta = 'futura' | 'determinata' | 'usata' | 'vuota'
type Scelta = {
  id: number
  team_origine_id: number
  team_proprietario_id: number
  stagione: number
  finestra: 'on' | 'off'
  posizione: number | null
  stato: StatoScelta
}

type Capienza = { stagione: number; tetto: number; monte: number; capienza: number; rosa: number; slot_liberi: number }

type TrattativaPubblica = {
  id: number
  da_team_id: number
  a_team_id: number
  giocatori_offerti: number[]
  giocatori_richiesti: number[]
  scelte_offerte: number[]
  scelte_richieste: number[]
}

const ETICHETTE_STATO: Record<StatoProposta, string> = {
  in_attesa: 'In attesa', accettata: 'Accettata', rifiutata: 'Rifiutata', ritirata: 'Ritirata', scaduta: 'Scaduta',
}

function minutiDalMezzanotteRoma() {
  const [ore, minuti] = new Intl.DateTimeFormat('it-IT', {
    timeZone: 'Europe/Rome', hour: '2-digit', minute: '2-digit', hour12: false,
  }).format(new Date()).split(':').map(Number)
  return ore * 60 + minuti
}
function mercatoAperto() {
  const ora = minutiDalMezzanotteRoma()
  return ora >= 23 * 60 + 30 || ora < 21 * 60
}
function milioni(euro: number) {
  return `${(euro / 1_000_000).toFixed(1).replace('.', ',')} M€`
}
function etichettaScelta(s: Scelta) {
  return `${s.finestra === 'on' ? 'ON' : 'OFF'}-Season ${s.stagione}`
}

export function Scambi({ membership, onNavigate }: Props) {
  const league = membership.league as League
  const dati = useSeasonData(membership)
  const adesso = useOraCorrente()
  const [rose, setRose] = useState<Giocatore[]>([])
  const [scelte, setScelte] = useState<Scelta[]>([])
  const [proposte, setProposte] = useState<Proposta[]>([])
  const [trattativePubbliche, setTrattativePubbliche] = useState<TrattativaPubblica[]>([])
  const [capienza, setCapienza] = useState<Capienza | null>(null)
  const [caricamento, setCaricamento] = useState(true)
  const [errore, setErrore] = useState<string | null>(null)

  const [avversaria, setAvversaria] = useState<number | null>(null)
  const [chiesti, setChiesti] = useState<number[]>([])
  const [offerti, setOfferti] = useState<number[]>([])
  const [scelteChieste, setScelteChieste] = useState<number[]>([])
  const [scelteOfferte, setScelteOfferte] = useState<number[]>([])
  const [messaggio, setMessaggio] = useState('')
  const [sceltaRifiutoId, setSceltaRifiutoId] = useState<number | null>(null)
  const [contropropostaOrigine, setContropropostaOrigine] = useState<Proposta | null>(null)
  const [inCorso, setInCorso] = useState(false)
  const [esito, setEsito] = useState<string | null>(null)
  const [schedaApertaId, setSchedaApertaId] = useState<number | null>(null)
  const [tabComposer, setTabComposer] = useState<'giocatori' | 'scelte'>('giocatori')
  const compositoreRef = useRef<HTMLElement>(null)

  const carica = useCallback(async (silenzioso = false) => {
    if (!silenzioso) setCaricamento(true)
    setErrore(null)
    const [istanzeRes, scelteRes, proposteRes, trattativeRes, capienzaRes] = await Promise.all([
      supabase.from('player_instances')
        .select('id, team_id, player_id, overall_corrente, eta_corrente, ingaggio, condizione, infortunato_fino_a, ritiro_annunciato')
        .eq('league_id', league.id).not('team_id', 'is', null),
      supabase.from('scelte_draft')
        .select('id, team_origine_id, team_proprietario_id, stagione, finestra, posizione, stato')
        .eq('league_id', league.id).in('stato', ['futura', 'determinata'])
        .order('stagione').order('finestra'),
      supabase.from('trade_proposals').select('*').eq('league_id', league.id).order('creata_il', { ascending: false }),
      supabase.rpc('trattative_pubbliche', { p_league_id: league.id }),
      supabase.rpc('capienza_squadra', { p_league_id: league.id }),
    ])
    const primoErrore = istanzeRes.error ?? scelteRes.error ?? proposteRes.error
    if (primoErrore) { setErrore(primoErrore.message); setCaricamento(false); return }

    const istanze = istanzeRes.data ?? []
    const daCercare = [...new Set(istanze.map((i) => i.player_id))]
    const { data: anagrafica, error: erroreAnagrafica } = daCercare.length
      ? await supabase.from('players').select('id, nome, club, nazionalita, posizioni, piede, altezza, attributi, overall, eta, foto_url').in('id', daCercare)
      : { data: [], error: null }
    if (erroreAnagrafica) { setErrore(erroreAnagrafica.message); setCaricamento(false); return }

    const fotoFirmate = await Promise.all((anagrafica ?? [])
      .filter((p) => p.foto_url)
      .map(async (p) => {
        if (p.foto_url?.startsWith('http')) return [p.id, p.foto_url] as const
        const { data } = await supabase.storage.from('player-photos').createSignedUrl(p.foto_url!, 3600)
        return [p.id, data?.signedUrl] as const
      }))
    const fotoPerId = new Map(fotoFirmate.filter((e): e is readonly [number, string] => Boolean(e[1])))
    const perId = new Map((anagrafica ?? []).map((p) => [p.id, p as {
      id: number; nome: string; club: string; nazionalita: string | null; posizioni: string[]
      piede: string | null; altezza: number | null; attributi: Record<string, number | null>
      overall: number; eta: number; foto_url: string | null
    }]))

    setProposte((proposteRes.data ?? []) as Proposta[])
    setTrattativePubbliche(trattativeRes.error ? [] : (trattativeRes.data ?? []) as TrattativaPubblica[])
    setScelte((scelteRes.data ?? []) as Scelta[])
    setCapienza(capienzaRes.error ? null : capienzaRes.data as Capienza)
    setRose(istanze.map((i) => ({
      id: i.id, player_id: i.player_id, team_id: i.team_id as number,
      overall: i.overall_corrente, eta: i.eta_corrente, ingaggio: i.ingaggio,
      nome: cognome(perId.get(i.player_id)?.nome ?? '—'),
      ruolo: perId.get(i.player_id)?.posizioni?.[0] ?? '—',
      club: perId.get(i.player_id)?.club,
      nazionalita: perId.get(i.player_id)?.nazionalita,
      posizioni: perId.get(i.player_id)?.posizioni,
      piede: perId.get(i.player_id)?.piede,
      altezza: perId.get(i.player_id)?.altezza,
      attributi: perId.get(i.player_id)?.attributi,
      foto_firmata: fotoPerId.get(i.player_id),
      condizione: i.condizione,
      infortunatoFinoA: i.infortunato_fino_a,
      ritiroAnnunciato: i.ritiro_annunciato,
    })))
    setCaricamento(false)
  }, [league.id])

  useEffect(() => { void carica() }, [carica])

  const nomeSquadra = useCallback((id: number) => dati.teamById.get(id)?.nome ?? 'Squadra', [dati.teamById])
  const stemma = useCallback((id: number) => <Crest
    value={dati.teamById.get(id)?.stemma_url ?? null}
    imageUrl={dati.crestUrlByTeamId.get(id) ?? null}
  />, [dati.teamById, dati.crestUrlByTeamId])
  const giocatore = useCallback((id: number) => rose.find((g) => g.id === id), [rose])
  const sceltaDati = useCallback((id: number) => scelte.find((s) => s.id === id), [scelte])

  // Stesso orologio dinamico del mercato svincolati: dopo l'ultima partita
  // simulata, prima della prossima. Fuori da un ciclo di stagione (draft,
  // off-season) resta l'orario fisso 23:30-21:00.
  const ultimaPartitaIl = useMemo(() => dati.matches.reduce<number | null>((u, p) => {
    const t = new Date(p.simulata_il).getTime()
    return u == null || t > u ? t : u
  }, null), [dati.matches])
  const prossimaPartitaIl = dati.fixtures.filter((f) => f.stato === 'programmata')
    .reduce<number | null>((p, f) => { const t = new Date(f.data_sim).getTime(); return p == null || t < p ? t : p }, null)
  const cicloDinamico = ultimaPartitaIl != null && prossimaPartitaIl != null
  const aperturaMercatoIl = ultimaPartitaIl == null ? null : ultimaPartitaIl + 30 * 60 * 1000
  const chiusuraMercatoIl = prossimaPartitaIl == null ? null : prossimaPartitaIl - 2 * 60 * 60 * 1000
  const mercatoDinamicoAperto = cicloDinamico && aperturaMercatoIl != null && chiusuraMercatoIl != null
    && adesso >= aperturaMercatoIl && adesso < chiusuraMercatoIl
  const aperto = cicloDinamico ? mercatoDinamicoAperto : mercatoAperto()
  const etichettaMercato = cicloDinamico
    ? aperto
      ? `Mercato aperto · chiude tra ${formatCountdown(Math.max(0, (chiusuraMercatoIl ?? adesso) - adesso))}`
      : adesso < (aperturaMercatoIl ?? 0)
        ? `Mercato chiuso · apre tra ${formatCountdown(Math.max(0, (aperturaMercatoIl ?? adesso) - adesso))}`
        : 'Mercato chiuso · in attesa della prossima partita'
    : aperto ? 'Mercato aperto · chiude alle 21:00' : 'Mercato chiuso · apre alle 23:30'

  const miaRosa = useMemo(() => rose.filter((g) => g.team_id === membership.id).sort((a, b) => b.overall - a.overall), [rose, membership.id])
  const rosaAvversaria = useMemo(() => rose.filter((g) => g.team_id === avversaria).sort((a, b) => b.overall - a.overall), [rose, avversaria])
  const mieScelte = useMemo(() => scelte.filter((s) => s.team_proprietario_id === membership.id)
    .sort((a, b) => a.stagione - b.stagione || a.finestra.localeCompare(b.finestra)), [scelte, membership.id])
  const scelteAvversaria = useMemo(() => scelte.filter((s) => s.team_proprietario_id === avversaria)
    .sort((a, b) => a.stagione - b.stagione || a.finestra.localeCompare(b.finestra)), [scelte, avversaria])

  const ricevute = proposte.filter((p) => p.a_team_id === membership.id && p.stato === 'in_attesa')
  const inviate = proposte.filter((p) => p.da_team_id === membership.id && p.stato === 'in_attesa')
  const concluse = proposte.filter((p) => p.stato === 'accettata')

  function giornoRoma(v: Date | string) {
    return new Intl.DateTimeFormat('en-CA', { timeZone: 'Europe/Rome', year: 'numeric', month: '2-digit', day: '2-digit' }).format(new Date(v))
  }
  const oggiRoma = giornoRoma(new Date())
  const concluseOggi = concluse.filter((p) => p.risolta_il && giornoRoma(p.risolta_il) === oggiRoma)

  async function chiama(azione: () => PromiseLike<{ error: { message: string } | null }>, successo: string, durataMinima = 0) {
    const partenza = performance.now()
    setInCorso(true)
    setEsito(null)
    try {
      const { error } = await azione()
      setEsito(error ? error.message : successo)
      if (!error) await carica(true)
      const attesa = Math.max(0, durataMinima - (performance.now() - partenza))
      if (attesa) await new Promise((r) => window.setTimeout(r, attesa))
      return !error
    } finally { setInCorso(false) }
  }

  function alterna(elenco: number[], id: number, imposta: (v: number[]) => void) {
    imposta(elenco.includes(id) ? elenco.filter((x) => x !== id) : [...elenco, id])
  }

  async function invia() {
    if (!avversaria) return
    const riuscita = await chiama(
      () => supabase.rpc(contropropostaOrigine ? 'controproponi' : 'proponi_scambio', {
        ...(contropropostaOrigine ? { p_proposta_id: contropropostaOrigine.id } : { p_a_team_id: avversaria }),
        p_giocatori_offerti: offerti,
        p_giocatori_richiesti: chiesti,
        p_scelte_offerte: scelteOfferte,
        p_scelte_richieste: scelteChieste,
        p_messaggio: messaggio.trim() || null,
      }),
      contropropostaOrigine ? 'Controfferta inviata.' : 'Proposta inviata.',
    )
    if (riuscita) {
      setChiesti([]); setOfferti([]); setScelteChieste([]); setScelteOfferte([]); setMessaggio('')
      setContropropostaOrigine(null)
    }
  }

  function preparaControfferta(p: Proposta) {
    setContropropostaOrigine(p)
    setAvversaria(p.da_team_id)
    setOfferti([...p.giocatori_richiesti])
    setChiesti([...p.giocatori_offerti])
    setScelteOfferte([...p.scelte_richieste])
    setScelteChieste([...p.scelte_offerte])
    setMessaggio('Controfferta')
    setSceltaRifiutoId(null)
    window.requestAnimationFrame(() => compositoreRef.current?.scrollIntoView({ behavior: 'smooth', block: 'start' }))
  }
  function annullaControfferta() {
    setContropropostaOrigine(null); setAvversaria(null)
    setChiesti([]); setOfferti([]); setScelteChieste([]); setScelteOfferte([]); setMessaggio('')
  }

  const nPacchettoOfferto = offerti.length + scelteOfferte.length
  const nPacchettoChiesto = chiesti.length + scelteChieste.length

  const listaGiocatori = (elenco: Giocatore[], selezionati: number[], imposta: (v: number[]) => void, vuoto: string) =>
    elenco.length === 0
      ? <p className="scambi-vuoto">{vuoto}</p>
      : <ul className="scambi-asset-grid">
          {elenco.map((g) => <li key={g.id}>
            <button type="button" className={`scambi-asset-card scambi-asset-card--player ${selezionati.includes(g.id) ? 'is-scelto' : ''}`}
              onClick={() => alterna(selezionati, g.id, imposta)} aria-pressed={selezionati.includes(g.id)}>
              <span className={`scambi-asset-card__ovr role-pill--${macroRuolo(g.posizioni ?? [g.ruolo]).toLowerCase()}`}>{g.overall}</span>
              <span className="scambi-asset-card__info"><strong>{g.nome}</strong><small>{g.ruolo} · {g.eta} anni · {milioni(g.ingaggio)}</small></span>
              {selezionati.includes(g.id) && <span className="scambi-asset-card__check" aria-hidden="true">✓</span>}
            </button>
          </li>)}
        </ul>

  const listaScelte = (elenco: Scelta[], selezionati: number[], imposta: (v: number[]) => void, vuoto: string) =>
    elenco.length === 0
      ? <p className="scambi-vuoto">{vuoto}</p>
      : <ul className="scambi-asset-grid">
          {elenco.map((s) => <li key={s.id}>
            <button type="button" className={`scambi-asset-card scambi-asset-card--pick scambi-asset-card--pick-${s.finestra} ${selezionati.includes(s.id) ? 'is-scelto' : ''}`}
              onClick={() => alterna(selezionati, s.id, imposta)} aria-pressed={selezionati.includes(s.id)}>
              <span className="scambi-asset-card__pickbadge">{s.finestra === 'on' ? 'ON' : 'OFF'}</span>
              <span className="scambi-asset-card__info">
                <strong>Stagione {s.stagione}</strong>
                <small>{s.stato === 'determinata' && s.posizione ? `${s.posizione}ª scelta` : 'posizione da definire'} · origine {nomeSquadra(s.team_origine_id)}</small>
              </span>
              {selezionati.includes(s.id) && <span className="scambi-asset-card__check" aria-hidden="true">✓</span>}
            </button>
          </li>)}
        </ul>

  const pacchettoChip = (id: number, tipo: 'g' | 's') => tipo === 'g'
    ? <button key={`g${id}`} type="button" className="scambi-chip scambi-chip--player" onClick={() => setSchedaApertaId(id)}>
        {giocatore(id)?.nome ?? `#${id}`}
      </button>
    : <span key={`s${id}`} className={`scambi-chip scambi-chip--pick scambi-chip--pick-${sceltaDati(id)?.finestra ?? 'on'}`}>
        {sceltaDati(id) ? etichettaScelta(sceltaDati(id)!) : `#${id}`}
      </span>

  const riepilogo = (p: Proposta) => <>
    <div className="scambi-riepilogo">
      <div className="scambi-riepilogo__lato">
        <small>{p.da_team_id === membership.id ? 'Offri' : 'Ti offre'}</small>
        <div className="scambi-riepilogo__chips">
          {p.giocatori_offerti.length + p.scelte_offerte.length === 0
            ? <span className="scambi-nessuno">niente</span>
            : <>{p.giocatori_offerti.map((id) => pacchettoChip(id, 'g'))}{p.scelte_offerte.map((id) => pacchettoChip(id, 's'))}</>}
        </div>
      </div>
      <i className="scambi-riepilogo__freccia" aria-hidden="true">⇄</i>
      <div className="scambi-riepilogo__lato">
        <small>{p.da_team_id === membership.id ? 'Chiedi' : 'Ti chiede'}</small>
        <div className="scambi-riepilogo__chips">
          {p.giocatori_richiesti.length + p.scelte_richieste.length === 0
            ? <span className="scambi-nessuno">niente</span>
            : <>{p.giocatori_richiesti.map((id) => pacchettoChip(id, 'g'))}{p.scelte_richieste.map((id) => pacchettoChip(id, 's'))}</>}
        </div>
      </div>
    </div>
    {p.messaggio && <p className="scambi-messaggio">«{p.messaggio}»</p>}
  </>

  const schedaAperta = schedaApertaId != null ? giocatore(schedaApertaId) : undefined
  const capienzaPct = capienza ? Math.min(100, Math.max(0, (capienza.monte / Math.max(capienza.tetto, 1)) * 100)) : 0
  const capienzaCritica = capienza ? capienza.capienza < 0 : false

  return <main className="app-shell season-shell scambi-shell">
    <GameNav league={league} active="scambi" onNavigate={onNavigate} />
    <header className="topbar season-topbar">
      <div className="brand-lockup brand-lockup--dark"><img src="/specialone-mark.svg" alt="" /><span>SpecialOne</span></div>
      <span className={`mercato-finestra ${aperto ? 'e-aperto' : ''}`}>{etichettaMercato}</span>
    </header>

    {caricamento && <div className="season-page"><section className="season-state mercato-caricamento"><LoadingLogo compatto /><h2>Preparo il mercato scambi…</h2><p>Recupero rose, scelte e trattative.</p></section></div>}
    {errore && <div className="season-page"><p className="season-empty">{errore}</p></div>}

    {!caricamento && !errore && <div className="season-page season-page--narrow scambi-page">
      <PopupSpiegazione userId={membership.user_id} hintKey="scambi" titolo="Come funzionano gli Scambi">
        <p>Si scambiano giocatori e scelte di draft insieme, come in NBA: <strong>nessun conguaglio in denaro</strong>,
          si tratta alla pari sotto lo stesso tetto salariale per tutti.</p>
        <p>Dopo lo scambio entrambe le rose devono restare fra 21 e 30 giocatori e sotto il tetto ingaggi. Una
          scelta di draft ceduta non può lasciare una squadra senza una propria scelta d'origine per due
          finestre consecutive (regola Stepien) — evita di svendere tutto il futuro in un colpo solo. Un
          giocatore appena scambiato è comunque scambiabile di nuovo subito: il vincolo delle 10 giornate prima
          di poter essere svincolato riguarda solo lo svincolo, non un nuovo scambio.</p>
      </PopupSpiegazione>
      <section className="season-title-row">
        <div>
          <p className="kicker">Stagione {league.stagione_corrente} · {league.nome}</p>
          <h1 className="scambi-title">Scambi.</h1>
        </div>
        {capienza && <div className={`scambi-gauge ${capienzaCritica ? 'is-critica' : ''}`}>
          <div className="scambi-gauge__numeri">
            <strong>{milioni(Math.max(0, capienza.capienza))}</strong>
            <span>{capienzaCritica ? 'oltre il tetto' : 'capienza libera'}</span>
          </div>
          <div className="scambi-gauge__barra" role="img" aria-label={`Monte ingaggi ${milioni(capienza.monte)} su tetto ${milioni(capienza.tetto)}`}>
            <motion.div className="scambi-gauge__riempimento" initial={{ width: 0 }} animate={{ width: `${capienzaPct}%` }} transition={{ duration: 0.7, ease: 'easeOut' }} />
          </div>
          <small>{milioni(capienza.monte)} di {milioni(capienza.tetto)} · stagione {capienza.stagione} · {capienza.slot_liberi} slot liberi</small>
        </div>}
      </section>

      {esito && <p className="notice">{esito}</p>}

      {/* ---- Ricevute ---- */}
      <section className="scambi-blocco">
        <div className="sezione-testa"><div><p className="kicker">In arrivo</p><h2>Proposte ricevute</h2></div>
          {ricevute.length > 0 && <span className="scambi-badge-contatore">{ricevute.length}</span>}
        </div>
        {ricevute.length === 0
          ? <p className="season-empty">Nessuna proposta da valutare.</p>
          : <div className="scambi-proposte-grid">
              <AnimatePresence>
                {ricevute.map((p) => <motion.article layout initial={{ opacity: 0, y: 8 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0, scale: 0.96 }} className="scambi-card" key={p.id}>
                  <header>{stemma(p.da_team_id)}<strong>{nomeSquadra(p.da_team_id)}</strong></header>
                  {riepilogo(p)}
                  <footer className={sceltaRifiutoId === p.id ? 'scambi-rifiuto-aperto' : ''}>
                    {sceltaRifiutoId !== p.id ? <>
                      <button className="button button--primary" type="button" disabled={inCorso || !aperto}
                        onClick={() => chiama(() => supabase.rpc('rispondi_a_proposta', { p_proposta_id: p.id, p_accetta: true }), 'Scambio concluso.')}>
                        Accetta
                      </button>
                      <button className="button button--secondary" type="button" disabled={inCorso} onClick={() => setSceltaRifiutoId(p.id)}>Rifiuta</button>
                    </> : <>
                      <button className="button button--primary" type="button" disabled={inCorso || !aperto} onClick={() => preparaControfferta(p)}>Controfferta</button>
                      <button className="button button--danger-ghost" type="button" disabled={inCorso}
                        onClick={() => chiama(() => supabase.rpc('rispondi_a_proposta', { p_proposta_id: p.id, p_accetta: false }), 'Proposta rifiutata.')}>
                        Rifiuta
                      </button>
                    </>}
                  </footer>
                </motion.article>)}
              </AnimatePresence>
            </div>}
      </section>

      {/* ---- Compositore ---- */}
      <section className="scambi-blocco scambi-compositore" ref={compositoreRef}>
        <div className="sezione-testa">
          <div>
            <p className="kicker">{contropropostaOrigine ? 'Risposta alla trattativa' : 'Tratta'}</p>
            <h2>{contropropostaOrigine ? `Controfferta a ${nomeSquadra(contropropostaOrigine.da_team_id)}` : 'Nuova proposta'}</h2>
          </div>
          {contropropostaOrigine && <button className="button button--secondary" type="button" disabled={inCorso} onClick={annullaControfferta}>Annulla</button>}
        </div>
        {contropropostaOrigine && <p className="notice">La proposta ricevuta è stata invertita: puoi cambiare giocatori e scelte prima di inviarla.</p>}
        {!aperto && <p className="notice">Il mercato è chiuso: puoi preparare la proposta ma potrai inviarla quando riapre.</p>}

        {!contropropostaOrigine && <div className="scambi-scelta-squadra">
          {dati.teams.filter((s) => s.id !== membership.id).map((s) => <button key={s.id} type="button"
            className={avversaria === s.id ? 'is-scelto' : ''}
            onClick={() => { setAvversaria(s.id); setChiesti([]); setScelteChieste([]) }}
            aria-label={s.nome} aria-pressed={avversaria === s.id} title={s.nome}>
            {stemma(s.id)}
          </button>)}
        </div>}

        {avversaria && <>
          <UnderlineTabs
            tabs={[{ value: 'giocatori', label: 'Giocatori' }, { value: 'scelte', label: 'Scelte di draft' }] as const}
            value={tabComposer}
            onChange={setTabComposer}
            layoutId="scambi-composer-indicator"
            className="mb-4"
          />

          <div className="scambi-colonne">
            <div>
              <h3>Cosa chiedi a {nomeSquadra(avversaria)}</h3>
              {tabComposer === 'giocatori'
                ? listaGiocatori(rosaAvversaria, chiesti, setChiesti, 'Rosa non disponibile.')
                : listaScelte(scelteAvversaria, scelteChieste, setScelteChieste, 'Nessuna scelta scambiabile.')}
            </div>
            <div>
              <h3>Cosa offri</h3>
              {tabComposer === 'giocatori'
                ? listaGiocatori(miaRosa, offerti, setOfferti, 'La tua rosa è vuota.')
                : listaScelte(mieScelte, scelteOfferte, setScelteOfferte, 'Nessuna scelta scambiabile.')}
            </div>
          </div>

          {(nPacchettoOfferto > 0 || nPacchettoChiesto > 0) && <div className="scambi-anteprima">
            <div className="scambi-anteprima__lato">
              <span className="scambi-anteprima__conteggio">{nPacchettoOfferto}</span>
              <div className="scambi-anteprima__chips">{offerti.map((id) => pacchettoChip(id, 'g'))}{scelteOfferte.map((id) => pacchettoChip(id, 's'))}</div>
            </div>
            <i aria-hidden="true">⇄</i>
            <div className="scambi-anteprima__lato">
              <span className="scambi-anteprima__conteggio">{nPacchettoChiesto}</span>
              <div className="scambi-anteprima__chips">{chiesti.map((id) => pacchettoChip(id, 'g'))}{scelteChieste.map((id) => pacchettoChip(id, 's'))}</div>
            </div>
          </div>}

          <div className="scambi-messaggio-riga">
            <label>
              <span>Messaggio (facoltativo)</span>
              <input type="text" value={messaggio} maxLength={240} onChange={(e) => setMessaggio(e.target.value)} placeholder="Due righe per convincerlo" />
            </label>
          </div>

          <button className="button button--primary scambi-invia" type="button"
            disabled={inCorso || !aperto || (nPacchettoOfferto === 0 && nPacchettoChiesto === 0)}
            onClick={() => void invia()}>
            {inCorso ? 'Invio…' : contropropostaOrigine ? 'Invia la controfferta' : 'Invia la proposta'}
          </button>
        </>}
      </section>

      {/* ---- Inviate ---- */}
      <section className="scambi-blocco">
        <div className="sezione-testa"><div><p className="kicker">In uscita</p><h2>Proposte inviate</h2></div></div>
        {inviate.length === 0
          ? <p className="season-empty">Nessuna proposta in attesa di risposta.</p>
          : <div className="scambi-proposte-grid">{inviate.map((p) => <article className="scambi-card" key={p.id}>
              <header>{stemma(p.a_team_id)}<strong>A {nomeSquadra(p.a_team_id)}</strong></header>
              {riepilogo(p)}
              <footer>
                <button className="button button--secondary" type="button" disabled={inCorso}
                  onClick={() => chiama(() => supabase.rpc('ritira_proposta', { p_proposta_id: p.id }), 'Proposta ritirata.')}>
                  Ritira
                </button>
              </footer>
            </article>)}</div>}
      </section>

      {/* ---- Rumors ---- */}
      <section className="scambi-blocco">
        <div className="sezione-testa"><div><p className="kicker">Voci di mercato</p><h2>Trattative in corso</h2></div></div>
        {trattativePubbliche.length === 0
          ? <p className="season-empty">Nessuna trattativa aperta al momento.</p>
          : <ul className="scambi-rumors">
              {trattativePubbliche.slice(0, 6).map((t) => <li key={t.id} className="scambi-rumor-riga">
                <span className="scambi-rumor-stemma">{stemma(t.da_team_id)}</span>
                <div className="scambi-rumor-conteggio">
                  <b>{t.giocatori_offerti.length + t.scelte_offerte.length}</b>
                  <small>asset</small>
                </div>
                <i aria-hidden="true">⇄</i>
                <div className="scambi-rumor-conteggio">
                  <b>{t.giocatori_richiesti.length + t.scelte_richieste.length}</b>
                  <small>asset</small>
                </div>
                <span className="scambi-rumor-stemma">{stemma(t.a_team_id)}</span>
              </li>)}
            </ul>}
      </section>

      {/* ---- Trasparenza ---- */}
      <section className="scambi-blocco">
        <div className="sezione-testa"><div><p className="kicker">Trasparenza</p><h2>Scambi conclusi oggi</h2></div></div>
        {concluseOggi.length === 0
          ? <p className="season-empty">Nessuno scambio concluso oggi.</p>
          : <ul className="scambi-trasparenza">
              {concluseOggi.map((p) => <li className="scambi-operazione" key={p.id}>
                <div className="scambi-operazione__lato">
                  {stemma(p.da_team_id)}
                  <div className="scambi-operazione__chips">{p.giocatori_offerti.map((id) => pacchettoChip(id, 'g'))}{p.scelte_offerte.map((id) => pacchettoChip(id, 's'))}</div>
                </div>
                <i aria-hidden="true">⇄</i>
                <div className="scambi-operazione__lato scambi-operazione__lato--destra">
                  <div className="scambi-operazione__chips">{p.giocatori_richiesti.map((id) => pacchettoChip(id, 'g'))}{p.scelte_richieste.map((id) => pacchettoChip(id, 's'))}</div>
                  {stemma(p.a_team_id)}
                </div>
                <em>{ETICHETTE_STATO[p.stato]}</em>
              </li>)}
            </ul>}
      </section>

      {schedaAperta && <SchedaGiocatore
        giocatore={{
          nome: schedaAperta.nome, club: schedaAperta.club, nazionalita: schedaAperta.nazionalita,
          posizioni: schedaAperta.posizioni ?? [schedaAperta.ruolo], overall: schedaAperta.overall, eta: schedaAperta.eta,
          piede: schedaAperta.piede, altezza: schedaAperta.altezza, ingaggio: schedaAperta.ingaggio,
          condizione: schedaAperta.condizione, infortunatoFinoA: schedaAperta.infortunatoFinoA,
          ritiroAnnunciato: schedaAperta.ritiroAnnunciato, attributi: schedaAperta.attributi ?? {},
        }}
        fotoUrl={schedaAperta.foto_firmata}
        onClose={() => setSchedaApertaId(null)}
      />}
    </div>}
  </main>
}
