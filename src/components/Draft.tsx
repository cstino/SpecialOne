import { useEffect, useRef, useState } from 'react'
import { motion } from 'motion/react'
import type { User } from '@supabase/supabase-js'
import { supabase } from '../lib/supabase'
import { MACRO_LABEL, ORDINE_MACRO_RUOLO, macroRuolo, type MacroRuolo } from '../lib/ruoli'
import type { League, Membership } from '../types'
import { GameNav } from './GameNav'
import type { GameView } from './GameNav'

type DraftTeamState = {
  pick_numero: number
  stato: 'in_corso' | 'concluso'
  carta_gk: number | null
  carta_def: number | null
  carta_mid: number | null
  carta_att: number | null
}
type DraftCard = {
  ruolo: MacroRuolo
  id: number
  nome: string
  club: string
  campionato: string
  overall: number
  eta: number
  posizioni: string[]
  foto_url: string | null
  ingaggio: number
  ingaggiabile: boolean
}
type DraftPacchetto = {
  league_id: number
  team_id: number
  pick_numero: number
  stato: 'in_corso' | 'concluso'
  reroll_rimasti: number
  budget: number
  slot_occupati: number
  carte: DraftCard[]
}
type RosterPlayer = {
  id: number
  nome: string
  club: string
  overall: number
  eta: number
  posizioni: string[]
  foto_url: string | null
  ingaggio: number
}
type DraftProps = { user: User; membership: Membership; onNavigate: (view: GameView) => void }

const NOME_RUOLO: Record<DraftCard['ruolo'], string> = {
  ALL: '',
  GK: 'Portiere',
  DEF: 'Difensore',
  MID: 'Centrocampista',
  ATT: 'Attaccante',
}

// Nomi decorativi per la fase di rotazione del pacchetto: mai reali, servono
// solo alla suspense visiva. Cambiano troppo in fretta per essere letti.
const NOMI_SPIN = [
  'Álvarez', 'Petrov', 'Nakamura', 'Diallo', 'Larsson', 'Okafor', 'Silva', 'Kowalski',
  'Hansen', 'Bianchi', 'Novák', 'Andersen', 'Ferreira', 'Yılmaz', 'Costa', 'Mendes',
  'Schulz', 'Kovač', 'Rossi', 'Aguilar', 'Dubois', 'Ibrahim', 'Santos', 'Wagner',
]

function milioni(euro: number) {
  return `${(euro / 1_000_000).toFixed(1).replace('.', ',')} M€`
}

async function firmaFoto(path: string | null | undefined): Promise<string | undefined> {
  if (!path) return undefined
  const { data } = await supabase.storage.from('player-photos').createSignedUrl(path, 3600)
  return data?.signedUrl
}

