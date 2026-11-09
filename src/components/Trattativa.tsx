import { Icona, type NomeIcona } from './Icona'
import { NOME_OPZIONE, type OpzioneContratto } from '../lib/contratti'

// Pezzi comuni delle trattative di contratto (rinnovo dalla scheda giocatore, primo contratto degli under dal vivaio).

export type Moltiplicatore = { durata: number; opzione: OpzioneContratto | null; moltiplicatore: number }

// Stessa formula del server (public.offri_rinnovo, public.offri_promozione): richiesta x moltiplicatore di durata e
// opzione, al passo di 0,1 M€, mai sotto 0,5 M€ ne' oltre l'ingaggio massimo.
export function richiestaContratto(base: number, moltiplicatori: Moltiplicatore[] | null | undefined, pluriennali: boolean | undefined,
  durata: number, opzione: OpzioneContratto | null, massimo?: number) {
  const m = pluriennali ? moltiplicatori?.find((x) => x.durata === durata && x.opzione === opzione)?.moltiplicatore ?? 1 : 1
  return Math.min(massimo ?? Infinity, Math.max(500_000, Math.round((base * m) / 100_000) * 100_000))
}

// La barra di soddisfazione della trattativa (9/11/2026): al 100% gli si offre quanto chiede. Non mostra dove sta la
// soglia di accettazione (la zona sfumata aiutava troppo e rendeva inutili i tre tentativi): il colore va dal rosso
// al verde con la percentuale, uguale per tutti i giocatori.
export function BarraSoddisfazione({ offerta, richiesta }: { offerta: number; richiesta: number }) {
  const percento = richiesta > 0 ? Math.round((offerta / richiesta) * 100) : 0
  const pieno = Math.min(100, Math.max(0, percento))
  // 50% e sotto rosso, 100% verde
  const tinta = Math.round(Math.min(1, Math.max(0, (percento - 50) / 50)) * 130)
  return <div className="rinnovo-soddisfazione">
    <div className="rinnovo-soddisfazione__testa">
      <span>Soddisfazione</span>
      <b>{percento}%</b>
    </div>
    <div className="rinnovo-soddisfazione__barra" role="meter" aria-valuemin={0} aria-valuemax={100} aria-valuenow={pieno} aria-label="Soddisfazione del giocatore">
      <span className="rinnovo-soddisfazione__riempimento" style={{ width: `${pieno}%`, backgroundColor: `hsl(${tinta} 68% 52%)` }} />
    </div>
    <small>100% = quello che chiede. Quanto sia disposto a scendere dipende da lui: bandiera, voglia di vincere, soldi e morale.</small>
  </div>
}

// Una tessera d'azione, stile menu dei giochi: icona nel colore della fase, nome dell'azione, una riga che dice cosa
// fa, freccia. Alta almeno 64 px e staccata dalle altre, per non sbagliare il tocco.
export function AzioneScheda({ icona, titolo, sotto, primaria, pericolo, compatta, disabled, onClick }: {
  icona: NomeIcona; titolo: string; sotto?: string; primaria?: boolean; pericolo?: boolean; compatta?: boolean; disabled?: boolean; onClick: () => void
}) {
  return <button type="button" className={`azione-scheda${primaria ? ' is-primaria' : ''}${pericolo ? ' is-pericolo' : ''}${compatta ? ' is-compatta' : ''}`} disabled={disabled} onClick={onClick}>
    <span className="azione-scheda__icona"><Icona nome={icona} /></span>
    <span className="azione-scheda__testo"><strong>{titolo}</strong>{sotto && <small>{sotto}</small>}</span>
    <span className="azione-scheda__freccia"><Icona nome="avanti" /></span>
  </button>
}

