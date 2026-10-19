import { useCallback, useEffect, useState, type ReactNode } from 'react'
import { supabase } from '../lib/supabase'
import { firmaFoto } from './RosaElenco'
import { ruoloIt } from '../lib/ruoli'

// Le richieste dei giocatori (docs/decisioni-conferenze-stampa.md §2e): un giocatore scrive al mister,
// l'allenatore risponde a testo libero, l'AI valuta l'effetto sul morale di quel giocatore e registra
// l'eventuale promessa, che si verifica a fine partita.

type Richiesta = {
  id: number
  player_instance_id: number
  tipo: 'titolare' | 'spazio' | 'riposo'
  testo: string
  giornata_target: number
  creata_il: string
  scade_il: string
  stato: 'aperta' | 'risposta' | 'promessa' | 'mantenuta' | 'tradita' | 'decaduta' | 'scaduta'
  risposta: string | null
  reazione: string | null
  effetto_morale: number | null
  esito_morale: number | null
}
type Giocatore = { nome: string; ruolo: string; foto?: string }

const MAX = 1200
const CHIEDE: Record<Richiesta['tipo'], string> = {
  titolare: 'Chiede di giocare titolare', spazio: 'Chiede più minuti', riposo: 'Chiede di riposare',
}
const PROMESSA: Record<Richiesta['tipo'], string> = {
  titolare: 'titolare nella prossima partita', spazio: 'almeno mezz\'ora nella prossima partita', riposo: 'a riposo nella prossima partita',
}
const numero = (n: number) => `${n > 0 ? '+' : n < 0 ? '−' : ''}${Math.abs(n).toFixed(0)}`

async function messaggioErrore(errore: unknown) {
  const contesto = (errore as { context?: Response })?.context
  try { const corpo = await contesto?.json(); if (corpo?.errore) return String(corpo.errore) } catch { /* corpo non JSON */ }
  return 'Il giocatore non risponde, riprova tra poco.'
}

