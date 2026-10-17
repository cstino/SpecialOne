import { useEffect, useMemo, useState } from 'react'
import { supabase } from '../lib/supabase'
import { useSeasonData } from '../lib/useSeasonData'
import type { League, Membership } from '../types'
import { Crest } from './Crest'
import { GameNav, type GameView } from './GameNav'
import { LoadingLogo } from './LoadingLogo'

// Il menù Rivalità (docs/decisioni-conferenze-stampa.md §2): tutte le squadre della lega e il grado di
// rivalità con la propria, da 0 a 100%. Il grado e' reciproco e lo vedi solo tu (le righe sono visibili
// solo alle squadre della coppia).

type Fascia = { testo: string; classe: string }
function fascia(grado: number): Fascia {
  if (grado >= 75) return { testo: 'Odio sportivo', classe: 'altissima' }
  if (grado >= 50) return { testo: 'Rivali', classe: 'alta' }
  if (grado >= 25) return { testo: 'Tensione', classe: 'media' }
  if (grado > 0) return { testo: 'Frecciatine', classe: 'bassa' }
  return { testo: 'Nessuna rivalità', classe: 'nulla' }
}

type Props = { membership: Membership; onNavigate: (view: GameView) => void; onOpenTeam?: (teamId: number) => void; onCambiaRivale?: () => void }

export function Rivalita({ membership, onNavigate, onOpenTeam, onCambiaRivale }: Props) {
  const league = membership.league as League
  const dati = useSeasonData(membership)
  const [gradi, setGradi] = useState<Map<number, number> | null>(null)

  useEffect(() => {
    let vivo = true
    void supabase.from('rivalita').select('team_a, team_b, grado').eq('league_id', league.id).then(({ data }) => {
      if (!vivo) return
      const mappa = new Map<number, number>()
      for (const r of (data ?? []) as Array<{ team_a: number; team_b: number; grado: number }>) {
        const altra = r.team_a === membership.id ? r.team_b : r.team_b === membership.id ? r.team_a : null
        if (altra != null) mappa.set(altra, Number(r.grado))
      }
      setGradi(mappa)
    })
    return () => { vivo = false }
  }, [league.id, membership.id])

  const sceltoDa = useMemo(() => [...dati.teamById.values()].filter((t) => t.rivale_id === membership.id), [dati.teamById, membership.id])

  const righe = useMemo(() => [...dati.teamById.values()]
    .filter((t) => t.id !== membership.id && t.attiva !== false)
    .map((t) => ({ team: t, grado: gradi?.get(t.id) ?? 0 }))
    .sort((a, b) => b.grado - a.grado || a.team.nome.localeCompare(b.team.nome)), [dati.teamById, gradi, membership.id])

  return <main className="app-shell season-shell rivalita-shell">
    <GameNav league={league} active="rivalita" onNavigate={onNavigate} />
    <header className="topbar season-topbar"><div className="brand-lockup brand-lockup--dark"><img src="/specialone-mark.svg" alt="" /><span>SpecialOne</span></div><span>Rivalità</span></header>
    <div className="season-page season-page--narrow rivalita-page">
      <section className="alerts-heading">
        <div><p className="kicker">{league.nome}</p><h1>Rivalità.</h1>
          <p>Il rapporto con ogni squadra, da 0 a 100%. Sale se in conferenza stampa schernisci, attacchi o disprezzi una squadra (qualsiasi, anche una che non affronti presto), scende se la elogi, e si raffredda di un punto a giornata. Ogni risposta vale +10 se la attacchi, −6 se la elogi. Negli scontri diretti il risultato pesa su morale e pubblico, in proporzione al grado. Lo vedi solo tu.</p>
          {onCambiaRivale && <p>Il tuo derby: <strong>{membership.rivale_id ? dati.teamById.get(membership.rivale_id)?.nome ?? '—' : 'non ancora scelto'}</strong>. <button className="rivalita-cambia" type="button" onClick={onCambiaRivale}>{membership.rivale_id ? 'Cambia rivale' : 'Scegli il rivale'}</button></p>}
          {sceltoDa.length > 0 && <p className="rivalita-scelto-da">{sceltoDa.map((t) => t.nome).join(', ')} {sceltoDa.length === 1 ? 'ti ha scelto' : 'ti hanno scelto'} come rivale: {sceltoDa.length === 1 ? 'la vostra partita è sempre un derby' : 'le vostre partite sono sempre derby'}.</p>}</div>
      </section>
      {dati.loading || gradi === null
        ? <section className="season-state is-caricamento"><LoadingLogo compatto /><h2>Carico le rivalità…</h2><span className="caricamento-barra" aria-hidden="true" /></section>
        : <ol className="rivalita-lista">
          {righe.map(({ team, grado }) => {
            const f = fascia(grado)
            return <li key={team.id}>
              <button className={`rivalita-riga rivalita-riga--${f.classe}`} type="button" onClick={() => onOpenTeam?.(team.id)} disabled={!onOpenTeam}
                aria-label={`${team.nome}: rivalità ${Math.round(grado)} per cento, ${f.testo}`}>
                <span className="rivalita-riga__stemma"><Crest value={team.stemma_url ?? null} stelle={team.titoli_title} imageUrl={dati.crestUrlByTeamId.get(team.id)} size="small" /></span>
                <span className="rivalita-riga__nome"><strong>{team.nome}</strong><small>{f.testo}</small></span>
                <span className="rivalita-riga__barra" aria-hidden="true"><i style={{ width: `${Math.max(grado, grado > 0 ? 3 : 0)}%` }} /></span>
                <b className="rivalita-riga__grado">{Math.round(grado)}<small>%</small></b>
              </button>
            </li>
          })}
        </ol>}
    </div>
  </main>
}
