import '@supabase/functions-js/edge-runtime.d.ts'
import { withSupabase } from '@supabase/server'
import { ovrEfficace, schiera, simulaPartita } from '../../../engine/engine.js'
import { MODULI } from '../../../engine/config.js'
import { setSeed } from '../../../engine/random.js'

// La chiave segreta del progetto, esposta con un nome non riservato: la
// piattaforma non inietta SUPABASE_SECRET_KEY e vieta di crearla a mano.
// Serve per due cose insieme, ed e' la stessa mappa: autenticare il cron
// (header `apikey`) e costruire il client amministrativo.
const CHIAVE_SEGRETA = Deno.env.get('CHIAVE_SEGRETA_PROGETTO') ?? ''

type JsonMap = Record<string, unknown>
type GolBlocco = { blocco: number; casa: number; ospite: number }
type EventoGol = { minuto: number; blocco: number; lato: 'casa' | 'ospite'; team_id: number; marcatore: number; assist: number | null }
type DbPlayer = { id: number; nome: string; posizioni: string[]; attributi: Record<string, number> }
type Instance = { id: number; team_id: number; player_id: number; overall_corrente: number; eta_corrente: number; condizione: number; infortunato_fino_a: number }
type EnginePlayer = { id: number; nome: string; posizioni: string[]; ovr: number; eta: number; stamina: number; finishing: number; short_passing: number; tackle: number; dribbling: number; gk: number; condizione: number; infortunatoFinoA: number }
type EngineRoster = { nome: string; giocatori: EnginePlayer[]; esperienzaModulo: Record<string, number> }
type DbLineup = { team_id: number; giornata?: number; modulo: string; titolari: number[]; panchina: number[]; tribuna: number[]; stile_gioco: string; automatica: boolean }
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
  // Un giocatore puo' sparire dalla rosa DOPO che la formazione e' stata
  // salvata: il mercato chiude alle 21:00 e la formazione salvata prima (o
  // ereditata dalla giornata precedente) resta li' con dentro un ceduto.
  //
  // Prima qui c'era un throw. Siccome l'errore risale fino al gestore esterno,
  // UNA sola formazione stantia avrebbe fatto fallire la giornata dell'intera
  // lega. Un ceduto va trattato come un indisponibile qualsiasi.
  const titolari = lineup.titolari.map((id) => byId.get(id))
  const riserveSalvate = lineup.panchina
    .map((id) => byId.get(id))
    .filter((giocatore): giocatore is EnginePlayer => Boolean(giocatore))

  // Stessa logica per gli infortunati: `schiera()` scarta gli indisponibili,
  // ma qui la formazione arriva dal database e il motore controlla gli
  // infortuni solo a fine partita, quindi senza questo blocco un infortunato
  // scenderebbe in campo.
  const undici: Array<EnginePlayer | undefined> = titolari
  const rimpiazzi: Array<{ esce: string; entra: string }> = []
  for (let i = 0; i < undici.length; i++) {
    const attuale = undici[i]
    if (attuale && attuale.infortunatoFinoA <= 0) continue
    const inCampo = new Set(undici.filter(Boolean).map((giocatore) => giocatore!.id))
    const candidati = [...riserveSalvate, ...roster.giocatori]
      .filter((giocatore) => giocatore.infortunatoFinoA <= 0 && !inCampo.has(giocatore.id))
    if (candidati.length === 0) continue
    let migliore = candidati[0]
    for (const candidato of candidati) {
      if (ovrEfficace(candidato, slots[i]) > ovrEfficace(migliore, slots[i])) migliore = candidato
    }
    rimpiazzi.push({ esce: attuale ? attuale.nome : 'giocatore non piu’ in rosa', entra: migliore.nome })
    undici[i] = migliore
  }
  // Restare senza undici e' l'unico caso che resta irrecuperabile: il motore
  // non sa giocare in dieci dal primo minuto.
  if (undici.some((giocatore) => !giocatore)) {
    throw new Error(`Rosa insufficiente per completare la formazione della squadra ${lineup.team_id}.`)
  }
  if (rimpiazzi.length) {
    console.log(`Squadra ${lineup.team_id}: rimpiazzati indisponibili`, rimpiazzi)
  }

  const formazione = undici as EnginePlayer[]
  const inCampo = new Set(formazione.map((giocatore) => giocatore.id))
  const panchina: EnginePlayer[] = []
  const inPanchina = new Set<number>()
  const aggiungiInPanchina = (giocatore: EnginePlayer) => {
    if (panchina.length >= 9 || giocatore.infortunatoFinoA > 0 || inCampo.has(giocatore.id) || inPanchina.has(giocatore.id)) return
    panchina.push(giocatore)
    inPanchina.add(giocatore.id)
  }
  // Conserva le riserve sane scelte dall'allenatore e completa gli eventuali
  // buchi con i migliori giocatori disponibili della rosa.
  riserveSalvate.forEach(aggiungiInPanchina)
  const miglioriDisponibili = [...roster.giocatori].sort((a, b) => b.ovr - a.ovr)
  miglioriDisponibili.forEach(aggiungiInPanchina)

  return { modulo: lineup.modulo, slots: [...slots], titolari: formazione, panchina, cambiFatti: 0 }
}

