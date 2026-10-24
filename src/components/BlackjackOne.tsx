import { useCallback, useEffect, useRef, useState } from 'react'
import { supabase } from '../lib/supabase'
import type { useSeasonData } from '../lib/useSeasonData'
import { useMusica } from '../lib/musicaCasino'
import { Contatore, Festa, fmt, useSuoni } from './Casino'
import { Crest } from './Crest'
import { ChatCasino } from './ChatCasino'

// BetOne Casino' › BlackjackOne LIVE (supabase/migrations/20261020270000_blackjackone_tavoli_live.sql).
// Tavoli condivisi da massimo 4 giocatori contro un solo banco: puntate 15 s, distribuzione, assicurazione, turni da
// 15 s per decisione, banco, risultati. 6 mazzi rimescolati a ogni giro dal SERVER, blackjack 3:2, banco su tutti i 17.
// Qui si disegna soltanto: carte, turni e scadenze li decide il server.

type Mano = { carte: number[]; puntata: number; fatto?: boolean; raddoppiata?: boolean; da_split?: boolean; assi_divisi?: boolean; vinto?: number; blackjack?: boolean }
type Dati = ReturnType<typeof useSeasonData>
type Posto = { posto: number; team_id: number; mio: boolean; puntata: number; mani: Mano[]; assicurazione: number; assicurazione_decisa: boolean; vinto: number | null; assente: boolean }
type Tavolo = { id: number; numero: number; fase: 'attesa' | 'puntate' | 'assicurazione' | 'turni' | 'risultato'; giro: number; scadenza: number | null; turno_posto: number | null; turno_mano: number | null; banco: Array<number | null> }
type StatoTavolo = { seduto: boolean; adesso?: number; tavolo?: Tavolo; posti?: Posto[]; crediti?: number }
type Sala = { crediti: number; mio_tavolo: number | null; tavoli: Array<{ id: number; numero: number; fase: string; posti: Array<{ posto: number; team_id: number }> }> }

const FICHE = [10, 20, 50, 100]
const SEMI = ['♠', '♥', '♦', '♣']
const RANGHI = ['A', '2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K']
const valore = (c: number) => (c % 13 === 0 ? 1 : c % 13 >= 9 ? 10 : (c % 13) + 1)
function totale(carte: number[]) {
  const s = carte.reduce((t, c) => t + valore(c), 0)
  const morbida = carte.some((c) => c % 13 === 0) && s + 10 <= 21
  return { tot: morbida ? s + 10 : s, morbida }
}

// ---------- Carta SpecialOne ----------
function Carta({ c, ritardo = 0 }: { c: number | null; ritardo?: number }) {
  const coperta = c == null
  return <span className={`bj-carta${coperta ? ' is-coperta' : ''}`} style={{ animationDelay: `${ritardo}ms` }}>
    {coperta ? <span className="bj-carta__dorso"><img src="/specialone-mark.svg" alt="" /></span> : (() => {
      const seme = Math.floor(c / 13), rango = RANGHI[c % 13], rossa = seme === 1 || seme === 2, figura = c % 13 >= 10
      return <span className={`bj-carta__fronte${rossa ? ' is-rossa' : ''}`} aria-label={`${rango} di ${SEMI[seme]}`}>
        <span className="bj-carta__angolo"><b>{rango}</b><i>{SEMI[seme]}</i></span>
        <span className="bj-carta__centro">{figura ? <><img src="/specialone-mark.svg" alt="" /><b>{rango}</b></> : rango === 'A' ? <em>{SEMI[seme]}</em> : <i>{SEMI[seme]}</i>}</span>
        <span className="bj-carta__angolo bj-carta__angolo--giu"><b>{rango}</b><i>{SEMI[seme]}</i></span>
      </span>
    })()}
  </span>
}

function esitoMano(m: Mano) {
  if (m.vinto == null) return null
  if (m.blackjack && m.vinto > m.puntata) return { testo: 'Blackjack!', tipo: 'bj' }
  if (totale(m.carte).tot > 21) return { testo: 'Sballata', tipo: 'perso' }
  if (m.vinto > m.puntata) return { testo: 'Vinta', tipo: 'vinto' }
  if (m.vinto === m.puntata) return { testo: 'Pareggio', tipo: 'pari' }
  return { testo: 'Persa', tipo: 'perso' }
}

let scarto = 0
const oraServer = () => Date.now() + scarto

