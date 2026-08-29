import { useEffect, useMemo, useRef, useState } from 'react'
import { supabase } from '../lib/supabase'
import { cognome } from '../lib/nomi'
import { ricostruisciEventiStorici, type StatEventoStorico } from '../lib/matchEvents'
import { useSeasonData } from '../lib/useSeasonData'
import { SFONDO_FASE_VERTICALE, type FaseSquadra } from '../lib/faseSquadra'
import { isEventoGol, type EventoPartita, type Membership } from '../types'
import { Crest } from './Crest'
import { MatchIntro } from './MatchIntro'

type Props = { membership: Membership; matchId: number; onClose: () => void; onRevealed: (matchId: number) => void; onOpenReport: () => void }
type Player = { id: number; nome: string }

// Le cronache salvate dal backend piu' recente hanno sempre `minuto`. Alcune
// partite gia' registrate (o scritte durante un deploy parziale) possono pero'
// contenere `null`: in JavaScript `null <= 2` e' vero, e tutti gli eventi
// finirebbero visibili gia' al secondo minuto. Prima del reveal rendiamo il
// dato sicuro usando il blocco da 15 minuti che accompagna ogni evento.
function normalizzaMinuti(eventi: EventoPartita[]) {
  const gruppi = new Map<number, number[]>()
  eventi.forEach((evento, indice) => {
    const minuto = Number(evento.minuto)
    if (Number.isInteger(minuto) && minuto >= 1 && minuto <= 90) return
    const bloccoLetto = Number(evento.blocco)
    const blocco = Number.isInteger(bloccoLetto) && bloccoLetto >= 1 && bloccoLetto <= 6
      ? bloccoLetto
      : Math.min(6, Math.floor(indice * 6 / Math.max(1, eventi.length)) + 1)
    const gruppo = gruppi.get(blocco) ?? []
    gruppo.push(indice)
    gruppi.set(blocco, gruppo)
  })

  const minutiRicostruiti = new Map<number, number>()
  for (const [blocco, gruppo] of gruppi) {
    gruppo.forEach((indice, posizione) => {
      // Li distribuiamo nel blocco, anziche' assegnarli tutti al suo primo
      // minuto: cosi' la cronaca conserva un ritmo naturale anche nel raro
      // caso di dati incompleti.
      minutiRicostruiti.set(indice, (blocco - 1) * 15 + Math.ceil((posizione + 1) * 15 / (gruppo.length + 1)))
    })
  }

  return eventi.map((evento, indice) => {
    const minuto = Number(evento.minuto)
    return Number.isInteger(minuto) && minuto >= 1 && minuto <= 90
      ? evento
      : { ...evento, minuto: minutiRicostruiti.get(indice) ?? 90 }
  }).sort((sinistra, destra) => sinistra.minuto - destra.minuto || sinistra.team_id - destra.team_id)
}

function testoEvento(evento: EventoPartita, nomi: Map<number, Player>) {
  const nome = (id: number) => cognome(nomi.get(id)?.nome ?? `Giocatore ${id}`)
  if (isEventoGol(evento)) return <><strong>GOOOL!</strong> {nome(evento.marcatore)} la mette dentro.</>
  if (evento.tipo === 'tiro_parato') return <>Il tiro di <strong>{nome(evento.giocatore)}</strong> viene parato.</>
  if (evento.tipo === 'tiro_fuori') return <>Il tiro di <strong>{nome(evento.giocatore)}</strong> termina fuori.</>
  if (evento.tipo === 'infortunio') return <><strong>{nome(evento.esce)}</strong> si infortuna ed esce. Al suo posto <strong>{nome(evento.entra)}</strong>.</>
  if (evento.tipo === 'sostituzione') return <><strong>{nome(evento.esce)}</strong> viene sostituito da <strong>{nome(evento.entra)}</strong>.</>
  return null
}

// Gol, infortuni e sostituzioni restano fissi in cronaca; solo i tiri
// (parati o fuori) sono eventi minori che altrimenti riempirebbero la
// lista, e scompaiono da soli qualche secondo dopo essere comparsi
// (is-transitorio, vedi l'animazione di uscita in styles.css). L'engine non
// modella ancora ammonizioni/espulsioni: quando arriveranno andranno
// aggiunte qui fra i permanenti, non fra i transitori.
function classeEvento(evento: EventoPartita): string {
  if (isEventoGol(evento)) return 'is-goal'
  if (evento.tipo === 'infortunio' || evento.tipo === 'sostituzione') return ''
  return 'is-transitorio'
}

