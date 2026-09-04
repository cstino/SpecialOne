import { useEffect, useMemo, useRef, useState } from 'react'
import { supabase } from '../lib/supabase'
import { cognome } from '../lib/nomi'
import { ricostruisciEventiStorici, type StatEventoStorico } from '../lib/matchEvents'
import { useSeasonData } from '../lib/useSeasonData'
import { SFONDO_FASE_VERTICALE, type FaseSquadra } from '../lib/faseSquadra'
import { isEventoGol, type EventoGol, type EventoPartita, type Membership } from '../types'
import { Crest } from './Crest'
import { firmaFoto } from './RosaElenco'
import { MatchIntro } from './MatchIntro'

type Props = { membership: Membership; matchId: number; onClose: () => void; onRevealed: (matchId: number) => void; onOpenReport: () => void }
type Player = { id: number; nome: string; foto?: string }

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

// Tiri parati e fuori: gli unici eventi che non restano in cronaca. Sono
// anche gli unici di cui ha senso limitare il numero, perche' sono gli unici
// che si ripetono decine di volte nella stessa partita.
function eTransitorio(evento: EventoPartita): boolean {
  return evento.tipo === 'tiro_parato' || evento.tipo === 'tiro_fuori'
}

const MAX_TIRI_PER_SQUADRA = 15
// Quanti minuti di gioco un evento minore resta in cronaca prima di sparire.
// A 700ms al minuto sono ~2,8s reali: il tempo di leggerlo e di far
// completare la dissolvenza (che parte a 2s e dura 0,4s).
const MINUTI_VITA_TRANSITORIO = 4
// Card ad altezza fissa, tarata su due righe di testo piene (il minuto sta in
// linea, non sopra, proprio per stare in due righe): serve a poter calcolare
// la disposizione senza dover misurare ogni card prima di posizionarla.
const ALTEZZA_EVENTO = 54
const ALTEZZA_EVENTO_STRETTA = 46
const GAP_EVENTO = 6

// Cap dei tiri mostrati in cronaca (deciso con l'utente il 1 settembre 2026):
// una squadra puo' arrivare a 40-59 tiri in una partita, e mostrarli tutti
// trasforma la cronaca in un elenco. Ne teniamo al massimo 15 per squadra,
// presi a passo costante sulla sequenza: restano distribuiti su tutto l'arco
// della partita e la densita' relativa si conserva (se una squadra ha
// assediato l'area fra il 40' e il 45', da li' ne escono di piu' che da un
// quarto d'ora di nulla). Non cambia cosa e' successo davvero: le statistiche
// restano quelle vere in match_stats e stats_squadra, qui si decide soltanto
// che cosa scorre a schermo.
function limitaTiri(eventi: EventoPartita[]) {
  const perSquadra = new Map<number, EventoPartita[]>()
  for (const evento of eventi) {
    if (!eTransitorio(evento)) continue
    const lista = perSquadra.get(evento.team_id) ?? []
    lista.push(evento)
    perSquadra.set(evento.team_id, lista)
  }
  const tenuti = new Set<EventoPartita>()
  for (const lista of perSquadra.values()) {
    if (lista.length <= MAX_TIRI_PER_SQUADRA) { for (const evento of lista) tenuti.add(evento); continue }
    for (let i = 0; i < MAX_TIRI_PER_SQUADRA; i += 1) {
      tenuti.add(lista[Math.round(i * (lista.length - 1) / (MAX_TIRI_PER_SQUADRA - 1))])
    }
  }
  return eventi.filter((evento) => !eTransitorio(evento) || tenuti.has(evento))
}

// Il minuto 0 e il minuto 90 non stanno agli estremi assoluti del canvas:
// mezza card di margine sopra e sotto, cosi' il primo e l'ultimo evento non
// escono dal riquadro. La stessa mappatura vale per linea, tacche ed eventi:
// e' l'unico modo perche' restino allineati fra loro.
function posizioneMinuto(minuto: number, altezza: number, margine: number) {
  return margine + (Math.min(90, Math.max(0, minuto)) / 90) * Math.max(0, altezza - margine * 2)
}

