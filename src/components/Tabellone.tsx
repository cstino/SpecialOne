import { useEffect, useMemo, useState } from 'react'
import { supabase } from '../lib/supabase'
import type { Bracket, BracketTie, Fixture, League, Match, Membership, Team } from '../types'
import { GameNav, type GameView } from './GameNav'
import { SeasonState } from './SeasonUI'
import { Crest } from './Crest'
import { useSeasonData } from '../lib/useSeasonData'

type Props = { membership: Membership; onNavigate: (view: GameView) => void; onOpenMatch: (id: number) => void }

const TITOLO: Record<Bracket['tipo'], string> = { playoff: 'Playoff', playout: 'Playout' }
const SOTTOTITOLO: Record<Bracket['tipo'], string> = {
  playoff: 'Si compete per il titolo di campione.',
  playout: 'Si compete per il bonus in denaro: al vincitore e al finalista.',
}

// Il nome del turno si legge da quanti ne restano, non da quanti ne sono
// passati: l'ultimo e' sempre la finale, quello prima la semifinale.
function nomeTurno(turno: number, turniTotali: number) {
  const mancanti = turniTotali - turno
  if (mancanti === 0) return 'Finale'
  if (mancanti === 1) return 'Semifinali'
  if (mancanti === 2) return 'Quarti'
  return `Turno ${turno}`
}

