import { useEffect, useState } from 'react'
import { Area, AreaChart, Bar, BarChart, Cell, ResponsiveContainer, Tooltip, XAxis, YAxis } from 'recharts'
import { supabase } from '../lib/supabase'
import type { League, Membership, Season, Transaction } from '../types'
import { GameNav, type GameView } from './GameNav'
import { SeasonState } from './SeasonUI'

type Props = { membership: Membership; onNavigate: (view: GameView) => void }

const ETICHETTA_TIPO: Record<string, string> = {
  dotazione_iniziale: 'Dotazione iniziale',
  sponsor: 'Sponsor',
  premi_partite: 'Premi partita',
  premio_classifica: 'Premio posizione',
  draft_pick: 'Ingaggi draft',
  ingaggi_stagione: 'Monte ingaggi stagionale',
  asta_svincolato: 'Aste svincolati',
  spin_offseason: 'Spin mercato off-season',
  mercato_scambio: 'Scambi di mercato',
  svincolo_buonuscita: 'Buonuscite',
  rinnovo_in_stagione: 'Rinnovi (impegno futuro)',
}

// Le righe "rinnovo_in_stagione" hanno importo sempre positivo ma non sono
// un vero movimento di cassa: rinnovare oggi non muove denaro oggi (design
// §10.4 bis), infatti saldo_dopo non cambia per queste righe. Vanno escluse
// dai totali entrate/uscite, altrimenti gonfierebbero le entrate.
function movimentoReale(transazione: Transaction) {
  return transazione.tipo !== 'rinnovo_in_stagione'
}

function money(value: number) {
  return `${(value / 1_000_000).toFixed(1).replace('.', ',')} M€`
}

function dataBreve(iso: string) {
  return new Intl.DateTimeFormat('it-IT', { day: 'numeric', month: 'short' }).format(new Date(iso))
}

