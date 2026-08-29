import { useEffect, useMemo, useState } from 'react'
import { supabase } from '../lib/supabase'
import { cognome } from '../lib/nomi'
import { MUSICA_FASE, type FaseSquadra } from '../lib/faseSquadra'
import { righeFormazione } from '../lib/formazioni'
import { firmaFoto } from './RosaElenco'
import type { Fixture, Membership, Team } from '../types'
import { Crest } from './Crest'

type Props = {
  membership: Membership
  fixture: Fixture
  homeTeam: Team | undefined
  awayTeam: Team | undefined
  homeCrestUrl: string | undefined
  awayCrestUrl: string | undefined
  onSkip: () => void
  onFinish: () => void
  onClose: () => void
}

type Beat = 'locandina' | 'home' | 'away'

type Lineup = { modulo: string; titolari: number[] }
type Giocatore = { nome: string; foto?: string }

// Stessa logica di nomeTurno in Tabellone.tsx: il nome del turno si legge da
// quanti ne restano, non da quanti ne sono passati.
function etichettaTurno(turno: number, turniTotali: number) {
  const mancanti = turniTotali - turno
  if (mancanti === 0) return 'Finale'
  if (mancanti === 1) return 'Semifinale'
  if (mancanti === 2) return 'Quarti di finale'
  return `Turno ${turno}`
}

export function MatchIntro({ membership, fixture, homeTeam, awayTeam, homeCrestUrl, awayCrestUrl, onSkip, onFinish, onClose }: Props) {
  const league = membership.league
  const [beat, setBeat] = useState<Beat>('locandina')
  const [fase, setFase] = useState<FaseSquadra>('regular')
  const [etichettaPartita, setEtichettaPartita] = useState('')
  const [lineups, setLineups] = useState<Map<number, Lineup>>(new Map())
  const [giocatori, setGiocatori] = useState<Map<number, Giocatore>>(new Map())

  // Scaletta fissa dei 25 secondi: 5 di locandina, 10 per ciascuna formazione.
  // Un solo effetto al mount, non uno per battuta: altrimenti ogni cambio di
  // `beat` riavvierebbe il proprio timer invece di lasciarli correre insieme.
  useEffect(() => {
    const t1 = window.setTimeout(() => setBeat('home'), 5000)
    const t2 = window.setTimeout(() => setBeat('away'), 15000)
    const t3 = window.setTimeout(() => onFinish(), 25000)
    return () => { window.clearTimeout(t1); window.clearTimeout(t2); window.clearTimeout(t3) }
  }, [onFinish])

  // Fase della partita (per musica e sfondo): dal tabellone se la partita fa
  // parte di un turno playoff, altrimenti stagione regolare. Un match
  // playoff coinvolge sempre due squadre nello stesso tabellone, quindi la
  // fase e' quella dell'incontro, non serve saperla per una squadra sola.
  useEffect(() => {
    let vivo = true
    async function carica() {
      if (!fixture.bracket_tie_id) {
        if (vivo) { setFase('regular'); setEtichettaPartita(`Giornata ${fixture.giornata} di ${league?.giornate_totali ?? '—'}`) }
        return
      }
      const { data: tie } = await supabase.from('bracket_ties').select('bracket_id, turno').eq('id', fixture.bracket_tie_id).single()
      if (!tie || !vivo) return
      const [{ data: bracket }, { data: tutte }] = await Promise.all([
        supabase.from('brackets').select('tipo').eq('id', tie.bracket_id).single(),
        supabase.from('bracket_ties').select('turno').eq('bracket_id', tie.bracket_id),
      ])
      if (!vivo) return
      const turniTotali = (tutte ?? []).reduce((massimo, riga) => Math.max(massimo, riga.turno), 0)
      setFase((bracket?.tipo as FaseSquadra | undefined) ?? 'regular')
      setEtichettaPartita(etichettaTurno(tie.turno, turniTotali))
    }
    void carica()
    return () => { vivo = false }
  }, [fixture.bracket_tie_id, fixture.giornata, league?.giornate_totali])

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

  const squadraInScena = beat === 'away' ? awayTeam : homeTeam
  const crestInScena = beat === 'away' ? awayCrestUrl : homeCrestUrl
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

  return (
    <div className="match-intro" role="dialog" aria-modal="true" aria-label="Presentazione della partita">
      <audio src={MUSICA_FASE[fase]} autoPlay loop />
      <div className="match-intro__sfondo" data-fase={fase} />
      <button className="match-intro__chiudi" type="button" onClick={onClose} aria-label="Chiudi">×</button>
      <button className="match-intro__salta" type="button" onClick={onSkip}>Salta intro ›</button>

      {beat === 'locandina' && (
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
          <p className="match-intro__turno">{etichettaPartita}</p>
        </div>
      )}

      {(beat === 'home' || beat === 'away') && squadraInScena && (
        <div className="match-intro__formazione" key={beat}>
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
                  const ritardo = ((ordineComparsa.get(slot.index) ?? 0) / totaleSlot) * 9
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
