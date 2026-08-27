import { useEffect, useMemo, useState } from 'react'
import { supabase } from '../lib/supabase'
import { cognome } from '../lib/nomi'
import { MACRO_LABEL, macroRuolo, type MacroRuolo } from '../lib/ruoli'
import { formatCountdown, useOraCorrente } from '../lib/countdown'
import type { League, Membership, SceltaDraft } from '../types'
import { GameNav, type GameView } from './GameNav'
import { SeasonState } from './SeasonUI'
import { Crest } from './Crest'
import { useSeasonData } from '../lib/useSeasonData'

type Props = { membership: Membership; onNavigate: (view: GameView) => void }

const ETICHETTA_FINESTRA: Record<SceltaDraft['finestra'], string> = { on: 'ON-Season', off: 'OFF-Season' }
const ETICHETTA_STATO: Record<SceltaDraft['stato'], string> = {
  futura: 'Posizione da determinare',
  determinata: 'Pronta',
  usata: 'Usata',
  vuota: 'Andata a vuoto',
}

type GiocatorePool = { id: number; nome: string; club: string; posizioni: string[]; overall: number; eta: number }

// Le 13:00 di Roma dello stesso giorno solare di una data ISO, robusto al
// cambio ora legale/solare: si prova prima il candidato in CET poi in CEST
// e si tiene quello che l'orologio di Roma legge davvero come 13:00.
function alle13RomaStessoGiorno(dataIso: string): Date {
  const giorno = new Intl.DateTimeFormat('en-CA', { timeZone: 'Europe/Rome', year: 'numeric', month: '2-digit', day: '2-digit' }).format(new Date(dataIso))
  for (const scarto of [1, 2]) {
    const candidato = new Date(`${giorno}T${String(13 - scarto).padStart(2, '0')}:00:00Z`)
    const oraRoma = new Intl.DateTimeFormat('en-GB', { timeZone: 'Europe/Rome', hour: '2-digit', minute: '2-digit', hour12: false }).format(candidato)
    if (oraRoma === '13:00') return candidato
  }
  return new Date(`${giorno}T13:00:00Z`)
}

