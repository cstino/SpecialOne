import { supabase } from '../lib/supabase'
import { stemmaPresetDaValore } from '../lib/teamCrests'
import { costruisciTelecronaca, type GiocatoreTelecronaca, type Riga } from '../lib/telecronaca'
import { curvaPressione } from '../lib/pressione'
import { cognome } from '../lib/nomi'
import type { EventoPartita } from '../types'

// Tutto quello che gli occhiali mostrano, letto con l'utente collegato (stesse regole di lettura dell'app).
export type Squadra = { id: number; nome: string; stemma: string | null }
export type Lega = { id: number; nome: string; squadra: Squadra; stagioneId: number | null; inCorso: boolean }
export type Partita = {
  fixtureId: number; giornata: number; dataSim: string; stato: string
  casa: Squadra; ospite: Squadra; inCasa: boolean
}
export type Evento = { minuto: number; lato: 'casa' | 'ospite'; tipo: 'gol' | 'giallo' | 'rosso'; testo: string }
export type Gol = { minuto: number; lato: 'casa' | 'ospite'; marcatore: string; assist: string | null }
export type Risultato = Partita & {
  golCasa: number; golOspite: number; svelata: boolean; eventi: Evento[]
  // Per la diretta: telecronaca dell'app (stesse frasi), gol, curva della pressione, durata.
  telecronaca: Riga[]; gol: Gol[]; curva: number[]; fine: number
}
export type RigaClassifica = { posizione: number; nome: string; punti: number; giocate: number; mia: boolean }
export type Notifica = { titolo: string; corpo: string | null; quando: string; letta: boolean }
export type Quadro = {
  prossima: Partita | null; formazioneSalvata: boolean | null
  ultima: Risultato | null; classifica: RigaClassifica[]; notifiche: Notifica[]
}

const stemmaDi = (valore: string | null) => stemmaPresetDaValore(valore)?.src ?? null

export async function caricaLeghe(): Promise<Lega[]> {
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return []
  const { data: squadre } = await supabase.from('teams').select('id, nome, stemma_url, league_id').eq('user_id', user.id).eq('attiva', true)
  const ids = [...new Set((squadre ?? []).map((s) => s.league_id))]
  if (!ids.length) return []
  const [{ data: leghe }, { data: stagioni }] = await Promise.all([
    supabase.from('leagues').select('id, nome, stato, stagione_corrente').in('id', ids),
    supabase.from('seasons').select('id, league_id, numero, stato').in('league_id', ids),
  ])
  return (squadre ?? []).map((s) => {
    const l = (leghe ?? []).find((x) => x.id === s.league_id)
    const st = (stagioni ?? []).find((x) => x.league_id === s.league_id && x.numero === l?.stagione_corrente)
    return { id: s.league_id, nome: l?.nome ?? 'Lega', squadra: { id: s.id, nome: s.nome, stemma: stemmaDi(s.stemma_url) }, stagioneId: st?.id ?? null, inCorso: st?.stato === 'in_corso' }
  }).sort((a, b) => Number(b.inCorso) - Number(a.inCorso) || a.nome.localeCompare(b.nome))
}

