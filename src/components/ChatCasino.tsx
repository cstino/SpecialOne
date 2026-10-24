import { useCallback, useEffect, useRef, useState } from 'react'
import { supabase } from '../lib/supabase'
import type { useSeasonData } from '../lib/useSeasonData'
import { Crest } from './Crest'

// Chat dei giochi multiplayer del casino' (CrazyOne, AviatOne, tavolo di BlackjackOne): testo libero fino a 140
// caratteri piu' reazioni rapide. Si legge con un sondaggio ogni pochi secondi (stesso metodo dei giochi live):
// gli ultimi 50 messaggi delle ultime 24 ore, regole e limiti li decide il server (casino_chat_*).
// Solo il proprietario del gioco vede i tasti per cancellare un messaggio o silenziare una squadra.

type Dati = ReturnType<typeof useSeasonData>
type Messaggio = { id: number; team_id: number; testo: string; ora: number }
type Stato = { mio_team_id: number; mod: boolean; silenziato: boolean; silenziati?: number[]; messaggi: Messaggio[] }

const MAX = 140
const MAX_IN_LISTA = 50
// Reazioni rapide: sono messaggi come gli altri (stesso limite di un messaggio ogni 3 secondi).
const REAZIONI = ['🔥🔥🔥', 'Dai!!! 🙌', 'Che fortuna! 🍀', 'Ohhh no 😭', 'Pazzesco 🤯', 'GG 👏', 'Banco 🃏', '😈😈😈']
const ora = (ms: number) => new Date(ms).toLocaleTimeString('it-IT', { hour: '2-digit', minute: '2-digit', timeZone: 'Europe/Rome' })

