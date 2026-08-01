import '@supabase/functions-js/edge-runtime.d.ts'
import { withSupabase } from '@supabase/server'
import { schiera, simulaPartita } from '../../../engine/engine.js'
import { MODULI } from '../../../engine/config.js'
import { setSeed } from '../../../engine/random.js'

type JsonMap = Record<string, unknown>
type DbPlayer = { id: number; nome: string; posizioni: string[]; attributi: Record<string, number> }
type Instance = { id: number; team_id: number; player_id: number; overall_corrente: number; eta_corrente: number; condizione: number; infortunato_fino_a: number }
type EnginePlayer = { id: number; nome: string; posizioni: string[]; ovr: number; eta: number; stamina: number; finishing: number; short_passing: number; tackle: number; dribbling: number; gk: number; condizione: number; infortunatoFinoA: number }
type EngineRoster = { nome: string; giocatori: EnginePlayer[]; esperienzaModulo: Record<string, number> }
type DbLineup = { team_id: number; giornata?: number; modulo: string; titolari: number[]; panchina: number[]; tribuna: number[]; automatica: boolean }
type EngineLineup = { modulo: string; slots: string[]; titolari: EnginePlayer[]; panchina: EnginePlayer[]; cambiFatti: number }
type Fixture = { id: number; season_id: number; league_id: number; giornata: number; home_team_id: number; away_team_id: number; stato: string }

function requiredNumber(attributes: Record<string, number>, field: string, playerId: number) {
  const value = attributes[field]
  if (typeof value !== 'number' || !Number.isFinite(value)) {
    throw new Error(`Giocatore ${playerId}: attributo obbligatorio ${field} assente.`)
  }
  return value
}

function adaptPlayer(instance: Instance, player: DbPlayer): EnginePlayer {
  if (!player || !player.nome || !Array.isArray(player.posizioni) || player.posizioni.length === 0) {
    throw new Error(`Giocatore ${instance.id}: dati anagrafici o posizioni mancanti.`)
  }
  for (const [field, value] of Object.entries({
    ovr: instance.overall_corrente,
    eta: instance.eta_corrente,
    condizione: instance.condizione,
    infortunatoFinoA: instance.infortunato_fino_a,
  })) {
    if (typeof value !== 'number' || !Number.isFinite(value)) throw new Error(`Giocatore ${instance.id}: campo ${field} assente.`)
  }
  return {
    id: instance.id,
    nome: player.nome,
    posizioni: player.posizioni,
    ovr: instance.overall_corrente,
    eta: instance.eta_corrente,
    stamina: requiredNumber(player.attributi, 'stamina', instance.id),
    finishing: requiredNumber(player.attributi, 'finishing', instance.id),
    short_passing: requiredNumber(player.attributi, 'short_passing', instance.id),
    tackle: requiredNumber(player.attributi, 'standing_tackle', instance.id),
    dribbling: requiredNumber(player.attributi, 'dribbling', instance.id),
    gk: requiredNumber(player.attributi, 'gk', instance.id),
    condizione: instance.condizione,
    infortunatoFinoA: instance.infortunato_fino_a,
  }
}

function buildLineup(lineup: DbLineup, roster: EngineRoster): EngineLineup {
  const byId = new Map(roster.giocatori.map((player) => [player.id, player]))
  const slots = MODULI[lineup.modulo]
  if (!slots || slots.length !== 11 || lineup.titolari.length !== 11) throw new Error(`Formazione non valida per la squadra ${lineup.team_id}.`)
  const titolari = lineup.titolari.map((id) => byId.get(id))
  const panchina = lineup.panchina.map((id) => byId.get(id))
  if (titolari.some((player) => !player) || panchina.some((player) => !player)) throw new Error(`Formazione con giocatori fuori rosa per la squadra ${lineup.team_id}.`)
  return { modulo: lineup.modulo, slots: [...slots], titolari: titolari as EnginePlayer[], panchina: panchina as EnginePlayer[], cambiFatti: 0 }
}

function seedFor(fixture: Fixture) {
  const value = (BigInt(fixture.id) * 2654435761n + BigInt(fixture.season_id) * 1013904223n) % 4294967295n
  return Number(value || 1n)
}

function mapValue(map: Map<number, number> | undefined, id: number) {
  return map?.get(id) ?? 0
}

