import { useEffect, useRef, useState } from 'react'
import { Bar, BarChart, LabelList, PolarAngleAxis, PolarGrid, PolarRadiusAxis, Radar, RadarChart, ResponsiveContainer, XAxis, YAxis } from 'recharts'
import { Progress } from './ui/progress'
import { UnderlineTabs } from './ui/underline-tabs'

export type StatsStagione = {
  presenze: number
  minuti: number
  gol: number
  assist: number
  porteInviolate: number
  tiri: number
  tiriPorta: number
  passaggiTentati: number
  passaggiRiusciti: number
  contrastiVinti: number
  dribbling: number
}

export type DatiScheda = {
  nome: string
  club?: string | null
  nazionalita?: string | null
  posizioni: string[]
  overall: number
  eta: number
  piede?: string | null
  altezza?: number | null
  condizione?: number
  infortunatoFinoA?: number
  squalificatoFinoA?: number
  /** Ingaggio annuo in euro (design §5.1: la scala e' annuale). */
  ingaggio?: number
  /** Ultima stagione coperta dal contratto, con la stagione in corso per il confronto. */
  contrattoScadenza?: number
  stagioneCorrente?: number
  /** Ha annunciato il ritiro a inizio stagione: gioca ancora, ma non e' cedibile. */
  ritiroAnnunciato?: boolean
  /** Morale 0-100 (design §11), ricalcolato a ogni quarto di stagione. */
  morale?: number
  /** Mentalita': i tre rami sommano sempre 100, dicono cosa viene prima. */
  mentalita?: { bandiera: number; economia: number; vittorie: number }
  attributi: Record<string, number | null>
}

/** Proposta di rinnovo a stagione in corso, come la restituisce la RPC. */
export type PropostaRinnovo = {
  richiesta: number
  durata: number
  ingaggio_attuale: number
  nuova_scadenza: number
  tentativi_usati: number
  tentativi_totali: number
  trattativa_chiusa: boolean
  gia_rinnovato: boolean
}

/** Risposta del giocatore a un'offerta: mai la cifra esatta, solo quanto si è lontani. */
export type EsitoRinnovo = {
  esito: 'accettato' | 'rifiutato' | 'chiusa'
  messaggio: string
  tentativi_usati: number
  contratto_scadenza?: number
  ingaggio?: number
}

/** Allenamento (cambio ruolo o specializzazione) in corso: stessa forma per entrambi i rami. */
type AllenamentoInCorso = { etichettaPrima: string | null; etichettaDopo: string; avviatoGiornata: number; completaGiornata: number }

type Props = {
  giocatore: DatiScheda
  fotoUrl?: string
  stagione?: StatsStagione
  azionePericolosa?: {
    etichetta: string
    descrizione: string
    inCorso?: boolean
    errore?: string | null
    onConferma: () => void
  }
  rinnovo?: {
    nomeAllenatore?: string | null
    /** Legge la proposta dal server: e' il giocatore a fare la prima cifra. */
    onCarica: () => Promise<PropostaRinnovo>
    /** Manda una controproposta. La soglia la valuta il server, mai il browser. Durata sempre di una stagione: non si negozia. */
    onOffri: (ingaggio: number) => Promise<EsitoRinnovo>
    /** Se valorizzato, il bottone e' disabilitato e questo e' il motivo. */
    bloccato?: string
  }
  listaMercato?: {
    inLista: boolean
    onCambia: (valore: boolean) => Promise<void>
  }
  cambioRuolo?: {
    inCorso: { ruoloPrecedente: string; ruoloTarget: string; avviatoGiornata: number; completaGiornata: number } | null
    /** Giornata di riferimento per il conto alla rovescia: solo indicativa, il server decide davvero. */
    prossimaGiornata: number | null
    onCaricaTarget: () => Promise<string[]>
    onAvvia: (ruoloTarget: string) => Promise<void>
    onAnnulla: () => Promise<void>
  }
  specializzazione?: {
    /** Etichetta della specializzazione gia' attiva, se nessun allenamento e' in corso. */
    attiva: string | null
    inCorso: { specializzazionePrecedente: string | null; specializzazioneTarget: string; avviatoGiornata: number; completaGiornata: number } | null
    prossimaGiornata: number | null
    onCaricaOpzioni: () => Promise<Array<{ chiave: string; etichetta: string; deltas: Array<[string, number]> }>>
    onAvvia: (specializzazione: string) => Promise<void>
    onAnnulla: () => Promise<void>
  }
  onClose: () => void
}

// I 6 valori del radar, stessa forma delle card FIFA/FM: pace/shooting/
// passing/dribbling/defending/physic sono i macro-voti gia' importati,
// composti a loro volta dai sotto-attributi qui sotto.
const MACRO_RADAR: Array<[string, string]> = [
  ['pace', 'RIT'], ['shooting', 'TIR'], ['passing', 'PAS'], ['dribbling_generale', 'DRI'], ['defending', 'DIF'], ['physic', 'FIS'],
]

// Tutti i sotto-attributi importati (normalizza.py, 2 settembre 2026),
// raggruppati per macro-categoria. "Portiere" compare solo per chi gioca
// GK: gli altri hanno comunque un valore (bassa media FC26), ma mostrarlo
// sarebbe solo rumore.
type Attributo = { chiave: string; etichetta: string }
type GruppoAttributi = { titolo: string; soloGk?: boolean; voci: Attributo[] }