function seedFor(fixture: Fixture) {
  const value = (BigInt(fixture.id) * 2654435761n + BigInt(fixture.season_id) * 1013904223n) % 4294967295n
  return Number(value || 1n)
}

function mapValue(map: Map<number, number> | undefined, id: number) {
  return map?.get(id) ?? 0
}

// ============================================================
//  DURATA DEGLI INFORTUNI
//
//  Il motore sorteggia 1-2, 3-6 oppure 8-15 giornate, tarato su una stagione
//  da 28 partite (la configurazione della validazione di Fase 0). In un
//  campionato da 14 giornate un 8-15 significa perdere il giocatore fino alla
//  fine: non e' una scelta tattica, e' una condanna.
//
//  Scaliamo la durata sulla lunghezza vera della stagione, con un tetto al 40%
//  delle giornate totali. Si tocca solo qui: le formule del motore restano
//  intatte, come impone CLAUDE.md §4.
// ============================================================

const GIORNATE_DI_TARATURA = 28

function scalaInfortunio(giornateOriginali: number, giornateTotali: number) {
  if (giornateOriginali <= 0 || giornateTotali <= 0) return giornateOriginali
  const scalato = Math.round(giornateOriginali * giornateTotali / GIORNATE_DI_TARATURA)
  const tetto = Math.max(1, Math.ceil(giornateTotali * 0.4))
  return Math.max(1, Math.min(scalato, tetto))
}

// ============================================================
//  MINUTI E ASSIST
//
//  Il motore decide i gol e i marcatori (chi segna, in totale); non modella
//  ne' il minuto esatto ne' l'ultimo passaggio. Minuto e assist sono quindi
//  un'attribuzione di presentazione, calcolata qui e non nell'engine: cosi'
//  il motore validato resta intatto e il suo stream RNG non viene consumato.
//  L'RNG e' lo stesso LCG di engine/random.js, ma con stato locale e seme
//  derivato da quello della partita: gli assist sono riproducibili quanto
//  il risultato.
//
//  Correzione del 4 agosto 2026 (segnalazione utente, lega reale): un
//  giocatore subentrato a partita in corso poteva risultare marcatore o
//  assistman di un gol caduto in un blocco precedente al suo ingresso —
//  il motore restituisce i marcatori come lista aggregata di fine partita,
//  senza legame col blocco, quindi l'abbinamento a un blocco specifico era
//  del tutto arbitrario. Ora l'engine espone anche `presenzePerBlocco` (chi
//  era davvero in campo in ciascun blocco) e l'abbinamento sceglie, fra i
//  marcatori rimasti, chi era presente in quel blocco. Il totale di gol e
//  assist per giocatore a fine partita resta identico a quello del motore:
//  cambia solo in quale blocco viene mostrato ciascuna occorrenza.
// ============================================================

