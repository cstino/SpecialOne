import { useCallback, useEffect, useMemo, useState, type ReactNode } from 'react'
import { supabase } from '../lib/supabase'
import { useSeasonData } from '../lib/useSeasonData'
import type { League, Membership } from '../types'
import { Crest } from './Crest'
import { GameNav, type GameView } from './GameNav'
import { LoadingLogo } from './LoadingLogo'
import { firmaFoto } from './RosaElenco'

// SocialOne: il feed social della lega (docs/decisioni-conferenze-stampa.md §3), in stile X.
// Un post per ogni evento, generato dal database; lo vede tutta la lega, l'utente vede per primi
// quelli che riguardano la sua squadra. Le conversazioni (domanda -> allenatore -> tifosi -> capitano)
// si leggono a filo, in ordine di tempo. Risultati e scambi hanno la loro card.

export type PostSocial = {
  id: number
  autore_tipo: 'lega' | 'testata' | 'allenatore' | 'tifosi' | 'giocatore'
  autore_nome: string
  team_id: number | null
  team2_id: number | null
  player_instance_id: number | null
  in_risposta_a: number | null
  testo: string
  creato_il: string
  n_mi_piace: number
  mio_mi_piace: boolean
  riguarda_me: boolean
}

type Dati = ReturnType<typeof useSeasonData>

const PAGINA = 30

// ------------------------------------------------------------
//  Dati
// ------------------------------------------------------------

export function useSocialFeed(leagueId: number, perTe: boolean, limite = PAGINA) {
  const [post, setPost] = useState<PostSocial[]>([])
  const [caricamento, setCaricamento] = useState(true)
  const [altri, setAltri] = useState(false)
  const [errore, setErrore] = useState<string | null>(null)

  const carica = useCallback(async (offset: number) => {
    const { data, error } = await supabase.rpc('social_feed', { p_league_id: leagueId, p_per_te: perTe, p_limite: limite, p_offset: offset })
    if (error) { setErrore(error.message); setCaricamento(false); return }
    const righe = (data ?? []).map((r: PostSocial) => ({ ...r, n_mi_piace: Number(r.n_mi_piace) })) as PostSocial[]
    setPost((prima) => offset === 0 ? righe : [...prima, ...righe.filter((r) => !prima.some((p) => p.id === r.id))])
    setAltri(righe.length === limite)
    setErrore(null)
    setCaricamento(false)
  }, [leagueId, perTe, limite])

  useEffect(() => { setCaricamento(true); void carica(0) }, [carica])

  const mostraAltri = useCallback(() => void carica(post.length), [carica, post.length])
  const mettiMiPiace = useCallback(async (id: number) => {
    setPost((p) => p.map((x) => x.id === id ? { ...x, mio_mi_piace: !x.mio_mi_piace, n_mi_piace: x.n_mi_piace + (x.mio_mi_piace ? -1 : 1) } : x))
    const { data, error } = await supabase.rpc('social_mi_piace', { p_post_id: id })
    if (error) { void carica(0); return }
    const r = (data as Array<{ mio: boolean; totale: number }> | null)?.[0]
    if (r) setPost((p) => p.map((x) => x.id === id ? { ...x, mio_mi_piace: r.mio, n_mi_piace: Number(r.totale) } : x))
  }, [carica])

  return { post, caricamento, altri, errore, mostraAltri, mettiMiPiace, ricarica: () => void carica(0) }
}

function useFotoGiocatori(post: PostSocial[]) {
  const [foto, setFoto] = useState<Map<number, string>>(new Map())
  const ids = useMemo(() => [...new Set(post.flatMap((p) => p.player_instance_id ? [p.player_instance_id] : []))].sort((a, b) => a - b).join(','), [post])
  useEffect(() => {
    if (!ids) return
    let vivo = true
    void (async () => {
      const { data: istanze } = await supabase.from('player_instances').select('id, player_id').in('id', ids.split(',').map(Number))
      const playerIds = [...new Set((istanze ?? []).map((i) => i.player_id))]
      const { data: giocatori } = playerIds.length ? await supabase.from('players').select('id, foto_url').in('id', playerIds) : { data: [] }
      const firmate = await Promise.all((giocatori ?? []).map(async (g) => [g.id, await firmaFoto(g.foto_url)] as const))
      if (!vivo) return
      const perPlayer = new Map(firmate)
      setFoto(new Map((istanze ?? []).flatMap((i) => { const url = perPlayer.get(i.player_id); return url ? [[i.id, url] as const] : [] })))
    })()
    return () => { vivo = false }
  }, [ids])
  return foto
}

