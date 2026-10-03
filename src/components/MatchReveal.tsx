import { useEffect, useId, useMemo, useRef, useState, type ReactNode } from 'react'
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
import { costruisciTelecronaca, type Riga } from '../lib/telecronaca'
import { coloreStemma, coloriDistinti, curvaPressione, percorsoCurva } from '../lib/pressione'

type Props = { membership: Membership; matchId: number; onClose: () => void; onRevealed: (matchId: number) => void; onOpenReport: () => void }
type Player = { id: number; nome: string; foto?: string; posizioni?: string[] }

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
    // Tutti i tiri restano: alimentano il grafico della pressione, e quanti
    // raccontarne lo decide la telecronaca.
    return match.gol_home_90 != null && match.gol_away_90 != null
      ? ricollocaSupplementari(cronaca, { casa: match.gol_home_90, ospite: match.gol_away_90 })
      : cronaca
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
      ...(match ? [...match.titolari_home, ...match.titolari_away].filter((id): id is number => id != null) : []),
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
        ? await supabase.from('players').select('id, nome, foto_url, posizioni').in('id', playerIds)
        : { data: [] }
      if (!attivo) return
      // La foto serve solo per la card del gol, ma firmarla per tutti evita di
      // dover distinguere marcatori da chi esce/entra in un cambio: sono
      // comunque poche foto (una manciata di giocatori a partita).
      const foto = await Promise.all((giocatori ?? []).map(async (giocatore) => [giocatore.id, await firmaFoto(giocatore.foto_url)] as const))
      if (!attivo) return
      const fotoPerGiocatore = new Map(foto)
      const perCatalogo = new Map((giocatori ?? []).map((giocatore) => [giocatore.id, { id: giocatore.id, nome: giocatore.nome, foto: fotoPerGiocatore.get(giocatore.id), posizioni: giocatore.posizioni ?? undefined } as Player]))
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
      // Muto durante lo sblocco: il play() dura finche' la promessa non si
      // risolve, e sull'iPhone quel frammento di boato si sentiva prima
      // dell'intro (segnalato dal committente il 4 ottobre 2026).
      audio.muted = true
      void audio.play()
        .then(() => { audio.pause(); audio.currentTime = 0 })
        .catch(() => {})
        .finally(() => { audio.muted = false })
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

  // La telecronaca: fissa per partita, costruita quando ci sono i nomi.
  const casaSq = fixture ? data.teamById.get(fixture.home_team_id) : undefined
  const ospiteSq = fixture ? data.teamById.get(fixture.away_team_id) : undefined
  // Gli allenatori raccontano i cambi ("Rossi pesca dalla panchina…"); le
  // squadre del PC non ne hanno uno.
  const [allenatori, setAllenatori] = useState<Record<string, string>>({})
  const idAllenatori = [casaSq, ospiteSq].filter((t) => t && !t.controllata_da_pc && t.user_id).map((t) => t!.user_id).join(',')
  useEffect(() => {
    if (!idAllenatori) return
    let vivo = true
    void supabase.from('profiles').select('user_id, nome_allenatore').in('user_id', idAllenatori.split(',')).then(({ data: righe }) => {
      if (vivo) setAllenatori(Object.fromEntries((righe ?? []).map((r: { user_id: string; nome_allenatore: string | null }) => [r.user_id, r.nome_allenatore ?? ''])))
    })
    return () => { vivo = false }
  }, [idAllenatori])
  const telecronaca = useMemo<Riga[]>(() => {
    if (!match || !eventi.length || !nomi.size) return []
    return costruisciTelecronaca({
      eventi, nomi,
      titolariCasa: match.titolari_home ?? [], titolariOspite: match.titolari_away ?? [],
      casa: { nome: casaSq?.nome ?? 'Casa', sigla: casaSq?.sigla ?? 'CAS' },
      ospite: { nome: ospiteSq?.nome ?? 'Ospite', sigla: ospiteSq?.sigla ?? 'OSP' },
      allenatoreCasa: casaSq && !casaSq.controllata_da_pc ? allenatori[casaSq.user_id] : null,
      allenatoreOspite: ospiteSq && !ospiteSq.controllata_da_pc ? allenatori[ospiteSq.user_id] : null,
      seme: match.id, supplementari,
    })
  }, [match, eventi, nomi, casaSq, ospiteSq, supplementari, allenatori])
  // Un gol entra in telecronaca solo dopo la sua scena (inTimeline).
  const righeVisibili = useMemo(() => telecronaca.filter((riga) => riga.minuto <= minuto
    && (!riga.gol || inTimeline.has(riga.gol))), [telecronaca, minuto, inTimeline])

  // Il grafico della pressione: la curva e' calcolata una volta su tutta la
  // partita (scala fissa), e si disegna fino al minuto corrente.
  const curva = useMemo(() => curvaPressione(eventi, oraFinale, match?.id ?? 0), [eventi, oraFinale, match?.id])
  const [colori, setColori] = useState<{ casa: string; ospite: string } | null>(null)
  const urlStemmaCasa = fixture ? data.crestUrlByTeamId.get(fixture.home_team_id) : undefined
  const urlStemmaOspite = fixture ? data.crestUrlByTeamId.get(fixture.away_team_id) : undefined
  useEffect(() => {
    let vivo = true
    void Promise.all([coloreStemma(urlStemmaCasa), coloreStemma(urlStemmaOspite)]).then(([c, o]) => {
      if (!vivo) return
      const casaColore = c ?? COLORE_FASE[fase]
      const ospiteColore = o && coloriDistinti(casaColore, o) ? o : coloriDistinti(casaColore, COLORE_OSPITE) ? COLORE_OSPITE : COLORE_FASE[fase]
      setColori({ casa: casaColore, ospite: ospiteColore })
    })
    return () => { vivo = false }
  }, [urlStemmaCasa, urlStemmaOspite, fase])

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
          : <div className="telecronaca">
            <div className="telecronaca__feed" aria-live="polite" aria-label="Telecronaca">
              {[...righeVisibili].reverse().map((riga) => {
                const stemma = riga.lato === 'casa' ? fixture.home_team_id : riga.lato === 'ospite' ? fixture.away_team_id : null
                const squadra = riga.lato === 'casa' ? casa : riga.lato === 'ospite' ? ospite : null
                return <article className={`tc-riga tc-riga--${riga.tipo}${riga.lato ? ` tc-riga--${riga.lato}` : ''}`} key={riga.chiave}
                  style={riga.lato && colori ? { ['--tc-colore' as string]: colori[riga.lato] } : undefined}>
                  <span className="tc-riga__quando">
                    <time>{riga.minuto}’</time>
                    {stemma && <span className="tc-riga__stemma" title={squadra?.nome}><Crest value={squadra?.stemma_url ?? null} imageUrl={data.crestUrlByTeamId.get(stemma)} size="small" /></span>}
                  </span>
                  <span className="tc-riga__icona" aria-hidden="true"><IconaTelecronaca tipo={riga.tipo} /></span>
                  <div className="tc-riga__corpo">
                    {riga.tipo === 'gol' && <b className="tc-riga__titolo">GOL!</b>}
                    <p>{riga.testo.map((parte, k) => typeof parte === 'string' ? parte : <strong key={k}>{parte.g}</strong>)}</p>
                  </div>
                </article>
              })}
            </div>
            <GraficoPressione curva={curva} minuto={minuto} fine={oraFinale} eventi={eventi} colori={colori ?? { casa: COLORE_FASE[fase], ospite: COLORE_OSPITE }}
              sigle={{ casa: casa?.sigla ?? 'CASA', ospite: ospite?.sigla ?? 'OSP' }}
              stemmi={{
                casa: <Crest value={casa?.stemma_url ?? null} imageUrl={data.crestUrlByTeamId.get(fixture.home_team_id)} size="small" />,
                ospite: <Crest value={ospite?.stemma_url ?? null} imageUrl={data.crestUrlByTeamId.get(fixture.away_team_id)} size="small" />,
              }} />
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