// Ogni card parte dal proprio minuto sulla linea del tempo e scivola verso il
// basso solo quel tanto che serve a non sovrapporsi alla precedente (passata
// in avanti); se l'ultima sfora il fondo si risale spingendo verso l'alto
// (passata all'indietro). E' il posizionamento classico delle etichette su un
// asse: lo scostamento dal minuto vero resta minimo finche' gli eventi sono
// radi, e degrada in modo prevedibile quando si infittiscono. Il canvas e'
// sempre alto almeno quanto serve a contenerli tutti, quindi la passata
// all'indietro trova sempre una soluzione valida.
function disponiEventi(eventi: EventoPartita[], altezza: number, altezzaEvento: number, margine: number) {
  const posizioni = new Map<EventoPartita, number>()
  let cursore = margine
  for (const evento of eventi) {
    const top = Math.max(posizioneMinuto(evento.minuto, altezza, margine) - altezzaEvento / 2, cursore)
    posizioni.set(evento, top)
    cursore = top + altezzaEvento + GAP_EVENTO
  }
  if (cursore - GAP_EVENTO > altezza - margine) {
    let limite = altezza - margine
    for (let i = eventi.length - 1; i >= 0; i -= 1) {
      const top = Math.min(posizioni.get(eventi[i]) ?? 0, limite - altezzaEvento)
      posizioni.set(eventi[i], top)
      limite = top - GAP_EVENTO
    }
  }
  return posizioni
}

function testoEvento(evento: EventoPartita, nomi: Map<number, Player>) {
  const nome = (id: number) => cognome(nomi.get(id)?.nome ?? `Giocatore ${id}`)
  if (isEventoGol(evento)) return <><strong>GOOOL!</strong> {nome(evento.marcatore)} la mette dentro.</>
  if (evento.tipo === 'tiro_parato') return <>Il tiro di <strong>{nome(evento.giocatore)}</strong> viene parato.</>
  if (evento.tipo === 'tiro_fuori') return <>Il tiro di <strong>{nome(evento.giocatore)}</strong> termina fuori.</>
  // Testi tenuti corti apposta: la card della cronaca e' alta due righe fisse,
  // e la vecchia formulazione ("si infortuna ed esce. Al suo posto…") ne
  // occupava tre, quindi finiva troncata.
  if (evento.tipo === 'infortunio') return <><strong>{nome(evento.esce)}</strong> si infortuna, entra <strong>{nome(evento.entra)}</strong>.</>
  if (evento.tipo === 'sostituzione') return <><strong>{nome(evento.esce)}</strong> esce, entra <strong>{nome(evento.entra)}</strong>.</>
  if (evento.tipo === 'cartellino') return evento.colore === 'giallo'
    ? <>Ammonito <strong>{nome(evento.giocatore)}</strong>.</>
    : evento.colore === 'doppio_giallo'
      ? <>Secondo giallo per <strong>{nome(evento.giocatore)}</strong>: espulso.</>
      : <>Cartellino rosso per <strong>{nome(evento.giocatore)}</strong>: espulso.</>
  return null
}

// Gol, infortuni, sostituzioni e cartellini restano fissi in cronaca; solo i
// tiri (parati o fuori) sono eventi minori che altrimenti riempirebbero la
// lista, e scompaiono da soli qualche secondo dopo essere comparsi
// (is-transitorio, vedi l'animazione di uscita in styles.css).
function classeEvento(evento: EventoPartita): string {
  if (isEventoGol(evento)) return 'is-goal'
  if (evento.tipo === 'infortunio' || evento.tipo === 'sostituzione') return ''
  if (evento.tipo === 'cartellino') return evento.colore === 'giallo' ? 'is-giallo' : 'is-rosso'
  return 'is-transitorio'
}

