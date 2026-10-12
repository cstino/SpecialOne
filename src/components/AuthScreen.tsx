import { useState, type FormEvent, type ReactNode } from 'react'
import { supabase } from '../lib/supabase'

type Modo = 'login' | 'signup'

const ICONE: Record<'email' | 'password' | 'occhio' | 'occhioBarrato', ReactNode> = {
  email: (
    <>
      <rect x="3" y="5" width="18" height="14" rx="3" />
      <path d="m4 8 8 5.5L20 8" />
    </>
  ),
  password: (
    <>
      <rect x="4.5" y="10.5" width="15" height="10" rx="3" />
      <path d="M8 10.5V8a4 4 0 0 1 8 0v2.5" />
    </>
  ),
  occhio: (
    <>
      <path d="M2.5 12S6 5.5 12 5.5 21.5 12 21.5 12 18 18.5 12 18.5 2.5 12 2.5 12Z" />
      <circle cx="12" cy="12" r="3" />
    </>
  ),
  occhioBarrato: (
    <>
      <path d="M3 3l18 18" />
      <path d="M10.6 5.6A9.7 9.7 0 0 1 12 5.5c6 0 9.5 6.5 9.5 6.5a16 16 0 0 1-3.2 3.9M6.4 7.2A15.6 15.6 0 0 0 2.5 12S6 18.5 12 18.5c1.4 0 2.7-.3 3.8-.8" />
      <path d="M9.9 9.9a3 3 0 0 0 4.2 4.2" />
    </>
  ),
}

function Icona({ nome }: { nome: keyof typeof ICONE }) {
  return (
    <svg className="acc-icona" viewBox="0 0 24 24" aria-hidden="true">
      {ICONE[nome]}
    </svg>
  )
}

export function AuthScreen() {
  const [mode, setMode] = useState<Modo>('login')
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [mostra, setMostra] = useState(false)
  const [pending, setPending] = useState(false)
  const [message, setMessage] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)

  function cambiaModo(nuovo: Modo) {
    setMode(nuovo)
    setError(null)
    setMessage(null)
  }

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

  const login = mode === 'login'

  return (
    <main className="acc">
      <div className="acc-sfondo" aria-hidden="true">
        <span className="acc-cerchio" />
        <span className="acc-linea" />
      </div>

      <div className="acc-colonna">
        <header className="acc-marchio">
          <img src="/specialone-mark.svg" alt="" />
          <span>SpecialOne</span>
        </header>

        <section className="acc-titolo" aria-label="Presentazione SpecialOne">
          <p className="acc-occhiello">La tua lega · Una giornata ogni notte</p>
          <h1>Costruisci la rosa.<br />Decidi la partita.</h1>
        </section>

        <section className="acc-scheda">
          <div className="acc-tab" role="tablist" aria-label="Accedi o crea un account">
            <button type="button" role="tab" aria-selected={login} onClick={() => cambiaModo('login')}>Accedi</button>
            <button type="button" role="tab" aria-selected={!login} onClick={() => cambiaModo('signup')}>Crea account</button>
          </div>

          <form className="acc-form" onSubmit={submit}>
            <label className="acc-campo">
              <span>Email</span>
              <div className="acc-input">
                <Icona nome="email" />
                <input
                  type="email"
                  inputMode="email"
                  autoComplete="email"
                  autoCapitalize="none"
                  spellCheck={false}
                  placeholder="nome@esempio.it"
                  required
                  value={email}
                  onChange={(event) => setEmail(event.target.value)}
                />
              </div>
            </label>

            <label className="acc-campo">
              <span>Password</span>
              <div className="acc-input">
                <Icona nome="password" />
                <input
                  type={mostra ? 'text' : 'password'}
                  autoComplete={login ? 'current-password' : 'new-password'}
                  placeholder={login ? 'La tua password' : 'Almeno 6 caratteri'}
                  minLength={6}
                  required
                  value={password}
                  onChange={(event) => setPassword(event.target.value)}
                />
                <button
                  type="button"
                  className="acc-occhio"
                  aria-label={mostra ? 'Nascondi password' : 'Mostra password'}
                  aria-pressed={mostra}
                  onClick={() => setMostra((v) => !v)}
                >
                  <Icona nome={mostra ? 'occhioBarrato' : 'occhio'} />
                </button>
              </div>
            </label>

            {error && <p className="acc-avviso acc-avviso--errore" role="alert">{error}</p>}
            {message && <p className="acc-avviso acc-avviso--ok" role="status">{message}</p>}

            <button className="acc-invio" type="submit" disabled={pending}>
              {pending ? 'Attendi…' : login ? 'Entra in panchina' : 'Crea il mio account'}
            </button>
          </form>

          <p className="acc-cambio">
            {login ? 'Non hai ancora un account?' : 'Hai già un account?'}
            <button type="button" onClick={() => cambiaModo(login ? 'signup' : 'login')}>
              {login ? 'Crea account' : 'Accedi'}
            </button>
          </p>
        </section>

        <p className="acc-piede">Un manageriale calcistico a turni per il tuo gruppo di amici.</p>
      </div>
    </main>
  )
}
