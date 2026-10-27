import { useCallback, useEffect, useMemo, useRef, useState, type ReactNode } from 'react'
import { motion, AnimatePresence } from 'motion/react'
import { cognome } from '../lib/nomi'
import { MACRO_COLORE, MACRO_LABEL, ORDINE_MACRO_RUOLO, macroRuolo, type MacroRuolo, ruoloIt } from '../lib/ruoli'
import { supabase } from '../lib/supabase'
import { urlFotoGiocatore } from '../lib/fotoGiocatore'
import { useSeasonData } from '../lib/useSeasonData'
import { formatCountdown, oraServerAdesso, useOraCorrente } from '../lib/countdown'
import type { League, Membership } from '../types'
import { Crest } from './Crest'
import { GameNav, type GameView } from './GameNav'
import { LoadingLogo } from './LoadingLogo'
import { PopupSpiegazione } from './PopupSpiegazione'
import { SchedaGiocatore } from './SchedaGiocatore'
import { attributiInLega, attributiIstanza, type Attributi } from '../lib/attributiGiocatore'
import { SegnaMercato } from './SegnaMercato'
import { UnderlineTabs } from './ui/underline-tabs'
import { useFaseSquadra } from '../lib/faseSquadra'
import { useFaseMercato, ETICHETTA_SCAMBI_CHIUSO } from '../lib/faseMercato'

// Ordine di CALENDARIO, non alfabetico. Dentro una stagione l'ON-Season cade a
// meta' campionato e l'OFF-Season alla fine, quindi viene prima la ON:
//   ON-1, OFF-1, ON-2, OFF-2, ...
// Prima si ordinava per finestra con localeCompare, e siccome 'off' precede
// 'on' in ordine alfabetico l'elenco mostrava OFF-2 sopra ON-2. Stessa tabella
// gia' usata in Scelte.tsx.
const ORDINE_FINESTRA: Record<'on' | 'off', number> = { on: 0, off: 1 }
const perCalendario = (a: { stagione: number; finestra: 'on' | 'off' }, b: { stagione: number; finestra: 'on' | 'off' }) =>
  a.stagione - b.stagione || ORDINE_FINESTRA[a.finestra] - ORDINE_FINESTRA[b.finestra]

// scorriAConclusi: un numero che cresce quando si arriva da una notifica «scambio ufficiale»;
// a pagina caricata si scorre al riepilogo degli scambi della stagione.
type Props = {
  membership: Membership
  onNavigate: (view: GameView) => void
  scorriAConclusi?: number
  // Arrivando dalla scheda di un giocatore altrui (Club): squadra e giocatore da chiedere.
  preselezione?: { teamId: number; istanzaId: number } | null
  onPreselezioneUsata?: () => void
  // Da una notifica di mercato: la proposta da mostrare (n cresce a ogni tocco, anche sulla stessa proposta).
  propostaDaMostrare?: { id: number; n: number } | null
}

// I ruoli cercabili, nell'ordine del campo (codici del database, sigle in italiano a schermo).
const RUOLI_RICERCA = ['GK', 'CB', 'RB', 'LB', 'CDM', 'CM', 'RM', 'LM', 'CAM', 'RW', 'LW', 'ST']
const LIMITE_RISULTATI = 30
// I voti di equilibrio degli scambi conclusi sono nascosti (19/10/2026). Il calcolo resta: per mostrarli basta true.
const MOSTRA_VOTI = false
const soloCifre = (v: string) => v.replace(/\D/g, '').slice(0, 3)
const numeroOppure = (v: string): number | null => (v === '' ? null : Number(v))

type StatoProposta = 'in_attesa' | 'accettata' | 'rifiutata' | 'ritirata' | 'scaduta'

type Proposta = {
  id: number
  da_team_id: number
  a_team_id: number
  giocatori_offerti: number[]
  giocatori_richiesti: number[]
  scelte_offerte: number[]
  scelte_richieste: number[]
  vivaio_offerti?: number[]
  vivaio_richiesti?: number[]
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
  nomeEsteso?: string | null
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
  sulMercato?: boolean
}

// Un prospetto del vivaio (scambiabile dal 19/10/2026: finisce nel vivaio di chi lo riceve, se ha uno slot libero).
type Prospetto = { id: number; team_id: number; player_id: number; nome: string; overall: number; eta: number; ruolo: string; posizioni: string[]; giornate: number; ingaggio: number; potMin: number | null; potMax: number | null }

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

type PezzoValutato = { lato: 'da' | 'a'; tipo: 'g' | 's'; etichetta: string; overall: number | null; eta: number | null; valore: number }
type Valutazione = { proposta_id: number; voto: number; valore_da: number; valore_a: number; dettaglio: PezzoValutato[] }

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
  }).format(new Date(oraServerAdesso())).split(':').map(Number)
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