// Colori di riserva del grafico, se lo stemma non da' un colore leggibile.
const COLORE_FASE: Record<FaseSquadra, string> = { regular: 'rgb(109, 255, 195)', title: 'rgb(127, 176, 255)', draft: 'rgb(255, 192, 122)' }
const COLORE_OSPITE = 'rgb(242, 244, 248)'

export function IconaTelecronaca({ tipo }: { tipo: Riga['tipo'] }) {
  const comune = { width: 16, height: 16, viewBox: '0 0 16 16', fill: 'none', stroke: 'currentColor', strokeWidth: 1.6, strokeLinecap: 'round' as const, strokeLinejoin: 'round' as const }
  switch (tipo) {
    case 'gol': return <svg {...comune}><circle cx="8" cy="8" r="6.2" /><path d="M8 4.6 10.9 6.7 9.8 10.1H6.2L5.1 6.7Z" fill="currentColor" stroke="none" /></svg>
    case 'parata': return <svg {...comune}><path d="M5 14V7.5M5 7.5V3.8a1 1 0 0 1 2 0V7M7 7V2.8a1 1 0 0 1 2 0V7M9 7V3.5a1 1 0 0 1 2 0V8M11 8V5.8a1 1 0 0 1 2 0V10c0 2.4-1.8 4-4 4H7.5C6 14 5 13 5 11.5" /></svg>
    case 'fuori': return <svg {...comune}><circle cx="5" cy="11" r="2.6" /><path d="M7.5 8.5 13 3M9.5 3H13v3.5" /></svg>
    case 'legno': return <svg {...comune}><path d="M3 14V3h10v11" /><circle cx="12" cy="6" r="2" fill="currentColor" stroke="none" /></svg>
    case 'giallo': return <svg {...comune}><rect x="4.5" y="2.5" width="7" height="11" rx="1.2" fill="#f5c84b" stroke="none" /></svg>
    case 'rosso': return <svg {...comune}><rect x="4.5" y="2.5" width="7" height="11" rx="1.2" fill="#e13e52" stroke="none" /></svg>
    case 'cambio': return <svg {...comune}><path d="M3 5.5h9M9.5 3 12 5.5 9.5 8M13 10.5H4M6.5 8 4 10.5 6.5 13" /></svg>
    case 'infortunio': return <svg {...comune}><path d="M6.3 2.5h3.4v3.8h3.8v3.4H9.7v3.8H6.3V9.7H2.5V6.3h3.8Z" fill="currentColor" stroke="none" /></svg>
    case 'angolo': return <svg {...comune}><path d="M4 14V2.5l7 2.5-7 2.5" /></svg>
    case 'fallo':
    case 'fischio': return <svg {...comune}><circle cx="6" cy="10" r="3.6" /><path d="M8.8 7.6 14 4.5V7l-3.4 2" /></svg>
  }
}

