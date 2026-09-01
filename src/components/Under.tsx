import { useCallback, useEffect, useMemo, useState } from 'react'
import { MACRO_COLORE, MACRO_LABEL, macroRuolo, type MacroRuolo } from '../lib/ruoli'
import { supabase } from '../lib/supabase'
import { useSeasonData } from '../lib/useSeasonData'
import { formatCountdown, useOraCorrente } from '../lib/countdown'
import type { Membership } from '../types'
import { GameNav, type GameView } from './GameNav'

type Props = { membership: Membership; onNavigate: (view: GameView) => void }

type Prospetto = { id: number; nome: string; posizioni: string[]; overall: number; potential: number; eta: number }
type Asta = { id: number; player_id: number; giorno: string; stato: 'aperta' | 'assegnata' | 'deserta'; vincitore_team_id: number | null; ingaggio_finale: number | null }
type Offerta = { id: number; auction_id: number; team_id: number; ingaggio_offerto: number }

function milioni(euro: number) { return `${(euro / 1_000_000).toFixed(1).replace('.', ',')} M€` }

function minutiDalMezzanotteRoma() {
  const [ore, minuti] = new Intl.DateTimeFormat('it-IT', {
    timeZone: 'Europe/Rome', hour: '2-digit', minute: '2-digit', hour12: false,
  }).format(new Date()).split(':').map(Number)
  return ore * 60 + minuti
}
function mercatoAperto() {
  const ora = minutiDalMezzanotteRoma()
  return ora >= 23 * 60 + 30 || ora < 21 * 60
}

