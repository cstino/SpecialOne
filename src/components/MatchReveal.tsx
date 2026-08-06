import { useEffect, useMemo, useRef, useState } from 'react'
import { supabase } from '../lib/supabase'
import { cognome } from '../lib/nomi'
import { useSeasonData } from '../lib/useSeasonData'
import { isEventoGol, type EventoPartita, type Membership } from '../types'
import { Crest } from './Crest'

type Props = { membership: Membership; matchId: number; onClose: () => void; onRevealed: (matchId: number) => void; onOpenReport: () => void }
type Player = { id: number; nome: string }
type StatStorica = { team_id: number; player_instance_id: number; minuti: number; gol: number; tiri: number; tiri_porta: number }

function creaRng(seme: number) {
  let stato = seme >>> 0
  return () => { stato = (stato * 1664525 + 1013904223) >>> 0; return stato / 4294967296 }
}

// Le vecchie partite hanno solo i gol salvati in cronaca, ma possiedono gia'
// minutaggio e tiri individuali. Li usiamo per ricostruire highlights reali
// (mai numeri aggiuntivi) finche' le nuove simulazioni non salvano tutto.
function ricostruisciStorico(gol: EventoPartita[], stats: StatStorica[], titolariCasa: number[], titolariOspite: number[], teamCasa: number, teamOspite: number, seed: number) {
  const rnd = creaRng(seed)
  // I minuti dei gol delle partite storiche erano assegnati in presentazione.
  // Se un marcatore era un subentrato, il vecchio minuto puo' cadere prima del
  // suo ingresso: lo riportiamo quindi nel suo intervallo effettivo di gioco.
  const intervalloGioco = (teamId: number, giocatoreId: number) => {
    const stat = stats.find((riga) => riga.team_id === teamId && riga.player_instance_id === giocatoreId)
    const titolari = teamId === teamCasa ? titolariCasa : titolariOspite
    if (!stat || !titolari.length || stat.minuti <= 0) return null
    return titolari.includes(giocatoreId)
      ? { da: 1, a: stat.minuti }
      : { da: Math.max(1, 90 - stat.minuti), a: 90 }
  }
  const eventi: EventoPartita[] = gol.map((evento) => {
    if (!isEventoGol(evento)) return evento
    const intervallo = intervalloGioco(evento.team_id, evento.marcatore)
    if (!intervallo || (evento.minuto >= intervallo.da && evento.minuto <= intervallo.a)) return evento
    return { ...evento, minuto: evento.minuto < intervallo.da ? intervallo.da : intervallo.a, blocco: Math.ceil((evento.minuto < intervallo.da ? intervallo.da : intervallo.a) / 15) }
  })
  for (const [lato, teamId, titolari] of [['casa', teamCasa, titolariCasa], ['ospite', teamOspite, titolariOspite]] as const) {
    const righe = stats.filter((stat) => stat.team_id === teamId)
    if (!righe.length) continue
    const azioni: Array<{ tipo: 'tiro_parato' | 'tiro_fuori'; giocatore: number; minuti: number }> = []
    for (const stat of righe) {
      for (let i = 0; i < Math.max(0, stat.tiri_porta - stat.gol); i++) azioni.push({ tipo: 'tiro_parato', giocatore: stat.player_instance_id, minuti: stat.minuti })
      for (let i = 0; i < Math.max(0, stat.tiri - stat.tiri_porta); i++) azioni.push({ tipo: 'tiro_fuori', giocatore: stat.player_instance_id, minuti: stat.minuti })
    }
    // Sono highlights, non il feed di ogni singolo tiro: al massimo quattro
    // per squadra, tutti comunque supportati dalle statistiche registrate.
    for (const azione of azioni.sort(() => rnd() - .5).slice(0, 4)) {
      const eTitolare = titolari.includes(azione.giocatore)
      const minimo = eTitolare ? 1 : Math.max(1, 90 - azione.minuti)
      const massimo = eTitolare ? Math.max(minimo, azione.minuti) : 90
      const minuto = minimo + Math.floor(rnd() * (massimo - minimo + 1))
      eventi.push({ tipo: azione.tipo, minuto, blocco: Math.ceil(minuto / 15), lato, team_id: teamId, giocatore: azione.giocatore })
    }
    const subentratiGiaUsati = new Set<number>()
    for (const titolare of righe.filter((stat) => titolari.includes(stat.player_instance_id) && stat.minuti > 0 && stat.minuti < 90)) {
      const entra = righe.find((stat) => !titolari.includes(stat.player_instance_id)
        && !subentratiGiaUsati.has(stat.player_instance_id)
        && stat.minuti === 90 - titolare.minuti)
      if (entra) {
        subentratiGiaUsati.add(entra.player_instance_id)
        eventi.push({ tipo: 'sostituzione', minuto: titolare.minuti, blocco: Math.ceil(titolare.minuti / 15), lato, team_id: teamId, esce: titolare.player_instance_id, entra: entra.player_instance_id })
      }
    }
  }
  return eventi.sort((sinistra, destra) => sinistra.minuto - destra.minuto || sinistra.team_id - destra.team_id)
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

export function MatchReveal({ membership, matchId, onClose, onRevealed, onOpenReport }: Props) {
  const data = useSeasonData(membership)
  const match = data.matches.find((item) => item.id === matchId)
  const fixture = match ? data.fixtures.find((item) => item.id === match.fixture_id) : undefined
  const [nomi, setNomi] = useState<Map<number, Player>>(new Map())
  const [statsStoriche, setStatsStoriche] = useState<StatStorica[]>([])
  const revealRegistrato = useRef(false)
  // Un secondo reale per ogni minuto di gioco: il reveal non salta da
  // un'azione all'altra, ma percorre tutta la partita come una cronaca.
  const [minutoCorrente, setMinutoCorrente] = useState(-1)

  const eventi = useMemo(() => {
    if (!match) return []
    const estesa = match.blocchi.some((evento) => !isEventoGol(evento))
    if (estesa || !fixture) return [...match.blocchi].sort((sinistra, destra) => sinistra.minuto - destra.minuto || sinistra.team_id - destra.team_id)
    return ricostruisciStorico(match.blocchi, statsStoriche, match.titolari_home, match.titolari_away, fixture.home_team_id, fixture.away_team_id, match.id)
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
      if (attivo) setStatsStoriche((righe ?? []) as StatStorica[])
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
    const timer = window.setTimeout(() => setMinutoCorrente((valore) => valore + 1), 1000)
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

  return <div className="match-reveal-backdrop" role="dialog" aria-modal="true" aria-label="Cronaca della partita">
    <section className="match-reveal">
      <button className="match-reveal__close" type="button" onClick={onClose} aria-label="Chiudi cronaca">×</button>
      <header className="match-reveal__header">
        <div><Crest value={casa?.stemma_url ?? null} imageUrl={data.crestUrlByTeamId.get(fixture.home_team_id)} size="small" /><strong>{casa?.nome}</strong></div>
        <div className="match-reveal__score"><small>{minutoCorrente < 0 ? 'IN ATTESA DEL CALCIO D’INIZIO' : completata ? 'RISULTATO FINALE' : `${minuto}’`}</small><b>{punteggio.casa} <i>–</i> {punteggio.ospite}</b></div>
        <div><strong>{ospite?.nome}</strong><Crest value={ospite?.stemma_url ?? null} imageUrl={data.crestUrlByTeamId.get(fixture.away_team_id)} size="small" /></div>
      </header>

      {eventi.length === 0 ? <div className="match-reveal__empty"><p>Questa partita è stata simulata prima della cronaca estesa.</p><button className="button button--primary" type="button" onClick={onOpenReport}>Vedi risultato</button></div> : <>
        <div className="match-reveal__pitch" aria-label={`Minuto ${minuto} su 90`}>
          <div className="match-reveal__half match-reveal__half--first">1º TEMPO</div>
          <div className="match-reveal__half match-reveal__half--second">2º TEMPO</div>
          <div className="match-reveal__line">
            <span style={{ height: `${Math.min(100, minuto / 90 * 100)}%` }} />
            <b className="match-reveal__minute" style={{ top: `${Math.min(100, minuto / 90 * 100)}%` }}>{minuto}’</b>
          </div>
          <span className="match-reveal__marker match-reveal__marker--half">45’</span><span className="match-reveal__marker match-reveal__marker--end">90’</span>
          <div className="match-reveal__events match-reveal__events--home">{visibili.filter((evento) => evento.lato === 'casa').map((evento, i) => <p className={isEventoGol(evento) ? 'is-goal' : ''} key={`${evento.minuto}-${i}`}><time>{evento.minuto}’</time>{testoEvento(evento, nomi)}</p>)}</div>
          <div className="match-reveal__events match-reveal__events--away">{visibili.filter((evento) => evento.lato === 'ospite').map((evento, i) => <p className={isEventoGol(evento) ? 'is-goal' : ''} key={`${evento.minuto}-${i}`}><time>{evento.minuto}’</time>{testoEvento(evento, nomi)}</p>)}</div>
        </div>
        <footer className="match-reveal__footer">
          {minutoCorrente < 0 ? <button className="button button--primary" type="button" onClick={() => setMinutoCorrente(0)}>Calcio d’inizio</button>
            : inCorso ? <span>La partita è in corso…</span>
              : <button className="button button--primary" type="button" onClick={onOpenReport}>Vedi rapporto partita</button>}
        </footer>
      </>}
    </section>
  </div>
}