const MINUTI_PER_BLOCCO = 15
const QUOTA_GOL_SENZA_ASSIST = 0.28 // rigori, tiri da fuori, ribattute, azioni personali

// Propensione all'assist per slot. Non deriva da PESI_STAT.passaggi, che misura
// il volume di passaggi: userebbe i centrali difensivi come uomini assist.
const PESO_ASSIST: Record<string, number> = {
  GK: 0.02,
  CB: 0.15, LB: 0.75, RB: 0.75, LWB: 0.90, RWB: 0.90,
  CDM: 0.50, CM: 0.95, CAM: 1.60, LM: 1.20, RM: 1.20,
  LW: 1.70, RW: 1.70, ST: 1.00, CF: 1.10,
}

function creaRng(seme: number) {
  let stato = seme % 4294967296
  return () => {
    stato = (stato * 1664525 + 1013904223) % 4294967296
    return stato / 4294967296
  }
}

function scegliPesatoLocale<T>(items: T[], pesi: number[], rnd: () => number): T {
  const totale = pesi.reduce((somma, peso) => somma + peso, 0)
  if (totale <= 0) return items[Math.floor(rnd() * items.length)]
  let resto = rnd() * totale
  for (let i = 0; i < items.length; i++) {
    resto -= pesi[i]
    if (resto <= 0) return items[i]
  }
  return items[items.length - 1]
}

// Sceglie l'uomo assist fra i titolari presenti in campo in quel blocco,
// escluso il marcatore. Senza il filtro di presenza un giocatore subentrato
// solo dopo poteva risultare assistman di un gol segnato prima del suo ingresso.
function scegliAssist(lineup: EngineLineup, marcatore: number, presenti: number[], rnd: () => number): number | null {
  if (rnd() < QUOTA_GOL_SENZA_ASSIST) return null
  const candidati: number[] = []
  const pesi: number[] = []
  for (let i = 0; i < lineup.slots.length; i++) {
    const giocatore = lineup.titolari[i]
    if (!giocatore || giocatore.id === marcatore) continue
    if (!presenti.includes(giocatore.id)) continue
    candidati.push(giocatore.id)
    pesi.push((PESO_ASSIST[lineup.slots[i]] ?? 0.5) * (giocatore.short_passing / 100))
  }
  if (candidati.length === 0) return null
  return scegliPesatoLocale(candidati, pesi, rnd)
}

