import { useCallback, useEffect, useRef, useState, type KeyboardEvent } from 'react'
import type { Session } from '@supabase/supabase-js'
import { supabase } from '../lib/supabase'
import { caricaLeghe, caricaQuadro, collega, type Evento, type Lega, type Quadro, type Squadra } from './dati'

// SpecialOne sui Ray-Ban Display: schermo fisso 600x600 senza scorrimento, comandi a frecce.
// Sinistra/destra cambiano schermata, su/giu' cambiano lega, Invio avvia la diretta.
const SCHERMATE = ['Prossima', 'Diretta', 'Classifica', 'Avvisi'] as const

function Stemma({ s, grande = false }: { s: Squadra; grande?: boolean }) {
  return s.stemma
    ? <img className={grande ? 'oc-stemma oc-stemma--grande' : 'oc-stemma'} src={s.stemma} alt="" />
    : <span className={grande ? 'oc-stemma oc-stemma--grande oc-stemma--sigla' : 'oc-stemma oc-stemma--sigla'}>{s.nome.slice(0, 2).toUpperCase()}</span>
}

function contoAllaRovescia(fino: string, adesso: number) {
  const ms = new Date(fino).getTime() - adesso
  if (ms <= 0) return 'in corso'
  const h = Math.floor(ms / 3_600_000), m = Math.floor((ms % 3_600_000) / 60_000), s = Math.floor((ms % 60_000) / 1000)
  return h > 0 ? `${h}h ${String(m).padStart(2, '0')}m` : `${m}:${String(s).padStart(2, '0')}`
}

export function Occhiali() {
  const [sessione, setSessione] = useState<Session | null | undefined>(undefined)
  useEffect(() => {
    void supabase.auth.getSession().then(({ data }) => setSessione(data.session))
    const { data } = supabase.auth.onAuthStateChange((_e, s) => setSessione(s))
    return () => data.subscription.unsubscribe()
  }, [])
  if (sessione === undefined) return <main className="oc"><p className="oc-centro">SpecialOne…</p></main>
  return sessione ? <Pannello /> : <Collegamento />
}

function Collegamento() {
  const [codice, setCodice] = useState('')
  const [errore, setErrore] = useState<string | null>(null)
  const [attesa, setAttesa] = useState(false)
  const campo = useRef<HTMLInputElement>(null)
  const bottone = useRef<HTMLButtonElement>(null)
  useEffect(() => { campo.current?.focus() }, [])
  async function invia() {
    if (codice.replace(/\D/g, '').length !== 6) { setErrore('Il codice ha 6 cifre.'); return }
    setAttesa(true); setErrore(null)
    const e = await collega(codice.replace(/\D/g, ''))
    setAttesa(false)
    if (e) setErrore(e)
  }
  const frecce = (e: KeyboardEvent) => {
    if (e.key === 'ArrowDown') { e.preventDefault(); bottone.current?.focus() }
    if (e.key === 'ArrowUp') { e.preventDefault(); campo.current?.focus() }
  }
  return <main className="oc oc-collega" onKeyDown={frecce}>
    <img className="oc-logo" src="/specialone-icon-192.png" alt="" />
    <h1>Collega gli occhiali</h1>
    <p>Sul telefono apri SpecialOne, menu, <b>Collega occhiali</b>, e scrivi qui il codice.</p>
    <input ref={campo} className="oc-focus oc-codice" type="text" inputMode="numeric" maxLength={6} placeholder="000000"
      value={codice} onChange={(e) => setCodice(e.target.value.replace(/\D/g, '').slice(0, 6))} aria-label="Codice di 6 cifre" />
    <button ref={bottone} className="oc-focus oc-bottone" type="button" onClick={() => void invia()} disabled={attesa}>{attesa ? 'Collego…' : 'Collega'}</button>
    {errore && <p className="oc-errore" role="alert">{errore}</p>}
  </main>
}

