import { useEffect, useMemo, useState, type ReactElement } from 'react'
import { supabase } from '../lib/supabase'
import { cognome } from '../lib/nomi'
import { ricostruisciEventiStorici } from '../lib/matchEvents'
import { ordineRuolo, ruoloIt } from '../lib/ruoli'
import { useSeasonData } from '../lib/useSeasonData'
import { isEventoGol, type EventoGol, type League, type MatchPlayerStat, type MatchTeamStats, type Membership } from '../types'
import { GameNav, type GameView } from './GameNav'
import { SeasonState } from './SeasonUI'
import { fasciaVoto, formatoVoto } from '../lib/voti'
import { LOGO_FASE, SFONDO_FASE, type FaseSquadra } from '../lib/faseSquadra'
import { Crest } from './Crest'
import { Icona } from './Icona'
import { urlFotoGiocatore } from '../lib/fotoGiocatore'
import { REPARTO } from '../lib/tattica'

type Props = {
  membership: Membership
  matchId: number
  onBack: () => void
  onRivedi?: () => void
  onNavigate: (view: GameView) => void
  onOpenTeam: (teamId: number) => void
}

type PlayerIdentity = { id: number; nome: string; posizioni: string[]; foto_url: string | null }

const STAT_ROWS: Array<[string, keyof MatchTeamStats, (value: number) => string]> = [
  ['Possesso', 'possesso', (value) => `${Math.round(value * 100)}%`],
  ['Tiri', 'tiri', String],
  ['Tiri in porta', 'inPorta', String],
  ['Precisione passaggi', 'passaggiPct', (value) => `${Math.round(value * 100)}%`],
  ['Passaggi riusciti', 'passaggiR', String],
  ['Contrasti', 'contrasti', String],
  ['Dribbling', 'dribbling', String],
]

type Pagella = { voto: number | null; migliore: boolean; dettaglio: Record<string, number> | null }

// Le azioni che spiegano il voto del migliore in campo: le tre piu' parlanti
// per il suo ruolo, mai uno zero.
function motivazioni(d: Record<string, number> | null): string[] {
  if (!d) return []
  const voci: [number, string][] = []
  if (d.gol) voci.push([100, `${d.gol} gol`])
  if (d.assist) voci.push([90, `${d.assist} assist`])
  if (d.parate) voci.push([80, `${d.parate} ${d.parate === 1 ? 'parata' : 'parate'}`])
  if (d.interventiRiusciti) voci.push([60 + d.interventiRiusciti, `${d.interventiRiusciti} interventi`])
  if (d.contrastiVinti) voci.push([50 + d.contrastiVinti, `${d.contrastiVinti} contrasti`])
  if (d.dribblingRiusciti) voci.push([45 + d.dribblingRiusciti, `${d.dribblingRiusciti} dribbling`])
  if (d.tiriInPorta && !d.gol) voci.push([40, `${d.tiriInPorta} tiri in porta`])
  if (d.passaggi >= 20) voci.push([30, `${Math.round(d.passaggiRiusciti / d.passaggi * 100)}% passaggi`])
  return voci.sort((a, b) => b[0] - a[0]).slice(0, 3).map(([, testo]) => testo)
}

