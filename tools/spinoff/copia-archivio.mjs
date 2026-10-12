// Copia i file dell'archivio (foto giocatori e stemmi) dal cloud al Supabase del Mac. Solo letture sul cloud.
// Uso: CLOUD_URL=... CLOUD_SERVICE_KEY=... LOCAL_URL=http://localhost:8000 LOCAL_SERVICE_KEY=... node tools/spinoff/copia-archivio.mjs
// L'elenco dei file (bucket, nome, tipo) sta in ~/supabase-spinoff/dump/oggetti.json (query su storage.objects del cloud).
import { readFileSync } from 'fs'
const { CLOUD_URL, CLOUD_SERVICE_KEY, LOCAL_URL, LOCAL_SERVICE_KEY } = process.env
if (!CLOUD_URL || !CLOUD_SERVICE_KEY || !LOCAL_URL || !LOCAL_SERVICE_KEY) { console.error('Servono CLOUD_URL, CLOUD_SERVICE_KEY, LOCAL_URL, LOCAL_SERVICE_KEY'); process.exit(1) }
const oggetti = JSON.parse(readFileSync(`${process.env.HOME}/supabase-spinoff/dump/oggetti.json`, 'utf8'))
const percorso = (n) => n.split('/').map(encodeURIComponent).join('/')
let fatti = 0, saltati = 0, errori = 0
async function una(o) {
  const url = `${LOCAL_URL}/storage/v1/object/${o.bucket_id}/${percorso(o.name)}`
  const gia = await fetch(url, { method: 'HEAD', headers: { Authorization: `Bearer ${LOCAL_SERVICE_KEY}` } })
  if (gia.ok) { saltati++; return }
  const origine = await fetch(`${CLOUD_URL}/storage/v1/object/${o.bucket_id}/${percorso(o.name)}`, { headers: { Authorization: `Bearer ${CLOUD_SERVICE_KEY}` } })
  if (!origine.ok) { errori++; console.error('lettura', o.bucket_id, o.name, origine.status); return }
  const corpo = Buffer.from(await origine.arrayBuffer())
  const r = await fetch(url, { method: 'POST', headers: { Authorization: `Bearer ${LOCAL_SERVICE_KEY}`, 'Content-Type': o.mime, 'x-upsert': 'true' }, body: corpo })
  if (!r.ok) { errori++; console.error('scrittura', o.bucket_id, o.name, r.status, (await r.text()).slice(0, 120)) } else fatti++
}
const coda = [...oggetti]
await Promise.all(Array.from({ length: 8 }, async () => { while (coda.length) { await una(coda.shift()); if ((fatti + saltati + errori) % 500 === 0) console.log(`${fatti + saltati + errori}/${oggetti.length}`) } }))
console.log(`finito: copiati ${fatti}, gia' presenti ${saltati}, errori ${errori}`)
