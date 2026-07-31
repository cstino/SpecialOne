import { useMemo, useState, type FormEvent } from 'react'
import type { User } from '@supabase/supabase-js'
import { preparaStemma } from '../lib/crest'
import {
  CAMPIONATI,
  calcolaGiornateTotali,
  calcolaPartitePerSquadra,
  dataFineStagione,
  normalizzaCodice,
} from '../lib/league'
import { supabase } from '../lib/supabase'
import type { CrestChoice, RpcResult } from '../types'
import { CrestPicker } from './CrestPicker'

type OnboardingProps = {
  user: User
  onComplete: (result: RpcResult) => void
  onCancel?: () => void
}

type TeamFields = {
  teamName: string
  crest: CrestChoice
}

const DEFAULT_CREST: CrestChoice = { type: 'preset', value: 'preset:scudo' }

function TeamIdentity({ fields, onChange, disabled }: {
  fields: TeamFields
  onChange: (fields: TeamFields) => void
  disabled: boolean
}) {
  return (
    <div className="team-identity">
      <label>
        Nome squadra
        <input
          type="text"
          minLength={2}
          maxLength={40}
          required
          placeholder="es. Atletico Bar Sport"
          value={fields.teamName}
          onChange={(event) => onChange({ ...fields, teamName: event.target.value })}
          disabled={disabled}
        />
      </label>
      <CrestPicker value={fields.crest} onChange={(crest) => onChange({ ...fields, crest })} disabled={disabled} />
    </div>
  )
}

async function salvaStemma(user: User, crest: CrestChoice) {
  if (crest.type === 'preset') return { path: crest.value, uploaded: false }
  const blob = await preparaStemma(crest.file)
  const path = `${user.id}/${crypto.randomUUID()}.webp`
  const { error } = await supabase.storage.from('team-crests').upload(path, blob, {
    contentType: 'image/webp',
    cacheControl: '31536000',
    upsert: false,
  })
  if (error) throw error
  return { path, uploaded: true }
}

async function eliminaStemmaSeOrfano(path: string) {
  const { data, error } = await supabase
    .from('teams')
    .select('id')
    .eq('stemma_url', path)
    .maybeSingle()
  if (!error && !data) await supabase.storage.from('team-crests').remove([path])
}

export function Onboarding({ user, onComplete, onCancel }: OnboardingProps) {
  const [mode, setMode] = useState<'choose' | 'create' | 'join'>('choose')

  return (
    <main className="app-shell onboarding-shell">
      <header className="topbar">
        <div className="brand-lockup brand-lockup--dark">
          <img src="/specialone-mark.svg" alt="" />
          <span>SpecialOne</span>
        </div>
        <button className="text-button" type="button" onClick={() => supabase.auth.signOut()}>Esci</button>
      </header>

      {mode === 'choose' && (
        <section className="choice-stage">
          <div className="choice-intro">
            <p className="kicker">Fischio d’inizio</p>
            <h1>Come entri in campo?</h1>
            <p>Crea le regole del campionato oppure usa il codice ricevuto dall’admin.</p>
          </div>
          <div className="choice-actions">
            <button className="choice-action choice-action--create" type="button" onClick={() => setMode('create')}>
              <span className="choice-index">ADMIN</span>
              <strong>Crea una lega</strong>
              <span>Scegli squadre, durata, budget e campionati.</span>
              <i aria-hidden="true">→</i>
            </button>
            <button className="choice-action" type="button" onClick={() => setMode('join')}>
              <span className="choice-index">INVITO</span>
              <strong>Entra con un codice</strong>
              <span>Registra nome e stemma della tua squadra.</span>
              <i aria-hidden="true">→</i>
            </button>
          </div>
          {onCancel && <button className="text-button choice-cancel" type="button" onClick={onCancel}>Torna alle mie leghe</button>}
        </section>
      )}

      {mode === 'create' && <CreateLeague user={user} onBack={() => setMode('choose')} onComplete={onComplete} />}
      {mode === 'join' && <JoinLeague user={user} onBack={() => setMode('choose')} onComplete={onComplete} />}
    </main>
  )
}

