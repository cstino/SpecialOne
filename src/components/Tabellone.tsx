import { useEffect, useMemo, useState } from 'react'
import { supabase } from '../lib/supabase'
import type { Bracket, BracketTie, Fixture, League, Membership, Team } from '../types'
import { GameNav, type GameView } from './GameNav'
import { PopupSpiegazione } from './PopupSpiegazione'
import { SeasonState } from './SeasonUI'
import { Crest } from './Crest'
import { useSeasonData } from '../lib/useSeasonData'
import { LOGO_FASE } from '../lib/faseSquadra'

type Props = { membership: Membership; onNavigate: (view: GameView) => void; onOpenMatch: (id: number) => void }

const TITOLO: Record<Bracket['tipo'], string> = { title: 'Title Playoff', draft: 'Draft Playoff' }

// Geometria dell'albero verticale "a scalini" (stile bracket UEFA): ogni
// turno e' spostato a destra e la carta di un turno siede nello spazio fra
// le sue due sfide d'origine. La riga di ogni carta e' la sua posizione in un
// attraversamento in-order dell'albero: cosi' nessuna carta si sovrappone a
// un'altra, a qualunque numero di turni.
const ALTEZZA_CARTA = 86
const GAP_CARTE = 12
const STACCO_CONNETTORE = 16

type NodoAlbero = { turno: number; posizione: number; riga: number }

function righeAlbero(turniTotali: number): NodoAlbero[] {
  const nodi: NodoAlbero[] = []
  let riga = 0
  function visita(turno: number, posizione: number) {
    if (turno > 1) visita(turno - 1, posizione * 2)
    nodi.push({ turno, posizione, riga: riga++ })
    if (turno > 1) visita(turno - 1, posizione * 2 + 1)
  }
  if (turniTotali > 0) visita(turniTotali, 0)
  return nodi
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
      <PopupSpiegazione userId={membership.user_id} hintKey="tabellone-playoff-v2" titolo="Come funzionano i playoff">
        <p>A fine stagione regolare la classifica si divide in due tabelloni a eliminazione diretta, giocati in parallelo. Il <strong>Title Playoff</strong> prende le prime 8 e assegna il titolo; il <strong>Draft Playoff</strong> prende tutte le altre squadre.</p>
        <p>Ogni sfida mostra andata, ritorno e totale. Passa chi segna di più nella somma delle due partite (i gol in trasferta non valgono doppio); in caso di parità il ritorno va ai <strong>supplementari</strong> e poi ai <strong>rigori</strong>. La <strong>finale</strong> invece è una gara secca in campo neutro.</p>
        <p>Il Draft Playoff non è un ripiego: come va lì, e chi ti elimina, decide l'ordine di scelta nel prossimo mercato a scelte. Vale la pena giocarselo fino in fondo.</p>
      </PopupSpiegazione>
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
        <div className="tabellone-schede" role="tablist" aria-label="Scegli tabellone">
          {bracketsStagione.map((b) => (
            <button key={b.tipo} type="button" role="tab" aria-selected={tabAttivo === b.tipo}
              className={`tabellone-scheda tabellone-scheda--${b.tipo} ${tabAttivo === b.tipo ? 'is-attiva' : ''}`}
              onClick={() => setTabAttivo(b.tipo)}>
              <img src={LOGO_FASE[b.tipo]} alt={TITOLO[b.tipo]} />
            </button>
          ))}
        </div>
      )}

      {bracketAttivo && (() => {
        const bracket = bracketAttivo
        const suoi = ties.filter((t) => t.bracket_id === bracket.id)
        const turniTotali = turniTotaliDa(suoi)
        const tieMap = new Map(suoi.map((t) => [`${t.turno}:${t.posizione}`, t]))

        const campione = bracket.stato === 'concluso' && bracket.vincitore_team_id ? teamById.get(bracket.vincitore_team_id) : undefined

        return <div className={`tabellone-blocco tabellone-blocco--${bracket.tipo}`}>
          <section className="tabellone-eroe">
            <div className="tabellone-eroe__comp">
              {/* Il logo della fase c'e' gia' nelle schede qui sopra; resta
                  qui solo se il tabellone e' uno (niente schede). */}
              {bracketsStagione.length < 2 && <img src={LOGO_FASE[bracket.tipo]} alt={TITOLO[bracket.tipo]} />}
              <strong>Tabellone</strong>
            </div>
            <div className="tabellone-eroe__campione">
              {campione ? <>
                <small>{bracket.tipo === 'title' ? `Campione · Season ${league.stagione_corrente}` : 'Vince il Draft Playoff'}</small>
                <b>{campione.nome}</b>
                <span className="tabellone-eroe__stemma"><Crest value={campione.stemma_url} imageUrl={dati.crestUrlByTeamId.get(campione.id)} size="large" /></span>
              </> : <>
                <small>Season {league.stagione_corrente}</small>
                <b>{bracket.tipo === 'title' ? 'Chi vince il titolo?' : 'In palio la prima scelta'}</b>
              </>}
            </div>
          </section>

          {turniTotali > 0 && <AlberoBracket turniTotali={turniTotali} tieMap={tieMap} dati={datiComuni} />}
        </div>
      })()}
    </div>
  </main>
}