export function Under({ membership, onNavigate }: Props) {
  const league = membership.league!
  const dati = useSeasonData(membership)
  const adesso = useOraCorrente()
  const [aste, setAste] = useState<Asta[]>([])
  const [prospetti, setProspetti] = useState<Map<number, Prospetto>>(new Map())
  const [mieOfferte, setMieOfferte] = useState<Map<number, number>>(new Map())
  const [caricamento, setCaricamento] = useState(true)
  const [bozza, setBozza] = useState<Record<number, string>>({})
  const [inCorso, setInCorso] = useState(false)
  const [azioneInCorso, setAzioneInCorso] = useState<number | null>(null)
  const [esito, setEsito] = useState<string | null>(null)

  const carica = useCallback(async () => {
    const [asteResult, offerteResult] = await Promise.all([
      supabase.from('under_auctions').select('id, player_id, giorno, stato, vincitore_team_id, ingaggio_finale')
        .eq('league_id', league.id).order('id', { ascending: false }).limit(60),
      supabase.from('under_bids').select('id, auction_id, team_id, ingaggio_offerto').eq('team_id', membership.id),
    ])
    const righeAste = (asteResult.data ?? []) as Asta[]
    setAste(righeAste)
    setMieOfferte(new Map((offerteResult.data ?? []).map((o: Offerta) => [o.auction_id, o.ingaggio_offerto])))
    const playerIds = [...new Set(righeAste.map((a) => a.player_id))]
    if (playerIds.length) {
      const { data: giocatori } = await supabase.from('players')
        .select('id, nome, posizioni, overall, potential, eta').in('id', playerIds)
      setProspetti(new Map((giocatori ?? []).map((g: Prospetto) => [g.id, g])))
    }
    setCaricamento(false)
  }, [league.id, membership.id])

  useEffect(() => { void carica() }, [carica])

  const ultimaPartitaIl = useMemo(() => dati.matches.reduce<number | null>((ultima, partita) => {
    const istante = new Date(partita.simulata_il).getTime()
    return ultima == null || istante > ultima ? istante : ultima
  }, null), [dati.matches])
  const prossimaPartitaIl = dati.fixtures.filter((f) => f.stato === 'programmata')
    .reduce<number | null>((prossima, f) => {
      const istante = new Date(f.data_sim).getTime()
      return prossima == null || istante < prossima ? istante : prossima
    }, null)
  const cicloDinamico = ultimaPartitaIl != null && prossimaPartitaIl != null
  const aperturaMercatoIl = ultimaPartitaIl == null ? null : ultimaPartitaIl + 30 * 60 * 1000
  const chiusuraMercatoIl = prossimaPartitaIl == null ? null : prossimaPartitaIl - 2 * 60 * 60 * 1000
  const mercatoDinamicoAperto = cicloDinamico && aperturaMercatoIl != null && chiusuraMercatoIl != null
    && adesso >= aperturaMercatoIl && adesso < chiusuraMercatoIl
  const aperto = cicloDinamico ? mercatoDinamicoAperto : mercatoAperto()
  const etichetta = cicloDinamico
    ? aperto ? `Mercato aperto · chiude tra ${formatCountdown(Math.max(0, (chiusuraMercatoIl ?? adesso) - adesso))}`
      : `Mercato chiuso · apre tra ${formatCountdown(Math.max(0, (aperturaMercatoIl ?? adesso) - adesso))}`
    : aperto ? 'Mercato aperto · chiude alle 21:00' : 'Mercato chiuso · apre alle 23:30'

  const giornoAste = aste[0]?.giorno ?? null
  const asteDelGiorno = aste.filter((a) => a.giorno === giornoAste && a.stato === 'aperta')
  const archivio = aste.filter((a) => a.stato !== 'aperta' || a.giorno !== giornoAste)

  async function offri(a: Asta) {
    const grezzo = bozza[a.id] ?? ''
    const valore = Math.round(Number(grezzo.replace(',', '.')) * 1_000_000)
    if (!grezzo || Number.isNaN(valore)) { setEsito('Ingaggio non valido.'); return }
    setAzioneInCorso(a.id); setInCorso(true); setEsito(null)
    const { error } = await supabase.rpc('offri_per_under', { p_auction_id: a.id, p_ingaggio: valore })
    setAzioneInCorso(null); setInCorso(false)
    if (error) { setEsito(error.message); return }
    setEsito('Offerta registrata. Si apre alle 21:00.')
    setBozza((b) => ({ ...b, [a.id]: '' }))
    await carica()
  }

  async function ritira(a: Asta) {
    setAzioneInCorso(a.id); setInCorso(true); setEsito(null)
    const { error } = await supabase.rpc('ritira_offerta_under', { p_auction_id: a.id })
    setAzioneInCorso(null); setInCorso(false)
    if (error) { setEsito(error.message); return }
    await carica()
  }

  return <main className="app-shell season-shell">
    <GameNav league={league} active="under" onNavigate={onNavigate} />
    <header className="topbar season-topbar">
      <div className="brand-lockup brand-lockup--dark"><img src="/specialone-mark.svg" alt="" /><span>SpecialOne</span></div>
      <span>Mercato UNDER</span>
    </header>

    <div className="season-page season-page--narrow">
      <section className="season-title-row">
        <div>
          <p className="kicker">{league.nome}</p>
          <h1>Mercato UNDER.</h1>
          <p>
            Giovani promesse di 15 anni per il vivaio, generate ogni giorno. Overall vero, potenziale mostrato come
            fascia — si stringe salendo di livello VIVAIO in Gestione risorse. Asta a busta chiusa come i
            svincolati, ma fuori dal conteggio rosa: minimo 0,1 M€.
          </p>
        </div>
        <span className={`mercato-finestra ${aperto ? 'e-aperto' : ''}`}>{etichetta}</span>
      </section>

      {esito && <p className={`notice ${esito.startsWith('Offerta registrata') ? 'notice--success' : 'notice--error'}`}>{esito}</p>}

      {caricamento ? <p className="season-empty">Carico il mercato UNDER…</p>
        : asteDelGiorno.length === 0 ? <p className="season-empty">Nessuna estrazione ancora oggi.</p>
        : <div className="free-agent-lista">
            {asteDelGiorno.map((a) => {
              const g = prospetti.get(a.player_id)
              const macro: MacroRuolo = macroRuolo(g?.posizioni ?? [])
              const mia = mieOfferte.get(a.id)
              return <article className="free-agent-card is-compact" key={a.id}>
                <div className="free-agent-card__portrait"><span aria-hidden="true">{g?.nome.charAt(0) ?? '?'}</span><b>{g?.overall ?? '—'}</b></div>
                <div className="free-agent-card__body">
                  <header><span className={`role-pill role-pill--${macro.toLowerCase()}`} style={{ background: MACRO_COLORE[macro] }}>{g?.posizioni?.[0] ?? '—'}</span><small>{MACRO_LABEL[macro]}</small></header>
                  <strong>{g?.nome ?? `#${a.player_id}`}</strong>
                  <p>15 anni · potenziale in valutazione</p>
                  <footer><em>Ingaggio minimo 0,1 M€</em></footer>
                </div>
                <div className={`free-agent-card__bid${!aperto ? ' is-mercato-chiuso' : ''}`}>
                  <input type="text" inputMode="decimal" disabled={!aperto}
                    placeholder={mia ? (mia / 1_000_000).toFixed(1).replace('.', ',') : 'M€'}
                    value={bozza[a.id] ?? ''}
                    onChange={(e) => setBozza({ ...bozza, [a.id]: e.target.value })} />
                  <div className="free-agent-card__bid-azioni">
                    <button className="button button--secondary" type="button" disabled={inCorso || !aperto} onClick={() => void offri(a)}>
                      {azioneInCorso === a.id ? 'Invio…' : !aperto ? 'Chiuso' : mia ? 'Modifica' : 'Offri'}
                    </button>
                    {mia !== undefined && <button className="button button--danger-ghost" type="button" disabled={inCorso || !aperto} onClick={() => void ritira(a)}>Ritira</button>}
                  </div>
                  {mia && <small>Hai offerto {milioni(mia)}</small>}
                </div>
              </article>
            })}
          </div>}

      {archivio.length > 0 && <section className="mercato-blocco">
        <div className="sezione-testa"><div><p className="kicker">Archivio</p><h2>Estrazioni precedenti</h2></div></div>
        <ul className="mercato-aste">
          {archivio.slice(0, 20).map((a) => {
            const g = prospetti.get(a.player_id)
            return <li key={a.id} className="e-chiusa">
              <b>{g?.overall ?? '—'}</b>
              <span><strong>{g?.nome ?? `#${a.player_id}`}</strong><small>{a.giorno}</small></span>
              <em className={a.stato === 'assegnata' ? 'e-presa' : ''}>
                {a.stato === 'assegnata' ? `Assegnato · ${milioni(a.ingaggio_finale ?? 0)}` : a.stato === 'deserta' ? 'Deserta' : 'Aperta'}
              </em>
            </li>
          })}
        </ul>
      </section>}
    </div>
  </main>
}
