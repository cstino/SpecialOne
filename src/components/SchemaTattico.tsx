// ============================================================
//  SCHEMA TATTICO — postazioni, ruoli e compiti
//
//  Si trascina una card su una postazione libera, come nelle tattiche
//  personalizzate di FC: le postazioni sono fisse (src/lib/schieramento.ts) e
//  la card ci si attacca a calamita. Toccandola senza trascinare si aprono
//  ruolo e compito.
//
//  NIENTE NOMI DI GIOCATORE. Qui si decide come gioca la SQUADRA: chi occupa
//  quella posizione lo si sceglie nella formazione, e mostrarlo qui faceva
//  sembrare la schermata una seconda distinta — oltre a gonfiare le card al
//  punto da farle sovrapporre.
//
//  IL DIVIETO. Una postazione ospita un giocatore solo. Sulle fasce e' il
//  vincolo che conta davvero (di LB ce n'e' una sola), al centro lascia fino a
//  tre: e' quello che distingue un centrocampo a due da uno a tre.
//
//  LE DUE BARRE IN TESTA SONO IL PUNTO. Ogni modifica costa familiarita', e il
//  costo si vede PRIMA di salvare: e' quello che rende la schermata una scelta
//  invece di un menu. Le formule sono le stesse di private.avanza_familiarita
//  in SQL e di quoteFamiliarita nell'Edge Function — tre posti, una formula.
// ============================================================
import { useEffect, useMemo, useRef, useState, type PointerEvent as ReactPointerEvent } from 'react'
import { COMPITI, COMPITI_REPARTO, FAM_PARTITE_PIENA, MODULI, REPARTO, RUOLI_SLOT, SPOSTAMENTI_SLOT } from '../lib/tattica'
import { ANCORE, nomeSchieramento, schieramentoInCampo, type Ancora } from '../lib/schieramento'
import { Icona } from './Icona'
import { STILI, STILE_LABEL, STILE_DESCRIZIONI } from '../lib/stili'

const ruoliPerSlot = (slot: string): string[] => RUOLI_SLOT[slot] ?? []

export type XpDisposizione = { disposizione: string[]; partite: number }


type Props = {
  modulo: string
  disposizione: string[] | null
  ruoli: (string | null)[] | null
  compiti: (string | null)[] | null
  focus: string | null
  xpDisposizione: XpDisposizione[]
  xpIndicazioni: number
  onChange: (d: string[] | null, r: (string | null)[] | null, c: (string | null)[] | null) => void
  onFocus: (f: string | null) => void
  onClose: () => void
  // Moduli personalizzati (max 3): salvare lo schema con un nome, sovrascriverne
  // uno o eliminarne uno. Le funzioni rispondono con un messaggio d'errore o null.
  moduliSalvati: { id: number; nome: string }[]
  moduloSalvatoAttivo: number | null
  onSalvaModulo: (nome: string, sostituisci: number | null) => Promise<string | null>
  onEliminaModulo: (id: number) => Promise<string | null>
  // La pagina "Squadra": stile, linea difensiva, ampiezza, portiere. null =
  // l'opzione predefinita (registro tattico, punto 30).
  squadra: IndicazioniSquadra
  onSquadra: (q: Partial<IndicazioniSquadra>) => void
}

export type IndicazioniSquadra = { stile: string; linea: string | null; ampiezza: string | null; portiere: string | null }

// Cosa fa ogni indicazione e che giocatori chiede. I numeri stanno in
// engine/squadra.js: qui c'e' solo come si spiegano.
const CHIEDE_STILE: Record<string, string> = {
  equilibrato: '',
  contropiede: 'Vuole attaccanti veloci.',
  possesso_palla: 'Vuole centrocampisti tecnici.',
  fasce: 'Vuole esterni e terzini che crossano e corrono.',
  recupero_veloce: 'Vuole giocatori aggressivi e bravi negli intercetti.',
  diretto: 'Vuole punte forti di testa e fisicamente.',
  blocco_basso: 'Vuole difensori forti e bravi a marcare.',
}
const LINEE: [string | null, string, string][] = [
  ['bassa', 'Bassa', 'Si difende vicino all’area: dietro più solidi, il resto della squadra più lontano. Vuole difensori forti e bravi a marcare.'],
  [null, 'Media', 'Nessuna indicazione particolare.'],
  ['alta', 'Alta', 'Squadra corta e centrocampo più forte, ma campo alle spalle dei difensori. Vuole difensori veloci.'],
]
const AMPIEZZE: [string | null, string, string][] = [
  ['stretta', 'Stretta', 'Superiorità in mezzo, fasce lasciate agli avversari. Vuole centrocampisti tecnici.'],
  [null, 'Normale', 'Nessuna indicazione particolare.'],
  ['larga', 'Larga', 'Più gioco sulle fasce, centro più solo. Vuole esterni e terzini che crossano e corrono.'],
]
const PORTIERI: [string | null, string, string][] = [
  [null, 'Normale', 'Resta tra i pali.'],
  ['libero', 'Portiere-libero', 'Esce dai pali e gioca coi piedi. Con la linea alta copre lo spazio dietro i difensori. Lo allena il piano «Fuori dai pali».'],
]

