import { useCallback, useEffect, useRef, useState } from 'react'
import { supabase } from '../lib/supabase'
import { useMusica } from '../lib/musicaCasino'
import { Contatore, Festa, fmt, useSuoni } from './Casino'

// BetOne Casino' › BlackjackOne (supabase/migrations/20261020260000_casino_blackjackone.sql).
// Blackjack online classico contro il banco: 6 mazzi rimescolati a ogni mano dal SERVER, blackjack 3:2, il banco sta
// su tutti i 17, raddoppio, divisione fino a 4 mani, assicurazione. Qui si disegna soltanto: ogni carta la da' il server.

type Mano = { carte: number[]; puntata: number; fatto?: boolean; raddoppiata?: boolean; da_split?: boolean; assi_divisi?: boolean; vinto?: number; blackjack?: boolean }
type Tavolo = { id: number; stato: 'assicurazione' | 'gioca' | 'finita'; attiva: number; puntata: number; assicurazione: number; vinto: number; mani: Mano[]; banco: Array<number | null>; puo_raddoppiare: boolean; puo_dividere: boolean }
type Stato = { crediti: number; mano: Tavolo | null }

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

export function BlackjackOne({ leagueId }: { leagueId: number }) {
  const [stato, setStato] = useState<Stato | null>(null)
  const [puntata, setPuntata] = useState(0)
  const [ultima, setUltima] = useState(0)
  const [errore, setErrore] = useState('')
  const [invio, setInvio] = useState(false)
  const [festa, setFesta] = useState(0)
  const [regole, setRegole] = useState(false)
  const [audio, setAudio] = useState(() => { try { return localStorage.getItem('slot-audio') !== '0' } catch { return true } })
  const suoni = useSuoni(audio)
  const sbloccaMusica = useMusica('bj', audio)
  const prima = useRef<Tavolo | null>(null)

  useEffect(() => { try { localStorage.setItem('slot-audio', audio ? '1' : '0') } catch { /* preferenza solo locale */ } }, [audio])

  const applica = useCallback((s: Stato) => {
    const vecchia = prima.current, nuova = s.mano
    // Suoni: una carta nuova = fruscio; fine mano = vincita.
    const contaCarte = (t: Tavolo | null) => (t ? t.mani.reduce((n, m) => n + m.carte.length, 0) + t.banco.filter((c) => c != null).length : 0)
    const nuove = vecchia && nuova && vecchia.id === nuova.id ? contaCarte(nuova) - contaCarte(vecchia) : contaCarte(nuova)
    for (let i = 0; i < Math.min(nuove, 8); i++) window.setTimeout(() => suoni.tick(i), i * 140)
    if (nuova?.stato === 'finita' && vecchia?.stato !== 'finita' || (nuova?.stato === 'finita' && vecchia?.id !== nuova?.id)) {
      const giocato = nuova.mani.reduce((t, m) => t + m.puntata, 0) + nuova.assicurazione
      window.setTimeout(() => {
        if (nuova.mani.some((m) => m.blackjack && (m.vinto ?? 0) > m.puntata)) { suoni.grande(); setFesta((n) => n + 1) }
        else if (nuova.vinto > giocato) suoni.vincita()
      }, Math.min(nuove, 8) * 140 + 200)
    }
    prima.current = nuova
    setStato(s)
  }, [suoni])

  const chiedi = useCallback(async (rpc: string, args: Record<string, unknown> = {}) => {
    if (invio) return null
    setInvio(true); setErrore('')
    const { data, error } = await supabase.rpc(rpc, { p_league_id: leagueId, ...args })
    setInvio(false)
    if (error) { setErrore(error.message); return null }
    applica(data as Stato)
    return data as Stato
  }, [leagueId, applica, invio])

  useEffect(() => {
    void (async () => {
      const { data, error } = await supabase.rpc('casino_bj_stato', { p_league_id: leagueId })
      if (error) { setErrore(error.message); return }
      prima.current = (data as Stato).mano
      setStato(data as Stato)
    })()
  }, [leagueId])

  if (!stato) return <section className="slot-caricamento">{errore ? <p role="alert">{errore}</p> : <p>Preparo il tavolo…</p>}</section>

  const t = stato.mano
  const inCorso = t != null && t.stato !== 'finita'
  const crediti = stato.crediti
  const aggiungi = (f: number) => { if (puntata + f > 500) { setErrore('Al massimo 500 crediti a mano.'); return } if (puntata + f > crediti) { setErrore('Crediti insufficienti.'); return } setErrore(''); setPuntata((p) => p + f); suoni.moneta(f) }
  const distribuisci = async () => { const p = puntata || ultima; if (!p) return; const r = await chiedi('casino_bj_punta', { p_puntata: p }); if (r) { setUltima(p); setPuntata(0) } }
  const banco = t?.banco ?? []
  const totBanco = t ? totale(banco.filter((c): c is number => c != null)) : null
  const attiva = t?.mani[t.attiva]
  const messaggio = errore ? <span className="slot-errore">{errore}</span>
    : !t || t.stato === 'finita' ? (t ? (t.vinto > 0 ? `Hai portato a casa ${fmt(t.vinto)} crediti.` : 'Il banco vince questa mano.') : 'Scegli la puntata e distribuisci le carte.')
      : t.stato === 'assicurazione' ? `Il banco mostra un asso: vuoi assicurarti per ${fmt(Math.floor(t.puntata / 2))} crediti?`
        : t.mani.length > 1 ? `Mano ${t.attiva + 1} di ${t.mani.length}: carta o stai?` : 'Carta o stai?'

  return <section className="bj" onPointerDown={() => { suoni.sblocca(); sbloccaMusica() }}>
    <div className="slot-saldo">
      <div><small>I tuoi crediti</small><strong><Contatore valore={crediti} /></strong></div>
      <span className="slot-ricarica">+1.000 gratis alle 23:00</span>
      <button type="button" className="slot-audio" aria-pressed={audio} aria-label={audio ? 'Togli i suoni' : 'Attiva i suoni'} onClick={() => setAudio((a) => !a)}>{audio ? '🔊' : '🔇'}</button>
    </div>

    <div className="bj-tavolo">
      <div className="bj-insegna"><img src="/specialone-mark.svg" alt="" /><span>BLACKJACK</span><b>ONE</b></div>
      <p className="bj-regola">Il blackjack paga 3 a 2 · Il banco sta su tutti i 17</p>

      <div className="bj-zona bj-zona--banco">
        <div className="bj-carte">{t ? banco.map((c, i) => <Carta key={`${t.id}-b${i}-${c ?? 'x'}`} c={c} ritardo={i * 140} />) : <><span className="bj-posto" /><span className="bj-posto" /></>}</div>
        {t && totBanco && <span className="bj-totale">Banco {totBanco.tot}{t.stato !== 'finita' ? '' : totBanco.tot > 21 ? ' · sballa' : ''}</span>}
      </div>

      <div className={`bj-zona bj-zona--giocatore${t && t.mani.length > 1 ? ' is-divise' : ''}`}>
        {t ? t.mani.map((m, i) => {
          const tt = totale(m.carte), es = esitoMano(m)
          return <div key={i} className={`bj-mano${inCorso && i === t.attiva ? ' is-attiva' : ''}${es ? ` is-${es.tipo}` : ''}`}>
            <div className="bj-carte">{m.carte.map((c, k) => <Carta key={`${t.id}-${i}-${k}`} c={c} ritardo={k * 140} />)}</div>
            <span className="bj-totale">{tt.morbida && tt.tot < 21 ? `${tt.tot - 10}/${tt.tot}` : tt.tot}{m.raddoppiata ? ' · ×2' : ''}</span>
            <span className="bj-fiche-mano">{fmt(m.puntata)}</span>
            {es && <span className={`bj-esito bj-esito--${es.tipo}`}>{es.testo}{(m.vinto ?? 0) > 0 ? ` +${fmt(m.vinto ?? 0)}` : ''}</span>}
          </div>
        }) : <div className="bj-mano"><div className="bj-carte"><span className="bj-posto" /><span className="bj-posto" /></div></div>}
      </div>
      {t && t.assicurazione > 0 && <p className="bj-assicurazione">Assicurazione: {fmt(t.assicurazione)}</p>}
      <Festa key={festa} attiva={festa > 0} />
    </div>

    <p className="slot-messaggio" role="status">{messaggio}</p>

    {t?.stato === 'assicurazione' ? <div className="bj-mosse">
      <button type="button" className="bj-mossa bj-mossa--si" disabled={invio || crediti < Math.floor(t.puntata / 2)} onClick={() => void chiedi('casino_bj_assicura', { p_si: true })}>Assicurati</button>
      <button type="button" className="bj-mossa" disabled={invio} onClick={() => void chiedi('casino_bj_assicura', { p_si: false })}>No grazie</button>
    </div>
      : inCorso && attiva ? <div className="bj-mosse">
        <button type="button" className="bj-mossa bj-mossa--carta" disabled={invio} onClick={() => void chiedi('casino_bj_azione', { p_azione: 'carta' })}>Carta</button>
        <button type="button" className="bj-mossa bj-mossa--stai" disabled={invio} onClick={() => void chiedi('casino_bj_azione', { p_azione: 'stai' })}>Stai</button>
        <button type="button" className="bj-mossa" disabled={invio || !t.puo_raddoppiare || crediti < attiva.puntata} onClick={() => void chiedi('casino_bj_azione', { p_azione: 'raddoppia' })}>Raddoppia</button>
        <button type="button" className="bj-mossa" disabled={invio || !t.puo_dividere || crediti < attiva.puntata} onClick={() => void chiedi('casino_bj_azione', { p_azione: 'dividi' })}>Dividi</button>
      </div>
        : <div className="bj-puntata">
          <div className="ct-fiche">{FICHE.map((f) => <button key={f} type="button" className={`fiche-casino fiche-casino--${f}`} disabled={invio} onClick={() => aggiungi(f)}><span>{f}</span></button>)}</div>
          <div className="bj-puntata__riga">
            <button type="button" className="bj-mossa bj-mossa--piccola" disabled={puntata === 0} onClick={() => setPuntata(0)}>Azzera</button>
            <div className="ct-totale"><small>Puntata</small><b>{fmt(puntata || ultima)}</b></div>
            <button type="button" className="bj-distribuisci" disabled={invio || !(puntata || ultima) || (puntata || ultima) > crediti} onClick={() => void distribuisci()}>
              <span>DISTRIBUISCI</span><small>{puntata ? 'nuova puntata' : ultima ? 'stessa puntata' : 'scegli le fiche'}</small>
            </button>
          </div>
        </div>}

    <section className="slot-pannello">
      <button type="button" className="slot-pannello__tasto" aria-expanded={regole} onClick={() => setRegole((v) => !v)}>Come si gioca <span aria-hidden="true">{regole ? '−' : '+'}</span></button>
      {regole && <div className="slot-premi">
        <p>Scopo: fare più punti del banco senza superare 21. Le figure valgono 10, l'asso 1 o 11, le altre carte il loro numero.</p>
        <p>Scegli la puntata con le fiche (da 10 a 500) e premi <b>DISTRIBUISCI</b>: due carte a te, due al banco (una coperta). Poi <b>Carta</b> per pescarne un'altra, <b>Stai</b> per fermarti. <b>Raddoppia</b>: raddoppi la puntata e ricevi una sola carta. <b>Dividi</b>: con due carte dello stesso valore le separi in due mani (fino a 4; gli assi divisi ricevono una carta sola).</p>
        <p>Il banco scopre la sua carta e pesca finché non arriva almeno a 17, poi si ferma. Vinci 1 a 1 se fai più punti del banco o se il banco supera 21; pareggio = puntata restituita. <b>Blackjack</b> (asso + figura o 10 con le prime due carte) paga 3 a 2.</p>
        <p><b>Assicurazione</b>: se il banco mostra un asso puoi assicurarti per metà puntata; se il banco ha blackjack l'assicurazione paga 2 a 1.</p>
        <p>Le carte le distribuisce il server da 6 mazzi rimescolati a ogni mano.</p>
      </div>}
    </section>
  </section>
}
