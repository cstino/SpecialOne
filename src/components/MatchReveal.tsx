import { useEffect, useMemo, useRef, useState } from 'react'
import { supabase } from '../lib/supabase'
import { cognome } from '../lib/nomi'
import { ricostruisciEventiStorici, type StatEventoStorico } from '../lib/matchEvents'
import { useSeasonData } from '../lib/useSeasonData'
import { LOGO_FASE, SFONDO_FASE_VERTICALE, type FaseSquadra } from '../lib/faseSquadra'

const NOME_FASE: Record<FaseSquadra, string> = { regular: 'Stagione regolare', title: 'Title Playoffs', draft: 'Draft Playoffs' }
import { isEventoGol, type EventoGol, type EventoPartita, type Membership } from '../types'
import { Crest } from './Crest'
import { firmaFoto } from './RosaElenco'
import { MatchIntro } from './MatchIntro'
import { Icona } from './Icona'
import { SpotVideo } from './SpotVideo'
import { RigoriScena, type FaseRigore } from './RigoriScena'

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
    if (Number.isInteger(minuto) && minuto >= 1 && minuto <= 120) return
    const bloccoLetto = Number(evento.blocco)
    const blocco = Number.isInteger(bloccoLetto) && bloccoLetto >= 1 && bloccoLetto <= 8
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
    return Number.isInteger(minuto) && minuto >= 1 && minuto <= 120
      ? evento
      : { ...evento, minuto: minutiRicostruiti.get(indice) ?? 90 }
  }).sort((sinistra, destra) => sinistra.minuto - destra.minuto || sinistra.team_id - destra.team_id)
}

