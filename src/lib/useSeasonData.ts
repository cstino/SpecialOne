import { useCallback, useEffect, useMemo, useState } from 'react'
import { supabase } from './supabase'
import { firmaStemma } from './stemmiFirmati'
import type { Fixture, Match, Membership, Season, Standing, Team } from '../types'

// Colonne leggere delle partite: senza la cronaca (blocchi), le statistiche di squadra e la serie dei rigori, che
// pesano quasi tutto e servono solo aprendo UNA partita (usePartitaCompleta). Le partite dell'ultima giornata le
// hanno comunque, per le notizie della home.
const COLONNE_LEGGERE = 'id, fixture_id, league_id, gol_home, gol_away, modulo_home, modulo_away, titolari_home, titolari_away, simulata_il, gol_home_90, gol_away_90, rigori_home, rigori_away'
const COLONNE_PESANTI = 'id, blocchi, stats_squadra, rigori_serie'

type Istantanea = {
  season: Season | null; teams: Team[]; crestUrls: Record<number, string>
  fixtures: Fixture[]; matches: Match[]; standings: Standing[]
}
// Una sola copia dei dati di stagione per lega, condivisa da tutte le pagine aperte (home, partita, intro, rapporto,
// Scambi...): prima ognuna li riscaricava, e aprire un risultato dalla home li chiedeva due o tre volte.
// Si riusa per FRESCHEZZA_MS; "Riprova" e il ricarico dopo la simulazione vanno sempre al database.
const FRESCHEZZA_MS = 60_000
const istantanee = new Map<string, { quando: number; dati: Istantanea }>()
const inCorso = new Map<string, Promise<Istantanea>>()

async function scarica(leagueId: number, stagione: number): Promise<Istantanea> {
  const [seasonResult, teamsResult] = await Promise.all([
    supabase.from('seasons').select('*').eq('league_id', leagueId).eq('numero', stagione).maybeSingle(),
    supabase.from('teams').select('*').eq('league_id', leagueId).order('nome'),
  ])
  if (seasonResult.error || teamsResult.error) throw new Error(seasonResult.error?.message ?? teamsResult.error?.message ?? 'Dati della stagione non disponibili.')
  const season = seasonResult.data as Season | null
  const teams = (teamsResult.data ?? []) as Team[]
  const signedCrests = await Promise.all(teams.filter((team) => team.stemma_url && !team.stemma_url.startsWith('preset:')).map(async (team) => {
    const { data } = await firmaStemma(team.stemma_url!)
    return [team.id, data?.signedUrl] as const
  }))
  const crestUrls = Object.fromEntries(signedCrests.filter((entry): entry is readonly [number, string] => Boolean(entry[1])))
  if (!season) return { season, teams, crestUrls, fixtures: [], matches: [], standings: [] }

  const [fixturesResult, matchesResultIniziale, standingsResult] = await Promise.all([
    supabase.from('fixtures').select('*').eq('league_id', leagueId).eq('season_id', season.id).order('giornata').order('id'),
    // Solo le partite della stagione corrente: le fixtures caricate sono solo queste.
    supabase.from('matches').select(`${COLONNE_LEGGERE}, fixtures!inner(season_id)`).eq('league_id', leagueId).eq('fixtures.season_id', season.id).order('simulata_il', { ascending: false }),
    supabase.from('standings').select('*').eq('league_id', leagueId).eq('season_id', season.id),
  ])
  let matchesResult = matchesResultIniziale
  // Rete di sicurezza: se il filtro per stagione non funziona si torna alla lettura completa.
  if (matchesResult.error) matchesResult = await supabase.from('matches').select(COLONNE_LEGGERE).eq('league_id', leagueId).order('simulata_il', { ascending: false }) as typeof matchesResult
  const firstError = fixturesResult.error ?? matchesResult.error ?? standingsResult.error
  if (firstError) throw new Error(firstError.message)
  const fixtures = (fixturesResult.data ?? []) as Fixture[]
  const leggere = (matchesResult.data ?? []).map((riga) => ({ ...(riga as object), blocchi: [], stats_squadra: { home: {}, away: {} }, rigori_serie: null })) as unknown as Match[]

  // La cronaca completa solo per le partite dell'ultima giornata giocata (le notizie della home la raccontano).
  const giornataPerFixture = new Map(fixtures.map((f) => [f.id, f.giornata]))
  const ultima = Math.max(0, ...leggere.map((m) => giornataPerFixture.get(m.fixture_id) ?? 0))
  const idsUltima = leggere.filter((m) => giornataPerFixture.get(m.fixture_id) === ultima).map((m) => m.id)
  if (idsUltima.length) {
    const { data: pesanti } = await supabase.from('matches').select(COLONNE_PESANTI).in('id', idsUltima)
    const perId = new Map((pesanti ?? []).map((riga) => [riga.id as number, riga]))
    for (const m of leggere) {
      const p = perId.get(m.id)
      if (p) Object.assign(m, { blocchi: p.blocchi ?? [], stats_squadra: p.stats_squadra ?? m.stats_squadra, rigori_serie: p.rigori_serie ?? null })
    }
  }
  return { season, teams, crestUrls, fixtures, matches: leggere, standings: (standingsResult.data ?? []) as Standing[] }
}