const GRUPPI_ATTRIBUTI: GruppoAttributi[] = [
  { titolo: 'Ritmo', voci: [
    { chiave: 'movement_acceleration', etichetta: 'Accelerazione' },
    { chiave: 'movement_sprint_speed', etichetta: 'Velocità di scatto' },
  ] },
  { titolo: 'Tiro', voci: [
    { chiave: 'finishing', etichetta: 'Finalizzazione' },
    { chiave: 'power_shot_power', etichetta: 'Potenza di tiro' },
    { chiave: 'power_long_shots', etichetta: 'Tiri da lontano' },
    { chiave: 'attacking_volleys', etichetta: 'Volée' },
    { chiave: 'mentality_penalties', etichetta: 'Rigori' },
    { chiave: 'mentality_positioning', etichetta: 'Attacco alla porta' },
  ] },
  { titolo: 'Passaggio', voci: [
    { chiave: 'short_passing', etichetta: 'Passaggi corti' },
    { chiave: 'skill_long_passing', etichetta: 'Passaggi lunghi' },
    { chiave: 'attacking_crossing', etichetta: 'Cross' },
    { chiave: 'skill_curve', etichetta: 'Effetto' },
    { chiave: 'skill_fk_accuracy', etichetta: 'Punizioni' },
    { chiave: 'mentality_vision', etichetta: 'Visione di gioco' },
  ] },
  { titolo: 'Dribbling', voci: [
    { chiave: 'dribbling', etichetta: 'Dribbling' },
    { chiave: 'skill_ball_control', etichetta: 'Controllo palla' },
    { chiave: 'movement_agility', etichetta: 'Agilità' },
    { chiave: 'movement_balance', etichetta: 'Equilibrio' },
    { chiave: 'movement_reactions', etichetta: 'Reattività' },
    { chiave: 'mentality_composure', etichetta: 'Compostezza' },
  ] },
  { titolo: 'Difesa', voci: [
    { chiave: 'standing_tackle', etichetta: 'Contrasti' },
    { chiave: 'defending_sliding_tackle', etichetta: 'Scivolate' },
    { chiave: 'defending_marking_awareness', etichetta: 'Marcatura' },
    { chiave: 'mentality_interceptions', etichetta: 'Intercetti' },
    { chiave: 'mentality_aggression', etichetta: 'Aggressività' },
  ] },
  { titolo: 'Fisico', voci: [
    { chiave: 'stamina', etichetta: 'Resistenza' },
    { chiave: 'power_strength', etichetta: 'Forza' },
    { chiave: 'power_jumping', etichetta: 'Elevazione' },
  ] },
  { titolo: 'Portiere', soloGk: true, voci: [
    { chiave: 'gk_diving', etichetta: 'Tuffo' },
    { chiave: 'gk_handling', etichetta: 'Presa' },
    { chiave: 'gk_kicking', etichetta: 'Rinvio' },
    { chiave: 'gk_positioning', etichetta: 'Posizionamento' },
    { chiave: 'gk_reflexes', etichetta: 'Riflessi' },
    { chiave: 'goalkeeping_speed', etichetta: 'Rapidità in uscita' },
  ] },
]

// Lookup piatta derivata dai gruppi qui sopra: usata per le etichette nel
// confronto prima/dopo dell'allenamento (le uniche 5 chiave che il motore
// legge vivono tutte in uno dei gruppi, niente elenco separato da tenere
// allineato a mano).
const ETICHETTE_ATTRIBUTI: Array<[string, string]> = GRUPPI_ATTRIBUTI.flatMap((gruppo) =>
  gruppo.voci.map((voce) => [voce.chiave, voce.etichetta] as [string, string]))

function reparto(slot = '') {
  if (slot === 'GK') return 'GK'
  if (['CB', 'LB', 'RB', 'LWB', 'RWB'].includes(slot)) return 'DEF'
  if (['CDM', 'CM', 'CAM', 'LM', 'RM'].includes(slot)) return 'MID'
  return 'ATT'
}

function AnonymousPlayer() {
  return <span className="anonymous-player" aria-hidden="true"><svg viewBox="0 0 100 110" focusable="false"><circle cx="50" cy="33" r="22" /><path d="M12 108c2-31 16-48 38-48s36 17 38 48H12Z" /></svg></span>
}

function percentuale(parte: number, totale: number) {
  if (totale <= 0) return '—'
  return `${Math.round(parte / totale * 100)}%`
}

const milioni = (euro: number) => `${(euro / 1_000_000).toFixed(1).replace('.', ',')} M€`
const stagioni = (n: number) => `${n} ${n === 1 ? 'stagione' : 'stagioni'}`

function etichettaMorale(morale: number) {
  if (morale >= 80) return { testo: 'Entusiasta', classe: 'ottimo' }
  if (morale >= 60) return { testo: 'Sereno', classe: 'buono' }
  if (morale >= 40) return { testo: 'Insoddisfatto', classe: 'medio' }
  if (morale >= 20) return { testo: 'Scontento', classe: 'basso' }
  return { testo: 'In rotta con la squadra', classe: 'critico' }
}

// I tre rami sommano 100: il dominante e' il tratto che definisce il giocatore.
const RAMI_MENTALITA: Array<[keyof NonNullable<DatiScheda['mentalita']>, string, string]> = [
  ['bandiera', 'Bandiera', 'Prima la maglia: soldi e vittorie vengono dopo.'],
  ['economia', 'Economia', 'Prima il contratto: punta sempre all’ingaggio più alto.'],
  ['vittorie', 'Vittorie', 'Prima i risultati: vuole vincere, il resto conta meno.'],
]

function etichettaAttributo(chiave: string) {
  return ETICHETTE_ATTRIBUTI.find(([k]) => k === chiave)?.[1] ?? chiave
}

// Percentuale di avanzamento di un allenamento (cambio ruolo o
// specializzazione): quante giornate sono gia' passate rispetto alla durata
// totale. prossimaGiornata e' solo un'indicazione lato client (il server
// decide davvero quando completare), quindi in sua assenza si mostra la
// barra vuota invece di indovinare.
function progressoAllenamento(a: { avviatoGiornata: number; completaGiornata: number }, prossimaGiornata: number | null) {
  const durata = a.completaGiornata - a.avviatoGiornata
  if (durata <= 0 || prossimaGiornata == null) return { percent: 0, mancano: Math.max(0, a.completaGiornata - (prossimaGiornata ?? a.avviatoGiornata)) }
  const fatte = Math.max(0, Math.min(durata, prossimaGiornata - a.avviatoGiornata))
  return { percent: Math.round((fatte / durata) * 100), mancano: Math.max(0, a.completaGiornata - prossimaGiornata) }
}