const MODULI_SALVABILI = 3

// I nomi che l'utente legge. Le chiavi sono quelle del motore (engine/ruoli.js):
// tenerle separate dalle etichette permette di cambiare parole senza toccare
// una taratura.
const RUOLO_LABEL: Record<string, { nome: string; detto: string }> = {
  centrale: { nome: 'Centrale', detto: 'Tiene la posizione e non si scopre.' },
  centrale_marcatore: { nome: 'Marcatore', detto: 'Più basso e aggressivo sull’uomo.' },
  centrale_impostatore: { nome: 'Impostatore', detto: 'Fa partire l’azione da dietro.' },
  terzino: { nome: 'Terzino', detto: 'Copre la fascia senza esporsi.' },
  terzino_offensivo: { nome: 'Fluidificante', detto: 'Si allarga e si sovrappone.' },
  terzino_interno: { nome: 'Terzino interno', detto: 'Rientra dentro: rinforza il centro, lascia la fascia.' },
  terzino_bloccato: { nome: 'Terzino bloccato', detto: 'Resta dietro, non accompagna mai.' },
  mediano: { nome: 'Mediano', detto: 'Fa legna e smista, senza sbilanciarsi.' },
  regista: { nome: 'Regista', detto: 'Gioca stretto e detta i tempi.' },
  mezzala: { nome: 'Mezzala', detto: 'Si allarga verso la fascia e accompagna.' },
  incursore: { nome: 'Incursore', detto: 'Attacca l’area senza palla.' },
  schermo: { nome: 'Schermo', detto: 'Davanti alla difesa e basta.' },
  esterno: { nome: 'Esterno', detto: 'Tiene la fascia in entrambe le fasi.' },
  ala_pura: { nome: 'Ala pura', detto: 'Larghissima, salta l’uomo e crossa.' },
  esterno_a_rientrare: { nome: 'A rientrare', detto: 'Converge dentro per calciare.' },
  esterno_difensivo: { nome: 'Esterno difensivo', detto: 'Raddoppia sul terzino avversario e copre la fascia.' },
  punta: { nome: 'Punta', detto: 'Gioca sul filo e attacca la porta.' },
  finalizzatore: { nome: 'Finalizzatore', detto: 'Vive in area, tocca poco e segna.' },
  punta_di_manovra: { nome: 'Punta di manovra', detto: 'Scende a legare il gioco.' },
}

// Un compito non vuol dire la stessa cosa per un centrale e per una punta.
// Dire a un attaccante di "restare dietro la linea della palla" non significa
// niente: per lui il compito difensivo e' andare addosso al portatore e
// rientrare, e si paga in fiato. I nomi vengono dal motore
// (COMPITI_REPARTO), qui c'e' solo come si spiegano.
const COMPITO_DETTO: Record<string, Record<string, string>> = {
  DEF: {
    difesa: 'Non si stacca mai dalla linea: reparto compatto, e arriva in fondo alla partita fresco. Non aiuta a costruire.',
    attacco: 'Accompagna l’azione e crea superiorità sulla fascia. Lascia spazio dietro di sé, e stanca di più.',
  },
  MID: {
    difesa: 'Scala davanti alla difesa e chiude le linee di passaggio. Si vede molto meno in avanti.',
    attacco: 'Attacca l’area senza palla: gol in più da dietro. Il centrocampo resta più scoperto.',
  },
  ATT: {
    difesa: 'Aggredisce chi imposta: la palla la tenete voi e loro tirano meno. Segna meno e consuma — conviene se ha la resistenza per reggerlo tutta la stagione.',
    attacco: 'Resta sull’ultima linea, pronto a partire, e si risparmia. In fase difensiva siete in nove.',
  },
}