// Le conversazioni: ogni post risale alla sua radice; il filo si mostra in ordine di tempo, nella
// posizione del suo post piu' in alto nel feed (cosi' la priorita' "per te" resta).
function aFili(post: PostSocial[]): PostSocial[][] {
  const perId = new Map(post.map((p) => [p.id, p]))
  const radice = (p: PostSocial) => { let r = p; const visti = new Set<number>(); while (r.in_risposta_a && perId.has(r.in_risposta_a) && !visti.has(r.id)) { visti.add(r.id); r = perId.get(r.in_risposta_a)! } return r.id }
  const fili = new Map<number, PostSocial[]>()
  for (const p of post) { const k = radice(p); fili.set(k, [...(fili.get(k) ?? []), p]) }
  return [...fili.values()].map((f) => [...f].sort((a, b) => a.creato_il.localeCompare(b.creato_il) || a.id - b.id))
}

// ------------------------------------------------------------
//  Piccoli pezzi
// ------------------------------------------------------------

function tempoBreve(iso: string) {
  const s = Math.max(0, (Date.now() - new Date(iso).getTime()) / 1000)
  if (s < 60) return 'ora'
  if (s < 3600) return `${Math.floor(s / 60)}m`
  if (s < 86400) return `${Math.floor(s / 3600)}h`
  if (s < 7 * 86400) return `${Math.floor(s / 86400)}g`
  return new Date(iso).toLocaleDateString('it-IT', { day: 'numeric', month: 'short', timeZone: 'Europe/Rome' })
}

const slug = (s: string) => s.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().replace(/[^a-z0-9]+/g, '_').replace(/^_|_$/g, '').slice(0, 22)

function handle(p: PostSocial, dati: Dati) {
  const squadra = p.team_id ? dati.teamById.get(p.team_id)?.nome ?? '' : ''
  switch (p.autore_tipo) {
    case 'lega': return 'SpecialOneLega'
    case 'tifosi': return `curva_${slug(squadra)}`
    case 'allenatore': return `mister_${slug(p.autore_nome)}`
    default: return slug(p.autore_nome)
  }
}

// Badge di verifica: oro la lega, blu stampa e giocatori, viola gli allenatori. I tifosi no.
function Verificato({ tipo }: { tipo: PostSocial['autore_tipo'] }) {
  if (tipo === 'tifosi') return null
  return <svg className={`x-verificato x-verificato--${tipo}`} viewBox="0 0 22 22" aria-label="Account verificato" role="img">
    <path fill="currentColor" d="M20.4 11c0-1.3-.8-2.5-2-3 .4-1.3.1-2.7-.8-3.6-.9-.9-2.3-1.2-3.6-.8-.5-1.2-1.7-2-3-2s-2.5.8-3 2c-1.3-.4-2.7-.1-3.6.8-.9.9-1.2 2.3-.8 3.6-1.2.5-2 1.7-2 3s.8 2.5 2 3c-.4 1.3-.1 2.7.8 3.6.9.9 2.3 1.2 3.6.8.5 1.2 1.7 2 3 2s2.5-.8 3-2c1.3.4 2.7.1 3.6-.8.9-.9 1.2-2.3.8-3.6 1.2-.5 2-1.7 2-3z" />
    <path fill="none" stroke="#0b0a10" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" d="m7.2 11.2 2.5 2.5 5.1-5.3" />
  </svg>
}

const IconaAzione: Record<'risposte' | 'cuore' | 'cuorePieno' | 'condividi' | 'fatto', ReactNode> = {
  risposte: <path d="M4.5 11.5a7 7 0 0 1 7-7h1a7 7 0 0 1 0 14H11l-4.5 3v-3.4a7 7 0 0 1-2-6.6z" />,
  cuore: <path d="M12 20.2S4 15.4 4 9.6A4.2 4.2 0 0 1 12 7.8a4.2 4.2 0 0 1 8 1.8c0 5.8-8 10.6-8 10.6Z" />,
  cuorePieno: <path fill="currentColor" d="M12 20.2S4 15.4 4 9.6A4.2 4.2 0 0 1 12 7.8a4.2 4.2 0 0 1 8 1.8c0 5.8-8 10.6-8 10.6Z" />,
  condividi: <><path d="M12 15V4" /><path d="m7.5 8.5 4.5-4.5 4.5 4.5" /><path d="M5 13v5.5A1.5 1.5 0 0 0 6.5 20h11a1.5 1.5 0 0 0 1.5-1.5V13" /></>,
  fatto: <path d="m5 12.5 4.5 4.5L19 7.5" />,
}
function Svg({ nome }: { nome: keyof typeof IconaAzione }) {
  return <svg viewBox="0 0 24 24" aria-hidden="true" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">{IconaAzione[nome]}</svg>
}

