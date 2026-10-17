import { useEffect, useMemo, useState } from 'react'
import { supabase } from '../lib/supabase'
import { useSeasonData } from '../lib/useSeasonData'
import type { League, Membership } from '../types'
import { Crest } from './Crest'
import { GameNav, type GameView } from './GameNav'
import { LoadingLogo } from './LoadingLogo'

// Il pubblico (docs/decisioni-conferenze-stampa.md §2b): l'umore dei tifosi di ogni squadra, da 0 a 100,
// della tua squadra, con l'andamento nel tempo (tabella pubblico_storico). Muove il bonus casa: pieno (+2,0 di overall) da 80 in su, nessun bonus a 10 o
// meno, mai uno svantaggio. Qui vedi solo il tuo.

const BONUS_MAX = 2
const moltiplicatore = (p: number) => Math.max(0, Math.min(1, (p - 10) / 70))
export const bonus = (p: number) => BONUS_MAX * moltiplicatore(p)
export const fmtBonus = (b: number) => `+${b.toFixed(1).replace('.', ',')}`

export function fascia(p: number) {
  if (p >= 80) return { testo: 'Stadio infuocato', classe: 'ottimo' }
  if (p >= 60) return { testo: 'Stadio caldo', classe: 'buono' }
  if (p >= 40) return { testo: 'Ambiente teso', classe: 'medio' }
  if (p >= 20) return { testo: 'Stadio freddo', classe: 'basso' }
  return { testo: 'Contestazione', classe: 'critico' }
}

type Punto = { etichetta: string; valore: number }

// L'andamento della stagione corrente: un punto per giornata (l'ultimo valore di quella giornata), piu' il
// valore di partenza. Le variazioni arrivano da pubblico_storico, riempita da un trigger su teams.pubblico.
function useAndamento(leagueId: number, teamId: number, stagione: number) {
  const [punti, setPunti] = useState<Punto[] | null>(null)
  useEffect(() => {
    let vivo = true
    void supabase.from('pubblico_storico').select('giornata, prima, valore').eq('team_id', teamId).eq('stagione', stagione).order('id').then(({ data }) => {
      if (!vivo) return
      const righe = (data ?? []) as Array<{ giornata: number; prima: number; valore: number }>
      if (!righe.length) { setPunti([]); return }
      const perGiornata = new Map<number, number>()
      for (const x of righe) perGiornata.set(x.giornata, Number(x.valore))
      // "Inizio" e' il valore prima della prima variazione, oppure, se prima della giornata 1 ci sono
      // gia' state variazioni (conferenze), il loro ultimo valore.
      const out: Punto[] = [{ etichetta: 'Inizio', valore: perGiornata.get(0) ?? Number(righe[0].prima) }]
      for (const [g, v] of [...perGiornata.entries()].sort((a, b) => a[0] - b[0])) if (g > 0) out.push({ etichetta: `G${g}`, valore: v })
      setPunti(out)
    })
    return () => { vivo = false }
  }, [leagueId, teamId, stagione])
  return punti
}