const compitoLabel = (slot: string, compito: string): { nome: string; detto: string; energia: number } => {
  if (compito === 'equilibrio') return { nome: 'Equilibrato', detto: 'Nessuna indicazione particolare.', energia: 1 }
  const r = REPARTO[slot] ?? 'MID'
  const c = COMPITI_REPARTO[r]?.[compito]
  return { nome: c?.nome ?? compito, detto: COMPITO_DETTO[r]?.[compito] ?? '', energia: c?.energia ?? 1 }
}

const REPARTO_DI = (slot: string): 'gk' | 'dif' | 'mid' | 'att' =>
  slot === 'GK' ? 'gk'
    : ['CB', 'LB', 'RB', 'LWB', 'RWB'].includes(slot) ? 'dif'
      : ['CDM', 'CM', 'CAM', 'LM', 'RM'].includes(slot) ? 'mid' : 'att'

const resaFamiliarita = (distanza: number) =>
  Math.max(0, Math.min(1, 1 - 1.6 * Math.max(0, Math.min(1, distanza))))

const uguali = (a: string[], b: string[]) => a.reduce((n, s, i) => n + (s === b[i] ? 1 : 0), 0)

// Oltre questa distanza dal centro di una postazione la calamita non prende e
// la card torna dov'era. In percentuale del campo.
const RAGGIO_CALAMITA = 13
// Sotto questo movimento e' un tocco, non un trascinamento: apre ruolo e compito.
const SOGLIA_TRASCINAMENTO = 3