export function ChatCasino({ leagueId, canale, dati, titolo = 'Chat' }: { leagueId: number; canale: string; dati: Dati; titolo?: string }) {
  const [msgs, setMsgs] = useState<Messaggio[]>([])
  const [info, setInfo] = useState<{ mio: number; mod: boolean; silenziato: boolean; silenziati: number[] } | null>(null)
  const [aperta, setAperta] = useState(false)
  const [letti, setLetti] = useState(0)             // id dell'ultimo messaggio visto: il resto e' "nuovo"
  const [testo, setTesto] = useState('')
  const [invio, setInvio] = useState(false)
  const [errore, setErrore] = useState('')
  const lista = useRef<HTMLOListElement>(null)
  const ultimoId = useRef(0)
  const attaccato = useRef(true)                    // la lista segue i nuovi messaggi solo se si e' gia' in fondo

  // Si rileggono sempre gli ultimi 50 (poche righe corte): cosi' arrivano anche i messaggi cancellati dal proprietario.
  const carica = useCallback(async (primo = false) => {
    const { data, error } = await supabase.rpc('casino_chat_leggi', { p_league_id: leagueId, p_canale: canale, p_dopo: 0 })
    if (error || !data) return
    const s = data as Stato
    setInfo({ mio: s.mio_team_id, mod: s.mod, silenziato: s.silenziato, silenziati: s.silenziati ?? [] })
    const ultimo = s.messaggi.at(-1)?.id ?? 0
    ultimoId.current = ultimo
    // Primo caricamento: quello che c'e' gia' e' "letto", i nuovi si contano da qui in poi.
    if (primo) setLetti(ultimo)
    setMsgs((m) => (m.length === s.messaggi.length && m.every((x, i) => x.id === s.messaggi[i].id) ? m : s.messaggi))
  }, [leagueId, canale])

  // Primo caricamento (e quando cambia canale).
  useEffect(() => {
    ultimoId.current = 0
    setMsgs([]); setInfo(null); setLetti(0)
    void carica(true)
  }, [carica])

  // Sondaggio: ogni 2 s con la chat aperta, ogni 5 s da chiusa (serve al contatore dei nuovi). Fermo se la pagina e' in background.
  useEffect(() => {
    const t = window.setInterval(() => { if (document.visibilityState === 'visible') void carica() }, aperta ? 2000 : 5000)
    return () => window.clearInterval(t)
  }, [carica, aperta])

  // Aperta: si segna tutto come letto e si resta in fondo se non si sta rileggendo.
  useEffect(() => {
    if (!aperta) return
    setLetti(ultimoId.current)
    const el = lista.current
    if (el && attaccato.current) el.scrollTop = el.scrollHeight
  }, [aperta, msgs])

  const nuovi = aperta ? 0 : msgs.filter((m) => m.id > letti && m.team_id !== info?.mio).length
  const ultimo = msgs.at(-1)

  async function manda(t: string) {
    const pulito = t.trim()
    if (!pulito || invio) return
    setInvio(true); setErrore('')
    const { error } = await supabase.rpc('casino_chat_invia', { p_league_id: leagueId, p_canale: canale, p_testo: pulito })
    setInvio(false)
    if (error) { setErrore(error.message); return }
    if (t === testo) setTesto('')
    attaccato.current = true
    await carica()
  }
  async function elimina(id: number) {
    setMsgs((m) => m.filter((x) => x.id !== id))
    const { error } = await supabase.rpc('casino_chat_elimina', { p_id: id })
    if (error) { setErrore(error.message); void carica() }
  }
  async function silenzia(teamId: number, si: boolean) {
    const { error } = await supabase.rpc('casino_chat_silenzia', { p_league_id: leagueId, p_team_id: teamId, p_silenzia: si })
    if (error) { setErrore(error.message); return }
    setInfo((i) => (i ? { ...i, silenziati: si ? [...i.silenziati, teamId] : i.silenziati.filter((x) => x !== teamId) } : i))
  }

  return <section className={`cc${aperta ? ' is-aperta' : ''}`}>
    <button type="button" className="cc__testa" aria-expanded={aperta} onClick={() => setAperta((a) => !a)}>
      <span className="cc__titolo">{titolo}{nuovi > 0 && <b className="cc__nuovi" aria-label={`${nuovi} nuovi messaggi`}>{nuovi}</b>}</span>
      {!aperta && <span className="cc__anteprima">{ultimo ? <><i>{dati.teamById.get(ultimo.team_id)?.nome ?? '—'}</i> {ultimo.testo}</> : 'Nessun messaggio ancora'}</span>}
      <span className="cc__freccia" aria-hidden="true">{aperta ? '−' : '+'}</span>
    </button>
    {aperta && <div className="cc__corpo">
      <ol className="cc__lista" ref={lista} onScroll={(e) => { const el = e.currentTarget; attaccato.current = el.scrollHeight - el.scrollTop - el.clientHeight < 40 }}>
        {msgs.length === 0 && <li className="cc__vuota">Nessun messaggio. Scrivi tu per primo!</li>}
        {msgs.map((m) => {
          const team = dati.teamById.get(m.team_id), mio = m.team_id === info?.mio, muto = info?.silenziati.includes(m.team_id)
          return <li key={m.id} className={`cc__msg${mio ? ' is-mio' : ''}`}>
            <span className="cc__stemma"><Crest value={team?.stemma_url ?? null} imageUrl={dati.crestUrlByTeamId.get(m.team_id)} size="small" /></span>
            <span className="cc__bolla">
              <span className="cc__autore"><b>{team?.nome ?? '—'}</b><small>{ora(m.ora)}</small></span>
              <span className="cc__testo">{m.testo}</span>
            </span>
            {info?.mod && !mio && <span className="cc__mod">
              <button type="button" aria-label="Cancella il messaggio" title="Cancella" onClick={() => void elimina(m.id)}>✕</button>
              <button type="button" aria-label={muto ? 'Riabilita la squadra' : 'Silenzia la squadra'} title={muto ? 'Riabilita' : 'Silenzia'} aria-pressed={muto} onClick={() => void silenzia(m.team_id, !muto)}>{muto ? '🔊' : '🔇'}</button>
            </span>}
          </li>
        })}
      </ol>
      <div className="cc__reazioni" role="group" aria-label="Reazioni rapide">
        {REAZIONI.map((r) => <button key={r} type="button" disabled={invio || info?.silenziato} onClick={() => void manda(r)}>{r}</button>)}
      </div>
      <form className="cc__form" onSubmit={(e) => { e.preventDefault(); void manda(testo) }}>
        <input type="text" value={testo} maxLength={MAX} placeholder={info?.silenziato ? 'Sei stato silenziato' : 'Scrivi un messaggio…'} disabled={info?.silenziato} enterKeyHint="send" autoComplete="off"
          onChange={(e) => setTesto(e.target.value)} aria-label="Messaggio" />
        <button type="submit" disabled={invio || !testo.trim() || info?.silenziato}>Invia</button>
      </form>
      <p className="cc__nota">{testo.length > 100 ? `${MAX - testo.length} caratteri rimasti · ` : ''}Un messaggio ogni 3 secondi. Restano 24 ore.</p>
      {errore && <p className="cc__errore" role="alert">{errore}</p>}
    </div>}
  </section>
}