function Avatar({ post, dati, foto }: { post: PostSocial; dati: Dati; foto: Map<number, string> }) {
  if (post.autore_tipo === 'lega') return <span className="x-avatar x-avatar--lega"><img src="/specialone-mark.svg" alt="" /></span>
  if (post.autore_tipo === 'giocatore') {
    const url = post.player_instance_id ? foto.get(post.player_instance_id) : undefined
    return <span className="x-avatar x-avatar--giocatore">{url ? <img src={url} alt="" loading="lazy" /> : <b>{post.autore_nome.charAt(0)}</b>}</span>
  }
  if (post.autore_tipo === 'testata') {
    const sigla = post.autore_nome.replace(/[^A-Za-zÀ-ÿ0-9° ]/g, '').split(/\s+/).filter((w) => w.length > 2 || /\d/.test(w)).slice(0, 2).map((w) => w.charAt(0)).join('').toUpperCase()
    return <span className={`x-avatar x-avatar--testata x-avatar--t${Math.abs([...post.autore_nome].reduce((h, c) => h * 31 + c.charCodeAt(0), 7)) % 4}`}><b>{sigla || '?'}</b></span>
  }
  const squadra = post.team_id ? dati.teamById.get(post.team_id) : undefined
  return <span className={`x-avatar x-avatar--${post.autore_tipo}`}>
    {post.team_id && <Crest value={squadra?.stemma_url ?? null} stelle={squadra?.titoli_title} imageUrl={dati.crestUrlByTeamId.get(post.team_id)} size="small" />}
  </span>
}

// Card del risultato: "FINALE · Casa 2-0 Ospite. commento"
function CardPartita({ post, dati }: { post: PostSocial; dati: Dati }) {
  const casa = post.team_id ? dati.teamById.get(post.team_id) : undefined
  const ospite = post.team2_id ? dati.teamById.get(post.team2_id) : undefined
  if (!casa || !ospite) return null
  const resto = post.testo.slice(`FINALE · ${casa.nome} `.length)
  const m = resto.match(/^(\d+)-(\d+) /)
  if (!post.testo.startsWith(`FINALE · ${casa.nome} `) || !m) return null
  const [gc, go] = [Number(m[1]), Number(m[2])]
  const commento = resto.slice(m[0].length + ospite.nome.length).replace(/^\.\s*/, '')
  return <>
    {commento && <p className="x-post__testo">{commento}</p>}
    <div className="x-card x-card--partita">
      <span className="x-card__kicker">Finale</span>
      <div className="x-card__match">
        <span className={`x-card__squadra${gc > go ? ' is-vince' : ''}`}><span className="x-card__stemma"><Crest value={casa.stemma_url ?? null} stelle={casa.titoli_title} imageUrl={dati.crestUrlByTeamId.get(casa.id)} size="small" /></span><b>{casa.nome}</b></span>
        <strong className="x-card__punteggio">{gc}<i>–</i>{go}</strong>
        <span className={`x-card__squadra${go > gc ? ' is-vince' : ''}`}><span className="x-card__stemma"><Crest value={ospite.stemma_url ?? null} stelle={ospite.titoli_title} imageUrl={dati.crestUrlByTeamId.get(ospite.id)} size="small" /></span><b>{ospite.nome}</b></span>
      </div>
    </div>
  </>
}

// Card dello scambio: "‼️ HERE WE GO ‼️ ... A cede X; B cede Y."
function CardScambio({ post, dati }: { post: PostSocial; dati: Dati }) {
  const a = post.team_id ? dati.teamById.get(post.team_id) : undefined
  const b = post.team2_id ? dati.teamById.get(post.team2_id) : undefined
  if (!a || !b || !post.testo.includes('HERE WE GO')) return null
  const cedeA = post.testo.match(new RegExp(`${a.nome.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')} cede ([^;]+);`))?.[1]
  const cedeB = post.testo.match(new RegExp(`${b.nome.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')} cede (.+)\\.$`))?.[1]
  const lato = (t: typeof a, riceve?: string) => <div className="x-card__lato">
    <span className="x-card__stemma"><Crest value={t.stemma_url ?? null} stelle={t.titoli_title} imageUrl={dati.crestUrlByTeamId.get(t.id)} size="small" /></span>
    <b>{t.nome}</b>
    {riceve && <small>riceve <em>{riceve}</em></small>}
  </div>
  return <>
    <p className="x-post__testo"><span className="x-herewego">HERE WE GO</span> È ufficiale lo scambio tra <b>{a.nome}</b> e <b>{b.nome}</b>.</p>
    <div className="x-card x-card--scambio">
      {lato(a, cedeB)}
      <span className="x-card__freccia" aria-hidden="true"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M4 8h14m0 0-3.5-3.5M18 8l-3.5 3.5M20 16H6m0 0 3.5-3.5M6 16l3.5 3.5" /></svg></span>
      {lato(b, cedeA)}
    </div>
  </>
}