// Confronto prima/dopo per le stat toccate da una specializzazione, stile
// scheda FIFA/Football Manager: pista con la stat attuale piena e il
// guadagno evidenziato in coda, valori numerici a fianco.
// Etichetta "56 → 63" alla fine della barra impilata (base + guadagno):
// x/width arrivano gia' sommati dal segmento "guadagno", che e' l'ultimo
// dello stack, quindi x+width e' proprio il bordo destro della barra intera.
function EtichettaConfronto(props: unknown) {
  const { x, y, width, height, payload } = props as { x: number; y: number; width: number; height: number; payload?: { prima: number; dopo: number } }
  if (!payload) return null
  return <text x={x + width + 10} y={y + height / 2} dy={5} fontSize={13} fontWeight={800}>
    <tspan fill="#8e8498">{payload.prima}</tspan>
    <tspan fill="#675c73"> → </tspan>
    <tspan fill="#e29bff">{payload.dopo}</tspan>
  </text>
}

function ConfrontoAttributi({ deltas, attributi }: { deltas: Array<[string, number]>; attributi: Record<string, number | null> }) {
  const dati = deltas.map(([chiave, delta]) => {
    const prima = Math.max(0, Math.min(99, Math.round(attributi[chiave] ?? 0)))
    const guadagno = Math.max(0, Math.min(99 - prima, delta))
    return { chiave, etichetta: etichettaAttributo(chiave), prima, guadagno, dopo: prima + guadagno }
  })
  return <div className="player-training-confronto">
    <ResponsiveContainer width="100%" height={dati.length * 40 + 8}>
      <BarChart data={dati} layout="vertical" margin={{ top: 4, right: 66, left: 4, bottom: 4 }} barCategoryGap={14}>
        <XAxis type="number" domain={[0, 99]} hide />
        <YAxis type="category" dataKey="etichetta" width={104} stroke="#524a5f" tick={{ fill: '#c6bfce', fontSize: 12 }} axisLine={false} tickLine={false} />
        <Bar dataKey="prima" stackId="s" fill="#3a3348" radius={[5, 0, 0, 5]} isAnimationActive={false} />
        <Bar dataKey="guadagno" stackId="s" fill="#a354e8" radius={[0, 5, 5, 0]} isAnimationActive={false}>
          <LabelList dataKey="guadagno" content={EtichettaConfronto} />
        </Bar>
      </BarChart>
    </ResponsiveContainer>
  </div>
}

// Radar delle 6 macro-categorie FIFA, stile card FIFA/Football Manager.
function RadarAbilita({ attributi }: { attributi: Record<string, number | null> }) {
  const dati = MACRO_RADAR.map(([chiave, etichetta]) => ({ etichetta, valore: typeof attributi[chiave] === 'number' ? attributi[chiave] as number : 0 }))
  return <ResponsiveContainer width="100%" height={210}>
    <RadarChart data={dati} outerRadius="72%">
      <PolarGrid stroke="#332c3e" />
      <PolarAngleAxis dataKey="etichetta" tick={{ fill: '#c6bfce', fontSize: 11, fontWeight: 800 }} />
      <PolarRadiusAxis domain={[0, 99]} tick={false} axisLine={false} />
      <Radar dataKey="valore" stroke="#a354e8" strokeWidth={2} fill="#a354e8" fillOpacity={0.35} isAnimationActive={false} />
    </RadarChart>
  </ResponsiveContainer>
}

// Un gruppo di sotto-attributi (Tiro, Passaggio, ...): barre shadcn/Radix,
// solo le chiavi che il giocatore ha davvero (il portiere non compare per
// chi non gioca GK, vedi GruppoAttributi.soloGk).
function GruppoAbilita({ gruppo, attributi }: { gruppo: GruppoAttributi; attributi: Record<string, number | null> }) {
  const voci = gruppo.voci.filter((voce) => typeof attributi[voce.chiave] === 'number')
  if (voci.length === 0) return null
  return <div className="player-abilita-gruppo">
    <h4>{gruppo.titolo}</h4>
    {voci.map((voce) => {
      const valore = attributi[voce.chiave] as number
      return <div className="player-abilita-riga" key={voce.chiave}>
        <span>{voce.etichetta}</span>
        <Progress value={(valore / 99) * 100} className="player-abilita-barra" />
        <b>{valore}</b>
      </div>
    })}
  </div>
}

