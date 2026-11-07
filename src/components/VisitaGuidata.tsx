import { useCallback, useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'
import type { League, Membership } from '../types'
import type { GameView } from './GameNav'

// Visita guidata (7/11/2026, per le quattro squadre nuove della Serie F a 28): un giro su tutte le pagine della lega,
// dentro l'app vera. A ogni tappa si apre la pagina reale, il menu illumina la voce (colonna a sinistra da computer,
// pulsante ☰ da telefono) e una scheda in basso spiega a cosa serve. Parte da sola una volta per chi entra da oggi,
// a stagione in corso; chiunque la rifa' dalla pagina Aiuto. "Vista" vive in hint_visti, come i popup delle pagine.
const CHIAVE = 'visita-guidata'
// Le squadre create prima non la vedono partire da sola: conoscono gia' il gioco.
const AUTOMATICA_DAL = Date.parse('2026-11-06T23:00:00Z')
// Evento con cui la pagina Aiuto la fa ripartire.
export const EVENTO_VISITA = 'specialone:visita-guidata'
// Evento con cui la visita apre e chiude il menu del telefono (lo ascolta GameNav).
export const EVENTO_MENU_MOBILE = 'specialone:menu-mobile'

type Contesto = { league: League; album: boolean; quiz: boolean; telefono: boolean }
type Tappa = {
  id: string
  view: GameView
  percorso: string[]
  titolo: string | ((c: Contesto) => string)
  testo: string | ((c: Contesto) => string)
  quando?: (c: Contesto) => boolean
}

const novita = (c: Contesto) => !!c.league.conferenze_stampa
const inStagione = (c: Contesto) => c.league.stato === 'stagione' && c.league.fase_carriera === 'normale'

const TAPPE: Tappa[] = [
  {
    id: 'benvenuto', view: 'overview', percorso: [],
    titolo: (c) => `Benvenuto in ${c.league.nome}!`,
    testo: 'In un paio di minuti ti faccio vedere tutte le pagine del gioco: dove stanno nel menu e a cosa servono. Puoi uscire quando vuoi e rifare il giro dalla pagina Aiuto.',
  },
  {
    id: 'menu', view: 'overview', percorso: ['Menu'],
    titolo: 'Il menu',
    testo: (c) => c.telefono
      ? 'Tutte le pagine stanno qui, nel menu che apri con ☰ in alto a destra. Le voci sono raggruppate per argomento: tocca un gruppo per aprirlo.'
      : 'Tutte le pagine stanno qui, nella colonna a sinistra. Le voci sono raggruppate per argomento: clicca un gruppo per aprirlo.',
  },
  {
    id: 'overview', view: 'overview', percorso: ['Overview'],
    titolo: 'Overview',
    testo: 'La tua casa: prossima partita, ultimi risultati e cose da fare. Il ritmo è sempre lo stesso: ogni sera alle 22:00 si gioca una giornata, il mercato riapre alle 22:30 e chiude alle 20:00 del giorno dopo.',
  },
  {
    id: 'formazione', view: 'squad', percorso: ['Gestione', 'Formazione'],
    titolo: 'Formazione',
    testo: 'Scegli modulo, stile di gioco, gli 11 titolari e la panchina entro le 22:00. Se non salvi, il sistema schiera una formazione automatica. Un giocatore fuori ruolo rende meno: tienili dove sanno giocare.',
  },
  {
    id: 'club', view: 'team', percorso: ['Gestione', 'Club'],
    titolo: 'Club',
    testo: 'La tua rosa al completo. Tocca un giocatore per aprire la scheda: rinnovo del contratto, prestito, cambio ruolo, piano di sviluppo, vetrina del mercato. Da «Modifica squadra» personalizzi il club.',
  },
  {
    id: 'finanza', view: 'finanza', percorso: ['Gestione', 'Finanza'],
    titolo: 'Finanza',
    testo: 'Qui non si guadagnano soldi: c\'è un tetto ingaggi uguale per tutti, che non cambia mai. Ogni giocatore ne occupa una fetta. Se svincoli qualcuno a stagione in corso, il suo ingaggio resta sul tetto fino a fine contratto.',
  },
  {
    id: 'risorse', view: 'risorse', percorso: ['Gestione', 'Risorse'],
    titolo: 'Risorse',
    testo: (c) => `Quattro volte a stagione ricevi punti abilità da investire in Vivaio, Training, Reparto medico${c.league.stadio_attivo ? ' e Stadio' : ''}. Non bastano per tutto e non si riassegnano: scegli bene la direzione.`,
  },
  {
    id: 'spogliatoio', view: 'spogliatoio', percorso: ['Gestione', 'Spogliatoio'], quando: novita,
    titolo: 'Spogliatoio',
    testo: 'I tuoi giocatori ti scrivono: chi vuole più minuti, chi chiede chiarimenti, il capitano un giorno libero. Rispondi con parole tue, la risposta muove il loro morale. Una richiesta lasciata scadere vale come un no.',
  },
  {
    id: 'freeagent', view: 'mercato', percorso: ['Mercato', 'Free Agent'],
    titolo: 'Free Agent',
    testo: 'Gli svincolati, con aste a busta chiusa. Ogni giorno escono giocatori nuovi: offri un ingaggio e alla chiusura del mercato vince l\'offerta più alta sopra la soglia segreta del giocatore.',
  },
  {
    id: 'scambi', view: 'scambi', percorso: ['Mercato', 'Scambi'],
    titolo: 'Scambi',
    testo: 'Proponi scambi alle altre squadre: giocatori e scelte del draft, mai soldi. Dopo lo scambio entrambe le rose devono stare sotto il tetto e tra 21 e 30 giocatori. Gli scambi conclusi li vede tutta la lega.',
  },
  {
    id: 'scelte', view: 'scelte', percorso: ['Mercato', 'Draft'],
    titolo: 'Draft',
    testo: 'Le tue scelte al draft di fine stagione. L\'ordine dipende dal piazzamento e le scelte si scambiano come i giocatori. Qui prepari anche la lista dei giocatori che vorresti prendere.',
  },
  {
    id: 'under', view: 'under', percorso: ['Mercato', 'UNDER'],
    titolo: 'UNDER',
    testo: 'Ogni giorno escono dei quindicenni all\'asta. Chi vinci va nel vivaio: l\'overall è vero, il potenziale è una fascia nascosta. Entro l\'off-season lo promuovi in prima squadra o lo lasci andare.',
  },
  {
    id: 'partite', view: 'matches', percorso: ['Risultati', 'Partite'],
    titolo: 'Partite',
    testo: 'Calendario e risultati. Le partite appena giocate le scopri in diretta: toccale per vederle, poi apri il tabellino con le statistiche di ogni giocatore.',
  },
  {
    id: 'classifica', view: 'table', percorso: ['Risultati', 'Classifica'],
    titolo: 'Classifica',
    testo: '3 punti a vittoria, 1 a pareggio. A pari punti contano gli scontri diretti, poi la differenza reti, poi i gol fatti.',
  },
  {
    id: 'tabellone', view: 'tabellone', percorso: ['Risultati', 'Tabellone'],
    titolo: 'Tabellone',
    testo: 'I playoff di fine stagione: chi si qualifica e come va a finire, turno per turno.',
  },
  {
    id: 'albo', view: 'honors', percorso: ['Risultati', 'Albo d\'oro'],
    titolo: 'Albo d\'oro',
    testo: 'I vincitori e i premi di ogni stagione passata della lega. Il tuo nome deve finire qui.',
  },
  {
    id: 'social', view: 'social', percorso: ['Extra campo', 'SocialOne'], quando: novita,
    titolo: 'SocialOne',
    testo: 'Il social della lega: giornali, giornalisti, influencer e tifosi commentano partite e mercato. Segui i profili che ti piacciono: in «Per te» vedi prima i loro post.',
  },
  {
    id: 'rivalita', view: 'rivalita', percorso: ['Extra campo', 'Rivalità'], quando: novita,
    titolo: 'Rivalità',
    testo: 'Il grado di rivalità con ogni altra squadra, da 0 a 100%: lo vedete solo tu e l\'altra squadra. Da qui puoi anche cambiare il tuo rivale fisso, il derby.',
  },
  {
    id: 'pubblico', view: 'pubblico', percorso: ['Extra campo', 'Pubblico'], quando: novita,
    titolo: 'Pubblico',
    testo: 'L\'umore dei tuoi tifosi, da 0 a 100. Più sono contenti, più grande è il bonus quando giochi in casa. Il massimo del bonus lo decide il livello dello stadio.',
  },
  {
    id: 'salastampa', view: 'salastampa', percorso: ['Extra campo', 'Sala stampa'], quando: novita,
    titolo: 'Sala stampa',
    testo: 'Prima e dopo le partite i giornalisti ti fanno domande. Rispondi come vuoi: le tue parole vengono valutate e toccano il morale dei giocatori.',
  },
  {
    id: 'sponsor', view: 'sponsor', percorso: ['Extra campo', 'Sponsor'], quando: (c) => novita(c) && !!c.league.stadio_attivo && inStagione(c),
    titolo: 'Sponsor',
    testo: 'Le aziende ti propongono contratti a breve e a lungo termine: ne firmi uno per colonna e, se centri l\'obiettivo, incassi crediti. Alcuni sponsor piacciono ai tifosi, altri no.',
  },
  {
    id: 'schedone', view: 'betone', percorso: ['BetOne', 'SchedOne'], quando: (c) => novita(c) && inStagione(c),
    titolo: 'SchedOne',
    testo: 'La schedina della prossima giornata: 1, X o 2 su ogni partita, al massimo 2 doppie. Si punta con i crediti e chiude 15 minuti prima della simulazione delle 22:00.',
  },
  {
    id: 'casinone', view: 'casinone', percorso: ['BetOne', 'CasinOne'], quando: novita,
    titolo: 'CasinOne',
    testo: 'I giochi del casinò: AviatOne, CrazyOne, BlackjackOne e SlotOne. Si gioca con i crediti, che non toccano mai la squadra: servono qui e per le bustine dell\'album.',
  },
  {
    id: 'quizone', view: 'quizzone', percorso: ['BetOne', 'QuizOne'], quando: (c) => novita(c) && c.quiz,
    titolo: 'QuizOne',
    testo: 'Ogni ora una domanda sulla lega, uguale per tutti. Entri nei primi 10 minuti, gratis o puntando, e se rispondi giusto vinci crediti.',
  },
  {
    id: 'album', view: 'album', percorso: ['Altro', 'Album'], quando: (c) => novita(c) && c.album,
    titolo: 'Album',
    testo: 'Le figurine della lega, una pagina per squadra. Compri bustine con i crediti, ricicli i doppioni e scambi con gli altri. Ogni pagina completa ti dà crediti.',
  },
  {
    id: 'avvisi', view: 'notifications', percorso: ['Avvisi'],
    titolo: 'Avvisi',
    testo: 'Tutto quello che riguarda la tua squadra: partita pronta da vedere, aste vinte o perse, proposte di scambio, richieste dei giocatori. Il pallino sul menu ti dice quando c\'è qualcosa di nuovo.',
  },
  {
    id: 'aiuto', view: 'help', percorso: ['Aiuto'],
    titolo: 'Aiuto',
    testo: 'Qui trovi tutte le regole, spiegate argomento per argomento. Se vuoi rifare questo giro, il pulsante è in cima alla pagina. Buon campionato!',
  },
]

/** Stato della visita: parte da sola una volta (chi entra da oggi, a stagione in corso) o dalla pagina Aiuto. */
export function useVisitaGuidata(membership: Membership | undefined, userId: string | undefined) {
  const [attiva, setAttiva] = useState(false)
  const league = membership?.league
  const candidata = !!membership?.user_id && membership.user_id === userId
    && !!membership.creata_il && Date.parse(membership.creata_il) >= AUTOMATICA_DAL
    && league?.stato === 'stagione' && league.fase_carriera === 'normale'

  useEffect(() => {
    if (!candidata || !userId) return
    let vivo = true
    void supabase.from('hint_visti').select('hint_key').eq('user_id', userId).eq('hint_key', CHIAVE).maybeSingle()
      .then(({ data, error }) => { if (vivo && !error && !data) setAttiva(true) })
    return () => { vivo = false }
  }, [candidata, userId])

  useEffect(() => {
    const avvia = () => setAttiva(true)
    window.addEventListener(EVENTO_VISITA, avvia)
    return () => window.removeEventListener(EVENTO_VISITA, avvia)
  }, [])

  const chiudi = useCallback(() => {
    setAttiva(false)
    if (!userId) return
    // La riga puo' esserci gia' (giro rifatto dall'Aiuto): il doppione viene rifiutato e va bene cosi'.
    void supabase.from('hint_visti').insert({ user_id: userId, hint_key: CHIAVE })
  }, [userId])

  return { attiva, chiudi }
}

const telefonoAdesso = () => window.matchMedia('(max-width: 899px)').matches

export function VisitaGuidata({ league, onNavigate, onChiudi }: {
  league: League
  onNavigate: (view: GameView) => void
  onChiudi: () => void
}) {
  const [album, setAlbum] = useState(false)
  const [quiz, setQuiz] = useState(false)
  const [telefono, setTelefono] = useState(telefonoAdesso)
  const [indice, setIndice] = useState(0)

  useEffect(() => {
    if (!league.conferenze_stampa) return
    void supabase.rpc('album_attivo', { p_league_id: league.id }).then(({ data }) => setAlbum(data === true))
    void supabase.rpc('quizzone_attivo', { p_league_id: league.id }).then(({ data }) => setQuiz(data === true))
  }, [league.id, league.conferenze_stampa])

  useEffect(() => {
    const mq = window.matchMedia('(max-width: 899px)')
    const cambia = () => setTelefono(mq.matches)
    mq.addEventListener('change', cambia)
    return () => mq.removeEventListener('change', cambia)
  }, [])

  const contesto: Contesto = { league, album, quiz, telefono }
  const tappe = TAPPE.filter((t) => !t.quando || t.quando(contesto))
  const tappa = tappe[Math.min(indice, tappe.length - 1)]
  const ultima = indice >= tappe.length - 1

  // Ogni tappa apre la sua pagina, dall'alto.
  useEffect(() => {
    onNavigate(tappa.view)
    window.scrollTo(0, 0)
  }, [tappa.id]) // eslint-disable-line react-hooks/exhaustive-deps

  // Il menu: da telefono si apre il cassetto vero, da computer si illumina la colonna.
  const tappaMenu = tappa.id === 'menu'
  useEffect(() => {
    if (!tappaMenu || !telefono) return
    window.dispatchEvent(new CustomEvent(EVENTO_MENU_MOBILE, { detail: true }))
    return () => { window.dispatchEvent(new CustomEvent(EVENTO_MENU_MOBILE, { detail: false })) }
  }, [tappaMenu, telefono])

  // Le classi sul body accendono la voce di menu della pagina (styles.css, "Visita guidata") e nascondono i popup
  // di spiegazione delle pagine, che restano per quando ci si torna da soli.
  useEffect(() => {
    document.body.classList.add('visita-attiva')
    return () => document.body.classList.remove('visita-attiva')
  }, [])
  useEffect(() => {
    document.body.classList.toggle('visita-menu', tappaMenu)
    return () => document.body.classList.remove('visita-menu')
  }, [tappaMenu])

  useEffect(() => {
    const tasto = (e: KeyboardEvent) => {
      if (e.key === 'ArrowRight') setIndice((i) => Math.min(i + 1, tappe.length - 1))
      if (e.key === 'ArrowLeft') setIndice((i) => Math.max(i - 1, 0))
    }
    window.addEventListener('keydown', tasto)
    return () => window.removeEventListener('keydown', tasto)
  }, [tappe.length])

  const titolo = typeof tappa.titolo === 'function' ? tappa.titolo(contesto) : tappa.titolo
  const testo = typeof tappa.testo === 'function' ? tappa.testo(contesto) : tappa.testo
  const percorso = tappa.percorso.length && tappa.id !== 'menu'
    ? [telefono ? '☰ Menu' : 'Menu', ...tappa.percorso]
    : []

  return <section className="visita" role="dialog" aria-modal="false" aria-label="Visita guidata">
    <div className="visita__testa">
      <span className="visita__conto">Visita guidata <b>{indice + 1}</b>/{tappe.length}</span>
      <button type="button" className="visita__salta" onClick={onChiudi}>{ultima ? 'Chiudi' : 'Salta'}</button>
    </div>
    <div className="visita__barra" aria-hidden="true"><i style={{ width: `${((indice + 1) / tappe.length) * 100}%` }} /></div>
    {percorso.length > 0 && <ol className="visita__percorso" aria-label="Dove si trova nel menu">
      {percorso.map((p, i) => <li key={p} className={i === percorso.length - 1 ? 'is-qui' : undefined}>{p}</li>)}
    </ol>}
    <h2 key={`t-${tappa.id}`} className="visita__titolo">{titolo}</h2>
    <p key={`p-${tappa.id}`} className="visita__corpo">{testo}</p>
    <div className="visita__azioni">
      <button type="button" className="visita__indietro" onClick={() => setIndice((i) => Math.max(i - 1, 0))} disabled={indice === 0}>Indietro</button>
      <button type="button" className="visita__avanti" onClick={() => ultima ? onChiudi() : setIndice((i) => i + 1)}>
        {indice === 0 ? 'Iniziamo' : ultima ? 'Inizia a giocare' : 'Avanti'}
      </button>
    </div>
  </section>
}
