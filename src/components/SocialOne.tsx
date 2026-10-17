import { useCallback, useEffect, useMemo, useState } from 'react'
import { supabase } from '../lib/supabase'
import { quandoRelativo } from '../lib/notifiche'
import { useSeasonData } from '../lib/useSeasonData'
import type { League, Membership } from '../types'
import { Crest } from './Crest'
import { GameNav, type GameView } from './GameNav'
import { LoadingLogo } from './LoadingLogo'
import { firmaFoto } from './RosaElenco'
import { UnderlineTabs } from './ui/underline-tabs'

// SocialOne: il feed social della lega (docs/decisioni-conferenze-stampa.md §3).
// Un post per ogni evento, generato dal database; lo vede tutta la lega, l'utente vede
// per primi quelli che riguardano la sua squadra. Un "mi piace" per utente e post.

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

const PAGINA = 30

const ETICHETTA: Record<PostSocial['autore_tipo'], string> = {
  lega: 'Ufficiale', testata: 'Stampa', allenatore: 'Allenatore', tifosi: 'Tifosi', giocatore: 'Giocatore',
}

// Il feed di una lega. `perTe`: prima i post che riguardano la propria squadra.
export function useSocialFeed(leagueId: number, perTe: boolean, limite = PAGINA) {
  const [post, setPost] = useState<PostSocial[]>([])
  const [caricamento, setCaricamento] = useState(true)
  const [altri, setAltri] = useState(false)
  const [errore, setErrore] = useState<string | null>(null)

  const carica = useCallback(async (offset: number) => {
    const { data, error } = await supabase.rpc('social_feed', { p_league_id: leagueId, p_per_te: perTe, p_limite: limite, p_offset: offset })
    if (error) { setErrore(error.message); setCaricamento(false); return }
    const righe = (data ?? []).map((r: PostSocial) => ({ ...r, n_mi_piace: Number(r.n_mi_piace) })) as PostSocial[]
    setPost((precedenti) => offset === 0 ? righe : [...precedenti, ...righe.filter((r) => !precedenti.some((p) => p.id === r.id))])
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

  return { post, caricamento, altri, errore, mostraAltri, mettiMiPiace }
}

// Le foto dei giocatori che compaiono nei post (firmate, come nella cronaca).
function useFotoGiocatori(post: PostSocial[]) {
  const [foto, setFoto] = useState<Map<number, string>>(new Map())
  const ids = useMemo(() => [...new Set(post.flatMap((p) => p.player_instance_id ? [p.player_instance_id] : []))].sort((a, b) => a - b).join(','), [post])
  useEffect(() => {
    if (!ids) return
    let vivo = true
    void (async () => {
      const lista = ids.split(',').map(Number)
      const { data: istanze } = await supabase.from('player_instances').select('id, player_id').in('id', lista)
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

function Cuore({ pieno }: { pieno: boolean }) {
  return <svg viewBox="0 0 24 24" width="18" height="18" aria-hidden="true" fill={pieno ? 'currentColor' : 'none'} stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round">
    <path d="M12 20.2S4 15.4 4 9.6A4.2 4.2 0 0 1 12 7.8a4.2 4.2 0 0 1 8 1.8c0 5.8-8 10.6-8 10.6Z" />
  </svg>
}

type DatiSquadre = ReturnType<typeof useSeasonData>

function Avatar({ post, dati, foto }: { post: PostSocial; dati: DatiSquadre; foto: Map<number, string> }) {
  if (post.autore_tipo === 'lega') return <span className="social-avatar social-avatar--lega"><img src="/specialone-mark.svg" alt="" /></span>
  if (post.autore_tipo === 'giocatore') {
    const url = post.player_instance_id ? foto.get(post.player_instance_id) : undefined
    return <span className="social-avatar social-avatar--giocatore">{url ? <img src={url} alt="" loading="lazy" /> : <b>{post.autore_nome.charAt(0)}</b>}</span>
  }
  if (post.autore_tipo === 'testata') {
    const sigla = post.autore_nome.replace(/[^A-Za-zÀ-ÿ0-9 ]/g, '').split(/\s+/).filter(Boolean).slice(0, 2).map((w) => w.charAt(0)).join('').toUpperCase()
    return <span className="social-avatar social-avatar--testata"><b>{sigla || '?'}</b></span>
  }
  const squadra = post.team_id ? dati.teamById.get(post.team_id) : undefined
  return <span className={`social-avatar social-avatar--${post.autore_tipo}`}>
    {post.team_id && <Crest value={squadra?.stemma_url ?? null} stelle={squadra?.titoli_title} imageUrl={dati.crestUrlByTeamId.get(post.team_id)} size="small" />}
  </span>
}

export function PostCard({ post, dati, foto, risposta, onMiPiace, compatto = false }: {
  post: PostSocial; dati: DatiSquadre; foto: Map<number, string>; risposta?: PostSocial | null; onMiPiace: (id: number) => void; compatto?: boolean
}) {
  const squadra = post.team_id ? dati.teamById.get(post.team_id)?.nome : undefined
  return <article className={`social-post social-post--${post.autore_tipo}${post.riguarda_me ? ' is-mio' : ''}${compatto ? ' is-compatto' : ''}`}>
    <Avatar post={post} dati={dati} foto={foto} />
    <div className="social-post__corpo">
      <header>
        <strong>{post.autore_nome}</strong>
        <span className="social-post__tipo">{ETICHETTA[post.autore_tipo]}</span>
        {post.autore_tipo === 'giocatore' && squadra && <span className="social-post__squadra">{squadra}</span>}
        <time dateTime={post.creato_il}>{quandoRelativo(post.creato_il)}</time>
      </header>
      {risposta && <p className="social-post__risposta">↳ in risposta a <b>{risposta.autore_nome}</b></p>}
      <p className="social-post__testo">{post.testo}</p>
      <footer>
        <button className={`social-post__cuore${post.mio_mi_piace ? ' is-attivo' : ''}`} type="button" onClick={() => onMiPiace(post.id)}
          aria-pressed={post.mio_mi_piace} aria-label={post.mio_mi_piace ? 'Togli il mi piace' : 'Metti mi piace'}>
          <Cuore pieno={post.mio_mi_piace} />{post.n_mi_piace > 0 && <span>{post.n_mi_piace}</span>}
        </button>
        {post.riguarda_me && <em>La tua squadra</em>}
      </footer>
    </div>
  </article>
}

type Props = { membership: Membership; onNavigate: (view: GameView) => void }

export function SocialOne({ membership, onNavigate }: Props) {
  const league = membership.league as League
  const dati = useSeasonData(membership)
  const [scheda, setScheda] = useState<'per-te' | 'lega'>('per-te')
  const { post, caricamento, altri, errore, mostraAltri, mettiMiPiace } = useSocialFeed(league.id, scheda === 'per-te')
  const foto = useFotoGiocatori(post)
  const perId = useMemo(() => new Map(post.map((p) => [p.id, p])), [post])

  return <main className="app-shell season-shell social-shell">
    <GameNav league={league} active="social" onNavigate={onNavigate} />
    <header className="topbar season-topbar"><div className="brand-lockup brand-lockup--dark"><img src="/specialone-mark.svg" alt="" /><span>SpecialOne</span></div><span>SocialOne</span></header>
    <div className="season-page season-page--narrow social-page">
      <section className="alerts-heading">
        <div><p className="kicker">{league.nome}</p><h1>SocialOne.</h1><p>Risultati, mercato, conferenze stampa e i tifosi: tutto quello che succede nella lega, appena succede.</p></div>
      </section>
      <UnderlineTabs
        tabs={[{ value: 'per-te', label: 'Per te' }, { value: 'lega', label: 'Tutta la lega' }] as const}
        value={scheda}
        onChange={setScheda}
      />
      {caricamento ? <section className="season-state is-caricamento"><LoadingLogo compatto /><h2>Carico il feed…</h2><span className="caricamento-barra" aria-hidden="true" /></section>
        : errore ? <p className="notice notice--error">{errore}</p>
        : post.length === 0 ? <section className="alerts-empty"><span aria-hidden="true">◎</span><h2>Ancora nessun post.</h2><p>Appena succede qualcosa nella lega, lo trovi qui.</p></section>
        : <div className="social-feed" aria-label="Feed">
          {post.map((p) => <PostCard key={p.id} post={p} dati={dati} foto={foto} risposta={p.in_risposta_a ? perId.get(p.in_risposta_a) ?? null : null} onMiPiace={(id) => void mettiMiPiace(id)} />)}
          {altri && <button className="button button--secondary social-feed__altri" type="button" onClick={mostraAltri}>Mostra altri</button>}
        </div>}
    </div>
  </main>
}

// L'anteprima in home: al posto delle notizie, i primi post "per te" e il rimando al feed.
export function SocialAnteprima({ membership, onNavigate }: Props) {
  const league = membership.league as League
  const dati = useSeasonData(membership)
  const { post, caricamento, mettiMiPiace } = useSocialFeed(league.id, true, 4)
  const foto = useFotoGiocatori(post)
  return <section className="dash-sezione social-anteprima">
    <header className="dash-testa">
      <h2 className="dash-linguetta">SocialOne</h2>
      <button className="dash-link" type="button" onClick={() => onNavigate('social')}>Apri il feed ›</button>
    </header>
    <div className="social-feed social-feed--anteprima">
      {caricamento ? <p className="season-empty">Carico il feed…</p>
        : post.length === 0 ? <p className="season-empty">Ancora nessun post: appena succede qualcosa nella lega, lo trovi qui.</p>
        : post.map((p) => <PostCard key={p.id} post={p} dati={dati} foto={foto} compatto onMiPiace={(id) => void mettiMiPiace(id)} />)}
    </div>
    <button className="dash-link social-anteprima__tutti" type="button" onClick={() => onNavigate('social')}>Vedi tutti i post ›</button>
  </section>
}
