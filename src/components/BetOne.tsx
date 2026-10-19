import { useCallback, useEffect, useMemo, useState } from 'react'
import { supabase } from '../lib/supabase'
import { useSeasonData } from '../lib/useSeasonData'
import type { League, Membership } from '../types'
import { Crest } from './Crest'
import { GameNav, type GameView } from './GameNav'
import { LoadingLogo } from './LoadingLogo'
import { Casino } from './Casino'

// BetOne (menu Extra campo, docs/decisioni-conferenze-stampa.md §BetOne): la schedina stile totocalcio della
// prossima giornata. 1, X o 2 per ogni partita, solo 2 doppie per schedina, una schedina per conferenza (East e
// West in Serie F). Si chiude 15 minuti prima della simulazione. Le schedine degli altri restano nascoste finche'
// non sono valutate. Una schedina perfetta e' una WIN: classifica per win, poi per partite azzeccate.

type Gruppo = 'est' | 'ovest' | 'tutte'
type Segno = '1' | 'X' | '2'
const SEGNI: Segno[] = ['1', 'X', '2']
const MAX_DOPPIE = 2
const MINUTI_CHIUSURA = 15

type Prono = { fixture_id: number; scelta: string; giusta: boolean | null }
type Schedina = {
  id: number; giornata: number; gruppo: Gruppo; team_id: number; user_id: string
  risolta_il: string | null; giuste: number | null; totale: number | null; perfetta: boolean | null
  betone_pronostici: Prono[]
}
type RigaClassifica = { team_id: number; wins: number; giuste: number; totale: number; schedine: number }

const NOME_GRUPPO: Record<Gruppo, string> = { est: 'East', ovest: 'West', tutte: 'Giornata' }

function useAdesso(ms = 1000) {
  const [adesso, setAdesso] = useState(() => Date.now())
  useEffect(() => {
    const t = window.setInterval(() => setAdesso(Date.now()), ms)
    return () => window.clearInterval(t)
  }, [ms])
  return adesso
}

function fmtOra(ms: number) {
  return new Intl.DateTimeFormat('it-IT', { hour: '2-digit', minute: '2-digit', timeZone: 'Europe/Rome' }).format(new Date(ms))
}
function fmtResto(ms: number) {
  const s = Math.max(0, Math.floor(ms / 1000))
  const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), sec = s % 60
  return h > 0 ? `${h}h ${String(m).padStart(2, '0')}m` : `${m}m ${String(sec).padStart(2, '0')}s`
}
const ordina = (sel: string[]) => [...sel].sort((a, b) => SEGNI.indexOf(a as Segno) - SEGNI.indexOf(b as Segno))
const esito = (casa: number, trasf: number): Segno => (casa > trasf ? '1' : casa < trasf ? '2' : 'X')

type Props = { membership: Membership; onNavigate: (view: GameView) => void; revealedMatchIds: Set<number>; onRevealMatch: (matchId: number) => void }

