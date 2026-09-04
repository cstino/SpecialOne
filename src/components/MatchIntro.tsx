import { useEffect, useMemo, useState } from 'react'
import { supabase } from '../lib/supabase'
import { cognome } from '../lib/nomi'
import { LOGO_FASE, MUSICA_FASE, type FaseSquadra } from '../lib/faseSquadra'
import { righeFormazione } from '../lib/formazioni'
import { firmaFoto } from './RosaElenco'
import type { useSeasonData } from '../lib/useSeasonData'
import type { BracketTie, Fixture, Match, Membership, Team } from '../types'
import { Crest } from './Crest'

type RigaClassificaStorica = { teamId: number; punti: number; differenzaReti: number; golFatti: number; posizione: number }

// La classifica del riepilogo non deve mai anticipare l'esito della partita
// che sta per essere presentata: data.standings e' sempre quella LIVE, gia'
// aggiornata dalla giornata in scena (e da eventuali giornate successive gia'
// simulate ma non ancora "viste"). Va ricostruita da zero usando solo i
// risultati con giornata precedente a quella della fixture, con lo stesso
// criterio del server (punti, scontri diretti fra chi e' a pari punti,
// differenza reti, gol fatti — vedi registra_risultato_partita).
function classificaFinoA(fixtures: Fixture[], matchByFixture: Map<number, Match>, teamIds: number[], giornataEsclusiva: number): RigaClassificaStorica[] {
  const stato = new Map<number, { punti: number; golFatti: number; golSubiti: number }>(
    teamIds.map((id) => [id, { punti: 0, golFatti: 0, golSubiti: 0 }])
  )
  const risultati = fixtures
    .filter((fixture) => fixture.bracket_tie_id == null && fixture.giornata < giornataEsclusiva)
    .map((fixture) => ({ fixture, match: matchByFixture.get(fixture.id) }))
    .filter((riga): riga is { fixture: Fixture; match: Match } => riga.match != null)

  for (const { fixture, match } of risultati) {
    const casa = stato.get(fixture.home_team_id)
    const ospite = stato.get(fixture.away_team_id)
    if (!casa || !ospite) continue
    casa.golFatti += match.gol_home; casa.golSubiti += match.gol_away
    ospite.golFatti += match.gol_away; ospite.golSubiti += match.gol_home
    if (match.gol_home > match.gol_away) casa.punti += 3
    else if (match.gol_home < match.gol_away) ospite.punti += 3
    else { casa.punti += 1; ospite.punti += 1 }
  }

  function puntiDiretti(teamId: number, puntiRiferimento: number) {
    let totale = 0
    for (const { fixture, match } of risultati) {
      const avversario = fixture.home_team_id === teamId ? fixture.away_team_id
        : fixture.away_team_id === teamId ? fixture.home_team_id : null
      if (avversario == null || stato.get(avversario)?.punti !== puntiRiferimento) continue
      const golPropri = fixture.home_team_id === teamId ? match.gol_home : match.gol_away
      const golAltrui = fixture.home_team_id === teamId ? match.gol_away : match.gol_home
      totale += golPropri > golAltrui ? 3 : golPropri === golAltrui ? 1 : 0
    }
    return totale
  }

  return teamIds
    .map((teamId) => {
      const riga = stato.get(teamId)!
      return { teamId, punti: riga.punti, differenzaReti: riga.golFatti - riga.golSubiti, golFatti: riga.golFatti, puntiDiretti: puntiDiretti(teamId, riga.punti) }
    })
    .sort((a, b) => b.punti - a.punti || b.puntiDiretti - a.puntiDiretti || b.differenzaReti - a.differenzaReti || b.golFatti - a.golFatti || a.teamId - b.teamId)
    .map((riga, indice) => ({ teamId: riga.teamId, punti: riga.punti, differenzaReti: riga.differenzaReti, golFatti: riga.golFatti, posizione: indice + 1 }))
}

type Props = {
  membership: Membership
  fixture: Fixture
  data: ReturnType<typeof useSeasonData>
  homeTeam: Team | undefined
  awayTeam: Team | undefined
  homeCrestUrl: string | undefined
  awayCrestUrl: string | undefined
  onSkip: () => void
  onFinish: () => void
  onClose: () => void
}

