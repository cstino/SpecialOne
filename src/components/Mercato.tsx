import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { ROSA_MASSIMA } from '../lib/league'
import { cognome } from '../lib/nomi'
import { MACRO_LABEL, ORDINE_MACRO_RUOLO, macroRuolo, type MacroRuolo } from '../lib/ruoli'
import { supabase } from '../lib/supabase'
import { useSeasonData } from '../lib/useSeasonData'
import type { League, Membership } from '../types'
import { Crest } from './Crest'
import { GameNav, type GameView } from './GameNav'
import { SchedaGiocatore } from './SchedaGiocatore'

type Props = { membership: Membership; onNavigate: (view: GameView) => void }

type StatoProposta = 'in_attesa' | 'accettata' | 'rifiutata' | 'ritirata' | 'scaduta'

type Proposta = {
  id: number
  da_team_id: number
  a_team_id: number
  giocatori_offerti: number[]
  giocatori_richiesti: number[]
  conguaglio: number
  messaggio: string | null
  stato: StatoProposta
  creata_il: string
  scade_il: string
  risolta_il?: string | null
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
  sulMercato?: boolean
  condizione?: number
  infortunatoFinoA?: number
  ritiroAnnunciato?: boolean
}

type Asta = {
  id: number
  giorno: string
  tornata: number
  player_id: number
  ingaggio_teorico: number
  stato: 'aperta' | 'assegnata' | 'deserta'
  origine: 'estrazione' | 'spin_offseason' | 'archivio'
  vincitore_team_id: number | null
  ingaggio_finale: number | null
}

type Anagrafica = {
  nome: string
  club: string
  ruolo: string
  posizioni: string[]
  overall: number
  eta: number
  foto_url: string | null
  foto_firmata?: string
}
type SpinOffseason = {
  id: number
  player_id: number
  stato: 'proposto' | 'ingaggiato' | 'asta'
  ingaggio: number
  nome: string
  club: string
  ruolo: string
  overall: number
  eta: number
  foto_url?: string | null
  foto_firmata?: string
}
type StatoSpinOffseason = { attivo: boolean; rimasti: number; usati: number; spin: SpinOffseason[] }
type AnimazioneSpin = { fase: 'giro' | 'reveal'; nome: string; overall?: number; ruolo?: string; foto?: string }

// Il mercato apre alle 23:30 e chiude alle 21:00 (design §9.1, apertura
// spostata dalle 07:00 il 7 agosto 2026 per aprire subito dopo le partite,
// simulate alle 23:00). Qui serve solo a non far comporre una proposta che
// il database rifiuterebbe: la regola vera sta nella RPC, dove non e'
// aggirabile cambiando l'orologio del telefono.
function minutiDalMezzanotteRoma() {
  const [ore, minuti] = new Intl.DateTimeFormat('it-IT', {
    timeZone: 'Europe/Rome', hour: '2-digit', minute: '2-digit', hour12: false,
  }).format(new Date()).split(':').map(Number)
  return ore * 60 + minuti
}

function mercatoAperto() {
  const ora = minutiDalMezzanotteRoma()
  // La finestra scavalca la mezzanotte (23:30 -> 21:00 del giorno dopo):
  // aperto se siamo oltre le 23:30 oppure prima delle 21:00. Chiuso solo
  // nelle due ore e mezza fra la chiusura e la riapertura.
  return ora >= 23 * 60 + 30 || ora < 21 * 60
}

function milioni(euro: number) {
  return `${(euro / 1_000_000).toFixed(1).replace('.', ',')} M€`
}

function giornoRoma(value: Date | string) {
  return new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Europe/Rome', year: 'numeric', month: '2-digit', day: '2-digit',
  }).format(new Date(value))
}

const ETICHETTE_STATO: Record<StatoProposta, string> = {
  in_attesa: 'In attesa',
  accettata: 'Accettata',
  rifiutata: 'Rifiutata',
  ritirata: 'Ritirata',
  scaduta: 'Scaduta',
}

type GiocatoreMini = { nome: string; foto?: string }

type RigaRumor =
  | { tipo: 'svincolato'; key: string; nome: string; foto?: string; destinazioneId: number }
  | { tipo: 'scambio'; key: string; daTeamId: number; aTeamId: number; offerti: GiocatoreMini[]; richiesti: GiocatoreMini[] }

type TrattativaPubblica = {
  id: number
  da_team_id: number
  a_team_id: number
  giocatori_offerti: number[]
  giocatori_richiesti: number[]
}

const PAGINA_RUMOR = 4

// Numero deterministico in [0,1) da un seme intero: stessa scelta ogni volta
// per lo stesso giocatore/asta, cambia solo se cambia il seme (non e' un
// generatore crittografico, serve solo a non ripescare a caso a ogni render).
function pseudoCasuale(seme: number) {
  const x = Math.sin(seme * 12.9898) * 43758.5453
  return x - Math.floor(x)
}

// Estrazione pesata deterministica: usata per scegliere la squadra "rumor" di
// uno svincolato, mai per calcoli su dati reali della busta chiusa.
function scegliPesato<T>(seme: number, opzioni: { valore: T; peso: number }[]) {
  const totale = opzioni.reduce((somma, o) => somma + o.peso, 0)
  if (totale <= 0 || opzioni.length === 0) return undefined
  let resto = pseudoCasuale(seme) * totale
  for (const opzione of opzioni) {
    resto -= opzione.peso
    if (resto <= 0) return opzione.valore
  }
  return opzioni[opzioni.length - 1].valore
}