// Riquadro comune a cambio ruolo e specializzazione: stato in corso con
// barra di avanzamento, o picker a schede quando non c'e' nulla in corso.
function PannelloAllenamento({
  titolo, attuale, inCorso, prossimaGiornata, opzioni, opzioniCaricamento, scelta, onScegli, onAvvia, onAnnulla, inviando, errore, descrizioneScelta, confrontoScelta, bloccatoDa,
}: {
  titolo: string
  attuale: string | null
  inCorso: AllenamentoInCorso | null
  prossimaGiornata: number | null
  opzioni: Array<{ chiave: string; etichetta: string; sottotesto?: string }> | null
  opzioniCaricamento: boolean
  scelta: string
  onScegli: (chiave: string) => void
  onAvvia: () => void
  onAnnulla: () => void
  inviando: boolean
  errore: string | null
  descrizioneScelta?: string
  /** Confronto grafico prima/dopo per l'opzione selezionata (solo specializzazione: il cambio ruolo non tocca stat). */
  confrontoScelta?: React.ReactNode
  /** Nome dell'altro allenamento gia' in corso: sono mutuamente esclusivi, un giocatore ne fa uno alla volta. */
  bloccatoDa?: string | null
}) {
  return <section className="player-training-sezione">
    <h3>{titolo}</h3>

    {inCorso ? <div className="player-training-corso">
      <div className="player-training-corso__frecce">
        {inCorso.etichettaPrima && <span>{inCorso.etichettaPrima}</span>}
        <i aria-hidden="true">→</i>
        <b>{inCorso.etichettaDopo}</b>
      </div>
      {(() => {
        const { percent, mancano } = progressoAllenamento(inCorso, prossimaGiornata)
        return <>
          <div className="player-training-barra"><i style={{ '--percent': percent / 100 } as React.CSSProperties} /></div>
          <p className="field-help">
            {prossimaGiornata != null ? `Pronto tra ${mancano} ${mancano === 1 ? 'giornata' : 'giornate'}.` : `Completa alla giornata ${inCorso.completaGiornata}.`}
          </p>
        </>
      })()}
      {errore && <p className="notice notice--error">{errore}</p>}
      <button className="button button--danger-ghost" type="button" disabled={inviando} onClick={onAnnulla}>
        {inviando ? 'Attendi…' : 'Annulla allenamento'}
      </button>
    </div> : bloccatoDa ? <div className="player-training-scelta">
      {attuale && <p className="field-help">Attuale: <b>{attuale}</b></p>}
      <p className="season-empty">Non disponibile: {bloccatoDa} già in corso. Un giocatore segue un solo allenamento alla volta.</p>
    </div> : <div className="player-training-scelta">
      {attuale && <p className="field-help">Attuale: <b>{attuale}</b></p>}
      {errore && <p className="notice notice--error">{errore}</p>}
      {opzioniCaricamento ? <p className="season-empty">Carico le opzioni…</p>
        : !opzioni ? null
        : opzioni.length === 0 ? <p className="season-empty">Nessuna opzione disponibile per questo giocatore.</p>
        : <>
            <div className="player-training-opzioni" role="radiogroup" aria-label={titolo}>
              {opzioni.map((opzione) => (
                <button
                  className={`player-training-opzioni__voce ${scelta === opzione.chiave ? 'is-active' : ''}`}
                  type="button" role="radio" aria-checked={scelta === opzione.chiave} key={opzione.chiave}
                  onClick={() => onScegli(opzione.chiave)}
                >
                  <i className="player-training-opzioni__pallino" aria-hidden="true">{scelta === opzione.chiave && '✓'}</i>
                  <span>
                    <strong>{opzione.etichetta}</strong>
                    {opzione.sottotesto && <small>{opzione.sottotesto}</small>}
                  </span>
                </button>
              ))}
            </div>
            {descrizioneScelta && <p className="field-help">{descrizioneScelta}</p>}
            {confrontoScelta}
            <button className="button button--primary" type="button" disabled={inviando || !scelta} onClick={onAvvia}>
              {inviando ? 'Avvio…' : 'Avvia allenamento'}
            </button>
          </>}
    </div>}
  </section>
}