// Trasforma i gol per blocco in eventi cronologici con minuto, marcatore e assist.
function costruisciEventiGol(
  golPerBlocco: GolBlocco[],
  lati: Array<{ lato: 'casa' | 'ospite'; teamId: number; lineup: EngineLineup; marcatori: number[]; presenzePerBlocco: number[][] }>,
  seed: number,
): EventoGol[] {
  const rnd = creaRng(seed)
  const eventi: EventoGol[] = []

  for (const blocco of golPerBlocco) {
    for (const lato of lati) {
      const quanti = lato.lato === 'casa' ? blocco.casa : blocco.ospite
      for (let g = 0; g < quanti; g++) {
        const minutoBase = (blocco.blocco - 1) * MINUTI_PER_BLOCCO
        eventi.push({
          minuto: minutoBase + 1 + Math.floor(rnd() * MINUTI_PER_BLOCCO),
          blocco: blocco.blocco,
          lato: lato.lato,
          team_id: lato.teamId,
          marcatore: 0,
          assist: null,
        })
      }
    }
  }

  eventi.sort((sinistra, destra) => sinistra.minuto - destra.minuto || sinistra.blocco - destra.blocco)

  // I marcatori arrivano dal motore come lista per squadra, senza legame con il
  // blocco: il totale a fine partita e' gia' deciso dal motore (validato) e non
  // cambia qui. Scegliamo pero' CHI, fra i marcatori rimasti, viene assegnato a
  // QUESTO blocco preferendo chi era davvero in campo in quel momento — un
  // subentrato non puo' risultare marcatore di un gol segnato prima del suo
  // ingresso. Se per caso nessuno dei rimasti era presente in quel blocco
  // (evento raro), si ripiega sul primo rimasto pur di non perdere il gol: il
  // totale per giocatore a fine partita resta comunque quello del motore,
  // cambia solo in quale blocco viene mostrato.
  const rimasti = new Map<string, number[]>()
  for (const lato of lati) rimasti.set(lato.lato, [...lato.marcatori])

  for (const evento of eventi) {
    const lato = lati.find((item) => item.lato === evento.lato)!
    const pool = rimasti.get(evento.lato)!
    const presenti = lato.presenzePerBlocco[evento.blocco - 1] ?? []
    let indice = pool.findIndex((id) => presenti.includes(id))
    if (indice === -1) indice = 0
    const marcatore = pool.splice(indice, 1)[0]
    if (marcatore === undefined) continue
    evento.marcatore = marcatore
    evento.assist = scegliAssist(lato.lineup, marcatore, presenti, rnd)
  }

  return eventi.filter((evento) => evento.marcatore !== 0)
}

