import { useCallback, useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'
import type { useSeasonData } from '../lib/useSeasonData'
import { Crest } from './Crest'
import { Casino, Contatore, fmt } from './Casino'
import { CrazyOne } from './CrazyOne'
import { AviatOne } from './AviatOne'
import { BlackjackOne } from './BlackjackOne'

// Pagina iniziale del BetOne Casino': una fila di copertine verticali (stile home di Netflix), una per gioco.
// I crediti sono gli stessi per tutti i giochi; la classifica e' unica (miglior colpo in un solo giro, qualsiasi gioco).

type Dati = ReturnType<typeof useSeasonData>
type RigaClassifica = { team_id: number; miglior_colpo: number; spesi: number; profitto: number; giri: number; crediti: number | null }
type Vista = 'colpo' | 'spesi' | 'profitto'
type Filtro = 'tutti' | 'aviat' | 'crazy' | 'bj' | 'slot'
type Gioco = 'slot' | 'crazy' | 'aviat' | 'bj'
type Premio = { esito: 'vittoria' | 'pareggio' | 'sconfitta'; crediti: number; avversario_id: number }

// Le locandine (public/casino/*.webp, 540×810) le ha disegnate il committente; il nome del gioco e' gia' nell'immagine.
const GIOCHI: Array<{ id: Gioco; titolo: string; sotto: string; nuovo?: boolean }> = [
  { id: 'aviat', titolo: 'AviatOne', sotto: 'Incassa prima che voli via' },
  { id: 'bj', titolo: 'BlackjackOne', sotto: 'Batti il banco senza sballare' },
  { id: 'crazy', titolo: 'CrazyOne', sotto: 'Ruota · 4 bonus' },
  { id: 'slot', titolo: 'SlotOne', sotto: '5 rulli · 10 linee' },
]

type Props = { leagueId: number; teamId: number; dati: Dati }

export function CasinoHub({ leagueId, teamId, dati }: Props) {
  const [gioco, setGioco] = useState<Gioco | null>(null)
  const [crediti, setCrediti] = useState<number | null>(null)
  const [classifica, setClassifica] = useState<RigaClassifica[]>([])
  const [vista, setVista] = useState<Vista>('colpo')
  const [filtro, setFiltro] = useState<Filtro>('tutti')
  const [errore, setErrore] = useState('')
  const [crazyone, setCrazyone] = useState(false)
  const [aviatone, setAviatone] = useState(false)
  const [blackjack, setBlackjack] = useState(false)
  const [premi, setPremi] = useState<Premio[]>([])
  // Una bustina di figurine gratis ogni 500 crediti spesi (dal 21/10/2026): avanzamento verso la prossima e bustine da aprire.
  const [bustina, setBustina] = useState<{ spesi: number; gratis: number } | null>(null)

  const carica = useCallback(async () => {
    const { data, error } = await supabase.rpc('casino_stato', { p_league_id: leagueId })
    if (error) { setErrore(error.message); return }
    setCrediti((data as { crediti: number }).crediti)
    setCrazyone((data as { crazyone?: boolean }).crazyone === true)
    setAviatone((data as { aviatone?: boolean }).aviatone === true)
    setBlackjack((data as { blackjack?: boolean }).blackjack === true)
    const st = data as { album?: boolean; bustina_spesi?: number; bustine_gratis?: number }
    setBustina(st.album && st.bustina_spesi != null ? { spesi: st.bustina_spesi, gratis: st.bustine_gratis ?? 0 } : null)
    // Premi partita appena pagati (solo partite gia' viste o vecchie di 24 ore: niente spoiler). Restano a schermo finche' non si chiudono.
    const nuovi = ((data as { premi?: Premio[] }).premi ?? [])
    if (nuovi.length) setPremi((p) => [...p, ...nuovi])

  }, [leagueId])
  useEffect(() => { if (gioco == null) void carica() }, [carica, gioco])

  // Classifica del casino': miglior colpo, crediti spesi o profitto, per tutti i giochi (predefinito) o per uno solo.
  const aggiornaClassifica = useCallback(() => {
    void supabase.rpc('casino_classifica_giochi', { p_league_id: leagueId, p_gioco: filtro === 'tutti' ? null : filtro })
      .then(({ data: cl }) => setClassifica((cl ?? []) as RigaClassifica[]))
  }, [leagueId, filtro])
  useEffect(() => { if (gioco == null) aggiornaClassifica() }, [aggiornaClassifica, gioco])
  const ordinata = [...classifica].sort((a, b) => vista === 'colpo' ? b.miglior_colpo - a.miglior_colpo : vista === 'spesi' ? b.spesi - a.spesi : b.profitto - a.profitto)
  const filtri: Array<[Filtro, string]> = [['tutti', 'Tutti'], ...(aviatone ? [['aviat', 'AviatOne'] as [Filtro, string]] : []), ...(crazyone ? [['crazy', 'CrazyOne'] as [Filtro, string]] : []),
    ...(blackjack ? [['bj', 'BlackjackOne'] as [Filtro, string]] : []), ['slot', 'SlotOne']]
  const tabellaClassifica = <>
  <section className="slot-classifica">
    <h2>Classifica del casinò</h2>
    <div className="bet-tab bet-tab--piccola" role="tablist" aria-label="Classifica">
      {([['colpo', 'Miglior colpo'], ['spesi', 'Crediti spesi'], ['profitto', 'Profitto']] as const).map(([k, l]) => <button key={k} type="button" role="tab" aria-selected={vista === k} className={vista === k ? 'is-attiva' : ''} onClick={() => setVista(k)}>{l}</button>)}
    </div>
    <div className="cas-filtri" role="group" aria-label="Gioco">
      {filtri.map(([k, l]) => <button key={k} type="button" aria-pressed={filtro === k} className={filtro === k ? 'is-attivo' : ''} onClick={() => setFiltro(k)}>{l}</button>)}
    </div>
    <p className="bet-nota">{vista === 'colpo' ? 'La vincita più alta ottenuta in un solo giro.' : vista === 'spesi' ? 'Tutti i crediti puntati.' : 'Crediti vinti meno crediti puntati.'}{filtro === 'tutti' ? ' Tutti i giochi.' : ''}</p>
    {ordinata.length === 0 ? <p className="bet-nota">Ancora nessuno al tavolo.</p> : <ol>
      {ordinata.map((r, i) => {
        const t = dati.teamById.get(r.team_id)
        const valore = vista === 'colpo' ? r.miglior_colpo : vista === 'spesi' ? r.spesi : r.profitto
        return <li key={r.team_id} className={r.team_id === teamId ? 'is-mia' : ''}>
          <span className={`bet-pos${i < 3 ? ` bet-pos--${i + 1}` : ''}`}>{i + 1}</span>
          <span className="bet-giocatori__stemma"><Crest value={t?.stemma_url ?? null} imageUrl={dati.crestUrlByTeamId.get(r.team_id)} size="small" /></span>
          <span className="bet-classifica__nome"><strong>{t?.nome ?? '—'}</strong><small>{r.crediti != null ? `${fmt(r.crediti)} crediti · ` : ''}{fmt(r.giri)} giri</small></span>
          <span className={`slot-classifica__crediti${vista === 'profitto' ? (valore >= 0 ? ' is-positivo' : ' is-negativo') : ''}`}><b>{vista === 'profitto' && valore > 0 ? '+' : ''}{fmt(valore)}</b><small>{vista === 'colpo' ? 'miglior colpo' : vista === 'spesi' ? 'spesi' : 'profitto'}</small></span>
        </li>
      })}
    </ol>}
  </section>
  </>

  if (crediti == null) return <section className="slot-caricamento">{errore ? <p role="alert">{errore}</p> : <p>Accendo le luci del casinò…</p>}</section>
  // Dove CrazyOne e' spento il casino' resta com'era: la slot subito, con la classifica sotto.
  if (!crazyone && !aviatone && !blackjack) return <section className="cas-hub"><Casino leagueId={leagueId} dati={dati} onGiro={aggiornaClassifica} />{tabellaClassifica}</section>

  if (gioco) return <section className="cas-gioco">
    <button type="button" className="cas-indietro" onClick={() => setGioco(null)}><span aria-hidden="true">‹</span> Casinò</button>
    {gioco === 'slot' ? <Casino leagueId={leagueId} dati={dati} /> : gioco === 'aviat' ? <AviatOne leagueId={leagueId} dati={dati} /> : gioco === 'bj' ? <BlackjackOne leagueId={leagueId} dati={dati} /> : <CrazyOne leagueId={leagueId} dati={dati} />}
  </section>

  return <section className="cas-hub">
    <div className="slot-saldo">
      <div><small>I tuoi crediti</small><strong><Contatore valore={crediti} /></strong></div>
      <span className="slot-ricarica">+1.000 gratis alle 23:00</span>
    </div>
    {errore && <p className="slot-errore" role="alert">{errore}</p>}
    {bustina && <div className="cas-bustina">
      <div className="cas-bustina__testo"><b>Bustina di figurine</b><span>{fmt(bustina.spesi)} / 500 crediti spesi</span></div>
      <div className="cas-bustina__barra" role="progressbar" aria-valuemin={0} aria-valuemax={500} aria-valuenow={bustina.spesi}><i style={{ width: `${Math.min(100, bustina.spesi / 5)}%` }} /></div>
      <small>{bustina.gratis > 0 ? `Hai ${bustina.gratis} ${bustina.gratis === 1 ? 'bustina gratis' : 'bustine gratis'} da aprire nell'Album.` : 'Ogni 500 crediti giocati al casinò ricevi una bustina gratis per l\'Album.'}</small>
    </div>}
    {premi.length > 0 && <div className="cas-premi" role="status">
      <div className="cas-premi__testa"><b>Premi partita</b><button type="button" aria-label="Chiudi" onClick={() => setPremi([])}>✕</button></div>
      {premi.map((p, i) => <p key={i}><span>{p.esito === 'vittoria' ? 'Vittoria' : p.esito === 'pareggio' ? 'Pareggio' : 'Sconfitta'} contro {dati.teamById.get(p.avversario_id)?.nome ?? '—'}</span><strong>+{fmt(p.crediti)}</strong></p>)}
    </div>}

    <section className="cas-fila">
      <h2>Giochi</h2>
      <div className="cas-fila__scorri">
        {GIOCHI.filter((g) => (g.id !== 'crazy' || crazyone) && (g.id !== 'aviat' || aviatone) && (g.id !== 'bj' || blackjack)).map((g) => <button key={g.id} type="button" className={`cas-poster cas-poster--${g.id}`} aria-label={`${g.titolo}: ${g.sotto}`} onClick={() => setGioco(g.id)}>
          <img className="cas-poster__locandina" src={`/casino/${{ slot: 'slotone', crazy: 'crazyone', aviat: 'aviatone', bj: 'blackjackone' }[g.id]}.webp`} alt="" decoding="async" />
          {g.nuovo && <span className="cas-poster__nuovo">Nuovo</span>}
          <span className="cas-poster__titolo"><small>{g.sotto}</small></span>
        </button>)}
        <div className="cas-poster cas-poster--presto" aria-label="Altri giochi in arrivo">
          <span className="cas-poster__presto">Prossimamente</span>
        </div>
      </div>
    </section>

    {tabellaClassifica}
  </section>
}