export function SchedaGiocatore({ giocatore, fotoUrl, stagione, azionePericolosa, rinnovo, listaMercato, cambioRuolo, specializzazione, onClose }: Props) {
  const [confermaAperta, setConfermaAperta] = useState(false)
  const [vistaRinnovo, setVistaRinnovo] = useState(false)
  const [proposta, setProposta] = useState<PropostaRinnovo | null>(null)
  const [rinnovoErrore, setRinnovoErrore] = useState<string | null>(null)
  const [rinnovoInCorso, setRinnovoInCorso] = useState(false)
  const [esito, setEsito] = useState<EsitoRinnovo | null>(null)
  // Offerta in M€ come stringa: l'utente digita "3,4" e non deve combattere
  // con l'arrotondamento mentre scrive.
  const [offertaM, setOffertaM] = useState('')
  const [inLista, setInLista] = useState(listaMercato?.inLista ?? false)
  const [listaInCorso, setListaInCorso] = useState(false)
  const [listaEsito, setListaEsito] = useState<string | null>(null)
  const [listaErrore, setListaErrore] = useState<string | null>(null)

  // Pagina "Training" (cambio ruolo + specializzazione): esiste solo se c'e'
  // almeno uno dei due rami, altrimenti la scheda resta a pagina singola
  // (es. profilo di un avversario, dove queste azioni non sono disponibili).
  const haTraining = Boolean(cambioRuolo || specializzazione)
  const [pagina, setPagina] = useState<'scheda' | 'training'>('scheda')
  const pagerRef = useRef<HTMLDivElement>(null)
  const touchStartX = useRef<number | null>(null)

  function onTouchStart(evento: React.TouchEvent) { touchStartX.current = evento.touches[0]?.clientX ?? null }
  function onTouchEnd(evento: React.TouchEvent) {
    if (touchStartX.current == null || !haTraining) return
    const dx = (evento.changedTouches[0]?.clientX ?? touchStartX.current) - touchStartX.current
    touchStartX.current = null
    if (Math.abs(dx) < 60) return
    if (dx < 0 && pagina === 'scheda') setPagina('training')
    if (dx > 0 && pagina === 'training') setPagina('scheda')
  }

  const [cambioTarget, setCambioTarget] = useState<string[] | null>(null)
  const [cambioScelto, setCambioScelto] = useState('')
  const [cambioInCorso, setCambioInCorso] = useState(false)
  const [cambioErrore, setCambioErrore] = useState<string | null>(null)
  const [cambioCaricamento, setCambioCaricamento] = useState(false)
  const [specOpzioni, setSpecOpzioni] = useState<Array<{ chiave: string; etichetta: string; deltas: Array<[string, number]> }> | null>(null)
  const [specScelta, setSpecScelta] = useState('')
  const [specInCorso, setSpecInCorso] = useState(false)
  const [specErrore, setSpecErrore] = useState<string | null>(null)
  const [specCaricamento, setSpecCaricamento] = useState(false)

  // Le opzioni si caricano una volta sola, quando si entra nella pagina
  // Training e non c'e' gia' un allenamento in corso da mostrare — cosi'
  // il picker e' gia' pronto appena si scorre, niente bottone "Cambia
  // ruolo" separato da premere prima.
  useEffect(() => {
    if (pagina !== 'training' || !cambioRuolo || cambioRuolo.inCorso || cambioTarget !== null) return
    setCambioCaricamento(true)
    setCambioErrore(null)
    cambioRuolo.onCaricaTarget()
      .then((target) => { setCambioTarget(target); setCambioScelto(target[0] ?? '') })
      .catch((errore) => setCambioErrore(errore instanceof Error ? errore.message : 'Ruoli raggiungibili non disponibili.'))
      .finally(() => setCambioCaricamento(false))
  }, [pagina, cambioRuolo, cambioTarget])

  useEffect(() => {
    if (pagina !== 'training' || !specializzazione || specializzazione.inCorso || specOpzioni !== null) return
    setSpecCaricamento(true)
    setSpecErrore(null)
    specializzazione.onCaricaOpzioni()
      .then((opzioni) => { setSpecOpzioni(opzioni); setSpecScelta(opzioni[0]?.chiave ?? '') })
      .catch((errore) => setSpecErrore(errore instanceof Error ? errore.message : 'Specializzazioni non disponibili.'))
      .finally(() => setSpecCaricamento(false))
  }, [pagina, specializzazione, specOpzioni])

  async function avviaCambioRuolo() {
    if (!cambioRuolo || !cambioScelto) return
    setCambioInCorso(true)
    setCambioErrore(null)
    try {
      await cambioRuolo.onAvvia(cambioScelto)
    } catch (errore) {
      setCambioErrore(errore instanceof Error ? errore.message : 'Cambio ruolo non riuscito.')
    }
    setCambioInCorso(false)
  }

  async function annullaCambioRuolo() {
    if (!cambioRuolo) return
    setCambioInCorso(true)
    setCambioErrore(null)
    try {
      await cambioRuolo.onAnnulla()
      setCambioTarget(null)
    } catch (errore) {
      setCambioErrore(errore instanceof Error ? errore.message : 'Annullamento non riuscito.')
    }
    setCambioInCorso(false)
  }

  async function avviaSpecializzazione() {
    if (!specializzazione || !specScelta) return
    setSpecInCorso(true)
    setSpecErrore(null)
    try {
      await specializzazione.onAvvia(specScelta)
    } catch (errore) {
      setSpecErrore(errore instanceof Error ? errore.message : 'Allenamento non riuscito.')
    }
    setSpecInCorso(false)
  }

  async function annullaSpecializzazione() {
    if (!specializzazione) return
    setSpecInCorso(true)
    setSpecErrore(null)
    try {
      await specializzazione.onAnnulla()
      setSpecOpzioni(null)
    } catch (errore) {
      setSpecErrore(errore instanceof Error ? errore.message : 'Annullamento non riuscito.')
    }
    setSpecInCorso(false)
  }

  // Notifica di successo: sparisce da sola dopo un secondo. Il cleanup annulla
  // il timer se nel frattempo arriva un altro esito o si chiude la scheda,
  // altrimenti il vecchio timer spegnerebbe il messaggio nuovo.
  useEffect(() => {
    if (!listaEsito) return
    const timer = window.setTimeout(() => setListaEsito(null), 1000)
    return () => window.clearTimeout(timer)
  }, [listaEsito])

  async function cambiaLista() {
    if (!listaMercato) return
    const prossimo = !inLista
    setListaInCorso(true)
    setListaErrore(null)
    setListaEsito(null)
    try {
      await listaMercato.onCambia(prossimo)
      setInLista(prossimo)
      setListaEsito(prossimo ? 'Giocatore inserito in lista' : 'Giocatore rimosso dalla lista')
    } catch (errore) {
      setListaErrore(errore instanceof Error ? errore.message : 'Operazione non riuscita.')
    }
    setListaInCorso(false)
  }

  async function apriRinnovo() {
    if (!rinnovo) return
    setVistaRinnovo(true)
    setProposta(null)
    setRinnovoErrore(null)
    setEsito(null)
    try {
      const dati = await rinnovo.onCarica()
      setProposta(dati)
      setOffertaM((dati.richiesta / 1_000_000).toFixed(1).replace('.', ','))
    } catch (errore) {
      setRinnovoErrore(errore instanceof Error ? errore.message : 'Proposta non disponibile.')
    }
  }

  // 0,1 M€ è il passo della scala ingaggi (design §5.1): si arrotonda lì.
  const offertaEuro = Math.round(parseFloat(offertaM.replace(',', '.')) * 10) * 100_000
  const offertaValida = Number.isFinite(offertaEuro) && offertaEuro >= 500_000

  async function inviaOfferta() {
    if (!rinnovo || !proposta || !offertaValida) return
    setRinnovoInCorso(true)
    setRinnovoErrore(null)
    try {
      const risposta = await rinnovo.onOffri(offertaEuro)
      setEsito(risposta)
      setProposta({ ...proposta, tentativi_usati: risposta.tentativi_usati, trattativa_chiusa: risposta.esito === 'chiusa' })
    } catch (errore) {
      setRinnovoErrore(errore instanceof Error ? errore.message : 'Offerta non riuscita.')
    }
    setRinnovoInCorso(false)
  }

  useEffect(() => {
    const chiudiConEsc = (evento: KeyboardEvent) => { if (evento.key === 'Escape') onClose() }
    document.addEventListener('keydown', chiudiConEsc)
    const overflowPrecedente = document.body.style.overflow
    document.body.style.overflow = 'hidden'
    return () => { document.removeEventListener('keydown', chiudiConEsc); document.body.style.overflow = overflowPrecedente }
  }, [onClose])

  const rep = reparto(giocatore.posizioni[0])

  if (vistaRinnovo) return <div className="player-modal-backdrop" role="presentation" onPointerDown={(evento) => { if (evento.target === evento.currentTarget) onClose() }}>
    <section className="player-modal player-modal--rinnovo" role="dialog" aria-modal="true" aria-label={`Rinnovo di ${giocatore.nome}`}>
      <button className="player-modal__close" type="button" onClick={() => setVistaRinnovo(false)} aria-label="Torna alla scheda">←</button>
      <div className={`rinnovo-ritratto player-modal__photo--${rep} ${fotoUrl ? 'has-photo' : ''}`}>
        <AnonymousPlayer />
        {fotoUrl && <img src={fotoUrl} alt={giocatore.nome} onError={(evento) => { evento.currentTarget.hidden = true; evento.currentTarget.parentElement?.classList.remove('has-photo') }} />}
      </div>
      <p className="kicker rinnovo-kicker">Trattativa · {giocatore.nome}</p>

      {rinnovoErrore && <p className="notice notice--error" role="alert">{rinnovoErrore}</p>}

      {!proposta && !rinnovoErrore && <p className="season-empty">Sto ascoltando la sua richiesta…</p>}

      {proposta && esito?.esito !== 'accettato' && <>
        <blockquote className="rinnovo-lettera">
          <p>Buongiorno mister{rinnovo?.nomeAllenatore ? ` ${rinnovo.nomeAllenatore}` : ''},</p>
          <p>questa è la mia proposta per il mio nuovo ingaggio.</p>
          <p className="rinnovo-lettera__firma">— {giocatore.nome}, {giocatore.eta} anni</p>
        </blockquote>
        <div className="rinnovo-cifre">
          <div><span>Ingaggio richiesto</span><strong>{milioni(proposta.richiesta)}</strong><small>a stagione</small></div>
          <div><span>Durata</span><strong>{stagioni(proposta.durata)}</strong><small>fino alla stagione {proposta.nuova_scadenza}</small></div>
        </div>

        {esito && <p className={`rinnovo-risposta rinnovo-risposta--${esito.esito}`}>«{esito.messaggio}»</p>}

        {proposta.gia_rinnovato ? <>
          <p className="rinnovo-nota">Ha rinnovato in questa stagione: se ne potrà ritrattare dalla prossima.</p>
          <div className="rinnovo-azioni"><button className="button button--secondary" type="button" onClick={() => setVistaRinnovo(false)}>Torna alla scheda</button></div>
        </> : proposta.trattativa_chiusa ? <>
          <p className="rinnovo-nota">La trattativa è chiusa: andrà a scadenza e lascerà la squadra a fine stagione.</p>
          <div className="rinnovo-azioni"><button className="button button--secondary" type="button" onClick={() => setVistaRinnovo(false)}>Torna alla scheda</button></div>
        </> : <>
          <div className="rinnovo-offerta">
            <p className="kicker">La tua offerta</p>
            <div>
              <label>
                <span>Ingaggio</span>
                <input type="text" inputMode="decimal" value={offertaM} onChange={(evento) => setOffertaM(evento.target.value)} aria-label="Ingaggio offerto in milioni" />
                <small>M€ a stagione</small>
              </label>
            </div>
          </div>
          <p className="rinnovo-nota">
            La durata non si negozia: un rinnovo estende sempre il contratto di una stagione.
            {' '}Il nuovo ingaggio decorre dalla prossima stagione — questa è già stata pagata.
          </p>
          <p className="rinnovo-tentativi">
            Tentativi rimasti: <b>{proposta.tentativi_totali - proposta.tentativi_usati}</b> su {proposta.tentativi_totali}.
            {' '}Esauriti, andrà a scadenza.
          </p>
          <div className="rinnovo-azioni">
            <button className="button button--primary" type="button" disabled={rinnovoInCorso || !offertaValida} onClick={inviaOfferta}>{rinnovoInCorso ? 'Attendo…' : 'Proponi'}</button>
            <button className="button button--secondary" type="button" disabled={rinnovoInCorso} onClick={() => setVistaRinnovo(false)}>Ci penso</button>
          </div>
        </>}
      </>}

      {esito?.esito === 'accettato' && <>
        <blockquote className="rinnovo-lettera rinnovo-lettera--firmata">
          <p>{esito.messaggio}</p>
          <p className="rinnovo-lettera__firma">— {giocatore.nome}</p>
        </blockquote>
        <p className="rinnovo-nota">Contratto rinnovato: {milioni(esito.ingaggio ?? 0)} a stagione fino alla stagione {esito.contratto_scadenza}.</p>
        <div className="rinnovo-azioni"><button className="button button--primary" type="button" onClick={onClose}>Chiudi</button></div>
      </>}
    </section>
  </div>

  return <div className="player-modal-backdrop" role="presentation" onPointerDown={(evento) => { if (evento.target === evento.currentTarget) onClose() }}>
    <section className="player-modal" role="dialog" aria-modal="true" aria-labelledby="player-modal-title">
      <button className="player-modal__close" type="button" onClick={onClose} aria-label="Chiudi dettagli giocatore">×</button>

      {haTraining && <UnderlineTabs
        className="player-modal__tabs"
        tabs={[{ value: 'scheda', label: 'Scheda' }, { value: 'training', label: 'Training' }] as const}
        value={pagina}
        onChange={setPagina}
      />}

      <div className="player-modal__pager" ref={pagerRef} onTouchStart={onTouchStart} onTouchEnd={onTouchEnd}>
        <div className={`player-modal__page ${haTraining && pagina !== 'scheda' ? 'is-nascosta' : ''}`}>
          <div className="player-modal__hero">
            <div className={`player-modal__photo player-modal__photo--${rep} ${fotoUrl ? 'has-photo' : ''}`}>
              <AnonymousPlayer />
              {fotoUrl && <img src={fotoUrl} alt={giocatore.nome} onError={(evento) => { evento.currentTarget.hidden = true; evento.currentTarget.parentElement?.classList.remove('has-photo') }} />}
            </div>
            <div>
              <p className="kicker">Scheda giocatore</p>
              <div className="player-modal__nome-riga">
                <h2 id="player-modal-title">{giocatore.nome}</h2>
                {giocatore.posizioni[0] && <span className={`role-pill role-pill--${rep.toLowerCase()}`}>{giocatore.posizioni[0]}</span>}
              </div>
              <p>{[giocatore.club, giocatore.nazionalita].filter(Boolean).join(' · ') || '—'}</p>
            </div>
            <strong className="player-modal__overall"><span>OVR</span>{giocatore.overall}</strong>
          </div>

          {giocatore.ritiroAnnunciato && <p className="player-modal__ritiro">Si ritira a fine stagione — non può essere ceduto.</p>}

          <dl className="player-modal__facts">
            <div><dt>Età</dt><dd>{giocatore.eta}</dd></div>
            <div><dt>Ruoli secondari</dt><dd>{giocatore.posizioni.slice(1).join(' · ') || 'Nessuno'}</dd></div>
            <div><dt>Piede</dt><dd>{giocatore.piede ?? '—'}</dd></div>
            <div><dt>Altezza</dt><dd>{giocatore.altezza ? `${giocatore.altezza} cm` : '—'}</dd></div>
            {typeof giocatore.ingaggio === 'number' && <div className="fatto-ingaggio">
              <dt>Ingaggio</dt>
              <dd>
                {(giocatore.ingaggio / 1_000_000).toFixed(1)} M€ <small>/ stagione</small>
                {typeof giocatore.contrattoScadenza === 'number' && typeof giocatore.stagioneCorrente === 'number' && (() => {
                  const residue = giocatore.contrattoScadenza - giocatore.stagioneCorrente
                  return <small className="fatto-contratto">
                    {residue <= 0
                      ? 'In scadenza a fine stagione'
                      : `Contratto fino alla stagione ${giocatore.contrattoScadenza} · ancora ${stagioni(residue)} dopo questa`}
                  </small>
                })()}
              </dd>
            </div>}
          </dl>

          {typeof giocatore.condizione === 'number' && <section className={`player-modal__fitness ${(giocatore.infortunatoFinoA ?? 0) > 0 ? 'is-injured' : (giocatore.squalificatoFinoA ?? 0) > 0 ? 'is-suspended' : ''}`}>
            <div>
              <span>Forma fisica</span>
              {(giocatore.infortunatoFinoA ?? 0) > 0
                ? <strong>Infortunato</strong>
                : (giocatore.squalificatoFinoA ?? 0) > 0
                  ? <strong>Squalificato</strong>
                  : <strong>{giocatore.condizione}%</strong>}
            </div>
            {(giocatore.infortunatoFinoA ?? 0) > 0
              ? <p>Rientro previsto tra {giocatore.infortunatoFinoA} {giocatore.infortunatoFinoA === 1 ? 'giornata' : 'giornate'}.</p>
              : (giocatore.squalificatoFinoA ?? 0) > 0
                ? <p>Salta ancora {giocatore.squalificatoFinoA} {giocatore.squalificatoFinoA === 1 ? 'giornata' : 'giornate'}.</p>
                : <><div className="player-modal__fitness-bar"><i style={{ width: `${giocatore.condizione}%` }} /></div><p>{giocatore.condizione >= 75 ? 'Pronto per giocare.' : giocatore.condizione >= 55 ? 'Condizione da gestire.' : 'Rischio elevato di sostituzione.'}</p></>}
          </section>}

          {typeof giocatore.morale === 'number' && <section className={`player-modal__morale morale--${etichettaMorale(giocatore.morale).classe}`}>
            <div>
              <span>Morale</span>
              <strong>{etichettaMorale(giocatore.morale).testo}</strong>
            </div>
            <div className="player-modal__morale-bar"><i style={{ width: `${giocatore.morale}%` }} /></div>
            {giocatore.mentalita && (() => {
              const rami = RAMI_MENTALITA.map(([chiave, nome, descrizione]) => ({ chiave, nome, descrizione, valore: giocatore.mentalita![chiave] }))
              const dominante = rami.reduce((piuAlto, ramo) => ramo.valore > piuAlto.valore ? ramo : piuAlto)
              return <>
                <p className="player-modal__mentalita-nota"><b>{dominante.nome}</b> — {dominante.descrizione}</p>
                <div className="player-modal__mentalita">
                  {rami.map((ramo) => <div className={ramo.chiave === dominante.chiave ? 'is-dominante' : ''} key={ramo.chiave}>
                    <span>{ramo.nome}</span>
                    <i><span style={{ width: `${ramo.valore}%` }} /></i>
                    <b>{ramo.valore}</b>
                  </div>)}
                </div>
              </>
            })()}
          </section>}

          {stagione && <div className="player-modal__stats">
            <h3>Stagione</h3>
            {stagione.presenze === 0
              ? <p className="season-empty">Non ha ancora giocato in questa stagione.</p>
              : <>
                <div className="scheda-numeri">
                  <div><b>{stagione.presenze}</b><span>Presenze</span></div>
                  <div><b>{stagione.minuti}</b><span>Minuti</span></div>
                  <div><b>{stagione.gol}</b><span>Gol</span></div>
                  <div><b>{stagione.assist}</b><span>Assist</span></div>
                  <div><b>{stagione.porteInviolate}</b><span>Porta inviolata</span></div>
                  <div><b>{stagione.minuti > 0 ? ((stagione.gol + stagione.assist) * 90 / stagione.minuti).toFixed(2) : '—'}</b><span>G+A ogni 90&#39;</span></div>
                </div>
                <div className="scheda-quote">
                  <div><span>Tiri in porta</span><b>{percentuale(stagione.tiriPorta, stagione.tiri)}</b><small>{stagione.tiriPorta} su {stagione.tiri}</small></div>
                  <div><span>Passaggi riusciti</span><b>{percentuale(stagione.passaggiRiusciti, stagione.passaggiTentati)}</b><small>{stagione.passaggiRiusciti} su {stagione.passaggiTentati}</small></div>
                  <div><span>Contrasti vinti</span><b>{stagione.contrastiVinti}</b><small>totali</small></div>
                  <div><span>Dribbling riusciti</span><b>{stagione.dribbling}</b><small>totali</small></div>
                </div>
              </>}
          </div>}

          <div className="player-modal__stats">
            <h3>Abilità</h3>
            <RadarAbilita attributi={giocatore.attributi} />
            <div className="player-abilita-gruppi">
              {GRUPPI_ATTRIBUTI.filter((gruppo) => !gruppo.soloGk || rep === 'GK').map((gruppo) => (
                <GruppoAbilita gruppo={gruppo} attributi={giocatore.attributi} key={gruppo.titolo} />
              ))}
            </div>
          </div>

          {(azionePericolosa || rinnovo || listaMercato) && <div className="player-modal__danger">
            {!confermaAperta
              ? <div className="player-modal__azioni">
                  {azionePericolosa && <button className="button button--danger-ghost" type="button" onClick={() => setConfermaAperta(true)}>{azionePericolosa.etichetta}</button>}
                  {rinnovo && (rinnovo.bloccato
                    ? <button className="button button--secondary" type="button" disabled title={rinnovo.bloccato}>Rinnovo</button>
                    : <button className="button button--secondary" type="button" onClick={apriRinnovo}>Rinnovo</button>)}
                  {listaMercato && <button className={`button player-modal__lista ${inLista ? 'button--secondary' : 'button--primary'}`} type="button" disabled={listaInCorso} onClick={cambiaLista}>
                    {listaInCorso ? 'Attendi…' : inLista ? 'Rimuovi dal mercato' : 'Metti sul mercato'}
                  </button>}
                  {listaEsito && <p className="player-modal__lista-esito" role="status">{listaEsito}</p>}
                  {listaErrore && <p className="notice notice--error player-modal__lista-esito" role="alert">{listaErrore}</p>}
                </div>
              : azionePericolosa && <div className="player-modal__confirm">
                  <div><strong>Confermi lo svincolo?</strong><p>{azionePericolosa.descrizione}</p></div>
                  {azionePericolosa.errore && <p className="notice notice--error">{azionePericolosa.errore}</p>}
                  <div>
                    <button className="button button--danger" type="button" disabled={azionePericolosa.inCorso} onClick={azionePericolosa.onConferma}>{azionePericolosa.inCorso ? 'Svincolo…' : 'Svincola definitivamente'}</button>
                    <button className="button button--secondary" type="button" disabled={azionePericolosa.inCorso} onClick={() => setConfermaAperta(false)}>Annulla</button>
                  </div>
                </div>}
          </div>}
        </div>

        {haTraining && <div className={`player-modal__page player-modal__page--training ${pagina !== 'training' ? 'is-nascosta' : ''}`}>
          <p className="player-training-intro">Allenamento di {giocatore.nome}: cambio di ruolo e specializzazione, dal ramo TRAINING di Gestione risorse.</p>

          {cambioRuolo && <PannelloAllenamento
            titolo="Cambio ruolo"
            attuale={null}
            inCorso={cambioRuolo.inCorso ? {
              etichettaPrima: cambioRuolo.inCorso.ruoloPrecedente, etichettaDopo: cambioRuolo.inCorso.ruoloTarget,
              avviatoGiornata: cambioRuolo.inCorso.avviatoGiornata, completaGiornata: cambioRuolo.inCorso.completaGiornata,
            } : null}
            prossimaGiornata={cambioRuolo.prossimaGiornata}
            opzioni={cambioTarget?.map((r) => ({ chiave: r, etichetta: r }))
              ?? (cambioCaricamento ? null : [])}
            opzioniCaricamento={cambioCaricamento}
            scelta={cambioScelto}
            onScegli={setCambioScelto}
            onAvvia={avviaCambioRuolo}
            onAnnulla={annullaCambioRuolo}
            inviando={cambioInCorso}
            errore={cambioErrore}
            bloccatoDa={specializzazione?.inCorso ? 'un allenamento di specializzazione' : null}
          />}

          {specializzazione && <PannelloAllenamento
            titolo="Specializzazione"
            attuale={specializzazione.attiva}
            inCorso={specializzazione.inCorso ? {
              etichettaPrima: specializzazione.inCorso.specializzazionePrecedente, etichettaDopo: specializzazione.inCorso.specializzazioneTarget,
              avviatoGiornata: specializzazione.inCorso.avviatoGiornata, completaGiornata: specializzazione.inCorso.completaGiornata,
            } : null}
            prossimaGiornata={specializzazione.prossimaGiornata}
            opzioni={specOpzioni?.map((o) => ({
              chiave: o.chiave, etichetta: o.etichetta,
              sottotesto: o.deltas.map(([chiave]) => etichettaAttributo(chiave)).join(' · '),
            })) ?? (specCaricamento ? null : [])}
            opzioniCaricamento={specCaricamento}
            scelta={specScelta}
            onScegli={setSpecScelta}
            onAvvia={avviaSpecializzazione}
            onAnnulla={annullaSpecializzazione}
            inviando={specInCorso}
            errore={specErrore}
            bloccatoDa={cambioRuolo?.inCorso ? 'un cambio ruolo' : null}
            confrontoScelta={(() => {
              const opzione = specOpzioni?.find((o) => o.chiave === specScelta)
              return opzione ? <ConfrontoAttributi deltas={opzione.deltas} attributi={giocatore.attributi} /> : null
            })()}
          />}
        </div>}
      </div>
    </section>
  </div>
}