export function BetOne({ membership, onNavigate, revealedMatchIds, onRevealMatch }: Props) {
  const league = membership.league as League
  const dati = useSeasonData(membership)
  const adesso = useAdesso()
  const [schedine, setSchedine] = useState<Schedina[]>([])
  const [classifica, setClassifica] = useState<Record<string, RigaClassifica[]>>({})
  const [caricato, setCaricato] = useState(false)
  const [gruppoAttivo, setGruppoAttivo] = useState<Gruppo | null>(null)
  const [scelte, setScelte] = useState<Record<number, string[]>>({})
  const [doppia, setDoppia] = useState<Record<number, boolean>>({})
  const [invio, setInvio] = useState(false)
  const [errore, setErrore] = useState('')
  const [salvata, setSalvata] = useState<number | null>(null)
  const [tabClassifica, setTabClassifica] = useState<'tot' | Gruppo>('tot')
  const [aperte, setAperte] = useState<Record<number, boolean>>({})
  const [regole, setRegole] = useState(false)
  const [sezione, setSezione] = useState<'pronostici' | 'casino'>('pronostici')
  // Il casino' per ora lo vede solo il committente (lo decide il server: casino_visibile).
  const [casinoVisibile, setCasinoVisibile] = useState(false)
  useEffect(() => { void supabase.rpc('casino_visibile').then(({ data }) => setCasinoVisibile(data === true)) }, [])

  // --- La giornata a cui si gioca: la prima ancora da giocare del campionato.
  const giornata = useMemo(() => {
    const prossime = dati.fixtures.filter((f) => f.stato === 'programmata' && f.bracket_tie_id == null && f.giornata <= dati.giornateStagione)
    return prossime.length ? Math.min(...prossime.map((f) => f.giornata)) : null
  }, [dati.fixtures, dati.giornateStagione])

  const confDi = useCallback((teamId: number): Gruppo => {
    const c = dati.standings.find((s) => s.team_id === teamId)?.conferenza
    return c === 'est' || c === 'ovest' ? c : 'tutte'
  }, [dati.standings])

  const gruppi = useMemo<Gruppo[]>(() => (league.conferenze_attive ? ['est', 'ovest'] : ['tutte']), [league.conferenze_attive])
  const partite = useMemo(() => {
    const per: Record<string, typeof dati.fixtures> = { est: [], ovest: [], tutte: [] }
    if (giornata == null) return per
    for (const f of dati.fixtures) {
      if (f.giornata === giornata && f.stato === 'programmata' && f.bracket_tie_id == null) per[confDi(f.home_team_id)].push(f)
    }
    for (const g of Object.keys(per)) per[g].sort((a, b) => a.id - b.id)
    return per
  }, [dati.fixtures, giornata, confDi])

  const chiusuraMs = useMemo(() => {
    if (giornata == null) return null
    const orari = dati.fixtures.filter((f) => f.giornata === giornata && f.bracket_tie_id == null).map((f) => new Date(f.data_sim).getTime())
    return orari.length ? Math.min(...orari) - MINUTI_CHIUSURA * 60_000 : null
  }, [dati.fixtures, giornata])
  const chiusa = chiusuraMs != null && adesso >= chiusuraMs
  const oraChiusura = chiusuraMs != null ? fmtOra(chiusuraMs) : ''

  // --- Caricamento di schedine (le mie e, a valutazione fatta, quelle degli altri) e classifiche.
  const carica = useCallback(async () => {
    if (!dati.season) return
    const da = Math.max(1, (giornata ?? dati.giornateStagione) - 2)
    const { data } = await supabase.from('betone_schedine')
      .select('id, giornata, gruppo, team_id, user_id, risolta_il, giuste, totale, perfetta, betone_pronostici(fixture_id, scelta, giusta)')
      .eq('league_id', league.id).eq('season_id', dati.season.id).gte('giornata', da)
    setSchedine((data ?? []) as unknown as Schedina[])
    const tab: Array<'tot' | Gruppo> = ['tot', ...gruppi]
    const out: Record<string, RigaClassifica[]> = {}
    await Promise.all(tab.map(async (t) => {
      const { data: righe } = await supabase.rpc('betone_classifica', { p_league_id: league.id, p_gruppo: t === 'tot' ? null : t })
      out[t] = (righe ?? []) as RigaClassifica[]
    }))
    setClassifica(out)
    setCaricato(true)
  }, [dati.season, dati.giornateStagione, giornata, league.id, gruppi])
  useEffect(() => { void carica() }, [carica])

  const mie = useMemo(() => schedine.filter((s) => s.team_id === membership.id), [schedine, membership.id])
  const miaCorrente = useCallback((g: Gruppo) => mie.find((s) => s.giornata === giornata && s.gruppo === g) ?? null, [mie, giornata])

  // Le scelte iniziali arrivano dalla schedina salvata.
  useEffect(() => {
    if (giornata == null) return
    const s: Record<number, string[]> = {}
    const d: Record<number, boolean> = {}
    for (const g of gruppi) {
      const salvataCorrente = miaCorrente(g)
      for (const p of salvataCorrente?.betone_pronostici ?? []) { s[p.fixture_id] = p.scelta.split(''); d[p.fixture_id] = p.scelta.length === 2 }
    }
    setScelte(s); setDoppia(d)
  }, [giornata, gruppi, miaCorrente])
  useEffect(() => { if (gruppoAttivo == null) setGruppoAttivo(gruppi[0]) }, [gruppi, gruppoAttivo])

  // Niente spoiler: i risultati e le classifiche aspettano che tu abbia guardato la tua ultima partita.
  const attivoReveal = Boolean(dati.lastFixture && dati.lastFixture.giornata >= (league.reveal_dalla_giornata ?? 1))
  const ultimaPartita = dati.lastFixture ? dati.matchByFixture.get(dati.lastFixture.id) : undefined
  const bloccato = dati.loading || Boolean(attivoReveal && ultimaPartita && !revealedMatchIds.has(ultimaPartita.id))

  const fixtureDi = useCallback((id: number) => dati.fixtures.find((f) => f.id === id), [dati.fixtures])
  const team = (id: number) => dati.teamById.get(id)
  const posizione = (id: number) => dati.standings.find((s) => s.team_id === id)?.posizione ?? null

  // --- Interazione: 1 X 2 e doppie.
  const righeGruppo = gruppoAttivo ? partite[gruppoAttivo] ?? [] : []
  const nDoppie = (g: Gruppo) => (partite[g] ?? []).filter((f) => doppia[f.id]).length
  const riempita = (fid: number) => { const sel = scelte[fid] ?? []; return doppia[fid] ? sel.length === 2 : sel.length === 1 }
  const completa = (g: Gruppo) => (partite[g] ?? []).length > 0 && (partite[g] ?? []).every((f) => riempita(f.id))
  const compilate = (g: Gruppo) => (partite[g] ?? []).filter((f) => riempita(f.id)).length

  function tocca(fid: number, s: Segno) {
    if (chiusa) return
    setSalvata(null); setErrore('')
    setScelte((prev) => {
      const cur = prev[fid] ?? []
      if (!doppia[fid]) return { ...prev, [fid]: [s] }
      if (cur.includes(s)) return { ...prev, [fid]: cur.filter((x) => x !== s) }
      return { ...prev, [fid]: cur.length < 2 ? [...cur, s] : [cur[1], s] }
    })
  }
  function toggleDoppia(fid: number, g: Gruppo) {
    if (chiusa) return
    setSalvata(null)
    if (!doppia[fid] && nDoppie(g) >= MAX_DOPPIE) { setErrore(`Hai già usato le ${MAX_DOPPIE} doppie di questa schedina.`); return }
    setErrore('')
    setDoppia((d) => ({ ...d, [fid]: !d[fid] }))
    // Spegnendo la doppia resta solo il primo segno.
    if (doppia[fid]) setScelte((prev) => ({ ...prev, [fid]: (prev[fid] ?? []).slice(0, 1) }))
  }

  async function salva(g: Gruppo) {
    setInvio(true); setErrore('')
    const pronostici = (partite[g] ?? []).map((f) => ({ fixture_id: f.id, scelta: ordina(scelte[f.id] ?? []).join('') }))
    const { error } = await supabase.rpc('betone_salva', { p_league_id: league.id, p_gruppo: g, p_pronostici: pronostici })
    setInvio(false)
    if (error) { setErrore(error.message); return }
    setSalvata(Date.now())
    await carica()
  }

  // --- Ultima giornata valutata: le mie schedine e quelle degli altri.
  const giornataRisultati = useMemo(() => {
    const giornate = schedine.filter((s) => s.risolta_il != null).map((s) => s.giornata)
    return giornate.length ? Math.max(...giornate) : null
  }, [schedine])
  const risolteUltime = useMemo(() => schedine.filter((s) => s.giornata === giornataRisultati && s.risolta_il != null), [schedine, giornataRisultati])

  if (!league.conferenze_stampa) {
    return <main className="app-shell season-shell bet-shell">
      <GameNav league={league} active="betone" onNavigate={onNavigate} />
      <div className="season-page season-page--narrow"><p>BetOne non è ancora attivo in questa lega.</p></div>
    </main>
  }

  const attivo = gruppoAttivo ?? gruppi[0]
  const mia = miaCorrente(attivo)
  const partiteAttivo = partite[attivo] ?? []
  const pronta = completa(attivo)
  const modificata = (() => {
    if (!mia) return true
    return partiteAttivo.some((f) => {
      const p = mia.betone_pronostici.find((x) => x.fixture_id === f.id)
      return !p || p.scelta !== ordina(scelte[f.id] ?? []).join('')
    })
  })()

  return <main className="app-shell season-shell bet-shell">
    <GameNav league={league} active="betone" onNavigate={onNavigate} />
    <header className="topbar season-topbar"><div className="brand-lockup brand-lockup--dark"><img src="/specialone-mark.svg" alt="" /><span>SpecialOne</span></div><span>BetOne</span></header>
    <div className="season-page season-page--narrow bet-page">
      {dati.loading || !caricato ? <section className="season-state is-caricamento"><LoadingLogo compatto /><h2>Preparo la schedina…</h2><span className="caricamento-barra" aria-hidden="true" /></section> : <>

        <section className="bet-hero">
          <div className="bet-hero__marchio" aria-hidden="true">
            <svg viewBox="0 0 48 48" width="34" height="34" fill="none" stroke="currentColor" strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round">
              <path d="M6 14a3 3 0 0 1 3-3h30a3 3 0 0 1 3 3v5a4 4 0 0 0 0 8v5a3 3 0 0 1-3 3H9a3 3 0 0 1-3-3v-5a4 4 0 0 0 0-8z" /><path d="M18 17v14M30 17v14" strokeDasharray="2 3.2" />
            </svg>
          </div>
          <div className="bet-hero__testo">
            <p className="bet-kicker">{league.nome}</p>
            <h1>Bet<b>One</b></h1>
            <p className="bet-sottotitolo">La schedina della giornata: 1, X o 2 per ogni partita, con solo {MAX_DOPPIE} doppie a disposizione. Una schedina perfetta vale una WIN.</p>
          </div>
        </section>

        <div className="bet-sezioni" role="tablist" aria-label="Sezione di BetOne">
          <button type="button" role="tab" aria-selected={sezione === 'pronostici'} className={sezione === 'pronostici' ? 'is-attiva' : ''} onClick={() => setSezione('pronostici')}><span aria-hidden="true">🎟️</span>Pronostici</button>
          {casinoVisibile && <button type="button" role="tab" aria-selected={sezione === 'casino'} className={sezione === 'casino' ? 'is-attiva' : ''} onClick={() => setSezione('casino')}><span aria-hidden="true">🎰</span>Casinò</button>}
        </div>

        {casinoVisibile && sezione === 'casino' ? <Casino leagueId={league.id} teamId={membership.id} dati={dati} /> : <>
        {giornata == null
          ? <section className="bet-vuoto"><strong>Nessuna giornata da giocare</strong><p>La prossima schedina si apre appena c'è una nuova giornata di campionato.</p></section>
          : <>
            <section className={`bet-stato${chiusa ? ' is-chiusa' : ''}`}>
              <div><small>Giornata {giornata}</small><strong>{chiusa ? 'Schedine chiuse' : `Chiude alle ${oraChiusura}`}</strong></div>
              {!chiusa && chiusuraMs != null && <span className="bet-conto" aria-label="Tempo rimasto">{fmtResto(chiusuraMs - adesso)}</span>}
              {chiusa && <span className="bet-conto bet-conto--chiusa">Si attende il fischio</span>}
            </section>

            {gruppi.length > 1 && <div className="bet-tab" role="tablist" aria-label="Conferenza">
              {gruppi.map((g) => {
                const s = miaCorrente(g)
                return <button key={g} type="button" role="tab" aria-selected={attivo === g} className={attivo === g ? 'is-attiva' : ''} onClick={() => { setGruppoAttivo(g); setErrore('') }}>
                  <span>{NOME_GRUPPO[g]}</span>
                  <i>{s ? '✓ giocata' : `${compilate(g)}/${(partite[g] ?? []).length}`}</i>
                </button>
              })}
            </div>}

            <article className="bet-ticket" aria-label={`Schedina ${NOME_GRUPPO[attivo]}`}>
              <header className="bet-ticket__testa">
                <div><small>Schedina</small><strong>{NOME_GRUPPO[attivo]}{attivo === 'tutte' ? ` ${giornata}` : ` · G${giornata}`}</strong></div>
                <div className="bet-ticket__doppie" aria-label={`Doppie usate ${nDoppie(attivo)} su ${MAX_DOPPIE}`}>
                  <small>Doppie</small>
                  <span>{Array.from({ length: MAX_DOPPIE }, (_, i) => <i key={i} className={i < nDoppie(attivo) ? 'is-usata' : ''} />)}</span>
                </div>
              </header>

              <p className="bet-ticket__avviso">Come al totocalcio vanno giocate <b>tutte le {partiteAttivo.length} partite</b>: la scommessa si piazza solo a schedina completa.</p>
              <ol className="bet-righe">
                {partiteAttivo.map((f, i) => {
                  const casa = team(f.home_team_id), ospite = team(f.away_team_id)
                  const sel = scelte[f.id] ?? []
                  const mioMatch = f.home_team_id === membership.id || f.away_team_id === membership.id
                  const eDoppia = Boolean(doppia[f.id])
                  return <li key={f.id} className={`bet-riga${mioMatch ? ' is-mia' : ''}${riempita(f.id) ? ' is-fatta' : ''}`}>
                    <div className="bet-riga__squadre">
                      <span className="bet-riga__n" aria-hidden="true">{i + 1}</span>
                      <div className="bet-squadra">
                        <Crest value={casa?.stemma_url ?? null} stelle={casa?.titoli_title} imageUrl={dati.crestUrlByTeamId.get(f.home_team_id)} size="small" />
                        <span>{casa?.nome ?? '—'}{posizione(f.home_team_id) != null && <em>{posizione(f.home_team_id)}°</em>}</span>
                      </div>
                      <b className="bet-vs">vs</b>
                      <div className="bet-squadra bet-squadra--ospite">
                        <span>{ospite?.nome ?? '—'}{posizione(f.away_team_id) != null && <em>{posizione(f.away_team_id)}°</em>}</span>
                        <Crest value={ospite?.stemma_url ?? null} stelle={ospite?.titoli_title} imageUrl={dati.crestUrlByTeamId.get(f.away_team_id)} size="small" />
                      </div>
                    </div>
                    {mioMatch && <p className="bet-riga__mia">La tua partita</p>}
                    <div className="bet-segni" role="group" aria-label={`Pronostico partita ${i + 1}`}>
                      {SEGNI.map((s) => <button key={s} type="button" className={`bet-segno${sel.includes(s) ? ' is-scelto' : ''}${eDoppia && sel.includes(s) ? ' is-doppio' : ''}`}
                        aria-pressed={sel.includes(s)} disabled={chiusa} onClick={() => tocca(f.id, s)}>{s}</button>)}
                      <button type="button" className={`bet-x2${eDoppia ? ' is-attiva' : ''}`} aria-pressed={eDoppia} disabled={chiusa || (!eDoppia && nDoppie(attivo) >= MAX_DOPPIE)}
                        onClick={() => toggleDoppia(f.id, attivo)} title="Doppia chance: copri due esiti">×2</button>
                    </div>
                    {eDoppia && sel.length < 2 && <p className="bet-riga__aiuto">Doppia: scegli due segni.</p>}
                  </li>
                })}
              </ol>
              {partiteAttivo.length === 0 && <p className="bet-vuoto-int">Nessuna partita in questa schedina.</p>}
            </article>
          </>}

        {caricato && !bloccato && giornataRisultati != null && risolteUltime.length > 0 && <section className="bet-sezione">
          <h2>Giornata {giornataRisultati}: com'è andata</h2>
          {gruppi.map((g) => {
            const gruppoRis = risolteUltime.filter((s) => s.gruppo === g).sort((a, b) => (b.giuste ?? 0) - (a.giuste ?? 0))
            if (!gruppoRis.length) return null
            const miaRis = gruppoRis.find((s) => s.team_id === membership.id)
            return <div key={g} className="bet-esito-gruppo">
              {gruppi.length > 1 && <h3>{NOME_GRUPPO[g]}</h3>}
              {miaRis ? <div className={`bet-esito-mia${miaRis.perfetta ? ' is-win' : ''}`}>
                <strong>{miaRis.perfetta ? 'WIN' : `${miaRis.giuste}/${miaRis.totale}`}</strong>
                <span>{miaRis.perfetta ? 'Schedina perfetta!' : 'La tua schedina'}</span>
              </div> : <p className="bet-nota">Non hai giocato questa schedina.</p>}
              <ol className="bet-giocatori">
                {gruppoRis.map((s, i) => {
                  const t = team(s.team_id)
                  return <li key={s.id} className={s.team_id === membership.id ? 'is-mia' : ''}>
                    <button type="button" onClick={() => setAperte((a) => ({ ...a, [s.id]: !a[s.id] }))} aria-expanded={Boolean(aperte[s.id])}>
                      <span className="bet-pos">{i + 1}</span>
                      <span className="bet-giocatori__stemma"><Crest value={t?.stemma_url ?? null} stelle={t?.titoli_title} imageUrl={dati.crestUrlByTeamId.get(s.team_id)} size="small" /></span>
                      <span className="bet-giocatori__nome">{t?.nome ?? '—'}</span>
                      {s.perfetta && <b className="bet-win">WIN</b>}
                      <span className="bet-punteggio">{s.giuste}<small>/{s.totale}</small></span>
                    </button>
                    {aperte[s.id] && <ul className="bet-dettaglio">
                      {[...s.betone_pronostici].sort((a, b) => a.fixture_id - b.fixture_id).map((p) => {
                        const f = fixtureDi(p.fixture_id)
                        const m = f ? dati.matchByFixture.get(f.id) : undefined
                        return <li key={p.fixture_id} className={p.giusta ? 'is-giusta' : 'is-sbagliata'}>
                          <span>{team(f?.home_team_id ?? 0)?.nome} {m ? `${m.gol_home}-${m.gol_away}` : 'vs'} {team(f?.away_team_id ?? 0)?.nome}</span>
                          <b>{p.scelta}{m ? ` · ${esito(m.gol_home, m.gol_away)}` : ''}</b><i aria-hidden="true">{p.giusta ? '✓' : '✗'}</i>
                        </li>
                      })}
                    </ul>}
                  </li>
                })}
              </ol>
            </div>
          })}
        </section>}

        {caricato && bloccato && (giornataRisultati != null) && <section className="bet-bloccato">
          <i aria-hidden="true">🔒</i>
          <strong>Risultati e classifica bloccati</strong>
          <p>Guarda prima il risultato della tua ultima partita: poi si sblocca, senza spoiler.</p>
          {ultimaPartita && <button className="button button--primary" type="button" onClick={() => onRevealMatch(ultimaPartita.id)}>Vedi risultato</button>}
        </section>}

        {caricato && !bloccato && <section className="bet-sezione">
          <h2>Classifica BetOne</h2>
          {gruppi.length > 1 && <div className="bet-tab bet-tab--piccola" role="tablist">
            {(['tot', ...gruppi] as Array<'tot' | Gruppo>).map((t) => <button key={t} type="button" role="tab" aria-selected={tabClassifica === t} className={tabClassifica === t ? 'is-attiva' : ''} onClick={() => setTabClassifica(t)}>
              <span>{t === 'tot' ? 'Totale' : NOME_GRUPPO[t]}</span></button>)}
          </div>}
          {(classifica[tabClassifica] ?? []).length === 0
            ? <p className="bet-nota">Nessuna schedina valutata per ora: la classifica nasce dopo la prima giornata.</p>
            : <ol className="bet-classifica">
              {(classifica[tabClassifica] ?? []).map((r, i) => {
                const t = team(r.team_id)
                return <li key={r.team_id} className={r.team_id === membership.id ? 'is-mia' : ''}>
                  <span className={`bet-pos${i < 3 ? ` bet-pos--${i + 1}` : ''}`}>{i + 1}</span>
                  <span className="bet-giocatori__stemma"><Crest value={t?.stemma_url ?? null} stelle={t?.titoli_title} imageUrl={dati.crestUrlByTeamId.get(r.team_id)} size="small" /></span>
                  <span className="bet-classifica__nome"><strong>{t?.nome ?? '—'}</strong><small>{r.giuste} azzeccate su {r.totale} · {r.schedine} {r.schedine === 1 ? 'schedina' : 'schedine'}</small></span>
                  <span className="bet-classifica__win"><b>{r.wins}</b><small>WIN</small></span>
                </li>
              })}
            </ol>}
          <p className="bet-nota">A parità di WIN conta il totale delle partite azzeccate.</p>
        </section>}

        <section className="bet-regole">
          <button type="button" className="bet-regole__tasto" aria-expanded={regole} onClick={() => setRegole((v) => !v)}>Come si gioca <span aria-hidden="true">{regole ? '−' : '+'}</span></button>
          {regole && <ul>
            <li>Per ogni partita della prossima giornata scegli <b>1</b> (vince la squadra di casa), <b>X</b> (pareggio) o <b>2</b> (vince la squadra ospite), sul risultato dei 90 minuti.</li>
            <li>Hai solo <b>{MAX_DOPPIE} doppie</b> per schedina: tocca <b>×2</b> sulla partita e scegli due segni.</li>
            <li>{gruppi.length > 1 ? 'Ci sono due schedine, East e West: puoi giocarle entrambe.' : 'Una sola schedina con tutte le partite della giornata.'}</li>
            <li>Puoi modificarla fino a {MINUTI_CHIUSURA} minuti prima della simulazione. Quelle degli altri restano nascoste finché non sono valutate.</li>
            <li>Una schedina con <b>tutti i pronostici giusti</b> vale una <b>WIN</b>. In classifica contano le WIN e, a parità, le partite azzeccate.</li>
          </ul>}
        </section>
        </>}
      </>}
    </div>

    {sezione === 'pronostici' && caricato && giornata != null && partiteAttivo.length > 0 && !chiusa && <div className="bet-barra">
      {errore && <p className="bet-barra__errore" role="alert">{errore}</p>}
      <p className="bet-barra__stato">
        {salvata ? <>Scommessa piazzata ✓ Puoi modificarla fino alle {oraChiusura}.</>
          : <>{compilate(attivo)}/{partiteAttivo.length} partite · doppie {nDoppie(attivo)}/{MAX_DOPPIE}{mia && !modificata ? ' · schedina giocata' : ''}</>}
      </p>
      <button type="button" className="bet-barra__salva" disabled={!pronta || invio || !modificata} onClick={() => void salva(attivo)}>
        {invio ? 'Piazzo…' : mia && !modificata ? 'Scommessa piazzata ✓' : mia ? 'Aggiorna la scommessa' : pronta ? 'Piazza la scommessa' : `Mancano ${partiteAttivo.length - compilate(attivo)} partite`}
      </button>
    </div>}
  </main>
}

