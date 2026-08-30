import { useEffect, useMemo, useState } from 'react'
import { supabase } from '../lib/supabase'
import type { Bracket, BracketTie, Fixture, League, Membership, Team } from '../types'
import { GameNav, type GameView } from './GameNav'
import { SeasonState } from './SeasonUI'
import { Crest } from './Crest'
import { useSeasonData } from '../lib/useSeasonData'
import { LOGO_FASE } from '../lib/faseSquadra'

type Props = { membership: Membership; onNavigate: (view: GameView) => void; onOpenMatch: (id: number) => void }

const TITOLO: Record<Bracket['tipo'], string> = { title: 'Title Playoff', draft: 'Draft Playoff' }

// Altezza fissa di ogni carta-incontro e spaziatura verticale fra due
// sorelle: sono le uniche due costanti da cui dipende la geometria del
// tabellone. Il connettore fra un turno e il successivo si calcola da
// queste, ricorsivamente, così le linee toccano sempre il centro esatto
// di ogni carta, a qualunque profondità (vedi altezzaSottoalbero).
const ALTEZZA_MATCH = 112
const GAP_VERTICALE = 24

function altezzaSottoalbero(turno: number): number {
  if (turno <= 1) return ALTEZZA_MATCH
  return 2 * altezzaSottoalbero(turno - 1) + GAP_VERTICALE
}

// Il turno si numera da quanti round ha DAVVERO il tabellone (dedotto dal
// numero di incontri nel primo turno, sempre generato per intero fin
// dall'inizio), non da quanti round esistono già in tabella: i turni
// successivi al primo nascono uno alla volta, mano a mano che si
// risolvono, quindi finché il tabellone è a metà il turno più alto
// presente è sempre meno del totale reale — usarlo come riferimento
// etichetta "Semifinali" un turno di Quarti e "Finale" una Semifinale.
function turniTotaliDa(ties: BracketTie[]): number {
  const primoTurno = ties.filter((t) => t.turno === 1).length
  return primoTurno > 0 ? Math.ceil(Math.log2(primoTurno * 2)) : 0
}

function nomeTurno(turno: number, turniTotali: number) {
  const mancanti = turniTotali - turno
  if (mancanti === 0) return 'Finale'
  if (mancanti === 1) return 'Semifinali'
  if (mancanti === 2) return 'Quarti'
  return `Turno ${turno}`
}

type DatiTabellone = {
  teamById: Map<number, Team>
  fixturePerTie: Map<number, Fixture[]>
  matchPerFixture: ReturnType<typeof useSeasonData>['matchByFixture']
  crestUrls: Map<number, string>
  onOpenMatch: (id: number) => void
}