function GraficoPubblico({ punti }: { punti: Punto[] }) {
  const L = 320, A = 170, m = { s: 26, d: 14, su: 12, g: 26 }
  const w = L - m.s - m.d, h = A - m.su - m.g
  const x = (i: number) => m.s + (punti.length === 1 ? w / 2 : (i / (punti.length - 1)) * w)
  const y = (v: number) => m.su + (1 - v / 100) * h
  const linea = punti.map((q, i) => `${i ? 'L' : 'M'}${x(i).toFixed(1)},${y(q.valore).toFixed(1)}`).join(' ')
  const area = `${linea} L${x(punti.length - 1).toFixed(1)},${y(0)} L${x(0).toFixed(1)},${y(0)} Z`
  const passo = Math.max(1, Math.ceil(punti.length / 6))
  const ultimo = punti[punti.length - 1]
  return <svg className="pubblico-grafico" viewBox={`0 0 ${L} ${A}`} role="img" aria-label={`Andamento del pubblico: ora ${Math.round(ultimo.valore)} su 100`}>
    <defs><linearGradient id="pubblico-area" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stopColor="#7be3a0" stopOpacity=".38" /><stop offset="1" stopColor="#7be3a0" stopOpacity="0" /></linearGradient></defs>
    {[0, 20, 40, 60, 80, 100].map((v) => <g key={v}>
      <line className={v === 80 ? 'pubblico-grafico__soglia' : 'pubblico-grafico__griglia'} x1={m.s} x2={L - m.d} y1={y(v)} y2={y(v)} />
      <text className="pubblico-grafico__asse" x={m.s - 6} y={y(v) + 3} textAnchor="end">{v}</text>
    </g>)}
    <text className="pubblico-grafico__nota" x={L - m.d} y={y(80) - 4} textAnchor="end">bonus casa pieno</text>
    <path d={area} fill="url(#pubblico-area)" />
    <path className="pubblico-grafico__linea" d={linea} />
    {punti.map((q, i) => <g key={i}>
      {(i % passo === 0 || i === punti.length - 1) && <text className="pubblico-grafico__asse" x={x(i)} y={A - 8} textAnchor="middle">{q.etichetta}</text>}
      {i < punti.length - 1 && <circle className="pubblico-grafico__punto" cx={x(i)} cy={y(q.valore)} r="2.2" />}
    </g>)}
    <circle className="pubblico-grafico__ultimo" cx={x(punti.length - 1)} cy={y(ultimo.valore)} r="5" />
    <text className="pubblico-grafico__valore" x={Math.min(x(punti.length - 1), L - m.d - 8)} y={y(ultimo.valore) - 10} textAnchor="middle">{Math.round(ultimo.valore)}</text>
  </svg>
}

type Props = { membership: Membership; onNavigate: (view: GameView) => void; onOpenTeam?: (teamId: number) => void }

