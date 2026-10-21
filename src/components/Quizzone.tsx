import { useCallback, useEffect, useRef, useState } from 'react'
import { supabase } from '../lib/supabase'
import type { League, Membership } from '../types'
import { Contatore, Festa, fmt, useSuoni } from './Casino'
import { Crest } from './Crest'
import { GameNav, type GameView } from './GameNav'
import { useSeasonData } from '../lib/useSeasonData'

// QUIZONE, scritto QuizOne (internamente "quizzone": supabase/migrations/20261020280000_quizzone.sql): una domanda ogni ora piena, uguale per tutti.
// :00-:10 si entra (gratis o puntando 10-500), :10-:25 domanda con 4 risposte, poi risultato. Risposta giusta = premio fisso (100, dal 22/10/2026 250) + 2x puntata; alle 22:30 il primo del giorno vince 500
// crediti, piu' il doppio della puntata. Le domande e le risposte giuste le decide il server dai dati della stagione.

type Dati = ReturnType<typeof useSeasonData>
type Domanda = { id: number; ora: number; regolata: boolean; testo: string | null; risposte: string[] | null; corretta: number | null; giocatori: number; esiti: Array<{ team_id: number; corretta: boolean | null; puntata: number; vinto: number }> | null }
type Mia = { puntata: number; risposta: number | null; corretta: boolean | null; vinto: number }
type Stato = { adesso: number; crediti: number; prossima: number; domanda: Domanda | null; mia: Mia | null; oggi: Array<{ ora: number; testo: string; risposta: string }>; classifica: RigaClassifica[]; classifica_totale?: RigaClassifica[]; premio?: number; vincitori?: Array<{ team_id: number; giuste: number; crediti: number }> }
type RigaClassifica = { team_id: number; giuste: number; giocate: number; vinto: number }
const MIN_WIN_RATE = 5   // domande giocate per entrare nella classifica del win rate