export function Tabellone({ membership, onNavigate, onOpenMatch }: Props) {
  const league = membership.league as League
  const dati = useSeasonData(membership)
  const [brackets, setBrackets] = useState<Bracket[]>([])
  const [ties, setTies] = useState<BracketTie[]>([])
  const [loading, setLoading] = useState(true)
  const [errore, setErrore] = useState<string | null>(null)
  const [tabAttivo, setTabAttivo] = useState<Bracket['tipo']>('title')

  useEffect(() => {
    let vivo = true
    async function carica() {
      setLoading(true)
      const [bRes, tRes] = await Promise.all([
        supabase.from('brackets').select('*').eq('league_id', league.id),
        supabase.from('bracket_ties').select('*').eq('league_id', league.id).order('turno').order('posizione'),
      ])
      if (!vivo) return
      const err = bRes.error ?? tRes.error
      if (err) { setErrore(err.message); setLoading(false); return }
      setBrackets((bRes.data ?? []) as Bracket[])
      setTies((tRes.data ?? []) as BracketTie[])
      setLoading(false)
    }
    void carica()
    return () => { vivo = false }
  }, [league.id, dati.season?.id])

  const teamById = useMemo(() => new Map(dati.teams.map((t) => [t.id, t])), [dati.teams])
  const fixturePerTie = useMemo(() => {
    const mappa = new Map<number, Fixture[]>()
    for (const f of dati.fixtures) {
      if (f.bracket_tie_id == null) continue
      const lista = mappa.get(f.bracket_tie_id) ?? []
      lista.push(f)
      mappa.set(f.bracket_tie_id, lista)
    }
    for (const lista of mappa.values()) lista.sort((a, b) => (a.mano ?? 0) - (b.mano ?? 0))
    return mappa
  }, [dati.fixtures])
  const matchPerFixture = dati.matchByFixture

  // Solo i tabelloni della stagione mostrata: una lega alla seconda stagione
  // ha in tabella anche quelli vecchi.
  const bracketsStagione = brackets.filter((b) => b.season_id === dati.season?.id)
  const bracketAttivo = bracketsStagione.find((b) => b.tipo === tabAttivo) ?? bracketsStagione[0]

  if (dati.loading || loading || dati.error || errore) {
    return <main className="app-shell season-shell">
      <GameNav league={league} active="tabellone" onNavigate={onNavigate} />
      <div className="season-page season-page--narrow">
        <SeasonState loading={dati.loading || loading} error={dati.error ?? errore} onRetry={dati.reload} />
      </div>
    </main>
  }

  const datiComuni: DatiTabellone = { teamById, fixturePerTie, matchPerFixture, crestUrls: dati.crestUrlByTeamId, onOpenMatch }

  return <main className={`app-shell season-shell tabellone-shell tabellone-shell--${bracketAttivo?.tipo ?? 'title'}`}>
    <div className="tabellone-sfondo" data-fase={bracketAttivo?.tipo ?? 'title'} aria-hidden="true" />
    <GameNav league={league} active="tabellone" onNavigate={onNavigate} />
    <header className="topbar season-topbar">
      <div className="brand-lockup brand-lockup--dark"><img src="/specialone-mark.svg" alt="" /><span>SpecialOne</span></div>
      <span>Tabellone</span>
    </header>
    <div className="season-page season-page--narrow tabellone-page">
      <section className="season-title-row">
        <div>
          <p className="kicker">{league.nome}</p>
          <h1>Tabellone.</h1>
          <p>Title Playoff e Draft Playoff della stagione {league.stagione_corrente}.</p>
        </div>
      </section>

      {bracketsStagione.length === 0 && <section className="offseason-card">
        <p className="kicker">Non ancora</p>
        <h2>I tabelloni non sono ancora nati</h2>
        <p>
          Title Playoff e Draft Playoff si formano da soli quando finisce l’ultima giornata di
          campionato: le prime 8 in classifica si giocano il titolo, il resto si gioca l’ordine
          di scelta del prossimo draft. Servono almeno 8 squadre.
        </p>
      </section>}

      {bracketsStagione.length > 1 && (
        <div className="segmented tabellone-segmented" aria-label="Scegli tabellone">
          {bracketsStagione.map((b) => (
            <button key={b.tipo} type="button" aria-pressed={tabAttivo === b.tipo} onClick={() => setTabAttivo(b.tipo)}>
              {TITOLO[b.tipo]}
            </button>
          ))}
        </div>
      )}

      {bracketAttivo && (() => {
        const bracket = bracketAttivo
        const suoi = ties.filter((t) => t.bracket_id === bracket.id)
        const turniTotali = turniTotaliDa(suoi)
        const tieMap = new Map(suoi.map((t) => [`${t.turno}:${t.posizione}`, t]))

        return <div className={`tabellone-blocco tabellone-blocco--${bracket.tipo}`}>
          <section className={`tabellone-card tabellone-card--${bracket.tipo}`}>
            <div className="tabellone-testa">
              <img className="tabellone-logo-fase" src={LOGO_FASE[bracket.tipo]} alt={TITOLO[bracket.tipo]} />
              {bracket.stato === 'concluso' && bracket.vincitore_team_id && (
                <span className="tabellone-vincitore">
                  {bracket.tipo === 'title' ? 'Campione' : 'Vince il Draft Playoff'}: <b>{teamById.get(bracket.vincitore_team_id)?.nome ?? '—'}</b>
                </span>
              )}
            </div>
          </section>

          {turniTotali > 0 && <div className="bracket-scroll">
            <NodoBracket
              turno={turniTotali} posizione={0} turniTotali={turniTotali}
              tieMap={tieMap} dati={datiComuni}
            />
          </div>}
        </div>
      })()}
    </div>
  </main>
}

function NodoBracket({ turno, posizione, turniTotali, tieMap, dati }: {
  turno: number
  posizione: number
  turniTotali: number
  tieMap: Map<string, BracketTie>
  dati: DatiTabellone
}) {
  const tie = tieMap.get(`${turno}:${posizione}`)
  const carta = <ConfrontoBracket tie={tie} turno={turno} turniTotali={turniTotali} dati={dati} />

  if (turno <= 1) return carta

  const margineConnettore = altezzaSottoalbero(turno - 1) / 2

  return <div className="bracket-nodo">
    <div className="bracket-nodo__figli">
      <NodoBracket turno={turno - 1} posizione={posizione * 2} turniTotali={turniTotali} tieMap={tieMap} dati={dati} />
      <NodoBracket turno={turno - 1} posizione={posizione * 2 + 1} turniTotali={turniTotali} tieMap={tieMap} dati={dati} />
    </div>
    <span className="bracket-nodo__connettore" style={{ margin: `${margineConnettore}px 0` }} aria-hidden="true" />
    {carta}
  </div>
}

