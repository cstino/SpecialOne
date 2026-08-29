import { useEffect, useMemo, useState } from 'react'
import { supabase } from '../lib/supabase'
import { cognome } from '../lib/nomi'
import { MUSICA_FASE, type FaseSquadra } from '../lib/faseSquadra'
import { righeFormazione } from '../lib/formazioni'
import { firmaFoto } from './RosaElenco'
import type { useSeasonData } from '../lib/useSeasonData'
import type { BracketTie, Fixture, Membership, Team } from '../types'
import { Crest } from './Crest'

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
      const turniTotali = (tutte ?? []).reduce((massimo, riga) => Math.max(massimo, riga.turno), 0)
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
      }).filter((voce): voce is readonly [number, { nome: string; foto_url: string | null }] => voce != null)

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

  return (
    <div className="match-intro" role="dialog" aria-modal="true" aria-label="Presentazione della partita">
      <audio src={MUSICA_FASE[fase]} autoPlay loop />
      <div className="match-intro__sfondo" data-fase={fase} />
      <button className="match-intro__chiudi" type="button" onClick={onClose} aria-label="Chiudi">×</button>
      <button className="match-intro__salta" type="button" onClick={onSkip}>Salta intro ›</button>

      {beat.tipo === 'locandina' && (
        <div className="match-intro__locandina">
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
        <div className="match-intro__classifica">
          <p className="match-intro__classifica-titolo">Classifica · Stagione regolare</p>
          <ol>
            {data.standings.map((riga, indice) => {
              const evidenziata = riga.team_id === fixture.home_team_id || riga.team_id === fixture.away_team_id
              const squadra = data.teamById.get(riga.team_id)
              return (
                <li className={evidenziata ? 'is-evidenziata' : ''} key={riga.team_id}>
                  <span className="match-intro__classifica-pos">{riga.posizione ?? indice + 1}</span>
                  <Crest value={squadra?.stemma_url ?? null} imageUrl={data.crestUrlByTeamId.get(riga.team_id)} size="small" />
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
