import { isEventoGol, type EventoPartita } from '../types'
import { cognome } from './nomi'

// La telecronaca della partita live: ogni evento della cronaca diventa una
// frase da radiocronista, con i nomi veri. Le frasi sono tante e diverse per
// ogni tipo di evento, e dipendono dal contesto (vantaggio, pareggio, rimonta,
// minuto, ruolo di chi segna e di chi fa l'assist). La scelta e' fissa per
// partita: rivedendo la stessa partita si ascolta la stessa telecronaca.
//
// Falli senza cartellino e calci d'angolo sono racconto di colore: il motore
// non li simula e non entrano in nessuna statistica (deciso col committente il
// 2 ottobre 2026). Tutto il resto racconta solo cio' che e' successo davvero.

type Lato = 'casa' | 'ospite'
export type Parte = string | { g: string }
export type TipoRiga = 'gol' | 'parata' | 'fuori' | 'legno' | 'giallo' | 'rosso' | 'cambio' | 'infortunio' | 'fallo' | 'angolo' | 'fischio'
export type Riga = {
  chiave: string
  minuto: number
  lato: Lato | null
  tipo: TipoRiga
  testo: Parte[]
  // Per i gol: l'evento originale, che entra in telecronaca solo dopo la
  // scena del gol (stesso meccanismo della vecchia cronaca).
  gol?: EventoPartita
}

export type GiocatoreTelecronaca = { nome: string; posizioni?: string[] }
type Squadra = { nome: string; sigla: string }

export type DatiTelecronaca = {
  eventi: EventoPartita[]
  nomi: Map<number, GiocatoreTelecronaca>
  titolariCasa: number[]
  titolariOspite: number[]
  casa: Squadra
  ospite: Squadra
  // Il nome dell'allenatore (profiles.nome_allenatore); le squadre del PC
  // non ce l'hanno e i cambi si raccontano col nome della squadra.
  allenatoreCasa?: string | null
  allenatoreOspite?: string | null
  seme: number
  supplementari: boolean
  // Tiri raccontati al massimo per squadra: gli altri restano nelle
  // statistiche e nel grafico della pressione, non in telecronaca.
  maxTiri?: number
}

// ---------------------------------------------------------------------------
// Frasi. Segnaposto: {A} protagonista, {B} secondo giocatore (assist, chi
// entra, chi subisce il fallo), {P} portiere avversario, {S} squadra del
// protagonista, {O} squadra avversaria. I nomi dei giocatori escono in grassetto.

