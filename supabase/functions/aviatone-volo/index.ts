// AviatOne: avvisa il telefono nell'istante esatto in cui l'aereo vola via.
// Il telefono chiama questa funzione appena l'aereo decolla; la funzione legge (con la chiave di servizio) quando il
// giro finisce e tiene la risposta in sospeso fino a quel momento, poi restituisce il punto di crash. Cosi' nessuno
// lo sa prima, ma lo si sa subito (prima arrivava con il controllo ogni mezzo secondo e il numero "scappava" oltre).
// Se mancano piu' di 25 secondi risponde "non ancora" e il telefono richiama.
const URL_SUPABASE = Deno.env.get('SUPABASE_URL') ?? ''
const CHIAVE_SERVIZIO = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
const ATTESA_MASSIMA = 25_000

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
  let giro = 0
  try { giro = Number((await req.json())?.giro) } catch { /* corpo non valido */ }
  if (!Number.isInteger(giro) || giro <= 0) return risposta(400, { errore: 'Giro non valido.' })

  const r = await fetch(`${URL_SUPABASE}/rest/v1/casino_av_giri?id=eq.${giro}&select=finisce_il,crash`, {
    headers: { apikey: CHIAVE_SERVIZIO, Authorization: `Bearer ${CHIAVE_SERVIZIO}` },
  })
  const righe = r.ok ? await r.json() : []
  if (!righe.length) return risposta(404, { errore: 'Giro non trovato.' })
  const fine = new Date(righe[0].finisce_il).getTime()
  const attesa = fine - Date.now()
  if (attesa > ATTESA_MASSIMA) return risposta(200, { giro, finito: false })
  if (attesa > 0) await new Promise((ok) => setTimeout(ok, attesa))
  return risposta(200, { giro, finito: true, crash: Number(righe[0].crash) })
})
