import { useCallback, useEffect, useMemo, useState, type FormEvent } from 'react'
import { formatoStemma, generaUuidV4, preparaStemma } from '../lib/crest'
import { ROSA_MASSIMA, ROSA_MINIMA } from '../lib/league'
import { supabase } from '../lib/supabase'
import { STEMMA_SQUADRA_DEFAULT, stemmaPresetDaValore } from '../lib/teamCrests'
import { useSeasonData } from '../lib/useSeasonData'
import { useFaseSquadra } from '../lib/faseSquadra'
import type { CrestChoice, Fixture, League, MatchPlayerStat, Membership, Team } from '../types'
import { Crest } from './Crest'
import { CrestPicker } from './CrestPicker'
import { GameNav, type GameView } from './GameNav'
import { SchedaGiocatore, type EsitoRinnovo, type PropostaRinnovo, type StatsStagione } from './SchedaGiocatore'
import { FixtureScore, SeasonState, TeamLabel } from './SeasonUI'
import { UnderlineTabs } from './ui/underline-tabs'

type Props = {
  membership: Membership
  teamId: number
  onNavigate: (view: GameView) => void
  onOpenMatch: (matchId: number) => void
  onTeamUpdated: () => Promise<void>
}

type RosterPlayer = {
  id: number
  nome: string
  club: string
  nazionalita: string | null
  posizioni: string[]
  overall: number
  eta: number
  ingaggio: number
  condizione: number
  infortunatoFinoA: number
  squalificatoFinoA: number
  piede: string | null
  altezza: number | null
  attributi: Record<string, number | null>
  foto_url: string | null
  ritiroAnnunciato: boolean
  specializzazioneAttiva: string | null
  morale: number
  contrattoScadenza: number
  rinnovoStagione: number | null
  rinnovoTentativi: number
  sulMercato: boolean
  mentalita: { bandiera: number; economia: number; vittorie: number }
  minuti: number
  gol: number
  assist: number
}

type Scelta = {
  id: number
  team_origine_id: number
  team_proprietario_id: number
  stagione: number
  finestra: 'on' | 'off'
  posizione: number | null
  stato: 'futura' | 'determinata'
}

type CambioRuoloRiga = {
  id: number
  player_instance_id: number
  ruolo_precedente: string
  ruolo_target: string
  avviato_giornata: number
  completa_giornata: number
}

type SpecializzazioneRiga = {
  id: number
  player_instance_id: number
  specializzazione_precedente: string | null
  specializzazione_target: string
  avviato_giornata: number
  completa_giornata: number
}

type VivaioProspetto = {
  id: number
  ingaggio: number
  entrata_stagione: number
  potenziale_min: number
  potenziale_max: number
  giocatore: { nome: string; posizioni: string[]; overall: number; eta: number; nazionalita: string | null }
}

const ROLE_ORDER: Record<string, number> = { GK: 0, DEF: 1, MID: 2, ATT: 3 }
const DEF = new Set(['LB', 'CB', 'RB', 'LWB', 'RWB'])
const MID = new Set(['CDM', 'CM', 'CAM', 'LM', 'RM'])

function department(position = '') {
  if (position === 'GK') return 'GK'
  if (DEF.has(position)) return 'DEF'
  if (MID.has(position)) return 'MID'
  return 'ATT'
}

function money(value: number) { return `${(value / 1_000_000).toFixed(1)} M€` }

// Durata residua del contratto. Rosso quando la squadra sta per perdere il
// giocatore: ultima stagione utile, o ritiro annunciato.
function contratto(player: RosterPlayer, stagioneCorrente: number) {
  if (player.ritiroAnnunciato) return { testo: 'ritiro a termine stag.', urgente: true }
  if (player.rinnovoTentativi >= 3) return { testo: 'Non intende rinnovare.', urgente: true }
  const residue = player.contrattoScadenza - stagioneCorrente
  if (residue <= 0) return { testo: 'ultima stagione', urgente: true }
  return { testo: `ancora ${residue} ${residue === 1 ? 'stagione' : 'stagioni'}`, urgente: false }
}

// Anteprima della buonuscita che chiederà svincola_giocatore: meta' (per
// difetto) dell'ingaggio delle stagioni residue dopo quella in corso, zero
// se e' l'ultimo anno o se ha gia' annunciato il ritiro. La cifra vera la
// ricalcola comunque il server: questa e' solo per mostrarla prima di
// chiedere conferma.
function buonuscita(player: RosterPlayer, stagioneCorrente: number) {
  if (player.ritiroAnnunciato) return 0
  const residue = Math.max(0, player.contrattoScadenza - stagioneCorrente)
  return Math.floor((residue * player.ingaggio) / 2)
}