type TipoBeat = 'locandina' | 'classifica' | 'tabellone' | 'formazione'
type Beat = { tipo: TipoBeat; lato?: 'home' | 'away'; durata: number }

// Scaletta e durate decise dall'utente il 29 agosto 2026: diverse per fase,
// non un unico schema fisso. La stagione regolare mostra la classifica, i
// playoff mostrano il tabellone al suo posto (stesso beat, contenuto diverso).
const BEATS_PER_FASE: Record<FaseSquadra, Beat[]> = {
  regular: [
    { tipo: 'locandina', durata: 3 },
    { tipo: 'classifica', durata: 4 },
    { tipo: 'formazione', lato: 'home', durata: 10 },
    { tipo: 'formazione', lato: 'away', durata: 10 },
  ],
  title: [
    { tipo: 'locandina', durata: 7 },
    { tipo: 'tabellone', durata: 8 },
    { tipo: 'formazione', lato: 'home', durata: 13 },
    { tipo: 'formazione', lato: 'away', durata: 13 },
  ],
  draft: [
    { tipo: 'locandina', durata: 5 },
    { tipo: 'tabellone', durata: 7 },
    { tipo: 'formazione', lato: 'home', durata: 13 },
    { tipo: 'formazione', lato: 'away', durata: 13 },
  ],
}

type Lineup = { modulo: string; titolari: number[] }
type Giocatore = { nome: string; foto?: string }
type InfoBracket = { tipo: FaseSquadra; bracketId: number; turno: number; turniTotali: number; etichettaTurno: string }

// I turni successivi nascono solo quando il precedente si risolve, quindi
// max(turno) fra gli accoppiamenti esistenti sottostima sempre il totale:
// giocando i quarti esistono solo i turni 1 e 2, e il turno 1 finiva
// etichettato "Semifinale". Il totale si ricava invece dalla dimensione del
// primo turno, che e' completo fin dall'inizio (4 accoppiamenti -> 8
// squadre -> 3 turni). Stessa formula di turniTotaliDa in Tabellone.tsx,
// dove la correzione era gia' stata fatta.
function turniTotaliDa(ties: BracketTie[]): number {
  const primoTurno = ties.filter((tie) => tie.turno === 1).length
  return primoTurno > 0 ? Math.ceil(Math.log2(primoTurno * 2)) : 0
}

// Stessa logica di nomeTurno in Tabellone.tsx: il nome del turno si legge da
// quanti ne restano, non da quanti ne sono passati.
function etichettaTurno(turno: number, turniTotali: number) {
  const mancanti = turniTotali - turno
  if (mancanti === 0) return 'Finale'
  if (mancanti === 1) return 'Semifinale'
  if (mancanti === 2) return 'Quarti di finale'
  return `Turno ${turno}`
}