export function Scelte({ membership, onNavigate }: Props) {
  const league = membership.league as League
  const dati = useSeasonData(membership)
  const adesso = useOraCorrente()
  const [scelte, setScelte] = useState<SceltaDraft[]>([])
  const [pool, setPool] = useState<GiocatorePool[]>([])
  const [filtroRuolo, setFiltroRuolo] = useState<MacroRuolo>('ALL')
  const [loading, setLoading] = useState(true)
  const [errore, setErrore] = useState<string | null>(null)

  useEffect(() => {
    let vivo = true
    async function carica() {
      setLoading(true)
      const [sceltaRes, giocatoriRes, istanzeRes, ritiratiRes] = await Promise.all([
        supabase.from('scelte_draft').select('*').eq('league_id', league.id).order('stagione').order('finestra'),
        supabase.from('players').select('id, nome, club, posizioni, overall, eta').gt('overall', 75).in('campionato', league.campionati_attivi),
        supabase.from('player_instances').select('player_id').eq('league_id', league.id).not('team_id', 'is', null),
        supabase.from('retired_players').select('player_id').eq('league_id', league.id),
      ])
      if (!vivo) return
      const primoErrore = sceltaRes.error ?? giocatoriRes.error ?? istanzeRes.error ?? ritiratiRes.error
      if (primoErrore) { setErrore(primoErrore.message); setLoading(false); return }
      const occupati = new Set([
        ...(istanzeRes.data ?? []).map((r) => r.player_id),
        ...(ritiratiRes.data ?? []).map((r) => r.player_id),
      ])
      setScelte((sceltaRes.data ?? []) as SceltaDraft[])
      setPool(((giocatoriRes.data ?? []) as GiocatorePool[])
        .filter((g) => !occupati.has(g.id))
        .sort((a, b) => b.overall - a.overall))
      setLoading(false)
    }
    void carica()
    return () => { vivo = false }
  }, [league.id, league.campionati_attivi])

  const teamById = useMemo(() => new Map(dati.teams.map((t) => [t.id, t])), [dati.teams])
  const mieScelte = useMemo(
    () => scelte.filter((s) => s.team_proprietario_id === membership.id)
      .sort((a, b) => a.stagione - b.stagione || a.finestra.localeCompare(b.finestra)),
    [scelte, membership.id],
  )
  const poolFiltrato = useMemo(
    () => pool.filter((g) => filtroRuolo === 'ALL' || macroRuolo(g.posizioni) === filtroRuolo),
    [pool, filtroRuolo],
  )

  // Finestra ON-Season: si apre a giornata ⌊totali/2⌋ (appena giocata la
  // precedente) e scade alle 13:00 del giorno in cui si gioca quella
  // giornata (10h prima della simulazione, docs/decisioni-draft-picks.md
  // deciso il 27/8 in chat). Nessuna finestra prima della stagione 2: le
  // scelte partono da li' (§3.2).
  const giornataMezza = dati.giornateStagione ? Math.floor(dati.giornateStagione / 2) : null
  const fixtureMezza = giornataMezza
    ? dati.fixtures.find((f) => f.giornata === giornataMezza && f.bracket_tie_id == null)
    : null
  const onSeasonVisibile = league.stagione_corrente >= 2 && league.fase_carriera !== 'offseason'
    && fixtureMezza != null && dati.currentGiornata === giornataMezza
  const onSeasonScadenza = fixtureMezza ? alle13RomaStessoGiorno(fixtureMezza.data_sim) : null

  // Finestra OFF-Season: usa la stessa scadenza dell'off-season vera e
  // propria (leagues.offseason_fine, sempre 24h dall'apertura — trigger
  // offseasons_durata_un_giorno). Non è una finestra separata: è l'ultima
  // fase dell'off-season stessa.
  const offSeasonVisibile = league.fase_carriera === 'offseason' && league.offseason_fine != null
  const offSeasonScadenza = league.offseason_fine ? new Date(league.offseason_fine) : null

  const finestraAttiva = offSeasonVisibile
    ? { label: `OFF-Season ${league.stagione_corrente + 1}`, scadenza: offSeasonScadenza! }
    : onSeasonVisibile
      ? { label: `ON-Season ${league.stagione_corrente}`, scadenza: onSeasonScadenza! }
      : null

  return <main className="app-shell season-shell">
    <GameNav league={league} active="scelte" onNavigate={onNavigate} />
    <header className="topbar season-topbar">
      <div className="brand-lockup brand-lockup--dark"><img src="/specialone-mark.svg" alt="" /><span>SpecialOne</span></div>
      <span>Draft</span>
    </header>
    <div className="season-page season-page--narrow">
      <section className="help-heading">
        <p className="kicker">{league.nome}</p>
        <h1>Draft.</h1>
        <p>
          Ogni ticket rappresenta una scelta in un mercato ON-Season o OFF-Season futuro. Lo
          stemma è sempre quello della squadra che l'ha guadagnata con il proprio piazzamento
          nei playoff — non cambia se la scelta viene scambiata, solo il proprietario cambia.
        </p>
      </section>

      {finestraAttiva
        ? <section className="offseason-card offseason-card--accent">
            <p className="kicker">Finestra aperta</p>
            <h2>{finestraAttiva.label}</h2>
            <p className="scelte-countdown">{formatCountdown(Math.max(0, finestraAttiva.scadenza.getTime() - adesso))}</p>
            <p>Allo scadere del countdown i giocatori vengono attribuiti in base alle liste di preferenze.</p>
          </section>
        : <section className="offseason-card">
            <p className="kicker">Nessuna finestra aperta</p>
            <h2>Prossima finestra non ancora iniziata</h2>
            <p>L'ON-Season si apre a metà stagione, l'OFF-Season durante l'ultima fase dell'off-season.</p>
          </section>}

      <section className="offseason-card">
        <p className="kicker">In arrivo</p>
        <h2>Liste di preferenze</h2>
        <p>
          La sezione per indicare le preferenze sui giocatori del pool qui sotto (fino a N
          scelte, dove N è la posizione del ticket) arriva in un passo successivo: qui vedi
          già il pool reale e il countdown della finestra, ma non puoi ancora sottomettere una
          lista.
        </p>
      </section>

      {(dati.loading || loading || dati.error || errore) && <SeasonState loading={dati.loading || loading} error={dati.error ?? errore} onRetry={dati.reload} />}

      {!dati.loading && !loading && !dati.error && !errore && <>
      <section className="mercato-blocco">
        <div className="sezione-testa">
          <div><p className="kicker">Le mie scelte</p><h2>{mieScelte.length} ticket</h2></div>
        </div>
        {mieScelte.length === 0
          ? <p className="season-empty">Nessuna scelta ancora assegnata a questa squadra.</p>
          : <ul className="scelte-lista">
              {mieScelte.map((s) => {
                const origine = teamById.get(s.team_origine_id)
                return <li className="scelta-ticket" key={s.id}>
                  <div className="scelta-ticket__origine">
                    <Crest value={origine?.stemma_url ?? null} imageUrl={origine ? dati.crestUrlByTeamId.get(origine.id) : undefined} />
                    <small>{origine?.nome ?? 'Squadra sconosciuta'}</small>
                  </div>
                  <div className="scelta-ticket__info">
                    <strong>S{s.stagione} · {ETICHETTA_FINESTRA[s.finestra]}</strong>
                    <span>{s.posizione != null ? `${s.posizione}ª scelta` : ETICHETTA_STATO[s.stato]}</span>
                  </div>
                  <div className={`scelta-ticket__stato scelta-ticket__stato--${s.stato}`}>{ETICHETTA_STATO[s.stato]}</div>
                </li>
              })}
            </ul>}
      </section>

      <section className="mercato-blocco">
        <div className="sezione-testa">
          <div><p className="kicker">Overall &gt; 75</p><h2>Pool del mercato a scelte</h2></div>
          <small>{poolFiltrato.length} giocatori</small>
        </div>
        <nav className="free-agent-ruoli" aria-label="Ruolo del pool">
          {(['ALL', 'GK', 'DEF', 'MID', 'ATT'] as MacroRuolo[]).map((r) => <button
            key={r} type="button" className={filtroRuolo === r ? 'is-attivo' : ''}
            onClick={() => setFiltroRuolo(r)}
          >
            <span>{r === 'ALL' ? 'Tutti' : MACRO_LABEL[r]}</span><b>{pool.filter((g) => r === 'ALL' || macroRuolo(g.posizioni) === r).length}</b>
          </button>)}
        </nav>
        {poolFiltrato.length === 0
          ? <p className="season-empty">Nessun giocatore libero con questi filtri.</p>
          : <ul className="scelte-pool">
              {poolFiltrato.map((g) => <li key={g.id}>
                <b>{g.overall}</b>
                <span><strong>{cognome(g.nome)}</strong><small>{g.club} · {(g.posizioni ?? []).join(' / ')} · {g.eta} anni</small></span>
              </li>)}
            </ul>}
      </section>
      </>}
    </div>
  </main>
}