// ------------------------------------------------------------
//  Il post
// ------------------------------------------------------------

export function PostX({ post, dati, foto, nRisposte, rispondeA, filoSopra, filoSotto, onMiPiace }: {
  post: PostSocial; dati: Dati; foto: Map<number, string>; nRisposte: number
  rispondeA?: PostSocial | null; filoSopra?: boolean; filoSotto?: boolean; onMiPiace: (id: number) => void
}) {
  const [condiviso, setCondiviso] = useState(false)
  const [scoppio, setScoppio] = useState(0)
  const squadra = post.team_id ? dati.teamById.get(post.team_id)?.nome : undefined
  const card = post.autore_tipo === 'lega' ? (CardPartita({ post, dati }) ?? CardScambio({ post, dati })) : null

  async function condividi() {
    const testo = `${post.autore_nome} su SocialOne: ${post.testo}`
    try {
      if (navigator.share) await navigator.share({ text: testo })
      else { await navigator.clipboard.writeText(testo); setCondiviso(true); window.setTimeout(() => setCondiviso(false), 1600) }
    } catch { /* condivisione annullata */ }
  }

  return <article className={`x-post x-post--${post.autore_tipo}${filoSopra ? ' has-filo-sopra' : ''}${filoSotto ? ' has-filo-sotto' : ''}`}>
    <div className="x-post__colonna">
      {filoSopra && <i className="x-filo x-filo--sopra" aria-hidden="true" />}
      <Avatar post={post} dati={dati} foto={foto} />
      {filoSotto && <i className="x-filo x-filo--sotto" aria-hidden="true" />}
    </div>
    <div className="x-post__corpo">
      <header className="x-post__testa">
        <strong className="x-post__nome">{post.autore_nome}</strong>
        <Verificato tipo={post.autore_tipo} />
        <span className="x-post__handle">@{handle(post, dati)}</span>
        <span className="x-post__punto" aria-hidden="true">·</span>
        <time className="x-post__tempo" dateTime={post.creato_il} title={new Date(post.creato_il).toLocaleString('it-IT', { timeZone: 'Europe/Rome' })}>{tempoBreve(post.creato_il)}</time>
      </header>
      {post.autore_tipo === 'giocatore' && squadra && <p className="x-post__contesto">{squadra}</p>}
      {rispondeA && !filoSopra && <p className="x-post__contesto">In risposta a <b>@{handle(rispondeA, dati)}</b></p>}
      {card ?? <p className="x-post__testo">{post.testo}</p>}
      {post.riguarda_me && <span className="x-post__tua">La tua squadra</span>}
      <footer className="x-azioni">
        <span className={`x-azione x-azione--risposte${nRisposte ? '' : ' is-vuota'}`} aria-label={`${nRisposte} risposte`}><Svg nome="risposte" />{nRisposte > 0 && <span>{nRisposte}</span>}</span>
        <button className={`x-azione x-azione--cuore${post.mio_mi_piace ? ' is-attivo' : ''}`} type="button"
          onClick={() => { if (!post.mio_mi_piace) setScoppio((n) => n + 1); onMiPiace(post.id) }}
          aria-pressed={post.mio_mi_piace} aria-label={post.mio_mi_piace ? 'Togli il mi piace' : 'Metti mi piace'}>
          <span className="x-azione__icona" key={scoppio}><Svg nome={post.mio_mi_piace ? 'cuorePieno' : 'cuore'} /></span>
          {post.n_mi_piace > 0 && <span>{post.n_mi_piace}</span>}
        </button>
        <button className={`x-azione x-azione--condividi${condiviso ? ' is-attivo' : ''}`} type="button" onClick={() => void condividi()} aria-label="Condividi">
          <Svg nome={condiviso ? 'fatto' : 'condividi'} />{condiviso && <span>Copiato</span>}
        </button>
      </footer>
    </div>
  </article>
}

