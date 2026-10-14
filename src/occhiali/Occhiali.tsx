import { useCallback, useEffect, useRef, useState, type KeyboardEvent } from 'react'
import type { Session } from '@supabase/supabase-js'
import { supabase } from '../lib/supabase'
import { caricaLeghe, caricaQuadro, collega, type Evento, type Lega, type Quadro, type Squadra } from './dati'
import { DirettaLive } from './DirettaLive'

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
    {/* Niente maxLength: sugli occhiali il compositore si fermava a 5 cifre. Le cifre in piu' si tagliano qui. */}
    <input ref={campo} className="oc-focus oc-codice" type="text" inputMode="numeric" autoComplete="one-time-code" placeholder="000000"
      value={codice} onChange={(e) => setCodice(e.target.value.replace(/\D/g, '').slice(0, 6))}
      onKeyDown={(e) => { if (e.key === 'Enter' && codice.length === 6) { e.preventDefault(); void invia() } }} aria-label="Codice di 6 cifre" />
    <p className="oc-cifre" aria-hidden="true">{codice.length}/6 cifre</p>
    <button ref={bottone} className="oc-focus oc-bottone" type="button" onClick={() => void invia()} disabled={attesa}>{attesa ? 'Collego…' : 'Collega'}</button>
    {errore && <p className="oc-errore" role="alert">{errore}</p>}
  </main>
}

// Prima si sceglie la lega, poi si entra nel suo pannello. Esc dal pannello torna qui.
const CHIAVE_LEGA = 'occhiali-lega'
function Pannello() {
  const [leghe, setLeghe] = useState<Lega[] | null>(null)
  const [scelta, setScelta] = useState<Lega | null>(null)
  useEffect(() => { void caricaLeghe().then(setLeghe) }, [])
  if (!leghe) return <main className="oc"><p className="oc-centro">SpecialOne…</p></main>
  if (!leghe.length) return <main className="oc"><p className="oc-centro">Nessuna squadra attiva.</p></main>
  if (scelta) return <PannelloLega lega={scelta} onIndietro={() => setScelta(null)} />
  return <SceltaLega leghe={leghe} onScegli={(l) => { try { localStorage.setItem(CHIAVE_LEGA, String(l.id)) } catch { /* niente */ } setScelta(l) }} />
}

function SceltaLega({ leghe, onScegli }: { leghe: Lega[]; onScegli: (l: Lega) => void }) {
  const ultima = (() => { try { return Number(localStorage.getItem(CHIAVE_LEGA)) } catch { return 0 } })()
  const iniziale = Math.max(0, leghe.findIndex((l) => l.id === ultima))
  const bottoni = useRef<(HTMLButtonElement | null)[]>([])
  useEffect(() => { bottoni.current[iniziale]?.focus() }, [iniziale])
  const frecce = (e: KeyboardEvent, i: number) => {
    if (e.key === 'ArrowDown') { e.preventDefault(); bottoni.current[(i + 1) % leghe.length]?.focus() }
    if (e.key === 'ArrowUp') { e.preventDefault(); bottoni.current[(i + leghe.length - 1) % leghe.length]?.focus() }
  }
  return <main className="oc oc-leghe">
    <header className="oc-leghe__testa"><img src="/specialone-icon-192.png" alt="" /><h1>Scegli la lega</h1></header>
    <div className="oc-leghe__lista">
      {leghe.map((l, i) => <button key={l.id} ref={(el) => { bottoni.current[i] = el }} type="button"
        className={`oc-focus oc-lega${l.inCorso ? '' : ' is-ferma'}`} onClick={() => onScegli(l)} onKeyDown={(e) => frecce(e, i)}>
        <Stemma s={l.squadra} />
        <span className="oc-lega__nomi"><b>{l.nome}</b><small>{l.squadra.nome}</small></span>
        <em>{l.inCorso ? 'In corso' : 'Ferma'}</em>
      </button>)}
    </div>
    <footer className="oc-piede">▲ ▼ scegli · Invio entra</footer>
  </main>
}