export function PaginaPubblico({ membership, onNavigate }: Props) {
  const league = membership.league as League
  const dati = useSeasonData(membership)
  const [spiega, setSpiega] = useState(false)
  const andamento = useAndamento(league.id, membership.id, league.stagione_corrente ?? 1)
  const righe = useMemo(() => [...dati.teamById.values()]
    .filter((t) => t.attiva !== false)
    .map((t) => ({ team: t, pubblico: Number(t.pubblico ?? 100) }))
    .sort((a, b) => b.pubblico - a.pubblico || a.team.nome.localeCompare(b.team.nome)), [dati.teamById])
  const mio = righe.find((r) => r.team.id === membership.id)
  const f = mio ? fascia(mio.pubblico) : null

  return <main className="app-shell season-shell pubblico-shell">
    <GameNav league={league} active="pubblico" onNavigate={onNavigate} />
    <header className="topbar season-topbar"><div className="brand-lockup brand-lockup--dark"><img src="/specialone-mark.svg" alt="" /><span>SpecialOne</span></div><span>Pubblico</span></header>
    <div className="season-page season-page--narrow pubblico-page">
      <section className="alerts-heading">
        <div><p className="kicker">{league.nome}</p><h1>Pubblico.</h1>
          <p>L'umore dei tifosi di ogni squadra. Più è alto, più il tuo stadio spinge: da 80 su 100 in su il bonus casa è pieno. Lo vedono tutti, anche prima di venire a giocare da te.</p></div>
      </section>

      {dati.loading ? <section className="season-state is-caricamento"><LoadingLogo compatto /><h2>Carico il pubblico…</h2><span className="caricamento-barra" aria-hidden="true" /></section> : <>
        {mio && f && <button className={`pubblico-mio pubblico-mio--${f.classe}`} type="button" onClick={() => setSpiega(true)} aria-label={`Il tuo pubblico: ${Math.round(mio.pubblico)} su 100, ${f.testo}. Tocca per capire come funziona.`}>
          <span className="pubblico-mio__testa"><small>Il tuo pubblico</small><em aria-hidden="true">Come funziona ›</em></span>
          <span className="pubblico-mio__corpo">
            <span className="pubblico-mio__stemma"><Crest value={mio.team.stemma_url ?? null} stelle={mio.team.titoli_title} imageUrl={dati.crestUrlByTeamId.get(mio.team.id)} size="large" /></span>
            <span className="pubblico-mio__valore"><b>{Math.round(mio.pubblico)}</b><small>/100</small></span>
            <span className="pubblico-mio__etichetta">{f.testo}</span>
          </span>
          <span className="pubblico-barra pubblico-barra--grande" aria-hidden="true"><i style={{ width: `${100 - mio.pubblico}%` }} /><u style={{ left: '80%' }} /></span>
          <span className="pubblico-mio__bonus">Bonus casa: <b>{fmtBonus(bonus(mio.pubblico))}</b> di overall <em>{mio.pubblico >= 80 ? '(il massimo)' : `(il massimo è ${fmtBonus(BONUS_MAX)})`}</em></span>
        </button>}

        <h2 className="pubblico-titolo">Come sta andando</h2>
        <section className="pubblico-andamento">
          {andamento === null ? <p className="pubblico-andamento__vuoto">Carico l'andamento…</p>
            : andamento.length === 0 ? <p className="pubblico-andamento__vuoto">Il pubblico per ora non si è mosso. L'andamento comparirà qui dopo la prossima conferenza stampa o la prossima partita.</p>
            : <GraficoPubblico punti={andamento} />}
        </section>
      </>}
    </div>

    {spiega && <div className="popup-spiegazione-sfondo" role="dialog" aria-modal="true" aria-label="Come funziona il pubblico" onClick={() => setSpiega(false)}>
      <div className="popup-spiegazione popup-morale" onClick={(e) => e.stopPropagation()}>
        <h2>Il pubblico</h2>
        <div className="popup-spiegazione__corpo">
          <p>Ogni squadra ha un <b>umore del pubblico da 0 a 100</b>, uguale per tutti all'inizio (100). Nella pagina vedi il tuo e come è cambiato nella stagione.</p>
          <h3>Perché conta</h3>
          <p>Decide il <b>bonus casa</b>: quando giochi in casa la tua squadra rende come con <b>+2,0 di overall</b> in attacco e a centrocampo. Con il pubblico <b>da 80 in su il bonus è pieno</b>; sotto cala fino a <b>zero a 10 o meno</b>. Non diventa mai uno svantaggio. Fra pubblico al massimo e in rottura ballano circa <b>5 punti in una stagione da 38 giornate</b>: è più del morale.</p>
          <h3>Cosa lo muove</h3>
          <ul>
            <li><b>Conferenze stampa</b> — è la leva più forte. Rispetto per i tifosi, ambizione e difesa del club lo alzano; dare la colpa a loro o allo stadio lo affonda. Lo scherno verso gli avversari lo fa salire.</li>
            <li><b>Risultati</b> — poco e lentamente: vittoria +1,5, pareggio −0,5, sconfitta −2,5 (in trasferta la metà).</li>
            <li><b>Rivalità</b> — contro una rivale la partita vale di più: vincere lo alza, perdere lo abbassa.</li>
            <li><b>Il capitano</b> — se la protesta è forte, un buon capitano risponde ai tifosi e li calma un po'.</li>
          </ul>
          <h3>Le fasce</h3>
          <ul className="popup-morale__fasce">
            {[['ottimo', 'Stadio infuocato', '80–100'], ['buono', 'Stadio caldo', '60–79'], ['medio', 'Ambiente teso', '40–59'], ['basso', 'Stadio freddo', '20–39'], ['critico', 'Contestazione', '0–19']].map(([c, t, r]) =>
              <li key={c}><i className={`morale-squadra__fascia morale-squadra__fascia--${c}`} /><b>{t}</b> <span>{r}</span></li>)}
          </ul>
        </div>
        <button className="button button--primary" type="button" onClick={() => setSpiega(false)}>Ho capito</button>
      </div>
    </div>}
  </main>
}