const GOL_CROSS = [
  '{B} la mette in mezzo, arriva prima di tutti {A}! La schiaccia di testa e la palla entra in rete!',
  'Cross teso di {B} dalla fascia, {A} anticipa il difensore e insacca sul primo palo!',
  '{B} va sul fondo e crossa: {A} si coordina al volo e la mette sotto la traversa!',
  'Traversone morbido di {B}, {A} sale in cielo e incorna: niente da fare per {P}!',
  '{B} scappa sulla fascia e serve un pallone d\'oro: {A} deve solo spingerla dentro!',
  'Palla bassa di {B} a centro area, {A} arriva in scivolata e la butta dentro!',
]
const GOL_FILTRANTE = [
  'Filtrante perfetto di {B}, {A} si presenta davanti a {P} e non sbaglia!',
  '{B} vede il corridoio e lo serve: {A} controlla, salta {P} e deposita in rete!',
  'Lancio di {B} sopra la difesa, {A} scatta sul filo del fuorigioco e batte {P} in uscita!',
  'Uno-due rapidissimo fra {B} e {A}, che entra in area e incrocia sul secondo palo!',
  '{B} taglia in due la difesa con un passaggio geniale: {A} a tu per tu con {P}… gol!',
  'Imbucata di {B}, {A} brucia il difensore e la piazza nell\'angolino!',
]
const GOL_SPONDA = [
  'Sponda di testa di {B}, {A} arriva a rimorchio e calcia di prima: gol!',
  '{B} fa a sportellate e la lascia per {A}, che dal limite la infila all\'angolo!',
  'Tocco di {B} spalle alla porta, {A} si inserisce e batte {P}!',
]
const GOL_RIMORCHIO = [
  'Scarico arretrato di {B}, {A} arriva a rimorchio e la piazza dove {P} non arriva!',
  '{B} rientra e appoggia per {A}: piattone preciso, palla in fondo al sacco!',
  'Ripartenza fulminea, {B} allarga per {A} che entra in area e fulmina {P}!',
]
const GOL_SOLO_ATT = [
  '{A} punta il difensore, lo salta, entra in area e tira: gol! Che azione!',
  '{A} ruba palla al limite, si gira e calcia: la palla si infila all\'angolino!',
  'Mischia in area, la palla resta lì e {A} è il più lesto di tutti: gol!',
  'Respinta corta di {P}, {A} è il primo sulla ribattuta e insacca!',
  '{A} si accentra e lascia partire un destro a giro: palla sotto il sette!',
  'Errore in disimpegno della difesa, {A} ringrazia e la mette dentro!',
]
const GOL_SOLO_DISTANZA = [
  '{A} prende la mira da fuori area… che bolide! Palla all\'incrocio, {P} immobile!',
  'Conclusione dalla distanza di {A}: la palla si abbassa all\'improvviso e beffa {P}!',
  '{A} ci prova da trenta metri: un missile che si infila sotto la traversa!',
  'Botta di collo pieno di {A} dal limite: {P} tocca ma non basta!',
]
const GOL_SOLO_DIFENSORE = [
  'Il difensore {A} si sgancia in avanti e trova il gol: che sorpresa!',
  '{A} si inserisce a sorpresa in area e la mette dentro!',
  'Mischia furibonda in area, {A} è il più lesto di tutti: gol!',
]
// Gol da calcio piazzato (arrivano dal motore col tipo e con chi ha battuto).
const GOL_ANGOLO = [
  'Calcio d\'angolo di {B}, stacco imperioso di {A}: gol!',
  'Corner a rientrare di {B}, {A} svetta più in alto di tutti e incorna: {P} battuto!',
  'Dalla bandierina {B}, sul primo palo spunta {A} che la gira in rete!',
  'Angolo battuto da {B}, mischia in area e {A} la spinge dentro!',
]
const GOL_ANGOLO_SOLO = [
  'Sugli sviluppi di un calcio d\'angolo, {A} è il più lesto di tutti: gol!',
  'Corner, palla che spiove in area, {A} incorna: rete!',
]
const GOL_PUNIZIONE_CORTA = [
  'Punizione dal limite: {A} la calcia sopra la barriera… gol! {P} non può arrivarci!',
  '{A} sistema il pallone, rincorsa… punizione perfetta all\'incrocio!',
  'Calcio piazzato di {A}: la palla aggira la barriera e si infila sul palo di {P}!',
  'Che punizione di {A}! Una parabola imprendibile!',
]
const GOL_PUNIZIONE_LUNGA = [
  'Punizione messa in mezzo da {B}, {A} di testa la mette dentro!',
  '{B} pennella la punizione in area, {A} anticipa tutti: gol!',
  'Calcio piazzato di {B} dalla trequarti, sponda e {A} insacca da due passi!',
]