// Invio dell'offerta: i tentativi rimasti ben in vista (9/11/2026: scritti solo nel pulsante si dimenticavano), la
// tessera piena «Proponi» (consuma un tentativo) e, staccato sotto, «Ci penso». All'ultimo tentativo tutto diventa rosso.
export function AzioniOfferta({ inCorso, disabilitato, tentativiRimasti, tentativiTotali, onProponi, onAnnulla, seChiude = 'andrà a scadenza' }: {
  inCorso: boolean; disabilitato: boolean; tentativiRimasti: number; tentativiTotali: number; onProponi: () => void; onAnnulla: () => void
  /** Cosa succede se rifiuta l'ultima offerta. */
  seChiude?: string
}) {
  const ultimo = tentativiRimasti <= 1
  return <div className="trattativa-azioni">
    <div className={`trattativa-tentativi${ultimo ? ' is-ultimo' : ''}`} role="status">
      <span className="trattativa-tentativi__pallini" aria-hidden="true">
        {Array.from({ length: tentativiTotali }, (_, i) => <i key={i} className={i < tentativiTotali - tentativiRimasti ? 'is-usato' : ''} />)}
      </span>
      <span className="trattativa-tentativi__testo">
        <b>{ultimo ? 'Ultimo tentativo' : `Tentativi rimasti: ${tentativiRimasti} su ${tentativiTotali}`}</b>
        {ultimo && <small>Se rifiuta, {seChiude}.</small>}
      </span>
    </div>
    <AzioneScheda icona="contratto" titolo={inCorso ? 'Attendo…' : 'Proponi'} primaria disabled={inCorso || disabilitato} onClick={onProponi}
      sotto={ultimo ? 'Ultimo tentativo' : 'Usa un tentativo'} />
    <button className="trattativa-azioni__annulla" type="button" disabled={inCorso} onClick={onAnnulla}>Ci penso</button>
  </div>
}

// Durata (1-3 stagioni) e opzione +1 del contratto, con la richiesta di ognuna.
export function SceltaContratto({ durata, opzione, stagioneFine, richiestaPer, disabled, onScegli }: {
  durata: number; opzione: OpzioneContratto | null
  /** Ultima stagione coperta da una durata (rinnovo: corrente + d; primo contratto: corrente + d - 1). */
  stagioneFine: (durata: number) => number
  richiestaPer: (durata: number, opzione: OpzioneContratto | null) => number
  disabled?: boolean
  onScegli: (durata: number, opzione: OpzioneContratto | null) => void
}) {
  const milioni = (euro: number) => `${(euro / 1_000_000).toFixed(1).replace('.', ',')} M€`
  return <div className="rinnovo-gradini rinnovo-durata">
    <p className="kicker">Durata del contratto</p>
    <div className="rinnovo-durata__scelte" role="radiogroup" aria-label="Durata del contratto">
      {[1, 2, 3].map((d) => <button key={d} type="button" role="radio" aria-checked={durata === d}
        className={`rinnovo-gradino${durata === d ? ' is-scelto' : ''}`} disabled={disabled} onClick={() => onScegli(d, opzione)}>
        <strong>{d === 1 ? '1 stagione' : `${d} stagioni`}</strong>
        <small>fino alla {stagioneFine(d)}</small>
        <b>{milioni(richiestaPer(d, opzione))}</b>
      </button>)}
    </div>
    <p className="kicker">Opzione +1</p>
    <div className="rinnovo-durata__scelte" role="radiogroup" aria-label="Opzione per una stagione in più">
      {([null, 'squadra', 'giocatore'] as const).map((o) => <button key={o ?? 'nessuna'} type="button" role="radio" aria-checked={opzione === o}
        className={`rinnovo-gradino${opzione === o ? ' is-scelto' : ''}`} disabled={disabled} onClick={() => onScegli(durata, o)}>
        <strong>{o ? NOME_OPZIONE[o][0].toUpperCase() + NOME_OPZIONE[o].slice(1) : 'Nessuna'}</strong>
        <small>{o === 'squadra' ? 'Decidi tu se tenerlo' : o === 'giocatore' ? 'Decide lui se restare' : 'Contratto secco'}</small>
        <b>{milioni(richiestaPer(durata, o))}</b>
      </button>)}
    </div>
  </div>
}
