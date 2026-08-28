import { useCallback, useEffect, useMemo, useState } from 'react'
import { ROSA_MASSIMA } from '../lib/league'
import { cognome } from '../lib/nomi'
import { MACRO_LABEL, ORDINE_MACRO_RUOLO, macroRuolo, type MacroRuolo } from '../lib/ruoli'
import { supabase } from '../lib/supabase'
import { useSeasonData } from '../lib/useSeasonData'
import { formatCountdown, useOraCorrente } from '../lib/countdown'
import type { League, Membership } from '../types'
import { Crest } from './Crest'
import { GameNav, type GameView } from './GameNav'
import { LoadingLogo } from './LoadingLogo'
import { UnderlineTabs } from './ui/underline-tabs'

type Props = { membership: Membership; onNavigate: (view: GameView) => void }

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

type RigaRumor = { tipo: 'svincolato'; key: string; nome: string; foto?: string; destinazioneId: number }

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
  const adesso = useOraCorrente()
  const [rose, setRose] = useState<Giocatore[]>([])
  const [aste, setAste] = useState<Asta[]>([])
  const [svincolati, setSvincolati] = useState<Map<number, Anagrafica>>(new Map())
  // Solo le proprie: la RLS non consegna quelle altrui, ed e' il punto.
  const [mieOfferte, setMieOfferte] = useState<Map<number, number>>(new Map())
  const [bozzaOfferta, setBozzaOfferta] = useState<Record<number, string>>({})
  const [paginaAstaRuolo, setPaginaAstaRuolo] = useState<MacroRuolo>('GK')
  // Offrire impegna il denaro: quello che conta non e' il budget ma cio' che
  // resta dopo aver messo da parte le offerte ancora in gioco.
  const [conti, setConti] = useState<{ disponibile: number; impegnato: number; slot_liberi: number } | null>(null)
  const [caricamento, setCaricamento] = useState(true)
  const [errore, setErrore] = useState<string | null>(null)

  const [filtroRuolo, setFiltroRuolo] = useState<MacroRuolo>('ALL')
  const [filtroEta, setFiltroEta] = useState<[number, number]>([16, 45])
  const [filtroIngaggio, setFiltroIngaggio] = useState<[number, number]>([0, 30])
  const [filtroOverall, setFiltroOverall] = useState<[number, number]>([50, 99])
  const [inCorso, setInCorso] = useState(false)
  const [offertaInCorso, setOffertaInCorso] = useState<{ id: number; tipo: 'offri' | 'modifica' | 'ritira' } | null>(null)
  const [esito, setEsito] = useState<string | null>(null)
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
    const [istanzeRes, asteRes, offerteRes, contiRes] = await Promise.all([
      supabase.from('player_instances')
        .select('id, team_id, player_id, overall_corrente, eta_corrente, ingaggio, condizione, infortunato_fino_a, ritiro_annunciato')
        .eq('league_id', league.id).not('team_id', 'is', null),
      supabase.from('free_agent_auctions')
        .select('id, giorno, tornata, player_id, ingaggio_teorico, stato, origine, vincitore_team_id, ingaggio_finale')
        .eq('league_id', league.id).order('giorno', { ascending: false }).order('id').limit(500),
      supabase.from('free_agent_bids').select('auction_id, ingaggio_offerto'),
      supabase.rpc('budget_disponibile', { p_league_id: league.id }),
    ])
    const primoErrore = istanzeRes.error ?? asteRes.error ?? offerteRes.error
    if (primoErrore) { setErrore(primoErrore.message); setCaricamento(false); return }

    const istanze = istanzeRes.data ?? []
    const asteRighe = (asteRes.data ?? []) as Asta[]
    // Una sola interrogazione per l'anagrafica: i giocatori delle rose e
    // quelli all'asta vengono dalla stessa tabella.
    const daCercare = [...new Set([
      ...istanze.map((i) => i.player_id),
      ...asteRighe.map((a) => a.player_id),
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
    setAste(asteRighe)
    setMieOfferte(new Map((offerteRes.data ?? []).map((o) => [o.auction_id, o.ingaggio_offerto])))
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

  const righeRumor = righeRumorSvincolati
  const paginaRumorMax = Math.max(0, Math.ceil(righeRumor.length / PAGINA_RUMOR) - 1)
  useEffect(() => { setPaginaRumor((p) => Math.min(p, paginaRumorMax)) }, [paginaRumorMax])
  useEffect(() => {
    if (paginaRumorMax < 1) return
    const timer = window.setInterval(() => setPaginaRumor((p) => (p + 1) % (paginaRumorMax + 1)), 6000)
    return () => window.clearInterval(timer)
  }, [paginaRumorMax])

  // Il live e' l'ultima tornata di estrazione della giornata corrente, mai
  // l'unione delle tornate manuali gia' chiuse nello stesso giorno. Esclude
  // le aste di origine spin off-season (funzionalita' rimossa, ma restano
  // aste storiche con questa origine): essendo datate col giorno corrente,
  // altrimenti nasconderebbero un'estrazione del giorno precedente ancora
  // aperta (chiude alle 21:00).
  const asteEstrazione = aste.filter((a) => a.origine === 'estrazione')
  const giornoAste = asteEstrazione[0]?.giorno ?? null
  const asteDelGiorno = asteEstrazione.filter((a) => a.giorno === giornoAste)
  const tornataLive = Math.max(0, ...asteDelGiorno
    .filter((a) => a.origine === 'estrazione')
    .map((a) => a.tornata))
  const nuoviDelGiorno = asteDelGiorno.filter((a) =>
    a.origine === 'estrazione' && a.tornata === tornataLive && a.stato === 'aperta')
  // Un'apertura manuale e' valida anche fuori orario, ma solo per le aste
  // dell'ultima estrazione: aste residue di giorni precedenti non devono
  // tenere artificialmente aperta tutta la pagina.
  const ultimaPartitaIl = useMemo(() => dati.matches.reduce<number | null>((ultima, partita) => {
    const istante = new Date(partita.simulata_il).getTime()
    return ultima == null || istante > ultima ? istante : ultima
  }, null), [dati.matches])
  const prossimaPartitaIl = dati.fixtures.filter((fixture) => fixture.stato === 'programmata')
    .reduce<number | null>((prossima, fixture) => {
      const istante = new Date(fixture.data_sim).getTime()
      return prossima == null || istante < prossima ? istante : prossima
    }, null)
  const cicloDinamico = ultimaPartitaIl != null && prossimaPartitaIl != null
  const aperturaMercatoIl = ultimaPartitaIl == null ? null : ultimaPartitaIl + 30 * 60 * 1000
  const chiusuraMercatoIl = prossimaPartitaIl == null ? null : prossimaPartitaIl - 2 * 60 * 60 * 1000
  const mercatoDinamicoAperto = cicloDinamico && aperturaMercatoIl != null && chiusuraMercatoIl != null
    && adesso >= aperturaMercatoIl && adesso < chiusuraMercatoIl
  const aperto = (cicloDinamico ? mercatoDinamicoAperto : mercatoAperto()) || nuoviDelGiorno.length > 0
  const etichettaMercato = cicloDinamico
    ? aperto
      ? `Mercato aperto · chiude tra ${formatCountdown(Math.max(0, (chiusuraMercatoIl ?? adesso) - adesso))}`
      : adesso < (aperturaMercatoIl ?? 0)
        ? `Mercato chiuso · apre tra ${formatCountdown(Math.max(0, (aperturaMercatoIl ?? adesso) - adesso))}`
        : 'Mercato chiuso · in attesa della prossima partita'
    : aperto ? 'Mercato aperto · chiude alle 21:00' : 'Mercato chiuso · apre alle 23:30'
  const mieProposteAperte = nuoviDelGiorno.filter((a) => a.stato === 'aperta' && mieOfferte.has(a.id))
  const giocatoriSottoContratto = new Set(rose.map((g) => g.player_id))

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

  async function offri(asta: Asta) {
    const grezzo = bozzaOfferta[asta.id] ?? ''
    const valore = Math.round(Number(grezzo.replace(',', '.')) * 1_000_000)
    if (!grezzo || Number.isNaN(valore)) { setEsito('Ingaggio non valido.'); return }
    setOffertaInCorso({ id: asta.id, tipo: mieOfferte.has(asta.id) ? 'modifica' : 'offri' })
    try {
      const riuscita = await chiama(
        () => supabase.rpc('offri_per_svincolato', { p_auction_id: asta.id, p_ingaggio: valore }),
        'Offerta registrata. Si apre alle 21:00.',
        350,
      )
      if (riuscita) setBozzaOfferta((correnti) => ({ ...correnti, [asta.id]: '' }))
    } finally {
      setOffertaInCorso(null)
    }
  }

  // La RPC esisteva già (controlla proprietà e finestra di mercato lato
  // server) ma nessun bottone la richiamava: ci si poteva solo pentire
  // modificando l'offerta, mai ritirandola del tutto.
  async function ritiraOfferta(asta: Asta) {
    setOffertaInCorso({ id: asta.id, tipo: 'ritira' })
    try {
      await chiama(
        () => supabase.rpc('ritira_offerta', { p_auction_id: asta.id }),
        'Offerta ritirata.',
        350,
      )
    } finally {
      setOffertaInCorso(null)
    }
  }

  async function offriArchivio(asta: Asta) {
    const grezzo = bozzaOfferta[asta.id] ?? ''
    const valore = Math.round(Number(grezzo.replace(',', '.')) * 1_000_000)
    if (!grezzo || Number.isNaN(valore)) { setEsito('Ingaggio non valido.'); return }
    setOffertaInCorso({ id: asta.id, tipo: 'offri' })
    try {
      const riuscita = await chiama(
        () => supabase.rpc('offri_per_svincolato_archivio', {
          p_league_id: league.id,
          p_player_id: asta.player_id,
          p_ingaggio: valore,
        }),
        'Offerta registrata. Il giocatore rientra nelle aste di oggi.',
        350,
      )
      if (riuscita) setBozzaOfferta((correnti) => ({ ...correnti, [asta.id]: '' }))
    } finally {
      setOffertaInCorso(null)
    }
  }

  // PromiseLike e non Promise: `supabase.rpc(...)` restituisce un builder
  // che si puo' attendere ma non e' una Promise vera.
  async function chiama(azione: () => PromiseLike<{ error: { message: string } | null }>, successo: string, durataMinima = 0) {
    const partenza = performance.now()
    setInCorso(true)
    setEsito(null)
    try {
      const { error } = await azione()
      setEsito(error ? error.message : successo)
      // Dopo un'offerta, uno scambio o un ritiro aggiorniamo solo i dati: il
      // loader dell'intera pagina farebbe sembrare un refresh e spezzerebbe il
      // contesto dell'azione appena compiuta.
      if (!error) await carica(true)
      const attesa = Math.max(0, durataMinima - (performance.now() - partenza))
      if (attesa) await new Promise((resolve) => window.setTimeout(resolve, attesa))
      return !error
    } finally {
      setInCorso(false)
    }
  }

  const cardSvincolato = (a: Asta, compatta = false) => {
    const g = svincolati.get(a.player_id)
    const mia = a.stato === 'aperta' ? mieOfferte.get(a.id) : undefined
    const azioneInCorso = offertaInCorso?.id === a.id ? offertaInCorso.tipo : null
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
          <button className={`button button--secondary${azioneInCorso && azioneInCorso !== 'ritira' ? ' offerta-in-corso' : ''}`} type="button"
            disabled={inCorso || !aperto} onClick={() => void (a.stato === 'aperta' ? offri(a) : offriArchivio(a))}>
            {azioneInCorso && azioneInCorso !== 'ritira' ? <><span className="offerta-spinner" role="status" aria-label="Operazione sull'offerta in corso" />{azioneInCorso === 'modifica' ? 'Aggiorno…' : 'Invio…'}</> : mia ? 'Modifica' : a.stato === 'aperta' ? 'Offri' : 'Rioffri'}
          </button>
          {mia !== undefined && a.stato === 'aperta' && <button className={`button button--danger-ghost${azioneInCorso === 'ritira' ? ' offerta-in-corso' : ''}`} type="button"
            disabled={inCorso || !aperto} onClick={() => void ritiraOfferta(a)}>
            {azioneInCorso === 'ritira' ? <><span className="offerta-spinner" role="status" aria-label="Ritiro offerta in corso" />Ritiro…</> : 'Ritira'}
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

  return <main className="app-shell season-shell">
    <GameNav league={league} active="mercato" onNavigate={onNavigate} />
    <header className="topbar season-topbar">
      <div className="brand-lockup brand-lockup--dark"><img src="/specialone-mark.svg" alt="" /><span>SpecialOne</span></div>
      <span className={`mercato-finestra ${aperto ? 'e-aperto' : ''}`}>
        {etichettaMercato}
      </span>
    </header>

    {caricamento && <div className="season-page"><section className="season-state mercato-caricamento"><LoadingLogo compatto /><h2>Preparo il mercato…</h2><p>Recupero trattative, svincolati e disponibilità.</p></section></div>}
    {errore && <div className="season-page"><p className="season-empty">{errore}</p></div>}

    {!caricamento && !errore && <div className="season-page season-page--narrow">
      <section className="season-title-row">
        <div>
          <p className="kicker">Stagione {league.stagione_corrente} · {league.nome}</p>
          <h1>Free Agent.</h1>
          <p>Asta a busta chiusa: si offre dalle 23:30 alle 21:00.</p>
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
                <UnderlineTabs
                  tabs={ORDINE_MACRO_RUOLO.map((ruolo) => {
                    const gruppo = gruppiAsta.find((voce) => voce.ruolo === ruolo)
                    return { value: ruolo, label: MACRO_LABEL[ruolo], badge: gruppo?.aste.length ?? 0, disabled: !gruppo }
                  })}
                  value={paginaAstaRuolo}
                  onChange={setPaginaAstaRuolo}
                  layoutId="mercato-ruolo-indicator"
                  className="mb-4"
                />
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
              {righeRumor.slice(pagina * PAGINA_RUMOR, pagina * PAGINA_RUMOR + PAGINA_RUMOR).map((riga) =>
                <li key={riga.key} className="rumors-riga rumors-riga--svincolato">
                    <div className="rumors-foto">
                      {riga.foto ? <img src={riga.foto} alt="" /> : <span className="rumors-foto-vuota" aria-hidden="true" />}
                    </div>
                    <div className="rumors-info">
                      <strong>{riga.nome}</strong>
                      <span className="rumors-etichetta rumors-etichetta--svincolato">Rumor</span>
                    </div>
                    <i aria-hidden="true">→</i>
                    <div className="rumors-destinazione">{stemma(riga.destinazioneId)}</div>
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

      {/* ---- Log pubblico: design §9.3, tutti vedono tutto ---- */}
      <section className="mercato-blocco">
        <div className="sezione-testa"><div><p className="kicker">Trasparenza</p><h2>Operazioni concluse</h2></div></div>
        <p className="mercato-nota">
          {giornoTrasparenza
            ? `Esiti della chiusura del ${giornoTrasparenza.split('-').reverse().join('/')}: aste vinte visibili a tutta la lega.`
            : 'Gli esiti del mercato appariranno qui alla prima chiusura.'}
        </p>
        {asteVinteTrasparenti.length === 0
          ? <p className="season-empty">Nessuna operazione conclusa in questa chiusura.</p>
          : <ul className="mercato-trasparenza">
              {asteVinteTrasparenti.map((asta) => {
                const g = svincolati.get(asta.player_id)
                return <li className="mercato-operazione mercato-operazione--asta" key={`asta-${asta.id}`}>
                  <div className="mercato-operazione__portrait">
                    {g?.foto_firmata ? <img src={g.foto_firmata} alt="" /> : <span>{(g?.nome ?? '?').slice(0, 1)}</span>}
                  </div>
                  <div className="mercato-operazione__firma">
                    <small>ASTA VINTA</small>
                    <strong>{g?.nome ?? `Giocatore #${asta.player_id}`}</strong>
                    <span>{g?.ruolo ?? 'Svincolato'} · Ingaggio {milioni(asta.ingaggio_finale ?? 0)}</span>
                  </div>
                  <div className="mercato-operazione__club mercato-operazione__club--firma">
                    {stemma(asta.vincitore_team_id!)}
                    <small>FIRMA PER</small>
                    <strong>{nomeSquadra(asta.vincitore_team_id!)}</strong>
                  </div>
                </li>
              })}
            </ul>}
      </section>
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