function playerStats(teamId: number, stats: JsonMap, teamStats: JsonMap) {
  const minuti = stats.minuti as Map<number, number>
  const tiri = stats.tiri as Map<number, number>
  const passaggi = stats.passaggi as Map<number, number>
  const contrasti = stats.contrasti as Map<number, number>
  const dribbling = stats.dribbling as Map<number, number>
  const marcatori = stats.marcatoriIds as number[]
  const goals = new Map<number, number>()
  for (const id of marcatori) goals.set(id, (goals.get(id) ?? 0) + 1)
  const shotsTotal = Number(teamStats.tiri ?? 0)
  const shotsOnTarget = Number(teamStats.inPorta ?? 0)
  const passPct = Number(teamStats.passaggiPct ?? 0)

  return [...minuti.entries()].map(([id, minutes]) => {
    const shots = mapValue(tiri, id)
    const passes = mapValue(passaggi, id)
    return {
      player_instance_id: id,
      team_id: teamId,
      minuti: Math.max(0, Math.min(90, minutes)),
      gol: goals.get(id) ?? 0,
      assist: 0,
      tiri: shots,
      tiri_porta: Math.min(shots, shotsTotal ? Math.round(shots * shotsOnTarget / shotsTotal) : 0),
      passaggi_tentati: passes,
      passaggi_riusciti: Math.min(passes, Math.round(passes * passPct)),
      contrasti_vinti: mapValue(contrasti, id),
      contrasti_persi: 0,
      dribbling: mapValue(dribbling, id),
    }
  })
}

