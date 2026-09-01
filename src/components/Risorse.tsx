import { useCallback, useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'
import type { Membership } from '../types'
import { GameNav, type GameView } from './GameNav'

type Props = { membership: Membership; onNavigate: (view: GameView) => void }

type Ramo = 'vivaio' | 'training' | 'medico'
type Risorse = {
  team_id: number
  punti_ricevuti: number
  livello_vivaio: number
  livello_training: number
  livello_medico: number
}
// Ogni voce e' l'effetto del ramo a un dato livello, cosi' come lo calcola
// private.effetti_ramo: la curva sta nel database, qui si legge soltanto.
type EffettiLivello = Record<string, number>
type Tabella = {
  punti_per_checkpoint: number
  punti_massimi: number
  livello_massimo: number
  rami: Record<Ramo, EffettiLivello[]>
}

const RAMI: readonly { id: Ramo; nome: string; occhiello: string; descrizione: string }[] = [
  {
    id: 'vivaio',
    nome: 'Vivaio',
    occhiello: 'Settore giovanile',
    descrizione: 'Quanti giovani puoi tenere in cantiera e quanto vedi chiaramente il loro potenziale nel mercato UNDER.',
  },
  {
    id: 'training',
    nome: 'Training',
    occhiello: 'Allenamento',
    descrizione: 'Quanto in fretta crescono i tuoi giocatori e quanto tempo serve per riqualificarne uno su un altro ruolo.',
  },
  {
    id: 'medico',
    nome: 'Reparto medico',
    occhiello: 'Staff sanitario',
    descrizione: 'Quanto resistono i tuoi giocatori agli infortuni e quanto lentamente consumano energia in partita.',
  },
]

// Come si legge a schermo un effetto: etichetta e formato del valore. Le
// chiavi sono quelle prodotte da private.effetti_ramo.
const ETICHETTE: Record<string, { testo: string; formato: (v: number) => string }> = {
  slot: { testo: 'Slot vivaio', formato: (v) => `${v}` },
  ampiezza_range: {
    testo: 'Incertezza sul potenziale',
    formato: (v) => (v === 0 ? 'valore esatto' : `± ${Math.round(v / 2)} punti`),
  },
  moltiplicatore_crescita: { testo: 'Crescita giocatori', formato: (v) => `×${v.toFixed(2)}` },
  riduzione_tempi_ruolo_pct: { testo: 'Tempi cambio ruolo', formato: (v) => (v === 0 ? 'pieni' : `−${v}%`) },
  riduzione_infortuni_pct: { testo: 'Rischio infortuni', formato: (v) => (v === 0 ? 'pieno' : `−${v}%`) },
  riduzione_consumo_pct: { testo: 'Consumo di energia', formato: (v) => (v === 0 ? 'pieno' : `−${v}%`) },
}

function livelloDi(risorse: Risorse, ramo: Ramo) {
  return ramo === 'vivaio' ? risorse.livello_vivaio
    : ramo === 'training' ? risorse.livello_training
    : risorse.livello_medico
}

export function Risorse({ membership, onNavigate }: Props) {
  const league = membership.league!
  const [risorse, setRisorse] = useState<Risorse | null>(null)
  const [tabella, setTabella] = useState<Tabella | null>(null)
  const [caricamento, setCaricamento] = useState(true)
  const [errore, setErrore] = useState<string | null>(null)
  const [ramoInCorso, setRamoInCorso] = useState<Ramo | null>(null)

  const carica = useCallback(async () => {
    const [statoResult, tabellaResult] = await Promise.all([
      supabase.from('team_risorse')
        .select('team_id, punti_ricevuti, livello_vivaio, livello_training, livello_medico')
        .eq('team_id', membership.id).maybeSingle(),
      supabase.rpc('tabella_risorse'),
    ])
    if (statoResult.error) { setErrore(statoResult.error.message); setCaricamento(false); return }
    if (tabellaResult.error) { setErrore(tabellaResult.error.message); setCaricamento(false); return }
    // Una squadra creata prima di questa funzionalita' puo' non avere ancora
    // la riga: si mostra come "tutto a zero" invece che come errore, la riga
    // vera nasce al primo punto assegnato o alla prima spesa.
    setRisorse((statoResult.data as Risorse | null) ?? {
      team_id: membership.id, punti_ricevuti: 0,
      livello_vivaio: 0, livello_training: 0, livello_medico: 0,
    })
    setTabella(tabellaResult.data as Tabella)
    setCaricamento(false)
  }, [membership.id])

  useEffect(() => { void carica() }, [carica])

  async function spendi(ramo: Ramo) {
    setRamoInCorso(ramo); setErrore(null)
    const { data, error } = await supabase.rpc('spendi_punto_abilita', {
      p_team_id: membership.id,
      p_ramo: ramo,
    })
    setRamoInCorso(null)
    if (error) { setErrore(error.message); return }
    setRisorse(data as Risorse)
  }

  if (caricamento || !risorse || !tabella) {
    return <main className="app-shell season-shell">
      <GameNav league={league} active="risorse" onNavigate={onNavigate} />
      <div className="season-page season-page--narrow"><p className="season-empty">Carico le risorse…</p></div>
    </main>
  }

  const spesi = risorse.livello_vivaio + risorse.livello_training + risorse.livello_medico
  const disponibili = risorse.punti_ricevuti - spesi
  const esauriti = risorse.punti_ricevuti >= tabella.punti_massimi

  return <main className="app-shell season-shell">
    <GameNav league={league} active="risorse" onNavigate={onNavigate} />
    <header className="topbar season-topbar">
      <div className="brand-lockup brand-lockup--dark"><img src="/specialone-mark.svg" alt="" /><span>SpecialOne</span></div>
      <span>Risorse</span>
    </header>

    <div className="season-page season-page--narrow risorse-page">
      <section className="season-title-row">
        <div>
          <p className="kicker">{league.nome}</p>
          <h1>Gestione risorse.</h1>
          <p>
            Ogni quarto di stagione ricevi {tabella.punti_per_checkpoint} punti abilità, fino a un
            massimo di {tabella.punti_massimi} in tutta la vita della lega. I rami hanno{' '}
            {tabella.livello_massimo} livelli ciascuno, {tabella.livello_massimo * RAMI.length} in
            totale: non potrai mai riempirli tutti, quindi la scelta conta.
          </p>
        </div>
        <div className="risorse-punti">
          <strong>{disponibili}</strong>
          <span>{disponibili === 1 ? 'punto da spendere' : 'punti da spendere'}</span>
          <small>{risorse.punti_ricevuti} / {tabella.punti_massimi} ricevuti{esauriti ? ' · esauriti' : ''}</small>
        </div>
      </section>

      {errore && <p className="notice notice--error">{errore}</p>}

      <div className="risorse-rami">
        {RAMI.map((ramo) => {
          const livello = livelloDi(risorse, ramo.id)
          const scala = tabella.rami[ramo.id]
          const ora = scala[livello]
          const dopo = livello < tabella.livello_massimo ? scala[livello + 1] : null
          const alMassimo = livello >= tabella.livello_massimo
          const chiavi = Object.keys(ora).filter((chiave) => chiave !== 'livello')
          return (
            <article className="risorse-ramo" key={ramo.id}>
              <header>
                <div>
                  <p className="kicker">{ramo.occhiello}</p>
                  <h2>{ramo.nome}</h2>
                </div>
                <b className={alMassimo ? 'is-massimo' : ''}>{livello}<i>/{tabella.livello_massimo}</i></b>
              </header>

              <div className="risorse-scala" role="img" aria-label={`Livello ${livello} su ${tabella.livello_massimo}`}>
                {Array.from({ length: tabella.livello_massimo }, (_, i) => (
                  <span className={i < livello ? 'is-attivo' : ''} key={i} />
                ))}
              </div>

              <p className="risorse-ramo__descrizione">{ramo.descrizione}</p>

              <dl className="risorse-effetti">
                {chiavi.map((chiave) => {
                  const etichetta = ETICHETTE[chiave]
                  if (!etichetta) return null
                  const valoreOra = etichetta.formato(ora[chiave])
                  const valoreDopo = dopo ? etichetta.formato(dopo[chiave]) : null
                  const migliora = valoreDopo !== null && valoreDopo !== valoreOra
                  return (
                    <div key={chiave}>
                      <dt>{etichetta.testo}</dt>
                      <dd>
                        <strong>{valoreOra}</strong>
                        {migliora && <em>→ {valoreDopo}</em>}
                      </dd>
                    </div>
                  )
                })}
              </dl>

              <button
                className="button button--primary"
                type="button"
                disabled={alMassimo || disponibili <= 0 || ramoInCorso !== null}
                onClick={() => void spendi(ramo.id)}
              >
                {ramoInCorso === ramo.id ? 'Assegno…'
                  : alMassimo ? 'Al massimo'
                  : disponibili <= 0 ? 'Nessun punto'
                  : `Investi 1 punto → livello ${livello + 1}`}
              </button>
            </article>
          )
        })}
      </div>

      <p className="risorse-nota">
        I punti investiti non si possono riassegnare: una volta messi su un ramo restano lì.
        {esauriti
          ? ' Hai già ricevuto tutti i punti che la lega distribuisce: quelli che hai adesso sono definitivi.'
          : ' I prossimi arrivano al quarto di stagione successivo.'}
      </p>
    </div>
  </main>
}