export function TeamProfile({ membership, teamId, onNavigate, onOpenMatch, onTeamUpdated }: Props) {
  const league = membership.league as League
  const seasonData = useSeasonData(membership)
  const [tab, setTab] = useState<'sommario' | 'rosa' | 'vivaio'>('sommario')
  const [teamOverride, setTeamOverride] = useState<Team | null>(null)
  const [crestUrl, setCrestUrl] = useState<string | null>(null)
  const [players, setPlayers] = useState<RosterPlayer[]>([])
  const [statRows, setStatRows] = useState<MatchPlayerStat[]>([])
  const [schedaAperta, setSchedaAperta] = useState<RosterPlayer | null>(null)
  const [fotoScheda, setFotoScheda] = useState<string | undefined>(undefined)
  const [allenatore, setAllenatore] = useState<string | null>(null)
  const [rosterLoading, setRosterLoading] = useState(true)
  const [rosterError, setRosterError] = useState<string | null>(null)
  const [editing, setEditing] = useState(false)
  const [teamName, setTeamName] = useState('')
  const [crest, setCrest] = useState<CrestChoice>({ type: 'preset', value: STEMMA_SQUADRA_DEFAULT })
  const [saving, setSaving] = useState(false)
  const [saveError, setSaveError] = useState<string | null>(null)
  const [releasePending, setReleasePending] = useState(false)
  const [releaseError, setReleaseError] = useState<string | null>(null)
  const [rosterNotice, setRosterNotice] = useState<string | null>(null)
  const [scelte, setScelte] = useState<Scelta[]>([])
  const [scelteLoading, setScelteLoading] = useState(true)
  const [vivaioProspetti, setVivaioProspetti] = useState<VivaioProspetto[]>([])
  const [vivaioLoading, setVivaioLoading] = useState(true)
  const [vivaioErrore, setVivaioErrore] = useState<string | null>(null)
  const [vivaioSlotMassimi, setVivaioSlotMassimi] = useState(1)
  const [vivaioAzioneInCorso, setVivaioAzioneInCorso] = useState<number | null>(null)
  const [cambiRuolo, setCambiRuolo] = useState<Map<number, CambioRuoloRiga>>(new Map())
  const [specializzazioni, setSpecializzazioni] = useState<Map<number, SpecializzazioneRiga>>(new Map())
  const team = teamOverride?.id === teamId ? teamOverride : seasonData.teamById.get(teamId)
  const ownTeam = teamId === membership.id
  const fase = useFaseSquadra(league.id, teamId, seasonData.season?.id)
  // Sfondo dell'hero: il logo della squadra stessa, non quello di fase (quello
  // resta solo in Overview). Un preset risolve subito a un file statico; uno
  // stemma caricato ha bisogno della URL firmata già recuperata per il <Crest>.
  const crestBgUrl = team?.stemma_url?.startsWith('preset:')
    ? stemmaPresetDaValore(team.stemma_url)?.src ?? null
    : crestUrl

  // Notifica di successo (svincolo): sparisce da sola dopo 2 secondi. Il
  // cleanup annulla il timer se nel frattempo arriva un altro avviso o si
  // cambia pagina, altrimenti un timer vecchio spegnerebbe quello nuovo.
  useEffect(() => {
    if (!rosterNotice) return
    const timer = window.setTimeout(() => setRosterNotice(null), 2000)
    return () => window.clearTimeout(timer)
  }, [rosterNotice])

  // Il nome dell'allenatore e' leggibile solo fra chi condivide una lega
  // (policy profiles_lettura): fuori dalla lega la query non restituisce nulla.
  useEffect(() => {
    let active = true
    async function loadAllenatore() {
      if (!team?.user_id) { setAllenatore(null); return }
      const { data } = await supabase.from('profiles').select('nome_allenatore').eq('user_id', team.user_id).maybeSingle()
      if (active) setAllenatore((data as { nome_allenatore: string } | null)?.nome_allenatore ?? null)
    }
    void loadAllenatore()
    return () => { active = false }
  }, [team?.user_id])

  useEffect(() => {
    let active = true
    async function loadCrest() {
      if (!team?.stemma_url || team.stemma_url.startsWith('preset:')) { setCrestUrl(null); return }
      const { data } = await supabase.storage.from('team-crests').createSignedUrl(team.stemma_url, 3600)
      if (active) setCrestUrl(data?.signedUrl ?? null)
    }
    void loadCrest()
    return () => { active = false }
  }, [team?.stemma_url])

  const stemmiUsati = useMemo(
    () => seasonData.teams.filter((t) => t.attiva && t.id !== teamId).map((t) => t.stemma_url).filter((value): value is string => !!value),
    [seasonData.teams, teamId]
  )

  useEffect(() => {
    if (!team) return
    setTeamName(team.nome)
    setCrest(team.stemma_url?.startsWith('preset:')
      ? { type: 'preset', value: team.stemma_url }
      : team.stemma_url && crestUrl
        ? { type: 'existing', value: team.stemma_url, previewUrl: crestUrl }
        : { type: 'preset', value: STEMMA_SQUADRA_DEFAULT })
  }, [team, crestUrl])

  const caricaRoster = useCallback(async () => {
      setRosterLoading(true)
      setRosterError(null)
      const [instancesResult, statsResult, cambiRuoloResult, specializzazioniResult] = await Promise.all([
        supabase.from('player_instances').select('id, player_id, overall_corrente, eta_corrente, ingaggio, condizione, infortunato_fino_a, squalificato_fino_a, ritiro_annunciato, morale, contratto_scadenza, rinnovo_stagione, rinnovo_tentativi, sul_mercato, posizioni_override, attributi_override, specializzazione_attiva').eq('league_id', league.id).eq('team_id', teamId),
        supabase.from('match_stats').select('match_id, player_instance_id, minuti, gol, assist, tiri, tiri_porta, passaggi_tentati, passaggi_riusciti, contrasti_vinti, dribbling').eq('league_id', league.id).eq('team_id', teamId),
        supabase.from('cambi_ruolo').select('id, player_instance_id, ruolo_precedente, ruolo_target, avviato_giornata, completa_giornata').eq('league_id', league.id).eq('team_id', teamId).is('completato_il', null),
        supabase.from('specializzazioni_giocatore').select('id, player_instance_id, specializzazione_precedente, specializzazione_target, avviato_giornata, completa_giornata').eq('league_id', league.id).eq('team_id', teamId).is('completato_il', null),
      ])
      setCambiRuolo(new Map(((cambiRuoloResult.data ?? []) as CambioRuoloRiga[]).map((riga) => [riga.player_instance_id, riga])))
      setSpecializzazioni(new Map(((specializzazioniResult.data ?? []) as SpecializzazioneRiga[]).map((riga) => [riga.player_instance_id, riga])))
      const firstError = instancesResult.error ?? statsResult.error
      if (firstError) { setRosterError(firstError.message); setRosterLoading(false); return }
      const instances = instancesResult.data ?? []
      const playerIds = instances.map((item) => item.player_id)
      const { data: catalog, error: catalogError } = playerIds.length
        ? await supabase.from('players').select('id, nome, club, nazionalita, posizioni, piede, altezza, attributi, foto_url, mentalita_bandiera, mentalita_economia, mentalita_vittorie').in('id', playerIds)
        : { data: [], error: null }
      if (catalogError) { setRosterError(catalogError.message); setRosterLoading(false); return }
      const catalogById = new Map((catalog ?? []).map((item) => [item.id, item]))
      const totals = new Map<number, { minuti: number; gol: number; assist: number }>()
      for (const stat of (statsResult.data ?? []) as MatchPlayerStat[]) {
        const total = totals.get(stat.player_instance_id) ?? { minuti: 0, gol: 0, assist: 0 }
        total.minuti += stat.minuti; total.gol += stat.gol; total.assist += stat.assist
        totals.set(stat.player_instance_id, total)
      }
      const loaded = instances.map((instance) => {
        const info = catalogById.get(instance.player_id)
        const total = totals.get(instance.id) ?? { minuti: 0, gol: 0, assist: 0 }
        return {
          id: instance.id, nome: info?.nome ?? `Giocatore ${instance.id}`, club: info?.club ?? '—',
          nazionalita: info?.nazionalita ?? null, posizioni: instance.posizioni_override ?? info?.posizioni ?? [],
          overall: instance.overall_corrente, eta: instance.eta_corrente, ingaggio: instance.ingaggio,
          condizione: instance.condizione, infortunatoFinoA: instance.infortunato_fino_a, squalificatoFinoA: instance.squalificato_fino_a, piede: info?.piede ?? null, altezza: info?.altezza ?? null,
          // attributi_override (Gestione risorse, specializzazione TRAINING) sostituisce
          // solo le chiavi presenti: vedi private.completa_specializzazioni().
          attributi: { ...(info?.attributi ?? {}), ...(instance.attributi_override ?? {}) } as Record<string, number | null>,
          foto_url: info?.foto_url ?? null,
          ritiroAnnunciato: instance.ritiro_annunciato,
          specializzazioneAttiva: instance.specializzazione_attiva,
          morale: instance.morale,
          contrattoScadenza: instance.contratto_scadenza,
          rinnovoStagione: instance.rinnovo_stagione,
          rinnovoTentativi: instance.rinnovo_tentativi,
          sulMercato: instance.sul_mercato,
          mentalita: {
            bandiera: info?.mentalita_bandiera ?? 33,
            economia: info?.mentalita_economia ?? 33,
            vittorie: info?.mentalita_vittorie ?? 34,
          },
          ...total,
        }
      }).sort((left, right) => ROLE_ORDER[department(left.posizioni[0])] - ROLE_ORDER[department(right.posizioni[0])] || right.overall - left.overall || left.nome.localeCompare(right.nome, 'it'))
      setPlayers(loaded); setStatRows((statsResult.data ?? []) as MatchPlayerStat[]); setRosterLoading(false)
  }, [league.id, teamId])

  useEffect(() => { void caricaRoster() }, [caricaRoster])

  // Scelte ancora scambiabili (le usate/svuotate non sono piu' un asset):
  // visibili a tutta la lega, servono a chi guarda una squadra avversaria
  // per valutare se proporre uno scambio che le coinvolga.
  useEffect(() => {
    let active = true
    async function loadScelte() {
      setScelteLoading(true)
      const { data } = await supabase.from('scelte_draft')
        .select('id, team_origine_id, team_proprietario_id, stagione, finestra, posizione, stato')
        .eq('league_id', league.id).eq('team_proprietario_id', teamId)
        .in('stato', ['futura', 'determinata'])
        .order('stagione')
      // ON prima di OFF a parita' di stagione: l'ordine alfabetico di
      // .order('finestra') metterebbe "off" prima di "on".
      const ordinate = ((data ?? []) as Scelta[]).sort((a, b) =>
        a.stagione - b.stagione || (a.finestra === b.finestra ? 0 : a.finestra === 'on' ? -1 : 1))
      if (active) { setScelte(ordinate); setScelteLoading(false) }
    }
    void loadScelte()
    return () => { active = false }
  }, [league.id, teamId])

  // Chi e' in cantera e' visibile a tutta la lega (stessa policy delle
  // scelte, scoutare gli avversari e' voluto): l'overall e' sempre quello
  // vero, il potenziale nascosto NON viene mai richiesto al client — la
  // fascia (ne' centrata sul valore vero, ne' calcolabile a ritroso) arriva
  // gia' pronta da public.fascia_potenziale_giocatori, che si stringe
  // salendo di livello VIVAIO della squadra proprietaria.
  const caricaVivaio = useCallback(async () => {
    setVivaioLoading(true); setVivaioErrore(null)
    const [prospettiResult, tabellaResult, risorseResult] = await Promise.all([
      supabase.from('vivaio_prospetti')
        .select('id, ingaggio, entrata_stagione, player_id, giocatore:players(nome, posizioni, overall, eta, nazionalita)')
        .eq('league_id', league.id).eq('team_id', teamId),
      supabase.rpc('tabella_risorse'),
      supabase.from('team_risorse').select('livello_vivaio').eq('team_id', teamId).maybeSingle(),
    ])
    if (prospettiResult.error) { setVivaioErrore(prospettiResult.error.message); setVivaioLoading(false); return }
    const livello = (risorseResult.data as { livello_vivaio: number } | null)?.livello_vivaio ?? 0
    const scala = (tabellaResult.data as { rami?: { vivaio?: { slot: number }[] } } | null)?.rami?.vivaio
    setVivaioSlotMassimi(scala?.[livello]?.slot ?? 1)
    const righe = (prospettiResult.data ?? []) as unknown as (VivaioProspetto & { player_id: number })[]
    if (righe.length === 0) { setVivaioProspetti([]); setVivaioLoading(false); return }
    const { data: fasce } = await supabase.rpc('fascia_potenziale_giocatori', {
      p_player_ids: righe.map((r) => r.player_id), p_team_id: teamId,
    })
    const fasciaPerId = new Map<number, { player_id: number; potenziale_min: number; potenziale_max: number }>(
      (fasce ?? []).map((f: { player_id: number; potenziale_min: number; potenziale_max: number }) => [f.player_id, f]))
    setVivaioProspetti(righe.map((r) => ({
      ...r,
      potenziale_min: fasciaPerId.get(r.player_id)?.potenziale_min ?? r.giocatore.overall,
      potenziale_max: fasciaPerId.get(r.player_id)?.potenziale_max ?? r.giocatore.overall,
    })))
    setVivaioLoading(false)
  }, [league.id, teamId])

  useEffect(() => { void caricaVivaio() }, [caricaVivaio])

  async function promuovi(id: number) {
    setVivaioAzioneInCorso(id); setVivaioErrore(null)
    const { error } = await supabase.rpc('promuovi_vivaio', { p_vivaio_id: id })
    setVivaioAzioneInCorso(null)
    if (error) { setVivaioErrore(error.message); return }
    await caricaVivaio()
    await onTeamUpdated()
  }

  async function rilascia(id: number) {
    setVivaioAzioneInCorso(id); setVivaioErrore(null)
    const { error } = await supabase.rpc('rilascia_vivaio', { p_vivaio_id: id })
    setVivaioAzioneInCorso(null)
    if (error) { setVivaioErrore(error.message); return }
    await caricaVivaio()
  }

  // Prima giornata ancora da giocare: stima locale per il conto alla
  // rovescia del cambio ruolo, il server e' comunque l'unica fonte vera.
  const prossimaGiornata = useMemo(() => {
    const programmate = seasonData.fixtures.filter((f) => f.stato === 'programmata').map((f) => f.giornata)
    return programmate.length ? Math.min(...programmate) : null
  }, [seasonData.fixtures])

  async function caricaTargetCambioRuolo(instanceId: number) {
    const { data, error } = await supabase.rpc('ruoli_target_cambio', { p_instance_id: instanceId })
    if (error) throw new Error(error.message)
    return (data ?? []) as string[]
  }

  async function avviaCambioRuolo(instanceId: number, ruoloTarget: string) {
    const { error } = await supabase.rpc('avvia_cambio_ruolo', { p_instance_id: instanceId, p_ruolo_target: ruoloTarget })
    if (error) throw new Error(error.message)
    await caricaRoster()
  }

  async function annullaCambioRuolo(instanceId: number) {
    const cambio = cambiRuolo.get(instanceId)
    if (!cambio) return
    const { error } = await supabase.rpc('annulla_cambio_ruolo', { p_id: cambio.id })
    if (error) throw new Error(error.message)
    await caricaRoster()
  }

  async function caricaOpzioniSpecializzazione(instanceId: number) {
    const { data, error } = await supabase.rpc('specializzazioni_disponibili', { p_instance_id: instanceId })
    if (error) throw new Error(error.message)
    const catalogo = (data ?? {}) as Record<string, { etichetta: string; deltas: Record<string, number> }>
    return Object.entries(catalogo).map(([chiave, valore]) => ({
      chiave, etichetta: valore.etichetta, deltas: Object.entries(valore.deltas),
    }))
  }

  async function avviaSpecializzazione(instanceId: number, specializzazione: string) {
    const { error } = await supabase.rpc('avvia_specializzazione', { p_instance_id: instanceId, p_specializzazione: specializzazione })
    if (error) throw new Error(error.message)
    await caricaRoster()
  }

  async function annullaSpecializzazione(instanceId: number) {
    const allenamento = specializzazioni.get(instanceId)
    if (!allenamento) return
    const { error } = await supabase.rpc('annulla_specializzazione', { p_id: allenamento.id })
    if (error) throw new Error(error.message)
    await caricaRoster()
  }

  const standing = seasonData.standings.find((item) => item.team_id === teamId)
  const recentFixtures = useMemo(() => [...seasonData.fixtures].reverse().filter((fixture) => fixture.stato === 'simulata' && (fixture.home_team_id === teamId || fixture.away_team_id === teamId)).slice(0, 5), [seasonData.fixtures, teamId])

  // Esito dal punto di vista di questa squadra: serve sia ai chip della forma
  // sia alla striscia colorata di ogni risultato.
  const esitoDi = useCallback((fixture: Fixture) => {
    const match = seasonData.matchByFixture.get(fixture.id)
    if (!match) return null
    const inCasa = fixture.home_team_id === teamId
    const propri = inCasa ? match.gol_home : match.gol_away
    const subiti = inCasa ? match.gol_away : match.gol_home
    return propri > subiti ? 'V' : propri < subiti ? 'P' : 'N'
  }, [seasonData.matchByFixture, teamId])

  const forma = useMemo(() => [...recentFixtures].reverse().map(esitoDi).filter((esito): esito is 'V' | 'N' | 'P' => esito !== null), [recentFixtures, esitoDi])
  const totalWage = players.reduce((sum, player) => sum + player.ingaggio, 0)

  // Gol subiti dalla squadra in ogni partita: serve per la porta inviolata,
  // che non e' un dato del singolo giocatore ma della squadra in cui giocava.
  const subitiPerPartita = useMemo(() => {
    const mappa = new Map<number, number>()
    for (const match of seasonData.matches) {
      const fixture = seasonData.fixtures.find((item) => item.id === match.fixture_id)
      if (!fixture) continue
      if (fixture.home_team_id === teamId) mappa.set(match.id, match.gol_away)
      else if (fixture.away_team_id === teamId) mappa.set(match.id, match.gol_home)
    }
    return mappa
  }, [seasonData.matches, seasonData.fixtures, teamId])

  const statsPerGiocatore = useMemo(() => {
    const mappa = new Map<number, StatsStagione>()
    for (const riga of statRows) {
      const corrente = mappa.get(riga.player_instance_id) ?? {
        presenze: 0, minuti: 0, gol: 0, assist: 0, porteInviolate: 0,
        tiri: 0, tiriPorta: 0, passaggiTentati: 0, passaggiRiusciti: 0, contrastiVinti: 0, dribbling: 0,
      }
      if (riga.minuti > 0) {
        corrente.presenze += 1
        if (subitiPerPartita.get(riga.match_id) === 0) corrente.porteInviolate += 1
      }
      corrente.minuti += riga.minuti
      corrente.gol += riga.gol
      corrente.assist += riga.assist
      corrente.tiri += riga.tiri
      corrente.tiriPorta += riga.tiri_porta
      corrente.passaggiTentati += riga.passaggi_tentati
      corrente.passaggiRiusciti += riga.passaggi_riusciti
      corrente.contrastiVinti += riga.contrasti_vinti
      corrente.dribbling += riga.dribbling
      mappa.set(riga.player_instance_id, corrente)
    }
    return mappa
  }, [statRows, subitiPerPartita])

  useEffect(() => {
    let active = true
    async function firmaFoto() {
      if (!schedaAperta?.foto_url) { setFotoScheda(undefined); return }
      const { data } = await supabase.storage.from('player-photos').createSignedUrl(schedaAperta.foto_url, 3600)
      if (active) setFotoScheda(data?.signedUrl ?? undefined)
    }
    void firmaFoto()
    return () => { active = false }
  }, [schedaAperta])

  // Le righe di specializzazioni_giocatore/player_instances tengono solo la
  // CHIAVE (es. "box_to_box"): l'etichetta leggibile ("Box-to-box") arriva
  // dal catalogo server, la teniamo qui solo per non rifare la scelta.
  const [specEtichette, setSpecEtichette] = useState<Map<string, string>>(new Map())
  useEffect(() => {
    let active = true
    async function caricaEtichette() {
      if (!schedaAperta) return
      try {
        const opzioni = await caricaOpzioniSpecializzazione(schedaAperta.id)
        if (active) setSpecEtichette(new Map(opzioni.map((o) => [o.chiave, o.etichetta])))
      } catch {
        // silenzioso: sono solo etichette per il riepilogo, il pannello di
        // scelta le ricarica comunque quando si apre.
      }
    }
    void caricaEtichette()
    return () => { active = false }
  }, [schedaAperta?.id])

  async function saveProfile(event: FormEvent) {
    event.preventDefault()
    if (!team) return
    setSaving(true); setSaveError(null)
    let uploadedPath: string | null = null
    try {
      let crestPath = crest.type === 'upload' ? '' : crest.value
      if (crest.type === 'upload') {
        const blob = await preparaStemma(crest.file)
        const formato = formatoStemma(blob)
        uploadedPath = `${membership.user_id}/${generaUuidV4()}.${formato.extension}`
        const { error } = await supabase.storage.from('team-crests').upload(uploadedPath, blob, { contentType: formato.contentType, cacheControl: '31536000', upsert: false })
        if (error) throw error
        crestPath = uploadedPath
      }
      const { data, error } = await supabase.rpc('aggiorna_profilo_squadra', { p_team_id: team.id, p_nome: teamName, p_stemma_url: crestPath })
      if (error) throw error
      const updated = data as Team
      setTeamOverride(updated)
      if (team.stemma_url && !team.stemma_url.startsWith('preset:') && team.stemma_url !== crestPath) await supabase.storage.from('team-crests').remove([team.stemma_url])
      await onTeamUpdated()
      setEditing(false)
    } catch (caught) {
      if (uploadedPath) await supabase.storage.from('team-crests').remove([uploadedPath])
      setSaveError(caught instanceof Error ? caught.message : 'Modifica della squadra non riuscita.')
    }
    setSaving(false)
  }

  function openPlayer(player: RosterPlayer) {
    setReleaseError(null)
    setRosterNotice(null)
    setSchedaAperta(player)
  }

  async function releasePlayer() {
    if (!schedaAperta || !ownTeam) return
    setReleasePending(true)
    setReleaseError(null)
    const player = schedaAperta
    const { error } = await supabase.rpc('svincola_giocatore', { p_instance_id: player.id })
    if (error) {
      setReleaseError(error.message)
      setReleasePending(false)
      return
    }
    setPlayers((current) => current.filter((item) => item.id !== player.id))
    setStatRows((current) => current.filter((item) => item.player_instance_id !== player.id))
    setSchedaAperta(null)
    setRosterNotice(`${player.nome} è stato svincolato. Nessun rimborso è stato accreditato.`)
    setReleasePending(false)
  }

  return <main className="app-shell season-shell">
    <GameNav league={league} active="team" onNavigate={onNavigate} />
    <header className="topbar season-topbar"><div className="brand-lockup brand-lockup--dark"><img src="/specialone-mark.svg" alt="" /><span>SpecialOne</span></div><span>{ownTeam ? 'La tua squadra' : 'Profilo avversario'}</span></header>
    <SeasonState loading={seasonData.loading} error={seasonData.error} onRetry={seasonData.reload} />
    {!seasonData.loading && !seasonData.error && team && <>
      {/* Sfondo a piena larghezza come in Overview (fuori da season-page
          apposta, cosi' tocca i bordi), ma qui e' il logo della squadra
          stessa, satinato e sfocato — quello di fase resta solo in
          Overview, dove indica la competizione e non la squadra. */}
      <section className={`team-profile-hero team-profile-hero--${fase}`}>
        {crestBgUrl && <div className="team-profile-hero__vetro" style={{ backgroundImage: `url(${crestBgUrl})` }} aria-hidden="true" />}
        <div className="team-profile-hero__inner">
          <div className="team-profile-crest"><Crest value={team.stemma_url} imageUrl={crestUrl} size="large" /></div>
          <div className="team-profile-hero__testo">
            <p className="kicker">{league.nome} · Stagione {league.stagione_corrente}</p>
            <h1>{team.nome}</h1>
            {allenatore && <p className="team-allenatore">Allenatore · <b>{allenatore}</b></p>}
            <div className="team-form">
              <span className="team-form__eti">FORMA</span>
              {forma.map((esito, indice) => <span className={`esito esito--${esito}`} key={`e${indice}`}>{esito}</span>)}
              {Array.from({ length: Math.max(0, 5 - forma.length) }).map((_, indice) => <span className="esito esito--vuoto" key={`v${indice}`} aria-hidden="true">·</span>)}
            </div>
          </div>
          {ownTeam && <button className="button team-edit-button" type="button" onClick={() => setEditing((value) => !value)}>{editing ? 'Chiudi modifica' : 'Modifica squadra'}</button>}
        </div>
      </section>

      <div className="season-page team-profile-page">

      {ownTeam && editing && <form className="team-settings-panel" onSubmit={saveProfile}>
        <div><p className="kicker">Impostazioni squadra</p><h2>Nome e logo</h2><label>Nome squadra<input type="text" minLength={2} maxLength={40} required value={teamName} onChange={(event) => setTeamName(event.target.value)} /></label></div>
        <CrestPicker value={crest} onChange={setCrest} disabled={saving} disabledValues={stemmiUsati} />
        {saveError && <p className="notice notice--error">{saveError}</p>}
        <button className="button button--primary" type="submit" disabled={saving}>{saving ? 'Salvataggio…' : 'Salva modifiche'}</button>
      </form>}

      {/* Due tab, non cinque per imitare un riferimento: sono i due
          raggruppamenti di contenuto che esistono davvero in questa
          pagina. Forzarne altri avrebbe voluto dire inventare contenuti
          vuoti solo per somigliare a un'app con più dati da mostrare. */}
      <UnderlineTabs
        tabs={[
          { value: 'sommario', label: 'Sommario' },
          { value: 'rosa', label: `Rosa (${players.length})` },
          { value: 'vivaio', label: `Vivaio (${vivaioProspetti.length}/${vivaioSlotMassimi})` },
        ] as const}
        value={tab}
        onChange={setTab}
      />

      {tab === 'sommario' && <>
        {/* Una statistica domina, le altre servono: quattro riquadri identici
            appiattivano la pagina e non dicevano cosa guardare per primo. */}
        <section className="team-profile-stats">
          <article className="stat-guida">
            <span className="stat-guida__numero">{standing?.posizione ?? '—'}<sup>ª</sup></span>
            <span className="stat-guida__testo">
              <b>Posizione in classifica</b>
              <span>{standing?.punti ?? 0} punti · {standing?.vittorie ?? 0} {standing?.vittorie === 1 ? 'vittoria' : 'vittorie'}</span>
            </span>
          </article>
          <div className="stat-fila">
            <article><small>Bilancio</small><b>{standing ? `${standing.vittorie}-${standing.pareggi}-${standing.sconfitte}` : '0-0-0'}</b></article>
            <article><small>Reti</small><b className={(standing?.differenza_reti ?? 0) < 0 ? 'is-negativo' : (standing?.differenza_reti ?? 0) > 0 ? 'is-positivo' : ''}>{standing && standing.differenza_reti > 0 ? `+${standing.differenza_reti}` : standing?.differenza_reti ?? 0}</b></article>
            <article><small>Overall</small><b>{players.length ? (players.reduce((sum, player) => sum + player.overall, 0) / players.length).toFixed(1) : '—'}</b></article>
          </div>
        </section>

        <section className="team-profile-grid">
          <article className="team-profile-panel team-recent-panel"><div className="season-card__heading"><div><p className="kicker">Forma recente</p><h2>Ultime partite</h2></div></div>{recentFixtures.length ? recentFixtures.map((fixture) => { const match = seasonData.matchByFixture.get(fixture.id); return <button className={`esito-riga esito-riga--${esitoDi(fixture) ?? 'N'}`} type="button" key={fixture.id} onClick={() => match && onOpenMatch(match.id)}><TeamLabel team={seasonData.teamById.get(fixture.home_team_id)} imageUrl={seasonData.crestUrlByTeamId.get(fixture.home_team_id)} /><FixtureScore fixture={fixture} match={match} /><TeamLabel team={seasonData.teamById.get(fixture.away_team_id)} imageUrl={seasonData.crestUrlByTeamId.get(fixture.away_team_id)} reversed /></button> }) : <p className="season-empty">Nessuna partita disputata.</p>}</article>
          <article className="team-profile-panel team-budget-panel"><p className="kicker">Gestione rosa</p><h2>{players.length} giocatori</h2><dl><div><dt>Valore ingaggi</dt><dd>{money(totalWage)}</dd></div>{ownTeam ? <div><dt>Capienza residua</dt><dd>{money(Math.max(0, league.tetto_ingaggi - totalWage))}</dd></div> : <div><dt>Gol segnati</dt><dd>{standing?.gol_fatti ?? 0}</dd></div>}<div><dt>Overall medio</dt><dd>{players.length ? (players.reduce((sum, player) => sum + player.overall, 0) / players.length).toFixed(1) : '—'}</dd></div></dl></article>
        </section>

        {/* In fondo, cosi' chi guarda una squadra avversaria sa subito cosa
            possiede in scelte future prima di valutare uno scambio. */}
        <section className="team-profile-panel team-picks-panel">
          <div className="season-card__heading"><div><p className="kicker">Portafoglio scelte</p><h2>{scelte.length ? `${scelte.length} in mano` : 'Nessuna scelta'}</h2></div></div>
          {scelteLoading ? <p className="season-empty">Carico le scelte…</p> : scelte.length ? (
            <ul className="scelte-lista">
              {scelte.map((s) => {
                const origine = seasonData.teamById.get(s.team_origine_id)
                return <li className={`scelta-ticket scelta-ticket--${s.finestra}`} key={s.id}>
                  <div className="scelta-ticket__taglio" aria-hidden="true">
                    <span className="scelta-ticket__stagione">S{s.stagione}</span>
                    <span className={`scelta-ticket__finestra scelta-ticket__finestra--${s.finestra}`}>{(s.finestra === 'on' ? 'ON-Season' : 'OFF-Season').toUpperCase()}</span>
                  </div>
                  <div className="scelta-ticket__corpo">
                    <div className="scelta-ticket__origine">
                      <Crest value={origine?.stemma_url ?? null} imageUrl={origine ? seasonData.crestUrlByTeamId.get(origine.id) : undefined} />
                      <small>{origine?.nome ?? 'Squadra sconosciuta'}</small>
                    </div>
                    <div className="scelta-ticket__dettagli">
                      <strong>{s.stato === 'determinata' && s.posizione ? `${s.posizione}ª scelta` : 'Posizione da determinare'}</strong>
                      <span className={`scelta-ticket__stato scelta-ticket__stato--${s.stato}`}>{s.stato === 'determinata' ? 'Pronta' : 'Posizione da determinare'}</span>
                    </div>
                  </div>
                </li>
              })}
            </ul>
          ) : <p className="season-empty">Nessuna scelta futura in portafoglio.</p>}
        </section>
      </>}

      {tab === 'rosa' && <section className="team-roster-panel">
        <div className="season-card__heading"><div><p className="kicker">Rosa completa</p><h2>Dal portiere all’attacco</h2></div><span>{players.length} giocatori · min {ROSA_MINIMA} · max {ROSA_MASSIMA}</span></div>
        {rosterNotice && <p className="notice notice--success">{rosterNotice}</p>}
        {rosterError && <p className="notice notice--error">{rosterError}</p>}
        {rosterLoading ? <p className="season-empty">Carico la rosa…</p> : <div className="team-roster-list">{players.map((player) => <button className={`team-roster-player team-roster-player--${department(player.posizioni[0])}`} type="button" key={player.id} onClick={() => openPlayer(player)} aria-label={`Scheda di ${player.nome}`}><i /><span className="team-roster-role">{player.posizioni[0] ?? '—'}</span><div><strong>{player.nome}</strong><small>{player.posizioni.join(' · ')} · {player.eta} anni · <em>{money(player.ingaggio)}/stagione</em> · <em className={contratto(player, league.stagione_corrente).urgente ? 'contratto-urgente' : 'contratto-residuo'}>{contratto(player, league.stagione_corrente).testo}</em></small></div><b>{player.overall}</b><dl><span>{player.minuti}<small>MIN</small></span><span>{player.gol}<small>GOL</small></span><span>{player.assist}<small>ASS</small></span></dl></button>)}</div>}
      </section>}

      {tab === 'vivaio' && <section className="team-roster-panel">
        <div className="season-card__heading">
          <div><p className="kicker">Settore giovanile</p><h2>Prospetti in cantera</h2></div>
          <span>{vivaioProspetti.length} / {vivaioSlotMassimi} slot</span>
        </div>
        <p className="field-help">
          Fuori dal conteggio rosa. {ownTeam ? 'Entro la fine dell’off-season devi promuoverli in prima squadra o torneranno sul mercato UNDER.' : 'Il potenziale mostrato è una fascia: si stringe salendo di livello VIVAIO.'}
        </p>
        {vivaioErrore && <p className="notice notice--error">{vivaioErrore}</p>}
        {vivaioLoading ? <p className="season-empty">Carico il vivaio…</p>
          : vivaioProspetti.length === 0 ? <p className="season-empty">Nessun prospetto in cantera.</p>
          : <div className="team-roster-list">
              {vivaioProspetti.map((prospetto) => {
                const g = prospetto.giocatore
                const inCorso = vivaioAzioneInCorso === prospetto.id
                return (
                  <div className={`team-roster-player team-roster-player--${department(g.posizioni[0])}`} key={prospetto.id}>
                    <i />
                    <span className="team-roster-role">{g.posizioni[0] ?? '—'}</span>
                    <div>
                      <strong>{g.nome}</strong>
                      <small>{g.posizioni.join(' · ')} · {g.eta} anni · <em>{money(prospetto.ingaggio)}/stagione</em> · potenziale {prospetto.potenziale_min === prospetto.potenziale_max ? prospetto.potenziale_min : `${prospetto.potenziale_min}-${prospetto.potenziale_max}`}</small>
                    </div>
                    <b>{g.overall}</b>
                    {ownTeam && <div className="vivaio-azioni">
                      <button className="button button--primary" type="button" disabled={inCorso} onClick={() => void promuovi(prospetto.id)}>
                        {inCorso ? '…' : 'Promuovi'}
                      </button>
                      <button className="button button--danger-ghost" type="button" disabled={inCorso} onClick={() => void rilascia(prospetto.id)}>
                        Rilascia
                      </button>
                    </div>}
                  </div>
                )
              })}
            </div>}
      </section>}

      {schedaAperta && <SchedaGiocatore
        giocatore={{
          nome: schedaAperta.nome,
          nazionalita: schedaAperta.nazionalita,
          posizioni: schedaAperta.posizioni,
          overall: schedaAperta.overall,
          eta: schedaAperta.eta,
          piede: schedaAperta.piede,
          altezza: schedaAperta.altezza,
          ingaggio: schedaAperta.ingaggio,
          condizione: schedaAperta.condizione,
          infortunatoFinoA: schedaAperta.infortunatoFinoA,
          squalificatoFinoA: schedaAperta.squalificatoFinoA,
          ritiroAnnunciato: schedaAperta.ritiroAnnunciato,
          morale: ownTeam ? schedaAperta.morale : undefined,
          contrattoScadenza: ownTeam ? schedaAperta.contrattoScadenza : undefined,
          stagioneCorrente: ownTeam ? league.stagione_corrente : undefined,
          mentalita: ownTeam ? schedaAperta.mentalita : undefined,
          attributi: schedaAperta.attributi,
        }}
        fotoUrl={fotoScheda}
        stagione={statsPerGiocatore.get(schedaAperta.id) ?? {
          presenze: 0, minuti: 0, gol: 0, assist: 0, porteInviolate: 0,
          tiri: 0, tiriPorta: 0, passaggiTentati: 0, passaggiRiusciti: 0, contrastiVinti: 0, dribbling: 0,
        }}
        azionePericolosa={ownTeam && league.stato === 'stagione' ? {
          etichetta: 'Svincola giocatore',
          descrizione: schedaAperta.ritiroAnnunciato
            ? `${schedaAperta.nome} ha già annunciato il ritiro: lo svincolo è definitivo, non tornerà disponibile per nessuna squadra. Non riceverai alcun rimborso e le formazioni future che lo contengono dovranno essere salvate di nuovo.`
            : (() => {
                const costo = buonuscita(schedaAperta, league.stagione_corrente)
                const base = `${schedaAperta.nome} uscirà subito dalla rosa. Devi mantenere almeno ${ROSA_MINIMA} giocatori. Le formazioni future che lo contengono dovranno essere salvate di nuovo.`
                return costo > 0
                  ? `${base} Ha ancora ${schedaAperta.contrattoScadenza - league.stagione_corrente} stagioni di contratto: per svincolarlo in anticipo dovrai pagargli una buonuscita di ${money(costo)}.`
                  : `${base} Non riceverai alcun rimborso.`
              })(),
          inCorso: releasePending,
          errore: releaseError,
          onConferma: releasePlayer,
        } : undefined}
        rinnovo={ownTeam && league.stato === 'stagione' && !schedaAperta.ritiroAnnunciato ? {
          nomeAllenatore: allenatore,
          bloccato: schedaAperta.rinnovoTentativi >= 3
            ? 'Non intende rinnovare: andrà a scadenza a fine stagione.'
            : schedaAperta.rinnovoStagione === league.stagione_corrente
              ? 'Ha già rinnovato in questa stagione: se ne riparla dalla prossima.'
              : undefined,
          onCarica: async () => {
            const { data, error } = await supabase.rpc('proposta_rinnovo', { p_instance_id: schedaAperta.id })
            if (error) throw new Error(error.message)
            return data as PropostaRinnovo
          },
          onOffri: async (ingaggio) => {
            const { data, error } = await supabase.rpc('offri_rinnovo', {
              p_instance_id: schedaAperta.id, p_ingaggio: ingaggio, p_durata: 1,
            })
            if (error) throw new Error(error.message)
            const risposta = data as EsitoRinnovo
            if (risposta.esito === 'accettato') {
              setPlayers((current) => current.map((item) => item.id === schedaAperta.id
                ? { ...item, ingaggio, contrattoScadenza: risposta.contratto_scadenza ?? item.contrattoScadenza, rinnovoStagione: league.stagione_corrente }
                : item))
            }
            return risposta
          },
        } : undefined}
        listaMercato={ownTeam && league.stato === 'stagione' ? {
          inLista: schedaAperta.sulMercato,
          onCambia: async (valore) => {
            const { error } = await supabase.rpc('imposta_sul_mercato', { p_instance_id: schedaAperta.id, p_valore: valore })
            if (error) throw new Error(error.message)
            setPlayers((current) => current.map((item) => item.id === schedaAperta.id ? { ...item, sulMercato: valore } : item))
          },
        } : undefined}
        cambioRuolo={ownTeam && league.stato === 'stagione' && !schedaAperta.ritiroAnnunciato ? {
          inCorso: (() => {
            const cambio = cambiRuolo.get(schedaAperta.id)
            return cambio ? { ruoloPrecedente: cambio.ruolo_precedente, ruoloTarget: cambio.ruolo_target, completaGiornata: cambio.completa_giornata } : null
          })(),
          prossimaGiornata,
          onCaricaTarget: () => caricaTargetCambioRuolo(schedaAperta.id),
          onAvvia: (ruoloTarget) => avviaCambioRuolo(schedaAperta.id, ruoloTarget),
          onAnnulla: () => annullaCambioRuolo(schedaAperta.id),
        } : undefined}
        specializzazione={ownTeam && league.stato === 'stagione' && !schedaAperta.ritiroAnnunciato ? {
          attiva: schedaAperta.specializzazioneAttiva
            ? specEtichette.get(schedaAperta.specializzazioneAttiva) ?? schedaAperta.specializzazioneAttiva
            : null,
          inCorso: (() => {
            const allenamento = specializzazioni.get(schedaAperta.id)
            if (!allenamento) return null
            return {
              specializzazionePrecedente: allenamento.specializzazione_precedente
                ? specEtichette.get(allenamento.specializzazione_precedente) ?? allenamento.specializzazione_precedente
                : null,
              specializzazioneTarget: specEtichette.get(allenamento.specializzazione_target) ?? allenamento.specializzazione_target,
              completaGiornata: allenamento.completa_giornata,
            }
          })(),
          prossimaGiornata,
          onCaricaOpzioni: () => caricaOpzioniSpecializzazione(schedaAperta.id),
          onAvvia: (specializzazione) => avviaSpecializzazione(schedaAperta.id, specializzazione),
          onAnnulla: () => annullaSpecializzazione(schedaAperta.id),
        } : undefined}
        onClose={() => setSchedaAperta(null)}
      />}
      </div>
    </>}
  </main>
}
