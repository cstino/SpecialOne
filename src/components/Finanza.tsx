import { useEffect, useMemo, useState } from 'react'
import { Bar, BarChart, Cell, ResponsiveContainer, Tooltip, XAxis, YAxis } from 'recharts'
import { motion } from 'motion/react'
import { supabase } from '../lib/supabase'
import type { League, Membership, Season, Transaction } from '../types'
import { GameNav, type GameView } from './GameNav'
import { PopupSpiegazione } from './PopupSpiegazione'
import { SeasonState } from './SeasonUI'

type Props = { membership: Membership; onNavigate: (view: GameView) => void }
type Contratto = { ingaggio: number; contratto_scadenza: number; ritiro_annunciato: boolean }
type Capienza = { stagione: number; tetto: number; monte: number; capienza: number; rosa: number; slot_liberi: number }

// Sotto il tetto salariale (docs/decisioni-economia.md) solo questi tipi
// rappresentano un vero movimento di spazio salariale. Il resto che compare
// ancora in transactions (sponsor, premi partita, stipendi a rate...) è
// rumore del vecchio modello a cassa, tenuto in vita dietro le quinte ma
// non più la grandezza rilevante per questa pagina.
const TIPI_CAPIENZA = new Set(['draft_pick', 'scelta_draft', 'asta_svincolato', 'mercato_scambio', 'rinnovo_in_stagione'])

const ETICHETTA_TIPO: Record<string, string> = {
  draft_pick: 'Ingaggi draft',
  scelta_draft: 'Mercato a scelte',
  asta_svincolato: 'Aste svincolati',
  mercato_scambio: 'Scambi di mercato',
  rinnovo_in_stagione: 'Rinnovo (stagione entrante)',
}

function money(value: number) {
  return `${(value / 1_000_000).toFixed(1).replace('.', ',')} M€`
}