export function Mercato({ membership, onNavigate }: Props) {
  const league = membership.league as League
  // Squadre e stemmi arrivano da qui: firmare le URL degli stemmi e' gia'
  // risolto, e rifarlo a mano avrebbe prodotto una seconda verita'.
  const dati = useSeasonData(membership)
  const [rose, setRose] = useState<Giocatore[]>([])
  const [proposte, setProposte] = useState<Proposta[]>([])
  const [trattativePubbliche, setTrattativePubbliche] = useState<TrattativaPubblica[]>([])
  const [aste, setAste] = useState<Asta[]>([])
  const [svincolati, setSvincolati] = useState<Map<number, Anagrafica>>(new Map())
  // Solo le proprie: la RLS non consegna quelle altrui, ed e' il punto.
  const [mieOfferte, setMieOfferte] = useState<Map<number, number>>(new Map())
  const [bozzaOfferta, setBozzaOfferta] = useState<Record<number, string>>({})
  const [spinOffseason, setSpinOffseason] = useState<StatoSpinOffseason | null>(null)
  const [animazioneSpin, setAnimazioneSpin] = useState<AnimazioneSpin | null>(null)
  const [paginaAstaRuolo, setPaginaAstaRuolo] = useState<MacroRuolo>('GK')
  // Offrire impegna il denaro: quello che conta non e' il budget ma cio' che
  // resta dopo aver messo da parte le offerte ancora in gioco.
  const [conti, setConti] = useState<{ disponibile: number; impegnato: number; slot_liberi: number } | null>(null)
  const [caricamento, setCaricamento] = useState(true)
  const [errore, setErrore] = useState<string | null>(null)

  const [avversaria, setAvversaria] = useState<number | null>(null)
  const [chiesti, setChiesti] = useState<number[]>([])
  const [offerti, setOfferti] = useState<number[]>([])
  const [conguaglio, setConguaglio] = useState('0')
  const [messaggio, setMessaggio] = useState('')
  const [vetrinaRuolo, setVetrinaRuolo] = useState<MacroRuolo>('ALL')
  const [vetrinaEta, setVetrinaEta] = useState<[number, number]>([16, 45])
  const [vetrinaOverall, setVetrinaOverall] = useState<[number, number]>([50, 99])
  const [filtroRuolo, setFiltroRuolo] = useState<MacroRuolo>('ALL')
  const [filtroEta, setFiltroEta] = useState<[number, number]>([16, 45])
  const [filtroIngaggio, setFiltroIngaggio] = useState<[number, number]>([0, 30])
  const [filtroOverall, setFiltroOverall] = useState<[number, number]>([50, 99])
  const [inCorso, setInCorso] = useState(false)
  const [esito, setEsito] = useState<string | null>(null)
  const [schedaApertaId, setSchedaApertaId] = useState<number | null>(null)
  const compositoreRef = useRef<HTMLElement>(null)

  // Dalla vetrina si salta dritti alla proposta, gia' compilata: e' il modo
  // piu' veloce per dire "questo lo voglio" senza passare dalla scheda.
  function proponiPerGiocatore(g: Giocatore) {
    setAvversaria(g.team_id)
    setChiesti([g.id])
    compositoreRef.current?.scrollIntoView({ behavior: 'smooth', block: 'start' })
  }
  const [paginaRumor, setPaginaRumor] = useState(0)

  const mostraListaLegacySvincolati = false
  // Nascosto su richiesta dell'utente per provare il mercato senza: resta
  // tutto il codice, basta rimettere a true per riportarlo visibile.
  // L'archivio resta attivo lato server ma, per ora, non è una schermata
  // giocabile: si riattiva senza migrazioni cambiando solo questo flag.
  const mostraArchivioSvincolati = false

  const carica = useCallback(async (silenzioso = false) => {
    if (!silenzioso) setCaricamento(true)
    setErrore(null)
    const [istanzeRes, proposteRes, trattativeRes, asteRes, offerteRes, contiRes, spinRes] = await Promise.all([
      supabase.from('player_instances')
        .select('id, team_id, player_id, overall_corrente, eta_corrente, ingaggio, condizione, infortunato_fino_a, ritiro_annunciato, sul_mercato')
        .eq('league_id', league.id).not('team_id', 'is', null),
      supabase.from('trade_proposals').select('*')
        .eq('league_id', league.id).order('creata_il', { ascending: false }),
      // Per la card "Rumors": chi tratta con chi, su tutta la lega. RPC
      // dedicata che espone solo squadre e giocatori coinvolti, mai
      // conguaglio ne' messaggio (restano privati alle due squadre).
      supabase.rpc('trattative_pubbliche', { p_league_id: league.id }),
      supabase.from('free_agent_auctions')
        .select('id, giorno, tornata, player_id, ingaggio_teorico, stato, origine, vincitore_team_id, ingaggio_finale')
        .eq('league_id', league.id).order('giorno', { ascending: false }).order('id').limit(500),
      supabase.from('free_agent_bids').select('auction_id, ingaggio_offerto'),
      supabase.rpc('budget_disponibile', { p_league_id: league.id }),
      league.fase_carriera === 'offseason'
        ? supabase.rpc('stato_spin_offseason', { p_league_id: league.id })
        : Promise.resolve({ data: null, error: null }),
    ])
    const primoErrore = istanzeRes.error ?? proposteRes.error ?? asteRes.error ?? offerteRes.error ?? spinRes.error
    if (primoErrore) { setErrore(primoErrore.message); setCaricamento(false); return }

    const istanze = istanzeRes.data ?? []
    const asteRighe = (asteRes.data ?? []) as Asta[]
    // Una sola interrogazione per l'anagrafica: i giocatori delle rose e
    // quelli all'asta vengono dalla stessa tabella.
    const daCercare = [...new Set([
      ...istanze.map((i) => i.player_id),
      ...asteRighe.map((a) => a.player_id),
      ...((spinRes.data as StatoSpinOffseason | null)?.spin ?? []).map((spin) => spin.player_id),
    ])]
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
    const fotoPerId = new Map(fotoFirmate.filter((entry): entry is readonly [number, string] => Boolean(entry[1])))
    const perId = new Map((anagrafica ?? []).map((p) => [p.id, p as {
      id: number; nome: string; club: string; nazionalita: string | null; posizioni: string[]
      piede: string | null; altezza: number | null; attributi: Record<string, number | null>
      overall: number; eta: number; foto_url: string | null
    }]))
    setProposte((proposteRes.data ?? []) as Proposta[])
    setTrattativePubbliche(trattativeRes.error ? [] : (trattativeRes.data ?? []) as TrattativaPubblica[])
    setAste(asteRighe)
    setMieOfferte(new Map((offerteRes.data ?? []).map((o) => [o.auction_id, o.ingaggio_offerto])))
    const statoSpin = spinRes.data as StatoSpinOffseason | null
    setSpinOffseason(statoSpin ? {
      ...statoSpin,
      spin: statoSpin.spin.map((spin) => ({
        ...spin,
        foto_url: perId.get(spin.player_id)?.foto_url ?? null,
        foto_firmata: fotoPerId.get(spin.player_id),
      })),
    } : null)
    // Un errore qui non deve impedire di usare il mercato: e' un indicatore.
    setConti(contiRes.error ? null : contiRes.data as typeof conti)
    setSvincolati(new Map(asteRighe.map((a) => [a.player_id, {
      nome: cognome(perId.get(a.player_id)?.nome ?? '—'),
      ruolo: perId.get(a.player_id)?.posizioni?.[0] ?? '—',
      club: perId.get(a.player_id)?.club ?? '—',
      posizioni: perId.get(a.player_id)?.posizioni ?? [],
      overall: perId.get(a.player_id)?.overall ?? 0,
      eta: perId.get(a.player_id)?.eta ?? 0,
      foto_url: perId.get(a.player_id)?.foto_url ?? null,
      foto_firmata: fotoPerId.get(a.player_id),
    }])))
    setRose(istanze.map((i) => ({
      id: i.id,
      player_id: i.player_id,
      team_id: i.team_id as number,
      overall: i.overall_corrente,
      eta: i.eta_corrente,
      ingaggio: i.ingaggio,
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
      sulMercato: i.sul_mercato,
    })))
    setCaricamento(false)
  }, [league.id])

  useEffect(() => { void carica() }, [carica])

  const nomeSquadra = useCallback(
    (id: number) => dati.teamById.get(id)?.nome ?? 'Squadra',
    [dati.teamById],
  )
  const stemma = useCallback((id: number) => <Crest
    value={dati.teamById.get(id)?.stemma_url ?? null}
    imageUrl={dati.crestUrlByTeamId.get(id) ?? null}
  />, [dati.teamById, dati.crestUrlByTeamId])
  const giocatore = useCallback((id: number) => rose.find((g) => g.id === id), [rose])

  // Quanti giocatori per macro-ruolo ha ciascuna squadra: e' l'unico segnale
  // che uso per il "rumor" degli svincolati (chi sembra scoperto in quel
  // ruolo). Nessun dato riservato: la rosa delle altre squadre e' gia'
  // pubblica in questa schermata (si vede scegliendo l'avversaria sotto).
  const conteggioRuoli = useMemo(() => {
    const mappa = new Map<number, Record<MacroRuolo, number>>()
    for (const g of rose) {
      const mr = macroRuolo(g.posizioni ?? [g.ruolo])
      const voce = mappa.get(g.team_id) ?? { ALL: 0, GK: 0, DEF: 0, MID: 0, ATT: 0 }
      voce[mr]++
      voce.ALL++
      mappa.set(g.team_id, voce)
    }
    return mappa
  }, [rose])

  // Trattative reali di tutta la lega, non solo le mie (decisione
  // dell'utente): chi offre cosa a chi, mai il conguaglio ne' il messaggio.
  const righeScambio = useMemo<RigaRumor[]>(() => trattativePubbliche.map((t): RigaRumor => ({
    tipo: 'scambio', key: `scambio-${t.id}`,
    daTeamId: t.da_team_id, aTeamId: t.a_team_id,
    offerti: t.giocatori_offerti.map((id) => giocatore(id)).filter((g): g is NonNullable<typeof g> => Boolean(g))
      .map((g) => ({ nome: g.nome, foto: g.foto_firmata })),
    richiesti: t.giocatori_richiesti.map((id) => giocatore(id)).filter((g): g is NonNullable<typeof g> => Boolean(g))
      .map((g) => ({ nome: g.nome, foto: g.foto_firmata })),
  })), [trattativePubbliche, giocatore])

  // Rumor speculativi sugli svincolati piu' quotati: la squadra di
  // destinazione NON viene dalle offerte reali (busta chiusa, non si tocca),
  // ma da un peso pubblico su slot liberi e scopertura nel ruolo. Puo'
  // anche sbagliare, come i rumor veri.
  const righeRumorSvincolati = useMemo<RigaRumor[]>(() => {
    const aperte = aste.filter((a) => a.stato === 'aperta')
      .sort((a, b) => b.ingaggio_teorico - a.ingaggio_teorico)
      .slice(0, 8)
    return aperte.map((a): RigaRumor | null => {
      const anagrafica = svincolati.get(a.player_id)
      if (!anagrafica) return null
      const mr = macroRuolo(anagrafica.posizioni)
      const opzioni = dati.teams
        .filter((t) => (conteggioRuoli.get(t.id)?.ALL ?? 0) < ROSA_MASSIMA)
        .map((t) => ({ valore: t.id, peso: 1 / (1 + (conteggioRuoli.get(t.id)?.[mr] ?? 0)) }))
      const destinazioneId = scegliPesato(a.id, opzioni)
      if (destinazioneId == null) return null
      return {
        tipo: 'svincolato', key: `rumor-${a.id}`,
        nome: anagrafica.nome, foto: anagrafica.foto_firmata,
        destinazioneId,
      }
    }).filter((r): r is RigaRumor => r !== null)
  }, [aste, svincolati, dati.teams, conteggioRuoli])

  const righeRumor = useMemo(() => [...righeScambio, ...righeRumorSvincolati], [righeScambio, righeRumorSvincolati])
  const paginaRumorMax = Math.max(0, Math.ceil(righeRumor.length / PAGINA_RUMOR) - 1)
  useEffect(() => { setPaginaRumor((p) => Math.min(p, paginaRumorMax)) }, [paginaRumorMax])
  useEffect(() => {
    if (paginaRumorMax < 1) return
    const timer = window.setInterval(() => setPaginaRumor((p) => (p + 1) % (paginaRumorMax + 1)), 6000)
    return () => window.clearInterval(timer)
  }, [paginaRumorMax])

  const miaRosa = useMemo(
    () => rose.filter((g) => g.team_id === membership.id).sort((a, b) => b.overall - a.overall),
    [rose, membership.id],
  )
  const rosaAvversaria = useMemo(
    () => rose.filter((g) => g.team_id === avversaria).sort((a, b) => b.overall - a.overall),
    [rose, avversaria],
  )

  const ricevute = proposte.filter((p) => p.a_team_id === membership.id && p.stato === 'in_attesa')
  const inviate = proposte.filter((p) => p.da_team_id === membership.id && p.stato === 'in_attesa')
  const concluse = proposte.filter((p) => p.stato === 'accettata')

  // Il live e' l'ultima tornata di estrazione della giornata corrente, mai
  // l'unione delle tornate manuali gia' chiuse nello stesso giorno.
  const giornoAste = aste[0]?.giorno ?? null
  const asteDelGiorno = aste.filter((a) => a.giorno === giornoAste)
  const tornataLive = Math.max(0, ...asteDelGiorno
    .filter((a) => a.origine === 'estrazione')
    .map((a) => a.tornata))
  const nuoviDelGiorno = asteDelGiorno.filter((a) =>
    a.origine === 'estrazione' && a.tornata === tornataLive && a.stato === 'aperta')
  // Un'apertura manuale e' valida anche fuori orario, ma solo per le aste
  // dell'ultima estrazione: aste residue di giorni precedenti non devono
  // tenere artificialmente aperta tutta la pagina.
  const aperto = mercatoAperto() || nuoviDelGiorno.length > 0
  const mieProposteAperte = nuoviDelGiorno.filter((a) => a.stato === 'aperta' && mieOfferte.has(a.id))
  const giocatoriSottoContratto = new Set(rose.map((g) => g.player_id))

  // Vetrina "Mercato della lega": i giocatori messi in lista dalle squadre.
  // Filtri indipendenti da quelli dell'archivio svincolati: sono due elenchi
  // diversi e chi cerca un difensore qui non sta cercando lo stesso di là.
  const vetrinaMercato = useMemo(() => rose
    .filter((g) => g.sulMercato && g.team_id !== membership.id)
    .filter((g) => {
      const macro = macroRuolo(g.posizioni ?? [])
      return (vetrinaRuolo === 'ALL' || macro === vetrinaRuolo)
        && g.eta >= vetrinaEta[0] && g.eta <= vetrinaEta[1]
        && g.overall >= vetrinaOverall[0] && g.overall <= vetrinaOverall[1]
    })
    .sort((a, b) => b.overall - a.overall),
    [rose, vetrinaRuolo, vetrinaEta, vetrinaOverall, membership.id])
  const archivioSvincolati = Array.from(new Map(aste
    .filter((a) => a.stato === 'deserta' && !giocatoriSottoContratto.has(a.player_id))
    .map((a) => [a.player_id, a])).values())
    .filter((a) => {
      const g = svincolati.get(a.player_id)
      if (!g) return false
      const macro = macroRuolo(g.posizioni)
      return (filtroRuolo === 'ALL' || macro === filtroRuolo)
        && g.eta >= filtroEta[0] && g.eta <= filtroEta[1]
        && g.overall >= filtroOverall[0] && g.overall <= filtroOverall[1]
        && a.ingaggio_teorico / 1_000_000 >= filtroIngaggio[0]
        && a.ingaggio_teorico / 1_000_000 <= filtroIngaggio[1]
    })

  // La trasparenza e' il resoconto dell'ultima TORNATA di estrazione chiusa,
  // non dell'intera giornata: l'admin puo' aprire piu' mercati nello stesso
  // giorno e ogni nuova tornata deve sostituire la precedente.
  const tornateAste = Array.from(new Map(aste
    .filter((asta) => asta.origine === 'estrazione')
    .map((asta) => [`${asta.giorno}-${asta.tornata}`, { giorno: asta.giorno, tornata: asta.tornata }]))
    .values())
    .sort((a, b) => b.giorno.localeCompare(a.giorno) || b.tornata - a.tornata)
  const tornataTrasparenza = tornateAste.find(({ giorno, tornata }) =>
    !aste.some((asta) => asta.origine === 'estrazione' && asta.giorno === giorno && asta.tornata === tornata && asta.stato === 'aperta')) ?? null
  const giornoTrasparenza = tornataTrasparenza?.giorno ?? null
  const asteVinteTrasparenti = tornataTrasparenza == null ? [] : aste
    .filter((asta) => asta.origine === 'estrazione'
      && asta.giorno === tornataTrasparenza.giorno
      && asta.tornata === tornataTrasparenza.tornata
      && asta.stato === 'assegnata'
      && asta.vincitore_team_id != null)
    .sort((a, b) => a.id - b.id)
  const trattativeTrasparenti = giornoTrasparenza == null ? [] : concluse
    .filter((proposta) => proposta.risolta_il != null && giornoRoma(proposta.risolta_il) === giornoTrasparenza)

  async function offri(asta: Asta) {
    const grezzo = bozzaOfferta[asta.id] ?? ''
    const valore = Math.round(Number(grezzo.replace(',', '.')) * 1_000_000)
    if (!grezzo || Number.isNaN(valore)) { setEsito('Ingaggio non valido.'); return }
    await chiama(
      () => supabase.rpc('offri_per_svincolato', { p_auction_id: asta.id, p_ingaggio: valore }),
      'Offerta registrata. Si apre alle 21:00.',
    )
  }

  // La RPC esisteva già (controlla proprietà e finestra di mercato lato
  // server) ma nessun bottone la richiamava: ci si poteva solo pentire
  // modificando l'offerta, mai ritirandola del tutto.
  async function ritiraOfferta(asta: Asta) {
    await chiama(
      () => supabase.rpc('ritira_offerta', { p_auction_id: asta.id }),
      'Offerta ritirata.',
    )
  }

  async function offriArchivio(asta: Asta) {
    const grezzo = bozzaOfferta[asta.id] ?? ''
    const valore = Math.round(Number(grezzo.replace(',', '.')) * 1_000_000)
    if (!grezzo || Number.isNaN(valore)) { setEsito('Ingaggio non valido.'); return }
    await chiama(
      () => supabase.rpc('offri_per_svincolato_archivio', {
        p_league_id: league.id,
        p_player_id: asta.player_id,
        p_ingaggio: valore,
      }),
      'Offerta registrata. Il giocatore rientra nelle aste di oggi.',
    )
  }

  async function usaSpin() {
    if (inCorso || animazioneSpin) return
    setInCorso(true)
    setEsito(null)
    const nomi = [...new Set([
      ...rose.map((giocatore) => giocatore.nome),
      ...Array.from(svincolati.values()).map((giocatore) => giocatore.nome),
    ].filter(Boolean))]
    const partenza = performance.now()
    let indice = Math.floor(Math.random() * Math.max(nomi.length, 1))
    setAnimazioneSpin({ fase: 'giro', nome: nomi[indice] ?? 'Scouting in corso' })
    const rotazione = window.setInterval(() => {
      indice = (indice + 1 + Math.floor(Math.random() * 5)) % Math.max(nomi.length, 1)
      setAnimazioneSpin({ fase: 'giro', nome: nomi[indice] ?? 'Analisi del mercato' })
    }, 85)

    const risultato = await supabase.rpc('spin_offseason', { p_league_id: league.id })
    const attesa = Math.max(0, 1750 - (performance.now() - partenza))
    await new Promise((resolve) => window.setTimeout(resolve, attesa))
    window.clearInterval(rotazione)

    if (risultato.error) {
      setAnimazioneSpin(null)
      setEsito(risultato.error.message)
      setInCorso(false)
      return
    }

    const nuovoStato = risultato.data as StatoSpinOffseason
    const estratto = nuovoStato.spin.find((spin) => spin.stato === 'proposto')
    let fotoFirmata: string | undefined
    let fotoUrl: string | null = null
    if (estratto) {
      const { data: giocatore } = await supabase.from('players').select('foto_url').eq('id', estratto.player_id).maybeSingle()
      fotoUrl = giocatore?.foto_url ?? null
      if (fotoUrl?.startsWith('http')) fotoFirmata = fotoUrl
      else if (fotoUrl) {
        const { data } = await supabase.storage.from('player-photos').createSignedUrl(fotoUrl, 3600)
        fotoFirmata = data?.signedUrl
      }
      setAnimazioneSpin({ fase: 'reveal', nome: estratto.nome, overall: estratto.overall, ruolo: estratto.ruolo, foto: fotoFirmata })
    }
    await new Promise((resolve) => window.setTimeout(resolve, 850))
    setSpinOffseason({
      ...nuovoStato,
      spin: nuovoStato.spin.map((spin) => spin.id === estratto?.id ? { ...spin, foto_url: fotoUrl, foto_firmata: fotoFirmata } : spin),
    })
    setAnimazioneSpin(null)
    setEsito('Nuovo giocatore estratto.')
    setInCorso(false)
  }

  async function ingaggiaSpin(spin: SpinOffseason) {
    await chiama(
      () => supabase.rpc('ingaggia_spin_offseason', { p_spin_id: spin.id }),
      `${cognome(spin.nome)} ingaggiato.`,
    )
  }

  async function mandaSpinAlMercato(spin: SpinOffseason) {
    await chiama(
      () => supabase.rpc('manda_spin_al_mercato', { p_spin_id: spin.id }),
      `${cognome(spin.nome)} aggiunto agli svincolati del giorno.`,
    )
  }

  function alterna(elenco: number[], id: number, imposta: (v: number[]) => void) {
    imposta(elenco.includes(id) ? elenco.filter((x) => x !== id) : [...elenco, id])
  }

  // PromiseLike e non Promise: `supabase.rpc(...)` restituisce un builder
  // che si puo' attendere ma non e' una Promise vera.
  async function chiama(azione: () => PromiseLike<{ error: { message: string } | null }>, successo: string) {
    setInCorso(true)
    setEsito(null)
    const { error } = await azione()
    setInCorso(false)
    setEsito(error ? error.message : successo)
    // Dopo un'offerta, uno scambio o un ritiro aggiorniamo solo i dati: il
    // loader dell'intera pagina farebbe sembrare un refresh e spezzerebbe il
    // contesto dell'azione appena compiuta.
    if (!error) await carica(true)
  }

  async function invia() {
    const valore = Math.round(Number(conguaglio.replace(',', '.')) * 1_000_000)
    if (!avversaria || Number.isNaN(valore)) { setEsito('Conguaglio non valido.'); return }
    await chiama(
      () => supabase.rpc('proponi_scambio', {
        p_a_team_id: avversaria,
        p_giocatori_offerti: offerti,
        p_giocatori_richiesti: chiesti,
        p_conguaglio: valore,
        p_messaggio: messaggio.trim() || null,
      }),
      'Proposta inviata.',
    )
    setChiesti([]); setOfferti([]); setConguaglio('0'); setMessaggio('')
  }

  const cardSvincolato = (a: Asta, compatta = false) => {
    const g = svincolati.get(a.player_id)
    const mia = a.stato === 'aperta' ? mieOfferte.get(a.id) : undefined
    const macro = macroRuolo(g?.posizioni ?? [])
    return <article key={a.id} className={`free-agent-card ${compatta ? 'is-compact' : ''} ${a.stato !== 'aperta' ? 'is-closed' : ''}`}>
      <div className="free-agent-card__portrait">
        {g?.foto_firmata ? <img src={g.foto_firmata} alt="" loading="lazy" /> : <span aria-hidden="true">?</span>}
        <b>{g?.overall ?? '—'}</b>
      </div>
      <div className="free-agent-card__body">
        <header>
          <span className={`role-pill role-pill--${macro.toLowerCase()}`}>{g?.ruolo ?? '—'}</span>
          <small>{MACRO_LABEL[macro]}</small>
        </header>
        <strong>{g?.nome ?? `#${a.player_id}`}</strong>
        <p>{g?.club ?? '—'} · {g?.eta ?? '—'} anni · {g?.posizioni?.join(' / ') ?? '—'}</p>
        <footer>
          <em>Ingaggio minimo {milioni(a.ingaggio_teorico)}</em>
          {a.origine === 'spin_offseason' && <i>Spin</i>}
          {a.stato !== 'aperta' && <i>{a.stato === 'assegnata' ? 'Assegnato' : 'Svincolato storico'}</i>}
        </footer>
      </div>
      <div className="free-agent-card__bid">
        <input
          type="text" inputMode="decimal"
          placeholder={mia ? (mia / 1_000_000).toFixed(1).replace('.', ',') : 'M€'}
          value={bozzaOfferta[a.id] ?? ''}
          onChange={(e) => setBozzaOfferta({ ...bozzaOfferta, [a.id]: e.target.value })}
        />
        <div className="free-agent-card__bid-azioni">
          <button className="button button--secondary" type="button"
            disabled={inCorso || !aperto} onClick={() => void (a.stato === 'aperta' ? offri(a) : offriArchivio(a))}>
            {mia ? 'Modifica' : a.stato === 'aperta' ? 'Offri' : 'Rioffri'}
          </button>
          {mia !== undefined && a.stato === 'aperta' && <button className="button button--danger-ghost" type="button"
            disabled={inCorso || !aperto} onClick={() => void ritiraOfferta(a)}>
            Ritira
          </button>}
        </div>
        {mia && <small>Hai offerto {milioni(mia)}</small>}
      </div>
    </article>
  }

  // Stessa sagoma di card, per ruolo GK/DEF/MID/ATT nell'ordine in cui si
  // gioca a calcio: piu' facile trovare "quel difensore" in un elenco di 24
  // che scorrere l'ordine casuale con cui escono dall'estrazione.
  const perRuolo = (elenco: Asta[]) => {
    const gruppi = new Map<MacroRuolo, Asta[]>()
    for (const a of elenco) {
      const macro = macroRuolo(svincolati.get(a.player_id)?.posizioni ?? [])
      gruppi.set(macro, [...(gruppi.get(macro) ?? []), a])
    }
    return ORDINE_MACRO_RUOLO
      .filter((ruolo) => (gruppi.get(ruolo) ?? []).length > 0)
      .map((ruolo) => ({ ruolo, aste: gruppi.get(ruolo)! }))
  }

  const gruppiAsta = perRuolo(nuoviDelGiorno)
  const paginaAsta = gruppiAsta.find((gruppo) => gruppo.ruolo === paginaAstaRuolo) ?? gruppiAsta[0]

  useEffect(() => {
    if (giornoAste === null || tornataLive === 0) return
    setPaginaAstaRuolo('GK')
  }, [giornoAste, tornataLive])

  const listaGiocatori = (
    elenco: Giocatore[], selezionati: number[], imposta: (v: number[]) => void, vuoto: string,
  ) => elenco.length === 0
    ? <p className="season-empty">{vuoto}</p>
    : <ul className="mercato-rosa">
        {elenco.map((g) => <li key={g.id}>
          <button
            type="button"
            className={selezionati.includes(g.id) ? 'is-scelto' : ''}
            onClick={() => alterna(selezionati, g.id, imposta)}
            aria-pressed={selezionati.includes(g.id)}
          >
            <b>{g.overall}</b>
            <span><strong>{g.nome}</strong><small>{g.ruolo} · {g.eta} anni</small></span>
            <em>{milioni(g.ingaggio)}</em>
          </button>
        </li>)}
      </ul>

  const riepilogo = (p: Proposta) => <>
    <div className="mercato-scambio">
      <div>
        <small>{p.da_team_id === membership.id ? 'Offri' : 'Ti offre'}</small>
        {p.giocatori_offerti.length === 0
          ? <span className="mercato-nessuno">nessun giocatore</span>
          : p.giocatori_offerti.map((id) => <button key={id} type="button" className="mercato-nome-giocatore" onClick={() => setSchedaApertaId(id)}>{giocatore(id)?.nome ?? `#${id}`}</button>)}
      </div>
      <i aria-hidden="true">⇄</i>
      <div>
        <small>{p.da_team_id === membership.id ? 'Chiedi' : 'Ti chiede'}</small>
        {p.giocatori_richiesti.length === 0
          ? <span className="mercato-nessuno">nessun giocatore</span>
          : p.giocatori_richiesti.map((id) => <button key={id} type="button" className="mercato-nome-giocatore" onClick={() => setSchedaApertaId(id)}>{giocatore(id)?.nome ?? `#${id}`}</button>)}
      </div>
    </div>
    {p.conguaglio !== 0 && <p className="mercato-conguaglio">
      Conguaglio: <strong>{milioni(Math.abs(p.conguaglio))}</strong>{' '}
      {p.conguaglio > 0 ? `da ${nomeSquadra(p.da_team_id)}` : `da ${nomeSquadra(p.a_team_id)}`}
    </p>}
    {p.messaggio && <p className="mercato-messaggio">«{p.messaggio}»</p>}
  </>

  const schedaAperta = schedaApertaId != null ? giocatore(schedaApertaId) : undefined

  return <main className="app-shell season-shell">
    <GameNav league={league} active="mercato" onNavigate={onNavigate} />
    <header className="topbar season-topbar">
      <div className="brand-lockup brand-lockup--dark"><img src="/specialone-mark.svg" alt="" /><span>SpecialOne</span></div>
      <span className={`mercato-finestra ${aperto ? 'e-aperto' : ''}`}>
        {aperto ? 'Mercato aperto · chiude alle 21:00' : 'Mercato chiuso · apre alle 23:30'}
      </span>
    </header>

    {caricamento && <div className="season-page"><p className="season-empty">Carico il mercato…</p></div>}
    {errore && <div className="season-page"><p className="season-empty">{errore}</p></div>}

    {!caricamento && !errore && <div className="season-page season-page--narrow">
      <section className="season-title-row">
        <div>
          <p className="kicker">Stagione {league.stagione_corrente} · {league.nome}</p>
          <h1>Mercato.</h1>
          <p>Si tratta dalle 23:30 alle 21:00. Le proposte non accettate entro la chiusura scadono.</p>
        </div>
        <div className="season-total">
          <strong>{milioni(conti ? conti.disponibile : membership.budget)}</strong>
          <span>{conti && conti.impegnato > 0 ? 'disponibile' : 'budget'}</span>
        </div>
      </section>

      {conti && conti.impegnato > 0 && <p className="mercato-impegno">
        <strong>{milioni(conti.impegnato)}</strong> sono impegnati in offerte ancora aperte (ingaggio
        pro-rata sulle giornate rimanenti, non l'importo pieno offerto) e tornano disponibili se le
        perdi o le ritiri. Posti liberi in rosa: <strong>{conti.slot_liberi}</strong>.
      </p>}

      {esito && <p className="notice">{esito}</p>}

      {league.fase_carriera === 'offseason' && spinOffseason?.attivo && <section className="mercato-blocco mercato-spin">
        <div className="sezione-testa">
          <div><p className="kicker">Off-season</p><h2>Spin mercato</h2></div>
          <span>{spinOffseason.rimasti} / 5 rimasti</span>
        </div>
        <p className="mercato-nota">
          Ogni squadra ha 5 occasioni extra: lo spin propone un giocatore libero. Puoi prenderlo subito
          oppure mandarlo nella lista svincolati, dove tutta la lega puo fare offerta.
        </p>
        <div className={`mercato-spin-stage ${animazioneSpin ? 'is-running' : ''}`}>
        {animazioneSpin
          ? <div className={`spin-reel spin-reel--${animazioneSpin.fase}`}>
              <div className="spin-reel__portrait">
                {animazioneSpin.foto ? <img src={animazioneSpin.foto} alt="" /> : <span aria-hidden="true">S1</span>}
                {animazioneSpin.overall && <b>{animazioneSpin.overall}</b>}
              </div>
              <div><small>{animazioneSpin.fase === 'giro' ? 'DATABASE GIOCATORI' : 'PROFILO TROVATO'}</small><strong>{animazioneSpin.nome}</strong>{animazioneSpin.ruolo && <em>{animazioneSpin.ruolo}</em>}</div>
              <i aria-hidden="true" />
            </div>
          : spinOffseason.spin.filter((spin) => spin.stato === 'proposto').length === 0
          ? <button className="button button--primary" type="button" disabled={inCorso || spinOffseason.rimasti <= 0} onClick={() => void usaSpin()}>
              {spinOffseason.rimasti <= 0 ? 'Spin esauriti' : 'Usa uno spin'}
            </button>
          : spinOffseason.spin.filter((spin) => spin.stato === 'proposto').map((spin) => <article className="mercato-spin-card" key={spin.id}>
              <div className="mercato-spin-card__portrait">{spin.foto_firmata ? <img src={spin.foto_firmata} alt="" /> : <span aria-hidden="true">?</span>}<b>{spin.overall}</b></div>
              <span><strong>{spin.nome}</strong><small>{spin.ruolo} Â· {spin.eta} anni Â· {spin.club}</small></span>
              <em>{milioni(spin.ingaggio)}</em>
              <footer>
                <button className="button button--primary" type="button" disabled={inCorso} onClick={() => void ingaggiaSpin(spin)}>Ingaggia</button>
                <button className="button button--secondary" type="button" disabled={inCorso} onClick={() => void mandaSpinAlMercato(spin)}>Manda al mercato</button>
              </footer>
            </article>)}
        </div>
        {spinOffseason.spin.some((spin) => spin.stato !== 'proposto') && <ul className="mercato-spin-log">
          {spinOffseason.spin.filter((spin) => spin.stato !== 'proposto').slice(0, 5).map((spin) => <li key={spin.id}>
            <strong>{cognome(spin.nome)}</strong>
            <span>{spin.stato === 'ingaggiato' ? 'Ingaggiato' : 'Negli svincolati'}</span>
          </li>)}
        </ul>}
      </section>}

      {/* ---- Ricevute: la cosa piu' urgente, quindi per prima ---- */}
      <section className="mercato-blocco">
        <div className="sezione-testa"><div><p className="kicker">In arrivo</p><h2>Proposte ricevute</h2></div></div>
        {ricevute.length === 0
          ? <p className="season-empty">Nessuna proposta da valutare.</p>
          : ricevute.map((p) => <article className="mercato-card" key={p.id}>
              <header>{stemma(p.da_team_id)}<strong>{nomeSquadra(p.da_team_id)}</strong></header>
              {riepilogo(p)}
              <footer>
                <button className="button button--primary" type="button" disabled={inCorso || !aperto}
                  onClick={() => chiama(() => supabase.rpc('rispondi_a_proposta', { p_proposta_id: p.id, p_accetta: true }), 'Scambio concluso.')}>
                  Accetta
                </button>
                <button className="button button--secondary" type="button" disabled={inCorso}
                  onClick={() => chiama(() => supabase.rpc('rispondi_a_proposta', { p_proposta_id: p.id, p_accetta: false }), 'Proposta rifiutata.')}>
                  Rifiuta
                </button>
              </footer>
            </article>)}
      </section>

      {/* ---- Mercato svincolati: nuovi + archivio filtrabile ---- */}
      <section className="mercato-blocco mercato-svincolati">
        <div className="sezione-testa">
          <div><p className="kicker">Asta a busta chiusa</p><h2>Mercato svincolati live</h2></div>
          <span>{league.fase_carriera === 'offseason' ? '10 per ruolo' : '5 per ruolo'}</span>
        </div>
        <p className="mercato-nota">
          Ogni giorno escono nuovi giocatori bilanciati per ruolo: portieri, difensori, centrocampisti
          e attaccanti. Offri l'ingaggio annuale: nessuno vede le offerte altrui e alle 21:00 vince
          l'offerta piu alta sopra la richiesta nascosta. A parita vince chi ha offerto prima.
        </p>

        <div className="free-agent-daily">
          <div className="free-agent-heading">
            <div><p className="kicker">Asta a busta chiusa</p><h3>{nuoviDelGiorno.length} occasioni</h3></div>
            <small>{giornoAste ?? 'nessuna estrazione'}</small>
          </div>
          {nuoviDelGiorno.length === 0
            ? <p className="season-empty">Nessuna estrazione ancora. I nuovi svincolati escono ogni giorno alle 23:30.</p>
            : <>
                <nav className="free-agent-ruoli" aria-label="Ruolo degli svincolati">
                  {ORDINE_MACRO_RUOLO.map((ruolo) => {
                    const gruppo = gruppiAsta.find((voce) => voce.ruolo === ruolo)
                    const attivo = paginaAsta?.ruolo === ruolo
                    return <button
                      key={ruolo}
                      type="button"
                      className={attivo ? 'is-attivo' : ''}
                      disabled={!gruppo}
                      aria-current={attivo ? 'page' : undefined}
                      onClick={() => setPaginaAstaRuolo(ruolo)}
                    >
                      <span>{MACRO_LABEL[ruolo]}</span><b>{gruppo?.aste.length ?? 0}</b>
                    </button>
                  })}
                </nav>
                {paginaAsta && <div className="free-agent-gruppo">
                  <p className="free-agent-gruppo__titolo">{MACRO_LABEL[paginaAsta.ruolo]} · {paginaAsta.aste.length} giocatori</p>
                  <div className="free-agent-grid">{paginaAsta.aste.map((a) => cardSvincolato(a))}</div>
                </div>}
              </>}
        </div>

        {mostraArchivioSvincolati && <div className="free-agent-archive">
          <div className="free-agent-heading">
            <div><p className="kicker">Archivio</p><h3>Tutti gli svincolati</h3></div>
            <small>{archivioSvincolati.length} filtrati</small>
          </div>
          <div className="free-agent-filters">
            <label><span>Ruolo</span><select value={filtroRuolo} onChange={(e) => setFiltroRuolo(e.target.value as MacroRuolo)}>
              {(['ALL', 'GK', 'DEF', 'MID', 'ATT'] as MacroRuolo[]).map((r) => <option key={r} value={r}>{MACRO_LABEL[r]}</option>)}
            </select></label>
            <RangeFilter label="Eta" value={filtroEta} min={16} max={45} onChange={setFiltroEta} />
            <RangeFilter label="Ingaggio M€" value={filtroIngaggio} min={0} max={30} onChange={setFiltroIngaggio} />
            <RangeFilter label="Overall" value={filtroOverall} min={50} max={99} onChange={setFiltroOverall} />
          </div>
          {archivioSvincolati.length === 0
            ? <p className="season-empty">Nessun giocatore con questi filtri.</p>
            : <div className="free-agent-list">{archivioSvincolati.map((a) => cardSvincolato(a, true))}</div>}
        </div>}
      </section>

      {/* ---- Le mie proposte: solo le aste su cui ho gia' offerto, per
          ritirarle o modificarle senza dover ripescare la carta giusta nella
          griglia grande qui sopra. ---- */}
      <section className="mercato-blocco">
        <div className="sezione-testa">
          <div><p className="kicker">Asta a busta chiusa</p><h2>Le mie proposte</h2></div>
          <span>{mieProposteAperte.length} {mieProposteAperte.length === 1 ? 'offerta' : 'offerte'}</span>
        </div>
        <p className="mercato-nota">Solo gli svincolati per cui hai già fatto un'offerta. Da qui la modifichi o la ritiri.</p>
        {mieProposteAperte.length === 0
          ? <p className="season-empty">Non hai ancora offerto per nessuno svincolato oggi.</p>
          : <div className="free-agent-grid">{mieProposteAperte.map((a) => cardSvincolato(a, true))}</div>}
      </section>

      {/* ---- Vetrina: chi le squadre hanno messo in lista ---- */}
      <section className="mercato-blocco">
        <div className="sezione-testa">
          <div><p className="kicker">Lista trasferimenti</p><h2>Mercato della lega</h2></div>
          <small>{vetrinaMercato.length} in lista</small>
        </div>
        <p className="mercato-nota">
          I giocatori che le squadre hanno messo sul mercato. È una vetrina: per trattare
          davvero, manda una proposta di scambio alla squadra proprietaria.
        </p>
        <div className="free-agent-filters free-agent-filters--vetrina">
          <label><span>Ruolo</span><select value={vetrinaRuolo} onChange={(e) => setVetrinaRuolo(e.target.value as MacroRuolo)}>
            {(['ALL', 'GK', 'DEF', 'MID', 'ATT'] as MacroRuolo[]).map((r) => <option key={r} value={r}>{MACRO_LABEL[r]}</option>)}
          </select></label>
          <RangeFilter label="Eta" value={vetrinaEta} min={16} max={45} onChange={setVetrinaEta} />
          <RangeFilter label="Overall" value={vetrinaOverall} min={50} max={99} onChange={setVetrinaOverall} />
        </div>
        {vetrinaMercato.length === 0
          ? <p className="season-empty">Nessun giocatore in lista con questi filtri.</p>
          : <div className="vetrina-list">{vetrinaMercato.map((g) => <button
              className="vetrina-card"
              type="button"
              key={g.id}
              onClick={() => proponiPerGiocatore(g)}
              aria-label={`Proponi uno scambio per ${g.nome}`}
            >
              <span className="vetrina-card__foto">
                {g.foto_firmata ? <img src={g.foto_firmata} alt="" loading="lazy" /> : <i aria-hidden="true">{g.nome.charAt(0)}</i>}
              </span>
              <span className="vetrina-card__info">
                <strong>{g.nome}</strong>
                <small>{(g.posizioni ?? [g.ruolo]).join(' · ')} · {g.eta} anni</small>
                <em>{nomeSquadra(g.team_id)}</em>
              </span>
              <span className="vetrina-card__numeri">
                <b>{g.overall}</b>
                <small>{(g.ingaggio / 1_000_000).toFixed(1)} M€</small>
              </span>
            </button>)}</div>}
      </section>

      <section className="mercato-blocco mercato-rumors">
        <div className="sezione-testa">
          <div><p className="kicker">Voci di mercato</p><h2>Rumors</h2></div>
          <img className="rumors-logo" src="/loghi/Transfermarkt_logo.svg" alt="" />
        </div>
        {righeRumor.length === 0
          ? <p className="season-empty">Nessuna voce di mercato al momento.</p>
          : <>
            {/* Tutte le pagine restano montate (solo quella attiva e' visibile):
                cosi' il browser carica le foto una volta sola in background,
                invece di doverle ripescare ogni volta che il carosello
                cambia pagina. */}
            {Array.from({ length: paginaRumorMax + 1 }, (_, pagina) => <ul key={pagina} className={`rumors-lista ${pagina === paginaRumor ? '' : 'is-nascosta'}`}>
              {righeRumor.slice(pagina * PAGINA_RUMOR, pagina * PAGINA_RUMOR + PAGINA_RUMOR).map((riga) => riga.tipo === 'svincolato'
                ? <li key={riga.key} className="rumors-riga rumors-riga--svincolato">
                    <div className="rumors-foto">
                      {riga.foto ? <img src={riga.foto} alt="" /> : <span className="rumors-foto-vuota" aria-hidden="true" />}
                    </div>
                    <div className="rumors-info">
                      <strong>{riga.nome}</strong>
                      <span className="rumors-etichetta rumors-etichetta--svincolato">Rumor</span>
                    </div>
                    <i aria-hidden="true">→</i>
                    <div className="rumors-destinazione">{stemma(riga.destinazioneId)}</div>
                  </li>
                : <li key={riga.key} className="rumors-riga rumors-riga--scambio">
                    <div className="rumors-scambio-lato">
                      <span className="rumors-scambio-stemma">{stemma(riga.daTeamId)}</span>
                      <div className="rumors-scambio-giocatore">
                        <div className="rumors-foto">
                          {riga.offerti[0]?.foto ? <img src={riga.offerti[0].foto} alt="" />
                            : riga.offerti[0] ? <span className="rumors-foto-vuota" aria-hidden="true" />
                            : <span className="rumors-foto-conguaglio" aria-hidden="true">€</span>}
                          {riga.offerti.length > 1 && <b className="rumors-extra">+{riga.offerti.length - 1}</b>}
                        </div>
                        <small>{riga.offerti[0]?.nome ?? 'Conguaglio'}</small>
                      </div>
                    </div>
                    <div className="rumors-scambio-centro">
                      <span className="rumors-etichetta rumors-etichetta--scambio">Trattativa</span>
                      <i aria-hidden="true">⇄</i>
                    </div>
                    <div className="rumors-scambio-lato rumors-scambio-lato--destra">
                      <div className="rumors-scambio-giocatore">
                        <div className="rumors-foto">
                          {riga.richiesti[0]?.foto ? <img src={riga.richiesti[0].foto} alt="" />
                            : riga.richiesti[0] ? <span className="rumors-foto-vuota" aria-hidden="true" />
                            : <span className="rumors-foto-conguaglio" aria-hidden="true">€</span>}
                          {riga.richiesti.length > 1 && <b className="rumors-extra">+{riga.richiesti.length - 1}</b>}
                        </div>
                        <small>{riga.richiesti[0]?.nome ?? 'Conguaglio'}</small>
                      </div>
                      <span className="rumors-scambio-stemma">{stemma(riga.aTeamId)}</span>
                    </div>
                  </li>)}
            </ul>)}
            {righeRumor.length > PAGINA_RUMOR && <div className="rumors-paginazione">
              <button type="button" disabled={paginaRumor === 0} onClick={() => setPaginaRumor((p) => Math.max(0, p - 1))} aria-label="Pagina precedente">‹</button>
              <span>{paginaRumor + 1} / {paginaRumorMax + 1}</span>
              <button type="button" disabled={paginaRumor === paginaRumorMax} onClick={() => setPaginaRumor((p) => Math.min(paginaRumorMax, p + 1))} aria-label="Pagina successiva">›</button>
            </div>}
          </>}
      </section>

      {mostraListaLegacySvincolati && <>
      {/* ---- Svincolati del giorno: a busta chiusa ---- */}
      <section className="mercato-blocco">
        <div className="sezione-testa"><div><p className="kicker">Asta a busta chiusa</p><h2>Svincolati del giorno</h2></div></div>
        <p className="mercato-nota">
          Offri l’ingaggio annuale che sei disposto a pagare. <strong>Nessuno vede le offerte altrui</strong>,
          e nemmeno tu vedi quanto chiede davvero il giocatore: se lo sapessi offriresti sempre un euro sopra.
          Alle 21:00 vince l’offerta più alta che supera la sua richiesta, e <strong>a parità vince chi ha
          offerto prima</strong> — modificare l’offerta fa ripartire il tuo turno. Nessun limite al numero di
          aste vinte: contano solo il budget e gli slot liberi in rosa. <strong>Offrire impegna il
          denaro</strong> finché l’asta non si chiude, così non puoi promettere più di quanto hai.
        </p>

        {asteDelGiorno.length === 0
          ? <p className="season-empty">Nessuna estrazione ancora. I nuovi svincolati escono ogni giorno alle 23:30.</p>
          : <ul className="mercato-aste">
              {asteDelGiorno.map((a) => {
                const g = svincolati.get(a.player_id)
                const mia = mieOfferte.get(a.id)
                return <li key={a.id} className={a.stato !== 'aperta' ? 'e-chiusa' : ''}>
                  <b>{g?.overall ?? '—'}</b>
                  <span>
                    <strong>{g?.nome ?? `#${a.player_id}`}</strong>
                    <small>{g?.ruolo} · {g?.eta} anni · ingaggio minimo {milioni(a.ingaggio_teorico)}</small>
                  </span>
                  {a.stato === 'aperta'
                    ? <div className="mercato-asta-offerta">
                        <input
                          type="text" inputMode="decimal"
                          placeholder={mia ? (mia / 1_000_000).toFixed(1).replace('.', ',') : 'M€'}
                          value={bozzaOfferta[a.id] ?? ''}
                          onChange={(e) => setBozzaOfferta({ ...bozzaOfferta, [a.id]: e.target.value })}
                        />
                        <button className="button button--secondary" type="button"
                          disabled={inCorso || !aperto} onClick={() => void offri(a)}>
                          {mia ? 'Modifica' : 'Offri'}
                        </button>
                        {mia !== undefined && <button className="button button--danger-ghost" type="button"
                          disabled={inCorso || !aperto} onClick={() => void ritiraOfferta(a)}>
                          Ritira
                        </button>}
                      </div>
                    : <em className={a.stato === 'assegnata' ? 'e-presa' : ''}>
                        {a.stato === 'assegnata'
                          ? `${nomeSquadra(a.vincitore_team_id ?? 0)} · ${milioni(a.ingaggio_finale ?? 0)}`
                          : 'Nessuno l’ha preso'}
                      </em>}
                  {a.stato === 'aperta' && mia && <i className="mercato-asta-mia">Hai offerto {milioni(mia)}</i>}
                </li>
              })}
            </ul>}
      </section>

      </>}

      {/* ---- Compositore ---- */}
      <section className="mercato-blocco" ref={compositoreRef}>
        <div className="sezione-testa"><div><p className="kicker">Tratta</p><h2>Nuova proposta</h2></div></div>
        {!aperto && <p className="notice">Il mercato è chiuso: puoi preparare la proposta ma potrai inviarla dalle 23:30.</p>}

        <div className="mercato-scelta-squadra">
          {dati.teams.filter((s) => s.id !== membership.id).map((s) => <button
            key={s.id} type="button"
            className={avversaria === s.id ? 'is-scelto' : ''}
            onClick={() => { setAvversaria(s.id); setChiesti([]) }}
            aria-label={s.nome}
            aria-pressed={avversaria === s.id}
            title={s.nome}
          >
            {stemma(s.id)}
          </button>)}
        </div>

        {avversaria && <>
          <div className="mercato-colonne">
            <div>
              <h3>Cosa chiedi a {nomeSquadra(avversaria)}</h3>
              {listaGiocatori(rosaAvversaria, chiesti, setChiesti, 'Rosa non disponibile.')}
            </div>
            <div>
              <h3>Cosa offri</h3>
              {listaGiocatori(miaRosa, offerti, setOfferti, 'La tua rosa è vuota.')}
            </div>
          </div>

          <div className="mercato-conguaglio-riga">
            <label>
              <span>Conguaglio in M€</span>
              <input type="text" inputMode="decimal" value={conguaglio}
                onChange={(e) => setConguaglio(e.target.value)} placeholder="0" />
              <small>Positivo: paghi tu. Negativo: paga lui.</small>
            </label>
            <label>
              <span>Messaggio (facoltativo)</span>
              <input type="text" value={messaggio} maxLength={240}
                onChange={(e) => setMessaggio(e.target.value)} placeholder="Due righe per convincerlo" />
            </label>
          </div>

          <button className="button button--primary" type="button"
            disabled={inCorso || !aperto || (chiesti.length === 0 && offerti.length === 0)}
            onClick={() => void invia()}>
            {inCorso ? 'Invio…' : 'Invia la proposta'}
          </button>
        </>}
      </section>

      {/* ---- Inviate ---- */}
      <section className="mercato-blocco">
        <div className="sezione-testa"><div><p className="kicker">In uscita</p><h2>Proposte inviate</h2></div></div>
        {inviate.length === 0
          ? <p className="season-empty">Nessuna proposta in attesa di risposta.</p>
          : inviate.map((p) => <article className="mercato-card" key={p.id}>
              <header>{stemma(p.a_team_id)}<strong>A {nomeSquadra(p.a_team_id)}</strong></header>
              {riepilogo(p)}
              <footer>
                <button className="button button--secondary" type="button" disabled={inCorso}
                  onClick={() => chiama(() => supabase.rpc('ritira_proposta', { p_proposta_id: p.id }), 'Proposta ritirata.')}>
                  Ritira
                </button>
              </footer>
            </article>)}
      </section>

      {/* ---- Log pubblico: design §9.3, tutti vedono tutto ---- */}
      <section className="mercato-blocco">
        <div className="sezione-testa"><div><p className="kicker">Trasparenza</p><h2>Operazioni concluse</h2></div></div>
        <p className="mercato-nota">
          {giornoTrasparenza
            ? `Esiti della chiusura del ${giornoTrasparenza.split('-').reverse().join('/')}: scambi e aste vinte visibili a tutta la lega.`
            : 'Gli esiti del mercato appariranno qui alla prima chiusura.'}
        </p>
        {trattativeTrasparenti.length === 0 && asteVinteTrasparenti.length === 0
          ? <p className="season-empty">Nessuna operazione conclusa in questa chiusura.</p>
          : <ul className="mercato-log">
              {trattativeTrasparenti.map((p) => <li key={`scambio-${p.id}`}>
                <strong>{nomeSquadra(p.da_team_id)}</strong>
                <i aria-hidden="true">⇄</i>
                <strong>{nomeSquadra(p.a_team_id)}</strong>
                <span>
                  {p.giocatori_offerti.map((id) => giocatore(id)?.nome ?? `#${id}`).join(', ') || '—'}
                  {' per '}
                  {p.giocatori_richiesti.map((id) => giocatore(id)?.nome ?? `#${id}`).join(', ') || '—'}
                  {p.conguaglio !== 0 && ` · ${milioni(Math.abs(p.conguaglio))}`}
                </span>
                <em>{ETICHETTE_STATO[p.stato]}</em>
              </li>)}
              {asteVinteTrasparenti.map((asta) => <li key={`asta-${asta.id}`}>
                <strong>{svincolati.get(asta.player_id)?.nome ?? `#${asta.player_id}`}</strong>
                <i aria-hidden="true">→</i>
                <strong>{nomeSquadra(asta.vincitore_team_id!)}</strong>
                <span>Ingaggio concordato: {milioni(asta.ingaggio_finale ?? 0)}</span>
                <em>Asta vinta</em>
              </li>)}
            </ul>}
      </section>

      {schedaAperta && <SchedaGiocatore
        giocatore={{
          nome: schedaAperta.nome,
          club: schedaAperta.club,
          nazionalita: schedaAperta.nazionalita,
          posizioni: schedaAperta.posizioni ?? [schedaAperta.ruolo],
          overall: schedaAperta.overall,
          eta: schedaAperta.eta,
          piede: schedaAperta.piede,
          altezza: schedaAperta.altezza,
          ingaggio: schedaAperta.ingaggio,
          condizione: schedaAperta.condizione,
          infortunatoFinoA: schedaAperta.infortunatoFinoA,
          ritiroAnnunciato: schedaAperta.ritiroAnnunciato,
          attributi: schedaAperta.attributi ?? {},
        }}
        fotoUrl={schedaAperta.foto_firmata}
        onClose={() => setSchedaApertaId(null)}
      />}
    </div>}
  </main>
}

function RangeFilter({ label, value, min, max, onChange }: {
  label: string
  value: [number, number]
  min: number
  max: number
  onChange: (value: [number, number]) => void
}) {
  const [from, to] = value
  return <fieldset className="range-filter">
    <legend>{label}</legend>
    <input
      type="number"
      min={min}
      max={to}
      value={from}
      onChange={(e) => onChange([Math.max(min, Math.min(Number(e.target.value), to)), to])}
    />
    <input
      type="number"
      min={from}
      max={max}
      value={to}
      onChange={(e) => onChange([from, Math.min(max, Math.max(Number(e.target.value), from))])}
    />
  </fieldset>
}