export default function SchemaTattico({
  modulo, disposizione, ruoli, compiti, focus, xpDisposizione, xpIndicazioni, onChange, onFocus, onClose,
  moduliSalvati, moduloSalvatoAttivo, onSalvaModulo, onEliminaModulo, squadra, onSquadra,
}: Props) {
  const standard = MODULI[modulo] ?? []
  const schema = disposizione ?? standard
  const [aperto, setAperto] = useState<number | null>(null)
  const [pagina, setPagina] = useState<'giocatori' | 'squadra'>('giocatori')
  const [salvataggio, setSalvataggio] = useState<{ nome: string; errore: string | null; inCorso: boolean } | null>(null)
  const [trascino, setTrascino] = useState<{ index: number; x: number; y: number; mosso: boolean } | null>(null)
  const campoRef = useRef<HTMLDivElement | null>(null)
  // Indice della card appena trascinata: il click che il browser genera dopo il
  // rilascio non deve aprirne il foglio.
  const appenaTrascinata = useRef<number | null>(null)

  const posti = useMemo(() => schieramentoInCampo(schema), [schema])

  // --- le due barre, calcolate come in SQL e nell'Edge Function ---
  const quotaDisposizione = useMemo(() => {
    const esatta = xpDisposizione.find((r) => r.disposizione?.length === 11 && uguali(r.disposizione, schema) === 11)
    if (esatta) return Math.min(1, esatta.partite / FAM_PARTITE_PIENA)
    let migliore = 0
    for (const r of xpDisposizione) {
      if (!r.disposizione || r.disposizione.length !== 11) continue
      const q = Math.min(1, r.partite / FAM_PARTITE_PIENA) * resaFamiliarita(1 - uguali(r.disposizione, schema) / 11)
      if (q > migliore) migliore = q
    }
    return Math.min(1, Math.round(migliore * FAM_PARTITE_PIENA) / FAM_PARTITE_PIENA)
  }, [xpDisposizione, schema])

  // Ventisette elementi come in SQL (private.avanza_familiarita): lo stile,
  // gli undici ruoli, gli undici compiti, dove si attacca, linea, ampiezza e
  // portiere.
  const conIndicazioni = (ruoli?.filter(Boolean).length ?? 0)
    + (compiti?.filter((c) => c && c !== 'equilibrio').length ?? 0)
    + (focus ? 1 : 0)
    + (squadra.stile !== 'equilibrato' ? 1 : 0)
    + (squadra.linea ? 1 : 0) + (squadra.ampiezza ? 1 : 0) + (squadra.portiere ? 1 : 0)
  const quotaIndicazioni = Math.min(1,
    Math.round(Math.min(1, xpIndicazioni / FAM_PARTITE_PIENA)
      * resaFamiliarita(conIndicazioni / 27) * FAM_PARTITE_PIENA) / FAM_PARTITE_PIENA)

  const cambiati = 11 - uguali(standard, schema)
  const nome = useMemo(() => nomeSchieramento(schema, MODULI), [schema])

  // --- dove si puo' andare ---
  // Le postazioni legali per una card: quelle che la sua posizione di partenza
  // puo' raggiungere (sale o scende di una linea, stessa corsia) e che nessun
  // altro occupa gia'.
  const ancoreLegali = (index: number): Ancora[] => {
    const consentite = SPOSTAMENTI_SLOT[standard[index]] ?? [standard[index]]
    const occupate = new Set(posti.filter((p) => p.index !== index).map((p) => p.ancora))
    return ANCORE.filter((a) => consentite.includes(a.slot) && !occupate.has(a.id))
  }

  // --- modifiche ---
  const scrivi = (i: number, campo: 'slot' | 'ruolo' | 'compito', valore: string | null) => {
    const d = [...schema]
    const r: (string | null)[] = ruoli ? [...ruoli] : Array(11).fill(null)
    const c: (string | null)[] = compiti ? [...compiti] : Array(11).fill(null)
    if (campo === 'slot' && valore) {
      d[i] = valore
      // Il ruolo apparteneva alla posizione di prima: se qui non esiste, torna a
      // niente invece di restare addosso a una posizione che non lo prevede —
      // sarebbe il salvataggio a rifiutarlo, e con un errore oscuro.
      if (r[i] && !ruoliPerSlot(valore).includes(r[i] as string)) r[i] = null
    }
    // Il ruolo base della posizione E' "nessuna indicazione": si salva come
    // null, cosi' la barra delle indicazioni non lo conta come una scelta.
    if (campo === 'ruolo') r[i] = valore && valore !== ruoliPerSlot(d[i])[0] ? valore : null
    if (campo === 'compito') c[i] = valore
    onChange(
      uguali(d, standard) === 11 ? null : d,
      r.every((x) => !x) ? null : r,
      c.every((x) => !x || x === 'equilibrio') ? null : c,
    )
  }

  const ripristina = () => {
    onChange(null, null, null); onFocus(null)
    onSquadra({ stile: 'equilibrato', linea: null, ampiezza: null, portiere: null })
    setAperto(null)
  }

  // --- trascinamento ---
  //
  // Gli ascoltatori di movimento e rilascio stanno sulla FINESTRA, non sulla
  // card. Sulla card sembrava naturale e invece si inchiodava: ogni movimento
  // ridisegna il campo, e se React ricicla il nodo la cattura del puntatore se
  // ne va con quello vecchio — il rilascio arriva a un elemento che non esiste
  // piu' e la card resta appesa a meta' trascinamento. Sulla finestra il
  // problema non puo' presentarsi.
  const puntoNelCampo = (clientX: number, clientY: number) => {
    const r = campoRef.current?.getBoundingClientRect()
    if (!r || !r.width || !r.height) return null
    return { x: ((clientX - r.left) / r.width) * 100, y: 100 - ((clientY - r.top) / r.height) * 100 }
  }

  const iniziaTrascinamento = (e: ReactPointerEvent, index: number, slot: string) => {
    if (slot === 'GK') return // il portiere non si sposta
    const p = puntoNelCampo(e.clientX, e.clientY)
    if (!p) return
    setTrascino({ index, x: p.x, y: p.y, mosso: false })
  }

  // I valori vivi per gli ascoltatori globali, che vengono agganciati una volta
  // sola per trascinamento e non devono richiudersi su uno stato vecchio.
  const vivo = useRef({ trascino, posti, bersaglio: null as Ancora | null, scrivi, aperto })
  vivo.current = { trascino, posti, bersaglio: null, scrivi, aperto }

  const bersaglio = useMemo(() => {
    if (!trascino?.mosso) return null
    let vicina: Ancora | null = null
    let dist = RAGGIO_CALAMITA
    for (const a of ancoreLegali(trascino.index)) {
      const d = Math.hypot(a.x - trascino.x, a.y - trascino.y)
      if (d < dist) { dist = d; vicina = a }
    }
    return vicina
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [trascino, posti, schema])
  vivo.current.bersaglio = bersaglio

  useEffect(() => {
    if (trascino === null) return
    const muovi = (e: PointerEvent) => {
      e.preventDefault()
      const t = vivo.current.trascino
      if (!t) return
      const p = puntoNelCampo(e.clientX, e.clientY)
      if (!p) return
      const partenza = vivo.current.posti.find((q) => q.index === t.index)
      const mosso = t.mosso || !partenza
        || Math.hypot(p.x - partenza.x, p.y - partenza.y) > SOGLIA_TRASCINAMENTO
      setTrascino({ index: t.index, x: p.x, y: p.y, mosso })
    }
    const molla = () => {
      const t = vivo.current.trascino
      setTrascino(null)
      if (!t) return
      // Il tocco semplice lo gestisce l'onClick della card. Aprire il foglio
      // qui, al rilascio, lo faceva comparire SOTTO il dito: il click generato
      // subito dopo cadeva sull'opzione apparsa in quel punto e sceglieva un
      // ruolo da solo (misurato sul telefono: un tocco su un CM dava "Mezzala").
      if (!t.mosso) return
      appenaTrascinata.current = t.index
      if (vivo.current.bersaglio) vivo.current.scrivi(t.index, 'slot', vivo.current.bersaglio.slot)
    }
    const annulla = () => setTrascino(null)
    window.addEventListener('pointermove', muovi, { passive: false })
    window.addEventListener('pointerup', molla)
    window.addEventListener('pointercancel', annulla)
    return () => {
      window.removeEventListener('pointermove', muovi)
      window.removeEventListener('pointerup', molla)
      window.removeEventListener('pointercancel', annulla)
    }
  // Si aggancia una volta per trascinamento: dipende da QUALE card e' in mano,
  // non da dove si trova in questo istante.
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [trascino?.index])

  const postoAperto = aperto === null ? null : posti.find((p) => p.index === aperto) ?? null
  const slotAperto = postoAperto ? schema[postoAperto.index] : null
  const legaliAperte = postoAperto ? ancoreLegali(postoAperto.index) : []

  return (
    <div className="schema" role="dialog" aria-label="Schema tattico">
      <header className="schema__testa">
        <button className="schema__chiudi" type="button" onClick={onClose} aria-label="Torna alla formazione"><Icona nome="indietro" /></button>
        <div className="schema__titolo">
          {/* Il nome grande e' quello che c'e' DAVVERO in campo: spostando le
              posizioni si arriva a una forma che col modulo di partenza non
              c'entra piu', e continuare a chiamarla col suo nome e' una bugia.
              Il modulo scelto resta sotto, perche' e' la chiave della
              familiarita' e non cambia. */}
          <small>{nome === modulo ? 'Schema tattico' : `Schema tattico · da ${modulo}`}</small>
          <strong>{nome}{cambiati > 0 && nome === modulo && <em> · personalizzato</em>}</strong>
        </div>
        {(cambiati > 0 || conIndicazioni > 0) && (
          <button className="schema__reset" type="button" onClick={ripristina}>Ripristina</button>
        )}
      </header>

      <div className="schema__barre">
        <Barra nome="Disposizione" quota={quotaDisposizione}
          nota={cambiati === 0 ? 'Lo schieramento standard del modulo.' : `${cambiati} ${cambiati === 1 ? 'posizione spostata' : 'posizioni spostate'}.`} />
        <Barra nome="Indicazioni" quota={quotaIndicazioni}
          nota={conIndicazioni === 0 ? 'Nessuna indicazione data.' : `${conIndicazioni} ${conIndicazioni === 1 ? 'indicazione attiva' : 'indicazioni attive'}.`} />
      </div>

      {(cambiati > 0 || conIndicazioni > 0) && (moduloSalvatoAttivo
        ? <p className="schema__salvato">Salvato come «{moduliSalvati.find((m) => m.id === moduloSalvatoAttivo)?.nome}»</p>
        : <button className="schema__salva-modulo" type="button" onClick={() => setSalvataggio({ nome: '', errore: null, inCorso: false })}>
          Salva come modulo personalizzato
        </button>)}

      <div className="schema__pagine" role="tablist" aria-label="Pagine dello schema">
        <button type="button" role="tab" aria-selected={pagina === 'giocatori'} className={pagina === 'giocatori' ? 'is-attiva' : ''} onClick={() => setPagina('giocatori')}>Giocatori</button>
        <button type="button" role="tab" aria-selected={pagina === 'squadra'} className={pagina === 'squadra' ? 'is-attiva' : ''} onClick={() => setPagina('squadra')}>Squadra</button>
      </div>

      {pagina === 'giocatori' && <>
      <div className="schema__campo pitch-field" ref={campoRef} aria-label={`Schema ${modulo}`}>
        <div className="pitch-field__circle" />
        <div className="pitch-field__box pitch-field__box--top" />
        <div className="pitch-field__box pitch-field__box--bottom" />

        {/* Le postazioni libere dove la card che stai trascinando puo' finire. */}
        {trascino?.mosso && ancoreLegali(trascino.index).map((a) => (
          <span key={a.id} aria-hidden="true"
            className={`schema__ancora${bersaglio?.id === a.id ? ' is-bersaglio' : ''}`}
            style={{ left: `${a.x}%`, top: `${100 - a.y}%` }}>{a.slot}</span>
        ))}

        {posti.map((posto) => {
          const slot = schema[posto.index]
          const ruolo = ruoli?.[posto.index] ?? null
          const compito = compiti?.[posto.index] ?? null
          const spostata = slot !== standard[posto.index]
          const inMano = trascino?.index === posto.index && trascino.mosso
          const x = inMano ? trascino.x : posto.x
          const y = inMano ? trascino.y : posto.y
          return (
            <button
              key={posto.index}
              type="button"
              className={`schema__posto schema__posto--${REPARTO_DI(slot)}${spostata ? ' is-spostata' : ''}${aperto === posto.index ? ' is-aperta' : ''}${inMano ? ' is-in-mano' : ''}`}
              style={{ left: `${x}%`, top: `${100 - y}%` }}
              onPointerDown={(e) => iniziaTrascinamento(e, posto.index, slot)}
              onClick={() => {
                if (appenaTrascinata.current === posto.index) { appenaTrascinata.current = null; return }
                setAperto((a) => (a === posto.index ? null : posto.index))
              }}
            >
              <span className="schema__slot">{slot}</span>
              {(ruolo || (compito && compito !== 'equilibrio')) && (
                <span className={`schema__badge schema__badge--${compito ?? 'equilibrio'}`}>
                  {ruolo ? RUOLO_LABEL[ruolo]?.nome ?? ruolo : compitoLabel(slot, compito ?? 'equilibrio').nome}
                </span>
              )}
            </button>
          )
        })}
      </div>

      <p className="schema__spiega">
        Tocca una posizione per darle ruolo e compito, trascinala per spostarla. Cambiare molto insieme fa
        scendere le barre, che tornano su giocando.
      </p>
      </>}

      {pagina === 'squadra' && <div className="schema__squadra">
        <Gruppo titolo="Stile di gioco">
          {STILI.map((k) => <Scelta key={k} attiva={squadra.stile === k} nome={STILE_LABEL[k].charAt(0) + STILE_LABEL[k].slice(1).toLowerCase()}
            detto={[STILE_DESCRIZIONI[k], CHIEDE_STILE[k]].filter(Boolean).join(' ')}
            onClick={() => onSquadra({ stile: k })} />)}
        </Gruppo>
        {/* Dove si attacca guarda la PROPRIA squadra (registro, punto 27): la
            corsia dove si hanno i giocatori piu' forti. */}
        <Gruppo titolo="Dove attacchiamo">
          {([[null, 'Ovunque', 'Nessuna concentrazione: si attacca dove capita.'],
            ['SX', 'A sinistra', 'Rende se a sinistra hai i giocatori migliori, costa se è il tuo lato debole.'],
            ['CEN', 'Al centro', 'Rende se al centro hai i giocatori migliori, costa se è il tuo lato debole.'],
            ['DX', 'A destra', 'Rende se a destra hai i giocatori migliori, costa se è il tuo lato debole.']] as const).map(([v, n, d]) =>
            <Scelta key={n} attiva={focus === v} nome={n} detto={d} onClick={() => onFocus(v)} />)}
        </Gruppo>
        <Gruppo titolo="Linea difensiva">
          {LINEE.map(([v, n, d]) => <Scelta key={n} attiva={squadra.linea === v} nome={n} detto={d} predefinita={v === null} onClick={() => onSquadra({ linea: v })} />)}
        </Gruppo>
        <Gruppo titolo="Ampiezza">
          {AMPIEZZE.map(([v, n, d]) => <Scelta key={n} attiva={squadra.ampiezza === v} nome={n} detto={d} predefinita={v === null} onClick={() => onSquadra({ ampiezza: v })} />)}
        </Gruppo>
        <Gruppo titolo="Portiere">
          {PORTIERI.map(([v, n, d]) => <Scelta key={n} attiva={squadra.portiere === v} nome={n} detto={d} predefinita={v === null} onClick={() => onSquadra({ portiere: v })} />)}
        </Gruppo>
        <p className="schema__spiega">
          Ogni indicazione rende se la tua rosa ha i giocatori adatti, e costa se non li ha. Quelle predefinite
          non danno né tolgono niente.
        </p>
      </div>}

      {postoAperto && slotAperto && (
        <>
          <button className="schema__scrim" type="button" aria-label="Chiudi" onClick={() => setAperto(null)} />
          <section className="schema__foglio">
            <header>
              <button className="schema__fatto" type="button" onClick={() => setAperto(null)}>Fatto</button>
              <strong>{slotAperto}</strong>
              <small>{slotAperto === standard[postoAperto.index] ? 'Posizione di partenza' : `Era ${standard[postoAperto.index]}`}</small>
            </header>

            {slotAperto === 'GK'
              ? <p className="schema__vuoto">Il portiere non si sposta e non prende indicazioni.</p>
              : <>
                {/* Il trascinamento e' la via veloce; questa resta per chi preferisce
                    toccare, e per chi usa la tastiera. */}
                <h3>Sposta</h3>
                <div className="schema__scelte schema__scelte--riga">
                  {(SPOSTAMENTI_SLOT[standard[postoAperto.index]] ?? [standard[postoAperto.index]]).map((s) => {
                    const libera = s === slotAperto || legaliAperte.some((a) => a.slot === s)
                    return (
                      <button key={s} type="button" disabled={!libera}
                        className={s === slotAperto ? 'is-attiva' : ''}
                        title={libera ? undefined : 'Non c’è una postazione libera lì'}
                        onClick={() => scrivi(postoAperto.index, 'slot', s)}>{s}</button>
                    )
                  })}
                </div>

                <h3>Ruolo</h3>
                <div className="schema__scelte">
                  {/* Niente idoneita' qui: lo schema e' della squadra, i segnalini
                      "++"/"−" stanno sulle magliette della formazione. */}
                  {ruoliPerSlot(slotAperto).map((r, i) => {
                    // Il primo ruolo e' quello base: scelto quando non si tocca
                    // niente, e il modo per tornare senza indicazioni.
                    const base = i === 0
                    const attivo = base ? !ruoli?.[postoAperto.index] || ruoli[postoAperto.index] === r : ruoli?.[postoAperto.index] === r
                    return (
                      <button key={r} type="button" className={attivo ? 'is-attiva' : ''}
                        onClick={() => scrivi(postoAperto.index, 'ruolo', base ? null : r)}>
                        <strong>{RUOLO_LABEL[r]?.nome ?? r}{base && <em className="schema__base">nessuna indicazione</em>}</strong>
                        <small>{RUOLO_LABEL[r]?.detto}</small>
                      </button>
                    )
                  })}
                </div>

                <h3>Compito</h3>
                <div className="schema__scelte">
                  {COMPITI.map((c) => {
                    const et = compitoLabel(slotAperto, c)
                    return (
                      <button key={c} type="button"
                        className={(compiti?.[postoAperto.index] ?? 'equilibrio') === c ? 'is-attiva' : ''}
                        onClick={() => scrivi(postoAperto.index, 'compito', c === 'equilibrio' ? null : c)}>
                        <strong>{et.nome}{et.energia !== 1 && (
                          <em className={`schema__fiato schema__fiato--${et.energia > 1 ? 'costa' : 'risparmia'}`}>
                            {et.energia > 1 ? `+${Math.round((et.energia - 1) * 100)}% stanchezza` : `−${Math.round((1 - et.energia) * 100)}% stanchezza`}
                          </em>
                        )}</strong>
                        <small>{et.detto}</small>
                      </button>
                    )
                  })}
                </div>
              </>}
          </section>
        </>
      )}

      {salvataggio && (() => {
        const pieni = moduliSalvati.length >= MODULI_SALVABILI
        const esegui = async (azione: () => Promise<string | null>) => {
          setSalvataggio((s) => s && { ...s, inCorso: true, errore: null })
          const errore = await azione()
          if (errore) setSalvataggio((s) => s && { ...s, inCorso: false, errore })
          else setSalvataggio(null)
        }
        const nome = salvataggio.nome.trim()
        return <>
          <button className="schema__scrim" type="button" aria-label="Chiudi" onClick={() => setSalvataggio(null)} />
          <section className="schema__foglio" role="dialog" aria-label="Salva modulo personalizzato">
            <header>
              <button className="schema__fatto" type="button" onClick={() => setSalvataggio(null)}>Annulla</button>
              <strong>Salva modulo</strong>
              <small>Posizioni, ruoli, compiti e dove attacchiamo. Lo vedi solo tu.</small>
            </header>
            <h3>Nome</h3>
            <input className="schema__nome" type="text" maxLength={30} value={salvataggio.nome}
              placeholder={`Es. il mio ${nomeSchieramento(schema, MODULI)}`}
              onChange={(e) => setSalvataggio((s) => s && { ...s, nome: e.target.value, errore: null })} />
            {!pieni && <button className="schema__conferma" type="button" disabled={!nome || salvataggio.inCorso}
              onClick={() => void esegui(() => onSalvaModulo(nome, null))}>Salva</button>}
            {pieni && <p className="schema__vuoto">Hai già {MODULI_SALVABILI} moduli personalizzati: sovrascrivine uno o eliminane uno per fare spazio.</p>}
            {salvataggio.errore && <p className="schema__errore" role="alert">{salvataggio.errore}</p>}
            {moduliSalvati.length > 0 && <>
              <h3>I tuoi moduli · {moduliSalvati.length}/{MODULI_SALVABILI}</h3>
              <ul className="schema__salvati">
                {moduliSalvati.map((m) => <li key={m.id}>
                  <strong>{m.nome}</strong>
                  <button type="button" disabled={salvataggio.inCorso}
                    onClick={() => { if (window.confirm(`Sovrascrivere «${m.nome}» con lo schema attuale${nome && nome !== m.nome ? `, col nome «${nome}»` : ''}?`)) void esegui(() => onSalvaModulo(nome || m.nome, m.id)) }}>Sovrascrivi</button>
                  <button type="button" className="schema__elimina" disabled={salvataggio.inCorso}
                    onClick={() => { if (window.confirm(`Eliminare il modulo «${m.nome}»?`)) void (async () => {
                      const errore = await onEliminaModulo(m.id)
                      setSalvataggio((s) => s && { ...s, errore })
                    })() }}>Elimina</button>
                </li>)}
              </ul>
            </>}
          </section>
        </>
      })()}
    </div>
  )
}

function Barra({ nome, quota, nota }: { nome: string; quota: number; nota: string }) {
  const pct = Math.round(quota * 100)
  return (
    <div className="schema__barra">
      <div className="schema__barra-testa"><span>{nome}</span><strong>{pct}%</strong></div>
      <div className="schema__barra-pista"><i style={{ width: `${pct}%` }} data-basso={pct < 60 ? 'si' : undefined} /></div>
      <small>{nota}</small>
    </div>
  )
}

function Gruppo({ titolo, children }: { titolo: string; children: React.ReactNode }) {
  return (
    <section className="schema__gruppo">
      <h3>{titolo}</h3>
      <div className="schema__scelte">{children}</div>
    </section>
  )
}

function Scelta({ nome, detto, attiva, predefinita = false, onClick }: { nome: string; detto: string; attiva: boolean; predefinita?: boolean; onClick: () => void }) {
  return (
    <button type="button" className={attiva ? 'is-attiva' : ''} onClick={onClick}>
      <strong>{nome}{predefinita && <em className="schema__base">nessuna indicazione</em>}</strong>
      <small>{detto}</small>
    </button>
  )
}
