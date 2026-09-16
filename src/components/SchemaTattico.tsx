// ============================================================
//  SCHEMA TATTICO — posizioni, ruoli e compiti
//
//  Scelto un modulo si entra qui e si tocca una posizione: la si puo' far
//  salire o scendere di una linea sulla propria corsia (un 4-4-2 i cui due CM
//  diventano CDM), darle un ruolo e un compito.
//
//  LE DUE BARRE IN TESTA SONO IL PUNTO. Ogni modifica costa familiarita', e il
//  costo si vede PRIMA di salvare: e' quello che rende la schermata una scelta
//  invece di un menu. Le formule sono le stesse di private.avanza_familiarita
//  in SQL e di quoteFamiliarita nell'Edge Function — tre posti, una formula.
// ============================================================
import { useMemo, useState } from 'react'
import { COMPITI, FAM_PARTITE_PIENA, MODULI, RUOLI_SLOT, SPOSTAMENTI_SLOT } from '../lib/tattica'
import { schieramentoInCampo } from '../lib/schieramento'

const ruoliPerSlot = (slot: string): string[] => RUOLI_SLOT[slot] ?? []

export type XpDisposizione = { disposizione: string[]; partite: number }

type Player = { id: number; nome: string; posizioni: string[]; overall_corrente: number }