export async function caricaQuadro(lega: Lega): Promise<Quadro> {
  const vuoto: Quadro = { prossima: null, formazioneSalvata: null, ultima: null, classifica: [], notifiche: [] }
  const { data: { user } } = await supabase.auth.getUser()
  if (!user || !lega.stagioneId) return vuoto
  const mia = lega.squadra.id
  const [{ data: partite }, { data: classifica }, { data: notifiche }] = await Promise.all([
    supabase.from('fixtures').select('id, giornata, home_team_id, away_team_id, data_sim, stato')
      .eq('season_id', lega.stagioneId).or(`home_team_id.eq.${mia},away_team_id.eq.${mia}`).order('data_sim'),
    supabase.from('standings').select('team_id, posizione, punti, giocate, conferenza').eq('season_id', lega.stagioneId).order('posizione'),
    supabase.from('notifications').select('titolo, corpo, creata_il, letta_il, league_id').eq('user_id', user.id)
      .order('creata_il', { ascending: false }).limit(3),
  ])
  const lista = partite ?? []
  const prossimaF = lista.find((f) => f.stato === 'programmata' || f.stato === 'in_corso') ?? null
  const ultimaF = [...lista].reverse().find((f) => f.stato === 'simulata') ?? null
  const miaConf = (classifica ?? []).find((r) => r.team_id === mia)?.conferenza ?? null
  const righe = (classifica ?? []).filter((r) => !miaConf || r.conferenza === miaConf)
  const idSquadre = [...new Set([...lista.flatMap((f) => [f.home_team_id, f.away_team_id]), ...righe.map((r) => r.team_id)])]
  const { data: squadre } = await supabase.from('teams').select('id, nome, stemma_url').in('id', idSquadre)
  const squadra = (id: number): Squadra => {
    const s = (squadre ?? []).find((x) => x.id === id)
    return { id, nome: s?.nome ?? 'Squadra', stemma: stemmaDi(s?.stemma_url ?? null) }
  }
  const partita = (f: NonNullable<typeof prossimaF>): Partita => ({
    fixtureId: f.id, giornata: f.giornata, dataSim: f.data_sim, stato: f.stato,
    casa: squadra(f.home_team_id), ospite: squadra(f.away_team_id), inCasa: f.home_team_id === mia,
  })

  let formazioneSalvata: boolean | null = null
  if (prossimaF) {
    const { data: l } = await supabase.from('lineups').select('automatica').eq('team_id', mia).eq('giornata', prossimaF.giornata).maybeSingle()
    formazioneSalvata = Boolean(l && !l.automatica)
  }

  let ultima: Risultato | null = null
  if (ultimaF) {
    const { data: m } = await supabase.from('matches').select('id, gol_home, gol_away, blocchi, titolari_home, titolari_away').eq('fixture_id', ultimaF.id).maybeSingle()
    if (m) {
      const { data: vista } = await supabase.from('match_reveals').select('match_id').eq('match_id', m.id).eq('user_id', user.id).maybeSingle()
      const tutti = ((m.blocchi ?? []) as EventoPartita[]).slice().sort((a, b) => a.minuto - b.minuto)
      const grezzi = tutti as unknown as Array<Record<string, unknown>>
      const ids = [...new Set([
        ...grezzi.flatMap((e) => [e.marcatore, e.assist, e.giocatore, e.entra, e.esce]),
        ...((m.titolari_home ?? []) as number[]), ...((m.titolari_away ?? []) as number[]),
      ].filter((x): x is number => typeof x === 'number' && x > 0))]
      const { data: istanze } = ids.length ? await supabase.from('player_instances').select('id, player_id').in('id', ids) : { data: [] }
      const { data: anagrafica } = (istanze ?? []).length ? await supabase.from('players').select('id, nome, posizioni').in('id', (istanze ?? []).map((i) => i.player_id)) : { data: [] }
      const nomi = new Map<number, GiocatoreTelecronaca>((istanze ?? []).flatMap((i) => {
        const g = (anagrafica ?? []).find((p) => p.id === i.player_id)
        return g ? [[i.id, { nome: g.nome, posizioni: g.posizioni }] as const] : []
      }))
      const nome = (id: unknown) => (typeof id === 'number' ? nomi.get(id)?.nome : null) ?? '—'
      const eventi: Evento[] = grezzi.filter((e) => e.tipo === 'gol' || 'marcatore' in e || e.tipo === 'cartellino').map((e) => {
        const gol = e.tipo === 'gol' || 'marcatore' in e
        const tipo: Evento['tipo'] = gol ? 'gol' : e.colore === 'giallo' ? 'giallo' : 'rosso'
        const lato: Evento['lato'] = e.lato === 'ospite' ? 'ospite' : 'casa'
        return { minuto: Number(e.minuto), lato, tipo, testo: gol ? `${nome(e.marcatore)}${e.assist ? ` (assist ${nome(e.assist)})` : ''}` : nome(e.giocatore) }
      })
      // Squadre, sigle e allenatori come nella diretta del telefono.
      const { data: sq } = await supabase.from('teams').select('id, nome, sigla, user_id, controllata_da_pc').in('id', [ultimaF.home_team_id, ultimaF.away_team_id])
      const casaSq = (sq ?? []).find((t) => t.id === ultimaF.home_team_id)
      const ospiteSq = (sq ?? []).find((t) => t.id === ultimaF.away_team_id)
      const utenti = [casaSq, ospiteSq].filter((t) => t && !t.controllata_da_pc && t.user_id).map((t) => t!.user_id as string)
      const { data: profili } = utenti.length ? await supabase.from('profiles').select('user_id, nome_allenatore').in('user_id', utenti) : { data: [] }
      const allenatore = (t: typeof casaSq) => (t && !t.controllata_da_pc ? (profili ?? []).find((p) => p.user_id === t.user_id)?.nome_allenatore ?? null : null)
      const fine = tutti.some((e) => e.minuto > 90) ? 120 : 90
      const telecronaca = costruisciTelecronaca({
        eventi: tutti, nomi,
        titolariCasa: (m.titolari_home ?? []) as number[], titolariOspite: (m.titolari_away ?? []) as number[],
        casa: { nome: casaSq?.nome ?? 'Casa', sigla: casaSq?.sigla ?? 'CAS' },
        ospite: { nome: ospiteSq?.nome ?? 'Ospite', sigla: ospiteSq?.sigla ?? 'OSP' },
        allenatoreCasa: allenatore(casaSq), allenatoreOspite: allenatore(ospiteSq),
        seme: m.id, supplementari: fine > 90,
      })
      const gol: Gol[] = grezzi.filter((e) => e.tipo === 'gol' || 'marcatore' in e).map((e) => ({
        minuto: Number(e.minuto), lato: e.lato === 'ospite' ? 'ospite' : 'casa',
        marcatore: cognome(nome(e.marcatore)), assist: e.assist ? cognome(nome(e.assist)) : null,
      }))
      ultima = {
        ...partita(ultimaF), golCasa: m.gol_home, golOspite: m.gol_away, svelata: Boolean(vista), eventi,
        telecronaca, gol, curva: curvaPressione(tutti, fine, m.id), fine,
      }
    }
  }

  const ordinate = righe.map((r, i) => ({ posizione: r.posizione ?? i + 1, nome: squadra(r.team_id).nome, punti: r.punti, giocate: r.giocate, mia: r.team_id === mia }))
  const iMia = ordinate.findIndex((r) => r.mia)
  const da = Math.max(0, Math.min(iMia - 1, ordinate.length - 3))
  return {
    prossima: prossimaF ? partita(prossimaF) : null,
    formazioneSalvata,
    ultima,
    classifica: iMia < 0 ? ordinate.slice(0, 3) : ordinate.slice(da, da + 3),
    notifiche: (notifiche ?? []).filter((n) => n.league_id == null || n.league_id === lega.id)
      .map((n) => ({ titolo: n.titolo, corpo: n.corpo, quando: n.creata_il, letta: Boolean(n.letta_il) })),
  }
}

// Collegamento: il codice di 6 cifre creato dal telefono diventa un accesso.
export async function collega(codice: string): Promise<string | null> {
  const url = import.meta.env.VITE_SUPABASE_URL as string
  const chiave = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY as string
  try {
    const r = await fetch(`${url}/functions/v1/collega-occhiali`, {
      method: 'POST', headers: { apikey: chiave, 'Content-Type': 'application/json' }, body: JSON.stringify({ codice }),
    })
    const d = await r.json()
    if (!r.ok || !d.token_hash) return d.errore ?? 'Collegamento non riuscito.'
    const { error } = await supabase.auth.verifyOtp({ token_hash: d.token_hash, type: 'magiclink' })
    if (error) return 'Collegamento non riuscito, riprova.'
    // Si registra la sessione degli occhiali, cosi' dal telefono si possono scollegare.
    await supabase.rpc('registra_occhiali')
    return null
  } catch {
    return 'Server non raggiungibile.'
  }
}
