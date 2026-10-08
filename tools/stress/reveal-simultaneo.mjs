// PROVA DI CARICO — N persone che aprono l'app e guardano lo stesso risultato nello stesso momento.
//
// Uso (le chiavi NON stanno nel codice, si passano da terminale):
//   SUPABASE_URL=https://xxx.supabase.co SUPABASE_ANON_KEY=... \
//   EMAIL=... PASSWORD=... LEGA=62 N=20 \
//   node tools/stress/reveal-simultaneo.mjs
//
// La chiave anon e' quella pubblica dell'app (la stessa del browser). EMAIL/PASSWORD: un account della lega
// (meglio una lega di prova come LegaBot). Lo stesso account apre N sessioni insieme: le richieste passano dalle
// stesse regole di sicurezza (RLS) di un partecipante vero. Solo letture: non scrive nulla.
//
// Ogni "persona" rifa' le richieste di quando si apre l'app (dati della stagione, stemmi) e poi quelle della
// cronaca della partita (statistiche, giocatori, formazioni). Misura i tempi e gli errori.
import { createClient } from '@supabase/supabase-js'

const { SUPABASE_URL, SUPABASE_ANON_KEY, EMAIL, PASSWORD } = process.env
const LEGA = Number(process.env.LEGA ?? 62)
const N = Number(process.env.N ?? 20)
const GIRI = Number(process.env.GIRI ?? 1)
if (!SUPABASE_URL || !SUPABASE_ANON_KEY || !EMAIL || (!PASSWORD && !process.env.SERVICE_ROLE_KEY)) {
  console.error('Servono SUPABASE_URL, SUPABASE_ANON_KEY, EMAIL e PASSWORD (vedi in cima al file).')
  process.exit(1)
}

const tempi = []
const errori = []
async function misura(nome, promessa) {
  const t0 = performance.now()
  try {
    const r = await promessa
    const ms = performance.now() - t0
    tempi.push({ nome, ms })
    if (r?.error) errori.push(`${nome}: ${r.error.message}`)
    return r
  } catch (e) {
    errori.push(`${nome}: ${e.message}`)
    return { data: null }
  }
}

async function persona(i, token) {
  const sb = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { Authorization: `Bearer ${token}` } },
  })
  const t0 = performance.now()
  const { data: lega } = await misura('leagues', sb.from('leagues').select('*').eq('id', LEGA).maybeSingle())
  const [stagione, squadre] = await Promise.all([
    misura('seasons', sb.from('seasons').select('*').eq('league_id', LEGA).eq('numero', lega?.stagione_corrente ?? 1).maybeSingle()),
    misura('teams', sb.from('teams').select('*').eq('league_id', LEGA).order('nome')),
  ])
  const percorsi = (squadre.data ?? []).map((t) => t.stemma_url).filter((u) => u && !u.startsWith('preset:'))
  if (percorsi.length) await misura('stemmi (batch)', sb.storage.from('team-crests').createSignedUrls(percorsi, 3600))
  const sid = stagione.data?.id
  const [fix, partite] = await Promise.all([
    misura('fixtures', sb.from('fixtures').select('*').eq('league_id', LEGA).eq('season_id', sid).order('giornata').order('id')),
    misura('matches', sb.from('matches').select('id, fixture_id, league_id, gol_home, gol_away, modulo_home, modulo_away, titolari_home, titolari_away, simulata_il, gol_home_90, gol_away_90, rigori_home, rigori_away, fixtures!inner(season_id)').eq('league_id', LEGA).eq('fixtures.season_id', sid).order('simulata_il', { ascending: false })),
    misura('standings', sb.from('standings').select('*').eq('league_id', LEGA).eq('season_id', sid)),
  ])
  // La partita piu' recente: quella che tutti aprono insieme.
  const match = (partite.data ?? [])[0]
  if (match) {
    // Come l'app: la cronaca completa solo della partita aperta.
    await misura('partita completa', sb.from('matches').select('id, blocchi, stats_squadra, rigori_serie').eq('id', match.id).maybeSingle())
    const fixture = (fix.data ?? []).find((f) => f.id === match.fixture_id)
    const [stats] = await Promise.all([
      misura('match_stats', sb.from('match_stats').select('team_id, player_instance_id, minuti, gol, tiri, tiri_porta').eq('match_id', match.id)),
      misura('lineups', sb.from('lineups').select('team_id, modulo, titolari, disposizione').eq('league_id', LEGA).eq('giornata', fixture?.giornata ?? 1)
        .in('team_id', [fixture?.home_team_id ?? 0, fixture?.away_team_id ?? 0])),
      misura('pagelle', sb.from('pagelle').select('player_instance_id, voto, migliore_in_campo').eq('match_id', match.id)),
    ])
    const ids = [...new Set([...(match.titolari_home ?? []), ...(match.titolari_away ?? []), ...(stats.data ?? []).map((s) => s.player_instance_id)])]
    const ist = await misura('player_instances', sb.from('player_instances').select('id, player_id').in('id', ids))
    const pids = [...new Set((ist.data ?? []).map((x) => x.player_id))]
    if (pids.length) await misura('players', sb.from('players').select('id, nome, foto_url, posizioni').in('id', pids))
  }
  return performance.now() - t0
}