function CreateLeague({ user, onBack, onComplete }: Omit<OnboardingProps, 'onCancel'> & { onBack: () => void }) {
  const [leagueName, setLeagueName] = useState('')
  const [teams, setTeams] = useState(8)
  const [rounds, setRounds] = useState(4)
  const [budget, setBudget] = useState(100)
  const [rerolls, setRerolls] = useState(12)
  const [rosterSlots, setRosterSlots] = useState(25)
  const [minKeepers, setMinKeepers] = useState(3)
  const [competitions, setCompetitions] = useState<string[]>([...CAMPIONATI])
  const [identity, setIdentity] = useState<TeamFields>({ teamName: '', crest: DEFAULT_CREST })
  const [pending, setPending] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const matchdays = useMemo(() => calcolaGiornateTotali(teams, rounds), [teams, rounds])
  const matches = useMemo(() => calcolaPartitePerSquadra(teams, rounds), [teams, rounds])

  function toggleCompetition(competition: string) {
    setCompetitions((current) =>
      current.includes(competition) ? current.filter((item) => item !== competition) : [...current, competition],
    )
  }

  async function submit(event: FormEvent) {
    event.preventDefault()
    if (competitions.length === 0) {
      setError('Seleziona almeno un campionato per il draft.')
      return
    }
    setPending(true)
    setError(null)
    let uploadedPath: string | null = null

    try {
      const crest = await salvaStemma(user, identity.crest)
      if (crest.uploaded) uploadedPath = crest.path
      const { data, error: rpcError } = await supabase.rpc('crea_lega', {
        p_nome_lega: leagueName,
        p_nome_squadra: identity.teamName,
        p_stemma_url: crest.path,
        p_n_squadre: teams,
        p_n_gironi: rounds,
        p_budget_iniziale: budget * 1_000_000,
        p_reroll_draft: rerolls,
        p_slot_rosa: rosterSlots,
        p_portieri_minimi: minKeepers,
        p_campionati_attivi: competitions,
      })
      if (rpcError) throw rpcError
      onComplete(data as RpcResult)
    } catch (caught) {
      if (uploadedPath) await eliminaStemmaSeOrfano(uploadedPath)
      setError(caught instanceof Error ? caught.message : 'Non è stato possibile creare la lega.')
      setPending(false)
    }
  }

  return (
    <form className="setup-layout" onSubmit={submit}>
      <section className="setup-main">
        <button className="back-button" type="button" onClick={onBack}>← Indietro</button>
        <div className="form-heading form-heading--large">
          <p className="kicker">Nuova lega</p>
          <h1>Disegna la stagione.</h1>
          <p>Le impostazioni seguono il design §3.1. Controllale nell’anteprima prima di confermare.</p>
        </div>

        <div className="form-section">
          <h2>Identità</h2>
          <label>
            Nome lega
            <input type="text" minLength={3} maxLength={60} required placeholder="es. Champions del Giovedì" value={leagueName} onChange={(event) => setLeagueName(event.target.value)} disabled={pending} />
          </label>
          <TeamIdentity fields={identity} onChange={setIdentity} disabled={pending} />
        </div>

        <div className="form-section">
          <div className="section-heading-row"><h2>Formato</h2><span>{matches} partite per squadra</span></div>
          <RangeField label="Squadre" value={teams} min={4} max={20} onChange={setTeams} disabled={pending} />
          <RangeField label="Gironi" value={rounds} min={2} max={6} onChange={setRounds} disabled={pending} />
        </div>

        <div className="form-section">
          <h2>Risorse del draft</h2>
          <RangeField label="Budget iniziale" value={budget} min={50} max={200} step={10} suffix=" M€" onChange={setBudget} disabled={pending} />
          <RangeField label="Reroll" value={rerolls} min={0} max={30} onChange={setRerolls} disabled={pending} />
          <RangeField label="Slot rosa" value={rosterSlots} min={20} max={30} onChange={setRosterSlots} disabled={pending} />
          <RangeField label="Portieri minimi" value={minKeepers} min={2} max={4} onChange={setMinKeepers} disabled={pending} />
        </div>

        <fieldset className="form-section competitions" disabled={pending}>
          <legend>Campionati attivi</legend>
          <div className="competition-grid">
            {CAMPIONATI.map((competition) => (
              <label key={competition}>
                <input type="checkbox" checked={competitions.includes(competition)} onChange={() => toggleCompetition(competition)} />
                <span>{competition}</span>
              </label>
            ))}
          </div>
          <div className="inline-actions">
            <button type="button" className="text-button" onClick={() => setCompetitions([...CAMPIONATI])}>Seleziona tutti</button>
            <button type="button" className="text-button" onClick={() => setCompetitions([])}>Deseleziona</button>
          </div>
        </fieldset>
        {error && <p className="notice notice--error" role="alert">{error}</p>}
      </section>

      <aside className="season-ticket">
        <span className="season-ticket__label">Anteprima stagione</span>
        <strong>{matchdays}</strong>
        <span>giornate reali</span>
        <dl>
          <div><dt>Squadre</dt><dd>{teams}</dd></div>
          <div><dt>Partite / squadra</dt><dd>{matches}</dd></div>
          <div><dt>Fine prevista</dt><dd>{dataFineStagione(matchdays)}</dd></div>
        </dl>
        <p>Una giornata viene simulata ogni notte alle 00:00, ora di Roma.</p>
        <button className="button button--light" type="submit" disabled={pending}>
          {pending ? 'Creazione in corso…' : 'Crea lega e squadra'}
        </button>
      </aside>
    </form>
  )
}

