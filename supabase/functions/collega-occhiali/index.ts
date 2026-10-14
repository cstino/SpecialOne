// Collega gli occhiali Ray-Ban Display all'account: riceve il codice di 6 cifre creato dal telefono
// (public.crea_codice_occhiali), lo consuma e restituisce un token di accesso monouso (magic link generato
// dall'admin di GoTrue, senza inviare email). Gli occhiali lo verificano con supabase.auth.verifyOtp.
const URL_SUPABASE = Deno.env.get('SUPABASE_URL') ?? ''
const CHIAVE_SERVIZIO = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, apikey, content-type, x-client-info',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}
const risposta = (stato: number, corpo: unknown) =>
  new Response(JSON.stringify(corpo), { status: stato, headers: { ...CORS, 'Content-Type': 'application/json' } })

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS })
  if (req.method !== 'POST') return risposta(405, { errore: 'Metodo non ammesso.' })
  let codice = ''
  try { codice = String((await req.json())?.codice ?? '').replace(/\D/g, '') } catch { /* corpo non valido */ }
  if (codice.length !== 6) return risposta(400, { errore: 'Il codice ha 6 cifre.' })

  const servizio = { apikey: CHIAVE_SERVIZIO, Authorization: `Bearer ${CHIAVE_SERVIZIO}`, 'Content-Type': 'application/json' }
  const r1 = await fetch(`${URL_SUPABASE}/rest/v1/rpc/usa_codice_occhiali`, { method: 'POST', headers: servizio, body: JSON.stringify({ p_codice: codice }) })
  const email = r1.ok ? await r1.json() : null
  if (!email) return risposta(401, { errore: 'Codice sbagliato o scaduto. Creane uno nuovo dal telefono.' })

  const r2 = await fetch(`${URL_SUPABASE}/auth/v1/admin/generate_link`, { method: 'POST', headers: servizio, body: JSON.stringify({ type: 'magiclink', email }) })
  const link = r2.ok ? await r2.json() : null
  const token = link?.hashed_token ?? link?.properties?.hashed_token
  if (!token) return risposta(500, { errore: 'Accesso non riuscito, riprova.' })
  return risposta(200, { token_hash: token })
})