// Accesso: con PASSWORD come un utente qualsiasi; senza, con SERVICE_ROLE_KEY si genera un link magico per EMAIL
// (nessuna email spedita) e lo si conferma subito: e' la sessione vera di quell'utente, RLS compresa.
const accesso = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, { auth: { persistSession: false } })
let token
if (PASSWORD) {
  const { data: sessione, error } = await accesso.auth.signInWithPassword({ email: EMAIL, password: PASSWORD })
  if (error) { console.error('Accesso non riuscito:', error.message); process.exit(1) }
  token = sessione.session.access_token
} else {
  const admin = createClient(SUPABASE_URL, process.env.SERVICE_ROLE_KEY, { auth: { persistSession: false } })
  const { data: link, error } = await admin.auth.admin.generateLink({ type: 'magiclink', email: EMAIL })
  if (error) { console.error('Link non generato:', error.message); process.exit(1) }
  const { data: sessione, error: e2 } = await accesso.auth.verifyOtp({ token_hash: link.properties.hashed_token, type: 'magiclink' })
  if (e2) { console.error('Accesso non riuscito:', e2.message); process.exit(1) }
  token = sessione.session.access_token
}

for (let giro = 1; giro <= GIRI; giro++) {
  tempi.length = 0; errori.length = 0
  const t0 = performance.now()
  const durate = await Promise.all(Array.from({ length: N }, (_, i) => persona(i, token)))
  const totale = performance.now() - t0
  durate.sort((a, b) => a - b)
  const q = (a, p) => a[Math.min(a.length - 1, Math.floor(p * a.length))]
  console.log(`\nGiro ${giro}: ${N} persone insieme, lega ${LEGA}`)
  console.log(`  tempo per persona (app + risultato): mediana ${(q(durate, .5) / 1000).toFixed(2)} s · peggiore ${(durate.at(-1) / 1000).toFixed(2)} s`)
  console.log(`  tutto finito in ${(totale / 1000).toFixed(2)} s · richieste ${tempi.length} · errori ${errori.length}`)
  const perNome = new Map()
  for (const t of tempi) perNome.set(t.nome, [...(perNome.get(t.nome) ?? []), t.ms])
  for (const [nome, v] of perNome) { v.sort((a, b) => a - b); console.log(`  ${nome.padEnd(18)} mediana ${Math.round(q(v, .5))} ms · peggiore ${Math.round(v.at(-1))} ms`) }
  if (errori.length) console.log('  ERRORI:', [...new Set(errori)].slice(0, 8).join(' | '))
}