const CODA_GOL: Record<string, string[]> = {
  sblocca: ['{S} passa in vantaggio!', 'Si sblocca la partita: avanti {S}!', 'È {S} a rompere l\'equilibrio!'],
  vantaggio: ['{S} torna avanti!', 'Di nuovo in vantaggio {S}!', 'Ancora avanti {S}!'],
  pareggio: ['{S} la riprende!', 'Pareggio di {S}, tutto da rifare!', 'Si torna in parità!'],
  raddoppio: ['{S} raddoppia!', 'Doppio vantaggio per {S}!', '{S} allunga!'],
  goleada: ['{S} dilaga!', 'Notte da incubo per {O}!', '{S} non si ferma più!'],
  accorcia: ['{S} accorcia le distanze!', '{S} torna in partita!', 'Si riapre tutto?'],
  avvicina: ['{S} accorcia le distanze.', '{S} prova a rientrare in partita.'],
  bandiera: ['Gol della bandiera per {S}.', '{S} rende meno amaro il passivo.', 'Magra consolazione per {S}.'],
  sorpasso: ['Rimonta completata: {S} avanti!', 'Sorpasso di {S}!', '{S} ribalta la partita!'],
  allungo: ['{S} mette al sicuro il risultato?', 'Altro gol di {S}!'],
}
const TEMPO_GOL = {
  freddo: ['A freddo!', 'Dopo pochi minuti!', 'Partenza a razzo!'],
  scadere: ['Allo scadere del primo tempo!', 'Proprio prima dell\'intervallo!'],
  finale: ['Nel finale!', 'A pochi minuti dalla fine!', 'Quando ormai sembrava finita!'],
  supplementari: ['Ai supplementari!', 'Nei tempi supplementari!'],
}

const PARATA = [
  '{A} entra in area, tira! Grande risposta di {P}!',
  'Conclusione di {A} dal limite: {P} si allunga e devia in angolo!',
  '{A} ci prova di testa, {P} blocca senza problemi.',
  'Botta di {A}, {P} respinge coi pugni!',
  '{A} a tu per tu con il portiere… {P} esce e chiude lo specchio! Parata decisiva!',
  'Destro velenoso di {A}, {P} vola e la toglie dall\'incrocio!',
  'Tiro rasoterra di {A}, {P} si distende e para.',
  '{A} calcia in diagonale: {P} c\'è, e in due tempi fa sua la palla.',
  'Punizione di {A} dal limite, {P} la vede partire e la blocca.',
  '{A} si libera e conclude: miracolo di {P}!',
]
const FUORI = [
  '{A} prova la conclusione, palla alta sopra la traversa.',
  'Tiro di {A} dal limite: di poco a lato!',
  '{A} di testa, la palla sfila sul fondo.',
  'Destro di {A} da fuori area, fuori misura.',
  '{A} calcia di prima intenzione, ma la mira è sbagliata.',
  'Occasione per {A}! Solo davanti alla porta… la manda fuori!',
  '{A} ci prova al volo: palla in curva.',
  'Diagonale di {A} che sfiora il palo e si spegne sul fondo.',
  '{A} si gira in area e calcia: murato dalla difesa.',
]
const LEGNO = [
  '{A} calcia… palo! Che sfortuna per {S}!',
  'Traversa di {A}! Il pallone trema sulla linea ed esce!',
  '{A} colpisce il legno! {P} era battuto!',
]
const GIALLO_FALLO = [
  'Entrataccia di {A} su {B}: l\'arbitro estrae il giallo.',
  '{A} ferma {B} in ripartenza: fallo tattico e ammonizione.',
  'Intervento in ritardo di {A} su {B}: cartellino giallo.',
  '{A} trattiene {B} per la maglia: ammonito.',
  'Scontro duro fra {A} e {B}, il giallo è per {A}.',
]
const GIALLO_ALTRO = [
  'Proteste vibranti di {A}: l\'arbitro lo ammonisce.',
  '{A} perde tempo sulla rimessa: giallo.',
  'Ammonito {A} per simulazione!',
]
const ROSSO = [
  'Intervento a gamba tesa di {A} su {B}! Rosso diretto!',
  '{A} commette un fallo da ultimo uomo su {B}: espulso!',
  'Che follia di {A}! Gomitata a {B}, l\'arbitro non ha dubbi: rosso!',
]
const DOPPIO_GIALLO = [
  'Secondo giallo per {A}! {S} resta in {N}!',
  '{A} stende {B}: è il secondo giallo, va sotto la doccia!',
  'Doppia ammonizione per {A}: {S} in {N}!',
]
const FALLO = [
  'Fallo di {A} su {B} a centrocampo: punizione per {O}.',
  '{A} va giù dopo il contrasto con {B}, l\'arbitro lascia correre.',
  'Spinta di {A} su {B}, fischia l\'arbitro.',
  '{A} anticipa {B} con le cattive: punizione.',
  'Partita maschia: duello rusticano fra {A} e {B}.',
]
const ANGOLO = [
  'Calcio d\'angolo per {S}: lo batte {A}… la difesa libera.',
  '{S} guadagna un corner. Sul primo palo spazza {B}.',
  'Corner di {A}, la difesa di {O} si salva in qualche modo.',
  'Angolo corto di {S}, {A} prova il cross ma {B} allontana di testa.',
]
// Cambi raccontati attraverso l'allenatore: {T} e' il suo nome, {C} l'elenco
// dei cambi ("dentro X per Y").
const CAMBIO_ALLENATORE = [
  '{T} decide di cambiare qualcosa: {C}.',
  '{T} pesca dalla panchina: {C}.',
  'Si muove {T}: {C}.',
  '{T} prova a dare una scossa ai suoi: {C}.',
  'Mossa di {T}: {C}.',
]
const CAMBI_ALLENATORE = [
  '{T} rivoluziona la squadra: {C}.',
  '{T} cambia volto ai suoi: {C}.',
  'Doppia mossa di {T}: {C}.',
]
const CAMBIO_INTERVALLO = [
  '{T} cambia all\'intervallo: {C}.',
  'Negli spogliatoi {T} ha deciso: {C}.',
]
const INFORTUNIO = [
  '{A} resta a terra dopo uno scontro… non ce la fa: al suo posto {B}.',
  'Problema muscolare per {A}, che chiede il cambio. Entra {B}.',
  'Brutta notizia per {S}: {A} esce in barella. Dentro {B}.',
  '{A} si tocca la coscia e alza bandiera bianca. Lo sostituisce {B}.',
]