export function Tabellone({ membership, onNavigate, onOpenMatch }: Props) {
  const league = membership.league as League
  const dati = useSeasonData(membership)
  const [brackets, setBrackets] = useState<Bracket[]>([])
  const [ties, setTies] = useState<BracketTie[]>([])
  const [loading, setLoading] = useState(true)
  const [errore, setErrore] = useState<string | null>(null)

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

  if (dati.loading || loading || dati.error || errore) {
    return <main className="app-shell season-shell">
      <GameNav league={league} active="tabellone" onNavigate={onNavigate} />
      <div className="season-page season-page--narrow">
        <SeasonState loading={dati.loading || loading} error={dati.error ?? errore} onRetry={dati.reload} />
      </div>
    </main>
  }

  return <main className="app-shell season-shell">
    <GameNav league={league} active="tabellone" onNavigate={onNavigate} />
    <header className="topbar season-topbar">
      <div className="brand-lockup brand-lockup--dark"><img src="/specialone-mark.svg" alt="" /><span>SpecialOne</span></div>
      <span>Tabellone</span>
    </header>
    <div className="season-page season-page--narrow">
      <section className="help-heading">
        <p className="kicker">{league.nome}</p>
        <h1>Tabellone</h1>
        <p>Playoff e playout della stagione {league.stagione_corrente}.</p>
      </section>

      {bracketsStagione.length === 0 && <section className="offseason-card">
        <p className="kicker">Non ancora</p>
        <h2>I tabelloni non sono ancora nati</h2>
        <p>
          Playoff e playout si formano da soli quando finisce l’ultima giornata di campionato:
          la metà alta della classifica si gioca il titolo, la metà bassa un bonus in denaro.
          Servono almeno 8 squadre.
        </p>
      </section>}

      {bracketsStagione.map((bracket) => {
        const suoi = ties.filter((t) => t.bracket_id === bracket.id)
        const turniTotali = suoi.reduce((max, t) => Math.max(max, t.turno), 0)
        const turni = [...new Set(suoi.map((t) => t.turno))].sort((a, b) => a - b)
        return <section className={`offseason-card tabellone tabellone--${bracket.tipo}`} key={bracket.id}>
          <div className="sezione-testa">
            <div><p className="kicker">{SOTTOTITOLO[bracket.tipo]}</p><h2>{TITOLO[bracket.tipo]}</h2></div>
            {bracket.stato === 'concluso' && bracket.vincitore_team_id && (
              <span className="tabellone-vincitore">
                {bracket.tipo === 'playoff' ? 'Campione' : 'Vince il playout'}: <b>{teamById.get(bracket.vincitore_team_id)?.nome ?? '—'}</b>
              </span>
            )}
          </div>

          {turni.map((turno) => <div className="tabellone-turno" key={turno}>
            <h3>{nomeTurno(turno, turniTotali)}</h3>
            {suoi.filter((t) => t.turno === turno).map((tie) => {
              const alta = tie.alta_team_id ? teamById.get(tie.alta_team_id) : null
              const bassa = tie.bassa_team_id ? teamById.get(tie.bassa_team_id) : null
              // Un accoppiamento con un solo lato e' un bye: la testa di serie
              // passa senza giocare.
              if (!alta || !bassa) {
                return <div className="tabellone-tie tabellone-tie--bye" key={tie.id}>
                  <RigaSquadra team={alta ?? bassa} seed={alta ? tie.alta_seed : tie.bassa_seed} crestUrls={dati.crestUrlByTeamId} vincitore />
                  <small>Passa senza giocare</small>
                </div>
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
              const rigoriAlta = rigori
                ? (fx.find((f) => matchPerFixture.get(f.id) === rigori)!.home_team_id === tie.alta_team_id ? rigori.rigori_home : rigori.rigori_away)
                : null
              const rigoriBassa = rigori
                ? (fx.find((f) => matchPerFixture.get(f.id) === rigori)!.home_team_id === tie.alta_team_id ? rigori.rigori_away : rigori.rigori_home)
                : null

              return <div className="tabellone-tie" key={tie.id}>
                <RigaSquadra team={alta} seed={tie.alta_seed} crestUrls={dati.crestUrlByTeamId}
                  gol={aggregato.giocate ? aggregato.alta : null} rigori={rigoriAlta}
                  vincitore={tie.vincitore_team_id === alta.id} />
                <RigaSquadra team={bassa} seed={tie.bassa_seed} crestUrls={dati.crestUrlByTeamId}
                  gol={aggregato.giocate ? aggregato.bassa : null} rigori={rigoriBassa}
                  vincitore={tie.vincitore_team_id === bassa.id} />
                <div className="tabellone-mani">
                  {tie.gara_secca && <span className="tabellone-badge">Gara secca · campo neutro</span>}
                  {fx.map((f) => {
                    const m = matchPerFixture.get(f.id)
                    const etichetta = tie.gara_secca ? 'Finale' : f.mano === 1 ? 'Andata' : 'Ritorno'
                    if (!m) return <span className="tabellone-mano" key={f.id}>{etichetta}: giornata {f.giornata}</span>
                    return <button className="tabellone-mano tabellone-mano--link" type="button" key={f.id}
                      onClick={() => onOpenMatch(m.id)}>
                      {etichetta}: {m.gol_home}-{m.gol_away}
                      {m.gol_home_90 !== null && <em> (90’ {m.gol_home_90}-{m.gol_away_90})</em>}
                    </button>
                  })}
                </div>
              </div>
            })}
          </div>)}
        </section>
      })}
    </div>
  </main>
}

function RigaSquadra({ team, seed, crestUrls, gol = null, rigori = null, vincitore = false }: {
  team: Team | null | undefined
  seed: number | null
  crestUrls: Map<number, string>
  gol?: number | null
  rigori?: number | null
  vincitore?: boolean
}) {
  if (!team) return <div className="tabellone-riga tabellone-riga--vuota"><span>Da definire</span></div>
  return <div className={`tabellone-riga ${vincitore ? 'e-vincitore' : ''}`}>
    <Crest value={team.stemma_url} imageUrl={crestUrls.get(team.id)} />
    <span className="tabellone-nome">{team.nome}{seed != null && <i className="tabellone-seed">{seed}</i>}</span>
    <span className="tabellone-gol">
      {gol != null ? gol : '—'}
      {rigori != null && <em> ({rigori})</em>}
    </span>
  </div>
}