export function MatchIntro({ membership, fixture, data, homeTeam, awayTeam, homeCrestUrl, awayCrestUrl, onSkip, onFinish, onClose }: Props) {
  const league = membership.league
  const [pronto, setPronto] = useState(false)
  const [fase, setFase] = useState<FaseSquadra>('regular')
  const [bracket, setBracket] = useState<InfoBracket | null>(null)
  const [tiesDelTurno, setTiesDelTurno] = useState<BracketTie[]>([])
  const [indiceBeat, setIndiceBeat] = useState(0)
  const [lineups, setLineups] = useState<Map<number, Lineup>>(new Map())
  const [giocatori, setGiocatori] = useState<Map<number, Giocatore>>(new Map())

  const beats = BEATS_PER_FASE[fase]
  const beat = beats[indiceBeat] ?? beats[beats.length - 1]

  // Fase della partita: dal tabellone se fa parte di un turno playoff,
  // altrimenti stagione regolare. Un match playoff coinvolge sempre due
  // squadre nello stesso tabellone, quindi la fase e' quella dell'incontro.
  useEffect(() => {
    let vivo = true
    async function carica() {
      if (!fixture.bracket_tie_id) {
        if (vivo) { setFase('regular'); setPronto(true) }
        return
      }
      const { data: tie } = await supabase.from('bracket_ties').select('bracket_id, turno').eq('id', fixture.bracket_tie_id).single()
      if (!tie || !vivo) return
      const [{ data: bracketRow }, { data: tutte }] = await Promise.all([
        supabase.from('brackets').select('tipo').eq('id', tie.bracket_id).single(),
        supabase.from('bracket_ties').select('*').eq('bracket_id', tie.bracket_id),
      ])
      if (!vivo) return
      const tipoBracket = (bracketRow?.tipo as FaseSquadra | undefined) ?? 'regular'
      const turniTotali = turniTotaliDa((tutte ?? []) as BracketTie[])
      setFase(tipoBracket)
      setBracket({ tipo: tipoBracket, bracketId: tie.bracket_id, turno: tie.turno, turniTotali, etichettaTurno: etichettaTurno(tie.turno, turniTotali) })
      // Solo il turno di questa partita: il tabellone completo su piu' round
      // non ci sta in una battuta da pochi secondi. L'esito di QUESTA sfida
      // non deve trapelare (l'utente non l'ha ancora "vista"), anche se in
      // tabella risulta gia' concluso: lo si maschera al momento del render.
      setTiesDelTurno(((tutte ?? []) as BracketTie[]).filter((riga) => riga.turno === tie.turno))
      setPronto(true)
    }
    void carica()
    return () => { vivo = false }
  }, [fixture.bracket_tie_id])

  // Formazioni delle due squadre per questa giornata, con nome e foto di chi
  // e' sceso in campo: senza, la presentazione mostrerebbe solo dei ruoli.
  useEffect(() => {
    let vivo = true
    async function carica() {
      const { data: righeLineup } = await supabase.from('lineups').select('team_id, modulo, titolari')
        .eq('league_id', fixture.league_id).eq('giornata', fixture.giornata)
        .in('team_id', [fixture.home_team_id, fixture.away_team_id])
      if (!vivo) return
      const mappaLineup = new Map<number, Lineup>((righeLineup ?? []).map((riga) => [riga.team_id, { modulo: riga.modulo, titolari: riga.titolari as number[] }]))
      setLineups(mappaLineup)

      const idsIstanze = [...mappaLineup.values()].flatMap((lineup) => lineup.titolari).filter((id) => id > 0)
      if (idsIstanze.length === 0) return
      const { data: istanze } = await supabase.from('player_instances').select('id, player_id').in('id', idsIstanze)
      if (!vivo || !istanze) return
      const idGiocatori = [...new Set(istanze.map((istanza) => istanza.player_id))]
      const { data: catalogo } = idGiocatori.length
        ? await supabase.from('players').select('id, nome, foto_url').in('id', idGiocatori)
        : { data: [] }
      if (!vivo) return
      const anagraficaPerGiocatore = new Map((catalogo ?? []).map((giocatore) => [giocatore.id, giocatore]))
      const vociGrezze = istanze.map((istanza) => {
        const anagrafica = anagraficaPerGiocatore.get(istanza.player_id)
        return anagrafica ? [istanza.id, anagrafica] as const : null
      }).filter((voce): voce is readonly [number, { id: number; nome: string; foto_url: string | null }] => voce != null)

      const foto = await Promise.all(vociGrezze.map(async ([id, anagrafica]) => [id, await firmaFoto(anagrafica.foto_url)] as const))
      const fotoPerIstanza = new Map(foto)
      if (vivo) setGiocatori(new Map(vociGrezze.map(([id, anagrafica]) => [id, { nome: anagrafica.nome, foto: fotoPerIstanza.get(id) }])))
    }
    void carica()
    return () => { vivo = false }
  }, [fixture.league_id, fixture.giornata, fixture.home_team_id, fixture.away_team_id])

  // Timer della scaletta: parte solo quando la fase e' nota, perche' stagione
  // regolare e playoff hanno durate diverse per ogni battuta. Un solo
  // effetto, non uno per battuta, per non doverli concatenare a mano.
  useEffect(() => {
    if (!pronto) return
    const timers: number[] = []
    let cumulativo = 0
    beats.forEach((singolo, indice) => {
      if (indice > 0) timers.push(window.setTimeout(() => setIndiceBeat(indice), cumulativo * 1000))
      cumulativo += singolo.durata
    })
    timers.push(window.setTimeout(() => onFinish(), cumulativo * 1000))
    return () => timers.forEach((id) => window.clearTimeout(id))
  }, [pronto, fase, beats, onFinish])

  const squadraInScena = beat.lato === 'away' ? awayTeam : homeTeam
  const crestInScena = beat.lato === 'away' ? awayCrestUrl : homeCrestUrl
  const lineupInScena = squadraInScena ? lineups.get(squadraInScena.id) : undefined

  const righe = useMemo(
    () => lineupInScena ? righeFormazione(lineupInScena.modulo, lineupInScena.titolari) : [],
    [lineupInScena],
  )
  // Ordine di comparsa globale (dal portiere agli attaccanti) per calcolare
  // il ritardo di ciascuno slot: un unico contatore che attraversa tutte le
  // righe, non un indice per riga.
  const ordineComparsa = useMemo(() => {
    const mappa = new Map<number, number>()
    let contatore = 0
    for (const riga of righe) for (const slot of riga) { mappa.set(slot.index, contatore); contatore += 1 }
    return mappa
  }, [righe])
  const totaleSlot = Math.max(1, ordineComparsa.size)
  const margineFineBattuta = 1 // secondi di margine prima della fine della battuta, cosi' l'ultimo giocatore resta visibile

  const classificaPrecedente = useMemo(
    () => classificaFinoA(data.fixtures, data.matchByFixture, data.teams.map((team) => team.id), fixture.giornata),
    [data.fixtures, data.matchByFixture, data.teams, fixture.giornata]
  )

  // Finche' non si sa se e' regular o playoff si mostra solo il fondale
  // neutro: `fase` parte da 'regular', quindi renderizzare subito faceva
  // lampeggiare per un istante sfondo, musica e logo della stagione
  // regolare prima di correggersi con quelli dei playoff.
  if (!pronto) {
    return (
      <div className="match-intro" role="dialog" aria-modal="true" aria-label="Presentazione della partita">
        <button className="match-intro__chiudi" type="button" onClick={onClose} aria-label="Chiudi">×</button>
      </div>
    )
  }

  return (
    <div className="match-intro" role="dialog" aria-modal="true" aria-label="Presentazione della partita">
      <audio src={MUSICA_FASE[fase]} autoPlay loop />
      <div className="match-intro__sfondo" data-fase={fase} />
      <button className="match-intro__chiudi" type="button" onClick={onClose} aria-label="Chiudi">×</button>
      <button className="match-intro__salta" type="button" onClick={onSkip}>Salta intro ›</button>

      {beat.tipo === 'locandina' && (
        <div className="match-intro__locandina">
          <img className="match-intro__logo-fase" src={LOGO_FASE[fase]} alt="" />
          <p className="match-intro__competizione">{league?.nome}</p>
          <div className="match-intro__sfida">
            <div className="match-intro__sfida-squadra">
              <Crest value={homeTeam?.stemma_url ?? null} imageUrl={homeCrestUrl} size="large" />
              <strong>{homeTeam?.nome ?? 'Casa'}</strong>
            </div>
            <span className="match-intro__vs">VS</span>
            <div className="match-intro__sfida-squadra">
              <Crest value={awayTeam?.stemma_url ?? null} imageUrl={awayCrestUrl} size="large" />
              <strong>{awayTeam?.nome ?? 'Ospite'}</strong>
            </div>
          </div>
          <p className="match-intro__turno">{bracket ? bracket.etichettaTurno : `Giornata ${fixture.giornata} di ${league?.giornate_totali ?? '—'}`}</p>
        </div>
      )}

      {beat.tipo === 'classifica' && (
        <div className="match-intro__classifica" style={{ '--n-squadre': classificaPrecedente.length } as React.CSSProperties}>
          <p className="match-intro__classifica-titolo">Classifica · Prima della giornata {fixture.giornata}</p>
          <ol>
            {classificaPrecedente.map((riga) => {
              const evidenziata = riga.teamId === fixture.home_team_id || riga.teamId === fixture.away_team_id
              const squadra = data.teamById.get(riga.teamId)
              return (
                <li className={evidenziata ? 'is-evidenziata' : ''} key={riga.teamId}>
                  <span className="match-intro__classifica-pos">{riga.posizione}</span>
                  <Crest value={squadra?.stemma_url ?? null} imageUrl={data.crestUrlByTeamId.get(riga.teamId)} size="small" />
                  <strong>{squadra?.nome ?? 'Squadra'}</strong>
                  <b>{riga.punti}</b>
                </li>
              )
            })}
          </ol>
        </div>
      )}

      {beat.tipo === 'tabellone' && bracket && (
        <div className="match-intro__tabellone">
          {/* Stesso marchio della locandina: era l'unica battuta dei playoff
              senza, e si perdeva il riferimento alla competizione. */}
          <img className="match-intro__logo-fase" src={LOGO_FASE[fase]} alt="" />
          <p className="match-intro__classifica-titolo">{bracket.tipo === 'title' ? 'Title Playoff' : 'Draft Playoff'} · {bracket.etichettaTurno}</p>
          <div className="match-intro__tie-lista">
            {tiesDelTurno.map((tie) => {
              // La sfida in corso non deve mai rivelare il proprio esito qui,
              // anche se in tabella risultasse gia' concluso: l'utente non
              // l'ha ancora "vista" finche' non arriva a questo punto.
              const eQuestaSfida = tie.id === fixture.bracket_tie_id
              const alta = tie.alta_team_id ? data.teamById.get(tie.alta_team_id) : undefined
              const bassa = tie.bassa_team_id ? data.teamById.get(tie.bassa_team_id) : undefined
              const concluso = !eQuestaSfida && tie.stato === 'concluso'
              return (
                <div className={`match-intro__tie ${eQuestaSfida ? 'is-in-corso' : ''}`} key={tie.id}>
                  <div className="match-intro__tie-squadra">
                    <Crest value={alta?.stemma_url ?? null} imageUrl={alta ? data.crestUrlByTeamId.get(alta.id) : undefined} size="small" />
                    <span className={concluso && tie.vincitore_team_id === alta?.id ? 'is-vincitrice' : ''}>{alta?.nome ?? 'Da definire'}</span>
                  </div>
                  <span className="match-intro__tie-stato">{eQuestaSfida ? 'IN CORSO' : concluso ? '—' : 'da giocare'}</span>
                  <div className="match-intro__tie-squadra match-intro__tie-squadra--destra">
                    <span className={concluso && tie.vincitore_team_id === bassa?.id ? 'is-vincitrice' : ''}>{bassa?.nome ?? 'Da definire'}</span>
                    <Crest value={bassa?.stemma_url ?? null} imageUrl={bassa ? data.crestUrlByTeamId.get(bassa.id) : undefined} size="small" />
                  </div>
                </div>
              )
            })}
          </div>
        </div>
      )}

      {beat.tipo === 'formazione' && squadraInScena && (
        <div className="match-intro__formazione" key={beat.lato}>
          <header className="match-intro__formazione-testa">
            <Crest value={squadraInScena.stemma_url ?? null} imageUrl={crestInScena} size="small" />
            <div>
              <strong>{squadraInScena.nome}</strong>
              {lineupInScena && <small>{lineupInScena.modulo}</small>}
            </div>
          </header>
          <div className="match-intro__righe">
            <div className="match-intro__campo" aria-hidden="true">
              <span className="match-intro__campo-linea" />
              <span className="match-intro__campo-cerchio" />
            </div>
            {righe.map((riga, indiceRiga) => (
              <div className="match-intro__riga" key={indiceRiga}>
                {riga.map((slot) => {
                  const giocatore = slot.valore ? giocatori.get(slot.valore) : undefined
                  const ritardo = ((ordineComparsa.get(slot.index) ?? 0) / totaleSlot) * Math.max(1, beat.durata - margineFineBattuta)
                  return (
                    <div className="match-intro__giocatore" style={{ animationDelay: `${ritardo}s` }} key={slot.index}>
                      <div className="match-intro__giocatore-foto">
                        {giocatore?.foto ? <img src={giocatore.foto} alt="" /> : <span aria-hidden="true">{giocatore ? giocatore.nome.charAt(0) : '?'}</span>}
                      </div>
                      <span className="match-intro__giocatore-ruolo">{slot.slot}</span>
                      <strong>{giocatore ? cognome(giocatore.nome) : '—'}</strong>
                    </div>
                  )
                })}
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  )
}