function Pannello() {
  const [leghe, setLeghe] = useState<Lega[]>([])
  const [iLega, setILega] = useState(0)
  const [schermata, setSchermata] = useState(0)
  const [quadro, setQuadro] = useState<Quadro | null>(null)
  const [adesso, setAdesso] = useState(Date.now())
  const [diretta, setDiretta] = useState<number | null>(null)   // minuto della diretta in riproduzione
  const radice = useRef<HTMLElement>(null)

  useEffect(() => { void caricaLeghe().then(setLeghe) }, [])
  const lega = leghe[iLega] ?? null
  const aggiorna = useCallback(() => { if (lega) void caricaQuadro(lega).then(setQuadro) }, [lega])
  useEffect(() => { setQuadro(null); setDiretta(null); aggiorna() }, [aggiorna])
  useEffect(() => {
    const t = window.setInterval(() => setAdesso(Date.now()), 1000)
    const r = window.setInterval(aggiorna, 60_000)
    return () => { window.clearInterval(t); window.clearInterval(r) }
  }, [aggiorna])
  useEffect(() => { radice.current?.focus() }, [leghe.length])

  // Diretta: un minuto di partita ogni 0,6 secondi (circa un minuto in tutto).
  useEffect(() => {
    if (diretta === null || diretta >= 90) return
    const t = window.setTimeout(() => setDiretta((m) => (m === null ? null : m + 1)), 600)
    return () => window.clearTimeout(t)
  }, [diretta])

  const tasti = (e: KeyboardEvent) => {
    if (e.key === 'ArrowRight') { e.preventDefault(); setSchermata((s) => (s + 1) % SCHERMATE.length) }
    else if (e.key === 'ArrowLeft') { e.preventDefault(); setSchermata((s) => (s + SCHERMATE.length - 1) % SCHERMATE.length) }
    else if (e.key === 'ArrowDown' && leghe.length > 1) { e.preventDefault(); setILega((i) => (i + 1) % leghe.length) }
    else if (e.key === 'ArrowUp' && leghe.length > 1) { e.preventDefault(); setILega((i) => (i + leghe.length - 1) % leghe.length) }
    else if (e.key === 'Enter' && SCHERMATE[schermata] === 'Diretta' && quadro?.ultima) {
      e.preventDefault(); setDiretta((m) => (m === null || m >= 90 ? 0 : null))
    } else if (e.key === 'Escape' && diretta !== null) { e.preventDefault(); setDiretta(null) }
  }

  if (!leghe.length) return <main className="oc"><p className="oc-centro">Nessuna squadra attiva.</p></main>
  return <main className="oc oc-focus" ref={radice} tabIndex={0} onKeyDown={tasti} aria-label="SpecialOne">
    <header className="oc-testa">
      <Stemma s={lega!.squadra} />
      <div className="oc-testa__nomi"><b>{lega!.squadra.nome}</b><small>{lega!.nome}{leghe.length > 1 ? ` · ${iLega + 1}/${leghe.length}` : ''}</small></div>
    </header>
    <nav className="oc-schede" aria-hidden="true">
      {SCHERMATE.map((n, i) => <span key={n} className={i === schermata ? 'is-attiva' : ''}>{n}</span>)}
    </nav>
    <section className="oc-corpo">
      {!quadro ? <p className="oc-centro">Carico…</p>
        : SCHERMATE[schermata] === 'Prossima' ? <Prossima quadro={quadro} adesso={adesso} />
        : SCHERMATE[schermata] === 'Diretta' ? <Diretta quadro={quadro} minuto={diretta} />
        : SCHERMATE[schermata] === 'Classifica' ? <Classifica quadro={quadro} />
        : <Avvisi quadro={quadro} />}
    </section>
    <footer className="oc-piede">◀ ▶ schermate{leghe.length > 1 ? ' · ▲ ▼ lega' : ''}{SCHERMATE[schermata] === 'Diretta' ? ' · Invio diretta' : ''}</footer>
  </main>
}

