import { useMemo, useState } from 'react'
import { useSeasonData } from '../lib/useSeasonData'
import type { League, Membership } from '../types'
import { Crest } from './Crest'
import { GameNav, type GameView } from './GameNav'
import { LoadingLogo } from './LoadingLogo'

// Il pubblico (docs/decisioni-conferenze-stampa.md §2b): l'umore dei tifosi di ogni squadra, da 0 a 100,
// visibile a tutta la lega. Muove il bonus casa: pieno (+2,0 di overall) da 80 in su, nessun bonus a 10 o
// meno, mai uno svantaggio. Chi va a giocare in trasferta sa che stadio trova.

const BONUS_MAX = 2
const moltiplicatore = (p: number) => Math.max(0, Math.min(1, (p - 10) / 70))
const bonus = (p: number) => BONUS_MAX * moltiplicatore(p)
const fmtBonus = (b: number) => `+${b.toFixed(1).replace('.', ',')}`

function fascia(p: number) {
  if (p >= 80) return { testo: 'Stadio infuocato', classe: 'ottimo' }
  if (p >= 60) return { testo: 'Stadio caldo', classe: 'buono' }
  if (p >= 40) return { testo: 'Ambiente teso', classe: 'medio' }
  if (p >= 20) return { testo: 'Stadio freddo', classe: 'basso' }
  return { testo: 'Contestazione', classe: 'critico' }
}

type Props = { membership: Membership; onNavigate: (view: GameView) => void; onOpenTeam?: (teamId: number) => void }

export function PaginaPubblico({ membership, onNavigate, onOpenTeam }: Props) {
  const league = membership.league as League
  const dati = useSeasonData(membership)
  const [spiega, setSpiega] = useState(false)
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

        <h2 className="pubblico-titolo">Tutta la lega</h2>
        <ol className="pubblico-lista">
          {righe.map(({ team, pubblico }) => {
            const g = fascia(pubblico)
            return <li key={team.id}>
              <button className={`pubblico-riga pubblico-riga--${g.classe}${team.id === membership.id ? ' is-mia' : ''}`} type="button" onClick={() => onOpenTeam?.(team.id)} disabled={!onOpenTeam}
                aria-label={`${team.nome}: pubblico ${Math.round(pubblico)} su 100, ${g.testo}, bonus casa ${fmtBonus(bonus(pubblico))}`}>
                <span className="pubblico-riga__stemma"><Crest value={team.stemma_url ?? null} stelle={team.titoli_title} imageUrl={dati.crestUrlByTeamId.get(team.id)} size="small" /></span>
                <span className="pubblico-riga__nome"><strong>{team.nome}</strong><small>{g.testo} · casa {fmtBonus(bonus(pubblico))}</small></span>
                <span className="pubblico-barra" aria-hidden="true"><i style={{ width: `${100 - pubblico}%` }} /></span>
                <b className="pubblico-riga__valore">{Math.round(pubblico)}</b>
              </button>
            </li>
          })}
        </ol>
      </>}
    </div>

    {spiega && <div className="popup-spiegazione-sfondo" role="dialog" aria-modal="true" aria-label="Come funziona il pubblico" onClick={() => setSpiega(false)}>
      <div className="popup-spiegazione popup-morale" onClick={(e) => e.stopPropagation()}>
        <h2>Il pubblico</h2>
        <div className="popup-spiegazione__corpo">
          <p>Ogni squadra ha un <b>umore del pubblico da 0 a 100</b>, uguale per tutti all'inizio (100). Lo vedono tutti.</p>
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