const PUNTATE = [10, 50, 100, 250, 500]
let scarto = 0
const ora = () => Date.now() + scarto
const hh = (ms: number) => new Intl.DateTimeFormat('it-IT', { hour: '2-digit', minute: '2-digit', timeZone: 'Europe/Rome' }).format(ms)
const mmss = (ms: number) => { const s = Math.max(0, Math.ceil(ms / 1000)); return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}` }

function Anello({ resto, totale }: { resto: number; totale: number }) {
  const k = Math.max(0, Math.min(1, resto / totale))
  return <div className="qz-anello" style={{ ['--k' as string]: k }} aria-label={`${Math.ceil(resto / 1000)} secondi`}>
    <svg viewBox="0 0 100 100" aria-hidden="true"><circle cx="50" cy="50" r="44" className="qz-anello__fondo" /><circle cx="50" cy="50" r="44" className="qz-anello__arco" pathLength="100" strokeDasharray={`${k * 100} 100`} /></svg>
    <b>{Math.max(0, Math.ceil(resto / 1000))}</b>
  </div>
}

export function Quizzone({ leagueId, dati }: { leagueId: number; dati: Dati }) {
  const [st, setSt] = useState<Stato | null>(null)
  const [puntata, setPuntata] = useState(50)
  const [errore, setErrore] = useState('')
  const [invio, setInvio] = useState(false)
  const [festa, setFesta] = useState(0)
  const [scheda, setScheda] = useState<'oggi' | 'totale' | 'winrate'>('oggi')
  const [, setTic] = useState(0)
  const [audio, setAudio] = useState(() => { try { return localStorage.getItem('slot-audio') !== '0' } catch { return true } })
  const suoni = useSuoni(audio)
  const suoniRef = useRef(suoni); suoniRef.current = suoni
  const visto = useRef<number | null>(null)
  const inAttesa = useRef(false)

  useEffect(() => { try { localStorage.setItem('slot-audio', audio ? '1' : '0') } catch { /* preferenza solo locale */ } }, [audio])

  const chiedi = useCallback(async (rpc: string, args: Record<string, unknown> = {}) => {
    const t0 = Date.now()
    const { data, error } = await supabase.rpc(rpc, { p_league_id: leagueId, ...args })
    const t1 = Date.now()
    if (error) { setErrore(error.message); return null }
    const s = data as Stato
    scarto = s.adesso - (t0 + t1) / 2
    setErrore('')
    // Risultato appena arrivato: suono e coriandoli se ho indovinato.
    if (s.domanda?.regolata && s.mia && visto.current !== s.domanda.id) {
      visto.current = s.domanda.id
      if (s.mia.corretta) { suoniRef.current.vincita(); if (s.mia.puntata > 0) setFesta((n) => n + 1) }
    }
    setSt(s)
    return s
  }, [leagueId])

  // Vicino all'ora piena e durante la domanda si chiede lo stato ogni secondo, altrimenti ogni 10 secondi.
  useEffect(() => {
    let vivo = true, timer = 0
    const giro = async () => {
      if (!vivo) return
      if (!inAttesa.current && !document.hidden) { inAttesa.current = true; await chiedi('quizzone_stato'); inAttesa.current = false }
      const s = st
      const vicino = s ? (s.prossima - ora() < 90_000 || (s.domanda != null && ora() - s.domanda.ora < 45_000 && !s.domanda.regolata)) : true
      timer = window.setTimeout(giro, vicino ? 1000 : 10_000)
    }
    void giro()
    const t = window.setInterval(() => setTic((n) => n + 1), 250)
    return () => { vivo = false; window.clearTimeout(timer); window.clearInterval(t) }
  }, [chiedi, st?.prossima, st?.domanda?.id, st?.domanda?.regolata]) // eslint-disable-line react-hooks/exhaustive-deps

  if (!st) return <section className="slot-caricamento">{errore ? <p role="alert">{errore}</p> : <p>Accendo le luci dello studio…</p>}</section>

  const d = st.domanda, mia = st.mia
  const premio = st.premio ?? 100  // premio fisso per risposta giusta, deciso dal server (250 dal 22/10/2026)
  const adesso = ora()
  const dt = d ? adesso - d.ora : Infinity
  const fase: 'entra' | 'domanda' | 'controllo' | 'risultato' | 'attesa' = !d ? 'attesa'
    : dt < 10_000 ? 'entra' : dt < 25_000 ? 'domanda' : !d.regolata ? (dt < 60_000 ? 'controllo' : 'attesa') : (dt < 15 * 60_000 ? 'risultato' : 'attesa')

  async function entra(p: number) { if (invio) return; setInvio(true); await chiedi('quizzone_entra', { p_puntata: p }); setInvio(false); suoni.moneta(1) }
  async function rispondi(i: number) { if (invio || mia?.risposta != null) return; setInvio(true); suoni.tick(i); await chiedi('quizzone_rispondi', { p_risposta: i }); setInvio(false) }

  return <section className="qz" onPointerDown={() => suoni.sblocca()}>
    <div className="slot-saldo">
      <div><small>I tuoi crediti</small><strong><Contatore valore={st.crediti} /></strong></div>
      <span className="slot-ricarica av-dal-vivo"><i aria-hidden="true" />LIVE</span>
      <button type="button" className="slot-audio" aria-pressed={audio} aria-label={audio ? 'Togli i suoni' : 'Attiva i suoni'} onClick={() => setAudio((a) => !a)}>{audio ? '🔊' : '🔇'}</button>
    </div>

    <div className={`qz-studio qz-studio--${fase}`}>
      <div className="qz-insegna"><img src="/specialone-mark.svg" alt="" /><span>QUIZ</span><b>ONE</b></div>

      {fase === 'attesa' && <div className="qz-attesa">
        <small>Prossima domanda</small>
        <strong>{hh(st.prossima)}</strong>
        <span>tra {mmss(st.prossima - adesso)}</span>
        <p>Una domanda ogni ora sulla stagione in corso. All'ora piena hai 10 secondi per entrare, gratis o puntando, poi 15 secondi per rispondere.</p>
      </div>}

      {fase === 'entra' && d && <div className="qz-entra">
        <small>Domanda delle {hh(d.ora)}</small>
        <Anello resto={10_000 - dt} totale={10_000} />
        {mia ? <p className="qz-dentro">Sei dentro {mia.puntata > 0 ? <>con <b>{fmt(mia.puntata)}</b> crediti</> : <b>gratis</b>}. La domanda sta per arrivare…</p> : <>
          <p>Gratis o con puntata, se indovini vinci sempre <b>{fmt(premio)} crediti</b>. Puntando vinci anche il doppio della puntata (se sbagli, perdi solo la puntata).</p>
          <div className="qz-puntate">{PUNTATE.map((p) => <button key={p} type="button" className={`fiche-casino fiche-casino--${p >= 100 ? 100 : p === 50 ? 50 : 10}${puntata === p ? ' is-scelta' : ''}`} disabled={p > st.crediti} onClick={() => setPuntata(p)}><span>{p}</span></button>)}</div>
          <div className="qz-scelta">
            <button type="button" className="qz-tasto qz-tasto--gratis" disabled={invio} onClick={() => void entra(0)}><span>Gioca gratis</span><small>se indovini +{fmt(premio)}</small></button>
            <button type="button" className="qz-tasto qz-tasto--punta" disabled={invio || puntata > st.crediti} onClick={() => void entra(puntata)}><span>Punta {fmt(puntata)}</span><small>se indovini +{fmt(premio + puntata * 2)}</small></button>
          </div>
        </>}
        <p className="qz-giocatori">{d.giocatori} {d.giocatori === 1 ? 'giocatore dentro' : 'giocatori dentro'}</p>
      </div>}

      {(fase === 'domanda' || fase === 'controllo' || fase === 'risultato') && d && <div className="qz-domanda">
        <div className="qz-domanda__testa">
          <small>Domanda delle {hh(d.ora)}</small>
          {fase === 'domanda' && <Anello resto={25_000 - dt} totale={15_000} />}
        </div>
        <h2>{d.testo ?? '…'}</h2>
        <div className="qz-risposte">
          {(d.risposte ?? []).map((r, i) => {
            const mia_ = mia?.risposta === i, giusta = d.corretta === i
            return <button key={i} type="button" disabled={fase !== 'domanda' || !mia || mia.risposta != null || invio} onClick={() => void rispondi(i)}
              className={`qz-risposta${mia_ ? ' is-mia' : ''}${d.corretta != null && giusta ? ' is-giusta' : ''}${d.corretta != null && mia_ && !giusta ? ' is-sbagliata' : ''}`}>
              <i>{'ABCD'[i]}</i><span>{r}</span>
            </button>
          })}
        </div>
        <p className="qz-esito" role="status">
          {fase === 'domanda' ? (!mia ? 'Non sei entrato in tempo: guardi la domanda, ma non puoi rispondere.' : mia.risposta == null ? 'Scegli una risposta!' : 'Risposta data. Aspetta il risultato…')
            : fase === 'controllo' ? 'Controllo le risposte…'
              : !mia ? 'Non hai giocato questa domanda.' : mia.corretta ? <>Esatto! <b>+{fmt(mia.vinto)}</b> crediti</> : mia.risposta == null ? 'Tempo scaduto: nessuna risposta.' : <>Sbagliato{mia.puntata > 0 ? <>: persi {fmt(mia.puntata)} crediti</> : ''}.</>}
        </p>
        {fase === 'risultato' && d.esiti && d.esiti.length > 0 && <ol className="qz-esiti">
          {d.esiti.map((e, i) => <li key={i} className={e.corretta ? 'is-giusta' : 'is-sbagliata'}>
            <Crest value={dati.teamById.get(e.team_id)?.stemma_url ?? null} imageUrl={dati.crestUrlByTeamId.get(e.team_id)} size="small" />
            <span>{dati.teamById.get(e.team_id)?.nome ?? '—'}</span>
            <b>{e.corretta ? `+${fmt(e.vinto)}` : e.puntata > 0 ? `−${fmt(e.puntata)}` : '✗'}</b>
          </li>)}
        </ol>}
        {fase === 'risultato' && <p className="qz-giocatori">Prossima domanda alle {hh(st.prossima)}</p>}
      </div>}
      <Festa key={festa} attiva={festa > 0} />
    </div>

    {errore && <p className="slot-messaggio"><span className="slot-errore">{errore}</span></p>}

    <section className="av-giocate">
      <header><h2>Classifica</h2></header>
      <div className="bet-tab bet-tab--piccola" role="tablist" aria-label="Classifica">
        {([['oggi', 'Oggi'], ['totale', 'Totale'], ['winrate', 'Win rate']] as const).map(([k, l]) => <button key={k} type="button" role="tab" aria-selected={scheda === k} className={scheda === k ? 'is-attiva' : ''} onClick={() => setScheda(k)}>{l}</button>)}
      </div>
      {(() => {
        const tot = st.classifica_totale ?? []
        const righe = scheda === 'oggi' ? st.classifica : scheda === 'totale' ? tot
          : tot.filter((c) => c.giocate >= MIN_WIN_RATE).sort((a, b) => b.giuste / b.giocate - a.giuste / a.giocate || b.giocate - a.giocate)
        if (righe.length === 0) return <p className="bet-nota">{scheda === 'winrate' ? `Entra in classifica chi ha giocato almeno ${MIN_WIN_RATE} domande.` : scheda === 'oggi' ? 'Nessuno ha ancora giocato oggi.' : 'Ancora nessuna domanda giocata.'}</p>
        return <ol>{righe.map((c, i) => <li key={c.team_id}>
          <span className={`bet-pos${i < 3 ? ` bet-pos--${i + 1}` : ''}`}>{i + 1}</span>
          <span className="av-giocate__nome qz-classifica__nome"><Crest value={dati.teamById.get(c.team_id)?.stemma_url ?? null} imageUrl={dati.crestUrlByTeamId.get(c.team_id)} size="small" />{dati.teamById.get(c.team_id)?.nome ?? '—'}</span>
          <span className="av-giocate__puntata">{scheda === 'winrate' ? `${Math.round((100 * c.giuste) / c.giocate)}%` : `${c.giuste}/${c.giocate}`}</span>
          <span className="av-giocate__esito">{scheda === 'winrate' ? <small>{c.giuste}/{c.giocate}</small> : <i>+{fmt(c.vinto)}</i>}</span>
        </li>)}</ol>
      })()}
      {scheda === 'oggi' && ((st.vincitori ?? []).length > 0
        ? <p className="bet-nota">Vincitore di oggi: {(st.vincitori ?? []).map((w) => dati.teamById.get(w.team_id)?.nome ?? '—').join(', ')} (+{fmt((st.vincitori ?? [])[0].crediti)} crediti).</p>
        : <p className="bet-nota">Alle 22:30 il primo della classifica di oggi vince 500 crediti.</p>)}
      {scheda === 'winrate' && <p className="bet-nota">Percentuale di risposte giuste, per chi ha giocato almeno {MIN_WIN_RATE} domande.</p>}
    </section>

    {st.oggi.length > 0 && <section className="qz-oggi">
      <h2>Le domande di oggi</h2>
      <ol>{st.oggi.map((q) => <li key={q.ora}><small>{hh(q.ora)}</small><p>{q.testo}</p><b>{q.risposta}</b></li>)}</ol>
    </section>}
  </section>
}

// Pagina di QuizOne (internamente "quizzone") nel menu Altro.
export function PaginaQuizzone({ membership, onNavigate }: { membership: Membership; onNavigate: (view: GameView) => void }) {
  const league = membership.league as League
  const dati = useSeasonData(membership)
  return <main className="app-shell season-shell bet-shell">
    <GameNav league={league} active="quizzone" onNavigate={onNavigate} />
    <header className="topbar season-topbar"><div className="brand-lockup brand-lockup--dark"><img src="/specialone-mark.svg" alt="" /><span>SpecialOne</span></div><span>QuizOne</span></header>
    <div className="season-page season-page--narrow bet-page">
      <section className="bet-hero">
        <div className="bet-hero__testo">
          <p className="bet-kicker">{league.nome}</p>
          <h1>Quiz<b>One</b></h1>
          <p className="bet-sottotitolo">Il quiz di SpecialOne: una domanda ogni ora sulla stagione. Crediti a chi indovina, chi punta raddoppia la puntata e il primo della giornata vince 500 crediti.</p>
        </div>
      </section>
      {dati.loading ? <section className="slot-caricamento"><p>Preparo lo studio…</p></section> : <Quizzone leagueId={league.id} dati={dati} />}
    </div>
  </main>
}