function Prossima({ quadro, adesso }: { quadro: Quadro; adesso: number }) {
  const p = quadro.prossima
  if (!p) return <p className="oc-centro">Nessuna partita in programma.</p>
  return <div className="oc-partita">
    <p className="oc-occhiello">Giornata {p.giornata} · ore 23:00</p>
    <div className="oc-sfida"><Stemma s={p.casa} grande /><span className="oc-vs">VS</span><Stemma s={p.ospite} grande /></div>
    <p className="oc-sfida__nomi"><span>{p.casa.nome}</span><span>{p.ospite.nome}</span></p>
    <p className="oc-grande">{contoAllaRovescia(p.dataSim, adesso)}</p>
    <p className={quadro.formazioneSalvata ? 'oc-stato oc-stato--ok' : 'oc-stato oc-stato--attenzione'}>
      {quadro.formazioneSalvata ? 'Formazione salvata' : 'Formazione da salvare'}
    </p>
  </div>
}

function Diretta({ quadro, minuto }: { quadro: Quadro; minuto: number | null }) {
  const u = quadro.ultima
  if (!u) return <p className="oc-centro">Nessuna partita giocata.</p>
  const fino = minuto ?? (u.svelata ? 90 : -1)
  const visti: Evento[] = u.eventi.filter((e) => e.minuto <= fino)
  const golC = visti.filter((e) => e.tipo === 'gol' && e.lato === 'casa').length
  const golO = visti.filter((e) => e.tipo === 'gol' && e.lato === 'ospite').length
  const nascosto = fino < 0
  return <div className="oc-partita">
    <p className="oc-occhiello">Giornata {u.giornata} · {minuto !== null ? (minuto >= 90 ? 'finale' : `${minuto}'`) : u.svelata ? 'finale' : 'da vedere'}</p>
    <div className="oc-sfida"><Stemma s={u.casa} grande />
      <span className="oc-punteggio">{nascosto ? '– : –' : `${golC} : ${golO}`}</span>
      <Stemma s={u.ospite} grande /></div>
    <p className="oc-sfida__nomi"><span>{u.casa.nome}</span><span>{u.ospite.nome}</span></p>
    {nascosto
      ? <p className="oc-stato">Premi Invio per guardarla in diretta</p>
      : <ul className="oc-eventi">
          {visti.slice(-3).reverse().map((e, i) => <li key={i} className={`oc-evento oc-evento--${e.tipo} oc-evento--${e.lato}`}>
            <b>{e.minuto}'</b><span>{e.tipo === 'gol' ? 'GOL' : e.tipo === 'giallo' ? 'Giallo' : 'Rosso'}</span><em>{e.testo}</em>
          </li>)}
          {visti.length === 0 && <li className="oc-evento"><em>Ancora niente…</em></li>}
        </ul>}
  </div>
}

function Classifica({ quadro }: { quadro: Quadro }) {
  return <div className="oc-classifica">
    {quadro.classifica.map((r) => <div key={r.posizione} className={r.mia ? 'oc-riga is-mia' : 'oc-riga'}>
      <b>{r.posizione}</b><span>{r.nome}</span><em>{r.punti} pt</em>
    </div>)}
    {quadro.ultima?.svelata && <p className="oc-stato">Ultima: {quadro.ultima.casa.nome} {quadro.ultima.golCasa}–{quadro.ultima.golOspite} {quadro.ultima.ospite.nome}</p>}
  </div>
}

function Avvisi({ quadro }: { quadro: Quadro }) {
  if (!quadro.notifiche.length) return <p className="oc-centro">Nessun avviso.</p>
  return <ul className="oc-avvisi">
    {quadro.notifiche.map((n, i) => <li key={i} className={n.letta ? '' : 'is-nuova'}><b>{n.titolo}</b>{n.corpo && <span>{n.corpo}</span>}</li>)}
  </ul>
}
