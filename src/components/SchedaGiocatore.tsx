import { useEffect, useState } from 'react'

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
    inCorso: { ruoloPrecedente: string; ruoloTarget: string; completaGiornata: number } | null
    /** Giornata di riferimento per il conto alla rovescia: solo indicativa, il server decide davvero. */
    prossimaGiornata: number | null
    onCaricaTarget: () => Promise<string[]>
    onAvvia: (ruoloTarget: string) => Promise<void>
    onAnnulla: () => Promise<void>
  }
  specializzazione?: {
    /** Etichetta della specializzazione gia' attiva, se nessun allenamento e' in corso. */
    attiva: string | null
    inCorso: { specializzazionePrecedente: string | null; specializzazioneTarget: string; completaGiornata: number } | null
    prossimaGiornata: number | null
    onCaricaOpzioni: () => Promise<Array<{ chiave: string; etichetta: string; deltas: Array<[string, number]> }>>
    onAvvia: (specializzazione: string) => Promise<void>
    onAnnulla: () => Promise<void>
  }
  onClose: () => void
}

const ETICHETTE_ATTRIBUTI: Array<[string, string]> = [
  ['pace', 'Velocità'], ['shooting', 'Tiro'], ['passing', 'Passaggio'], ['dribbling_generale', 'Dribbling'], ['defending', 'Difesa'], ['physic', 'Fisico'],
  ['stamina', 'Resistenza'], ['finishing', 'Finalizzazione'], ['short_passing', 'Passaggi corti'], ['standing_tackle', 'Contrasti'],
  ['gk_diving', 'Tuffo'], ['gk_handling', 'Presa'], ['gk_kicking', 'Rinvio'], ['gk_positioning', 'Posizionamento'], ['gk_reflexes', 'Riflessi'],
]

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
  const [cambioAperto, setCambioAperto] = useState(false)
  const [cambioTarget, setCambioTarget] = useState<string[] | null>(null)
  const [cambioScelto, setCambioScelto] = useState('')
  const [cambioInCorso, setCambioInCorso] = useState(false)
  const [cambioErrore, setCambioErrore] = useState<string | null>(null)
  const [specAperto, setSpecAperto] = useState(false)
  const [specOpzioni, setSpecOpzioni] = useState<Array<{ chiave: string; etichetta: string; deltas: Array<[string, number]> }> | null>(null)
  const [specScelta, setSpecScelta] = useState('')
  const [specInCorso, setSpecInCorso] = useState(false)
  const [specErrore, setSpecErrore] = useState<string | null>(null)

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

  async function apriCambioRuolo() {
    if (!cambioRuolo) return
    setCambioAperto(true)
    setCambioErrore(null)
    try {
      const target = await cambioRuolo.onCaricaTarget()
      setCambioTarget(target)
      setCambioScelto(target[0] ?? '')
    } catch (errore) {
      setCambioErrore(errore instanceof Error ? errore.message : 'Ruoli raggiungibili non disponibili.')
    }
  }

  async function avviaCambioRuolo() {
    if (!cambioRuolo || !cambioScelto) return
    setCambioInCorso(true)
    setCambioErrore(null)
    try {
      await cambioRuolo.onAvvia(cambioScelto)
      setCambioAperto(false)
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
    } catch (errore) {
      setCambioErrore(errore instanceof Error ? errore.message : 'Annullamento non riuscito.')
    }
    setCambioInCorso(false)
  }

  async function apriSpecializzazione() {
    if (!specializzazione) return
    setSpecAperto(true)
    setSpecErrore(null)
    try {
      const opzioni = await specializzazione.onCaricaOpzioni()
      setSpecOpzioni(opzioni)
      setSpecScelta(opzioni[0]?.chiave ?? '')
    } catch (errore) {
      setSpecErrore(errore instanceof Error ? errore.message : 'Specializzazioni non disponibili.')
    }
  }

  async function avviaSpecializzazione() {
    if (!specializzazione || !specScelta) return
    setSpecInCorso(true)
    setSpecErrore(null)
    try {
      await specializzazione.onAvvia(specScelta)
      setSpecAperto(false)
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
    } catch (errore) {
      setSpecErrore(errore instanceof Error ? errore.message : 'Annullamento non riuscito.')
    }
    setSpecInCorso(false)
  }

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
      <div className="player-modal__hero">
        <div className={`player-modal__photo player-modal__photo--${rep} ${fotoUrl ? 'has-photo' : ''}`}>
          <AnonymousPlayer />
          {fotoUrl && <img src={fotoUrl} alt={giocatore.nome} onError={(evento) => { evento.currentTarget.hidden = true; evento.currentTarget.parentElement?.classList.remove('has-photo') }} />}
        </div>
        <div>
          <p className="kicker">Scheda giocatore</p>
          <h2 id="player-modal-title">{giocatore.nome}</h2>
          <p>{[giocatore.club, giocatore.nazionalita].filter(Boolean).join(' · ') || '—'}</p>
        </div>
        <strong className="player-modal__overall"><span>OVR</span>{giocatore.overall}</strong>
      </div>

      {giocatore.ritiroAnnunciato && <p className="player-modal__ritiro">Si ritira a fine stagione — non può essere ceduto.</p>}

      <dl className="player-modal__facts">
        <div><dt>Età</dt><dd>{giocatore.eta}</dd></div>
        <div><dt>Ruoli</dt><dd>{giocatore.posizioni.join(' · ') || '—'}</dd></div>
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
        <h3>Attributi</h3>
        <div className="player-stats-grid">
          {ETICHETTE_ATTRIBUTI.map(([chiave, etichetta]) => {
            const valore = giocatore.attributi[chiave]
            return typeof valore === 'number'
              ? <div className="player-stat" key={chiave}><span>{etichetta}</span><b>{valore}</b><i><span style={{ width: `${valore}%` }} /></i></div>
              : null
          })}
        </div>
      </div>

      {(azionePericolosa || rinnovo || listaMercato || cambioRuolo || specializzazione) && <div className="player-modal__danger">
        {!confermaAperta
          ? <div className="player-modal__azioni">
              {azionePericolosa && <button className="button button--danger-ghost" type="button" onClick={() => setConfermaAperta(true)}>{azionePericolosa.etichetta}</button>}
              {rinnovo && (rinnovo.bloccato
                ? <button className="button button--secondary" type="button" disabled title={rinnovo.bloccato}>Rinnovo</button>
                : <button className="button button--secondary" type="button" onClick={apriRinnovo}>Rinnovo</button>)}
              {listaMercato && <button className={`button player-modal__lista ${inLista ? 'button--secondary' : 'button--primary'}`} type="button" disabled={listaInCorso} onClick={cambiaLista}>
                {listaInCorso ? 'Attendi…' : inLista ? 'Rimuovi dal mercato' : 'Metti sul mercato'}
              </button>}
              {cambioRuolo && !cambioRuolo.inCorso && !cambioAperto && <button className="button button--secondary" type="button" onClick={apriCambioRuolo}>Cambia ruolo</button>}
              {specializzazione && !specializzazione.inCorso && !specAperto && <button className="button button--secondary" type="button" onClick={apriSpecializzazione}>Allena specializzazione</button>}
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

        {cambioRuolo?.inCorso && <div className="player-modal__cambio-ruolo">
          <p>
            Riqualificazione in corso: da <b>{cambioRuolo.inCorso.ruoloPrecedente}</b> a <b>{cambioRuolo.inCorso.ruoloTarget}</b>.
            {' '}{cambioRuolo.prossimaGiornata != null
              ? ` Pronto tra ${Math.max(0, cambioRuolo.inCorso.completaGiornata - cambioRuolo.prossimaGiornata)} giornate.`
              : ` Completa alla giornata ${cambioRuolo.inCorso.completaGiornata}.`}
          </p>
          {cambioErrore && <p className="notice notice--error">{cambioErrore}</p>}
          <button className="button button--danger-ghost" type="button" disabled={cambioInCorso} onClick={annullaCambioRuolo}>
            {cambioInCorso ? 'Attendi…' : 'Annulla riqualificazione'}
          </button>
        </div>}

        {cambioRuolo && !cambioRuolo.inCorso && cambioAperto && <div className="player-modal__cambio-ruolo">
          {cambioErrore && <p className="notice notice--error">{cambioErrore}</p>}
          {cambioTarget === null ? <p className="season-empty">Carico i ruoli raggiungibili…</p>
            : cambioTarget.length === 0 ? <p className="season-empty">Nessun ruolo vicino raggiungibile (i portieri non si riqualificano).</p>
            : <>
                <label>
                  <span>Nuovo ruolo</span>
                  <select value={cambioScelto} onChange={(evento) => setCambioScelto(evento.target.value)}>
                    {cambioTarget.map((ruolo) => <option value={ruolo} key={ruolo}>{ruolo}</option>)}
                  </select>
                </label>
                <div>
                  <button className="button button--primary" type="button" disabled={cambioInCorso} onClick={avviaCambioRuolo}>
                    {cambioInCorso ? 'Avvio…' : 'Avvia riqualificazione'}
                  </button>
                  <button className="button button--secondary" type="button" disabled={cambioInCorso} onClick={() => setCambioAperto(false)}>Annulla</button>
                </div>
              </>}
        </div>}

        {specializzazione?.inCorso && <div className="player-modal__cambio-ruolo">
          <p>
            Allenamento in corso: {specializzazione.inCorso.specializzazionePrecedente ? <>da <b>{specializzazione.inCorso.specializzazionePrecedente}</b> a</> : 'verso'} <b>{specializzazione.inCorso.specializzazioneTarget}</b>.
            {' '}{specializzazione.prossimaGiornata != null
              ? ` Pronto tra ${Math.max(0, specializzazione.inCorso.completaGiornata - specializzazione.prossimaGiornata)} giornate.`
              : ` Completa alla giornata ${specializzazione.inCorso.completaGiornata}.`}
          </p>
          {specErrore && <p className="notice notice--error">{specErrore}</p>}
          <button className="button button--danger-ghost" type="button" disabled={specInCorso} onClick={annullaSpecializzazione}>
            {specInCorso ? 'Attendi…' : 'Annulla allenamento'}
          </button>
        </div>}

        {specializzazione && !specializzazione.inCorso && specAperto && <div className="player-modal__cambio-ruolo">
          {specializzazione.attiva && <p className="field-help">Specializzazione attuale: <b>{specializzazione.attiva}</b>. Riallenarsi la sostituisce.</p>}
          {specErrore && <p className="notice notice--error">{specErrore}</p>}
          {specOpzioni === null ? <p className="season-empty">Carico le specializzazioni…</p>
            : specOpzioni.length === 0 ? <p className="season-empty">Il portiere non ha specializzazioni: il motore riassume le sue qualità in un unico valore.</p>
            : <>
                <label>
                  <span>Specializzazione</span>
                  <select value={specScelta} onChange={(evento) => setSpecScelta(evento.target.value)}>
                    {specOpzioni.map((opzione) => <option value={opzione.chiave} key={opzione.chiave}>{opzione.etichetta}</option>)}
                  </select>
                </label>
                {specOpzioni.find((opzione) => opzione.chiave === specScelta) && <p className="field-help">
                  Migliora {specOpzioni.find((opzione) => opzione.chiave === specScelta)!.deltas
                    .map(([chiave, valore]) => `${etichettaAttributo(chiave)} +${valore}`).join(', ')}.
                </p>}
                <div>
                  <button className="button button--primary" type="button" disabled={specInCorso} onClick={avviaSpecializzazione}>
                    {specInCorso ? 'Avvio…' : 'Avvia allenamento'}
                  </button>
                  <button className="button button--secondary" type="button" disabled={specInCorso} onClick={() => setSpecAperto(false)}>Annulla</button>
                </div>
              </>}
        </div>}
      </div>}
    </section>
  </div>
}