function caricaCondiviso(leagueId: number, stagione: number, forza: boolean): Promise<Istantanea> {
  const chiave = `${leagueId}:${stagione}`
  const nota = istantanee.get(chiave)
  if (!forza && nota && Date.now() - nota.quando < FRESCHEZZA_MS) return Promise.resolve(nota.dati)
  const attesa = inCorso.get(chiave)
  if (attesa) return attesa
  const promessa = scarica(leagueId, stagione)
    .then((dati) => { istantanee.set(chiave, { quando: Date.now(), dati }); return dati })
    .finally(() => inCorso.delete(chiave))
  inCorso.set(chiave, promessa)
  return promessa
}

// Una partita con tutto (cronaca, statistiche di squadra, rigori): la chiede solo chi apre quella partita.
export function usePartitaCompleta(matchId: number) {
  // undefined = si sta caricando; null = non trovata.
  const [partita, setPartita] = useState<Match | null | undefined>(undefined)
  useEffect(() => {
    let vivo = true
    setPartita(undefined)
    void supabase.from('matches').select(`${COLONNE_LEGGERE}, ${COLONNE_PESANTI.replace('id, ', '')}`).eq('id', matchId).maybeSingle()
      .then(({ data }) => { if (vivo) setPartita(data ? data as unknown as Match : null) })
    return () => { vivo = false }
  }, [matchId])
  return partita
}

export function useSeasonData(membership: Membership) {
  const league = membership.league!
  const [season, setSeason] = useState<Season | null>(null)
  const [teams, setTeams] = useState<Team[]>([])
  const [fixtures, setFixtures] = useState<Fixture[]>([])
  const [matches, setMatches] = useState<Match[]>([])
  const [standings, setStandings] = useState<Standing[]>([])
  const [crestUrls, setCrestUrls] = useState<Record<number, string>>({})
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const load = useCallback(async (forza = false) => {
    setLoading(true)
    setError(null)
    try {
      const dati = await caricaCondiviso(league.id, league.stagione_corrente, forza)
      setSeason(dati.season); setTeams(dati.teams); setCrestUrls(dati.crestUrls)
      setFixtures(dati.fixtures); setMatches(dati.matches); setStandings(dati.standings)
    } catch (errore) {
      setError(errore instanceof Error ? errore.message : 'Dati della stagione non disponibili.')
    }
    setLoading(false)
  }, [league.id, league.stagione_corrente])
  const reload = useCallback(() => load(true), [load])

  useEffect(() => { void load() }, [load])

  // Alla scadenza di una partita il server puo' impiegare qualche secondo a
  // simulare il turno e a fissare quello successivo. Ricarichiamo solo in
  // quel breve intervallo: il countdown resta allineato al dato autorevole.
  useEffect(() => {
    const prossima = fixtures.find((fixture) => fixture.stato === 'programmata')
    if (!prossima) return
    const scadenza = new Date(prossima.data_sim).getTime()
    if (Date.now() < scadenza) return
    const timer = window.setInterval(() => { void load(true) }, 15_000)
    return () => window.clearInterval(timer)
  }, [fixtures, load])

  const teamById = useMemo(() => new Map(teams.map((team) => [team.id, team])), [teams])
  const crestUrlByTeamId = useMemo(() => new Map(Object.entries(crestUrls).map(([id, url]) => [Number(id), url])), [crestUrls])
  const matchByFixture = useMemo(() => new Map(matches.map((match) => [match.fixture_id, match])), [matches])
  const currentGiornata = fixtures.find((fixture) => fixture.stato === 'programmata' || fixture.stato === 'in_corso')?.giornata
    ?? Math.max(1, ...fixtures.map((fixture) => fixture.giornata))
  const nextFixture = fixtures.find((fixture) =>
    (fixture.home_team_id === membership.id || fixture.away_team_id === membership.id)
    && (fixture.stato === 'programmata' || fixture.stato === 'in_corso')) ?? null
  const lastFixture = [...fixtures].reverse().find((fixture) =>
    (fixture.home_team_id === membership.id || fixture.away_team_id === membership.id)
    && fixture.stato === 'simulata') ?? null
  const orderedStandings = [...standings].sort((left, right) =>
    (left.posizione ?? 999) - (right.posizione ?? 999)
    || right.punti - left.punti
    || right.differenza_reti - left.differenza_reti
    || right.gol_fatti - left.gol_fatti
    || (teamById.get(left.team_id)?.nome ?? '').localeCompare(teamById.get(right.team_id)?.nome ?? '', 'it')
  )

  // Quante giornate ha DAVVERO questa stagione. league.giornate_totali e' una
  // colonna generata da squadre e gironi: cambia quando l'admin aggiunge una
  // squadra, anche per le stagioni gia' concluse, e faceva comparire cose come
  // "giornata 21 di 33" su un campionato finito alla 21a. La stagione se lo
  // porta dietro da quando e' nato il calendario; le fixtures sono il ripiego
  // per le stagioni piu' vecchie del backfill.
  const giornateStagione = season?.giornate_totali
    ?? (fixtures.length
      ? Math.max(...fixtures.filter((f) => f.bracket_tie_id == null).map((f) => f.giornata))
      : league.giornate_totali)

  return {
    season, teams, teamById, crestUrlByTeamId, fixtures, matches, matchByFixture, standings: orderedStandings,
    currentGiornata, nextFixture, lastFixture, giornateStagione, loading, error, reload,
  }
}