export function Draft({ user, membership, onNavigate }: DraftProps) {
  const league = membership.league as League
  const [state, setState] = useState<DraftTeamState | null>(null)
  const [payload, setPayload] = useState<DraftPacchetto | null>(null)
  const [fotoCarte, setFotoCarte] = useState<Map<number, string>>(new Map())
  const [selezionati, setSelezionati] = useState<number[]>([])
  const [fase, setFase] = useState<'idle' | 'girando' | 'rivelato'>('idle')
  const [budgetAttuale, setBudgetAttuale] = useState<number>(membership.budget)
  const [rosaAperta, setRosaAperta] = useState(false)
  const [loading, setLoading] = useState(true)
  const [pending, setPending] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [refresh, setRefresh] = useState(0)
  const spinRef = useRef<number | null>(null)
  const [nomiSpin, setNomiSpin] = useState<string[]>(['', '', '', ''])

  useEffect(() => {
    let active = true
    async function load() {
      setLoading(true); setError(null); setSelezionati([])
      const [{ data: teamState, error: stateError }, { data: team }] = await Promise.all([
        supabase.from('draft_team_state').select('*').eq('team_id', membership.id).maybeSingle(),
        supabase.from('teams').select('budget').eq('id', membership.id).maybeSingle(),
      ])
      if (!active) return
      if (team) setBudgetAttuale(team.budget)
      if (stateError || !teamState) { setError(stateError?.message ?? 'Stato del tuo draft non disponibile.'); setLoading(false); return }
      const nextState = teamState as DraftTeamState
      setState(nextState)
      if (nextState.carta_gk !== null && nextState.stato === 'in_corso') {
        const result = await supabase.rpc('draft_apri_pacchetto', { p_league_id: league.id })
        if (!active) return
        if (result.error) setError(result.error.message)
        else {
          const dati = result.data as DraftPacchetto
          setPayload(dati)
          setFase('rivelato')
          setFotoCarte(await firmaTutte(dati.carte))
        }
      } else { setPayload(null); setFase('idle') }
      setLoading(false)
    }
    void load()
    return () => { active = false; if (spinRef.current) window.clearInterval(spinRef.current) }
  }, [league.id, membership.id, refresh])

  async function firmaTutte(carte: DraftCard[]) {
    const voci = await Promise.all(carte.map(async (c) => [c.id, await firmaFoto(c.foto_url)] as const))
    return new Map(voci.filter((v): v is [number, string] => Boolean(v[1])))
  }

  function avviaRotazione(dati: DraftPacchetto) {
    setPayload(dati)
    setFase('girando')
    setSelezionati([])
    if (spinRef.current) window.clearInterval(spinRef.current)
    spinRef.current = window.setInterval(() => {
      setNomiSpin([0, 1, 2, 3].map(() => NOMI_SPIN[Math.floor(Math.random() * NOMI_SPIN.length)]))
    }, 65)
    window.setTimeout(async () => {
      if (spinRef.current) { window.clearInterval(spinRef.current); spinRef.current = null }
      setFase('rivelato')
      setFotoCarte(await firmaTutte(dati.carte))
    }, 1000)
  }

  async function apriPacchetto() {
    setPending(true); setError(null)
    const result = await supabase.rpc('draft_apri_pacchetto', { p_league_id: league.id })
    if (result.error) setError(result.error.message)
    else avviaRotazione(result.data as DraftPacchetto)
    setPending(false)
  }

  async function reroll() {
    setPending(true); setError(null)
    const result = await supabase.rpc('draft_pacchetto_reroll', { p_league_id: league.id })
    if (result.error) setError(result.error.message)
    else avviaRotazione(result.data as DraftPacchetto)
    setPending(false)
  }

  function toggleCarta(carta: DraftCard) {
    if (!carta.ingaggiabile || fase !== 'rivelato') return
    setSelezionati((attuali) => {
      if (attuali.includes(carta.id)) return attuali.filter((id) => id !== carta.id)
      if (attuali.length >= 2) return attuali
      return [...attuali, carta.id]
    })
  }

  async function confermaScelta() {
    if (selezionati.length !== 2) return
    setPending(true); setError(null)
    const result = await supabase.rpc('draft_scegli_pacchetto', {
      p_league_id: league.id,
      p_player_id_1: selezionati[0],
      p_player_id_2: selezionati[1],
    })
    if (result.error) setError(result.error.message)
    else { setPayload(null); setFase('idle'); setSelezionati([]); setRefresh((value) => value + 1) }
    setPending(false)
  }

  if (loading) return <main className="loading-screen"><img className="loading-mark" src="/specialone-mark.svg" alt="" /><p>Apro il pacchetto…</p></main>
  if (error && !state) return <main className="fatal-state"><h1>Draft non disponibile</h1><p>{error}</p></main>

  const picks = state?.pick_numero ?? 0
  const total = league.slot_rosa
  const tetto = Math.round(league.budget_iniziale * 0.8)
  const speso = league.budget_iniziale - budgetAttuale
  const disponibile = Math.max(0, tetto - speso)
  const progressoSpesa = tetto > 0 ? Math.min(100, (speso / tetto) * 100) : 0

  return (
    <main className="app-shell draft-shell">
      <GameNav league={league} active="draft" onNavigate={onNavigate} />
      <header className="topbar"><div className="brand-lockup brand-lockup--dark"><img src="/specialone-mark.svg" alt="" /><span>SpecialOne</span></div><span className="user-email">{user.email}</span></header>
      <section className="draft-hero">
        <div><p className="kicker">Draft a pacchetti · {league.nome}</p><h1>{state?.stato === 'concluso' ? 'Rosa completa.' : 'Scegli bene.'}</h1><p>La tua squadra è al pacchetto {Math.min(Math.floor(picks / 2) + 1, total / 2)} su {total / 2}. Le altre squadre possono draftare contemporaneamente.</p></div>
        <button className="draft-turn-board draft-turn-board--clickable" type="button" onClick={() => setRosaAperta(true)}>
          <span>La tua squadra</span>
          <strong>{membership.nome}</strong>
          <small>{state?.stato === 'concluso' ? 'Draft completato' : `${picks} / ${total} giocatori`}</small>
          <div className="draft-budget">
            <div className="draft-budget__bar"><div className="draft-budget__fill" style={{ width: `${progressoSpesa}%` }} /></div>
            <div className="draft-budget__cifre"><span>{milioni(speso)} speso</span><span>{milioni(disponibile)} disponibile</span></div>
            <small>Tetto draft: 80% del budget ({milioni(tetto)} su {milioni(league.budget_iniziale)})</small>
          </div>
          <span className="draft-turn-board__hint">Tocca per vedere la rosa →</span>
        </button>
      </section>
      {error && <p className="notice notice--error" role="alert">{error}</p>}
      {state?.stato !== 'concluso' && fase === 'idle' && (
        <section className="draft-action-panel">
          <p className="kicker">Il tuo prossimo pacchetto</p>
          <h2>Apri un pacchetto: 4 carte, una per ruolo.</h2>
          <p>Ne terrai 2, le altre 2 restano nel pool per tutti — anche per un tuo pacchetto futuro. Non devi aspettare nessuno.</p>
          <button className="button button--primary" type="button" disabled={pending} onClick={apriPacchetto}>APRI PACCHETTO</button>
        </section>
      )}
      {payload && state?.stato !== 'concluso' && (fase === 'girando' || fase === 'rivelato') && (
        <section className="draft-club-panel">
          <div className="section-heading-row">
            <div><p className="kicker">{fase === 'girando' ? 'Apertura in corso…' : 'Pacchetto aperto'}</p><h2>{fase === 'girando' ? 'Scouting il pool attivo.' : 'Scegli 2 carte su 4.'}</h2></div>
            <button className="button button--secondary" type="button" disabled={pending || fase === 'girando' || payload.reroll_rimasti < 1} onClick={reroll}>Reroll · {payload.reroll_rimasti}</button>
          </div>
          {fase === 'rivelato' && <p>Le carte non ingaggiabili sono in grigio: superano il tetto o lascerebbero la rosa insostenibile.</p>}
          <div className="draft-pacchetto-grid">
            {payload.carte.map((carta, indice) => (
              <div key={carta.ruolo} className={`draft-carta-slot draft-carta-slot--${carta.ruolo.toLowerCase()}`}>
                <span className={`draft-ruolo-badge draft-ruolo-badge--${carta.ruolo.toLowerCase()}`}>{NOME_RUOLO[carta.ruolo]}</span>
                {fase === 'girando' ? (
                  <div className="draft-carta draft-carta--spin">
                    <div className="draft-carta__foto draft-carta__foto--spin" aria-hidden="true" />
                    <strong className="draft-carta__nome-spin">{nomiSpin[indice]}</strong>
                    <span className="draft-carta__ovr-spin">{40 + Math.floor(Math.random() * 55)}</span>
                  </div>
                ) : (
                  <motion.button
                    type="button"
                    className={`draft-carta${selezionati.includes(carta.id) ? ' draft-carta--selezionata' : ''}`}
                    disabled={pending || !carta.ingaggiabile}
                    onClick={() => toggleCarta(carta)}
                    initial={{ opacity: 0, scale: 0.88, y: 8 }}
                    animate={{ opacity: 1, scale: 1, y: 0 }}
                    transition={{ type: 'spring', stiffness: 340, damping: 22, delay: indice * 0.08 }}
                  >
                    <div className="draft-carta__foto">
                      {fotoCarte.get(carta.id) ? <img src={fotoCarte.get(carta.id)} alt="" loading="lazy" /> : <span aria-hidden="true">{carta.nome.charAt(0)}</span>}
                      <b className="draft-carta__ovr">{carta.overall}</b>
                    </div>
                    <div className="draft-carta__info">
                      <strong>{carta.nome}</strong>
                      <small>{carta.club} · {carta.eta} anni</small>
                      <small className="draft-carta__posizioni">{carta.posizioni.join(' · ')}</small>
                    </div>
                    <div className="draft-carta__wage">
                      {(carta.ingaggio / 1_000_000).toFixed(1)} M€
                      <small>{!carta.ingaggiabile ? 'Non sostenibile' : selezionati.includes(carta.id) ? 'Selezionata ✓' : 'Tocca per scegliere'}</small>
                    </div>
                  </motion.button>
                )}
              </div>
            ))}
          </div>
          {fase === 'rivelato' && (
            <button className="button button--primary draft-conferma" type="button" disabled={pending || selezionati.length !== 2} onClick={confermaScelta}>
              Conferma scelta ({selezionati.length}/2)
            </button>
          )}
        </section>
      )}
      {state?.stato === 'concluso' && <section className="draft-action-panel"><p className="kicker">Draft concluso</p><h2>La rosa è pronta.</h2><p>Il prossimo passaggio sarà la scelta della formazione.</p></section>}
      {state?.stato !== 'concluso' && fase === 'idle' && !payload && <button className="text-button draft-refresh" type="button" onClick={() => setRefresh((value) => value + 1)}>Aggiorna stato</button>}
      {rosaAperta && <RosaModale league={league} membership={membership} onClose={() => setRosaAperta(false)} />}
    </main>
  )
}