export function RichiesteGiocatori({ teamId, onCambio, senzaTitolo = false, quandoVuota = null }: { teamId: number; onCambio?: () => void; senzaTitolo?: boolean; quandoVuota?: ReactNode }) {
  const [richieste, setRichieste] = useState<Richiesta[]>([])
  const [giocatori, setGiocatori] = useState<Map<number, Giocatore>>(new Map())
  const [bozze, setBozze] = useState<Record<number, string>>({})
  const [invio, setInvio] = useState<number | null>(null)
  const [errori, setErrori] = useState<Record<number, string>>({})

  const carica = useCallback(async () => {
    const tre = new Date(Date.now() - 3 * 86_400_000).toISOString()
    const { data } = await supabase.from('richieste_giocatori')
      .select('id, player_instance_id, tipo, testo, giornata_target, creata_il, scade_il, stato, risposta, reazione, effetto_morale, esito_morale')
      .eq('team_id', teamId).gte('creata_il', tre).order('id', { ascending: false }).limit(3)
    const righe = (data ?? []) as Richiesta[]
    setRichieste(righe)
    const ids = [...new Set(righe.map((r) => r.player_instance_id))].filter((id) => !giocatori.has(id))
    if (!ids.length) return
    // Il ruolo vero: quello dopo un eventuale cambio ruolo (posizioni_override), non quello del catalogo.
    const { data: istanze } = await supabase.from('player_instances').select('id, player_id, posizioni_override').in('id', ids)
    const playerIds = [...new Set((istanze ?? []).map((i) => i.player_id))]
    const { data: players } = playerIds.length ? await supabase.from('players').select('id, nome, foto_url, posizioni').in('id', playerIds) : { data: [] }
    const firmate = await Promise.all((players ?? []).map(async (p) => [p.id, { nome: p.nome as string, ruolo: ((p.posizioni ?? [])[0] ?? '') as string, foto: await firmaFoto(p.foto_url) }] as const))
    const perPlayer = new Map(firmate)
    setGiocatori((prima) => {
      const nuovo = new Map(prima)
      for (const i of istanze ?? []) {
        const g = perPlayer.get(i.player_id)
        const override = (i as { posizioni_override?: string[] | null }).posizioni_override
        if (g) nuovo.set(i.id, { ...g, ruolo: override?.[0] ?? g.ruolo })
      }
      return nuovo
    })
  }, [teamId, giocatori])

  useEffect(() => { void carica() }, [teamId]) // eslint-disable-line react-hooks/exhaustive-deps
  if (!richieste.length) return <>{quandoVuota}</>

  async function rispondi(r: Richiesta) {
    const testo = (bozze[r.id] ?? '').trim()
    if (!testo) return
    setInvio(r.id)
    setErrori((e) => ({ ...e, [r.id]: '' }))
    const { error } = await supabase.functions.invoke('conferenza-stampa', { body: { azione: 'rispondi_richiesta', richiesta_id: r.id, risposta: testo } })
    if (error) { const msg = await messaggioErrore(error); setErrori((e) => ({ ...e, [r.id]: msg })) }
    setInvio(null)
    await carica()
    onCambio?.()
  }

  return <section className="dash-sezione">
    {!senzaTitolo && <header className="dash-testa"><h2 className="dash-linguetta">Spogliatoio</h2></header>}
    <div className="dash-card richieste">
      {richieste.map((r) => {
        const g = giocatori.get(r.player_instance_id)
        const aperta = r.stato === 'aperta' && new Date(r.scade_il).getTime() > Date.now()
        const bozza = bozze[r.id] ?? ''
        return <article className="richiesta" key={r.id}>
          <header className="richiesta__testa">
            <span className="richiesta__foto">{g?.foto ? <img src={g.foto} alt="" loading="lazy" /> : <b>{(g?.nome ?? '?').charAt(0)}</b>}</span>
            <span><strong>{g?.nome ?? 'Giocatore'}</strong><small>{ruoloIt(g?.ruolo)} · {CHIEDE[r.tipo]}</small></span>
          </header>
          <p className="richiesta__messaggio">{r.testo}</p>
          {aperta
            ? <div className="richiesta__form">
              <textarea value={bozza} maxLength={MAX} rows={3} placeholder="Rispondi al giocatore…" disabled={invio === r.id}
                onChange={(e) => setBozze((b) => ({ ...b, [r.id]: e.target.value }))} />
              <div className="richiesta__azioni">
                <span>{bozza.length}/{MAX}</span>
                <button className="overview-cta-button" type="button" disabled={!bozza.trim() || invio !== null} onClick={() => void rispondi(r)}>
                  {invio === r.id ? 'Invio…' : 'Rispondi'}
                </button>
              </div>
              <p className="richiesta__nota">Se prometti qualcosa, ricorda che a fine partita si controlla.</p>
              {errori[r.id] && <p className="richiesta__errore" role="alert">{errori[r.id]}</p>}
            </div>
            : <>
              {r.risposta && <blockquote className="richiesta__risposta">{r.risposta}</blockquote>}
              {r.reazione && <p className="richiesta__reazione"><b>{g?.nome ?? 'Il giocatore'}</b>{r.reazione}{r.effetto_morale != null && <em>Morale {numero(Number(r.effetto_morale))}</em>}</p>}
              {r.stato === 'promessa' && <p className="richiesta__esito is-promessa">Promessa registrata: {PROMESSA[r.tipo]} (giornata {r.giornata_target}). Se non la mantieni, perderà molto morale.</p>}
              {r.stato === 'mantenuta' && <p className="richiesta__esito is-ok">Promessa mantenuta: morale {numero(Number(r.esito_morale ?? 8))}.</p>}
              {r.stato === 'tradita' && <p className="richiesta__esito is-no">Promessa non mantenuta: morale {numero(Number(r.esito_morale ?? -20))}. Si è sfogato sui social.</p>}
              {r.stato === 'decaduta' && <p className="richiesta__esito">Promessa decaduta: non era disponibile.</p>}
              {r.stato === 'scaduta' && <p className="richiesta__esito">Nessuna risposta: la richiesta è scaduta.</p>}
            </>}
        </article>
      })}
    </div>
  </section>
}