export function MatchDetail({ membership, matchId, onBack, onRivedi, onNavigate, onOpenTeam }: Props) {
  const league = membership.league as League
  const data = useSeasonData(membership)
  const [stats, setStats] = useState<MatchPlayerStat[]>([])
  const [players, setPlayers] = useState<Map<number, PlayerIdentity>>(new Map())
  const [statsLoading, setStatsLoading] = useState(true)
  const [statsError, setStatsError] = useState<string | null>(null)
  const [titolariLineupByTeam, setTitolariLineupByTeam] = useState<Map<number, Set<number>>>(new Map())
  const [pagelle, setPagelle] = useState<Map<number, Pagella>>(new Map())
  const match = data.matches.find((item) => item.id === matchId)
  const fixture = match ? data.fixtures.find((item) => item.id === match.fixture_id) : undefined

  useEffect(() => {
    let active = true
    async function loadStats() {
      setStatsLoading(true)
      setStatsError(null)
      const { data: statRows, error } = await supabase.from('match_stats').select('*').eq('match_id', matchId)
      if (error) { if (active) { setStatsError(error.message); setStatsLoading(false) }; return }
      const loadedStats = (statRows ?? []) as MatchPlayerStat[]
      const instanceIds = loadedStats.map((item) => item.player_instance_id)
      const { data: instances, error: instanceError } = instanceIds.length
        ? await supabase.from('player_instances').select('id, player_id').in('id', instanceIds)
        : { data: [], error: null }
      if (instanceError) { if (active) { setStatsError(instanceError.message); setStatsLoading(false) }; return }
      const playerIds = [...new Set((instances ?? []).map((item) => item.player_id))]
      const { data: catalog, error: catalogError } = playerIds.length
        ? await supabase.from('players').select('id, nome, posizioni, foto_url').in('id', playerIds)
        : { data: [], error: null }
      if (catalogError) { if (active) { setStatsError(catalogError.message); setStatsLoading(false) }; return }
      const catalogById = new Map((catalog ?? []).map((player) => [player.id, player as PlayerIdentity]))
      const instancePlayers = new Map<number, PlayerIdentity>()
      for (const instance of instances ?? []) {
        const player = catalogById.get(instance.player_id)
        if (player) instancePlayers.set(instance.id, player)
      }
      // Le pagelle esistono dalle partite simulate con la Edge Function delle
      // tattiche: per quelle di prima la colonna resta vuota, senza errori.
      const { data: righePagelle } = await supabase.from('pagelle')
        .select('player_instance_id, voto, migliore_in_campo, dettaglio').eq('match_id', matchId)
      const mappaPagelle = new Map<number, Pagella>((righePagelle ?? []).map((riga) => [riga.player_instance_id, {
        voto: riga.voto === null ? null : Number(riga.voto), migliore: riga.migliore_in_campo, dettaglio: riga.dettaglio,
      }]))
      if (active) { setStats(loadedStats); setPlayers(instancePlayers); setPagelle(mappaPagelle); setStatsLoading(false) }
    }
    void loadStats()
    return () => { active = false }
  }, [matchId])

  // Fallback per le partite simulate prima che matches.titolari_home/away
  // fotografasse chi e' davvero sceso in campo: la scelta salvata prima
  // della partita e' il meglio che si puo' mostrare per quelle vecchie.
  useEffect(() => {
    let active = true
    async function loadLineups() {
      if (!fixture) return
      const { data: rows } = await supabase.from('lineups').select('team_id, titolari')
        .eq('league_id', fixture.league_id).eq('giornata', fixture.giornata)
        .in('team_id', [fixture.home_team_id, fixture.away_team_id])
      if (!active) return
      const mappa = new Map<number, Set<number>>()
      for (const row of rows ?? []) mappa.set(row.team_id, new Set(row.titolari as number[]))
      setTitolariLineupByTeam(mappa)
    }
    void loadLineups()
    return () => { active = false }
  }, [fixture])

  // Chi e' davvero sceso in campo dal minuto 0, non chi era stato scelto
  // prima della partita: la Edge Function puo' aver gia' rimpiazzato un
  // titolare infortunato con un giocatore di panchina (buildLineup), e quel
  // rimpiazzante puo' a sua volta uscire durante la partita per stanchezza
  // -- indistinguibile da un vero subentrato guardando solo i minuti.
  const titolariByTeam = useMemo(() => {
    const mappa = new Map<number, Set<number>>()
    if (!match || !fixture) return mappa
    for (const [teamId, effettivi] of [
      [fixture.home_team_id, match.titolari_home],
      [fixture.away_team_id, match.titolari_away],
    ] as const) {
      mappa.set(teamId, effettivi.length ? new Set(effettivi) : (titolariLineupByTeam.get(teamId) ?? new Set()))
    }
    return mappa
  }, [match, fixture, titolariLineupByTeam])

  // Fase, turno e andata: come la cronaca live (MatchReveal) e l'intro
  // (MatchIntro), cosi' il riepilogo ha la stessa veste grafica della partita.
  const [fase, setFase] = useState<FaseSquadra>('regular')
  const [turno, setTurno] = useState<string | null>(null)
  const [andata, setAndata] = useState<{ casa: number; ospite: number } | null>(null)
  useEffect(() => {
    let vivo = true
    async function carica() {
      if (!fixture?.bracket_tie_id) { if (vivo) { setFase('regular'); setTurno(null); setAndata(null) }; return }
      const { data: tie } = await supabase.from('bracket_ties').select('bracket_id, turno').eq('id', fixture.bracket_tie_id).single()
      if (!tie || !vivo) return
      const [{ data: bracketRow }, { data: tutte }, { data: primaMano }] = await Promise.all([
        supabase.from('brackets').select('tipo').eq('id', tie.bracket_id).single(),
        supabase.from('bracket_ties').select('turno').eq('bracket_id', tie.bracket_id),
        fixture.mano === 2
          ? supabase.from('fixtures').select('home_team_id, matches(gol_home, gol_away)').eq('bracket_tie_id', fixture.bracket_tie_id).eq('mano', 1).maybeSingle()
          : Promise.resolve({ data: null }),
      ])
      if (!vivo) return
      setFase((bracketRow?.tipo as FaseSquadra | undefined) ?? 'regular')
      // Il totale dei turni si legge dal primo, che e' completo dall'inizio
      // (stessa regola di Tabellone.tsx e MatchIntro.tsx).
      const primoTurno = (tutte ?? []).filter((t) => t.turno === 1).length
      const totali = primoTurno > 0 ? Math.ceil(Math.log2(primoTurno * 2)) : 0
      const mancanti = totali - tie.turno
      setTurno(mancanti === 0 ? 'Finale' : mancanti === 1 ? 'Semifinale' : mancanti === 2 ? 'Quarti di finale' : `Turno ${tie.turno}`)
      const partita = primaMano ? (Array.isArray(primaMano.matches) ? primaMano.matches[0] : primaMano.matches) : null
      if (primaMano && partita) {
        const stessoVerso = primaMano.home_team_id === fixture.home_team_id
        setAndata({ casa: stessoVerso ? partita.gol_home : partita.gol_away, ospite: stessoVerso ? partita.gol_away : partita.gol_home })
      } else setAndata(null)
    }
    void carica()
    return () => { vivo = false }
  }, [fixture?.bracket_tie_id, fixture?.mano, fixture?.home_team_id])

  // Le partite simulate prima dell'introduzione della cronaca hanno blocchi vuoto.
  const eventi = useMemo(() => {
    const registrati = match?.blocchi
    if (!Array.isArray(registrati)) return []
    const estesa = registrati.some((evento) => !isEventoGol(evento))
    if (!estesa && match && fixture) {
      if (statsLoading) return []
      return ricostruisciEventiStorici(
        registrati,
        stats,
        match.titolari_home,
        match.titolari_away,
        fixture.home_team_id,
        fixture.away_team_id,
        match.id,
      )
    }
    return [...registrati].sort((sinistra, destra) => sinistra.minuto - destra.minuto)
  }, [fixture, match, stats, statsLoading])

  // Ordinati per reparto (GK -> ST) prima ancora che per prestazione: e' cosi'
  // che si legge un tabellino, non per gol fatti.
  const byTeam = useMemo(() => {
    const grouped = new Map<number, MatchPlayerStat[]>()
    for (const row of stats) grouped.set(row.team_id, [...(grouped.get(row.team_id) ?? []), row])
    for (const rows of grouped.values()) {
      rows.sort((left, right) =>
        ordineRuolo(players.get(left.player_instance_id)?.posizioni) - ordineRuolo(players.get(right.player_instance_id)?.posizioni)
        || right.gol - left.gol || right.assist - left.assist || right.tiri_porta - left.tiri_porta || right.minuti - left.minuti)
    }
    return grouped
  }, [stats, players])

  // Titolari e subentrati in due gruppi separati, ciascuno gia' ordinato come
  // sopra. Chi e' uscito si riconosce senza ambiguita' solo fra i titolari
  // (minuti < 90): per un subentrato gli stessi minuti ridotti potrebbero
  // significare solo che e' entrato tardi, non che sia uscito a sua volta.
  const gruppiByTeam = useMemo(() => {
    const risultato = new Map<number, { titolari: MatchPlayerStat[]; subentrati: MatchPlayerStat[] }>()
    for (const [teamId, rows] of byTeam) {
      const titolariSet = titolariByTeam.get(teamId) ?? new Set<number>()
      risultato.set(teamId, {
        titolari: rows.filter((row) => titolariSet.has(row.player_instance_id)),
        subentrati: rows.filter((row) => !titolariSet.has(row.player_instance_id)),
      })
    }
    return risultato
  }, [byTeam, titolariByTeam])

  function navigate(view: GameView) { onNavigate(view) }

  // mostraUscita e' vero solo per i titolari: e' l'unico caso in cui minuti
  // ridotti significano senza ambiguita' "sostituito", non "entrato tardi".
  function rigaGiocatore(row: MatchPlayerStat, mostraUscita: boolean, posizione: number) {
    const identita = players.get(row.player_instance_id)
    const ruolo = identita?.posizioni[0] ?? '—'
    const foto = urlFotoGiocatore(identita?.foto_url)
    // Gol e assist come icone accanto al nome: niente colonne in piu', cosi'
    // la riga non scorre mai di lato anche a 360 px.
    return <div className="pagella-riga" key={row.id} style={{ ['--i' as string]: posizione }}>
      <span className="pagella-riga__foto">{foto ? <img src={foto} alt="" loading="lazy" /> : <b>{(identita?.nome ?? '?').charAt(0)}</b>}</span>
      <span className="pagella-riga__chi">
        <strong>{identita ? cognome(identita.nome) : `Giocatore ${row.player_instance_id}`}</strong>
        <span className="pagella-riga__info">
          <i className={`ruolo-chip ruolo-chip--${REPARTO[ruolo] ?? 'MID'}`}>{ruoloIt(ruolo)}</i>
          {Array.from({ length: row.gol }, (_, k) => <span key={`g${k}`} className="pagella-icona" title="Gol"><Pallone /></span>)}
          {Array.from({ length: row.assist }, (_, k) => <span key={`a${k}`} className="pagella-icona pagella-icona--assist" title="Assist"><Scarpa /></span>)}
          {mostraUscita && row.minuti < 90 && <em className="pagella-uscita" title={`Uscito al ${row.minuti}'`}>↓ {row.minuti}′</em>}
        </span>
      </span>
      <VotoCella pagella={pagelle.get(row.player_instance_id)} assenti={pagelle.size === 0} />
      <b className="pagella-riga__min">{row.minuti}′</b>
    </div>
  }

  const nome = (id: number | null | undefined) => (id == null ? '' : cognome(players.get(id)?.nome ?? `Giocatore ${id}`))
  // I momenti che contano, in ordine: gol, cartellini, cambi e infortuni. I
  // tiri restano fuori, sarebbero rumore.
  const momenti = eventi.filter((e) => isEventoGol(e) || e.tipo === 'cartellino' || e.tipo === 'sostituzione' || e.tipo === 'infortunio')
  // Il risultato dopo ogni gol, per la linea del tempo.
  const parziali = new Map<EventoGol, string>()
  {
    let c = 0, o = 0
    for (const e of momenti) if (isEventoGol(e)) { if (e.lato === 'casa') c++; else o++; parziali.set(e, `${c}–${o}`) }
  }

  return <main className="app-shell season-shell">
    <GameNav league={league} active="matches" onNavigate={navigate} />
    <header className="topbar season-topbar"><button className="match-detail-back" type="button" onClick={onBack}>← Torna alle partite</button><span>Rapporto partita</span></header>
    <SeasonState loading={data.loading} error={data.error} onRetry={data.reload} />
    {!data.loading && !data.error && (!match || !fixture) && <section className="season-state"><span className="season-state__icon">!</span><h2>Partita non trovata</h2><button className="button button--primary" type="button" onClick={onBack}>Torna indietro</button></section>}
    {!data.loading && !data.error && match && fixture && (() => {
      const casa = data.teamById.get(fixture.home_team_id)
      const ospite = data.teamById.get(fixture.away_team_id)
      const stato = match.rigori_home !== null ? 'Finale d.c.r.' : match.gol_home_90 !== null ? 'Finale d.t.s.' : 'Finale'
      const squadraEroe = (teamId: number, team: typeof casa, lato: 'casa' | 'ospite') =>
        <button className={`riepilogo-eroe__squadra riepilogo-eroe__squadra--${lato}`} type="button" onClick={() => onOpenTeam(teamId)}>
          <span className="riepilogo-eroe__stemma"><Crest value={team?.stemma_url ?? null} stelle={team?.titoli_title} imageUrl={data.crestUrlByTeamId.get(teamId)} size="large" /></span>
          <b>{team?.sigla ?? team?.nome?.slice(0, 3).toUpperCase()}</b>
          <small>{team?.nome ?? 'Squadra'}</small>
        </button>
      return <div className={`season-page season-page--narrow match-detail-page riepilogo riepilogo--${fase}`}>
        <section className="riepilogo-eroe" style={{ ['--rie-fondo' as string]: `url(${SFONDO_FASE[fase]})` }}>
          <div className="riepilogo-eroe__testa">
            <img src={LOGO_FASE[fase]} alt="" />
            <p>{turno ? `${turno}${fixture.mano ? ` · ${fixture.mano === 1 ? 'andata' : 'ritorno'}` : ''}` : `Giornata ${fixture.giornata}`} · Stagione {league.stagione_corrente}</p>
          </div>
          <div className="riepilogo-eroe__tabellone">
            {squadraEroe(fixture.home_team_id, casa, 'casa')}
            <div className="riepilogo-eroe__punteggio" aria-label={`${match.gol_home} a ${match.gol_away}`}>
              <b>{match.gol_home}{match.rigori_home !== null && <sup>{match.rigori_home}</sup>}</b><i aria-hidden="true" /><b>{match.gol_away}{match.rigori_away !== null && <sup>{match.rigori_away}</sup>}</b>
              <span className="riepilogo-eroe__stato">{stato}</span>
            </div>
            {squadraEroe(fixture.away_team_id, ospite, 'ospite')}
          </div>
          {andata && <p className="riepilogo-eroe__totale"><span>Andata {andata.casa}–{andata.ospite}</span><b>Totale {andata.casa + match.gol_home}–{andata.ospite + match.gol_away}</b></p>}
          <div className="riepilogo-eroe__marcatori">
            {(['casa', 'ospite'] as const).map((lato) => <ul key={lato} className={`riepilogo-marcatori riepilogo-marcatori--${lato}`}>
              {eventi.filter((e): e is EventoGol => isEventoGol(e) && e.lato === lato).map((e, k) => <li key={`${e.minuto}-${k}`}>
                <time>{e.minuto}′</time><b>{nome(e.marcatore)}</b>{e.assist !== null && <em>{nome(e.assist)}</em>}
              </li>)}
            </ul>)}
          </div>
          {onRivedi && <button className="match-detail-rivedi match-detail-rivedi--eroe" type="button" onClick={onRivedi}>▶ Rivedi la partita</button>}
        </section>

        {!statsLoading && (() => {
          const mvp = [...pagelle.entries()].find(([, p]) => p.migliore)
          if (!mvp || mvp[1].voto === null) return null
          const [id, p] = mvp
          const riga = stats.find((r) => r.player_instance_id === id)
          const identita = players.get(id)
          const squadra = riga ? data.teamById.get(riga.team_id)?.nome : undefined
          const foto = urlFotoGiocatore(identita?.foto_url)
          return <div className="mvp-card">
            <div className="mvp-card__testo">
              <span className="mvp-card__etichetta"><Stella />Migliore in campo</span>
              <div className="mvp-card__chi">
                <strong>{identita?.nome ?? `Giocatore ${id}`}</strong>
                <small>{[ruoloIt(identita?.posizioni[0]), squadra].filter(Boolean).join(' · ')}</small>
              </div>
              {motivazioni(p.dettaglio).length > 0 && <ul className="mvp-card__perche">
                {motivazioni(p.dettaglio).map((m) => <li key={m}>{m}</li>)}
              </ul>}
            </div>
            <div className="mvp-card__ritratto">
              {foto ? <img src={foto} alt="" /> : <span>{(identita?.nome ?? '?').charAt(0)}</span>}
              <b className={`mvp-card__voto voto--${fasciaVoto(p.voto!)}`}>{formatoVoto(p.voto!)}</b>
            </div>
          </div>
        })()}

        {momenti.length > 0 && <section className="riepilogo-pannello">
          <h2 className="riepilogo-titolo">Momenti chiave</h2>
          <ol className="riepilogo-momenti">
            {momenti.flatMap((e, k) => {
              // Separatori di tempo fra un evento e il successivo: intervallo,
              // fine dei 90' se si e' andati ai supplementari.
              const prima = k > 0 ? momenti[k - 1].minuto : 0
              const separatori: ReactElement[] = []
              if (prima <= 45 && e.minuto > 45) separatori.push(<li key={`s45-${k}`} className="riepilogo-separatore"><span>45′ · Intervallo</span></li>)
              if (match.gol_home_90 !== null && prima <= 90 && e.minuto > 90) separatori.push(<li key={`s90-${k}`} className="riepilogo-separatore"><span>90′ · Supplementari {match.gol_home_90}–{match.gol_away_90}</span></li>)
              const contenuto = isEventoGol(e)
                ? <><span className="momento-icona momento-icona--gol" role="img" aria-label="Gol"><Pallone /></span><span><b>{nome(e.marcatore)} <em className="momento-parziale">{parziali.get(e)}</em></b>{e.assist !== null && <small>assist {nome(e.assist)}</small>}</span></>
                : e.tipo === 'cartellino'
                  ? <><span className={`momento-icona momento-icona--${e.colore === 'giallo' ? 'giallo' : 'rosso'}`} aria-label={e.colore === 'giallo' ? 'Ammonizione' : 'Espulsione'} /><span><b>{nome(e.giocatore)}</b>{e.colore === 'doppio_giallo' && <small>secondo giallo</small>}</span></>
                  : e.tipo === 'sostituzione'
                    ? <><span className="momento-icona momento-icona--cambio" aria-label="Sostituzione"><Icona nome="cambio" /></span><span><b className="entra">{nome(e.entra)}</b><small>esce {nome(e.esce)}</small></span></>
                    : e.tipo === 'infortunio'
                      ? <><span className="momento-icona momento-icona--infortunio" aria-label="Infortunio" /><span><b>{nome(e.esce)}</b><small>infortunato, entra {nome(e.entra)}</small></span></>
                      : null
              return [...separatori, <li key={k} className={`riepilogo-momento riepilogo-momento--${e.lato}${isEventoGol(e) ? ' is-gol' : ''}`}>
                <time>{e.minuto}′</time>
                <div>{contenuto}</div>
              </li>]
            })}
            {/* Supplementari senza eventi: il separatore serve comunque, la partita e' andata oltre. */}
            {match.gol_home_90 !== null && !momenti.some((e) => e.minuto > 90) && <li className="riepilogo-separatore"><span>90′ · Supplementari {match.gol_home_90}–{match.gol_away_90}</span></li>}
            {match.rigori_home !== null && <li className="riepilogo-separatore riepilogo-separatore--fine"><span>Rigori {match.rigori_home}–{match.rigori_away}</span></li>}
          </ol>
        </section>}

        {/* Playoff/playout (design §10.7): senza questo riquadro il punteggio in
            alto sarebbe incomprensibile — una gara vinta ai rigori mostrerebbe
            un pareggio con un vincitore. */}
        {match.rigori_home !== null && match.rigori_away !== null && <section className="riepilogo-pannello">
          <h2 className="riepilogo-titolo">Calci di rigore</h2>
          <div className="riepilogo-rigori">
            {(['casa', 'ospite'] as const).map((lato) => <div key={lato} className="riepilogo-rigori__riga">
              <span className="riepilogo-rigori__stemma"><Crest value={(lato === 'casa' ? casa : ospite)?.stemma_url ?? null} stelle={(lato === 'casa' ? casa : ospite)?.titoli_title} imageUrl={data.crestUrlByTeamId.get(lato === 'casa' ? fixture.home_team_id : fixture.away_team_id)} size="small" /></span>
              <b>{(lato === 'casa' ? casa : ospite)?.sigla}</b>
              <ol>{(match.rigori_serie ?? []).filter((t) => t.lato === lato).map((t, k) =>
                <li key={t.numero} className={t.segnato ? 'is-gol' : 'is-errore'} style={{ ['--i' as string]: k }} title={`${t.tiratore}: ${t.segnato ? 'gol' : 'errore'}`} aria-label={`${t.tiratore}: ${t.segnato ? 'gol' : 'errore'}`}>{t.segnato ? '✓' : '✕'}</li>)}</ol>
              <strong>{lato === 'casa' ? match.rigori_home : match.rigori_away}</strong>
            </div>)}
          </div>
          {match.gol_home_90 !== null && <p className="riepilogo-nota"><span>Al 90′ {match.gol_home_90}–{match.gol_away_90}</span><span>Dopo i supplementari {match.gol_home}–{match.gol_away}</span></p>}
        </section>}

        <section className="riepilogo-pannello">
          <h2 className="riepilogo-titolo">Statistiche</h2>
          <div className="riepilogo-stat__sigle">
            <span className="riepilogo-stat__squadra riepilogo-stat__squadra--casa"><span className="riepilogo-squadra__stemma"><Crest value={casa?.stemma_url ?? null} stelle={casa?.titoli_title} imageUrl={data.crestUrlByTeamId.get(fixture.home_team_id)} size="small" /></span>{casa?.sigla}</span>
            <span className="riepilogo-stat__squadra riepilogo-stat__squadra--ospite">{ospite?.sigla}<span className="riepilogo-squadra__stemma"><Crest value={ospite?.stemma_url ?? null} stelle={ospite?.titoli_title} imageUrl={data.crestUrlByTeamId.get(fixture.away_team_id)} size="small" /></span></span>
          </div>
          <div className="riepilogo-stat">
            {STAT_ROWS.map(([label, key, format]) => {
              const home = Number(match.stats_squadra.home[key] ?? 0)
              const away = Number(match.stats_squadra.away[key] ?? 0)
              const total = home + away || 1
              return <div className={`riepilogo-stat__riga${home > away ? ' is-casa' : away > home ? ' is-ospite' : ''}`} key={key}>
                <b>{format(home)}</b><span>{label}</span><b>{format(away)}</b>
                <i><span style={{ width: `${home / total * 100}%` }} /><span style={{ width: `${away / total * 100}%` }} /></i>
              </div>
            })}
          </div>
        </section>

        <section className="riepilogo-pannello">
          <h2 className="riepilogo-titolo">Pagelle e prestazioni</h2>
          {statsError && <p className="notice notice--error">{statsError}</p>}
          {statsLoading ? <p className="season-empty">Carico le prestazioni…</p> : <div className="match-player-columns">
            {[fixture.home_team_id, fixture.away_team_id].map((teamId) => {
              const gruppi = gruppiByTeam.get(teamId)
              const modulo = teamId === fixture.home_team_id ? match.modulo_home : match.modulo_away
              const team = data.teamById.get(teamId)
              return <div className="match-player-team" key={teamId}>
                <h3><span className="riepilogo-squadra"><span className="riepilogo-squadra__stemma"><Crest value={team?.stemma_url ?? null} stelle={team?.titoli_title} imageUrl={data.crestUrlByTeamId.get(teamId)} size="small" /></span>{team?.nome ?? 'Squadra'}</span><small>{modulo}</small></h3>
                <div className="pagella-tabella">
                  <div className="pagella-tabella__testa"><span>Giocatore</span><span>Voto</span><span>Min</span></div>
                  {gruppi && gruppi.titolari.length > 0 && <>
                    <p className="pagella-gruppo">Titolari</p>
                    {gruppi.titolari.map((row, k) => rigaGiocatore(row, true, k))}
                  </>}
                  {gruppi && gruppi.subentrati.length > 0 && <>
                    <p className="pagella-gruppo">Subentrati</p>
                    {gruppi.subentrati.map((row, k) => rigaGiocatore(row, false, gruppi.titolari.length + k))}
                  </>}
                </div>
              </div>
            })}
          </div>}
        </section>
      </div>
    })()}
  </main>
}