type Props = {
  modulo: string
  disposizione: string[] | null
  ruoli: (string | null)[] | null
  compiti: (string | null)[] | null
  titolari: number[]
  players: Player[]
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

const COMPITO_LABEL: Record<string, { nome: string; detto: string }> = {
  difesa: { nome: 'Difensivo', detto: 'Resta dietro la linea della palla.' },
  equilibrio: { nome: 'Equilibrato', detto: 'Nessuna indicazione particolare.' },
  attacco: { nome: 'Offensivo', detto: 'Si spinge in avanti appena può.' },
}

const REPARTO_DI = (slot: string): 'gk' | 'dif' | 'mid' | 'att' =>
  slot === 'GK' ? 'gk'
    : ['CB', 'LB', 'RB', 'LWB', 'RWB'].includes(slot) ? 'dif'
      : ['CDM', 'CM', 'CAM', 'LM', 'RM'].includes(slot) ? 'mid' : 'att'

const resaFamiliarita = (distanza: number) =>
  Math.max(0, Math.min(1, 1 - 1.6 * Math.max(0, Math.min(1, distanza))))

const uguali = (a: string[], b: string[]) => a.reduce((n, s, i) => n + (s === b[i] ? 1 : 0), 0)

export default function SchemaTattico({
  modulo, disposizione, ruoli, compiti, titolari, players, xpDisposizione, xpIndicazioni, onChange, onClose,
}: Props) {
  const standard = MODULI[modulo] ?? []
  const schema = disposizione ?? standard
  const [aperto, setAperto] = useState<number | null>(null)

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

  const quotaIndicazioni = Math.min(1, xpIndicazioni / FAM_PARTITE_PIENA)

  const cambiati = uguali(standard, schema) === 11 ? 0 : 11 - uguali(standard, schema)
  const conIndicazioni = (ruoli?.filter(Boolean).length ?? 0) + (compiti?.filter((c) => c && c !== 'equilibrio').length ?? 0)

  // --- modifiche ---
  const scrivi = (i: number, campo: 'slot' | 'ruolo' | 'compito', valore: string | null) => {
    let d = [...schema]
    let r: (string | null)[] = ruoli ? [...ruoli] : Array(11).fill(null)
    let c: (string | null)[] = compiti ? [...compiti] : Array(11).fill(null)
    if (campo === 'slot' && valore) {
      d[i] = valore
      // Il ruolo apparteneva alla posizione di prima: se non esiste piu' qui,
      // torna a niente invece di restare addosso a una posizione che non lo
      // prevede — sarebbe il salvataggio a rifiutarlo, e con un errore oscuro.
      if (r[i] && !ruoliPerSlot(valore).includes(r[i] as string)) r[i] = null
    }
    if (campo === 'ruolo') r[i] = valore
    if (campo === 'compito') c[i] = valore
    const dNullo = uguali(d, standard) === 11
    const rNullo = r.every((x) => !x)
    const cNullo = c.every((x) => !x || x === 'equilibrio')
    onChange(dNullo ? null : d, rNullo ? null : r, cNullo ? null : c)
  }

  const ripristina = () => { onChange(null, null, null); setAperto(null) }

  const postoAperto = aperto === null ? null : posti.find((p) => p.index === aperto) ?? null
  const slotAperto = postoAperto ? schema[postoAperto.index] : null
  const giocatoreAperto = postoAperto ? players.find((p) => p.id === titolari[postoAperto.index]) : undefined

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
        <Barra
          nome="Disposizione"
          quota={quotaDisposizione}
          nota={cambiati === 0 ? 'Lo schieramento standard del modulo.' : `${cambiati} ${cambiati === 1 ? 'posizione spostata' : 'posizioni spostate'}.`}
        />
        <Barra
          nome="Indicazioni"
          quota={quotaIndicazioni}
          nota={conIndicazioni === 0 ? 'Nessuna indicazione data.' : `${conIndicazioni} ${conIndicazioni === 1 ? 'indicazione attiva' : 'indicazioni attive'}.`}
        />
      </div>
      <p className="schema__spiega">
        La squadra rende meglio quanto più conosce lo schieramento e le indicazioni. Spostare una posizione
        o cambiare molte indicazioni insieme fa scendere le barre: tornano su giocando.
      </p>

      <div className="schema__campo pitch-field" aria-label={`Schema ${modulo}`}>
        <div className="pitch-field__circle" />
        <div className="pitch-field__box pitch-field__box--top" />
        <div className="pitch-field__box pitch-field__box--bottom" />
        {posti.map((posto) => {
          const slot = schema[posto.index]
          const giocatore = players.find((p) => p.id === titolari[posto.index])
          const ruolo = ruoli?.[posto.index] ?? null
          const compito = compiti?.[posto.index] ?? null
          const spostata = slot !== standard[posto.index]
          return (
            <button
              key={posto.index}
              type="button"
              className={`schema__posto schema__posto--${REPARTO_DI(slot)}${spostata ? ' is-spostata' : ''}${aperto === posto.index ? ' is-aperta' : ''}`}
              style={{ left: `${posto.x}%`, top: `${100 - posto.y}%` }}
              onClick={() => setAperto(aperto === posto.index ? null : posto.index)}
            >
              <span className="schema__slot">{slot}</span>
              <span className="schema__nome">{giocatore ? cognome(giocatore.nome) : '—'}</span>
              {(ruolo || (compito && compito !== 'equilibrio')) && (
                <span className={`schema__badge schema__badge--${compito ?? 'equilibrio'}`}>
                  {ruolo ? RUOLO_LABEL[ruolo]?.nome ?? ruolo : COMPITO_LABEL[compito ?? 'equilibrio'].nome}
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
              <strong>{giocatoreAperto?.nome ?? 'Posizione vuota'}</strong>
              <small>{slotAperto}{slotAperto !== standard[postoAperto.index] && ` · era ${standard[postoAperto.index]}`}</small>
            </header>

            {slotAperto !== 'GK' && (
              <>
                <h3>Posizione</h3>
                <div className="schema__scelte schema__scelte--riga">
                  {(SPOSTAMENTI_SLOT[standard[postoAperto.index]] ?? [standard[postoAperto.index]]).map((s) => (
                    <button key={s} type="button" className={s === slotAperto ? 'is-attiva' : ''}
                      onClick={() => scrivi(postoAperto.index, 'slot', s)}>{s}</button>
                  ))}
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
                  {COMPITI.map((c) => (
                    <button key={c} type="button"
                      className={(compiti?.[postoAperto.index] ?? 'equilibrio') === c ? 'is-attiva' : ''}
                      onClick={() => scrivi(postoAperto.index, 'compito', c === 'equilibrio' ? null : c)}>
                      <strong>{COMPITO_LABEL[c].nome}</strong><small>{COMPITO_LABEL[c].detto}</small>
                    </button>
                  ))}
                </div>
              </>
            )}
            {slotAperto === 'GK' && <p className="schema__vuoto">Il portiere non si sposta e non prende indicazioni.</p>}
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

const cognome = (nome: string) => {
  const parti = nome.trim().split(' ')
  return parti.length > 1 ? parti[parti.length - 1] : nome
}