function playerStats(teamId: number, stats: JsonMap, teamStats: JsonMap, assist: Map<number, number>) {
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
      assist: assist.get(id) ?? 0,
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
  // Due chiamanti: l'amministratore dal browser (JWT utente) e il cron
  // notturno, che presenta la chiave segreta del progetto nell'header `apikey`.
  fetch: withSupabase({
    auth: ['user', 'secret'],
    env: { secretKeys: CHIAVE_SEGRETA ? { default: CHIAVE_SEGRETA } : {} },
  }, async (req, ctx) => {
    try {
      if (req.method !== 'POST') return Response.json({ error: 'Metodo non consentito.' }, { status: 405 })
      const body = await req.json().catch(() => ({})) as { league_id?: number; giornata?: number }
      const leagueId = Number(body.league_id)
      if (!Number.isInteger(leagueId) || leagueId < 1) return Response.json({ error: 'league_id non valido.' }, { status: 400 })

      // Lettura con il client amministrativo, come tutto il resto della
      // funzione: in modalita' segreta `ctx.supabase` porta la chiave del cron,
      // che PostgREST non riconosce. Il controllo sull'admin resta esplicito.
      const chiamataDiSistema = ctx.authMode === 'secret'
      const { data: league, error: leagueError } = await ctx.supabaseAdmin.from('leagues')
        .select('id, nome, admin_id, stato, giornate_totali').eq('id', leagueId).single()
      if (leagueError || !league) return Response.json({ error: 'Lega non trovata.' }, { status: 404 })
      if (!chiamataDiSistema && league.admin_id !== ctx.userClaims?.id) {
        return Response.json({ error: 'Solo l’amministratore può simulare una giornata.' }, { status: 403 })
      }
      if (league.stato !== 'stagione') return Response.json({ error: 'La stagione non è in corso.' }, { status: 409 })

      const { data: firstFixture, error: firstError } = await ctx.supabaseAdmin.from('fixtures')
        .select('giornata').eq('league_id', leagueId).eq('stato', 'programmata').order('giornata').limit(1).maybeSingle()
      if (firstError) throw firstError
      if (!firstFixture) return Response.json({ league_id: leagueId, completata: true, modo: ctx.authMode, partite: [] })
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
        ctx.supabaseAdmin.from('teams').select('id, nome, user_id').eq('league_id', leagueId).in('id', teamIds),
        ctx.supabaseAdmin.from('player_instances').select('id, team_id, player_id, overall_corrente, eta_corrente, condizione, infortunato_fino_a').eq('league_id', leagueId).in('team_id', teamIds),
        ctx.supabaseAdmin.from('lineups').select('team_id, modulo, titolari, panchina, tribuna, stile_gioco, automatica').eq('league_id', leagueId).eq('giornata', giornata).in('team_id', teamIds),
        ctx.supabaseAdmin.from('lineups').select('team_id, giornata, modulo, titolari, panchina, tribuna, stile_gioco, automatica').eq('league_id', leagueId).lt('giornata', giornata).in('team_id', teamIds).order('automatica', { ascending: true }).order('giornata', { ascending: false }),
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
      // Serve a sapere chi notificare: le notifiche sono per-persona, non
      // per-squadra, perche' la campanella e' una sola per tutte le leghe.
      const teamUsers = new Map((teamsResult.data ?? []).map((team) => [team.id, team.user_id as string]))
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
      // Chi non ha schierato entro le 23:00 va avvisato: ha giocato con una
      // formazione che non ha scelto, ed e' un'informazione che cambia il
      // comportamento della giornata dopo.
      const formazioniAutomatiche = new Map<number, 'ereditata' | 'generata'>()
      for (const teamId of teamIds) {
        if (lineups.has(teamId)) continue
        const roster = rosters.get(teamId)!
        const inherited = inheritedLineups.get(teamId)
        formazioniAutomatiche.set(teamId, inherited ? 'ereditata' : 'generata')
        let fallback: DbLineup
        if (inherited) {
          fallback = { team_id: teamId, modulo: inherited.modulo, titolari: inherited.titolari, panchina: inherited.panchina, tribuna: inherited.tribuna, stile_gioco: inherited.stile_gioco, automatica: true }
        } else {
          const automatic = schiera(roster, '4-3-3')
          const starters = automatic.titolari.map((player: EnginePlayer) => player.id)
          const bench = automatic.panchina.map((player: EnginePlayer) => player.id)
          const tribuna = roster.giocatori.filter((player) => !starters.includes(player.id) && !bench.includes(player.id)).map((player) => player.id)
          fallback = { team_id: teamId, modulo: '4-3-3', titolari: starters, panchina: bench, tribuna, stile_gioco: 'equilibrato', automatica: true }
        }
        const { error: lineupError } = await ctx.supabaseAdmin.from('lineups').insert({ league_id: leagueId, giornata, ...fallback })
        if (lineupError) throw lineupError
        lineups.set(teamId, fallback)
      }

      // Fotografia prima delle partite: serve a distinguere un infortunio nuovo
      // da uno vecchio che il motore sta solo scalando di una giornata.
      const infortuniPrima = new Map<number, number>()
      for (const roster of rosters.values()) {
        for (const giocatore of roster.giocatori) {
          infortuniPrima.set(giocatore.id, giocatore.infortunatoFinoA)
        }
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
          usaCondizione: true,
          statsGiocatori: true,
          lineupCasa: homeLineup,
          lineupOspite: awayLineup,
          stileCasa: homeDbLineup.stile_gioco,
          stileOspite: awayDbLineup.stile_gioco,
        })
        const presenzePerBlocco = result.presenzePerBlocco as { casa: number[][]; ospite: number[][] }
        const eventi = costruisciEventiGol(result.golPerBlocco as GolBlocco[], [
          { lato: 'casa', teamId: fixture.home_team_id, lineup: homeLineup, marcatori: result.perGiocatore.casa.marcatoriIds as number[], presenzePerBlocco: presenzePerBlocco.casa },
          { lato: 'ospite', teamId: fixture.away_team_id, lineup: awayLineup, marcatori: result.perGiocatore.ospite.marcatoriIds as number[], presenzePerBlocco: presenzePerBlocco.ospite },
        ], seed)
        const assistPerGiocatore = new Map<number, number>()
        for (const evento of eventi) {
          if (evento.assist === null) continue
          assistPerGiocatore.set(evento.assist, (assistPerGiocatore.get(evento.assist) ?? 0) + 1)
        }

        const stats = [
          ...playerStats(fixture.home_team_id, result.perGiocatore.casa, result.statsCasa, assistPerGiocatore),
          ...playerStats(fixture.away_team_id, result.perGiocatore.ospite, result.statsOspite, assistPerGiocatore),
        ]
        const { data: saved, error: saveError } = await ctx.supabaseAdmin.rpc('registra_risultato_partita', {
          p_fixture_id: fixture.id,
          p_seed: seed,
          p_modulo_home: homeDbLineup.modulo,
          p_modulo_away: awayDbLineup.modulo,
          p_stile_home: homeDbLineup.stile_gioco,
          p_stile_away: awayDbLineup.stile_gioco,
          p_gol_home: result.golC,
          p_gol_away: result.golO,
          p_blocchi: eventi,
          p_stats_squadra: { home: result.statsCasa, away: result.statsOspite },
          p_player_stats: stats,
        })
        if (saveError) throw saveError
        summaries.push(saved)
      }

      // Condizione e infortuni tornano sul database: senza questo passaggio il
      // logoramento non si accumula, nessuno scende sotto la soglia di cambio e
      // le sostituzioni non scattano mai.
      const giornateTotali = Number(league.giornate_totali) || GIORNATE_DI_TARATURA
      const valoriCondizione = []
      const nuoviInfortuni: Array<{ teamId: number; playerId: number; nome: string; giornate: number }> = []
      for (const [teamId, roster] of rosters) {
        for (const giocatore of roster.giocatori) {
          const prima = infortuniPrima.get(giocatore.id) ?? 0
          const dopo = giocatore.infortunatoFinoA
          // Un valore cresciuto e' un infortunio nuovo, da riscalare sulla
          // lunghezza della stagione. Uno calato e' il conto alla rovescia.
          const giornateFuori = dopo > prima ? scalaInfortunio(dopo, giornateTotali) : dopo
          if (dopo > prima) {
            nuoviInfortuni.push({ teamId, playerId: giocatore.id, nome: giocatore.nome, giornate: Math.max(1, Math.round(giornateFuori)) })
          }

          // Nessuna amplificazione dell'usura: da quando il motore usa il
          // modello di fatica da partita, il consumo dentro i 90 minuti basta
          // da solo a far scattare i cambi in ogni giornata.
          valoriCondizione.push({
            id: giocatore.id,
            condizione: Math.round(Math.max(0, Math.min(100, giocatore.condizione))),
            infortunato_fino_a: Math.max(0, Math.round(giornateFuori)),
          })
        }
      }
      const { error: condizioneError } = await ctx.supabaseAdmin.rpc('aggiorna_condizione_rosa', {
        p_league_id: leagueId,
        p_valori: valoriCondizione,
      })
      if (condizioneError) throw condizioneError

      // Ogni quarto della stagione aggiorna gli overall di tutte le rose. La
      // RPC è idempotente e recupera anche un checkpoint rimasto in sospeso
      // dopo un eventuale ritentativo del cron.
      const { data: progressione, error: progressioneError } = await ctx.supabaseAdmin.rpc('applica_progressione_trimestrale', {
        p_league_id: leagueId,
        p_giornata: giornata,
      })
      if (progressioneError) throw progressioneError

      // Stesso ritmo (un quarto di stagione) ma registro e funzione separati
      // dalla progressione overall: sono due meccaniche distinte e tenerle
      // separate permette di correggerne una senza toccare l'altra.
      const { data: morale, error: moraleError } = await ctx.supabaseAdmin.rpc('applica_morale_checkpoint', {
        p_league_id: leagueId,
        p_giornata: giornata,
      })
      if (moraleError) throw moraleError

      // Notifiche: la giornata si gioca alle 00:00, quando tutti dormono.
      // Senza un avviso, il risultato lo si scopre solo riaprendo l'app.
      //
      // Un errore qui non deve far fallire la chiamata: la giornata e' gia'
      // scritta, e un 500 farebbe ritentare il cron su dati gia' registrati.
      let notificheInviate = 0
      try {
        const righe = []
        const squadreConPartitaNuova = new Set<number>()
        for (let i = 0; i < fixtures.length; i++) {
          const fixture = fixtures[i]
          const esito = summaries[i] as
            { match_id: number; gia_simulata: boolean; gol_home: number; gol_away: number } | null
          // Una partita gia' registrata e' un ritentativo: non si rinotifica.
          if (!esito || esito.gia_simulata) continue
          squadreConPartitaNuova.add(fixture.home_team_id)
          squadreConPartitaNuova.add(fixture.away_team_id)

          const lati = [
            { teamId: fixture.home_team_id, avversario: fixture.away_team_id, fatti: esito.gol_home, subiti: esito.gol_away },
            { teamId: fixture.away_team_id, avversario: fixture.home_team_id, fatti: esito.gol_away, subiti: esito.gol_home },
          ]
          for (const lato of lati) {
            const userId = teamUsers.get(lato.teamId)
            if (!userId) continue
            const verdetto = lato.fatti > lato.subiti ? 'Vittoria' : lato.fatti < lato.subiti ? 'Sconfitta' : 'Pareggio'
            righe.push({
              user_id: userId,
              league_id: leagueId,
              tipo: 'giornata_simulata',
              titolo: `${verdetto} ${lato.fatti}-${lato.subiti}`,
              corpo: `Giornata ${giornata} contro ${teamNames.get(lato.avversario) ?? 'l’avversario'}`,
              dati: { match_id: esito.match_id, giornata },
            })
          }
        }

        for (const infortunio of nuoviInfortuni) {
          if (!squadreConPartitaNuova.has(infortunio.teamId)) continue
          const userId = teamUsers.get(infortunio.teamId)
          if (!userId) continue
          righe.push({
            user_id: userId,
            league_id: leagueId,
            tipo: 'infortunio',
            titolo: `${infortunio.nome} si è infortunato`,
            corpo: `Sarà indisponibile per ${infortunio.giornate} ${infortunio.giornate === 1 ? 'giornata' : 'giornate'}. Controlla la formazione.`,
            dati: { view: 'squad', player_instance_id: infortunio.playerId, giornata },
          })
        }

        for (const [teamId, origine] of formazioniAutomatiche) {
          const userId = teamUsers.get(teamId)
          if (!userId) continue
          righe.push({
            user_id: userId,
            league_id: leagueId,
            tipo: 'formazione_mancante',
            titolo: `Formazione automatica alla giornata ${giornata}`,
            corpo: origine === 'ereditata'
              ? 'Non hai schierato entro le 23:00: e’ stata riproposta la tua ultima formazione.'
              : 'Non hai schierato entro le 23:00: e’ stato schierato il miglior 4-3-3 disponibile.',
            dati: { giornata },
          })
        }

        if (righe.length) {
          const { error: notificheError } = await ctx.supabaseAdmin.from('notifications').insert(righe)
          if (notificheError) console.error('Notifiche non inviate:', notificheError)
          else notificheInviate = righe.length
        }
      } catch (errore) {
        console.error('Notifiche non inviate:', errore)
      }

      return Response.json({ league_id: leagueId, giornata, modo: ctx.authMode, rose_aggiornate: valoriCondizione.length, progressione, morale, notifiche: notificheInviate, partite: summaries })
    } catch (error) {
      console.error(error)
      return Response.json({ error: error instanceof Error ? error.message : 'Errore durante la simulazione.' }, { status: 500 })
    }
  }),
}