export function Scambi({ membership, onNavigate, scorriAConclusi = 0, preselezione = null, onPreselezioneUsata, propostaDaMostrare = null }: Props) {
  const league = membership.league as League
  const dati = useSeasonData(membership)
  // Colori della fase (verde regular, blu title, arancio draft), come Rosa e dashboard.
  const fase = useFaseSquadra(league.id, membership.id, dati.season?.id)
  const faseMercato = useFaseMercato(league.id)
  const adesso = useOraCorrente()
  const [rose, setRose] = useState<Giocatore[]>([])
  const [scelte, setScelte] = useState<Scelta[]>([])
  const [valutazioni, setValutazioni] = useState<Map<number, Valutazione>>(new Map())
  const [bilanciaAperta, setBilanciaAperta] = useState<number | null>(null)
  const [proposte, setProposte] = useState<Proposta[]>([])
  const [trattativePubbliche, setTrattativePubbliche] = useState<TrattativaPubblica[]>([])
  const [capienza, setCapienza] = useState<Capienza | null>(null)
  const [caricamento, setCaricamento] = useState(true)
  // Arrivando da una notifica «scambio ufficiale» si scorre al riepilogo, appena la pagina e' pronta.
  // Da una notifica di mercato si arriva sulla proposta: ricevuta, inviata o fra gli scambi conclusi. Se non e'
  // piu' in nessun elenco (rifiutata, ritirata, scaduta) si resta sulle proposte, in cima alla pagina.
  const [propostaEvidenziata, setPropostaEvidenziata] = useState<number | null>(null)
  useEffect(() => {
    if (!propostaDaMostrare || caricamento) return
    const timer = window.setTimeout(() => {
      const el = document.querySelector(`[data-proposta="${propostaDaMostrare.id}"]`)
      if (el) {
        el.scrollIntoView({ behavior: 'smooth', block: 'center' })
        setPropostaEvidenziata(propostaDaMostrare.id)
        window.setTimeout(() => setPropostaEvidenziata(null), 2600)
      } else window.scrollTo({ top: 0, behavior: 'smooth' })
    }, 200)
    return () => window.clearTimeout(timer)
  }, [propostaDaMostrare, caricamento])
  useEffect(() => {
    if (!scorriAConclusi || caricamento || propostaDaMostrare) return
    const timer = window.setTimeout(() => document.getElementById('scambi-stagione')?.scrollIntoView({ behavior: 'smooth', block: 'start' }), 150)
    return () => window.clearTimeout(timer)
  }, [scorriAConclusi, caricamento, propostaDaMostrare])
  const [errore, setErrore] = useState<string | null>(null)

  const [avversaria, setAvversaria] = useState<number | null>(null)
  const [chiesti, setChiesti] = useState<number[]>([])
  const [offerti, setOfferti] = useState<number[]>([])
  const [scelteChieste, setScelteChieste] = useState<number[]>([])
  const [scelteOfferte, setScelteOfferte] = useState<number[]>([])
  const [vivaioChiesti, setVivaioChiesti] = useState<number[]>([])
  const [vivaioOfferti, setVivaioOfferti] = useState<number[]>([])
  const [vivai, setVivai] = useState<Prospetto[]>([])
  const [messaggio, setMessaggio] = useState('')
  const [sceltaRifiutoId, setSceltaRifiutoId] = useState<number | null>(null)
  const [contropropostaOrigine, setContropropostaOrigine] = useState<Proposta | null>(null)
  const [inCorso, setInCorso] = useState(false)
  const [esito, setEsito] = useState<string | null>(null)
  // Gli errori di un'azione (scambio bloccato dalle regole, mercato chiuso,
  // rosa piena) finivano in una riga di testo in cima alla pagina. Chi compone
  // una proposta sta pero' in fondo, e vedeva solo un pulsante che non faceva
  // niente. Vanno in un popup, che si mette davanti.
  const [erroreAzione, setErroreAzione] = useState<string | null>(null)
  const [schedaApertaId, setSchedaApertaId] = useState<number | null>(null)
  const [attributiScheda, setAttributiScheda] = useState<Attributi>({})

  // Gli attributi si caricano per il giocatore che si apre davvero: chiederli
  // per tutta la lega in lista costava centinaia di kilobyte a ogni apertura.
  // `id` e' l'istanza (player_instances.id), non il catalogo: prima finiva in
  // attributiDi, che cerca per players.id, e la scheda mostrava le abilita'
  // di un altro giocatore. Ora arrivano quelle vere, crescita compresa.
  async function apriScheda(id: number) {
    let attributi = await attributiIstanza(id)
    // Se le abilita' correnti non arrivano (succede con i giocatori di altre squadre) si ripiega su quelle della lega.
    if (Object.keys(attributi).length === 0) {
      const g = rose.find((r) => r.id === id)
      if (g) attributi = await attributiInLega(league.id, g.player_id)
    }
    setAttributiScheda(attributi)
    setSchedaApertaId(id)
  }
  const [tabComposer, setTabComposer] = useState<'giocatori' | 'scelte' | 'vivaio'>('giocatori')
  const compositoreRef = useRef<HTMLElement>(null)

  const carica = useCallback(async (silenzioso = false) => {
    if (!silenzioso) setCaricamento(true)
    setErrore(null)
    const [istanzeRes, scelteRes, proposteRes, trattativeRes, capienzaRes, valutazioniRes] = await Promise.all([
      supabase.from('player_instances')
        .select('id, team_id, player_id, overall_corrente, eta_corrente, ingaggio, condizione, infortunato_fino_a, ritiro_annunciato, sul_mercato, posizioni_override')
        .eq('league_id', league.id).not('team_id', 'is', null),
      supabase.from('scelte_draft')
        .select('id, team_origine_id, team_proprietario_id, stagione, finestra, posizione, stato')
        .eq('league_id', league.id).in('stato', ['futura', 'determinata'])
        .order('stagione'),
      supabase.from('trade_proposals').select('*').eq('league_id', league.id).order('creata_il', { ascending: false }),
      supabase.rpc('trattative_pubbliche', { p_league_id: league.id }),
      supabase.rpc('capienza_squadra', { p_league_id: league.id }),
      supabase.rpc('valutazione_scambi', { p_league_id: league.id }),
    ])
    const primoErrore = istanzeRes.error ?? scelteRes.error ?? proposteRes.error
    if (primoErrore) { setErrore(primoErrore.message); setCaricamento(false); return }

    const istanze = istanzeRes.data ?? []
    const daCercare = [...new Set(istanze.map((i) => i.player_id))]
    const { data: anagrafica, error: erroreAnagrafica } = daCercare.length
      ? await supabase.from('players').select('id, nome, nome_completo, club, nazionalita, posizioni, piede, altezza, overall, eta, foto_url').in('id', daCercare)
      : { data: [], error: null }
    if (erroreAnagrafica) { setErrore(erroreAnagrafica.message); setCaricamento(false); return }

    const fotoFirmate = await Promise.all((anagrafica ?? [])
      .filter((p) => p.foto_url)
      .map(async (p) => {
        if (p.foto_url?.startsWith('http')) return [p.id, p.foto_url] as const
        return [p.id, urlFotoGiocatore(p.foto_url)] as const
      }))
    const fotoPerId = new Map(fotoFirmate.filter((e): e is readonly [number, string] => Boolean(e[1])))
    const perId = new Map((anagrafica ?? []).map((p) => [p.id, p as {
      id: number; nome: string; club: string; nazionalita: string | null; posizioni: string[]
      piede: string | null; altezza: number | null
      overall: number; eta: number; foto_url: string | null
    }]))

    setProposte((proposteRes.data ?? []) as Proposta[])
    setTrattativePubbliche(trattativeRes.error ? [] : (trattativeRes.data ?? []) as TrattativaPubblica[])
    setScelte((scelteRes.data ?? []) as Scelta[])
    setCapienza(capienzaRes.error ? null : capienzaRes.data as Capienza)
    // Il voto e' un di piu': se non arriva, le card restano senza.
    setValutazioni(new Map(((valutazioniRes.error ? [] : valutazioniRes.data ?? []) as Valutazione[]).map((v) => [v.proposta_id, v])))
    setRose(istanze.map((i) => {
      const posizioni = i.posizioni_override ?? perId.get(i.player_id)?.posizioni ?? []
      return {
      id: i.id, player_id: i.player_id, team_id: i.team_id as number,
      overall: i.overall_corrente, eta: i.eta_corrente, ingaggio: i.ingaggio,
      nome: cognome(perId.get(i.player_id)?.nome ?? '—'),
      nomeEsteso: (perId.get(i.player_id) as { nome_completo?: string | null } | undefined)?.nome_completo ?? null,
      ruolo: posizioni[0] ?? '—',
      club: perId.get(i.player_id)?.club,
      nazionalita: perId.get(i.player_id)?.nazionalita,
      posizioni,
      piede: perId.get(i.player_id)?.piede,
      altezza: perId.get(i.player_id)?.altezza,
      foto_firmata: fotoPerId.get(i.player_id),
      condizione: i.condizione,
      infortunatoFinoA: i.infortunato_fino_a,
      ritiroAnnunciato: i.ritiro_annunciato,
      sulMercato: i.sul_mercato,
    }}))
    // Vivai di tutta la lega (leggibili ai membri): nome e ruolo dal catalogo, potenziale con la propria scouting.
    const { data: prospettiDb } = await supabase.from('vivaio_prospetti').select('id, team_id, player_id, giornate_rimanenti, ingaggio').eq('league_id', league.id)
    const idPros = [...new Set((prospettiDb ?? []).map((v) => v.player_id))]
    const [anaPros, fascePros] = idPros.length
      ? await Promise.all([
          supabase.from('players').select('id, nome, overall, eta, posizioni').in('id', idPros),
          supabase.rpc('fascia_potenziale_giocatori', { p_player_ids: idPros, p_team_id: membership.id }),
        ])
      : [{ data: [] }, { data: [] }]
    const anaPerId = new Map(((anaPros.data ?? []) as Array<{ id: number; nome: string; overall: number; eta: number; posizioni: string[] }>).map((x) => [x.id, x]))
    const fasciaPerId = new Map(((fascePros.data ?? []) as Array<{ player_id: number; potenziale_min: number; potenziale_max: number }>).map((x) => [x.player_id, x]))
    setVivai((prospettiDb ?? []).map((v) => {
      const a = anaPerId.get(v.player_id); const f = fasciaPerId.get(v.player_id)
      return { id: v.id, team_id: v.team_id, player_id: v.player_id, nome: a?.nome ?? 'Prospetto', overall: a?.overall ?? 0, eta: a?.eta ?? 0,
        ruolo: a?.posizioni?.[0] ?? '—', posizioni: a?.posizioni ?? [], giornate: v.giornate_rimanenti, ingaggio: v.ingaggio,
        potMin: f?.potenziale_min ?? null, potMax: f?.potenziale_max ?? null }
    }))
    setCaricamento(false)
  }, [league.id, membership.id])

  useEffect(() => { void carica() }, [carica])

  // La pagina si caricava UNA VOLTA SOLA e non si aggiornava piu'. Chi la
  // teneva aperta vedeva la fotografia di quando l'aveva aperta: e' cosi' che
  // un partecipante ha visto tutti i giocatori messi in vendita tranne
  // l'ultimo, segnalandolo come un bug dei permessi che non era.
  //
  // Si ricarica quando si TORNA sulla pagina, non a intervalli. Un polling
  // costerebbe banda a ogni utente per tutto il tempo in cui la tiene aperta,
  // e il piano gratuito Supabase la banda ce l'ha gia' contata; tornare sulla
  // scheda e' invece il momento esatto in cui uno si aspetta dati freschi.
  useEffect(() => {
    const suRitorno = () => { if (document.visibilityState === 'visible') void carica(true) }
    document.addEventListener('visibilitychange', suRitorno)
    window.addEventListener('focus', suRitorno)
    return () => {
      document.removeEventListener('visibilitychange', suRitorno)
      window.removeEventListener('focus', suRitorno)
    }
  }, [carica])


  const nomeSquadra = useCallback((id: number) => dati.teamById.get(id)?.nome ?? 'Squadra', [dati.teamById])
  const stemma = useCallback((id: number) => <Crest
    value={dati.teamById.get(id)?.stemma_url ?? null}
    stelle={dati.teamById.get(id)?.titoli_title}
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
  const chiusoPerFase = faseMercato?.scambiChiuso ?? false   // playoff e fine stagione; riapre con l'off-season
  const aperto = !chiusoPerFase && (cicloDinamico ? mercatoDinamicoAperto : mercatoAperto())
  const etichettaMercato = chiusoPerFase ? ETICHETTA_SCAMBI_CHIUSO : cicloDinamico
    ? aperto
      ? `Mercato aperto · chiude tra ${formatCountdown(Math.max(0, (chiusuraMercatoIl ?? adesso) - adesso))}`
      : adesso < (aperturaMercatoIl ?? 0)
        ? `Mercato chiuso · apre tra ${formatCountdown(Math.max(0, (aperturaMercatoIl ?? adesso) - adesso))}`
        : 'Mercato chiuso · in attesa della prossima partita'
    : aperto ? 'Mercato aperto · chiude alle 21:00' : 'Mercato chiuso · apre alle 23:30'

  const miaRosa = useMemo(() => rose.filter((g) => g.team_id === membership.id).sort((a, b) => b.overall - a.overall), [rose, membership.id])
  const rosaAvversaria = useMemo(() => rose.filter((g) => g.team_id === avversaria).sort((a, b) => b.overall - a.overall), [rose, avversaria])
  const mieScelte = useMemo(() => scelte.filter((s) => s.team_proprietario_id === membership.id)
    .sort(perCalendario), [scelte, membership.id])
  const mioVivaio = useMemo(() => vivai.filter((v) => v.team_id === membership.id).sort((a, b) => b.overall - a.overall), [vivai, membership.id])
  const vivaioAvversaria = useMemo(() => vivai.filter((v) => v.team_id === avversaria).sort((a, b) => b.overall - a.overall), [vivai, avversaria])
  const prospetto = useCallback((id: number) => vivai.find((v) => v.id === id), [vivai])
  const scelteAvversaria = useMemo(() => scelte.filter((s) => s.team_proprietario_id === avversaria)
    .sort(perCalendario), [scelte, avversaria])

  const ricevute = proposte.filter((p) => p.a_team_id === membership.id && p.stato === 'in_attesa')
  const inviate = proposte.filter((p) => p.da_team_id === membership.id && p.stato === 'in_attesa')
  const concluse = proposte.filter((p) => p.stato === 'accettata')

  // Data breve di uno scambio, ora di Roma. Serve da quando l'elenco copre
  // l'intera stagione invece del solo giorno corrente: con piu' giorni insieme,
  // "quando" diventa un'informazione necessaria per leggere la riga.
  function dataBreve(v: string) {
    return new Intl.DateTimeFormat('it-IT', { timeZone: 'Europe/Rome', day: 'numeric', month: 'short' }).format(new Date(v))
  }

  // Tutti gli scambi conclusi DELLA STAGIONE, dal piu' recente. Prima erano
  // solo quelli del giorno: un affare di ieri spariva, e la sezione
  // "Trasparenza" perdeva il suo scopo proprio quando serviva, cioe' quando
  // qualcuno voleva capire com'era cambiata una rosa.
  //
  // Il confine e' data_inizio della stagione corrente. Se manca — stagione non
  // ancora caricata — si mostrano tutti gli accettati invece di nasconderli:
  // meglio qualche riga di troppo che una sezione vuota senza motivo.
  const inizioStagione = dati.season?.data_inizio ? new Date(dati.season.data_inizio).getTime() : null
  const concluseStagione = useMemo(() => concluse
    .filter((p) => p.risolta_il && (inizioStagione == null || new Date(p.risolta_il).getTime() >= inizioStagione))
    .sort((a, b) => new Date(b.risolta_il!).getTime() - new Date(a.risolta_il!).getTime()),
    [concluse, inizioStagione])

  async function chiama(azione: () => PromiseLike<{ error: { message: string } | null }>, successo: string, durataMinima = 0) {
    const partenza = performance.now()
    setInCorso(true)
    setEsito(null)
    setErroreAzione(null)
    try {
      const { error } = await azione()
      if (error) setErroreAzione(error.message)
      else setEsito(successo)
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
        p_vivaio_offerti: vivaioOfferti,
        p_vivaio_richiesti: vivaioChiesti,
      }),
      contropropostaOrigine ? 'Controfferta inviata.' : 'Proposta inviata.',
    )
    if (riuscita) {
      setChiesti([]); setOfferti([]); setScelteChieste([]); setScelteOfferte([]); setVivaioChiesti([]); setVivaioOfferti([]); setMessaggio('')
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
    setVivaioOfferti([...(p.vivaio_richiesti ?? [])])
    setVivaioChiesti([...(p.vivaio_offerti ?? [])])
    setMessaggio('Controfferta')
    setSceltaRifiutoId(null)
    window.requestAnimationFrame(() => compositoreRef.current?.scrollIntoView({ behavior: 'smooth', block: 'start' }))
  }
  function annullaControfferta() {
    setContropropostaOrigine(null); setAvversaria(null)
    setChiesti([]); setOfferti([]); setScelteChieste([]); setScelteOfferte([]); setVivaioChiesti([]); setVivaioOfferti([]); setMessaggio('')
  }

  const nPacchettoOfferto = offerti.length + scelteOfferte.length + vivaioOfferti.length
  const nPacchettoChiesto = chiesti.length + scelteChieste.length + vivaioChiesti.length

  const listaGiocatori = (elenco: Giocatore[], selezionati: number[], imposta: (v: number[]) => void, vuoto: string) =>
    elenco.length === 0
      ? <p className="scambi-vuoto">{vuoto}</p>
      : <ul className="scambi-asset-grid">
          {elenco.map((g) => <li key={g.id}>
            <button type="button" className={`scambi-asset-card scambi-asset-card--player ${selezionati.includes(g.id) ? 'is-scelto' : ''}`}
              onClick={() => alterna(selezionati, g.id, imposta)} aria-pressed={selezionati.includes(g.id)}>
              <span className={`scambi-asset-card__ovr role-pill--${macroRuolo(g.posizioni ?? [g.ruolo]).toLowerCase()}`}>{g.overall}</span>
              <span className="scambi-asset-card__info"><strong>{g.nome}{g.sulMercato && <SegnaMercato />}</strong><small>{ruoloIt(g.ruolo)} · {g.eta} anni · {milioni(g.ingaggio)}</small></span>
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

  const listaVivaio = (elenco: Prospetto[], selezionati: number[], imposta: (v: number[]) => void, vuoto: string) =>
    elenco.length === 0
      ? <p className="scambi-vuoto">{vuoto}</p>
      : <ul className="scambi-asset-grid">
          {elenco.map((v) => <li key={v.id}>
            <button type="button" className={`scambi-asset-card scambi-asset-card--player ${selezionati.includes(v.id) ? 'is-scelto' : ''}`}
              onClick={() => alterna(selezionati, v.id, imposta)} aria-pressed={selezionati.includes(v.id)}>
              <span className={`scambi-asset-card__ovr role-pill--${macroRuolo(v.posizioni.length ? v.posizioni : [v.ruolo]).toLowerCase()}`}>{v.overall}</span>
              <span className="scambi-asset-card__info"><strong>{cognome(v.nome)}</strong>
                <small>{ruoloIt(v.ruolo)} · {v.eta} anni{v.potMin != null ? ` · pot. ${v.potMin === v.potMax ? v.potMin : `${v.potMin}-${v.potMax}`}` : ''} · {v.giornate} giornate · {milioni(v.ingaggio)}</small></span>
              {selezionati.includes(v.id) && <span className="scambi-asset-card__check" aria-hidden="true">✓</span>}
            </button>
          </li>)}
        </ul>

  const chipVivaio = (id: number) => <span key={`v${id}`} className="scambi-chip scambi-chip--player">🌱 {prospetto(id) ? cognome(prospetto(id)!.nome) : 'Prospetto'}</span>
  const tuttiChip = (g: number[], sc: number[], v: number[] | undefined) => <>{g.map((id) => pacchettoChip(id, 'g'))}{sc.map((id) => pacchettoChip(id, 's'))}{(v ?? []).map(chipVivaio)}</>

  const pacchettoChip = (id: number, tipo: 'g' | 's') => tipo === 'g'
    ? <button key={`g${id}`} type="button" className="scambi-chip scambi-chip--player" onClick={() => void apriScheda(id)}>
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
          {p.giocatori_offerti.length + p.scelte_offerte.length + (p.vivaio_offerti?.length ?? 0) === 0
            ? <span className="scambi-nessuno">niente</span>
            : tuttiChip(p.giocatori_offerti, p.scelte_offerte, p.vivaio_offerti)}
        </div>
      </div>
      <i className="scambi-riepilogo__freccia" aria-hidden="true">⇄</i>
      <div className="scambi-riepilogo__lato">
        <small>{p.da_team_id === membership.id ? 'Chiedi' : 'Ti chiede'}</small>
        <div className="scambi-riepilogo__chips">
          {p.giocatori_richiesti.length + p.scelte_richieste.length + (p.vivaio_richiesti?.length ?? 0) === 0
            ? <span className="scambi-nessuno">niente</span>
            : tuttiChip(p.giocatori_richiesti, p.scelte_richieste, p.vivaio_richiesti)}
        </div>
      </div>
    </div>
    {p.messaggio && <p className="scambi-messaggio">«{p.messaggio}»</p>}
  </>

  // VETRINA — chi le altre squadre hanno messo in lista.
  //
  // Il flag sul_mercato esiste dal 5 agosto 2026 insieme alla sua RPC e al suo
  // indice, ma questa sezione non era mai stata costruita: ventuno giocatori
  // erano in lista e nessuno poteva vederli, mentre la pagina di aiuto
  // descriveva una vetrina che nel gioco non esisteva.
  //
  // Non serve nessuna query nuova: la pagina caricava gia' tutte le istanze
  // della lega con anagrafica e foto, mancava solo di chiedere il campo.
  //
  // Ci sono anche i propri giocatori messi in lista (8 ottobre 2026, richiesta del
  // committente): si vede cosa e' esposto davvero, con la dicitura «Tuo».
  const inVendita = useMemo(
    () => rose.filter((g) => g.sulMercato)
      .sort((a, b) => b.overall - a.overall),
    [rose])
  // La vetrina e' divisa per ruolo (portieri, difensori, centrocampisti, attaccanti), una scheda per ruolo.
  const [ruoloVendita, setRuoloVendita] = useState<MacroRuolo | null>(null)
  const venditaPerRuolo = useMemo(() => {
    const mappa = new Map<MacroRuolo, Giocatore[]>()
    for (const g of inVendita) {
      const ruolo = macroRuolo(g.posizioni ?? [g.ruolo]) as MacroRuolo
      mappa.set(ruolo, [...(mappa.get(ruolo) ?? []), g])
    }
    return mappa
  }, [inVendita])
  // Se la scheda scelta si svuota (o non e' ancora scelta) si va sulla prima che ha qualcuno.
  const ruoloVenditaVisto: MacroRuolo | null = ruoloVendita && venditaPerRuolo.has(ruoloVendita)
    ? ruoloVendita
    : ORDINE_MACRO_RUOLO.find((r) => venditaPerRuolo.has(r)) ?? null

  const schedaAperta = schedaApertaId != null ? giocatore(schedaApertaId) : undefined

  // «Proponi scambio» dalla scheda di un giocatore altrui: la squadra e il giocatore sono gia' scelti nel compositore.
  function preparaScambio(g: Giocatore) {
    setContropropostaOrigine(null)
    setAvversaria(g.team_id)
    setChiesti([g.id]); setOfferti([]); setScelteChieste([]); setScelteOfferte([]); setVivaioChiesti([]); setVivaioOfferti([])
    setTabComposer('giocatori')
    setSchedaApertaId(null)
    setEsito(null)
    window.setTimeout(() => compositoreRef.current?.scrollIntoView({ behavior: 'smooth', block: 'start' }), 80)
  }
  useEffect(() => {
    if (!preselezione || caricamento) return
    const g = rose.find((r) => r.id === preselezione.istanzaId)
    if (g) preparaScambio(g)
    onPreselezioneUsata?.()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [preselezione, caricamento, rose])

  // RICERCA nella lega: ruolo, eta' e overall, con minimi e massimi. Solo i giocatori delle ALTRE squadre
  // (i propri sono gia' nel compositore).
  const [ruoloRicerca, setRuoloRicerca] = useState<string | null>(null)
  const [etaDa, setEtaDa] = useState(''); const [etaA, setEtaA] = useState('')
  const [ovrDa, setOvrDa] = useState(''); const [ovrA, setOvrA] = useState('')
  const [ancheSecondari, setAncheSecondari] = useState(false)
  const [soloVendita, setSoloVendita] = useState(false)
  const filtriAttivi = ruoloRicerca !== null || etaDa !== '' || etaA !== '' || ovrDa !== '' || ovrA !== '' || soloVendita
  const azzeraRicerca = () => { setRuoloRicerca(null); setEtaDa(''); setEtaA(''); setOvrDa(''); setOvrA(''); setAncheSecondari(false); setSoloVendita(false) }
  const risultatiRicerca = useMemo(() => {
    const eMin = numeroOppure(etaDa), eMax = numeroOppure(etaA), oMin = numeroOppure(ovrDa), oMax = numeroOppure(ovrA)
    return rose.filter((g) => g.team_id !== membership.id)
      .filter((g) => !ruoloRicerca || (ancheSecondari ? (g.posizioni ?? [g.ruolo]).includes(ruoloRicerca) : (g.posizioni?.[0] ?? g.ruolo) === ruoloRicerca))
      .filter((g) => (eMin === null || g.eta >= eMin) && (eMax === null || g.eta <= eMax))
      .filter((g) => (oMin === null || g.overall >= oMin) && (oMax === null || g.overall <= oMax))
      .filter((g) => !soloVendita || g.sulMercato)
      .sort((a, b) => b.overall - a.overall || a.eta - b.eta)
  }, [rose, membership.id, ruoloRicerca, ancheSecondari, etaDa, etaA, ovrDa, ovrA, soloVendita])
  const capienzaPct = capienza ? Math.min(100, Math.max(0, (capienza.monte / Math.max(capienza.tetto, 1)) * 100)) : 0
  const capienzaCritica = capienza ? capienza.capienza < 0 : false

  return <main className="app-shell season-shell scambi-shell">
    <GameNav league={league} active="scambi" onNavigate={onNavigate} />
    <header className="topbar season-topbar">
      <div className="brand-lockup brand-lockup--dark"><img src="/specialone-mark.svg" alt="" /><span>SpecialOne</span></div>
      <span className={`mercato-finestra ${aperto ? 'e-aperto' : ''}`}>{etichettaMercato}</span>
    </header>

    {caricamento && <div className="season-page"><section className="season-state is-caricamento mercato-caricamento"><LoadingLogo compatto /><h2>Preparo il mercato scambi…</h2><p>Recupero rose, scelte e trattative.</p><span className="caricamento-barra" aria-hidden="true" /></section></div>}
    {errore && <div className="season-page"><p className="season-empty">{errore}</p></div>}

    {!caricamento && !errore && <div className={`season-page season-page--narrow scambi-page scambi-broadcast formazione-broadcast formazione-broadcast--${fase}`}>
      <PopupSpiegazione userId={membership.user_id} hintKey="scambi-v3" titolo="Come funzionano gli Scambi">
        <p>Si scambiano giocatori e scelte di draft insieme, come in NBA: <strong>nessun conguaglio in denaro</strong>,
          si tratta alla pari sotto lo stesso tetto salariale per tutti.</p>
        <p>Dopo lo scambio entrambe le rose devono restare fra 21 e 30 giocatori e sotto il tetto ingaggi. Una
          scelta di draft ceduta non può lasciare una squadra senza una propria scelta d'origine per due
          finestre consecutive (regola Stepien) — evita di svendere tutto il futuro in un colpo solo. Un
          giocatore appena scambiato è comunque scambiabile di nuovo subito: il vincolo delle 10 giornate prima
          di poter essere svincolato riguarda solo lo svincolo, non un nuovo scambio.</p>
        <p>Il <strong>minutaggio promesso</strong> viaggia col giocatore, come l'ingaggio: chi prende un titolare fisso si prende anche la promessa di farlo giocare. I richiami e le richieste di cessione invece si azzerano, perché erano rivolti all'allenatore di prima.</p>
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
                {ricevute.map((p) => <motion.article layout initial={{ opacity: 0, y: 8 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0, scale: 0.96 }} className={`scambi-card${propostaEvidenziata === p.id ? ' is-evidenziata' : ''}`} data-proposta={p.id} key={p.id}>
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
            onClick={() => { setAvversaria(s.id); setChiesti([]); setScelteChieste([]); setVivaioChiesti([]) }}
            aria-label={s.nome} aria-pressed={avversaria === s.id} title={s.nome}>
            {stemma(s.id)}
          </button>)}
        </div>}

        {avversaria && <>
          <UnderlineTabs
            tabs={[{ value: 'giocatori', label: 'Giocatori' }, { value: 'scelte', label: 'Scelte di draft' }, { value: 'vivaio', label: 'Vivaio' }] as const}
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
                : tabComposer === 'vivaio'
                ? listaVivaio(vivaioAvversaria, vivaioChiesti, setVivaioChiesti, 'Nessun giocatore nel vivaio.')
                : listaScelte(scelteAvversaria, scelteChieste, setScelteChieste, 'Nessuna scelta scambiabile.')}
            </div>
            <div>
              <h3>Cosa offri</h3>
              {tabComposer === 'giocatori'
                ? listaGiocatori(miaRosa, offerti, setOfferti, 'La tua rosa è vuota.')
                : tabComposer === 'vivaio'
                ? listaVivaio(mioVivaio, vivaioOfferti, setVivaioOfferti, 'Il tuo vivaio è vuoto.')
                : listaScelte(mieScelte, scelteOfferte, setScelteOfferte, 'Nessuna scelta scambiabile.')}
              {tabComposer === 'vivaio' && <p className="scambi-vuoto">I giocatori del vivaio passano nel vivaio di chi li riceve, che deve avere uno slot libero. Mantengono le giornate rimaste e l'ingaggio.</p>}
            </div>
          </div>

          {(nPacchettoOfferto > 0 || nPacchettoChiesto > 0) && <div className="scambi-anteprima">
            <div className="scambi-anteprima__lato">
              <span className="scambi-anteprima__conteggio">{nPacchettoOfferto}</span>
              <small>Offri</small>
              <div className="scambi-anteprima__chips">{nPacchettoOfferto === 0
                ? <span className="scambi-nessuno">niente</span>
                : tuttiChip(offerti, scelteOfferte, vivaioOfferti)}</div>
            </div>
            <i aria-hidden="true">⇄</i>
            <div className="scambi-anteprima__lato">
              <span className="scambi-anteprima__conteggio">{nPacchettoChiesto}</span>
              <small>Chiedi</small>
              <div className="scambi-anteprima__chips">{nPacchettoChiesto === 0
                ? <span className="scambi-nessuno">niente</span>
                : tuttiChip(chiesti, scelteChieste, vivaioChiesti)}</div>
            </div>
          </div>}

          <div className="scambi-messaggio-riga">
            <label>
              <span>Messaggio (facoltativo)</span>
              <input type="text" value={messaggio} maxLength={240} onChange={(e) => setMessaggio(e.target.value)} placeholder="Due righe per convincerlo" />
            </label>
          </div>

          {(nPacchettoOfferto > 0) !== (nPacchettoChiesto > 0) && <p className="scambi-vuoto">{nPacchettoOfferto === 0 ? 'Scegli anche cosa offri: non si chiedono asset senza dare niente in cambio.' : 'Scegli anche cosa chiedi: non si regalano asset.'}</p>}
          <button className="button button--primary scambi-invia" type="button"
            disabled={inCorso || !aperto || nPacchettoOfferto === 0 || nPacchettoChiesto === 0}
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
          : <div className="scambi-proposte-grid">{inviate.map((p) => <article className={`scambi-card${propostaEvidenziata === p.id ? ' is-evidenziata' : ''}`} data-proposta={p.id} key={p.id}>
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

      {/* ---- Ricerca nella lega ---- */}
      <section className="scambi-blocco scambi-cerca">
        <div className="sezione-testa">
          <div><p className="kicker">Cerca</p><h2>Giocatori della lega{filtriAttivi && <span className="scambi-conteggio"> {risultatiRicerca.length}</span>}</h2></div>
          {filtriAttivi && <button className="button button--secondary" type="button" onClick={azzeraRicerca}>Azzera</button>}
        </div>
        <div className="scambi-cerca__ruoli" role="group" aria-label="Ruolo">
          <button type="button" className={ruoloRicerca === null ? 'is-attivo' : ''} aria-pressed={ruoloRicerca === null} onClick={() => setRuoloRicerca(null)}>Tutti</button>
          {RUOLI_RICERCA.map((r) => <button key={r} type="button" className={ruoloRicerca === r ? 'is-attivo' : ''} aria-pressed={ruoloRicerca === r}
            style={{ ['--c' as string]: MACRO_COLORE[macroRuolo([r]) as MacroRuolo] }} onClick={() => setRuoloRicerca(ruoloRicerca === r ? null : r)}>{ruoloIt(r)}</button>)}
        </div>
        <div className="scambi-cerca__campi">
          <fieldset>
            <legend>Età</legend>
            <input inputMode="numeric" placeholder="da" aria-label="Età minima" value={etaDa} onChange={(e) => setEtaDa(soloCifre(e.target.value))} />
            <span aria-hidden="true">–</span>
            <input inputMode="numeric" placeholder="a" aria-label="Età massima" value={etaA} onChange={(e) => setEtaA(soloCifre(e.target.value))} />
          </fieldset>
          <fieldset>
            <legend>Overall</legend>
            <input inputMode="numeric" placeholder="da" aria-label="Overall minimo" value={ovrDa} onChange={(e) => setOvrDa(soloCifre(e.target.value))} />
            <span aria-hidden="true">–</span>
            <input inputMode="numeric" placeholder="a" aria-label="Overall massimo" value={ovrA} onChange={(e) => setOvrA(soloCifre(e.target.value))} />
          </fieldset>
        </div>
        <div className="scambi-cerca__opzioni">
          <label><input type="checkbox" checked={ancheSecondari} onChange={(e) => setAncheSecondari(e.target.checked)} />Anche ruolo secondario</label>
          <label><input type="checkbox" checked={soloVendita} onChange={(e) => setSoloVendita(e.target.checked)} />Solo sul mercato</label>
        </div>
        {!filtriAttivi
          ? <p className="scambi-vetrina-nota">Scegli un ruolo o imposta età e overall (minimi, massimi o entrambi) per cercare nelle rose delle altre squadre.</p>
          : risultatiRicerca.length === 0
            ? <p className="season-empty">Nessun giocatore con questi filtri.</p>
            : <>
                <ul className="scambi-asset-grid scambi-cerca__risultati">
                  {risultatiRicerca.slice(0, LIMITE_RISULTATI).map((g) => <li key={g.id}>
                    <button type="button" className="scambi-asset-card scambi-asset-card--player scambi-asset-card--vetrina" onClick={() => void apriScheda(g.id)}>
                      <span className={`scambi-asset-card__ovr role-pill--${macroRuolo(g.posizioni ?? [g.ruolo]).toLowerCase()}`}>{g.overall}</span>
                      <span className="scambi-asset-card__info">
                        <strong>{g.nome}{g.sulMercato && <SegnaMercato />}</strong>
                        <small>{ruoloIt(g.ruolo)} · {g.eta} anni · {milioni(g.ingaggio)}</small>
                        <small className="scambi-asset-card__squadra">{nomeSquadra(g.team_id)}</small>
                      </span>
                      <span className="scambi-asset-card__stemma" title={nomeSquadra(g.team_id)}>
                        <Crest value={dati.teamById.get(g.team_id)?.stemma_url ?? null} imageUrl={dati.crestUrlByTeamId.get(g.team_id)} stelle={dati.teamById.get(g.team_id)?.titoli_title} />
                      </span>
                    </button>
                  </li>)}
                </ul>
                {risultatiRicerca.length > LIMITE_RISULTATI && <p className="scambi-vetrina-nota">Mostro i primi {LIMITE_RISULTATI} su {risultatiRicerca.length}: restringi i filtri per vedere gli altri.</p>}
              </>}
      </section>

      {/* ---- Vetrina della lega ---- */}
      <section className="scambi-blocco">
        <div className="sezione-testa"><div>
          <p className="kicker">Vetrina della lega</p>
          <h2>In vendita{inVendita.length > 0 && <span className="scambi-conteggio"> {inVendita.length}</span>}</h2>
        </div></div>
        {inVendita.length === 0
          ? <p className="season-empty">Nessuna squadra ha messo giocatori in lista. Puoi metterci i tuoi dalla loro scheda, nella pagina Club.</p>
          : <>
              <p className="scambi-vetrina-nota">
                Segnalano «questo lo cederei». Non e' un canale a parte: se ti interessa, componi una normale proposta qui sopra.
              </p>
              <UnderlineTabs
                tabs={ORDINE_MACRO_RUOLO.map((ruolo) => ({ value: ruolo, label: MACRO_LABEL[ruolo], badge: venditaPerRuolo.get(ruolo)?.length ?? 0, disabled: !venditaPerRuolo.has(ruolo), activeColor: MACRO_COLORE[ruolo] }))}
                value={ruoloVenditaVisto ?? ORDINE_MACRO_RUOLO[0]}
                onChange={setRuoloVendita}
                layoutId="scambi-vetrina-ruolo-indicator"
                className="mb-3"
              />
              <ul className="scambi-asset-grid">
                {(ruoloVenditaVisto ? venditaPerRuolo.get(ruoloVenditaVisto) ?? [] : []).map((g) => <li key={g.id}>
                  <button type="button" className="scambi-asset-card scambi-asset-card--player scambi-asset-card--vetrina"
                    onClick={() => void apriScheda(g.id)}>
                    <span className={`scambi-asset-card__ovr role-pill--${macroRuolo(g.posizioni ?? [g.ruolo]).toLowerCase()}`}>{g.overall}</span>
                    <span className="scambi-asset-card__info">
                      <strong>{g.nome}{g.team_id === membership.id && <em className="scambi-asset-card__tuo">Tuo</em>}</strong>
                      <small>{ruoloIt(g.ruolo)} · {g.eta} anni · {milioni(g.ingaggio)}</small>
                      <small className="scambi-asset-card__squadra">{nomeSquadra(g.team_id)}</small>
                    </span>
                    <span className="scambi-asset-card__stemma" title={nomeSquadra(g.team_id)}>
                      <Crest value={dati.teamById.get(g.team_id)?.stemma_url ?? null} imageUrl={dati.crestUrlByTeamId.get(g.team_id)} stelle={dati.teamById.get(g.team_id)?.titoli_title} />
                    </span>
                  </button>
                </li>)}
              </ul>
            </>}
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
      <section className="scambi-blocco" id="scambi-stagione">
        <div className="sezione-testa"><div><p className="kicker">Trasparenza</p>
          <h2>Scambi della stagione{concluseStagione.length > 0 && <span className="scambi-conteggio"> {concluseStagione.length}</span>}</h2></div></div>
        {concluseStagione.length === 0
          ? <p className="season-empty">Nessuno scambio concluso in questa stagione.</p>
          : <ul className="scambi-trasparenza">
              {concluseStagione.map((p) => <li className={`scambi-operazione${propostaEvidenziata === p.id ? ' is-evidenziata' : ''}`} data-proposta={p.id} key={p.id}>
                <div className="scambi-operazione__lato">
                  {stemma(p.da_team_id)}
                  <div className="scambi-operazione__chips">{tuttiChip(p.giocatori_offerti, p.scelte_offerte, p.vivaio_offerti)}</div>
                </div>
                <i aria-hidden="true">⇄</i>
                <div className="scambi-operazione__lato scambi-operazione__lato--destra">
                  <div className="scambi-operazione__chips">{tuttiChip(p.giocatori_richiesti, p.scelte_richieste, p.vivaio_richiesti)}</div>
                  {stemma(p.a_team_id)}
                </div>
                <em>{ETICHETTE_STATO[p.stato]} · {p.risolta_il ? dataBreve(p.risolta_il) : ''}</em>
                {/* Voti degli scambi nascosti (19/10/2026, richiesta del committente). */}
                {MOSTRA_VOTI && valutazioni.get(p.id) && <VotoScambio voto={valutazioni.get(p.id)!.voto} onClick={() => setBilanciaAperta(p.id)} />}
              </li>)}
            </ul>}
      </section>

      {bilanciaAperta !== null && valutazioni.get(bilanciaAperta) && (() => {
        const v = valutazioni.get(bilanciaAperta)!
        const prop = proposte.find((x) => x.id === bilanciaAperta)
        if (!prop) return null
        return <BilanciaScambio
          valutazione={v}
          // chi ha proposto riceve cio' che cede l'altra squadra (lato 'a'), e viceversa
          squadraDa={{ nome: nomeSquadra(prop.da_team_id), stemma: stemma(prop.da_team_id) }}
          squadraA={{ nome: nomeSquadra(prop.a_team_id), stemma: stemma(prop.a_team_id) }}
          onClose={() => setBilanciaAperta(null)}
        />
      })()}

      {erroreAzione && <div className="popup-spiegazione-sfondo" role="alertdialog" aria-modal="true" aria-label="Operazione non riuscita">
        <div className="popup-spiegazione">
          <h2>Non si può fare</h2>
          <div className="popup-spiegazione__corpo"><p>{erroreAzione}</p></div>
          <button className="button button--primary" type="button" onClick={() => setErroreAzione(null)}>Ho capito</button>
        </div>
      </div>}

      {schedaAperta && <SchedaGiocatore
        giocatore={{
          nome: schedaAperta.nome, nomeEsteso: schedaAperta.nomeEsteso, club: schedaAperta.club, nazionalita: schedaAperta.nazionalita,
          posizioni: schedaAperta.posizioni ?? [schedaAperta.ruolo], overall: schedaAperta.overall, eta: schedaAperta.eta,
          piede: schedaAperta.piede, altezza: schedaAperta.altezza, ingaggio: schedaAperta.ingaggio,
          condizione: schedaAperta.condizione, infortunatoFinoA: schedaAperta.infortunatoFinoA,
          ritiroAnnunciato: schedaAperta.ritiroAnnunciato, attributi: attributiScheda,
        }}
        fotoUrl={schedaAperta.foto_firmata}
        fase={fase}
        tatticheAttive={Boolean(league.tattiche_attive)}
        proponiScambio={schedaAperta.team_id !== membership.id ? { onClick: () => preparaScambio(schedaAperta) } : undefined}
        onClose={() => setSchedaApertaId(null)}
      />}
    </div>}
  </main>
}

// ---- Voto di equilibrio dello scambio (public.valutazione_scambi) ----

function fasciaVoto(voto: number) {
  return voto >= 8.5 ? 'equo' : voto >= 6 ? 'medio' : 'squilibrato'
}

function VotoScambio({ voto, onClick }: { voto: number; onClick: () => void }) {
  return <button type="button" className={`scambio-voto scambio-voto--${fasciaVoto(voto)}`} onClick={onClick}
    aria-label={`Equilibrio dello scambio: ${voto.toFixed(1)} su 10. Vedi il dettaglio`}>
    <b>{voto.toFixed(1)}</b><small>/10</small>
  </button>
}

type SquadraBilancia = { nome: string; stemma: ReactNode }

function BilanciaScambio({ valutazione: v, squadraDa, squadraA, onClose }: {
  valutazione: Valutazione; squadraDa: SquadraBilancia; squadraA: SquadraBilancia; onClose: () => void
}) {
  // Valore RICEVUTO da ciascuna squadra.
  const riceveDa = v.valore_a
  const riceveA = v.valore_da
  const totale = riceveDa + riceveA || 1
  const quotaDa = (riceveDa / totale) * 100
  // Inclinazione della bilancia: fino a 14 gradi, verso chi riceve di piu'.
  const inclinazione = Math.max(-14, Math.min(14, (quotaDa - 50) * 0.6))
  const vincitore = v.voto >= 9.5 ? null : riceveDa > riceveA ? squadraDa.nome : squadraA.nome
  const elenco = (lato: 'da' | 'a') => v.dettaglio.filter((p) => p.lato === lato)
  return <div className="popup-spiegazione-sfondo" role="dialog" aria-modal="true" aria-label="Equilibrio dello scambio" onClick={onClose}>
    <div className="popup-spiegazione bilancia" onClick={(e) => e.stopPropagation()}>
      <header className="bilancia__testa">
        <span className={`scambio-voto scambio-voto--${fasciaVoto(v.voto)} scambio-voto--grande`}><b>{v.voto.toFixed(1)}</b><small>/10</small></span>
        <div>
          <h2>{v.voto >= 9.5 ? 'Scambio equilibrato' : `Pende verso ${vincitore}`}</h2>
          <p>{v.voto >= 8.5 ? 'Valori molto vicini.' : v.voto >= 6 ? 'Una squadra ci guadagna, ma senza esagerare.' : 'Uno dei due lati vale molto di più.'}</p>
        </div>
      </header>

      <BilanciaGrafica inclinazione={inclinazione} sinistra={squadraDa.stemma} destra={squadraA.stemma} />

      <div className="bilancia__barra" aria-hidden="true">
        <span style={{ width: `${quotaDa}%` }} />
      </div>
      <div className="bilancia__quote">
        <span><b>{Math.round(quotaDa)}%</b> {squadraDa.nome}</span>
        <span>{squadraA.nome} <b>{Math.round(100 - quotaDa)}%</b></span>
      </div>

      <div className="bilancia__lati">
        {([[squadraDa, 'a', riceveDa], [squadraA, 'da', riceveA]] as const).map(([sq, lato, tot]) =>
          <section key={lato}>
            <h3>{sq.stemma}<span>{sq.nome} riceve</span></h3>
            <ul>
              {elenco(lato).map((p, i) => <li key={i}>
                <span>{p.etichetta}{p.tipo === 'g' && p.overall != null && <small>{p.overall} · {p.eta} anni</small>}{p.tipo === 's' && <small>scelta al draft</small>}</span>
                <b>{p.valore.toFixed(1)}</b>
              </li>)}
            </ul>
            <p className="bilancia__totale">Totale <b>{tot.toFixed(1)}</b></p>
          </section>)}
      </div>

      <p className="bilancia__nota">Calcolato sui valori di oggi: overall, crescita attesa in base all'età e scelte al draft in base alla posizione. Non tiene conto di ingaggi e bisogni di ruolo.</p>
      <button className="button button--primary" type="button" onClick={onClose}>Chiudi</button>
    </div>
  </div>
}

// Bilancia a due piatti: la trave ruota attorno al perno, i piatti restano appesi in verticale.
// Inclinazione positiva = scende il piatto di SINISTRA (chi riceve di piu' sta in basso).
function BilanciaGrafica({ inclinazione, sinistra, destra }: { inclinazione: number; sinistra: ReactNode; destra: ReactNode }) {
  const [angolo, setAngolo] = useState(0)
  useEffect(() => {
    const ridotto = window.matchMedia?.('(prefers-reduced-motion: reduce)').matches
    if (ridotto) { setAngolo(inclinazione); return }
    let raf = 0
    const inizio = performance.now()
    const durata = 1100
    const passo = (t: number) => {
      const x = Math.min(1, (t - inizio) / durata)
      // molla smorzata: oscilla un poco e si ferma
      const e = 1 - Math.exp(-5 * x) * Math.cos(9 * x)
      setAngolo(inclinazione * e)
      if (x < 1) raf = requestAnimationFrame(passo)
    }
    raf = requestAnimationFrame(passo)
    return () => cancelAnimationFrame(raf)
  }, [inclinazione])

  const W = 320, H = 190, cx = 160, cy = 46, L = 112, filo = 52, piatto = 30
  const r = (angolo * Math.PI) / 180
  const sx = cx - L * Math.cos(r), sy = cy + L * Math.sin(r)
  const dx = cx + L * Math.cos(r), dy = cy - L * Math.sin(r)
  const pct = (x: number, tot: number) => `${(x / tot) * 100}%`
  const piattoSvg = (x: number, y: number) => <g>
    <line x1={x} y1={y} x2={x - piatto} y2={y + filo} className="bil-filo" />
    <line x1={x} y1={y} x2={x + piatto} y2={y + filo} className="bil-filo" />
    <path d={`M ${x - piatto - 4} ${y + filo} Q ${x} ${y + filo + 22} ${x + piatto + 4} ${y + filo} Z`} fill="url(#bil-oro)" className="bil-piatto" />
    <ellipse cx={x} cy={y + filo} rx={piatto + 4} ry={4} fill="#fff3c4" opacity=".55" />
    <circle cx={x} cy={y} r={4.5} fill="url(#bil-oro)" />
  </g>
  return <div className="bilancia-grafica" aria-hidden="true">
    <svg viewBox={`0 0 ${W} ${H}`} preserveAspectRatio="xMidYMid meet">
      <defs>
        <linearGradient id="bil-oro" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#ffe9a3" /><stop offset=".45" stopColor="#d8b34f" /><stop offset="1" stopColor="#8a6a1e" />
        </linearGradient>
        <linearGradient id="bil-colonna" x1="0" y1="0" x2="1" y2="0">
          <stop offset="0" stopColor="#6e5a2a" /><stop offset=".5" stopColor="#f2d27a" /><stop offset="1" stopColor="#6e5a2a" />
        </linearGradient>
        <radialGradient id="bil-alone" cx=".5" cy=".5" r=".5">
          <stop offset="0" stopColor="#c59be8" stopOpacity=".35" /><stop offset="1" stopColor="#c59be8" stopOpacity="0" />
        </radialGradient>
      </defs>
      <ellipse cx={cx} cy={cy + 10} rx="120" ry="70" fill="url(#bil-alone)" />
      {/* colonna e base */}
      <rect x={cx - 4} y={cy} width="8" height={H - cy - 26} rx="3" fill="url(#bil-colonna)" />
      <path d={`M ${cx - 46} ${H - 8} L ${cx + 46} ${H - 8} L ${cx + 30} ${H - 26} L ${cx - 30} ${H - 26} Z`} fill="url(#bil-colonna)" />
      <rect x={cx - 54} y={H - 9} width="108" height="6" rx="3" fill="#8a6a1e" />
      {/* trave */}
      <line x1={sx} y1={sy} x2={dx} y2={dy} stroke="url(#bil-oro)" strokeWidth="6" strokeLinecap="round" />
      {piattoSvg(sx, sy)}
      {piattoSvg(dx, dy)}
      {/* perno con la punta che indica il verso */}
      <circle cx={cx} cy={cy} r="9" fill="url(#bil-oro)" stroke="#5c4714" strokeWidth="1.5" />
      <circle cx={cx} cy={cy} r="3" fill="#5c4714" />
      <path d={`M ${cx} ${cy - 30} L ${cx - 5} ${cy - 12} L ${cx + 5} ${cy - 12} Z`} fill="url(#bil-oro)" transform={`rotate(${-angolo} ${cx} ${cy})`} />
    </svg>
    {/* gli stemmi stanno nei piatti */}
    <span className="bilancia-grafica__stemma" style={{ left: pct(sx, W), top: pct(sy + filo - 20, H) }}>{sinistra}</span>
    <span className="bilancia-grafica__stemma" style={{ left: pct(dx, W), top: pct(dy + filo - 20, H) }}>{destra}</span>
  </div>
}