function dataOraBreve(iso: string) {
  return new Intl.DateTimeFormat('it-IT', { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' }).format(new Date(iso))
}

type TooltipVoce = { value?: number | string; payload?: Record<string, unknown> }

function TooltipCategoria({ active, payload }: { active?: boolean; payload?: TooltipVoce[] }) {
  if (!active || !payload?.length) return null
  const dato = payload[0].payload as { etichetta: string; valore: number }
  return <div className="finanza-tooltip"><strong>{money(dato.valore)}</strong><span>{dato.etichetta}</span></div>
}

export function Finanza({ membership, onNavigate }: Props) {
  const league = membership.league as League
  const [transazioni, setTransazioni] = useState<Transaction[]>([])
  const [contratti, setContratti] = useState<Contratto[]>([])
  const [capienza, setCapienza] = useState<Capienza | null>(null)
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
    // Stessa convenzione di prima: per la stagione 1 non filtriamo (dotazione
    // e ingaggi draft precedono la riga "seasons"), dalla 2 in poi creata_il
    // e' un confine affidabile perche' il cambio stagione e' atomico.
    const inizio = league.stagione_corrente > 1 ? (stagione as Season | null)?.creata_il ?? null : null

    let query = supabase
      .from('transactions')
      .select('*')
      .eq('team_id', membership.id)
      .order('creata_il', { ascending: true })
    if (inizio) query = query.gte('creata_il', inizio)

    const [transazioniResult, contrattiResult, capienzaResult] = await Promise.all([
      query,
      supabase.from('player_instances').select('ingaggio, contratto_scadenza, ritiro_annunciato').eq('team_id', membership.id),
      supabase.rpc('capienza_squadra', { p_league_id: league.id }),
    ])
    const primoErrore = transazioniResult.error ?? contrattiResult.error ?? capienzaResult.error
    if (primoErrore) { setError(primoErrore.message); setLoading(false); return }
    setTransazioni((transazioniResult.data ?? []) as Transaction[])
    setContratti((contrattiResult.data ?? []) as Contratto[])
    setCapienza(capienzaResult.data as Capienza)
    setLoading(false)
  }

  useEffect(() => { void carica() }, [league.id, league.stagione_corrente, membership.id])

  const movimentiCapienza = useMemo(() => transazioni.filter((t) => TIPI_CAPIENZA.has(t.tipo)), [transazioni])

  const perCategoria = new Map<string, number>()
  for (const t of movimentiCapienza) perCategoria.set(t.tipo, (perCategoria.get(t.tipo) ?? 0) + t.importo)
  const categorie = [...perCategoria.entries()]
    .map(([tipo, valore]) => ({ tipo, etichetta: ETICHETTA_TIPO[tipo] ?? tipo, valore }))
    .sort((a, b) => Math.abs(b.valore) - Math.abs(a.valore))

  const movimentiRecenti = [...movimentiCapienza].reverse()

  const confermati = contratti.filter((g) => g.contratto_scadenza > league.stagione_corrente && !g.ritiro_annunciato)
  const inScadenza = contratti.filter((g) => g.contratto_scadenza <= league.stagione_corrente && !g.ritiro_annunciato)
  const ingaggioConfermati = confermati.reduce((somma, g) => somma + g.ingaggio, 0)
  const ingaggioInScadenza = inScadenza.reduce((somma, g) => somma + g.ingaggio, 0)

  const capienzaPct = capienza ? Math.min(100, Math.max(0, (capienza.monte / Math.max(capienza.tetto, 1)) * 100)) : 0
  const capienzaCritica = capienza ? capienza.capienza < 0 : false

  return <main className="app-shell season-shell">
    <GameNav league={league} active="finanza" onNavigate={naviga} />
    <header className="topbar season-topbar"><div className="brand-lockup brand-lockup--dark"><img src="/specialone-mark.svg" alt="" /><span>SpecialOne</span></div><span>Finanza</span></header>
    <div className="season-page season-page--narrow finanza-page">
      <PopupSpiegazione userId={membership.user_id} hintKey="finanza" titolo="Come funziona la Finanza">
        <p>Il tetto ingaggi è uguale per tutte le squadre della lega e <strong>non cambia mai</strong> fra le
          stagioni. Non è cassa da spendere: è spazio salariale, uno stipendio lo occupa finché il contratto è
          attivo, non è mai una spesa "una tantum".</p>
        <p>Ogni contratto dura <strong>una sola stagione</strong>: chi non viene rinnovato entro la fine
          dell'off-season lascia la squadra ed entra tra gli svincolati.</p>
      </PopupSpiegazione>
      <section className="season-title-row">
        <div>
          <p className="kicker">{league.nome}</p>
          <h1>Finanza.</h1>
        </div>
        {capienza && <div className={`scambi-gauge ${capienzaCritica ? 'is-critica' : ''}`}>
          <div className="scambi-gauge__numeri">
            <strong>{money(Math.max(0, capienza.capienza))}</strong>
            <span>{capienzaCritica ? 'oltre il tetto' : 'capienza libera'}</span>
          </div>
          <div className="scambi-gauge__barra" role="img" aria-label={`Monte ingaggi ${money(capienza.monte)} su tetto ${money(capienza.tetto)}`}>
            <motion.div className="scambi-gauge__riempimento" initial={{ width: 0 }} animate={{ width: `${capienzaPct}%` }} transition={{ duration: 0.7, ease: 'easeOut' }} />
          </div>
          <small>{money(capienza.monte)} di {money(capienza.tetto)} · stagione {capienza.stagione} · {capienza.slot_liberi} slot liberi</small>
        </div>}
      </section>

      <SeasonState loading={loading} error={error} onRetry={carica} />

      {!loading && !error && <>
        <div className="finanza-kpi">
          <div className="finanza-kpi__cella"><span>Tetto ingaggi</span><strong>{capienza ? money(capienza.tetto) : '—'}</strong></div>
          <div className="finanza-kpi__cella"><span>Monte ingaggi</span><strong>{capienza ? money(capienza.monte) : '—'}</strong></div>
          <div className={`finanza-kpi__cella ${capienzaCritica ? 'finanza-kpi__cella--uscita' : 'finanza-kpi__cella--entrata'}`}><span>Capienza residua</span><strong>{capienza ? money(capienza.capienza) : '—'}</strong></div>
          <div className="finanza-kpi__cella"><span>Rosa</span><strong>{capienza?.rosa ?? '—'}</strong></div>
          <div className="finanza-kpi__cella"><span>Slot liberi</span><strong>{capienza?.slot_liberi ?? '—'}</strong></div>
          <div className="finanza-kpi__cella finanza-kpi__cella--entrata"><span>Confermati stagione entrante</span><strong>{confermati.length}</strong></div>
          <div className="finanza-kpi__cella finanza-kpi__cella--uscita"><span>In scadenza questa stagione</span><strong>{inScadenza.length}</strong></div>
        </div>

        <section className="finanza-grafico">
          <div className="finanza-grafico__heading"><p className="kicker">Contratti</p><h2>Ingaggi confermati e in scadenza</h2></div>
          <dl className="finanza-contratti">
            <div><dt>Confermati per la stagione entrante</dt><dd>{confermati.length} giocatori · {money(ingaggioConfermati)}</dd></div>
            <div><dt>In scadenza a fine stagione corrente</dt><dd>{inScadenza.length} giocatori · {money(ingaggioInScadenza)}</dd></div>
          </dl>
        </section>

        {categorie.length === 0
          ? <p className="season-empty">Nessun movimento di spazio salariale ancora in questa stagione.</p>
          : <>
            <section className="finanza-grafico">
              <div className="finanza-grafico__heading"><p className="kicker">Riepilogo</p><h2>Movimenti di spazio salariale per categoria</h2></div>
              <ResponsiveContainer width="100%" height={Math.max(100, categorie.length * 34)}>
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

            <section className="finanza-movimenti">
              <div className="finanza-grafico__heading"><p className="kicker">Registro</p><h2>Movimenti recenti</h2></div>
              <ul>{movimentiRecenti.map((t) => <li key={t.id} className={t.importo >= 0 ? 'is-entrata' : 'is-uscita'}>
                  <span className="finanza-movimenti__testo"><strong>{t.descrizione}</strong><small>{dataOraBreve(t.creata_il)} · {ETICHETTA_TIPO[t.tipo] ?? t.tipo}</small></span>
                  <b>{t.importo >= 0 ? '+' : ''}{money(t.importo)}</b>
                </li>)}</ul>
            </section>
          </>}
      </>}
    </div>
  </main>
}
