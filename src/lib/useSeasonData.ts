import { useCallback, useEffect, useMemo, useState } from 'react'
import { supabase } from './supabase'
import type { Fixture, Match, Membership, Season, Standing, Team } from '../types'
import { firmaStemma } from './stemmiFirmati'

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

  const load = useCallback(async () => {
    setLoading(true)
    setError(null)

    const [seasonResult, teamsResult] = await Promise.all([
      supabase.from('seasons').select('*').eq('league_id', league.id).eq('numero', league.stagione_corrente).maybeSingle(),
      supabase.from('teams').select('*').eq('league_id', league.id).order('nome'),
    ])

    if (seasonResult.error || teamsResult.error) {
      setError(seasonResult.error?.message ?? teamsResult.error?.message ?? 'Dati della stagione non disponibili.')
      setLoading(false)
      return
    }

    const currentSeason = seasonResult.data as Season | null
    setSeason(currentSeason)
    const loadedTeams = (teamsResult.data ?? []) as Team[]
    setTeams(loadedTeams)
    const signedCrests = await Promise.all(loadedTeams.filter((team) => team.stemma_url && !team.stemma_url.startsWith('preset:')).map(async (team) => {
      const { data } = await firmaStemma(team.stemma_url!)
      return [team.id, data?.signedUrl] as const
    }))
    setCrestUrls(Object.fromEntries(signedCrests.filter((entry): entry is readonly [number, string] => Boolean(entry[1]))))

    if (!currentSeason) {
      setFixtures([])
      setMatches([])
      setStandings([])
      setLoading(false)
      return
    }

    const [fixturesResult, matchesResult, standingsResult] = await Promise.all([
      supabase.from('fixtures').select('*').eq('league_id', league.id).eq('season_id', currentSeason.id).order('giornata').order('id'),
      // Solo le partite della stagione corrente: le fixtures caricate sono solo queste, e le partite di
      // tutte le stagioni passate (con i blocchi della cronaca) crescevano di peso a ogni stagione.
      supabase.from('matches').select('id, fixture_id, league_id, gol_home, gol_away, modulo_home, modulo_away, titolari_home, titolari_away, stats_squadra, blocchi, simulata_il, gol_home_90, gol_away_90, rigori_home, rigori_away, rigori_serie, fixtures!inner(season_id)').eq('league_id', league.id).eq('fixtures.season_id', currentSeason.id).order('simulata_il', { ascending: false }),
      supabase.from('standings').select('*').eq('league_id', league.id).eq('season_id', currentSeason.id),
    ])

    // Rete di sicurezza: se per qualunque motivo il filtro per stagione non funziona, si torna alla
    // lettura completa di prima invece di lasciare l'app senza partite.
    if (matchesResult.error) {
      const ripiego = await supabase.from('matches').select('id, fixture_id, league_id, gol_home, gol_away, modulo_home, modulo_away, titolari_home, titolari_away, stats_squadra, blocchi, simulata_il, gol_home_90, gol_away_90, rigori_home, rigori_away, rigori_serie').eq('league_id', league.id).order('simulata_il', { ascending: false })
      matchesResult.data = ripiego.data as typeof matchesResult.data
      matchesResult.error = ripiego.error as typeof matchesResult.error
    }

    const firstError = fixturesResult.error ?? matchesResult.error ?? standingsResult.error
    if (firstError) {
      setError(firstError.message)
      setLoading(false)
      return
    }

    setFixtures((fixturesResult.data ?? []) as Fixture[])
    setMatches((matchesResult.data ?? []) as Match[])
    setStandings((standingsResult.data ?? []) as Standing[])
    setLoading(false)
  }, [league.id, league.stagione_corrente])

  useEffect(() => { void load() }, [load])

  // Alla scadenza di una partita il server puo' impiegare qualche secondo a
  // simulare il turno e a fissare quello successivo. Ricarichiamo solo in
  // quel breve intervallo: il countdown resta allineato al dato autorevole.
  useEffect(() => {
    const prossima = fixtures.find((fixture) => fixture.stato === 'programmata')
    if (!prossima) return
    const scadenza = new Date(prossima.data_sim).getTime()
    if (Date.now() < scadenza) return
    const timer = window.setInterval(() => { void load() }, 15_000)
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
    currentGiornata, nextFixture, lastFixture, giornateStagione, loading, error, reload: load,
  }
}