function Feed({ post, dati, foto, onMiPiace }: { post: PostSocial[]; dati: Dati; foto: Map<number, string>; onMiPiace: (id: number) => void }) {
  const fili = useMemo(() => aFili(post), [post])
  const perId = useMemo(() => new Map(post.map((p) => [p.id, p])), [post])
  const risposte = useMemo(() => {
    const n = new Map<number, number>()
    for (const p of post) if (p.in_risposta_a) n.set(p.in_risposta_a, (n.get(p.in_risposta_a) ?? 0) + 1)
    return n
  }, [post])
  return <div className="x-feed">
    {fili.map((filo) => <div className={`x-filo-gruppo${filo.length > 1 ? ' is-conversazione' : ''}`} key={filo[0].id}>
      {filo.map((p, i) => <PostX key={p.id} post={p} dati={dati} foto={foto} nRisposte={risposte.get(p.id) ?? 0}
        rispondeA={p.in_risposta_a ? perId.get(p.in_risposta_a) ?? null : null}
        filoSopra={i > 0} filoSotto={i < filo.length - 1} onMiPiace={onMiPiace} />)}
    </div>)}
  </div>
}

// ------------------------------------------------------------
//  Pagine
// ------------------------------------------------------------

type Props = { membership: Membership; onNavigate: (view: GameView) => void }

export function SocialOne({ membership, onNavigate }: Props) {
  const league = membership.league as League
  const dati = useSeasonData(membership)
  const [scheda, setScheda] = useState<'per-te' | 'lega'>('per-te')
  const { post, caricamento, altri, errore, mostraAltri, mettiMiPiace } = useSocialFeed(league.id, scheda === 'per-te')
  const foto = useFotoGiocatori(post)

  return <main className="app-shell season-shell social-shell">
    <GameNav league={league} active="social" onNavigate={onNavigate} />
    <div className="x-pagina">
      <header className="x-barra">
        <div className="x-barra__titolo">
          <img src="/specialone-mark.svg" alt="" />
          <span>Social<b>One</b></span>
          <small>{league.nome}</small>
        </div>
        <nav className="x-schede" role="tablist" aria-label="Feed">
          {([['per-te', 'Per te'], ['lega', 'Tutta la lega']] as const).map(([valore, testo]) =>
            <button key={valore} type="button" role="tab" aria-selected={scheda === valore} className={scheda === valore ? 'is-attiva' : ''} onClick={() => setScheda(valore)}>
              <span>{testo}</span>
            </button>)}
        </nav>
      </header>
      {caricamento ? <div className="x-stato"><LoadingLogo compatto /><p>Carico il feed…</p></div>
        : errore ? <div className="x-stato"><p>{errore}</p></div>
        : post.length === 0 ? <div className="x-stato"><strong>Ancora nessun post</strong><p>Appena succede qualcosa nella lega, lo trovi qui.</p></div>
        : <>
          <Feed post={post} dati={dati} foto={foto} onMiPiace={(id) => void mettiMiPiace(id)} />
          {altri && <button className="x-altri" type="button" onClick={mostraAltri}>Mostra altri post</button>}
        </>}
    </div>
  </main>
}

// L'anteprima in home, al posto delle notizie: i primi post "per te" e il rimando al feed.
export function SocialAnteprima({ membership, onNavigate }: Props) {
  const league = membership.league as League
  const dati = useSeasonData(membership)
  const { post, caricamento, mettiMiPiace } = useSocialFeed(league.id, true, 6)
  const foto = useFotoGiocatori(post)
  return <section className="dash-sezione x-anteprima">
    <header className="dash-testa">
      <h2 className="dash-linguetta">SocialOne</h2>
      <button className="dash-link" type="button" onClick={() => onNavigate('social')}>Apri il feed ›</button>
    </header>
    <div className="x-anteprima__riquadro">
      {caricamento ? <div className="x-stato"><p>Carico il feed…</p></div>
        : post.length === 0 ? <div className="x-stato"><p>Ancora nessun post: appena succede qualcosa nella lega, lo trovi qui.</p></div>
        : <Feed post={post.slice(0, 4)} dati={dati} foto={foto} onMiPiace={(id) => void mettiMiPiace(id)} />}
      <button className="x-anteprima__tutti" type="button" onClick={() => onNavigate('social')}>Mostra tutto il feed</button>
    </div>
  </section>
}