function RosaModale({ league, membership, onClose }: { league: League; membership: Membership; onClose: () => void }) {
  const [giocatori, setGiocatori] = useState<RosterPlayer[]>([])
  const [foto, setFoto] = useState<Map<number, string>>(new Map())
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    let active = true
    async function load() {
      const { data: instances } = await supabase.from('player_instances')
        .select('id, player_id, ingaggio, overall_corrente, eta_corrente')
        .eq('league_id', league.id).eq('team_id', membership.id)
      const ids = (instances ?? []).map((i) => i.player_id)
      const { data: catalogo } = ids.length
        ? await supabase.from('players').select('id, nome, club, posizioni, foto_url').in('id', ids)
        : { data: [] }
      if (!active) return
      const byId = new Map((catalogo ?? []).map((p) => [p.id, p]))
      const elenco: RosterPlayer[] = (instances ?? []).map((i) => {
        const p = byId.get(i.player_id)
        return {
          id: i.id, ingaggio: i.ingaggio, overall: i.overall_corrente, eta: i.eta_corrente,
          nome: p?.nome ?? '—', club: p?.club ?? '—', posizioni: p?.posizioni ?? [], foto_url: p?.foto_url ?? null,
        }
      }).sort((a, b) => {
        const ra = ORDINE_MACRO_RUOLO.indexOf(macroRuolo(a.posizioni))
        const rb = ORDINE_MACRO_RUOLO.indexOf(macroRuolo(b.posizioni))
        return ra !== rb ? ra - rb : b.overall - a.overall
      })
      setGiocatori(elenco)
      const voci = await Promise.all(elenco.map(async (g) => [g.id, await firmaFoto(g.foto_url)] as const))
      if (!active) return
      setFoto(new Map(voci.filter((v): v is [number, string] => Boolean(v[1]))))
      setLoading(false)
    }
    void load()
    return () => { active = false }
  }, [league.id, membership.id])

  const speso = giocatori.reduce((somma, g) => somma + g.ingaggio, 0)

  return (
    <div className="modale-sfondo" role="dialog" aria-modal="true" onClick={onClose}>
      <div className="modale-rosa" onClick={(e) => e.stopPropagation()}>
        <div className="modale-rosa__testa">
          <div><p className="kicker">{membership.nome}</p><h2>{giocatori.length} / {league.slot_rosa} giocatori</h2><small>{milioni(speso)} di ingaggi complessivi</small></div>
          <button className="button-icona" type="button" onClick={onClose} aria-label="Chiudi">✕</button>
        </div>
        {loading ? <p className="empty-state">Carico la rosa…</p> : giocatori.length === 0 ? <p className="empty-state">Non hai ancora scelto giocatori.</p> : (
          <div className="modale-rosa__lista">
            {ORDINE_MACRO_RUOLO.map((ruolo) => {
              const delReparto = giocatori.filter((g) => macroRuolo(g.posizioni) === ruolo)
              if (delReparto.length === 0) return null
              return (
                <div className="modale-rosa__reparto" key={ruolo}>
                  <p className={`modale-rosa__reparto-titolo modale-rosa__reparto-titolo--${ruolo.toLowerCase()}`}>{MACRO_LABEL[ruolo]} · {delReparto.length}</p>
                  {delReparto.map((g) => (
                    <div className="modale-rosa__riga" key={g.id}>
                      <div className="draft-carta__foto draft-carta__foto--small">
                        {foto.get(g.id) ? <img src={foto.get(g.id)} alt="" loading="lazy" /> : <span aria-hidden="true">{g.nome.charAt(0)}</span>}
                        <b>{g.overall}</b>
                      </div>
                      <div><strong>{g.nome}</strong><small>{g.club} · {g.eta} anni</small></div>
                      <b className="modale-rosa__ingaggio">{(g.ingaggio / 1_000_000).toFixed(1)} M€</b>
                    </div>
                  ))}
                </div>
              )
            })}
          </div>
        )}
      </div>
    </div>
  )
}