// La pressione offensiva: sopra la linea attacca la squadra di casa, sotto
// l'ospite. Sotto l'asse, i gol e i cartellini rossi al loro minuto.
export function GraficoPressione({ curva, minuto, fine, eventi, colori, sigle, stemmi }: {
  curva: number[]; minuto: number; fine: number; eventi: EventoPartita[]
  colori: { casa: string; ospite: string }; sigle: { casa: string; ospite: string }
  // Gli stemmi a sinistra del grafico, ognuno al centro della sua meta'.
  stemmi?: { casa: ReactNode; ospite: ReactNode }
}) {
  const W = 1000, H = 120
  const id = useId().replace(/:/g, '')
  const { linea, area } = percorsoCurva(curva, minuto, W, H, fine)
  const segni = eventi.filter((e) => e.minuto <= minuto && (isEventoGol(e) || (e.tipo === 'cartellino' && e.colore !== 'giallo')))
  const pct = (m: number) => `${(m / fine) * 100}%`
  return <section className="pressione" aria-label="Pressione offensiva">
    <header className="pressione__testa">
      <span>Pressione offensiva</span>
      <span className="pressione__legenda">
        <i style={{ background: colori.casa }} />{sigle.casa}
        <i style={{ background: colori.ospite }} />{sigle.ospite}
      </span>
    </header>
    <div className={`pressione__corpo${stemmi ? ' con-stemmi' : ''}`}>
    {stemmi && <div className="pressione__stemmi" aria-hidden="true">
      <span title={sigle.casa}>{stemmi.casa}</span>
      <span title={sigle.ospite}>{stemmi.ospite}</span>
    </div>}
    <div className="pressione__area">
      <svg viewBox={`0 0 ${W} ${H}`} preserveAspectRatio="none" aria-hidden="true">
        <defs>
          <clipPath id={`sopra-${id}`}><rect x="0" y="0" width={W} height={H / 2} /></clipPath>
          <clipPath id={`sotto-${id}`}><rect x="0" y={H / 2} width={W} height={H / 2} /></clipPath>
          <linearGradient id={`gc-${id}`} x1="0" y1="0" x2="0" y2="1"><stop offset="0" stopColor={colori.casa} stopOpacity=".95" /><stop offset=".5" stopColor={colori.casa} stopOpacity=".25" /></linearGradient>
          <linearGradient id={`go-${id}`} x1="0" y1="1" x2="0" y2="0"><stop offset="0" stopColor={colori.ospite} stopOpacity=".95" /><stop offset=".5" stopColor={colori.ospite} stopOpacity=".25" /></linearGradient>
        </defs>
        <line x1="0" y1={H / 2} x2={W} y2={H / 2} className="pressione__zero" />
        {[45, ...(fine > 90 ? [90] : [])].map((m) => <line key={m} x1={(m / fine) * W} y1="4" x2={(m / fine) * W} y2={H - 4} className="pressione__tempo" />)}
        {area && <>
          <path d={area} fill={`url(#gc-${id})`} clipPath={`url(#sopra-${id})`} />
          <path d={area} fill={`url(#go-${id})`} clipPath={`url(#sotto-${id})`} />
          <path d={linea} className="pressione__linea" />
        </>}
        {minuto < fine && <line x1={(minuto / fine) * W} y1="2" x2={(minuto / fine) * W} y2={H - 2} className="pressione__cursore" />}
      </svg>
      <div className="pressione__segni">
        {segni.map((e, k) => <span key={k} className={`pressione__segno ${isEventoGol(e) ? 'is-gol' : 'is-rosso'} is-${e.lato}`} style={{ left: `clamp(5px, ${pct(e.minuto)}, calc(100% - 5px))`, ['--tc-colore' as string]: colori[e.lato as 'casa' | 'ospite'] }} title={`${e.minuto}′`} />)}
      </div>
    </div>
    </div>
    <footer className={`pressione__assi${stemmi ? ' con-stemmi' : ''}`}>
      <span>1′</span><span style={{ left: pct(45) }}>Intervallo</span>{fine > 90 && <span style={{ left: pct(90) }}>90′</span>}<span>{fine > 90 ? '120′' : '90′'}</span>
    </footer>
  </section>
}
