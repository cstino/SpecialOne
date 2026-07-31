import { useState, type FormEvent } from 'react'
import { supabase } from '../lib/supabase'

export function AuthScreen() {
  const [mode, setMode] = useState<'login' | 'signup'>('login')
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [pending, setPending] = useState(false)
  const [message, setMessage] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)

  async function submit(event: FormEvent) {
    event.preventDefault()
    setPending(true)
    setError(null)
    setMessage(null)

    const result =
      mode === 'login'
        ? await supabase.auth.signInWithPassword({ email, password })
        : await supabase.auth.signUp({
            email,
            password,
            options: { emailRedirectTo: window.location.origin },
          })

    setPending(false)
    if (result.error) {
      setError(result.error.message)
      return
    }
    if (mode === 'signup' && !result.data.session) {
      setMessage('Account creato. Apri l’email di conferma, poi torna qui per accedere.')
    }
  }

  return (
    <main className="auth-layout">
      <section className="auth-pitch" aria-label="Presentazione SpecialOne">
        <div className="brand-lockup">
          <img src="/specialone-mark.svg" alt="" />
          <span>SpecialOne</span>
        </div>
        <div className="pitch-copy">
          <p className="kicker">La tua lega. Una giornata ogni notte.</p>
          <h1>Costruisci la rosa.<br />Decidi la partita.</h1>
          <p>Un manageriale calcistico a turni per il tuo gruppo di amici. Niente stagioni infinite: ogni giorno conta.</p>
        </div>
        <div className="pitch-line" aria-hidden="true"><span /></div>
      </section>

      <section className="auth-panel">
        <div className="auth-form-wrap">
          <div className="segmented" aria-label="Scegli accesso o registrazione">
            <button type="button" aria-pressed={mode === 'login'} onClick={() => setMode('login')}>Accedi</button>
            <button type="button" aria-pressed={mode === 'signup'} onClick={() => setMode('signup')}>Crea account</button>
          </div>
          <div className="form-heading">
            <h2>{mode === 'login' ? 'Bentornato mister.' : 'Entra nello spogliatoio.'}</h2>
            <p>{mode === 'login' ? 'Riprendi la gestione della tua squadra.' : 'Serve solo un’email. Il nome della squadra viene dopo.'}</p>
          </div>
          <form className="form-stack" onSubmit={submit}>
            <label>
              Email
              <input type="email" autoComplete="email" required value={email} onChange={(event) => setEmail(event.target.value)} />
            </label>
            <label>
              Password
              <input
                type="password"
                autoComplete={mode === 'login' ? 'current-password' : 'new-password'}
                minLength={6}
                required
                value={password}
                onChange={(event) => setPassword(event.target.value)}
              />
            </label>
            {error && <p className="notice notice--error" role="alert">{error}</p>}
            {message && <p className="notice notice--success" role="status">{message}</p>}
            <button className="button button--primary" type="submit" disabled={pending}>
              {pending ? 'Attendi…' : mode === 'login' ? 'Entra in panchina' : 'Crea il mio account'}
            </button>
          </form>
        </div>
      </section>
    </main>
  )
}