// Le partite con supplementari simulate prima della correzione della Edge
// Function hanno i gol dei supplementari "riparati" dentro i 90 minuti. Si
// riconoscono perche' nessun evento supera il 90' e i gol dei tempi
// regolamentari sono piu' del parziale salvato: gli ultimi in eccesso tornano
// nei supplementari, cosi' il punteggio a 90' coincide con quello vero.
function ricollocaSupplementari(eventi: EventoPartita[], golRegolamentari: { casa: number; ospite: number }) {
  if (eventi.some((evento) => evento.minuto > 90)) return eventi
  const inEccesso = new Set<EventoPartita>()
  for (const lato of ['casa', 'ospite'] as const) {
    const gol = eventi.filter((evento) => isEventoGol(evento) && evento.lato === lato)
    gol.slice(golRegolamentari[lato]).forEach((evento) => inEccesso.add(evento))
  }
  if (!inEccesso.size) return eventi
  let k = 0
  return eventi.map((evento) => inEccesso.has(evento)
    ? { ...evento, minuto: 90 + Math.round(++k * 30 / (inEccesso.size + 1)), blocco: 7 }
    : evento).sort((sinistra, destra) => sinistra.minuto - destra.minuto || sinistra.team_id - destra.team_id)
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
// `inizio` e `durata` descrivono la finestra mostrata: 0-90 per i tempi
// regolamentari, 90-120 per i supplementari (ognuno sulla sua schermata).
function posizioneMinuto(minuto: number, altezza: number, margine: number, durata: number, inizio = 0) {
  return margine + (Math.min(durata, Math.max(0, minuto - inizio)) / durata) * Math.max(0, altezza - margine * 2)
}

// Ogni card parte dal proprio minuto sulla linea del tempo e scivola verso il
// basso solo quel tanto che serve a non sovrapporsi alla precedente (passata
// in avanti); se l'ultima sfora il fondo si risale spingendo verso l'alto
// (passata all'indietro). E' il posizionamento classico delle etichette su un
// asse: lo scostamento dal minuto vero resta minimo finche' gli eventi sono
// radi, e degrada in modo prevedibile quando si infittiscono. Il canvas e'
// sempre alto almeno quanto serve a contenerli tutti, quindi la passata
// all'indietro trova sempre una soluzione valida.
function disponiEventi(eventi: EventoPartita[], altezza: number, altezzaEvento: number, margine: number, durata: number, inizio: number) {
  const posizioni = new Map<EventoPartita, number>()
  let cursore = margine
  for (const evento of eventi) {
    const top = Math.max(posizioneMinuto(evento.minuto, altezza, margine, durata, inizio) - altezzaEvento / 2, cursore)
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
const TACCHE_SUPPLEMENTARI = [95, 100, 105, 110, 115, 120]
// Lo stacco fra una fase e l'altra (simulazione ferma). La schermata sotto
// cambia a SWITCH_STACCO_MS, quando lo stacco e' ancora opaco; poi si dissolve.
const DURATA_ANNUNCIO_MS = 3200
const SWITCH_STACCO_MS = 2700
// Ritmo di ogni rigore: presentazione del tiratore, rincorsa, esito. L'ultimo
// (quello che decide la serie) si fa aspettare di piu'.
const RIGORE_INTRO_MS = 2300
const RIGORE_INTRO_DECISIVO_MS = 3400
const RIGORE_RINCORSA_MS = 1700
const RIGORE_TIRO_MS = 1100
const RIGORE_ESITO_MS = 3200
// Quanto resta in scena la card del gol: stessa durata del file audio
// dell'esultanza (~2,4s), un filo piu' corta cosi' il boato non viene
// interrotto a meta'.
const DURATA_POPUP_GOL_MS = 2200

// Sorpresa una tantum: uno spot prima dell'intro, solo per Maudit Printemps
// (squadra 285) e solo per la prima partita del turno playoff (fixture 2424,
// giornata 31). Chiusa la partita viene segnata come vista, quindi non si ripete.
const SPOT = { teamId: 285, fixtureId: 2424, src: '/spot/maudit-printemps.mp4' }

export function MatchReveal({ membership, matchId, onClose, onRevealed, onOpenReport }: Props) {
  const data = useSeasonData(membership)
  const match = data.matches.find((item) => item.id === matchId)
  const fixture = match ? data.fixtures.find((item) => item.id === match.fixture_id) : undefined
  const [nomi, setNomi] = useState<Map<number, Player>>(new Map())
  const [statsStoriche, setStatsStoriche] = useState<StatEventoStorico[]>([])
  const revealRegistrato = useRef(false)
  const [spotFinito, setSpotFinito] = useState(false)
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

  // Nel ritorno di un'eliminatoria conta il totale delle due partite: senza
  // l'andata un 1-0 che porta ai supplementari sembrerebbe un errore.
  const [andata, setAndata] = useState<{ casa: number; ospite: number } | null>(null)
  useEffect(() => {
    let vivo = true
    async function caricaAndata() {
      if (!fixture?.bracket_tie_id || fixture.mano !== 2) { if (vivo) setAndata(null); return }
      const { data: riga } = await supabase.from('fixtures').select('home_team_id, matches(gol_home, gol_away)')
        .eq('bracket_tie_id', fixture.bracket_tie_id).eq('mano', 1).maybeSingle()
      const partita = Array.isArray(riga?.matches) ? riga.matches[0] : riga?.matches
      if (!vivo || !riga || !partita) return
      const casaInCasa = riga.home_team_id === fixture.home_team_id
      setAndata({ casa: casaInCasa ? partita.gol_home : partita.gol_away, ospite: casaInCasa ? partita.gol_away : partita.gol_home })
    }
    void caricaAndata()
    return () => { vivo = false }
  }, [fixture?.bracket_tie_id, fixture?.mano, fixture?.home_team_id])

  const eventi = useMemo(() => {
    if (!match) return []
    const estesa = match.blocchi.some((evento) => !isEventoGol(evento))
    const cronaca = estesa || !fixture
      ? normalizzaMinuti([...match.blocchi])
      : normalizzaMinuti(ricostruisciEventiStorici(match.blocchi, statsStoriche, match.titolari_home, match.titolari_away, fixture.home_team_id, fixture.away_team_id, match.id))
    return limitaTiri(match.gol_home_90 != null && match.gol_away_90 != null
      ? ricollocaSupplementari(cronaca, { casa: match.gol_home_90, ospite: match.gol_away_90 })
      : cronaca)
  }, [fixture, match, statsStoriche])
  // Supplementari e rigori esistono solo nelle eliminatorie finite in parita':
  // il parziale dei 90' c'e' solo se si sono giocati i supplementari, la serie
  // dei rigori solo se sono serviti. Il tempo di gioco diventa 120' e, in coda,
  // si aggiunge la sequenza dal dischetto.
  const supplementari = match?.gol_home_90 != null
  const serieRigori = useMemo(() => match?.rigori_home != null ? (match.rigori_serie ?? []) : [], [match])
  const haRigori = serieRigori.length > 0
  // La partita si guarda una fase alla volta, senza anticipare la successiva:
  // prima i 90', poi (se ci sono stati) i supplementari, infine i rigori.
  const [annuncio, setAnnuncio] = useState<'supplementari' | 'rigori' | null>(null)
  const [fasePartita, setFasePartita] = useState<'regolamentari' | 'supplementari' | 'rigori'>('regolamentari')
  const annunciFatti = useRef({ supplementari: false, rigori: false })
  const [rigoreCorrente, setRigoreCorrente] = useState(0)
  const [faseRigore, setFaseRigore] = useState<FaseRigore>('intro')
  const rigoriFiniti = !haRigori || rigoreCorrente >= serieRigori.length
  const oraFinale = supplementari ? 120 : 90
  const fineFase = fasePartita === 'regolamentari' && supplementari ? 90 : oraFinale
  const inizioFase = fasePartita === 'supplementari' ? 90 : 0
  const durata = fineFase - inizioFase
  const inCorso = minutoCorrente >= 0 && minutoCorrente < fineFase
  const inRigori = fasePartita === 'rigori' && !rigoriFiniti
  const completata = minutoCorrente >= oraFinale && rigoriFiniti
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
    // Per i rigori servono anche i tiratori e i portieri (titolari[0] e' sempre
    // il portiere: lo e' in tutti i moduli).
    const idRigori = [
      ...serieRigori.flatMap((tiro) => tiro.tiratoreId != null ? [tiro.tiratoreId] : []),
      ...(haRigori && match ? [match.titolari_home[0], match.titolari_away[0]].filter((id): id is number => id != null) : []),
    ]
    const ids = [...new Set([...eventi.flatMap((evento) => isEventoGol(evento)
      ? [evento.marcatore, ...(evento.assist ? [evento.assist] : [])]
      : evento.tipo === 'sostituzione' || evento.tipo === 'infortunio' ? [evento.esce, evento.entra] : [evento.giocatore]), ...idRigori])]
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
  }, [eventi, serieRigori, haRigori, match])

  // L'avanzamento si ferma mentre c'e' un gol in scena: riprende da solo
  // quando popupGol torna null (vedi l'effetto piu' sotto).
  useEffect(() => {
    if (minutoCorrente < 0 || minutoCorrente >= fineFase || popupGol || annuncio) return
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
  }, [minutoCorrente, popupGol, annuncio, fineFase, eventi])

  // A fine fase la partita si ferma e annuncia la successiva: dai 90' ai
  // supplementari (se in parita'), da li' ai rigori (se serve). Aspetta che
  // l'eventuale gol dell'ultimo minuto abbia finito la sua scena.
  useEffect(() => {
    if (popupGol || annuncio || minutoCorrente !== fineFase) return
    if (fasePartita === 'regolamentari' && supplementari && !annunciFatti.current.supplementari) {
      annunciFatti.current.supplementari = true
      setAnnuncio('supplementari')
    } else if (fasePartita !== 'rigori' && haRigori && !annunciFatti.current.rigori) {
      annunciFatti.current.rigori = true
      setAnnuncio('rigori')
    }
  }, [minutoCorrente, fineFase, fasePartita, popupGol, annuncio, supplementari, haRigori])

  useEffect(() => {
    if (!annuncio) return
    const cambio = window.setTimeout(() => setFasePartita(annuncio), SWITCH_STACCO_MS)
    const fine = window.setTimeout(() => setAnnuncio(null), DURATA_ANNUNCIO_MS)
    return () => { window.clearTimeout(cambio); window.clearTimeout(fine) }
  }, [annuncio])

  // Ogni rigore: presentazione, rincorsa, tiro (il pallone vola), esito; poi il successivo. L'ultimo
  // esito porta rigoreCorrente a serie.length, cioe' a serie conclusa.
  useEffect(() => {
    if (fasePartita !== 'rigori' || annuncio || rigoreCorrente >= serieRigori.length) return
    const ms = faseRigore === 'intro'
      ? (rigoreCorrente === serieRigori.length - 1 ? RIGORE_INTRO_DECISIVO_MS : RIGORE_INTRO_MS)
      : faseRigore === 'rincorsa' ? RIGORE_RINCORSA_MS : faseRigore === 'tiro' ? RIGORE_TIRO_MS : RIGORE_ESITO_MS
    const timer = window.setTimeout(() => {
      if (faseRigore === 'intro') setFaseRigore('rincorsa')
      else if (faseRigore === 'rincorsa') setFaseRigore('tiro')
      else if (faseRigore === 'tiro') setFaseRigore('esito')
      else { setRigoreCorrente((i) => i + 1); setFaseRigore('intro') }
    }, ms)
    return () => window.clearTimeout(timer)
  }, [fasePartita, annuncio, rigoreCorrente, faseRigore, serieRigori.length])

  // Il boato dello stadio quando un rigore finisce in rete.
  useEffect(() => {
    if (fasePartita !== 'rigori' || faseRigore !== 'esito' || !serieRigori[rigoreCorrente]?.segnato) return
    const audio = suonoGolRef.current
    if (audio) { audio.currentTime = 0; void audio.play().catch(() => {}) }
  }, [fasePartita, faseRigore, rigoreCorrente, serieRigori])

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
  const sottofondoAcceso = eventi.length > 0 && (inCorso || inRigori || popupGol !== null || annuncio !== null)
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
    if (!completata || revealRegistrato.current) return
    revealRegistrato.current = true
    onRevealed(matchId)
  }, [matchId, completata, onRevealed])

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
    && evento.minuto > inizioFase
    && (!isEventoGol(evento) || inTimeline.has(evento))
    && (!eTransitorio(evento) || minuto - evento.minuto < MINUTI_VITA_TRANSITORIO)), [eventi, minuto, inTimeline, inizioFase])
  const eventiCasa = useMemo(() => visibili.filter((evento) => evento.lato === 'casa'), [visibili])
  const eventiOspite = useMemo(() => visibili.filter((evento) => evento.lato === 'ospite'), [visibili])

  // Di norma la cronaca sta esattamente in una schermata. Solo se una partita
  // fittissima non ci sta il canvas cresce, e cresce per tutti: linea, tacche
  // ed eventi condividono la stessa altezza, quindi restano allineati anche
  // quando si scorre.
  const spazioPerEventi = (quanti: number) => quanti === 0 ? 0 : quanti * (altezzaEvento + GAP_EVENTO) - GAP_EVENTO + margine * 2
  const altezzaCanvas = Math.max(altezzaVisibile, spazioPerEventi(eventiCasa.length), spazioPerEventi(eventiOspite.length))
  const posizioniCasa = useMemo(() => disponiEventi(eventiCasa, altezzaCanvas, altezzaEvento, margine, durata, inizioFase), [eventiCasa, altezzaCanvas, altezzaEvento, margine, durata, inizioFase])
  const posizioniOspite = useMemo(() => disponiEventi(eventiOspite, altezzaCanvas, altezzaEvento, margine, durata, inizioFase), [eventiOspite, altezzaCanvas, altezzaEvento, margine, durata, inizioFase])

  useEffect(() => {
    if (!pitchEl || altezzaCanvas <= pitchEl.clientHeight) return
    pitchEl.scrollTo({ top: Math.max(0, posizioneMinuto(minuto, altezzaCanvas, margine, durata, inizioFase) - pitchEl.clientHeight / 2), behavior: 'smooth' })
  }, [pitchEl, minuto, altezzaCanvas, margine, durata, inizioFase])

  // Ogni fase riparte dall'alto della sua schermata.
  useEffect(() => { pitchEl?.scrollTo({ top: 0 }) }, [pitchEl, fasePartita])

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

  // Anche mentre i dati si caricano: lo sblocco dell'audio (effect qui sopra)
  // gira al primo render, cioe' dentro il tocco che ha aperto la partita, e
  // deve trovare gia' gli elementi. Con `return null` non c'erano, e su iPhone
  // restavano muti sia il pubblico sia il boato del gol.
  if (data.loading || !match || !fixture) return <>{elementiAudio}</>
  const casa = data.teamById.get(fixture.home_team_id)
  const ospite = data.teamById.get(fixture.away_team_id)


  // L'intro (musica di fase, locandina, formazioni) precede il calcio
  // d'inizio solo quando c'e' davvero una cronaca da vivere: per le partite
  // simulate prima della cronaca estesa non avrebbe nulla da presentare.
  if (minutoCorrente < 0 && eventi.length > 0 && !spotFinito && membership.id === SPOT.teamId && fixture.id === SPOT.fixtureId) {
    return <>
    {elementiAudio}
    <SpotVideo src={SPOT.src} onFine={() => setSpotFinito(true)} />
    </>
  }

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

  const tacche = fasePartita === 'supplementari' ? TACCHE_SUPPLEMENTARI : TACCHE
  const fasceTempo = fasePartita === 'supplementari'
    ? [{ inizio: 90, fine: 105, etichetta: '1º SUPPL.' }, { inizio: 105, fine: 120, etichetta: '2º SUPPL.' }]
    : [{ inizio: 0, fine: 45, etichetta: '1º TEMPO' }, { inizio: 45, fine: 90, etichetta: '2º TEMPO' }]
  const inCorsoSupplementari = fasePartita === 'supplementari'

  const squadraGol = popupGol && (popupGol.lato === 'casa' ? casa : ospite)
  const crestGolUrl = popupGol && data.crestUrlByTeamId.get(popupGol.lato === 'casa' ? fixture.home_team_id : fixture.away_team_id)
  const marcatore = popupGol && nomi.get(popupGol.marcatore)

  return <>
    {elementiAudio}
    <div className="match-reveal-backdrop" role="dialog" aria-modal="true" aria-label="Cronaca della partita">
    <section className="match-reveal">
      <div className="match-reveal__sfondo" style={{ backgroundImage: `url(${SFONDO_FASE_VERTICALE[fase]})` }} />
      <button className="match-reveal__close" type="button" onClick={onClose} aria-label="Chiudi cronaca"><Icona nome="chiudi" /></button>

      {popupGol && <div className="match-reveal__gol-popup" role="alert">
        <div className="rig__card rig__card--gol" key={`${popupGol.minuto}-${popupGol.team_id}`}>
          <span className="rig__filigrana" aria-hidden="true">{cognome(marcatore?.nome ?? '')}</span>
          <div className="rig__banda rig__banda--testa"><strong>GOOOL!</strong></div>
          <div className="rig__ritratto">
            <div className="rig__foto">
              {marcatore?.foto ? <img src={marcatore.foto} alt="" /> : <span aria-hidden="true">{cognome(marcatore?.nome ?? '?').charAt(0)}</span>}
            </div>
          </div>
          <strong className="rig__nome">{cognome(marcatore?.nome ?? 'Giocatore')}</strong>
          <div className="match-reveal__gol-risultato">
            <span className={popupGol.lato === 'casa' ? 'is-segna' : ''}>{casa?.sigla}</span>
            <b>{punteggio.casa}<i>–</i>{punteggio.ospite}</b>
            <span className={popupGol.lato === 'ospite' ? 'is-segna' : ''}>{ospite?.sigla}</span>
          </div>
          <div className="rig__squadra-tiro">
            <span className="rig__stemma"><Crest value={squadraGol?.stemma_url ?? null} imageUrl={crestGolUrl ?? undefined} size="small" /></span>
            <span>{squadraGol?.nome ?? 'Squadra'}</span>
            <em>{popupGol.minuto}’ · {popupGol.minuto > 105 ? '2º supplementare' : popupGol.minuto > 90 ? '1º supplementare' : popupGol.minuto > 45 ? '2º tempo' : '1º tempo'}</em>
          </div>
        </div>
      </div>}

      {annuncio && <div className={`match-reveal__stacco is-${annuncio}`} role="alert">
        <div className="match-reveal__stacco-lame" aria-hidden="true" />
        <p className="match-reveal__stacco-kicker">{annuncio === 'supplementari' ? 'Fine dei tempi regolamentari' : supplementari ? 'Dopo i supplementari' : 'Dopo i 90′'}</p>
        <div className="match-reveal__stacco-squadre">
          <div><Crest value={casa?.stemma_url ?? null} imageUrl={data.crestUrlByTeamId.get(fixture.home_team_id)} size="large" /><span>{casa?.nome}</span></div>
          <b>{punteggio.casa}<i>–</i>{punteggio.ospite}</b>
          <div><Crest value={ospite?.stemma_url ?? null} imageUrl={data.crestUrlByTeamId.get(fixture.away_team_id)} size="large" /><span>{ospite?.nome}</span></div>
        </div>
        <h2 className="match-reveal__stacco-titolo">{annuncio === 'supplementari' ? 'Supplementari' : 'Calci di rigore'}</h2>
        {andata && <p className="match-reveal__stacco-totale">Andata {andata.casa}–{andata.ospite} · totale <b>{andata.casa + punteggio.casa}–{andata.ospite + punteggio.ospite}</b></p>}
        <p className="match-reveal__stacco-sotto"><em>{annuncio === 'supplementari' ? '+30′' : '11 m'}</em>{annuncio === 'supplementari' ? 'Altri trenta minuti per decidere.' : 'Decidono gli undici metri.'}</p>
      </div>}

      <header className={`match-reveal__header scoreboard scoreboard--${fase}`}>
        <div className="scoreboard__comp"><img src={LOGO_FASE[fase]} alt={NOME_FASE[fase]} /></div>
        <div className="scoreboard__bar">
          <div className="scoreboard__team">
            <span className="scoreboard__stemma"><Crest value={casa?.stemma_url ?? null} imageUrl={data.crestUrlByTeamId.get(fixture.home_team_id)} size="small" /></span>
            <b title={casa?.nome}>{casa?.sigla}</b>
          </div>
          <div className="scoreboard__score" aria-label={`${punteggio.casa} a ${punteggio.ospite}`}>
            <b>{punteggio.casa}</b><i aria-hidden="true" /><b>{punteggio.ospite}</b>
          </div>
          <div className="scoreboard__team scoreboard__team--ospite">
            <b title={ospite?.nome}>{ospite?.sigla}</b>
            <span className="scoreboard__stemma"><Crest value={ospite?.stemma_url ?? null} imageUrl={data.crestUrlByTeamId.get(fixture.away_team_id)} size="small" /></span>
          </div>
          <span className="scoreboard__stato">
            {completata ? (haRigori ? 'FINALE D.C.R.' : supplementari ? 'FINALE D.T.S.' : 'FINALE')
              : fasePartita === 'rigori' ? 'RIGORI'
              : <><i className="match-reveal__live-dot" aria-hidden="true" />{minuto}’{minuto > 90 ? ' SUPPL.' : ''}</>}
            {andata && fasePartita !== 'rigori' && <em>TOT. {andata.casa + punteggio.casa}–{andata.ospite + punteggio.ospite}</em>}
          </span>
        </div>
      </header>

      {eventi.length === 0 ? <div className="match-reveal__empty"><p>Questa partita è stata simulata prima della cronaca estesa.</p><button className="button button--primary" type="button" onClick={onOpenReport}>Vedi risultato</button></div> : <>
        {fasePartita === 'rigori'
          ? <div className="match-reveal__pitch match-reveal__pitch--rigori" aria-label="Calci di rigore">
            <RigoriScena
              serie={serieRigori}
              indice={rigoreCorrente}
              fase={faseRigore}
              seed={match.id}
              casa={{ nome: casa?.nome ?? 'Casa', stemma: casa?.stemma_url ?? null, stemmaUrl: data.crestUrlByTeamId.get(fixture.home_team_id) }}
              ospite={{ nome: ospite?.nome ?? 'Ospite', stemma: ospite?.stemma_url ?? null, stemmaUrl: data.crestUrlByTeamId.get(fixture.away_team_id) }}
              giocatori={nomi}
              portiereCasa={match.titolari_home[0] ?? null}
              portiereOspite={match.titolari_away[0] ?? null}
            />
          </div>
          : <div className="match-reveal__pitch" ref={setPitchEl} aria-label={`Minuto ${minuto}`}>
          <div className="match-reveal__canvas" style={{ height: `${altezzaCanvas}px` }}>
            {fasceTempo.map((fascia) => (
              <div className={`match-reveal__half ${fascia.inizio > inizioFase ? 'match-reveal__half--second' : ''} ${fascia.inizio >= 90 ? 'match-reveal__half--extra' : ''}`} style={{ top: `${(fascia.inizio - inizioFase) / durata * 100}%`, height: `${(fascia.fine - fascia.inizio) / durata * 100}%` }} key={fascia.etichetta}>{fascia.etichetta}</div>
            ))}
            <div className="match-reveal__line" style={{ top: `${margine}px`, bottom: `${margine}px` }}>
              <span style={{ height: `${Math.min(100, (minuto - inizioFase) / durata * 100)}%` }} />
              <b className={`match-reveal__minute ${inCorso ? 'is-live' : ''}`} style={{ top: `${Math.min(100, (minuto - inizioFase) / durata * 100)}%` }}>{minuto}’</b>
            </div>
            {tacche.map((tacca) => (
              <span className={`match-reveal__marker ${tacca === 45 || tacca === 90 || tacca === 105 ? 'is-forte' : ''}`} style={{ top: `${posizioneMinuto(tacca, altezzaCanvas, margine, durata, inizioFase)}px` }} key={tacca}>{tacca}’</span>
            ))}
            <div className="match-reveal__events match-reveal__events--home">
              {eventiCasa.map((evento, i) => <p className={classeEvento(evento)} style={{ top: `${posizioniCasa.get(evento) ?? 0}px`, height: `${altezzaEvento}px` }} key={`${evento.minuto}-${i}`}><time>{evento.minuto}’</time>{testoEvento(evento, nomi)}</p>)}
            </div>
            <div className="match-reveal__events match-reveal__events--away">
              {eventiOspite.map((evento, i) => <p className={classeEvento(evento)} style={{ top: `${posizioniOspite.get(evento) ?? 0}px`, height: `${altezzaEvento}px` }} key={`${evento.minuto}-${i}`}><time>{evento.minuto}’</time>{testoEvento(evento, nomi)}</p>)}
            </div>
          </div>
        </div>}
        <footer className="match-reveal__footer">
          {!completata && fasePartita === 'rigori' ? <span className="match-reveal__in-corso"><i aria-hidden="true" />Si decide dal dischetto…</span>
            : !completata ? <span className="match-reveal__in-corso"><i aria-hidden="true" />{inCorsoSupplementari ? 'Supplementari in corso…' : 'La partita è in corso…'}</span>
            : <button className="button button--primary" type="button" onClick={onOpenReport}>Vedi rapporto partita</button>}
        </footer>
      </>}
    </section>
    </div>
  </>
}
