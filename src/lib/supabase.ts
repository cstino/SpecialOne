import { createClient } from '@supabase/supabase-js'

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL as string | undefined
const supabaseKey = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY as string | undefined

export const configurationError =
  !supabaseUrl || !supabaseKey
    ? 'Configurazione Supabase assente. Copia .env.example in .env.local e inserisci la publishable key.'
    : null

export const supabase = createClient(
  supabaseUrl ?? 'http://127.0.0.1:54321',
  supabaseKey ?? 'missing-publishable-key',
  {
    auth: {
      persistSession: true,
      autoRefreshToken: true,
      detectSessionInUrl: true,
    },
  },
)