function AlberoBracket({ turniTotali, tieMap, dati }: {
  turniTotali: number
  tieMap: Map<string, BracketTie>
  dati: DatiTabellone
}) {
  const nodi = righeAlbero(turniTotali)
  const rigaDi = new Map(nodi.map((n) => [`${n.turno}:${n.posizione}`, n.riga]))
  const frazione = (turno: number) => turniTotali > 1 ? (turno - 1) / (turniTotali - 1) : 0
  const sinistra = (turno: number) => `calc((100% - var(--larghezza-carta)) * ${frazione(turno)})`
  const passo = ALTEZZA_CARTA + GAP_CARTE

  return <div className="albero" style={{ '--larghezza-carta': `min(250px, calc(100% - ${46 * (turniTotali - 1)}px))`, height: nodi.length * passo - GAP_CARTE } as React.CSSProperties}>
    {nodi.filter((n) => n.turno < turniTotali).map((n) => {
      // Dal centro del lato destro della carta figlia, in orizzontale, poi in
      // verticale fino al bordo della carta del turno dopo.
      const rigaPadre = rigaDi.get(`${n.turno + 1}:${Math.floor(n.posizione / 2)}`) ?? 0
      const centro = n.riga * passo + ALTEZZA_CARTA / 2
      const sopra = n.riga < rigaPadre
      const bordoPadre = sopra ? rigaPadre * passo : rigaPadre * passo + ALTEZZA_CARTA
      const x = `calc(${sinistra(n.turno)} + var(--larghezza-carta))`
      return <span className="albero__linea" aria-hidden="true" key={`l-${n.turno}-${n.posizione}`} style={{
        left: x,
        top: Math.min(centro, bordoPadre),
        width: STACCO_CONNETTORE,
        height: Math.abs(bordoPadre - centro),
        borderTopWidth: sopra ? 2 : 0,
        borderBottomWidth: sopra ? 0 : 2,
      }} />
    })}
    {nodi.map((n) => (
      <div className="albero__posto" key={`${n.turno}-${n.posizione}`} style={{ top: n.riga * passo, left: sinistra(n.turno), height: ALTEZZA_CARTA }}>
        <CartaSfida tie={tieMap.get(`${n.turno}:${n.posizione}`)} turno={n.turno} turniTotali={turniTotali} dati={dati} />
      </div>
    ))}
  </div>
}

function CartaSfida({ tie, turno, turniTotali, dati }: {
  tie: BracketTie | undefined
  turno: number
  turniTotali: number
  dati: DatiTabellone
}) {
  const { teamById, fixturePerTie, matchPerFixture, crestUrls, onOpenMatch } = dati
  const alta = tie?.alta_team_id ? teamById.get(tie.alta_team_id) ?? null : null
  const bassa = tie?.bassa_team_id ? teamById.get(tie.bassa_team_id) ?? null : null
  const fx = tie ? fixturePerTie.get(tie.id) ?? [] : []
  const secca = !!tie?.gara_secca || fx.length === 1
  const colonne = secca ? ['RIS'] : ['A', 'R', 'TOT']

  const golDi = (team: Team | null, f: Fixture | undefined) => {
    const m = f ? matchPerFixture.get(f.id) : undefined
    if (!team || !f || !m) return null
    return f.home_team_id === team.id ? m.gol_home : m.gol_away
  }
  const rigoriDi = (team: Team | null) => {
    for (const f of fx) {
      const m = matchPerFixture.get(f.id)
      if (team && m && m.rigori_home != null) return f.home_team_id === team.id ? m.rigori_home : m.rigori_away
    }
    return null
  }
  const andata = fx.find((f) => f.mano === 1) ?? fx[0]
  const ritorno = secca ? undefined : fx.find((f) => f.mano === 2)

  const riga = (team: Team | null, seed: number | null | undefined, chiave: string) => {
    if (!team) return <div className="carta__riga carta__riga--vuota" key={chiave}><span>{turno === 1 && tie && (alta || bassa) ? 'Passa senza giocare' : 'Da definire'}</span></div>
    const a = golDi(team, andata)
    const r = golDi(team, ritorno)
    const totale = a == null && r == null ? null : (a ?? 0) + (r ?? 0)
    const rig = rigoriDi(team)
    // Riga luminosa solo per chi ha passato il turno: a sfida aperta le due
    // righe restano neutre, altrimenti sembra che abbia gia' vinto qualcuno.
    const deciso = tie?.stato === 'concluso' && tie.vincitore_team_id != null
    const esito = deciso ? (tie!.vincitore_team_id === team.id ? 'is-vincitore is-luce' : 'is-eliminato') : ''
    const cella = (valore: number | null, f: Fixture | undefined, forte = false) => {
      const m = f ? matchPerFixture.get(f.id) : undefined
      const testo = <>{valore == null ? '–' : valore}{forte && rig != null && <sup title="Calci di rigore">{rig}</sup>}</>
      return m
        ? <button type="button" className={`carta__num ${forte ? 'is-forte' : ''}`} onClick={() => onOpenMatch(m.id)}>{testo}</button>
        : <span className={`carta__num ${forte ? 'is-forte' : ''}`}>{testo}</span>
    }
    return <div className={`carta__riga ${esito}`} key={chiave}>
      <span className="carta__stemma"><Crest value={team.stemma_url} imageUrl={crestUrls.get(team.id)} size="small" /></span>
      <span className="carta__nome"><span>{team.nome}</span>{seed != null && <i>{seed}</i>}</span>
      {secca
        ? <>{cella(a, andata, true)}</>
        : <>{cella(a, andata)}{cella(r, ritorno)}{cella(totale, undefined, true)}</>}
    </div>
  }

  return <div className={`carta ${secca ? 'carta--secca' : ''}`}>
    <div className="carta__testa">
      <span>{nomeTurno(turno, turniTotali)}{tie?.gara_secca ? ' · campo neutro' : ''}</span>
      {colonne.map((c) => <b key={c}>{c}</b>)}
    </div>
    {riga(alta, tie?.alta_seed, 'alta')}
    {riga(bassa, tie?.bassa_seed, 'bassa')}
  </div>
}