const INFORTUNIO_ALLENATORE = [
  '{A} resta a terra dopo uno scontro… {T} è costretto al cambio: dentro {B}.',
  'Problema fisico per {A}: {T} manda subito a scaldare {B}, che entra al suo posto.',
  '{A} non ce la fa. {T} allarga le braccia e si affida a {B}.',
]

// ---------------------------------------------------------------------------

// Generatore deterministico per partita (mulberry32).
function creaRnd(seme: number) {
  let a = seme >>> 0
  return () => {
    a = (a + 0x6d2b79f5) >>> 0
    let t = a
    t = Math.imul(t ^ (t >>> 15), t | 1)
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61)
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
}

const REPARTO: Record<string, 'GK' | 'DEF' | 'MID' | 'ATT'> = {
  GK: 'GK', CB: 'DEF', LB: 'DEF', RB: 'DEF', LWB: 'DEF', RWB: 'DEF',
  CDM: 'MID', CM: 'MID', CAM: 'MID', LM: 'MID', RM: 'MID',
  LW: 'ATT', RW: 'ATT', ST: 'ATT', CF: 'ATT',
}
const FASCIA = new Set(['LB', 'RB', 'LWB', 'RWB', 'LM', 'RM', 'LW', 'RW'])

export function costruisciTelecronaca(d: DatiTelecronaca): Riga[] {
  const rnd = creaRnd(d.seme * 2654435761)
  // Mai la stessa frase due volte di fila per lo stesso tipo: si pesca senza
  // rimettere finche' la lista non e' esaurita.
  const usate = new Map<string[], Set<number>>()
  const pesca = (lista: string[]) => {
    let fatte = usate.get(lista)
    if (!fatte || fatte.size >= lista.length) { fatte = new Set(); usate.set(lista, fatte) }
    let i = Math.floor(rnd() * lista.length)
    while (fatte.has(i)) i = (i + 1) % lista.length
    fatte.add(i)
    return lista[i]
  }
  const nome = (id: number | null | undefined) => id == null ? '' : cognome(d.nomi.get(id)?.nome ?? '').toUpperCase()
  const reparto = (id: number) => REPARTO[d.nomi.get(id)?.posizioni?.[0] ?? ''] ?? 'MID'
  const suFascia = (id: number) => FASCIA.has(d.nomi.get(id)?.posizioni?.[0] ?? '')
  const squadra = (lato: Lato) => (lato === 'casa' ? d.casa : d.ospite).nome
  const altro = (lato: Lato): Lato => (lato === 'casa' ? 'ospite' : 'casa')
  const allenatore = (lato: Lato) => (lato === 'casa' ? d.allenatoreCasa : d.allenatoreOspite)?.trim().toUpperCase() || null

  const componi = (modello: string, v: { A?: number | null; B?: number | null; P?: number | null; lato: Lato; N?: string }): Parte[] => {
    const parti: Parte[] = []
    for (const pezzo of modello.split(/(\{[ABPSONT]\})/)) {
      if (pezzo === '{A}') parti.push({ g: nome(v.A) })
      else if (pezzo === '{B}') parti.push({ g: nome(v.B) })
      else if (pezzo === '{P}') parti.push({ g: nome(v.P) || 'il portiere' })
      else if (pezzo === '{S}') parti.push(squadra(v.lato))
      else if (pezzo === '{O}') parti.push(squadra(altro(v.lato)))
      else if (pezzo === '{N}') parti.push(v.N ?? 'dieci')
      else if (pezzo === '{T}') parti.push({ g: allenatore(v.lato) ?? squadra(v.lato) })
      else if (pezzo) parti.push(pezzo)
    }
    return parti
  }

  // Chi e' in campo minuto per minuto, per i portieri avversari, le vittime
  // dei falli e il conto degli uomini dopo un'espulsione.
  const eventi = [...d.eventi].sort((a, b) => a.minuto - b.minuto)
  const inCampo = (lato: Lato, minuto: number) => {
    const set = new Set(lato === 'casa' ? d.titolariCasa : d.titolariOspite)
    for (const e of eventi) {
      if (e.minuto > minuto || e.lato !== lato) continue
      if (e.tipo === 'sostituzione' || e.tipo === 'infortunio') { set.delete(e.esce); set.add(e.entra) }
      if (e.tipo === 'cartellino' && e.colore !== 'giallo' && e.minuto < minuto) set.delete(e.giocatore)
    }
    return set
  }
  const portiere = (lato: Lato, minuto: number) => {
    const titolare = (lato === 'casa' ? d.titolariCasa : d.titolariOspite)[0]
    let id = titolare
    for (const e of eventi) if (e.minuto <= minuto && e.lato === lato && (e.tipo === 'sostituzione' || e.tipo === 'infortunio') && e.esce === id) id = e.entra
    return id ?? null
  }
  const unoDi = (ids: number[]) => ids.length ? ids[Math.floor(rnd() * ids.length)] : null

  const righe: Riga[] = []
  const fine = d.supplementari ? 120 : 90

  // Fischi: inizio, intervallo, ripresa, fine (e supplementari).
  const punteggioAl = (minuto: number) => eventi.filter((e) => isEventoGol(e) && e.minuto <= minuto)
    .reduce((t, e) => { t[e.lato]++; return t }, { casa: 0, ospite: 0 } as Record<Lato, number>)
  const risultato = (minuto: number) => {
    const p = punteggioAl(minuto)
    return `${d.casa.sigla} ${p.casa}–${p.ospite} ${d.ospite.sigla}`
  }
  righe.push({ chiave: 'fischio-0', minuto: 0, lato: null, tipo: 'fischio', testo: [`Fischio d'inizio! ${d.casa.nome} contro ${d.ospite.nome}, si parte.`] })
  righe.push({ chiave: 'fischio-45', minuto: 45, lato: null, tipo: 'fischio', testo: [`Fine primo tempo: ${risultato(45)}.`] })
  righe.push({ chiave: 'fischio-46', minuto: 46, lato: null, tipo: 'fischio', testo: ['Si riparte: comincia la ripresa.'] })
  if (d.supplementari) {
    righe.push({ chiave: 'fischio-90', minuto: 90, lato: null, tipo: 'fischio', testo: [`Finiscono i tempi regolamentari: ${risultato(90)}. Si va ai supplementari!`] })
    righe.push({ chiave: 'fischio-105', minuto: 105, lato: null, tipo: 'fischio', testo: [`Fine del primo supplementare: ${risultato(105)}.`] })
  }
  righe.push({ chiave: `fischio-${fine}`, minuto: fine, lato: null, tipo: 'fischio', testo: [`Triplice fischio! Finisce ${risultato(fine)}.`] })

  // Tiri: solo una parte arriva in telecronaca, distribuita su tutta la
  // partita (le parate prima, sono le piu' raccontabili).
  const maxTiri = d.maxTiri ?? 6
  const tiriTenuti = new Set<EventoPartita>()
  for (const lato of ['casa', 'ospite'] as Lato[]) {
    // Un portiere che tira e' un residuo di una vecchia distribuzione dei tiri
    // (corretta il 2 ottobre 2026): in telecronaca non si racconta.
    const tiri = eventi.filter((e) => e.lato === lato && (e.tipo === 'tiro_parato' || e.tipo === 'tiro_fuori') && reparto(e.giocatore) !== 'GK')
    if (tiri.length <= maxTiri) { tiri.forEach((t) => tiriTenuti.add(t)); continue }
    const parati = tiri.filter((t) => t.tipo === 'tiro_parato')
    const scelti = [...parati.slice(0, Math.ceil(maxTiri * 0.6)), ...tiri.filter((t) => t.tipo === 'tiro_fuori')]
    const passo = scelti.length / maxTiri
    const ordinati = scelti.sort((a, b) => a.minuto - b.minuto)
    for (let i = 0; i < maxTiri; i++) tiriTenuti.add(ordinati[Math.floor(i * passo)])
  }

  // Cambi dello stesso minuto e della stessa squadra in una sola riga.
  const cambiRaccolti = new Set<EventoPartita>()

  let golCasa = 0, golOspite = 0
  // Il punto piu' basso toccato da ogni squadra (gol di scarto): serve a
  // riconoscere una rimonta.
  const statoPeggiore: Record<Lato, number> = { casa: 0, ospite: 0 }
  eventi.forEach((e, indice) => {
    const chiave = `${e.tipo}-${e.minuto}-${e.lato}-${indice}`
    const lato = e.lato as Lato
    if (isEventoGol(e)) {
      const prima = lato === 'casa' ? golCasa - golOspite : golOspite - golCasa
      if (lato === 'casa') golCasa++; else golOspite++
      const dopo = prima + 1
      const P = portiere(altro(lato), e.minuto)
      let modello: string
      if (e.piazzato) {
        modello = pesca(e.piazzato.startsWith('angolo') ? (e.assist != null ? GOL_ANGOLO : GOL_ANGOLO_SOLO)
          : e.piazzato === 'punizione_corta' ? GOL_PUNIZIONE_CORTA
          : e.assist != null ? GOL_PUNIZIONE_LUNGA : GOL_ANGOLO_SOLO)
      } else if (e.assist != null) {
        const r = reparto(e.assist)
        modello = pesca(suFascia(e.assist) ? GOL_CROSS : r === 'ATT' ? (rnd() < 0.5 ? GOL_SPONDA : GOL_FILTRANTE) : rnd() < 0.6 ? GOL_FILTRANTE : GOL_RIMORCHIO)
      } else {
        const r = reparto(e.marcatore)
        modello = pesca(r === 'DEF' || r === 'GK' ? GOL_SOLO_DIFENSORE : r === 'MID' && rnd() < 0.55 ? GOL_SOLO_DISTANZA : rnd() < 0.25 ? GOL_SOLO_DISTANZA : GOL_SOLO_ATT)
      }
      const contesto = dopo === 1 && statoPeggiore[lato] < 0 ? 'sorpasso'
        : prima === 0 ? (golCasa + golOspite === 1 ? 'sblocca' : 'vantaggio') : dopo === 0 ? 'pareggio'
        : dopo === 2 ? 'raddoppio' : dopo >= 4 ? 'goleada' : dopo === 3 ? 'allungo'
        : dopo === -1 ? 'accorcia' : dopo === -2 ? 'avvicina' : 'bandiera'
      statoPeggiore[lato] = Math.min(statoPeggiore[lato], dopo)
      statoPeggiore[altro(lato)] = Math.min(statoPeggiore[altro(lato)], -dopo)
      const tempo = e.minuto > 90 ? TEMPO_GOL.supplementari : e.minuto <= 5 ? TEMPO_GOL.freddo
        : e.minuto >= 42 && e.minuto <= 45 ? TEMPO_GOL.scadere
        // "Quando ormai sembrava finita" ha senso solo se il gol cambia davvero
        // la partita: pareggio, sorpasso, vantaggio o un gol che la riapre.
        : e.minuto >= 85 && Math.abs(dopo) <= 1 ? TEMPO_GOL.finale : null
      const coda = [pesca(CODA_GOL[contesto]), ...(tempo && rnd() < 0.7 ? [pesca(tempo)] : [])].join(' ')
      righe.push({ chiave, minuto: e.minuto, lato, tipo: 'gol', gol: e, testo: [...componi(modello, { A: e.marcatore, B: e.assist, P, lato }), ' ', ...componi(coda, { lato })] })
      return
    }
    if (e.tipo === 'tiro_parato' || e.tipo === 'tiro_fuori') {
      if (!tiriTenuti.has(e)) return
      const P = portiere(altro(lato), e.minuto)
      const legno = e.tipo === 'tiro_fuori' && rnd() < 0.14
      const modello = pesca(e.tipo === 'tiro_parato' ? PARATA : legno ? LEGNO : FUORI)
      righe.push({ chiave, minuto: e.minuto, lato, tipo: e.tipo === 'tiro_parato' ? 'parata' : legno ? 'legno' : 'fuori', testo: componi(modello, { A: e.giocatore, P, lato }) })
      return
    }
    if (e.tipo === 'cartellino') {
      const avversari = [...inCampo(altro(lato), e.minuto)].filter((id) => id !== portiere(altro(lato), e.minuto))
      const B = unoDi(avversari)
      if (e.colore === 'giallo') {
        const modello = B != null && rnd() < 0.8 ? pesca(GIALLO_FALLO) : pesca(GIALLO_ALTRO)
        righe.push({ chiave, minuto: e.minuto, lato, tipo: 'giallo', testo: componi(modello, { A: e.giocatore, B, lato }) })
      } else {
        const rimasti = inCampo(lato, e.minuto).size - 1
        const N = ['', 'uno', 'due', 'tre', 'quattro', 'cinque', 'sei', 'sette', 'otto', 'nove', 'dieci'][Math.max(0, rimasti)] ?? String(rimasti)
        const modello = pesca(e.colore === 'doppio_giallo' ? DOPPIO_GIALLO : ROSSO)
        righe.push({ chiave, minuto: e.minuto, lato, tipo: 'rosso', testo: componi(modello, { A: e.giocatore, B, lato, N }) })
      }
      return
    }
    if (e.tipo === 'infortunio') {
      const modello = pesca(allenatore(lato) && rnd() < 0.6 ? INFORTUNIO_ALLENATORE : INFORTUNIO)
      righe.push({ chiave, minuto: e.minuto, lato, tipo: 'infortunio', testo: componi(modello, { A: e.esce, B: e.entra, lato }) })
      return
    }
    if (e.tipo === 'sostituzione') {
      if (cambiRaccolti.has(e)) return
      const gruppo = eventi.filter((x) => x.tipo === 'sostituzione' && x.lato === e.lato && x.minuto === e.minuto) as Array<Extract<EventoPartita, { tipo: 'sostituzione' }>>
      gruppo.forEach((x) => cambiRaccolti.add(x))
      const all = e.minuto === 46 ? 'all\'intervallo' : e.minuto === 91 ? 'prima dei supplementari' : ''
      const elenco: Parte[] = []
      gruppo.forEach((x, k) => {
        if (k > 0) elenco.push(k === gruppo.length - 1 ? ' e ' : ', ')
        elenco.push(k === 0 ? 'dentro ' : '', { g: nome(x.entra) }, ' per ', { g: nome(x.esce) })
        if (x.motivo === 'rendimento') elenco.push(' (non in giornata)')
      })
      let testo: Parte[]
      if (allenatore(lato)) {
        const modello = pesca(e.minuto === 46 ? CAMBIO_INTERVALLO : gruppo.length > 1 ? CAMBI_ALLENATORE : CAMBIO_ALLENATORE)
        testo = componi(modello, { lato }).flatMap((parte) => parte === '{C}' ? elenco : typeof parte === 'string' && parte.includes('{C}')
          ? parte.split('{C}').flatMap((pezzo, k) => k === 0 ? [pezzo] : [...elenco, pezzo]) : [parte])
      } else {
        const apertura = gruppo.length === 1
          ? (all ? `${squadra(lato)} cambia ${all}: ` : rnd() < 0.5 ? `Cambio per ${squadra(lato)}: ` : `Mossa dalla panchina di ${squadra(lato)}: `)
          : `${gruppo.length === 2 ? 'Doppio' : 'Triplo'} cambio per ${squadra(lato)}${all ? ' ' + all : ''}: `
        testo = [apertura, ...elenco, '.']
      }
      righe.push({ chiave, minuto: e.minuto, lato, tipo: 'cambio', testo })
    }
  })

  // Racconto di colore: qualche fallo e qualche angolo nei minuti liberi.
  const occupati = new Set(righe.map((r) => r.minuto))
  const quanti = 4 + Math.floor(rnd() * 4)
  for (let k = 0; k < quanti; k++) {
    const minuto = 3 + Math.floor(rnd() * (fine - 6))
    if (occupati.has(minuto) || occupati.has(minuto - 1) || occupati.has(minuto + 1) || minuto === 45 || minuto === 46) continue
    occupati.add(minuto)
    const lato: Lato = rnd() < 0.5 ? 'casa' : 'ospite'
    const miei = [...inCampo(lato, minuto)].filter((id) => id !== portiere(lato, minuto))
    const loro = [...inCampo(altro(lato), minuto)].filter((id) => id !== portiere(altro(lato), minuto))
    const A = unoDi(miei), B = unoDi(loro)
    if (A == null || B == null) continue
    const angolo = rnd() < 0.4
    righe.push({ chiave: `colore-${minuto}`, minuto, lato, tipo: angolo ? 'angolo' : 'fallo', testo: componi(pesca(angolo ? ANGOLO : FALLO), { A, B: angolo ? unoDi(loro) : B, lato }) })
  }

  return righe.sort((a, b) => a.minuto - b.minuto || ordineTipo(a.tipo) - ordineTipo(b.tipo))
}

// Nello stesso minuto: prima l'azione, poi i fischi di fine tempo.
function ordineTipo(tipo: TipoRiga) {
  return tipo === 'fischio' ? 1 : 0
}
