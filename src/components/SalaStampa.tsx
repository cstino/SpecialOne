import { useCallback, useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'

// Conferenze stampa post partita (docs/decisioni-conferenze-stampa.md, fase 1).
// Le domande della propria ultima partita, una risposta per domanda; la
// valutazione e l'effetto sul morale arrivano dalla Edge Function.

type Domanda = {
  id: number
  match_id: number
  ordine: number
  giornalista: string
  domanda: string
  scade_il: string
  risposta: string | null
  voto: number | null
  reazione: string | null
  effetto_morale: number | null
  effetto_pubblico: number | null
  reazione_pubblico: string | null
}

const MAX = 1200

function giudizio(voto: number) {
  if (voto >= 1) return { testo: 'Conferenza da leader', tono: 'ottima' }
  if (voto >= 0.5) return { testo: 'Parole convincenti', tono: 'buona' }
  if (voto > -0.5) return { testo: 'Risposta di routine', tono: 'neutra' }
  if (voto > -2) return { testo: 'Parole poco convincenti', tono: 'scarsa' }
  return { testo: 'Conferenza da dimenticare', tono: 'pessima' }
}

const numero = (n: number) => `${n > 0 ? '+' : ''}${n.toFixed(1).replace('.', ',')}`

async function messaggioErrore(errore: unknown) {
  const contesto = (errore as { context?: Response })?.context
  try { const corpo = await contesto?.json(); if (corpo?.errore) return String(corpo.errore) } catch { /* corpo non JSON */ }
  return 'La sala stampa non risponde, riprova tra poco.'
}

export function SalaStampa({ teamId, revealedMatchIds }: { teamId: number; revealedMatchIds: Set<number> }) {
  const [domande, setDomande] = useState<Domanda[]>([])
  const [bozze, setBozze] = useState<Record<number, string>>({})
  const [invio, setInvio] = useState<number | null>(null)
  const [errori, setErrori] = useState<Record<number, string>>({})

  const carica = useCallback(async () => {
    const tre = new Date(Date.now() - 3 * 86_400_000).toISOString()
    const { data } = await supabase.from('conferenze_domande')
      .select('id, match_id, ordine, giornalista, domanda, scade_il, risposta, voto, reazione, effetto_morale, effetto_pubblico, reazione_pubblico')
      .eq('team_id', teamId).gte('creata_il', tre)
      .order('match_id', { ascending: false }).order('ordine')
    setDomande((data ?? []) as Domanda[])
  }, [teamId])

  useEffect(() => { void carica() }, [carica])

  // Solo l'ultima partita con domande: le conferenze vecchie non servono qui.
  const ultimaPartita = domande[0]?.match_id
  const correnti = domande.filter((d) => d.match_id === ultimaPartita)
  if (!correnti.length) return null
  const vista = revealedMatchIds.has(ultimaPartita)

  async function rispondi(d: Domanda) {
    const testo = (bozze[d.id] ?? '').trim()
    if (!testo) return
    setInvio(d.id)
    setErrori((e) => ({ ...e, [d.id]: '' }))
    const { error } = await supabase.functions.invoke('conferenza-stampa', { body: { azione: 'rispondi', domanda_id: d.id, risposta: testo } })
    if (error) {
      const msg = await messaggioErrore(error)
      setErrori((e) => ({ ...e, [d.id]: msg }))
    }
    setInvio(null)
    await carica()
  }

  return <section className="dash-sezione">
    <header className="dash-testa"><h2 className="dash-linguetta">Sala stampa</h2></header>
    <div className="dash-card stampa">
      {!vista
        ? <p className="stampa__attesa">I giornalisti ti aspettano dopo la partita: guardala prima, poi passa in sala stampa.</p>
        : correnti.map((d) => {
          const scaduta = new Date(d.scade_il).getTime() < Date.now()
          const g = d.voto != null ? giudizio(Number(d.voto)) : null
          const bozza = bozze[d.id] ?? ''
          return <article className="stampa__voce" key={d.id}>
            <p className="stampa__testata"><Microfono />{d.giornalista}</p>
            <p className="stampa__domanda">{d.domanda}</p>
            {d.risposta
              ? <>
                <blockquote className="stampa__risposta">{d.risposta}</blockquote>
                {g && <div className={`stampa__esito is-${g.tono}`}>
                  <strong>{g.testo}</strong>
                  {d.reazione && <span>{d.reazione}</span>}
                  {d.effetto_morale != null && <em>Morale della rosa {numero(Number(d.effetto_morale))}</em>}
                  {d.effetto_pubblico != null && <em>Pubblico {numero(Number(d.effetto_pubblico))}</em>}
                </div>}
                {g && d.reazione_pubblico && <p className={`stampa__tifoso${Number(d.effetto_pubblico ?? 0) < 0 ? ' is-protesta' : ''}`}><b>Dai tifosi</b>{d.reazione_pubblico}</p>}
                {!g && <p className="stampa__attesa">La sala stampa sta ascoltando…</p>}
              </>
              : scaduta
                ? <p className="stampa__nocomment">Nessuna risposta: «no comment».</p>
                : <div className="stampa__form">
                  <textarea
                    value={bozza}
                    maxLength={MAX}
                    rows={3}
                    placeholder="Rispondi al giornalista…"
                    disabled={invio === d.id}
                    onChange={(e) => setBozze((b) => ({ ...b, [d.id]: e.target.value }))}
                  />
                  <div className="stampa__azioni">
                    <span>{bozza.length}/{MAX}</span>
                    <button className="overview-cta-button" type="button" disabled={!bozza.trim() || invio !== null} onClick={() => void rispondi(d)}>
                      {invio === d.id ? 'La sala ascolta…' : 'Rispondi'}
                    </button>
                  </div>
                  {errori[d.id] && <p className="stampa__errore" role="alert">{errori[d.id]}</p>}
                </div>}
          </article>
        })}
    </div>
  </section>
}

function Microfono() {
  return <svg viewBox="0 0 16 16" width="14" height="14" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" aria-hidden="true">
    <rect x="5.5" y="1.8" width="5" height="8" rx="2.5" /><path d="M3.5 8a4.5 4.5 0 0 0 9 0M8 12.5v2" />
  </svg>
}