// Il pallone dei momenti chiave: pentagono nero al centro, cuciture e toppe al
// bordo. Un gradiente circolare sembrava un CD.
function Pallone() {
  return (
    <svg viewBox="0 0 24 24" width="100%" height="100%" aria-hidden="true" focusable="false">
      <defs><radialGradient id="pallone-luce" cx="38%" cy="32%" r="75%"><stop offset="0" stopColor="#ffffff" /><stop offset="1" stopColor="#d6d0df" /></radialGradient></defs>
      <circle cx="12" cy="12" r="10.8" fill="url(#pallone-luce)" />
      <path d="M12.00 8.40L15.64 6.98 M12.00 8.40L8.36 6.98 M15.42 10.89L15.64 6.98 M15.42 10.89L17.90 13.92 M14.12 14.91L17.90 13.92 M14.12 14.91L12.00 18.20 M9.88 14.91L12.00 18.20 M9.88 14.91L6.10 13.92 M8.58 10.89L6.10 13.92 M8.58 10.89L8.36 6.98 M19.80 3.97L19.52 4.25 M22.05 16.93L21.69 16.76 M13.59 23.08L13.53 22.69 M1.95 16.93L2.31 16.76 M6.77 2.10L6.95 2.45" stroke="#4a4256" strokeWidth="0.75" strokeLinecap="round" />
      <g fill="#16121e"><polygon points="12.00,8.40 15.42,10.89 14.12,14.91 9.88,14.91 8.58,10.89" /><polygon points="15.64,6.98 14.66,3.97 17.23,2.10 19.80,3.97 18.82,6.98" /><polygon points="17.90,13.92 20.46,12.05 23.03,13.92 22.05,16.93 18.88,16.93" /><polygon points="12.00,18.20 14.57,20.07 13.59,23.08 10.41,23.08 9.43,20.07" /><polygon points="6.10,13.92 5.12,16.93 1.95,16.93 0.97,13.92 3.54,12.05" /><polygon points="8.36,6.98 5.18,6.98 4.20,3.97 6.77,2.10 9.34,3.97" /></g>
    </svg>
  )
}