export function MatchReveal({ membership, matchId, onClose, onRevealed, onOpenReport }: Props) {
  const data = useSeasonData(membership)
  const match = data.matches.find((item) => item.id === matchId)
  const fixture = match ? data.fixtures.find((item) => item.id === match.fixture_id) : undefined
  const [nomi, setNomi] = useState<Map<number, Player>>(new Map())
  const [statsStoriche, setStatsStoriche] = useState<StatEventoStorico[]>([])
  const revealRegistrato = useRef(false)
  // Un secondo reale per ogni minuto di gioco: il reveal non salta da
  // un'azione all'altra, ma percorre tutta la partita come una cronaca.
  const [minutoCorrente, setMinutoCorrente] = useState(-1)
  // Fase della partita, solo per lo sfondo a vetro dietro la cronaca (stessa
  // immagine dell'intro): non serve il dettaglio del tabellone qui, solo
  // sapere quale delle tre immagini di fase mostrare.
  const [fase, setFase] = useState<FaseSquadra>('regular')

  useEffect(() => {
    let vivo = true
    async function carica() {
      if (!fixture?.bracket_tie_id) { if (vivo) setFase('regular'); return }
      const { data: tie } = await supabase.from('bracket_ties').select('bracket_id').eq('id', fixture.bracket_tie_id).single()
      if (!tie || !vivo) return
      const { data: bracket } = await supabase.from('brackets').select('tipo').eq('id', tie.bracket_id).single()
      if (vivo) setFase((bracket?.tipo as FaseSquadra | undefined) ?? 'regular')
    }
    void carica()
    return () => { vivo = false }
  }, [fixture?.bracket_tie_id])

  const eventi = useMemo(() => {
    if (!match) return []
    const estesa = match.blocchi.some((evento) => !isEventoGol(evento))
    if (estesa || !fixture) return normalizzaMinuti([...match.blocchi])
    return normalizzaMinuti(ricostruisciEventiStorici(match.blocchi, statsStoriche, match.titolari_home, match.titolari_away, fixture.home_team_id, fixture.away_team_id, match.id))
  }, [fixture, match, statsStoriche])
  const inCorso = minutoCorrente >= 0 && minutoCorrente < 90
  const completata = minutoCorrente >= 90
  const minuto = Math.max(0, minutoCorrente)
  const punteggio = eventi.filter((evento) => evento.minuto <= minuto).reduce((totale, evento) => {
    if (isEventoGol(evento)) {
      if (evento.lato === 'casa') totale.casa++
      else totale.ospite++
    }
    return totale
  }, { casa: 0, ospite: 0 })

  useEffect(() => {
    if (!match || match.blocchi.some((evento) => !isEventoGol(evento))) return
    const idPartita = match.id
    let attivo = true
    async function caricaStatisticheStoriche() {
      const { data: righe } = await supabase.from('match_stats').select('team_id, player_instance_id, minuti, gol, tiri, tiri_porta').eq('match_id', idPartita)
      if (attivo) setStatsStoriche((righe ?? []) as StatEventoStorico[])
    }
    void caricaStatisticheStoriche()
    return () => { attivo = false }
  }, [match])

  useEffect(() => {
    const ids = [...new Set(eventi.flatMap((evento) => isEventoGol(evento)
      ? [evento.marcatore, ...(evento.assist ? [evento.assist] : [])]
      : evento.tipo === 'sostituzione' || evento.tipo === 'infortunio' ? [evento.esce, evento.entra] : [evento.giocatore]))]
    if (!ids.length) return
    let attivo = true
    async function caricaNomi() {
      const { data: istanze, error } = await supabase.from('player_instances').select('id, player_id').in('id', ids)
      if (error || !attivo) return
      const playerIds = [...new Set((istanze ?? []).map((istanza) => istanza.player_id))]
      const { data: giocatori } = playerIds.length ? await supabase.from('players').select('id, nome').in('id', playerIds) : { data: [] }
      if (!attivo) return
      const perCatalogo = new Map((giocatori ?? []).map((giocatore) => [giocatore.id, giocatore as Player]))
      setNomi(new Map((istanze ?? []).flatMap((istanza) => {
        const giocatore = perCatalogo.get(istanza.player_id)
        return giocatore ? [[istanza.id, giocatore] as const] : []
      })))
    }
    void caricaNomi()
    return () => { attivo = false }
  }, [eventi])

  useEffect(() => {
    if (minutoCorrente < 0 || minutoCorrente >= 90) return
    const timer = window.setTimeout(() => setMinutoCorrente((valore) => valore + 1), 700)
    return () => window.clearTimeout(timer)
  }, [minutoCorrente])

  useEffect(() => {
    if (minutoCorrente < 90 || revealRegistrato.current) return
    revealRegistrato.current = true
    onRevealed(matchId)
  }, [matchId, minutoCorrente, onRevealed])

  if (data.loading || !match || !fixture) return null
  const casa = data.teamById.get(fixture.home_team_id)
  const ospite = data.teamById.get(fixture.away_team_id)
  const visibili = eventi.filter((evento) => evento.minuto <= minuto)

  // L'intro (musica di fase, locandina, formazioni) precede il calcio
  // d'inizio solo quando c'e' davvero una cronaca da vivere: per le partite
  // simulate prima della cronaca estesa non avrebbe nulla da presentare.
  if (minutoCorrente < 0 && eventi.length > 0) {
    return <MatchIntro
      membership={membership}
      fixture={fixture}
      data={data}
      homeTeam={casa}
      awayTeam={ospite}
      homeCrestUrl={data.crestUrlByTeamId.get(fixture.home_team_id)}
      awayCrestUrl={data.crestUrlByTeamId.get(fixture.away_team_id)}
      onSkip={() => setMinutoCorrente(0)}
      onFinish={() => setMinutoCorrente(0)}
      onClose={onClose}
    />
  }

  return <div className="match-reveal-backdrop" role="dialog" aria-modal="true" aria-label="Cronaca della partita">
    <section className="match-reveal">
      <div className="match-reveal__sfondo" style={{ backgroundImage: `url(${SFONDO_FASE_VERTICALE[fase]})` }} />
      <button className="match-reveal__close" type="button" onClick={onClose} aria-label="Chiudi cronaca">×</button>
      <header className="match-reveal__header">
        <div><Crest value={casa?.stemma_url ?? null} imageUrl={data.crestUrlByTeamId.get(fixture.home_team_id)} size="small" /><strong>{casa?.nome}</strong></div>
        <div className="match-reveal__score">
          <small>{completata ? 'RISULTATO FINALE' : <><i className="match-reveal__live-dot" aria-hidden="true" />{minuto}’</>}</small>
          <b>{punteggio.casa} <i>–</i> {punteggio.ospite}</b>
        </div>
        <div><strong>{ospite?.nome}</strong><Crest value={ospite?.stemma_url ?? null} imageUrl={data.crestUrlByTeamId.get(fixture.away_team_id)} size="small" /></div>
      </header>

      {eventi.length === 0 ? <div className="match-reveal__empty"><p>Questa partita è stata simulata prima della cronaca estesa.</p><button className="button button--primary" type="button" onClick={onOpenReport}>Vedi risultato</button></div> : <>
        <div className="match-reveal__pitch" aria-label={`Minuto ${minuto} su 90`}>
          <div className="match-reveal__half match-reveal__half--first">1º TEMPO</div>
          <div className="match-reveal__half match-reveal__half--second">2º TEMPO</div>
          <div className="match-reveal__line">
            <span style={{ height: `${Math.min(100, minuto / 90 * 100)}%` }} />
            <b className={`match-reveal__minute ${inCorso ? 'is-live' : ''}`} style={{ top: `${Math.min(100, minuto / 90 * 100)}%` }}>{minuto}’</b>
          </div>
          {[15, 30, 45, 60, 75, 90].map((tacca) => (
            <span className={`match-reveal__marker ${tacca === 45 || tacca === 90 ? 'is-forte' : ''}`} style={{ top: `${tacca / 90 * 100}%` }} key={tacca}>{tacca}’</span>
          ))}
          <div className="match-reveal__events match-reveal__events--home">{visibili.filter((evento) => evento.lato === 'casa').map((evento, i) => <p className={classeEvento(evento)} key={`${evento.minuto}-${i}`}><time>{evento.minuto}’</time>{testoEvento(evento, nomi)}</p>)}</div>
          <div className="match-reveal__events match-reveal__events--away">{visibili.filter((evento) => evento.lato === 'ospite').map((evento, i) => <p className={classeEvento(evento)} key={`${evento.minuto}-${i}`}><time>{evento.minuto}’</time>{testoEvento(evento, nomi)}</p>)}</div>
        </div>
        <footer className="match-reveal__footer">
          {inCorso ? <span className="match-reveal__in-corso"><i aria-hidden="true" />La partita è in corso…</span>
            : <button className="button button--primary" type="button" onClick={onOpenReport}>Vedi rapporto partita</button>}
        </footer>
      </>}
    </section>
  </div>
}