function ConfrontoBracket({ tie, turno, turniTotali, dati }: {
  tie: BracketTie | undefined
  turno: number
  turniTotali: number
  dati: DatiTabellone
}) {
  const { teamById, fixturePerTie, matchPerFixture, crestUrls, onOpenMatch } = dati

  return <div className="bracket-match" style={{ height: ALTEZZA_MATCH }}>
    <p className="bracket-match__turno">{nomeTurno(turno, turniTotali)}</p>
    {!tie ? <>
      <RigaSquadra team={null} seed={null} crestUrls={crestUrls} />
      <RigaSquadra team={null} seed={null} crestUrls={crestUrls} />
    </> : (() => {
      const alta = tie.alta_team_id ? teamById.get(tie.alta_team_id) : null
      const bassa = tie.bassa_team_id ? teamById.get(tie.bassa_team_id) : null

      if (!alta || !bassa) {
        const solo = alta ?? bassa
        return <>
          <RigaSquadra team={solo} seed={alta ? tie.alta_seed : tie.bassa_seed} crestUrls={crestUrls} vincitore />
          <p className="bracket-match__nota">Passa senza giocare</p>
        </>
      }

      const fx = fixturePerTie.get(tie.id) ?? []
      const aggregato = fx.reduce((acc, f) => {
        const m = matchPerFixture.get(f.id)
        if (!m) return acc
        const golAlta = f.home_team_id === tie.alta_team_id ? m.gol_home : m.gol_away
        const golBassa = f.home_team_id === tie.alta_team_id ? m.gol_away : m.gol_home
        return { alta: acc.alta + golAlta, bassa: acc.bassa + golBassa, giocate: acc.giocate + 1 }
      }, { alta: 0, bassa: 0, giocate: 0 })
      const rigori = fx.map((f) => matchPerFixture.get(f.id)).find((m) => m && m.rigori_home !== null)
      const fxRigori = rigori ? fx.find((f) => matchPerFixture.get(f.id) === rigori) : undefined
      const rigoriAlta = rigori && fxRigori ? (fxRigori.home_team_id === tie.alta_team_id ? rigori.rigori_home : rigori.rigori_away) : null
      const rigoriBassa = rigori && fxRigori ? (fxRigori.home_team_id === tie.alta_team_id ? rigori.rigori_away : rigori.rigori_home) : null

      return <>
        <RigaSquadra team={alta} seed={tie.alta_seed} crestUrls={crestUrls}
          gol={aggregato.giocate ? aggregato.alta : null} rigori={rigoriAlta}
          vincitore={tie.vincitore_team_id === alta.id} />
        <RigaSquadra team={bassa} seed={tie.bassa_seed} crestUrls={crestUrls}
          gol={aggregato.giocate ? aggregato.bassa : null} rigori={rigoriBassa}
          vincitore={tie.vincitore_team_id === bassa.id} />
        <div className="bracket-match__mani">
          {tie.gara_secca && <span className="bracket-match__badge">Campo neutro</span>}
          {fx.map((f) => {
            const m = matchPerFixture.get(f.id)
            const etichetta = tie.gara_secca ? 'Finale' : f.mano === 1 ? 'A' : 'R'
            if (!m) return <span className="bracket-match__mano" key={f.id}>{etichetta} · g.{f.giornata}</span>
            return <button className="bracket-match__mano bracket-match__mano--link" type="button" key={f.id}
              onClick={() => onOpenMatch(m.id)}>
              {etichetta} {m.gol_home}-{m.gol_away}
            </button>
          })}
        </div>
      </>
    })()}
  </div>
}

function RigaSquadra({ team, seed, crestUrls, gol = null, rigori = null, vincitore = false }: {
  team: Team | null | undefined
  seed: number | null
  crestUrls: Map<number, string>
  gol?: number | null
  rigori?: number | null
  vincitore?: boolean
}) {
  if (!team) return <div className="bracket-riga bracket-riga--vuota"><span>Da definire</span></div>
  return <div className={`bracket-riga ${vincitore ? 'e-vincitore' : ''}`}>
    <Crest value={team.stemma_url} imageUrl={crestUrls.get(team.id)} />
    <span className="bracket-nome">{team.nome}{seed != null && <i className="bracket-seed">{seed}</i>}</span>
    <span className="bracket-gol">
      {gol != null ? gol : '—'}
      {rigori != null && <em> ({rigori})</em>}
    </span>
  </div>
}
