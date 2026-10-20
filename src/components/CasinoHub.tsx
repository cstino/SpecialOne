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
type RigaClassifica = { team_id: number; crediti: number; max_vincita: number; giri: number }
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
  const [errore, setErrore] = useState('')
  const [crazyone, setCrazyone] = useState(false)
  const [aviatone, setAviatone] = useState(false)
  const [blackjack, setBlackjack] = useState(false)
  const [premi, setPremi] = useState<Premio[]>([])

  const carica = useCallback(async () => {
    const { data, error } = await supabase.rpc('casino_stato', { p_league_id: leagueId })
    if (error) { setErrore(error.message); return }
    setCrediti((data as { crediti: number }).crediti)
    setCrazyone((data as { crazyone?: boolean }).crazyone === true)
    setAviatone((data as { aviatone?: boolean }).aviatone === true)
    setBlackjack((data as { blackjack?: boolean }).blackjack === true)
    // Premi partita appena pagati (solo partite gia' viste o vecchie di 24 ore: niente spoiler). Restano a schermo finche' non si chiudono.
    const nuovi = ((data as { premi?: Premio[] }).premi ?? [])
    if (nuovi.length) setPremi((p) => [...p, ...nuovi])
    const { data: cl } = await supabase.rpc('casino_classifica', { p_league_id: leagueId })
    setClassifica((cl ?? []) as RigaClassifica[])
  }, [leagueId])
  useEffect(() => { if (gioco == null) void carica() }, [carica, gioco])

  const aggiornaClassifica = () => { void supabase.rpc('casino_classifica', { p_league_id: leagueId }).then(({ data: cl }) => setClassifica((cl ?? []) as RigaClassifica[])) }
  const tabellaClassifica = <>
  <section className="slot-classifica">
    <h2>Classifica del casinò</h2>
    <p className="bet-nota">Conta la vincita più alta ottenuta in un solo giro{crazyone || aviatone ? ', in qualsiasi gioco' : ''}.</p>
    {classifica.length === 0 ? <p className="bet-nota">Ancora nessuno al tavolo.</p> : <ol>
      {classifica.map((r, i) => {
        const t = dati.teamById.get(r.team_id)
        return <li key={r.team_id} className={r.team_id === teamId ? 'is-mia' : ''}>
          <span className={`bet-pos${i < 3 ? ` bet-pos--${i + 1}` : ''}`}>{i + 1}</span>
          <span className="bet-giocatori__stemma"><Crest value={t?.stemma_url ?? null} imageUrl={dati.crestUrlByTeamId.get(r.team_id)} size="small" /></span>
          <span className="bet-classifica__nome"><strong>{t?.nome ?? '—'}</strong><small>{fmt(r.crediti)} crediti · {fmt(r.giri)} giri</small></span>
          <span className="slot-classifica__crediti"><b>{fmt(r.max_vincita)}</b><small>miglior colpo</small></span>
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
    {gioco === 'slot' ? <Casino leagueId={leagueId} dati={dati} /> : gioco === 'aviat' ? <AviatOne leagueId={leagueId} dati={dati} /> : gioco === 'bj' ? <BlackjackOne leagueId={leagueId} /> : <CrazyOne leagueId={leagueId} dati={dati} />}
  </section>

  return <section className="cas-hub">
    <div className="slot-saldo">
      <div><small>I tuoi crediti</small><strong><Contatore valore={crediti} /></strong></div>
      <span className="slot-ricarica">+1.000 gratis alle 23:00</span>
    </div>
    {errore && <p className="slot-errore" role="alert">{errore}</p>}
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