const TACCHE = [15, 30, 45, 60, 75, 90]
// Quanto resta in scena la card del gol: stessa durata del file audio
// dell'esultanza (~2,4s), un filo piu' corta cosi' il boato non viene
// interrotto a meta'.
const DURATA_POPUP_GOL_MS = 2200

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
  // Il canvas della cronaca si misura da solo: le card sono posizionate in
  // pixel al loro minuto, quindi serve sapere quanto spazio c'e' davvero.
  const [pitchEl, setPitchEl] = useState<HTMLDivElement | null>(null)
  const [altezzaVisibile, setAltezzaVisibile] = useState(0)
  const [stretto, setStretto] = useState(false)
  const suonoGolRef = useRef<HTMLAudioElement>(null)
  const sottofondoRef = useRef<HTMLAudioElement>(null)
  // Il gol appena segnato resta in scena da solo (simulazione ferma) prima di
  // "sistemarsi" nella cronaca: popupGol e' quello in scena ora, codaGolRef
  // quelli in attesa (due gol nello stesso minuto sono rari ma possibili).
  // inTimeline segna quali sono gia' passati dalla card grande alla cronaca:
  // finche' un gol non c'e' dentro, resta escluso da eventiCasa/eventiOspite.
  const [popupGol, setPopupGol] = useState<EventoGol | null>(null)
  const codaGolRef = useRef<EventoGol[]>([])
  const [inTimeline, setInTimeline] = useState<Set<EventoPartita>>(new Set())

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
    if (estesa || !fixture) return limitaTiri(normalizzaMinuti([...match.blocchi]))
    return limitaTiri(normalizzaMinuti(ricostruisciEventiStorici(match.blocchi, statsStoriche, match.titolari_home, match.titolari_away, fixture.home_team_id, fixture.away_team_id, match.id)))
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
      const { data: giocatori } = playerIds.length
        ? await supabase.from('players').select('id, nome, foto_url').in('id', playerIds)
        : { data: [] }
      if (!attivo) return
      // La foto serve solo per la card del gol, ma firmarla per tutti evita di
      // dover distinguere marcatori da chi esce/entra in un cambio: sono
      // comunque poche foto (una manciata di giocatori a partita).
      const foto = await Promise.all((giocatori ?? []).map(async (giocatore) => [giocatore.id, await firmaFoto(giocatore.foto_url)] as const))
      if (!attivo) return
      const fotoPerGiocatore = new Map(foto)
      const perCatalogo = new Map((giocatori ?? []).map((giocatore) => [giocatore.id, { id: giocatore.id, nome: giocatore.nome, foto: fotoPerGiocatore.get(giocatore.id) } as Player]))
      setNomi(new Map((istanze ?? []).flatMap((istanza) => {
        const giocatore = perCatalogo.get(istanza.player_id)
        return giocatore ? [[istanza.id, giocatore] as const] : []
      })))
    }
    void caricaNomi()
    return () => { attivo = false }
  }, [eventi])

  // L'avanzamento si ferma mentre c'e' un gol in scena: riprende da solo
  // quando popupGol torna null (vedi l'effetto piu' sotto).
  useEffect(() => {
    if (minutoCorrente < 0 || minutoCorrente >= 90 || popupGol) return
    const timer = window.setTimeout(() => {
      const prossimo = minutoCorrente + 1
      const golAlMinuto = eventi.filter((evento): evento is EventoGol => isEventoGol(evento) && evento.minuto === prossimo)
      setMinutoCorrente(prossimo)
      if (golAlMinuto.length) {
        codaGolRef.current.push(...golAlMinuto.slice(1))
        setPopupGol(golAlMinuto[0])
      }
    }, 700)
    return () => window.clearTimeout(timer)
  }, [minutoCorrente, popupGol, eventi])

  // Sblocco dell'audio all'apertura della cronaca: un play() immediatamente
  // seguito da pause() mentre il tocco dell'utente e' ancora "valido"
  // autorizza l'elemento, cosi' i play() successivi (il boato del gol e il
  // sottofondo, che partono da un timer) non vengono piu' rifiutati. Senza
  // questo, chi guardava l'intro fino in fondo restava senza alcun suono.
  useEffect(() => {
    for (const ref of [suonoGolRef, sottofondoRef]) {
      const audio = ref.current
      if (!audio) continue
      void audio.play().then(() => { audio.pause(); audio.currentTime = 0 }).catch(() => {})
    }
  }, [])

  // Sottofondo dello stadio: si accende mentre la partita scorre (o mentre
  // un gol e' in scena) e si spegne a fine cronaca.
  const sottofondoAcceso = eventi.length > 0 && (inCorso || popupGol !== null)
  useEffect(() => {
    const audio = sottofondoRef.current
    if (!audio) return
    if (sottofondoAcceso) void audio.play().catch(() => {})
    else audio.pause()
  }, [sottofondoAcceso])

  // Ogni gol resta in scena da solo per DURATA_POPUP_GOL_MS (sincronizzato col
  // boato dell'esultanza), poi passa al prossimo in coda o si riprende la
  // simulazione. Solo a quel punto il gol entra in inTimeline e compare nella
  // sua porzione del grafico: prima card grande, poi cronaca, mai insieme.
  useEffect(() => {
    if (!popupGol) return
    const audio = suonoGolRef.current
    if (audio) { audio.currentTime = 0; void audio.play().catch(() => {}) }
    const timer = window.setTimeout(() => {
      const golConcluso = popupGol
      setInTimeline((precedente) => new Set(precedente).add(golConcluso))
      setPopupGol(codaGolRef.current.shift() ?? null)
    }, DURATA_POPUP_GOL_MS)
    return () => window.clearTimeout(timer)
  }, [popupGol])

  useEffect(() => {
    if (minutoCorrente < 90 || revealRegistrato.current) return
    revealRegistrato.current = true
    onRevealed(matchId)
  }, [matchId, minutoCorrente, onRevealed])

  // La card ha altezza fissa (testo troncato a due righe): serve a poterne
  // calcolare la disposizione senza doverle prima misurare una a una.
  const altezzaEvento = stretto ? ALTEZZA_EVENTO_STRETTA : ALTEZZA_EVENTO
  const margine = altezzaEvento / 2 + 4

  useEffect(() => {
    const mq = window.matchMedia('(max-width: 560px)')
    const aggiorna = () => setStretto(mq.matches)
    aggiorna()
    mq.addEventListener('change', aggiorna)
    return () => mq.removeEventListener('change', aggiorna)
  }, [])

  useEffect(() => {
    if (!pitchEl) return
    const osservatore = new ResizeObserver(() => setAltezzaVisibile(pitchEl.clientHeight))
    osservatore.observe(pitchEl)
    setAltezzaVisibile(pitchEl.clientHeight)
    return () => osservatore.disconnect()
  }, [pitchEl])

  // Un evento minore sparisce da solo dopo qualche minuto di gioco: da qui in
  // poi esce proprio dalla lista, non resta piu' una card invisibile a
  // occupare spazio (era la causa dei buchi enormi in cronaca). Un gol invece
  // resta escluso finche' non e' passato dalla card grande (inTimeline).
  const visibili = useMemo(() => eventi.filter((evento) => evento.minuto <= minuto
    && (!isEventoGol(evento) || inTimeline.has(evento))
    && (!eTransitorio(evento) || minuto - evento.minuto < MINUTI_VITA_TRANSITORIO)), [eventi, minuto, inTimeline])
  const eventiCasa = useMemo(() => visibili.filter((evento) => evento.lato === 'casa'), [visibili])
  const eventiOspite = useMemo(() => visibili.filter((evento) => evento.lato === 'ospite'), [visibili])

  // Di norma la cronaca sta esattamente in una schermata. Solo se una partita
  // fittissima non ci sta il canvas cresce, e cresce per tutti: linea, tacche
  // ed eventi condividono la stessa altezza, quindi restano allineati anche
  // quando si scorre.
  const spazioPerEventi = (quanti: number) => quanti === 0 ? 0 : quanti * (altezzaEvento + GAP_EVENTO) - GAP_EVENTO + margine * 2
  const altezzaCanvas = Math.max(altezzaVisibile, spazioPerEventi(eventiCasa.length), spazioPerEventi(eventiOspite.length))
  const posizioniCasa = useMemo(() => disponiEventi(eventiCasa, altezzaCanvas, altezzaEvento, margine), [eventiCasa, altezzaCanvas, altezzaEvento, margine])
  const posizioniOspite = useMemo(() => disponiEventi(eventiOspite, altezzaCanvas, altezzaEvento, margine), [eventiOspite, altezzaCanvas, altezzaEvento, margine])

  useEffect(() => {
    if (!pitchEl || altezzaCanvas <= pitchEl.clientHeight) return
    pitchEl.scrollTo({ top: Math.max(0, posizioneMinuto(minuto, altezzaCanvas, margine) - pitchEl.clientHeight / 2), behavior: 'smooth' })
  }, [pitchEl, minuto, altezzaCanvas, margine])

  if (data.loading || !match || !fixture) return null
  const casa = data.teamById.get(fixture.home_team_id)
  const ospite = data.teamById.get(fixture.away_team_id)

  // I due elementi audio stanno FUORI dal ramo dell'intro, cosi' esistono
  // gia' al primo render — cioe' subito dopo il tocco che ha aperto la
  // partita — e restano gli stessi quando l'intro lascia il posto alla
  // cronaca. Prima nascevano solo dopo l'intro: chi la saltava col
  // pulsante li creava dentro al proprio tocco (e i suoni partivano), chi
  // la guardava fino in fondo li creava da un timer, fuori da qualsiasi
  // gesto, e il browser ne bloccava la riproduzione. Da qui la differenza
  // fra stagione regolare (intro corta, spesso saltata) e playoff.
  const elementiAudio = <>
    <audio ref={suonoGolRef} src="/suoni-effetti/esultanza-gol.m4a" preload="auto" />
    <audio ref={sottofondoRef} src="/suoni-effetti/stadio-sottofondo.m4a" loop preload="auto" />
  </>

  // L'intro (musica di fase, locandina, formazioni) precede il calcio
  // d'inizio solo quando c'e' davvero una cronaca da vivere: per le partite
  // simulate prima della cronaca estesa non avrebbe nulla da presentare.
  if (minutoCorrente < 0 && eventi.length > 0) {
    return <>
    {elementiAudio}
    <MatchIntro
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
    </>
  }

  const squadraGol = popupGol && (popupGol.lato === 'casa' ? casa : ospite)
  const crestGolUrl = popupGol && data.crestUrlByTeamId.get(popupGol.lato === 'casa' ? fixture.home_team_id : fixture.away_team_id)
  const marcatore = popupGol && nomi.get(popupGol.marcatore)

  return <div className="match-reveal-backdrop" role="dialog" aria-modal="true" aria-label="Cronaca della partita">
    {elementiAudio}
    <section className="match-reveal">
      <div className="match-reveal__sfondo" style={{ backgroundImage: `url(${SFONDO_FASE_VERTICALE[fase]})` }} />
      <button className="match-reveal__close" type="button" onClick={onClose} aria-label="Chiudi cronaca">×</button>

      {popupGol && <div className="match-reveal__gol-popup" role="alert">
        <div className="match-reveal__gol-popup-card">
          <p className="match-reveal__gol-popup-titolo">GOOOL!</p>
          <div className="match-reveal__gol-popup-foto">
            {marcatore?.foto ? <img src={marcatore.foto} alt="" /> : <span aria-hidden="true">{cognome(marcatore?.nome ?? '?').charAt(0)}</span>}
          </div>
          <strong>{cognome(marcatore?.nome ?? 'Giocatore')}</strong>
          <div className="match-reveal__gol-popup-squadra">
            <Crest value={squadraGol?.stemma_url ?? null} imageUrl={crestGolUrl ?? undefined} size="small" />
            <span>{squadraGol?.nome ?? 'Squadra'}</span>
            <b>{popupGol.minuto}’</b>
          </div>
        </div>
      </div>}

      <header className="match-reveal__header">
        <div><Crest value={casa?.stemma_url ?? null} imageUrl={data.crestUrlByTeamId.get(fixture.home_team_id)} size="small" /><strong>{casa?.nome}</strong></div>
        <div className="match-reveal__score">
          <small>{completata ? 'RISULTATO FINALE' : <><i className="match-reveal__live-dot" aria-hidden="true" />{minuto}’</>}</small>
          <b>{punteggio.casa} <i>–</i> {punteggio.ospite}</b>
        </div>
        <div><strong>{ospite?.nome}</strong><Crest value={ospite?.stemma_url ?? null} imageUrl={data.crestUrlByTeamId.get(fixture.away_team_id)} size="small" /></div>
      </header>

      {eventi.length === 0 ? <div className="match-reveal__empty"><p>Questa partita è stata simulata prima della cronaca estesa.</p><button className="button button--primary" type="button" onClick={onOpenReport}>Vedi risultato</button></div> : <>
        <div className="match-reveal__pitch" ref={setPitchEl} aria-label={`Minuto ${minuto} su 90`}>
          <div className="match-reveal__canvas" style={{ height: `${altezzaCanvas}px` }}>
            <div className="match-reveal__half match-reveal__half--first">1º TEMPO</div>
            <div className="match-reveal__half match-reveal__half--second">2º TEMPO</div>
            <div className="match-reveal__line" style={{ top: `${margine}px`, bottom: `${margine}px` }}>
              <span style={{ height: `${Math.min(100, minuto / 90 * 100)}%` }} />
              <b className={`match-reveal__minute ${inCorso ? 'is-live' : ''}`} style={{ top: `${Math.min(100, minuto / 90 * 100)}%` }}>{minuto}’</b>
            </div>
            {TACCHE.map((tacca) => (
              <span className={`match-reveal__marker ${tacca === 45 || tacca === 90 ? 'is-forte' : ''}`} style={{ top: `${posizioneMinuto(tacca, altezzaCanvas, margine)}px` }} key={tacca}>{tacca}’</span>
            ))}
            <div className="match-reveal__events match-reveal__events--home">
              {eventiCasa.map((evento, i) => <p className={classeEvento(evento)} style={{ top: `${posizioniCasa.get(evento) ?? 0}px`, height: `${altezzaEvento}px` }} key={`${evento.minuto}-${i}`}><time>{evento.minuto}’</time>{testoEvento(evento, nomi)}</p>)}
            </div>
            <div className="match-reveal__events match-reveal__events--away">
              {eventiOspite.map((evento, i) => <p className={classeEvento(evento)} style={{ top: `${posizioniOspite.get(evento) ?? 0}px`, height: `${altezzaEvento}px` }} key={`${evento.minuto}-${i}`}><time>{evento.minuto}’</time>{testoEvento(evento, nomi)}</p>)}
            </div>
          </div>
        </div>
        <footer className="match-reveal__footer">
          {inCorso ? <span className="match-reveal__in-corso"><i aria-hidden="true" />La partita è in corso…</span>
            : <button className="button button--primary" type="button" onClick={onOpenReport}>Vedi rapporto partita</button>}
        </footer>
      </>}
    </section>
  </div>
}