export default {
  fetch: withSupabase({ auth: 'user' }, async (req, ctx) => {
    try {
      if (req.method !== 'POST') return Response.json({ error: 'Metodo non consentito.' }, { status: 405 })
      const body = await req.json().catch(() => ({})) as { league_id?: number; giornata?: number }
      const leagueId = Number(body.league_id)
      if (!Number.isInteger(leagueId) || leagueId < 1) return Response.json({ error: 'league_id non valido.' }, { status: 400 })

      const { data: league, error: leagueError } = await ctx.supabase.from('leagues')
        .select('id, nome, admin_id, stato').eq('id', leagueId).single()
      if (leagueError || !league) return Response.json({ error: 'Lega non trovata.' }, { status: 404 })
      if (league.admin_id !== ctx.userClaims?.id) return Response.json({ error: 'Solo l’amministratore può simulare una giornata.' }, { status: 403 })
      if (league.stato !== 'stagione') return Response.json({ error: 'La stagione non è in corso.' }, { status: 409 })

      const { data: firstFixture, error: firstError } = await ctx.supabaseAdmin.from('fixtures')
        .select('giornata').eq('league_id', leagueId).eq('stato', 'programmata').order('giornata').limit(1).maybeSingle()
      if (firstError) throw firstError
      if (!firstFixture) return Response.json({ league_id: leagueId, completata: true, partite: [] })
      if (body.giornata && body.giornata !== firstFixture.giornata) {
        return Response.json({ error: `La prossima giornata simulabile è la ${firstFixture.giornata}.` }, { status: 409 })
      }
      const giornata = firstFixture.giornata

      const { data: fixtureRows, error: fixturesError } = await ctx.supabaseAdmin.from('fixtures')
        .select('*').eq('league_id', leagueId).eq('giornata', giornata).eq('stato', 'programmata').order('id')
      if (fixturesError) throw fixturesError
      const fixtures = (fixtureRows ?? []) as Fixture[]
      const teamIds = [...new Set(fixtures.flatMap((fixture) => [fixture.home_team_id, fixture.away_team_id]))]

      const [teamsResult, instancesResult, lineupsResult, previousLineupsResult, xpResult] = await Promise.all([
        ctx.supabaseAdmin.from('teams').select('id, nome').eq('league_id', leagueId).in('id', teamIds),
        ctx.supabaseAdmin.from('player_instances').select('id, team_id, player_id, overall_corrente, eta_corrente, condizione, infortunato_fino_a').eq('league_id', leagueId).in('team_id', teamIds),
        ctx.supabaseAdmin.from('lineups').select('team_id, modulo, titolari, panchina, tribuna, automatica').eq('league_id', leagueId).eq('giornata', giornata).in('team_id', teamIds),
        ctx.supabaseAdmin.from('lineups').select('team_id, giornata, modulo, titolari, panchina, tribuna, automatica').eq('league_id', leagueId).lt('giornata', giornata).in('team_id', teamIds).order('automatica', { ascending: true }).order('giornata', { ascending: false }),
        ctx.supabaseAdmin.from('formation_xp').select('team_id, modulo, partite_giocate').eq('league_id', leagueId).in('team_id', teamIds),
      ])
      const loadError = teamsResult.error ?? instancesResult.error ?? lineupsResult.error ?? previousLineupsResult.error ?? xpResult.error
      if (loadError) throw loadError

      const instances = (instancesResult.data ?? []) as Instance[]
      const playerIds = [...new Set(instances.map((instance) => instance.player_id))]
      const { data: playersData, error: playersError } = await ctx.supabaseAdmin.from('players')
        .select('id, nome, posizioni, attributi').in('id', playerIds)
      if (playersError) throw playersError
      const catalog = new Map((playersData ?? []).map((player) => [player.id, player as DbPlayer]))
      const teamNames = new Map((teamsResult.data ?? []).map((team) => [team.id, team.nome]))
      const rosters = new Map<number, EngineRoster>()

      for (const teamId of teamIds) {
        const esperienzaModulo: Record<string, number> = {}
        for (const xp of xpResult.data ?? []) if (xp.team_id === teamId) esperienzaModulo[xp.modulo] = xp.partite_giocate
        rosters.set(teamId, {
          nome: teamNames.get(teamId) ?? `Squadra ${teamId}`,
          giocatori: instances.filter((instance) => instance.team_id === teamId).map((instance) => adaptPlayer(instance, catalog.get(instance.player_id)!)),
          esperienzaModulo,
        })
      }

      const lineups = new Map<number, DbLineup>((lineupsResult.data ?? []).map((lineup) => [lineup.team_id, lineup as DbLineup]))
      const inheritedLineups = new Map<number, DbLineup>()
      for (const lineup of previousLineupsResult.data ?? []) {
        if (!inheritedLineups.has(lineup.team_id)) inheritedLineups.set(lineup.team_id, lineup as DbLineup)
      }
      for (const teamId of teamIds) {
        if (lineups.has(teamId)) continue
        const roster = rosters.get(teamId)!
        const inherited = inheritedLineups.get(teamId)
        let fallback: DbLineup
        if (inherited) {
          fallback = { team_id: teamId, modulo: inherited.modulo, titolari: inherited.titolari, panchina: inherited.panchina, tribuna: inherited.tribuna, automatica: true }
        } else {
          const automatic = schiera(roster, '4-3-3')
          const starters = automatic.titolari.map((player: EnginePlayer) => player.id)
          const bench = automatic.panchina.map((player: EnginePlayer) => player.id)
          const tribuna = roster.giocatori.filter((player) => !starters.includes(player.id) && !bench.includes(player.id)).map((player) => player.id)
          fallback = { team_id: teamId, modulo: '4-3-3', titolari: starters, panchina: bench, tribuna, automatica: true }
        }
        const { error: lineupError } = await ctx.supabaseAdmin.from('lineups').insert({ league_id: leagueId, giornata, ...fallback })
        if (lineupError) throw lineupError
        lineups.set(teamId, fallback)
      }

      const summaries = []
      for (const fixture of fixtures) {
        const homeRoster = rosters.get(fixture.home_team_id)!
        const awayRoster = rosters.get(fixture.away_team_id)!
        const homeDbLineup = lineups.get(fixture.home_team_id)!
        const awayDbLineup = lineups.get(fixture.away_team_id)!
        const homeLineup = buildLineup(homeDbLineup, homeRoster)
        const awayLineup = buildLineup(awayDbLineup, awayRoster)
        const seed = seedFor(fixture)
        setSeed(seed)
        const result = simulaPartita(homeRoster, awayRoster, homeDbLineup.modulo, awayDbLineup.modulo, {
          usaCondizione: false,
          statsGiocatori: true,
          lineupCasa: homeLineup,
          lineupOspite: awayLineup,
        })
        const stats = [
          ...playerStats(fixture.home_team_id, result.perGiocatore.casa, result.statsCasa),
          ...playerStats(fixture.away_team_id, result.perGiocatore.ospite, result.statsOspite),
        ]
        const { data: saved, error: saveError } = await ctx.supabaseAdmin.rpc('registra_risultato_partita', {
          p_fixture_id: fixture.id,
          p_seed: seed,
          p_modulo_home: homeDbLineup.modulo,
          p_modulo_away: awayDbLineup.modulo,
          p_gol_home: result.golC,
          p_gol_away: result.golO,
          p_blocchi: [],
          p_stats_squadra: { home: result.statsCasa, away: result.statsOspite },
          p_player_stats: stats,
        })
        if (saveError) throw saveError
        summaries.push(saved)
      }

      return Response.json({ league_id: leagueId, giornata, partite: summaries })
    } catch (error) {
      console.error(error)
      return Response.json({ error: error instanceof Error ? error.message : 'Errore durante la simulazione.' }, { status: 500 })
    }
  }),
}
