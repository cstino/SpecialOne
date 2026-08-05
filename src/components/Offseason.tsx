import { useEffect, useMemo, useState } from 'react'
import type { User } from '@supabase/supabase-js'
import { supabase } from '../lib/supabase'
import type { League, Membership, Team } from '../types'
import { GameNav, type GameView } from './GameNav'
import { Crest } from './Crest'

type StatoTeam = { id: number; nome: string; attiva: boolean; entrante: boolean; rosa: number; draft: string | null; budget: number }
type StatoOffseason = { fase: string; stagione_corrente: number; stagione_prossima: number; scade_il: string | null; posti_nuovi: number; squadre_attese: number; squadre: StatoTeam[] }
type Props = { user: User; membership: Membership; onNavigate: (view: GameView) => void; onRefresh: () => Promise<void> }

export function Offseason({ user, membership, onNavigate, onRefresh }: Props) {
  const league = membership.league as League
  const admin = league.admin_id === user.id
  const [teams, setTeams] = useState<Team[]>([])
  const [crestUrls, setCrestUrls] = useState<Record<number, string>>({})
  const [status, setStatus] = useState<StatoOffseason | null>(null)
  const [removed, setRemoved] = useState<number[]>([])
  const [newSlots, setNewSlots] = useState(0)
  const [pending, setPending] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [notice, setNotice] = useState<string | null>(null)
  const [adesso, setAdesso] = useState(Date.now())

  async function load() {
    setError(null)
    const teamResult = await supabase.from('teams').select('*').eq('league_id', league.id).order('nome')
    if (teamResult.error) { setError(teamResult.error.message); return }
    const loadedTeams = (teamResult.data ?? []) as Team[]
    setTeams(loadedTeams)
    const signed = await Promise.all(loadedTeams.filter(team => team.stemma_url && !team.stemma_url.startsWith('preset:')).map(async team => {
      const { data } = await supabase.storage.from('team-crests').createSignedUrl(team.stemma_url!, 3600)
      return [team.id, data?.signedUrl] as const
    }))
    setCrestUrls(Object.fromEntries(signed.filter((entry): entry is readonly [number, string] => Boolean(entry[1]))))
    if (league.fase_carriera !== 'offseason') return
    const stateResult = await supabase.rpc('stato_offseason', { p_league_id: league.id })
    if (stateResult.error) { setError(stateResult.error.message); return }
    setStatus(stateResult.data as StatoOffseason)
  }

  useEffect(() => { void load() }, [league.id, league.fase_carriera, membership.id])

  useEffect(() => {
    if (league.fase_carriera !== 'offseason') return
    const timer = window.setInterval(() => setAdesso(Date.now()), 1000)
    return () => window.clearInterval(timer)
  }, [league.fase_carriera])

  // Dopo lo zero il cron puo' impiegare al massimo un minuto a finalizzare.
  // Un polling leggero aggiorna la schermata senza costringere l'utente a
  // ricaricare l'app proprio nel passaggio alla nuova stagione.
  useEffect(() => {
    const scadenza = status?.scade_il ? new Date(status.scade_il).getTime() : null
    if (!scadenza) return
    const timer = window.setInterval(() => {
      if (Date.now() >= scadenza) { void onRefresh(); void load() }
    }, 15_000)
    return () => window.clearInterval(timer)
  }, [status?.scade_il, onRefresh])

  async function run(action: () => PromiseLike<{ error: { message: string } | null }>, success: string) {
    setPending(true); setError(null); setNotice(null)
    const result = await action()
    if (result.error) setError(result.error.message)
    else { setNotice(success); await onRefresh(); await load() }
    setPending(false)
  }

  function openOffseason() {
    void run(
      () => supabase.rpc('prepara_offseason', { p_league_id: league.id, p_squadre_rimosse: removed, p_posti_nuovi: newSlots }),
      'Off-season aperta. Premi e progressione sono stati calcolati.',
    )
  }

  const entrant = membership.entrata_stagione === league.stagione_corrente + 1
  const activeCount = useMemo(() => teams.filter((team) => team.attiva && !removed.includes(team.id)).length + newSlots, [teams, removed, newSlots])
  const millisecondiRimasti = status?.scade_il ? Math.max(0, new Date(status.scade_il).getTime() - adesso) : 0
  const scaduta = Boolean(status?.scade_il) && millisecondiRimasti === 0
  const countdown = formatCountdown(millisecondiRimasti)

  return <main className="app-shell offseason-shell">
    <GameNav league={league} active="offseason" onNavigate={onNavigate} />
    <section className="season-page offseason-page">
      <header className="offseason-hero">
        <div>
          <p className="kicker">{league.nome} · Carriera</p>
          <h1>{league.fase_carriera === 'offseason' ? 'Costruisci il futuro.' : 'Fine stagione. Nuove scelte.'}</h1>
          <p>Rinnovi, mercato e nuovi ingressi. La prossima stagione comincia qui.</p>
        </div>
        <div className="offseason-transition" aria-label={`Passaggio dalla stagione ${league.stagione_corrente} alla ${league.stagione_corrente + 1}`}>
          <span><small>STAGIONE</small>{league.stagione_corrente}</span><i aria-hidden="true">→</i><strong><small>PROSSIMA</small>{league.stagione_corrente + 1}</strong>
        </div>
      </header>
      {error && <p className="notice notice--error" role="alert">{error}</p>}
      {notice && <p className="notice notice--success">{notice}</p>}

      {league.fase_carriera !== 'offseason' && <section className="offseason-launch">
        <div className="offseason-launch__intro">
          <span className="offseason-launch__number">01</span>
          <p className="kicker">Decisione dell’admin</p><h2>Chi resta in gioco?</h2>
          <p>Conferma i club che continueranno. I giocatori delle squadre escluse entreranno nel mercato svincolati.</p>
          <ul><li>Rinnovi e progressione</li><li>Un giorno di mercato</li><li>Nuovo calendario</li></ul>
        </div>
        <div className="offseason-launch__control">
        {!admin && <p>L’admin deve confermare partecipanti e posti disponibili.</p>}
        {admin && <>
          <div className="offseason-control__heading"><div><p className="kicker">Partecipanti</p><h3>Club confermati</h3></div><span>{teams.filter(team => team.attiva).length - removed.length}</span></div>
          <div className="offseason-team-grid">{teams.filter(t => t.attiva).map(team => {
            const selected = !removed.includes(team.id)
            const locked = team.user_id === league.admin_id
            return <label className={`${selected ? 'is-selected' : 'is-removed'} ${locked ? 'is-locked' : ''}`} key={team.id}>
              <input className="sr-only" type="checkbox" checked={selected} disabled={locked} onChange={() => setRemoved(value => value.includes(team.id) ? value.filter(id => id !== team.id) : [...value, team.id])} />
              <Crest value={team.stemma_url} imageUrl={crestUrls[team.id]} />
              <span><strong>{team.nome}</strong><small>{locked ? 'La tua squadra · Admin' : selected ? 'Confermata' : 'Esclusa dalla prossima stagione'}</small></span>
              <i aria-hidden="true">{locked ? '◆' : selected ? '✓' : '×'}</i>
            </label>})}
          </div>
          <div className="offseason-slots"><div><p className="kicker">Espansione</p><strong>Nuovi posti</strong><small>Il codice invito resterà attivo per nuovi allenatori.</small></div><div className="offseason-stepper"><button type="button" aria-label="Riduci nuovi posti" disabled={newSlots === 0} onClick={() => setNewSlots(value => Math.max(0, value - 1))}>−</button><output>{newSlots}</output><button type="button" aria-label="Aumenta nuovi posti" disabled={newSlots === 16} onClick={() => setNewSlots(value => Math.min(16, value + 1))}>+</button></div></div>
          <div className="offseason-launch__footer"><div><small>PROSSIMA STAGIONE</small><strong>{activeCount} squadre</strong></div><button className="offseason-open-button" disabled={pending || activeCount < 4 || activeCount > 20} onClick={openOffseason}><span>{pending ? 'Preparazione…' : 'Apri off-season'}</span><i aria-hidden="true">→</i></button></div>
        </>}
        </div>
      </section>}

      {league.fase_carriera === 'offseason' && <>
        <section className={`offseason-countdown ${scaduta ? 'is-expired' : ''}`}>
          <div><p className="kicker">Finestra di preparazione</p><h2>{scaduta ? 'Tempo scaduto.' : 'Il mercato non aspetta.'}</h2><p>{scaduta ? 'Il server sta completando le rose corte e preparando il calendario.' : 'Hai 24 ore dall’apertura per spin, mercato e sistemazione della rosa.'}</p></div>
          <time dateTime={status?.scade_il ?? undefined}><span>{scaduta ? 'CHIUSURA' : 'TEMPO RIMASTO'}</span><strong>{scaduta ? 'IN CORSO' : countdown}</strong></time>
        </section>
        <section className="offseason-summary">
          <div><small>SCADENZA</small><strong>{status?.scade_il ? new Intl.DateTimeFormat('it-IT', { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(status.scade_il)) : '—'}</strong></div>
          <div><small>SQUADRE</small><strong>{status?.squadre.filter(t => t.attiva).length ?? '—'} / {status?.squadre_attese ?? league.n_squadre}</strong></div>
          <div><small>INVITO</small><strong>{league.codice_invito}</strong></div>
        </section>
        {entrant && <section className="offseason-card offseason-card--accent"><p className="kicker">Nuova squadra</p><h2>Completa il draft</h2><p>Hai il budget iniziale completo e puoi scegliere senza attendere gli altri.</p><button className="button button--primary" onClick={() => onNavigate('draft')}>Vai al draft</button></section>}
        {!entrant && <section className="offseason-card"><p className="kicker">Contratti</p><h2>Chi è in scadenza</h2><p>I rinnovi si trattano durante la stagione, dalla scheda del giocatore. Chi arriva a fine off-season col contratto scaduto lascia la squadra ed entra nel pool degli svincolati.</p></section>}
        <section className="offseason-card"><p className="kicker">Stato lega</p><h2>Squadre pronte</h2><p>Alla scadenza le rose sotto quota 21 saranno completate automaticamente con gli svincolati più economici sostenibili.</p><div className="offseason-readiness">{status?.squadre.filter(t => t.attiva).map(team => <div key={team.id}><strong>{team.nome}</strong><span>{team.rosa} giocatori</span></div>)}</div>
          {admin && !scaduta && <button className="button button--secondary" disabled type="button">Avvio automatico tra {countdown}</button>}
          {admin && scaduta && <button className="button button--primary" disabled={pending} onClick={() => void run(() => supabase.rpc('avvia_prossima_stagione', { p_league_id: league.id }), 'Nuova stagione avviata.')}>{pending ? 'Preparazione…' : 'Riprova avvio adesso'}</button>}
        </section>
      </>}
    </section>
  </main>
}

function formatCountdown(milliseconds: number) {
  const totaleSecondi = Math.max(0, Math.ceil(milliseconds / 1000))
  const ore = Math.floor(totaleSecondi / 3600)
  const minuti = Math.floor((totaleSecondi % 3600) / 60)
  const secondi = totaleSecondi % 60
  return [ore, minuti, secondi].map((parte) => String(parte).padStart(2, '0')).join(':')
}