function JoinLeague({ user, onBack, onComplete }: Omit<OnboardingProps, 'onCancel'> & { onBack: () => void }) {
  const [code, setCode] = useState('')
  const [identity, setIdentity] = useState<TeamFields>({ teamName: '', crest: DEFAULT_CREST })
  const [pending, setPending] = useState(false)
  const [error, setError] = useState<string | null>(null)

  async function submit(event: FormEvent) {
    event.preventDefault()
    if (code.length !== 6) {
      setError('Inserisci tutte le 6 lettere del codice invito.')
      return
    }
    setPending(true)
    setError(null)
    let uploadedPath: string | null = null
    try {
      const crest = await salvaStemma(user, identity.crest)
      if (crest.uploaded) uploadedPath = crest.path
      const { data, error: rpcError } = await supabase.rpc('entra_in_lega', {
        p_codice: code,
        p_nome_squadra: identity.teamName,
        p_stemma_url: crest.path,
      })
      if (rpcError) throw rpcError
      onComplete(data as RpcResult)
    } catch (caught) {
      if (uploadedPath) await eliminaStemmaSeOrfano(uploadedPath)
      setError(caught instanceof Error ? caught.message : 'Non è stato possibile entrare nella lega.')
      setPending(false)
    }
  }

  return (
    <section className="join-stage">
      <button className="back-button" type="button" onClick={onBack}>← Indietro</button>
      <div className="join-grid">
        <div className="join-code-panel">
          <p className="kicker">Codice invito</p>
          <h1>Sei convocato.</h1>
          <p>Chiedi all’admin il codice a sei caratteri. Non contiene O, 0, I o 1.</p>
          <label className="code-field">
            <span className="sr-only">Codice invito</span>
            <input
              autoCapitalize="characters"
              autoComplete="off"
              inputMode="text"
              maxLength={6}
              placeholder="ABC234"
              value={code}
              onChange={(event) => setCode(normalizzaCodice(event.target.value))}
              disabled={pending}
              required
            />
          </label>
        </div>
        <form className="join-team-panel" onSubmit={submit}>
          <div className="form-heading">
            <h2>Registra la squadra</h2>
            <p>Nome e stemma saranno visibili a tutti i partecipanti della lega.</p>
          </div>
          <TeamIdentity fields={identity} onChange={setIdentity} disabled={pending} />
          {error && <p className="notice notice--error" role="alert">{error}</p>}
          <button className="button button--primary" type="submit" disabled={pending}>
            {pending ? 'Ingresso in corso…' : 'Entra nella lega'}
          </button>
        </form>
      </div>
    </section>
  )
}

function RangeField({ label, value, min, max, step = 1, suffix = '', onChange, disabled }: {
  label: string
  value: number
  min: number
  max: number
  step?: number
  suffix?: string
  onChange: (value: number) => void
  disabled: boolean
}) {
  const progress = ((value - min) / (max - min)) * 100
  return (
    <label className="range-field">
      <span>{label}</span>
      <output>{value}{suffix}</output>
      <input
        type="range"
        min={min}
        max={max}
        step={step}
        value={value}
        disabled={disabled}
        style={{ '--range-progress': `${progress}%` } as React.CSSProperties}
        onChange={(event) => onChange(Number(event.target.value))}
      />
    </label>
  )
}