function dataOraBreve(iso: string) {
  return new Intl.DateTimeFormat('it-IT', { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' }).format(new Date(iso))
}

type TooltipVoce = { value?: number | string; payload?: Record<string, unknown> }

function TooltipSaldo({ active, payload }: { active?: boolean; payload?: TooltipVoce[] }) {
  if (!active || !payload?.length) return null
  const dato = payload[0].payload as { creata_il: string; saldo: number }
  return <div className="finanza-tooltip"><strong>{money(dato.saldo)}</strong><span>{dataOraBreve(dato.creata_il)}</span></div>
}

function TooltipCategoria({ active, payload }: { active?: boolean; payload?: TooltipVoce[] }) {
  if (!active || !payload?.length) return null
  const dato = payload[0].payload as { etichetta: string; valore: number }
  return <div className="finanza-tooltip"><strong>{money(dato.valore)}</strong><span>{dato.etichetta}</span></div>
}

export function Finanza({ membership, onNavigate }: Props) {
  const league = membership.league as League
  const [transazioni, setTransazioni] = useState<Transaction[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  function naviga(view: GameView) { onNavigate(view) }

  async function carica() {
    setLoading(true)
    setError(null)
    const { data: stagione, error: erroreStagione } = await supabase
      .from('seasons')
      .select('*')
      .eq('league_id', league.id)
      .eq('numero', league.stagione_corrente)
      .maybeSingle()
    if (erroreStagione) { setError(erroreStagione.message); setLoading(false); return }
    // La riga "seasons" per la stagione 1 nasce quando il draft finisce (lo
    // stato passa a 'stagione'), non quando la stagione economica comincia:
    // dotazione iniziale e ingaggi draft sono sempre precedenti a quel
    // timestamp. Per la stagione 1 quindi non filtriamo affatto (coincide
    // con "da sempre"); dalla stagione 2 in poi il passaggio di stagione e'
    // un'unica operazione atomica, quindi creata_il e' un confine affidabile.
    const inizio = league.stagione_corrente > 1 ? (stagione as Season | null)?.creata_il ?? null : null

    let query = supabase
      .from('transactions')
      .select('*')
      .eq('team_id', membership.id)
      .order('creata_il', { ascending: true })
    if (inizio) query = query.gte('creata_il', inizio)
    const { data, error: erroreTransazioni } = await query
    if (erroreTransazioni) { setError(erroreTransazioni.message); setLoading(false); return }
    setTransazioni((data ?? []) as Transaction[])
    setLoading(false)
  }

  useEffect(() => { void carica() }, [league.id, league.stagione_corrente, membership.id])

  const reali = transazioni.filter(movimentoReale)
  const entrate = reali.filter((t) => t.importo > 0).reduce((somma, t) => somma + t.importo, 0)
  const uscite = reali.filter((t) => t.importo < 0).reduce((somma, t) => somma - t.importo, 0)
  const saldoNetto = entrate - uscite

  const puntiSaldo = transazioni.length
    ? [
        { creata_il: transazioni[0].creata_il, saldo: transazioni[0].saldo_dopo - transazioni[0].importo },
        ...transazioni.map((t) => ({ creata_il: t.creata_il, saldo: t.saldo_dopo })),
      ]
    : []

  const perCategoria = new Map<string, number>()
  for (const t of reali) perCategoria.set(t.tipo, (perCategoria.get(t.tipo) ?? 0) + t.importo)
  const categorie = [...perCategoria.entries()]
    .map(([tipo, valore]) => ({ tipo, etichetta: ETICHETTA_TIPO[tipo] ?? tipo, valore }))
    .sort((a, b) => Math.abs(b.valore) - Math.abs(a.valore))

  const movimentiRecenti = [...transazioni].reverse()

  return <main className="app-shell season-shell">
    <GameNav league={league} active="finanza" onNavigate={naviga} />
    <header className="topbar season-topbar"><div className="brand-lockup brand-lockup--dark"><img src="/specialone-mark.svg" alt="" /><span>SpecialOne</span></div><span>Finanza</span></header>
    <div className="season-page season-page--narrow finanza-page">
      <section className="help-heading">
        <p className="kicker">{league.nome}</p>
        <h1>Finanza</h1>
        <p>Entrate e uscite della tua squadra in questa stagione.</p>
      </section>

      <SeasonState loading={loading} error={error} onRetry={carica} />

      {!loading && !error && <>
        <div className="finanza-kpi">
          <div className="finanza-kpi__cella"><span>Budget attuale</span><strong>{money(membership.budget)}</strong></div>
          <div className="finanza-kpi__cella finanza-kpi__cella--entrata"><span>Entrate stagione</span><strong>{money(entrate)}</strong></div>
          <div className="finanza-kpi__cella finanza-kpi__cella--uscita"><span>Uscite stagione</span><strong>{money(uscite)}</strong></div>
          <div className={`finanza-kpi__cella ${saldoNetto >= 0 ? 'finanza-kpi__cella--entrata' : 'finanza-kpi__cella--uscita'}`}><span>Saldo netto</span><strong>{saldoNetto >= 0 ? '+' : ''}{money(saldoNetto)}</strong></div>
        </div>

        {transazioni.length === 0
          ? <p className="season-empty">Nessun movimento ancora in questa stagione.</p>
          : <>
            <section className="finanza-grafico">
              <div className="finanza-grafico__heading"><p className="kicker">Andamento</p><h2>Budget nel tempo</h2></div>
              <ResponsiveContainer width="100%" height={200}>
                <AreaChart data={puntiSaldo} margin={{ top: 8, right: 8, left: 8, bottom: 0 }}>
                  <defs>
                    <linearGradient id="finanzaSaldoFill" x1="0" y1="0" x2="0" y2="1">
                      <stop offset="0%" stopColor="#bd67ff" stopOpacity={0.38} />
                      <stop offset="100%" stopColor="#bd67ff" stopOpacity={0} />
                    </linearGradient>
                  </defs>
                  <XAxis dataKey="creata_il" tickFormatter={dataBreve} stroke="#524a5f" tick={{ fill: '#8a8194', fontSize: 11 }} axisLine={{ stroke: '#322b41' }} tickLine={false} minTickGap={30} />
                  <YAxis stroke="#524a5f" tick={{ fill: '#8a8194', fontSize: 11 }} axisLine={false} tickLine={false} tickFormatter={(v: number) => money(v)} width={64} />
                  <Tooltip content={<TooltipSaldo />} cursor={{ stroke: '#65408a', strokeWidth: 1 }} />
                  <Area type="monotone" dataKey="saldo" stroke="#bd67ff" strokeWidth={2.5} fill="url(#finanzaSaldoFill)" />
                </AreaChart>
              </ResponsiveContainer>
            </section>

            <section className="finanza-grafico">
              <div className="finanza-grafico__heading"><p className="kicker">Riepilogo</p><h2>Entrate e uscite per categoria</h2></div>
              <ResponsiveContainer width="100%" height={Math.max(140, categorie.length * 34)}>
                <BarChart data={categorie} layout="vertical" margin={{ top: 4, right: 24, left: 4, bottom: 4 }}>
                  <XAxis type="number" hide />
                  <YAxis type="category" dataKey="etichetta" width={160} stroke="#524a5f" tick={{ fill: '#c6bfce', fontSize: 12 }} axisLine={false} tickLine={false} />
                  <Tooltip content={<TooltipCategoria />} cursor={{ fill: 'rgba(255,255,255,.04)' }} />
                  <Bar dataKey="valore" radius={5}>
                    {categorie.map((voce) => <Cell key={voce.tipo} fill={voce.valore >= 0 ? '#3dbf94' : '#bd67ff'} />)}
                  </Bar>
                </BarChart>
              </ResponsiveContainer>
            </section>
          </>}

        <section className="finanza-movimenti">
          <div className="finanza-grafico__heading"><p className="kicker">Registro</p><h2>Movimenti recenti</h2></div>
          {movimentiRecenti.length === 0
            ? <p className="season-empty">Nessun movimento da mostrare.</p>
            : <ul>{movimentiRecenti.map((t) => <li key={t.id} className={!movimentoReale(t) ? 'is-neutro' : t.importo >= 0 ? 'is-entrata' : 'is-uscita'}>
                <span className="finanza-movimenti__testo"><strong>{t.descrizione}</strong><small>{dataOraBreve(t.creata_il)} · {ETICHETTA_TIPO[t.tipo] ?? t.tipo}{!movimentoReale(t) ? ' · nessun movimento di cassa' : ''}</small></span>
                <b>{t.importo >= 0 ? '+' : ''}{money(t.importo)}</b>
              </li>)}</ul>}
        </section>
      </>}
    </div>
  </main>
}