// L'assist: una scarpetta, in coppia col pallone del gol.
function Scarpa() {
  return (
    <svg viewBox="0 0 24 24" width="100%" height="100%" aria-hidden="true" focusable="false">
      <path d="M3 9.5 9.2 9l2.3 3.2 5.6 1.4c2.4.6 3.9 1.8 3.9 3.4v.5H3z" fill="#e9e3f1" />
      <path d="M3 17.5h18" stroke="#15111d" strokeWidth="1.4" />
      <path d="M6 19.5v-1.2M10 19.5v-1.2M14 19.5v-1.2M18 19.5v-1.2" stroke="#e9e3f1" strokeWidth="1.6" strokeLinecap="round" />
    </svg>
  )
}

// Il migliore in campo: stella oro, come il Player of the Match di EA FC.
function Stella() {
  return (
    <svg className="mvp-stella" viewBox="0 0 24 24" width="1em" height="1em" aria-hidden="true" focusable="false">
      <path d="M12 2.8l2.7 5.6 6.1.8-4.5 4.2 1.1 6.1L12 16.6l-5.4 2.9 1.1-6.1-4.5-4.2 6.1-.8z" fill="currentColor" />
    </svg>
  )
}

function VotoCella({ pagella, assenti }: { pagella?: Pagella; assenti: boolean }) {
  if (assenti) return <span />
  if (!pagella || pagella.voto === null) return <span className="voto voto--vuoto" title="Senza voto: meno di 15 minuti">SV</span>
  return <span className={`voto voto--${fasciaVoto(pagella.voto)}${pagella.migliore ? ' is-migliore' : ''}`}
    title={pagella.migliore ? 'Migliore in campo' : undefined}>{formatoVoto(pagella.voto)}</span>
}