function PannelloLega({ lega, onIndietro }: { lega: Lega; onIndietro: () => void }) {
  const [schermata, setSchermata] = useState(0)
  const [quadro, setQuadro] = useState<Quadro | null>(null)
  const [adesso, setAdesso] = useState(Date.now())
  const [live, setLive] = useState(false)   // diretta a tutto schermo
  const [automatica, setAutomatica] = useState(false)   // la diretta e' partita da sola (alle 23:00)
  // Diretta automatica, solo per questa lega: l'ultima partita gia' nota all'apertura; se dalle 23:00 ne
  // compare una nuova non ancora vista, la diretta parte da sola.
  const nota = useRef<number | null | undefined>(undefined)
  const radice = useRef<HTMLElement>(null)

  const aggiorna = useCallback(() => { void caricaQuadro(lega).then((q) => {
    if (nota.current === undefined) nota.current = q.ultima?.fixtureId ?? null
    setQuadro(q)
  }) }, [lega])
  useEffect(() => { aggiorna() }, [aggiorna])
  useEffect(() => {
    const t = window.setInterval(() => setAdesso(Date.now()), 1000)
    const r = window.setInterval(aggiorna, 60_000)
    return () => { window.clearInterval(t); window.clearInterval(r) }
  }, [aggiorna])
  useEffect(() => { if (!live) radice.current?.focus() }, [live, quadro === null])

  // Dalle 23:00 alle 23:59 (ora di Roma) controlla ogni 30 secondi se la partita di stasera e' uscita.
  useEffect(() => {
    const controlla = async () => {
      const ora = Number(new Intl.DateTimeFormat('it-IT', { hour: 'numeric', hourCycle: 'h23', timeZone: 'Europe/Rome' }).format(new Date()))
      // Solo in sviluppo: ?prova23 finge che siano le 23 (per provare la diretta automatica).
      const prova = import.meta.env.DEV && new URLSearchParams(window.location.search).has('prova23')
      if ((ora !== 23 && !prova) || nota.current === undefined || live) return
      const q = await caricaQuadro(lega)
      const id = q.ultima?.fixtureId ?? null
      if (id === null || id === nota.current) return
      nota.current = id
      setQuadro(q)
      if (!q.ultima?.svelata) { setSchermata(1); setAutomatica(true); setLive(true) }
    }
    const t = window.setInterval(() => void controlla(), 30_000)
    return () => window.clearInterval(t)
  }, [lega, live])

  const tasti = (e: KeyboardEvent) => {
    if (e.key === 'ArrowRight') { e.preventDefault(); setSchermata((s) => (s + 1) % SCHERMATE.length) }
    else if (e.key === 'ArrowLeft') { e.preventDefault(); setSchermata((s) => (s + SCHERMATE.length - 1) % SCHERMATE.length) }
    else if (e.key === 'Escape') { e.preventDefault(); onIndietro() }
    else if (e.key === 'Enter' && SCHERMATE[schermata] === 'Diretta' && quadro?.ultima) { e.preventDefault(); setLive(true) }
  }

  if (live && quadro?.ultima) return <DirettaLive partita={quadro.ultima} automatica={automatica}
    onEsci={() => { setLive(false); setAutomatica(false); aggiorna() }} />
  return <main className="oc oc-focus" ref={radice} tabIndex={0} onKeyDown={tasti} aria-label="SpecialOne">
    <header className="oc-testa">
      <Stemma s={lega.squadra} />
      <div className="oc-testa__nomi"><b>{lega.squadra.nome}</b><small>{lega.nome}</small></div>
    </header>
    <nav className="oc-schede" aria-hidden="true">
      {SCHERMATE.map((n, i) => <span key={n} className={i === schermata ? 'is-attiva' : ''}>{n}</span>)}
    </nav>
    <section className="oc-corpo">
      {!quadro ? <p className="oc-centro">Carico…</p>
        : SCHERMATE[schermata] === 'Prossima' ? <Prossima quadro={quadro} adesso={adesso} />
        : SCHERMATE[schermata] === 'Diretta' ? <Diretta quadro={quadro} />
        : SCHERMATE[schermata] === 'Classifica' ? <Classifica quadro={quadro} />
        : <Avvisi quadro={quadro} />}
    </section>
    <footer className="oc-piede">◀ ▶ schermate · Esc leghe{SCHERMATE[schermata] === 'Diretta' ? ' · Invio diretta' : ''}</footer>
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

function Diretta({ quadro }: { quadro: Quadro }) {
  const u = quadro.ultima
  if (!u) return <p className="oc-centro">Nessuna partita giocata.</p>
  const ultimi: Evento[] = u.eventi.filter((e) => e.tipo === 'gol').slice(-3).reverse()
  return <div className="oc-partita">
    <p className="oc-occhiello">Giornata {u.giornata} · {u.svelata ? 'finale' : 'da vedere'}</p>
    <div className="oc-sfida"><Stemma s={u.casa} grande />
      <span className="oc-punteggio">{u.svelata ? `${u.golCasa} : ${u.golOspite}` : '– : –'}</span>
      <Stemma s={u.ospite} grande /></div>
    <p className="oc-sfida__nomi"><span>{u.casa.nome}</span><span>{u.ospite.nome}</span></p>
    {u.svelata && ultimi.length > 0 && <ul className="oc-eventi">
      {ultimi.map((e, i) => <li key={i} className={`oc-evento oc-evento--gol oc-evento--${e.lato}`}><b>{e.minuto}'</b><span>GOL</span><em>{e.testo}</em></li>)}
    </ul>}
    <p className="oc-stato oc-stato--invito">Invio: {u.svelata ? 'rivedi la diretta' : 'guardala in diretta'}</p>
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
