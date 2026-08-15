import { useEffect, useMemo, useRef, useState } from 'react'
import { supabase } from '../lib/supabase'
import { cognome } from '../lib/nomi'
import { useSeasonData } from '../lib/useSeasonData'
import type { League, Membership } from '../types'
import { GameNav, type GameView } from './GameNav'
import { Forma, formaPerSquadra, SeasonState, TeamLabel } from './SeasonUI'
import { Crest } from './Crest'

type Props = { membership: Membership; onNavigate: (view: GameView) => void; onOpenTeam: (teamId: number) => void }

type RigaClassificaGiocatori = {
  playerInstanceId: number
  nome: string
  foto?: string
  teamId: number
  gol: number
  assist: number
}
type RigaStatGiocatore = { player_instance_id: number; team_id: number; gol: number; assist: number }

const SCHEDE = ['classifica', 'marcatori', 'assistman'] as const
type Scheda = typeof SCHEDE[number]
const ETICHETTE_SCHEDA: Record<Scheda, string> = { classifica: 'Classifica', marcatori: 'Marcatori', assistman: 'Assist' }

export function Standings({ membership, onNavigate, onOpenTeam }: Props) {
  const league = membership.league as League
  const data = useSeasonData(membership)
  const forma = useMemo(() => formaPerSquadra(data.fixtures, data.matchByFixture), [data.fixtures, data.matchByFixture])

  const [scheda, setScheda] = useState<Scheda>('classifica')
  const [righeGiocatori, setRigheGiocatori] = useState<RigaClassificaGiocatori[]>([])
  const [caricoGiocatori, setCaricoGiocatori] = useState(true)

  useEffect(() => {
    let attivo = true
    async function carica() {
      setCaricoGiocatori(true)
      // L'aggregazione avviene nel database sulla stagione corrente: non
      // dipende dal caricamento asincrono di fixture e match nel browser.
      const { data: righeStat, error } = await supabase
        .rpc('classifica_giocatori_stagione', { p_league_id: league.id })
      if (error || !attivo) { if (attivo) setCaricoGiocatori(false); return }

      const aggregati = new Map<number, { teamId: number; gol: number; assist: number }>()
      for (const riga of (righeStat ?? []) as RigaStatGiocatore[]) {
        const voce = aggregati.get(riga.player_instance_id) ?? { teamId: riga.team_id, gol: 0, assist: 0 }
        voce.gol += riga.gol
        voce.assist += riga.assist
        aggregati.set(riga.player_instance_id, voce)
      }

      const instanceIds = [...aggregati.keys()]
      const { data: istanze } = instanceIds.length
        ? await supabase.from('player_instances').select('id, players(nome, foto_url)').in('id', instanceIds)
        : { data: [] }
      if (!attivo) return

      const anagrafica = new Map((istanze ?? []).map((riga) => [riga.id, riga.players as unknown as { nome: string; foto_url: string | null } | null]))
      const fotoFirmate = await Promise.all((istanze ?? [])
        .filter((riga) => (anagrafica.get(riga.id))?.foto_url)
        .map(async (riga) => {
          const path = anagrafica.get(riga.id)!.foto_url!
          if (path.startsWith('http')) return [riga.id, path] as const
          const { data: signed } = await supabase.storage.from('player-photos').createSignedUrl(path, 3600)
          return [riga.id, signed?.signedUrl] as const
        }))
      if (!attivo) return
      const fotoPerId = new Map(fotoFirmate.filter((entry): entry is readonly [number, string] => Boolean(entry[1])))

      const righe: RigaClassificaGiocatori[] = [...aggregati.entries()]
        .filter(([, voce]) => voce.gol > 0 || voce.assist > 0)
        .map(([playerInstanceId, voce]) => ({
          playerInstanceId, teamId: voce.teamId, gol: voce.gol, assist: voce.assist,
          nome: cognome(anagrafica.get(playerInstanceId)?.nome ?? `Giocatore ${playerInstanceId}`),
          foto: fotoPerId.get(playerInstanceId),
        }))
      if (attivo) { setRigheGiocatori(righe); setCaricoGiocatori(false) }
    }
    void carica()
    return () => { attivo = false }
  }, [league.id])

  const marcatori = useMemo(
    () => [...righeGiocatori].sort((a, b) => b.gol - a.gol || b.assist - a.assist).slice(0, 10),
    [righeGiocatori],
  )
  const assistman = useMemo(
    () => [...righeGiocatori].sort((a, b) => b.assist - a.assist || b.gol - a.gol).slice(0, 10),
    [righeGiocatori],
  )

  // Swipe orizzontale sul pannello, in aggiunta ai tab: non e' l'unico modo
  // di cambiare scheda, ma e' quello che l'utente ha chiesto esplicitamente.
  const tocco = useRef<{ x: number; y: number } | null>(null)
  function alTouchStart(evento: React.TouchEvent) {
    const t = evento.touches[0]
    tocco.current = t ? { x: t.clientX, y: t.clientY } : null
  }
  function alTouchEnd(evento: React.TouchEvent) {
    const inizio = tocco.current
    tocco.current = null
    if (!inizio) return
    const t = evento.changedTouches[0]
    if (!t) return
    const dx = t.clientX - inizio.x
    const dy = Math.abs(t.clientY - inizio.y)
    if (Math.abs(dx) < 50 || dy > Math.abs(dx) * 0.6) return
    const indice = SCHEDE.indexOf(scheda)
    if (dx < 0 && indice < SCHEDE.length - 1) setScheda(SCHEDE[indice + 1])
    if (dx > 0 && indice > 0) setScheda(SCHEDE[indice - 1])
  }

  function rigaGiocatore(riga: RigaClassificaGiocatori, indice: number, chiave: 'gol' | 'assist') {
    return <div className="players-standings-row" key={riga.playerInstanceId}>
      <span className="standings-position">{indice + 1}</span>
      <div className="players-standings-giocatore" onClick={() => onOpenTeam(riga.teamId)} role="button" tabIndex={0}>
        <span className="players-standings-foto">{riga.foto ? <img src={riga.foto} alt="" /> : null}</span>
        <span>
          <strong>{riga.nome}</strong>
          <small><Crest value={data.teamById.get(riga.teamId)?.stemma_url ?? null} imageUrl={data.crestUrlByTeamId.get(riga.teamId)} />{data.teamById.get(riga.teamId)?.nome ?? 'Squadra'}</small>
        </span>
      </div>
      <strong className="players-standings-valore">{riga[chiave]}</strong>
      <span className="players-standings-secondario">{chiave === 'gol' ? `${riga.assist} assist` : `${riga.gol} gol`}</span>
    </div>
  }

  return <main className="app-shell season-shell">
    <GameNav league={league} active="table" onNavigate={onNavigate} />
    <header className="topbar season-topbar"><div className="brand-lockup brand-lockup--dark"><img src="/specialone-mark.svg" alt="" /><span>SpecialOne</span></div><span>Aggiornata alla giornata {Math.max(0, data.currentGiornata - 1)}</span></header>
    <SeasonState loading={data.loading} error={data.error} onRetry={data.reload} />
    {!data.loading && !data.error && <div className="season-page season-page--narrow">
      <section className="season-title-row"><div><p className="kicker">Stagione {league.stagione_corrente} · {league.nome}</p><h1>Classifica.</h1><p>Punti, risultati e differenza reti aggiornati dopo ogni simulazione.</p></div><div className="season-total"><strong>{league.n_squadre}</strong><span>squadre</span></div></section>

      <div className="standings-tabs" role="tablist">
        {SCHEDE.map((voce) => <button key={voce} type="button" role="tab" aria-selected={scheda === voce} className={scheda === voce ? 'is-active' : ''} onClick={() => setScheda(voce)}>{ETICHETTE_SCHEDA[voce]}</button>)}
      </div>

      <section className="standings-panel" onTouchStart={alTouchStart} onTouchEnd={alTouchEnd}>
        {scheda === 'classifica' && <>
          <div className="standings-head"><span>POS</span><span>SQUADRA</span><span>PG</span><span>V</span><span>N</span><span>P</span><span>GF</span><span>GS</span><span>DR</span><span>PT</span></div>
          <div className="standings-body">
            {data.standings.map((standing, index) => <div className={`standings-row ${standing.team_id === membership.id ? 'is-mine' : ''}`} key={standing.team_id}>
              <span className="standings-position">{standing.posizione ?? index + 1}</span>
              <div className="standings-squadra">
                <TeamLabel team={data.teamById.get(standing.team_id)} imageUrl={data.crestUrlByTeamId.get(standing.team_id)} onClick={() => onOpenTeam(standing.team_id)} />
                <Forma esiti={forma.get(standing.team_id)} />
              </div>
              <span>{standing.giocate}</span><span>{standing.vittorie}</span><span>{standing.pareggi}</span><span>{standing.sconfitte}</span><span>{standing.gol_fatti}</span><span>{standing.gol_subiti}</span><span>{standing.differenza_reti > 0 ? `+${standing.differenza_reti}` : standing.differenza_reti}</span><strong>{standing.punti}</strong>
            </div>)}
          </div>
          <footer><span><i /> La tua squadra</span><small>Ordine: punti · scontri diretti · differenza reti · gol fatti</small></footer>
        </>}

        {scheda === 'marcatori' && (caricoGiocatori
          ? <p className="season-empty">Carico la classifica marcatori…</p>
          : marcatori.length === 0
            ? <p className="season-empty">Nessun gol segnato finora in questa stagione.</p>
            : <div className="players-standings-body">{marcatori.map((riga, indice) => rigaGiocatore(riga, indice, 'gol'))}</div>)}

        {scheda === 'assistman' && (caricoGiocatori
          ? <p className="season-empty">Carico la classifica assistman…</p>
          : assistman.length === 0
            ? <p className="season-empty">Nessun assist registrato finora in questa stagione.</p>
            : <div className="players-standings-body">{assistman.map((riga, indice) => rigaGiocatore(riga, indice, 'assist'))}</div>)}
      </section>
    </div>}
  </main>
}