function Conto({ fino }: { fino: number | null }) {
  const [, aggiorna] = useState(0)
  useEffect(() => { const t = window.setInterval(() => aggiorna((n) => n + 1), 250); return () => window.clearInterval(t) }, [])
  if (!fino) return null
  return <b className="bj-conto">{Math.max(0, Math.ceil((fino - oraServer()) / 1000))}s</b>
}

export function BlackjackOne({ leagueId, dati }: { leagueId: number; dati: Dati }) {
  const [sala, setSala] = useState<Sala | null>(null)
  const [st, setSt] = useState<StatoTavolo | null>(null)
  const [ultima, setUltima] = useState(0)
  const [errore, setErrore] = useState('')
  const [invio, setInvio] = useState(false)
  const [festa, setFesta] = useState(0)
  const [regole, setRegole] = useState(false)
  const [audio, setAudio] = useState(() => { try { return localStorage.getItem('slot-audio') !== '0' } catch { return true } })
  const suoni = useSuoni(audio)
  const suoniRef = useRef(suoni); suoniRef.current = suoni
  const sbloccaMusica = useMusica('bj', audio)
  const prima = useRef<StatoTavolo | null>(null)
  const inAttesa = useRef(false)

  useEffect(() => { try { localStorage.setItem('slot-audio', audio ? '1' : '0') } catch { /* preferenza solo locale */ } }, [audio])

  const conta = (s: StatoTavolo | null) => (s?.posti ?? []).reduce((n, p) => n + p.mani.reduce((k, m) => k + m.carte.length, 0), 0) + (s?.tavolo?.banco ?? []).filter((c) => c != null).length

  const applica = useCallback((s: StatoTavolo, t0: number, t1: number) => {
    if (s.adesso) scarto = s.adesso - (t0 + t1) / 2
    const vecchio = prima.current
    const stessoGiro = vecchio?.tavolo?.giro === s.tavolo?.giro
    const nuove = stessoGiro ? conta(s) - conta(vecchio) : conta(s)
    for (let i = 0; i < Math.min(Math.max(0, nuove), 10); i++) window.setTimeout(() => suoniRef.current.tick(i), i * 130)
    // Fine giro: suono della mia vincita.
    if (s.tavolo?.fase === 'risultato' && vecchio?.tavolo?.fase !== 'risultato') {
      const mio = s.posti?.find((p) => p.mio)
      if (mio && mio.puntata > 0 && mio.vinto != null) {
        const giocato = mio.mani.reduce((t, m) => t + m.puntata, 0) + mio.assicurazione
        window.setTimeout(() => {
          if (mio.mani.some((m) => m.blackjack && (m.vinto ?? 0) > m.puntata)) { suoniRef.current.grande(); setFesta((n) => n + 1) }
          else if ((mio.vinto ?? 0) > giocato) suoniRef.current.vincita()
        }, 600)
      }
    }
    // Tocca a me: un piccolo avviso.
    const mioPosto = s.posti?.find((p) => p.mio)?.posto
    if (s.tavolo?.fase === 'turni' && s.tavolo.turno_posto === mioPosto && !(vecchio?.tavolo?.fase === 'turni' && vecchio.tavolo.turno_posto === mioPosto)) suoniRef.current.coppe()
    prima.current = s
    setSt(s)
  }, [])

  const chiedi = useCallback(async (rpc: string, args: Record<string, unknown> = {}) => {
    const t0 = Date.now()
    const { data, error } = await supabase.rpc(rpc, { p_league_id: leagueId, ...args })
    const t1 = Date.now()
    if (error) { setErrore(error.message); return null }
    setErrore('')
    const d = data as StatoTavolo & Partial<Sala>
    if ('tavoli' in d) { setSala(d as unknown as Sala); setSt({ seduto: false }); prima.current = null }
    else applica({ ...d, seduto: d.seduto ?? 'tavolo' in d }, t0, t1)   // siedi risponde con il tavolo, senza 'seduto'
    return d
  }, [leagueId, applica])

  // Seduto: stato del tavolo ogni secondo. In sala: elenco dei tavoli ogni 3 secondi.
  useEffect(() => {
    let vivo = true
    const giro = async () => {
      if (!vivo || inAttesa.current || document.hidden) return
      inAttesa.current = true
      const s = await chiedi('casino_bjl_stato')
      if (s && !s.seduto) await chiedi('casino_bjl_sala')
      inAttesa.current = false
    }
    void giro()
    const t = window.setInterval(() => void giro(), st?.seduto ? 1000 : 3000)
    return () => { vivo = false; window.clearInterval(t) }
  }, [chiedi, st?.seduto])

  async function azione(rpc: string, args: Record<string, unknown> = {}) {
    if (invio) return
    setInvio(true); await chiedi(rpc, args); setInvio(false)
  }

  // ---------- Sala ----------
  if (!st || (!st.seduto && !sala)) return <section className="slot-caricamento">{errore ? <p role="alert">{errore}</p> : <p>Preparo i tavoli…</p>}</section>

  if (!st.seduto) {
    const s = sala!
    return <section className="bj" onPointerDown={() => { suoni.sblocca(); sbloccaMusica() }}>
      <div className="slot-saldo">
        <div><small>I tuoi crediti</small><strong><Contatore valore={s.crediti} /></strong></div>
        <span className="slot-ricarica av-dal-vivo"><i aria-hidden="true" />LIVE</span>
        <button type="button" className="slot-audio" aria-pressed={audio} aria-label={audio ? 'Togli i suoni' : 'Attiva i suoni'} onClick={() => setAudio((a) => !a)}>{audio ? '🔊' : '🔇'}</button>
      </div>
      <div className="bj-sala">
        <div className="bj-insegna"><img src="/specialone-mark.svg" alt="" /><span>BLACKJACK</span><b>ONE</b></div>
        <p className="bet-nota">Tavoli da massimo 4 giocatori contro un solo banco. Siediti dove vuoi o al primo posto libero.</p>
        <button type="button" className="bj-distribuisci bj-siediti" disabled={invio} onClick={() => void azione('casino_bjl_siedi')}><span>SIEDITI</span><small>al primo posto libero</small></button>
        {errore && <p className="slot-errore" role="alert">{errore}</p>}
        {s.tavoli.length === 0 ? <p className="bet-nota">Nessun tavolo aperto: sedendoti ne apri uno.</p> : <ol className="bj-tavoli">
          {s.tavoli.map((t) => <li key={t.id}>
            <div><b>Tavolo {t.numero}</b><small>{t.posti.length}/4 giocatori</small></div>
            <span className="bj-tavoli__posti">{[1, 2, 3, 4].map((n) => { const p = t.posti.find((x) => x.posto === n); return <span key={n} className={p ? 'is-pieno' : ''}>{p ? <Crest value={dati.teamById.get(p.team_id)?.stemma_url ?? null} imageUrl={dati.crestUrlByTeamId.get(p.team_id)} size="small" /> : null}</span> })}</span>
            <button type="button" className="bj-mossa bj-mossa--piccola" disabled={invio || t.posti.length >= 4} onClick={() => void azione('casino_bjl_siedi', { p_tavolo: t.id })}>{t.posti.length >= 4 ? 'Pieno' : 'Siediti'}</button>
          </li>)}
        </ol>}
      </div>
    </section>
  }

  // ---------- Tavolo ----------
  const t = st.tavolo!, posti = st.posti ?? [], crediti = st.crediti ?? 0
  const mio = posti.find((p) => p.mio)
  const banco = t.banco ?? []
  const totBanco = totale(banco.filter((c): c is number => c != null))
  const mioTurno = t.fase === 'turni' && t.turno_posto === mio?.posto
  const manoMia = mioTurno && mio ? mio.mani[t.turno_mano ?? 0] : undefined
  const puoRaddoppiare = !!manoMia && manoMia.carte.length === 2 && crediti >= manoMia.puntata
  const puoDividere = !!manoMia && !!mio && manoMia.carte.length === 2 && valore(manoMia.carte[0]) === valore(manoMia.carte[1]) && mio.mani.length < 4 && crediti >= manoMia.puntata
  const inGioco = !!mio && mio.puntata > 0 && (t.fase === 'assicurazione' || t.fase === 'turni')
  const nomeDi = (teamId: number) => dati.teamById.get(teamId)?.nome ?? '—'
  const diTurno = posti.find((p) => p.posto === t.turno_posto)
  const punta = async (nuova: number) => { if (nuova > 500) { setErrore('Al massimo 500 crediti a mano.'); return } await azione('casino_bjl_punta', { p_puntata: nuova }); if (nuova > 0) setUltima(nuova) }
  const fraseFase = t.fase === 'attesa' ? 'In attesa di giocatori…'
    : t.fase === 'puntate' ? (mio?.puntata ? `Puntata registrata: ${fmt(mio.puntata)}. Le carte tra poco.` : 'Puntate aperte: scegli le fiche.')
      : t.fase === 'assicurazione' ? 'Il banco mostra un asso: assicurazione?'
        : t.fase === 'turni' ? (mioTurno ? 'Tocca a te!' : `Tocca a ${diTurno ? nomeDi(diTurno.team_id) : '…'}`)
          : 'Risultati'

  return <section className="bj" onPointerDown={() => { suoni.sblocca(); sbloccaMusica() }}>
    <div className="slot-saldo">
      <div><small>I tuoi crediti</small><strong><Contatore valore={crediti} /></strong></div>
      <button type="button" className="bj-mossa bj-mossa--piccola" disabled={invio || inGioco} onClick={() => void azione('casino_bjl_alzati')}>Alzati</button>
      <button type="button" className="slot-audio" aria-pressed={audio} aria-label={audio ? 'Togli i suoni' : 'Attiva i suoni'} onClick={() => setAudio((a) => !a)}>{audio ? '🔊' : '🔇'}</button>
    </div>

    <div className="bj-tavolo">
      <div className="bj-insegna"><img src="/specialone-mark.svg" alt="" /><span>TAVOLO</span><b>{t.numero}</b></div>
      <p className="bj-regola">Il blackjack paga 3 a 2 · Il banco sta su tutti i 17</p>
      <div className="bj-fase"><span>{fraseFase}</span>{t.fase !== 'risultato' && t.fase !== 'attesa' && <Conto fino={t.scadenza} />}</div>
      <div className="bj-zona bj-zona--banco">
        <div className="bj-carte">{banco.length ? banco.map((c, i) => <Carta key={`${t.giro}-b${i}-${c ?? 'x'}`} c={c} ritardo={i * 130} />) : <><span className="bj-posto" /><span className="bj-posto" /></>}</div>
        {banco.length > 0 && <span className="bj-totale">Banco {totBanco.tot}{t.fase === 'risultato' && totBanco.tot > 21 ? ' · sballa' : ''}</span>}
      </div>
      <div className="bj-posti">
        {[1, 2, 3, 4].map((n) => {
          const p = posti.find((x) => x.posto === n)
          if (!p) return <div key={n} className="bj-sedia is-vuota"><span>Posto libero</span></div>
          const diTurnoQui = t.fase === 'turni' && t.turno_posto === n
          return <div key={n} className={`bj-sedia${p.mio ? ' is-mia' : ''}${diTurnoQui ? ' is-turno' : ''}${p.assente ? ' is-assente' : ''}`}>
            <div className="bj-sedia__testa">
              <Crest value={dati.teamById.get(p.team_id)?.stemma_url ?? null} imageUrl={dati.crestUrlByTeamId.get(p.team_id)} size="small" />
              <b>{p.mio ? 'Tu' : nomeDi(p.team_id)}</b>
              {p.puntata > 0 && <span className="bj-sedia__fiche">{fmt(p.mani.reduce((x, m) => x + m.puntata, 0) || p.puntata)}</span>}
            </div>
            {p.mani.length === 0 ? <small className="bj-sedia__stato">{t.fase === 'puntate' ? (p.puntata ? 'Ha puntato' : 'Sceglie…') : 'Non gioca'}</small>
              : <div className="bj-sedia__mani">{p.mani.map((m, i) => {
                const tt = totale(m.carte), es = esitoMano(m)
                return <div key={i} className={`bj-mano bj-mano--piccola${diTurnoQui && t.turno_mano === i ? ' is-attiva' : ''}${es ? ` is-${es.tipo}` : ''}`}>
                  <div className="bj-carte">{m.carte.map((c, k) => <Carta key={`${t.giro}-${n}-${i}-${k}`} c={c} ritardo={k * 130} />)}</div>
                  <span className="bj-totale">{tt.morbida && tt.tot < 21 ? `${tt.tot - 10}/${tt.tot}` : tt.tot}{m.raddoppiata ? ' ×2' : ''}</span>
                  {es && <span className={`bj-esito bj-esito--${es.tipo}`}>{es.testo}</span>}
                </div>
              })}</div>}
            {p.vinto != null && p.puntata > 0 && t.fase === 'risultato' && <small className={`bj-sedia__vinto${p.vinto > 0 ? ' is-positivo' : ''}`}>{p.vinto > 0 ? `+${fmt(p.vinto)}` : 'nulla'}</small>}
          </div>
        })}
      </div>
      <Festa key={festa} attiva={festa > 0} />
    </div>

    <p className="slot-messaggio" role="status">{errore ? <span className="slot-errore">{errore}</span> : mioTurno ? 'Carta o stai? Hai 15 secondi, poi stai automaticamente.' : t.fase === 'puntate' ? 'Le fiche si sommano; puoi cambiare la puntata finché il tempo non scade.' : ' '}</p>

    {t.fase === 'assicurazione' && mio && mio.puntata > 0 && !mio.assicurazione_decisa ? <div className="bj-mosse">
      <button type="button" className="bj-mossa bj-mossa--si" disabled={invio || crediti < Math.floor(mio.puntata / 2)} onClick={() => void azione('casino_bjl_assicura', { p_si: true })}>Assicurati ({fmt(Math.floor(mio.puntata / 2))})</button>
      <button type="button" className="bj-mossa" disabled={invio} onClick={() => void azione('casino_bjl_assicura', { p_si: false })}>No grazie</button>
    </div>
      : mioTurno ? <div className="bj-mosse">
        <button type="button" className="bj-mossa bj-mossa--carta" disabled={invio} onClick={() => void azione('casino_bjl_azione', { p_azione: 'carta' })}>Carta</button>
        <button type="button" className="bj-mossa bj-mossa--stai" disabled={invio} onClick={() => void azione('casino_bjl_azione', { p_azione: 'stai' })}>Stai</button>
        <button type="button" className="bj-mossa" disabled={invio || !puoRaddoppiare} onClick={() => void azione('casino_bjl_azione', { p_azione: 'raddoppia' })}>Raddoppia</button>
        <button type="button" className="bj-mossa" disabled={invio || !puoDividere} onClick={() => void azione('casino_bjl_azione', { p_azione: 'dividi' })}>Dividi</button>
      </div>
        : (t.fase === 'puntate' || t.fase === 'attesa') && mio ? <div className="bj-puntata">
          <div className="ct-fiche">{FICHE.map((f) => <button key={f} type="button" className={`fiche-casino fiche-casino--${f}`} disabled={invio || mio.puntata + f > Math.min(500, crediti + mio.puntata)} onClick={() => void punta(mio.puntata + f)}><span>{f}</span></button>)}</div>
          <div className="bj-puntata__riga">
            <button type="button" className="bj-mossa bj-mossa--piccola" disabled={invio || mio.puntata === 0} onClick={() => void punta(0)}>Azzera</button>
            <div className="ct-totale"><small>La tua puntata</small><b>{fmt(mio.puntata)}</b></div>
            <button type="button" className="bj-mossa bj-mossa--piccola" disabled={invio || !ultima || mio.puntata === ultima || ultima > crediti + mio.puntata} onClick={() => void punta(ultima)}>Ripeti {ultima ? fmt(ultima) : ''}</button>
          </div>
        </div> : null}

    <ChatCasino key={t.id} leagueId={leagueId} canale={`bj:${t.id}`} dati={dati} titolo={`Chat del tavolo ${t.numero}`} />

    <section className="slot-pannello">
      <button type="button" className="slot-pannello__tasto" aria-expanded={regole} onClick={() => setRegole((v) => !v)}>Come si gioca <span aria-hidden="true">{regole ? '−' : '+'}</span></button>
      {regole && <div className="slot-premi">
        <p>BlackjackOne è <b>live</b>: fino a 4 giocatori allo stesso tavolo contro un solo banco, e tutti vedono le carte di tutti.</p>
        <p><b>Puntate</b> (15 secondi): tocca le fiche, si sommano (da 10 a 500); puoi cambiare o azzerare finché il tempo non scade. Chi non punta salta il giro ma resta seduto.</p>
        <p><b>Turni</b>: si gioca un posto alla volta. Quando tocca a te hai 15 secondi per ogni decisione, poi stai automaticamente. <b>Carta</b> per pescare, <b>Stai</b> per fermarti, <b>Raddoppia</b> (raddoppi e ricevi una carta sola), <b>Dividi</b> (due carte dello stesso valore diventano due mani, fino a 4; gli assi divisi ricevono una carta sola).</p>
        <p>Scopo: fare più punti del banco senza superare 21 (figure 10, asso 1 o 11). Il banco gioca una volta sola per tutti e pesca fino ad almeno 17. Vinci 1 a 1, pareggio = puntata indietro, <b>blackjack</b> 3 a 2. <b>Assicurazione</b> se il banco mostra un asso: metà puntata, paga 2 a 1 se il banco ha blackjack.</p>
        <p>Se non ti colleghi per un minuto perdi il posto a fine mano. Le carte le distribuisce il server da 6 mazzi rimescolati a ogni giro.</p>
      </div>}
    </section>
  </section>
}
