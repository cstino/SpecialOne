import { useMemo, useState, type FormEvent } from 'react'
import type { User } from '@supabase/supabase-js'
import { formatoStemma, generaUuidV4, preparaStemma } from '../lib/crest'
import {
  CAMPIONATI,
  calcolaGiornateTotali,
  calcolaPartitePerSquadra,
  dataFineStagione,
  normalizzaCodice,
} from '../lib/league'
import { supabase } from '../lib/supabase'
import { STEMMA_SQUADRA_DEFAULT, STEMMI_SQUADRA } from '../lib/teamCrests'
import type { CrestChoice, RpcResult } from '../types'
import { CrestPicker } from './CrestPicker'

type OnboardingProps = {
  user: User
  onComplete: (result: RpcResult) => void
  onCancel?: () => void
  /** Dal menu iniziale si entra gia' dentro il ramo scelto. */
  modoIniziale?: 'choose' | 'create' | 'join'
}

type TeamFields = {
  teamName: string
  crest: CrestChoice
}

type InvitePreview = {
  league_id: number
  nome_lega: string
  posti_disponibili: number
  fase_carriera?: string
  stemmi_usati: string[]
}

const DEFAULT_CREST: CrestChoice = { type: 'preset', value: STEMMA_SQUADRA_DEFAULT }

function TeamIdentity({ fields, onChange, disabled, disabledCrests = [] }: {
  fields: TeamFields
  onChange: (fields: TeamFields) => void
  disabled: boolean
  disabledCrests?: string[]
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
      <CrestPicker value={fields.crest} onChange={(crest) => onChange({ ...fields, crest })} disabled={disabled} disabledValues={disabledCrests} />
    </div>
  )
}

async function salvaStemma(user: User, crest: CrestChoice) {
  if (crest.type === 'preset' || crest.type === 'existing') return { path: crest.value, uploaded: false }
  const blob = await preparaStemma(crest.file)
  const formato = formatoStemma(blob)
  const path = `${user.id}/${generaUuidV4()}.${formato.extension}`
  const { error } = await supabase.storage.from('team-crests').upload(path, blob, {
    contentType: formato.contentType,
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

export function Onboarding({ user, onComplete, onCancel, modoIniziale = 'choose' }: OnboardingProps) {
  const [mode, setMode] = useState<'choose' | 'create' | 'join'>(modoIniziale)
  const tornaIndietro = () => {
    if (modoIniziale !== 'choose' && onCancel && mode === modoIniziale) onCancel()
    else setMode('choose')
  }

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

      {mode === 'create' && <CreateLeague user={user} onBack={tornaIndietro} onComplete={onComplete} />}
      {mode === 'join' && <JoinLeague user={user} onBack={tornaIndietro} onComplete={onComplete} />}
    </main>
  )
}

function CreateLeague({ user, onBack, onComplete }: Omit<OnboardingProps, 'onCancel'> & { onBack: () => void }) {
  const [leagueName, setLeagueName] = useState('')
  const [teams, setTeams] = useState(8)
  const [rounds, setRounds] = useState(4)
  const [budget, setBudget] = useState(100)
  const [rerolls, setRerolls] = useState(12)
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
        p_slot_rosa: 24,
        p_portieri_minimi: 0,
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
          <p className="field-help">Rosa fissata a 24 giocatori: 12 pacchetti da 2 carte a testa, senza resto.</p>
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
        <p>Una giornata viene simulata ogni sera alle 23:00, ora di Roma.</p>
        <button className="button button--light" type="submit" disabled={pending}>
          {pending ? 'Creazione in corso…' : 'Crea lega e squadra'}
        </button>
      </aside>
    </form>
  )
}

function JoinLeague({ user, onBack, onComplete }: Omit<OnboardingProps, 'onCancel'> & { onBack: () => void }) {
  const [code, setCode] = useState('')
  const [step, setStep] = useState<'code' | 'team'>('code')
  const [preview, setPreview] = useState<InvitePreview | null>(null)
  const [identity, setIdentity] = useState<TeamFields>({ teamName: '', crest: DEFAULT_CREST })
  const [pending, setPending] = useState(false)
  const [error, setError] = useState<string | null>(null)

  async function verifyCode(event: FormEvent) {
    event.preventDefault()
    if (code.length !== 6) {
      setError('Inserisci tutte le 6 lettere del codice invito.')
      return
    }
    setPending(true)
    setError(null)
    const { data, error: rpcError } = await supabase.rpc('anteprima_invito', { p_codice: code })
    if (rpcError) {
      setError(rpcError.message)
      setPending(false)
      return
    }
    const nextPreview = data as InvitePreview
    setPreview(nextPreview)
    if (identity.crest.type === 'preset' && nextPreview.stemmi_usati.includes(identity.crest.value)) {
      const libero = STEMMI_SQUADRA.map((stemma) => `preset:${stemma.id}`).find((value) => !nextPreview.stemmi_usati.includes(value))
      setIdentity((current) => ({ ...current, crest: { type: 'preset', value: libero ?? STEMMA_SQUADRA_DEFAULT } }))
    }
    setStep('team')
    setPending(false)
  }

  async function submit(event: FormEvent) {
    event.preventDefault()
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
      <button className="back-button" type="button" onClick={step === 'team' ? () => { setStep('code'); setPreview(null); setError(null) } : onBack}>← Indietro</button>
      <div className={`join-grid ${step === 'team' ? 'join-grid--team' : ''}`}>
        {step === 'code' && <form className="join-code-panel" onSubmit={verifyCode}>
          <p className="kicker">Codice invito</p>
          <h1>Sei convocato.</h1>
          <p>Chiedi all’admin il codice a sei caratteri. Non contiene O, 0, I o 1.</p>
          <label className="code-field">
            <span className="sr-only">Codice invito</span>
            <input
              type="text"
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
          {error && <p className="notice notice--error" role="alert">{error}</p>}
          <button className="button button--primary" type="submit" disabled={pending}>
            {pending ? 'Controllo codice…' : 'Continua'}
          </button>
        </form>}
        {step === 'team' && <form className="join-team-panel" onSubmit={submit}>
          <div className="form-heading">
            <h2>Registra la squadra</h2>
            <p>{preview ? `${preview.nome_lega} · ${preview.posti_disponibili} posti disponibili` : 'Nome e stemma saranno visibili a tutti i partecipanti della lega.'}</p>
          </div>
          <TeamIdentity fields={identity} onChange={setIdentity} disabled={pending} disabledCrests={preview?.stemmi_usati ?? []} />
          {error && <p className="notice notice--error" role="alert">{error}</p>}
          <button className="button button--primary" type="submit" disabled={pending}>
            {pending ? 'Ingresso in corso…' : 'Entra nella lega'}
          </button>
        </form>}
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
