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
import { ANCORE, schieramentoInCampo, type Ancora } from '../lib/schieramento'

const ruoliPerSlot = (slot: string): string[] => RUOLI_SLOT[slot] ?? []

export type XpDisposizione = { disposizione: string[]; partite: number }

type Props = {
  modulo: string
  disposizione: string[] | null
  ruoli: (string | null)[] | null
  compiti: (string | null)[] | null
  xpDisposizione: XpDisposizione[]
  xpIndicazioni: number
  onChange: (d: string[] | null, r: (string | null)[] | null, c: (string | null)[] | null) => void
  onClose: () => void
}

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
  esterno_di_rientro: { nome: 'Esterno di rientro', detto: 'Raddoppia sul terzino avversario.' },
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
    difesa: 'Non accompagna mai, resta a protezione. Corre meno.',
    attacco: 'Accompagna e si propone. Scopre la fascia e costa fiato.',
  },
  MID: {
    difesa: 'Scala a protezione della difesa.',
    attacco: 'Attacca l’area senza palla. Costa fiato.',
  },
  ATT: {
    difesa: 'Va addosso al portatore e rientra. Aiuta poco dietro, ma costa molto fiato.',
    attacco: 'Resta alto e non rientra mai. Si risparmia.',
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
  modulo, disposizione, ruoli, compiti, xpDisposizione, xpIndicazioni, onChange, onClose,
}: Props) {
  const standard = MODULI[modulo] ?? []
  const schema = disposizione ?? standard
  const [aperto, setAperto] = useState<number | null>(null)
  const [trascino, setTrascino] = useState<{ index: number; x: number; y: number; mosso: boolean } | null>(null)
  const campoRef = useRef<HTMLDivElement | null>(null)

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

  const conIndicazioni = (ruoli?.filter(Boolean).length ?? 0) + (compiti?.filter((c) => c && c !== 'equilibrio').length ?? 0)
  const quotaIndicazioni = Math.min(1,
    Math.round(Math.min(1, xpIndicazioni / FAM_PARTITE_PIENA)
      * resaFamiliarita(conIndicazioni / 23) * FAM_PARTITE_PIENA) / FAM_PARTITE_PIENA)

  const cambiati = 11 - uguali(standard, schema)

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
    if (campo === 'ruolo') r[i] = valore
    if (campo === 'compito') c[i] = valore
    onChange(
      uguali(d, standard) === 11 ? null : d,
      r.every((x) => !x) ? null : r,
      c.every((x) => !x || x === 'equilibrio') ? null : c,
    )
  }

  const ripristina = () => { onChange(null, null, null); setAperto(null) }

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
      // Un tocco senza movimento apre ruolo e compito. Va deciso QUI e non in
      // un onClick sulla card: il click scatta dopo il rilascio, quindi
      // apriva il foglio e lo richiudeva subito dopo.
      if (!t.mosso) setAperto((a) => (a === t.index ? null : t.index))
      else if (vivo.current.bersaglio) vivo.current.scrivi(t.index, 'slot', vivo.current.bersaglio.slot)
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
        <button className="schema__chiudi" type="button" onClick={onClose} aria-label="Torna alla formazione">‹</button>
        <div className="schema__titolo">
          <small>Schema tattico</small>
          <strong>{modulo}{cambiati > 0 && <em> · personalizzato</em>}</strong>
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
      <p className="schema__spiega">
        Trascina una posizione per spostarla, toccala per darle ruolo e compito. La squadra rende meglio
        quanto più conosce lo schieramento e le indicazioni: spostare o cambiare molto insieme fa scendere
        le barre, che tornano su giocando.
      </p>

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

      {postoAperto && slotAperto && (
        <>
          <button className="schema__scrim" type="button" aria-label="Chiudi" onClick={() => setAperto(null)} />
          <section className="schema__foglio">
            <header>
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
                  <button type="button" className={!ruoli?.[postoAperto.index] ? 'is-attiva' : ''}
                    onClick={() => scrivi(postoAperto.index, 'ruolo', null)}>
                    <strong>Nessuno</strong><small>Gioca la posizione senza indicazioni.</small>
                  </button>
                  {ruoliPerSlot(slotAperto).map((r) => (
                    <button key={r} type="button" className={ruoli?.[postoAperto.index] === r ? 'is-attiva' : ''}
                      onClick={() => scrivi(postoAperto.index, 'ruolo', r)}>
                      <strong>{RUOLO_LABEL[r]?.nome ?? r}</strong><small>{RUOLO_LABEL[r]?.detto}</small>
                    </button>
                  ))}
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
                            {et.energia > 1 ? `+${Math.round((et.energia - 1) * 100)}% fiato` : `−${Math.round((1 - et.energia) * 100)}% fiato`}
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
