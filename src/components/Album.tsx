import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { supabase } from '../lib/supabase'
import type { useSeasonData } from '../lib/useSeasonData'
import { urlFotoGiocatore } from '../lib/fotoGiocatore'
import { cognome } from '../lib/nomi'
import { macroRuolo, ruoloIt } from '../lib/ruoli'
import { Crest } from './Crest'
import { LogoSeason } from './LogoSeason'
import { FacciataPromo } from './BustinaPromo'
import { Carta, type Anagrafica, type Figurina, type Versione } from './CartaFut'

// Album delle figurine (docs/decisioni-conferenze-stampa.md §BetOne): una pagina per squadra, stemma + giocatori.
// Bustina da 250 crediti, 3 figurine; l'estrazione la fa il server (album_compra_bustina). Dalla Season 3 quattro
// versioni (docs/DIARIO-SEASON3.md §8): common (argento), rare (oro), ultrarara (oro olografico), ultimate
// (iridescente); stemmi e conference solo ultimate. Doppioni riciclabili, pagina completa = 200 crediti.

type Dati = ReturnType<typeof useSeasonData>
type Possesso = { figurina_id: number; normali: number; rare: number; ultra: number; ultimate: number }
type Uscita = { figurina_id: number; tipo: Figurina['tipo']; versione?: Versione; ultra: boolean; nuova: boolean }
type RigaClassifica = { team_id: number; attaccate: number; totale: number; ultra: number; pagine: number }
type Voce = { figurina_id: number; versione: Versione }
// impegnate: copie gia' dentro altri scambi in attesa (non si possono riproporre ne' riciclare)
type Doppione = Voce & { copie: number; impegnate?: number }
type VoceSalvata = { figurina_id: number; versione?: Versione; ultra?: boolean }
type ScambioFig = { id: number; da_team_id: number; a_team_id: number; offerte: VoceSalvata[]; richieste: VoceSalvata[]; stato: string; scade_il: string; da_user: string }

const PREZZO = 250
// Quello che serve alla card FUT: foto, bandiera e le sei statistiche (anche quelle da portiere).
const COLONNE_GIOCATORE = 'id, nome, posizioni, foto_url, foto_figurina, nazionalita, pace:attributi->pace, shooting:attributi->shooting, passing:attributi->passing, dribbling_generale:attributi->dribbling_generale, defending:attributi->defending, physic:attributi->physic, gk_diving:attributi->gk_diving, gk_handling:attributi->gk_handling, gk_kicking:attributi->gk_kicking, gk_reflexes:attributi->gk_reflexes, goalkeeping_speed:attributi->goalkeeping_speed, gk_positioning:attributi->gk_positioning'
// Ordine di pregio, nome e valore al riciclo di ogni versione (stessi crediti di album_ricicla_doppioni).
const VERSIONI: Versione[] = ['ultimate', 'ultra', 'rare', 'common']
const NOME_VERSIONE: Record<Versione, string> = { common: 'Common', rare: 'Rara', ultra: 'Ultrarara', ultimate: 'Ultimate' }
const RICICLO: Record<Versione, number> = { common: 10, rare: 25, ultra: 50, ultimate: 150 }
const copie = (p: Possesso | undefined, v: Versione) => !p ? 0 : v === 'rare' ? p.rare : v === 'ultra' ? p.ultra : v === 'ultimate' ? p.ultimate : p.normali
const totale = (p: Possesso | undefined) => !p ? 0 : p.normali + p.rare + p.ultra + p.ultimate
// Le voci degli scambi fatti prima delle rarita' hanno {ultra} al posto di {versione}.
const voce = (x: VoceSalvata): Voce => ({ figurina_id: x.figurina_id, versione: x.versione ?? (x.ultra ? 'ultra' : 'common') })
const speciale = (v: Versione | undefined) => v === 'ultra' || v === 'ultimate'
const ridotto = () => typeof window !== 'undefined' && window.matchMedia?.('(prefers-reduced-motion: reduce)').matches
const fmt = (n: number) => new Intl.NumberFormat('it-IT').format(n)

// ---------- La figurina di prima ----------
// Resta negli album delle stagioni cominciate prima delle rarita' (leagues.album_nuovo_dalla_stagione): solo normale e
// ultrarara. Cornice argento (oro olografico per le ultrarare), voto nello scudo, foto, targhetta col nome, stemma e numero.
function CartaClassica({ f, ana, dati, ultra, vuota, numero, piccola }: { f: Figurina; ana?: Anagrafica; dati: Dati; ultra: boolean; vuota?: boolean; numero?: number; piccola?: boolean }) {
  const team = f.team_id != null ? dati.teamById.get(f.team_id) : undefined
  const crestUrl = f.team_id != null ? dati.crestUrlByTeamId.get(f.team_id) : undefined
  const ruoloMacro = macroRuolo(ana?.posizioni ?? []).toLowerCase()
  const classe = `fig${ultra ? ' fig--ultra' : ''}${piccola ? ' fig--piccola' : ''} fig--${f.tipo}${f.tipo === 'giocatore' ? ` fig--${ruoloMacro}` : ''}`
  if (vuota) return <div className="fig fig--vuota" aria-label={`Figurina ${numero ?? ''} mancante`}><span className="fig__numero">{numero}</span></div>
  const extra = <>
    <span className="fig__lucido" aria-hidden="true" />
    {ultra && <><span className="fig__olo" aria-hidden="true" /><span className="fig__scintille" aria-hidden="true"><i /><i /><i /><i /><i /></span></>}
    {numero != null && <span className="fig__num" aria-hidden="true">{numero}</span>}
  </>
  if (f.tipo === 'conferenza') {
    const est = f.conferenza === 'est'
    return <div className={classe} aria-label={`Figurina ultrarara ${est ? 'Eastern' : 'Western'} Conference`}>
      <div className="fig__dentro">
        <div className="fig__raggi" aria-hidden="true" />
        <div className="fig__conf"><img src={est ? '/loghi-conferenza/east.svg' : '/loghi-conferenza/west.svg'} alt="" /></div>
        <div className="fig__targa"><strong>{est ? 'EASTERN' : 'WESTERN'}</strong><small>Conference</small></div>
      </div>
      {extra}
    </div>
  }
  if (f.tipo === 'stemma') {
    return <div className={classe} aria-label={`Stemma ${team?.nome ?? ''}`}>
      <div className="fig__dentro">
        <div className="fig__raggi" aria-hidden="true" />
        <div className="fig__stemma"><Crest value={team?.stemma_url ?? null} imageUrl={crestUrl} size="large" eager /></div>
        <div className="fig__targa"><strong>{team?.nome ?? '—'}</strong><small>Stemma ufficiale</small></div>
      </div>
      {extra}
    </div>
  }
  const foto = urlFotoGiocatore(ana?.foto_url)
  return <div className={classe} aria-label={`${ana?.nome ?? 'Giocatore'}${ultra ? ', ultrarara' : ''}`}>
    <div className="fig__dentro">
      <div className="fig__raggi" aria-hidden="true" />
      <div className="fig__scudo"><b>{f.overall ?? ''}</b><span>{ruoloIt(ana?.posizioni?.[0] ?? '')}</span></div>
      <div className="fig__club"><Crest value={team?.stemma_url ?? null} imageUrl={crestUrl} size="small" /></div>
      <div className="fig__foto">{foto ? <img src={foto} alt="" loading="lazy" /> : <span>👤</span>}</div>
      <div className="fig__targa"><strong>{ana ? cognome(ana.nome) : '—'}</strong><small>{team?.nome ?? ''}</small></div>
      {f.aggiornamento && <em className="fig__agg">AGG.</em>}
    </div>
    {extra}
  </div>
}

// ---------- La bustina: 3D, si inclina col dito e si apre strappando la linea in alto ----------
function suonoStrappo(forte: boolean) {
  try {
    const ctx = new (window.AudioContext ?? (window as unknown as { webkitAudioContext: typeof AudioContext }).webkitAudioContext)()
    const durata = forte ? 0.35 : 0.06
    const buf = ctx.createBuffer(1, Math.floor(ctx.sampleRate * durata), ctx.sampleRate)
    const d = buf.getChannelData(0)
    for (let i = 0; i < d.length; i++) d[i] = (Math.random() * 2 - 1) * (1 - i / d.length) * (forte ? 0.6 : 0.25)
    const src = ctx.createBufferSource(); src.buffer = buf
    const filtro = ctx.createBiquadFilter(); filtro.type = 'highpass'; filtro.frequency.value = forte ? 900 : 2400
    src.connect(filtro).connect(ctx.destination); src.start()
    window.setTimeout(() => void ctx.close(), 600)
  } catch { /* audio non disponibile */ }
}

// iOS chiede il permesso per il giroscopio, e solo dentro un tocco: si chiede al tasto che compra la bustina.
function chiediGiroscopio() {
  try {
    const D = window.DeviceOrientationEvent as unknown as { requestPermission?: () => Promise<string> } | undefined
    void D?.requestPermission?.().catch(() => undefined)
  } catch { /* niente giroscopio */ }
}

// La bustina v4 (plastica, logo SEASON) arriva con l'album della stagione nuova: gli album aperti prima di questa
// data tengono la bustina di prima fino a fine stagione (decisione del committente, 7/11/2026).
const BUSTINA_V4_DAL = Date.parse('2026-11-07T12:00:00Z')

// I premiati della stagione prima (capocannoniere, assistman, miglior portiere) sulla bustina v4, al posto dell'emblema.
type Premiato = { premio: 'marcatore' | 'assistman' | 'portiere'; nome: string; foto?: string }

async function caricaPremiati(leagueId: number, stagione: number): Promise<Premiato[]> {
  const { data: prima } = await supabase.from('seasons').select('id').eq('league_id', leagueId).eq('numero', stagione - 1).maybeSingle()
  if (!prima) return []
  const { data } = await supabase.rpc('premi_individuali_lega', { p_league_id: leagueId })
  const righe = ((data ?? []) as Array<{ season_id: number; premio: Premiato['premio']; ambito?: string; nome: string; player_instance_id: number }>)
    .filter((r) => r.season_id === (prima as { id: number }).id && (r.ambito ?? 'totale') === 'totale')
  if (righe.length === 0) return []
  const { data: ist } = await supabase.from('player_instances').select('id, players(foto_figurina, foto_url)').in('id', righe.map((r) => r.player_instance_id))
  const foto = new Map(((ist ?? []) as unknown as Array<{ id: number; players: { foto_figurina: string | null; foto_url: string | null } | null }>)
    .map((x) => [x.id, x.players?.foto_figurina ?? x.players?.foto_url ?? null]))
  return righe.map((r) => ({ premio: r.premio, nome: r.nome, foto: urlFotoGiocatore(foto.get(r.player_instance_id)) }))
}

export function Bustina({ stagione, nuova, premiati = [], onAperta }: { stagione: number; nuova: boolean; premiati?: Premiato[]; onAperta: () => void }) {
  const ref = useRef<HTMLDivElement>(null)
  const [tilt, setTilt] = useState({ x: 0, y: 0, lx: 50, ly: 30 })
  const [strappo, setStrappo] = useState(0)
  const [aperta, setAperta] = useState(false)
  const trascina = useRef<{ attivo: boolean; ultimoSuono: number }>({ attivo: false, ultimoSuono: 0 })
  const dito = useRef(false)
  const promo = nuova && premiati.filter((p) => p.foto).length === 3
  // Sul telefono la bustina si inclina col giroscopio, come tenerla in mano: i riflessi della plastica scorrono.
  // La posizione di partenza e' quella in cui la si tiene quando compare; il dito ha la precedenza.
  useEffect(() => {
    if (!nuova || aperta || ridotto()) return
    let zero: { b: number; g: number } | null = null
    const gira = (e: DeviceOrientationEvent) => {
      if (dito.current || e.beta == null || e.gamma == null) return
      zero ??= { b: e.beta, g: e.gamma }
      const px = Math.min(1, Math.max(0, 0.5 + (e.gamma - zero.g) / 50))
      const py = Math.min(1, Math.max(0, 0.3 + (e.beta - zero.b) / 50))
      setTilt({ x: (0.5 - py) * 18, y: (px - 0.5) * 24, lx: px * 100, ly: py * 100 })
    }
    window.addEventListener('deviceorientation', gira)
    return () => window.removeEventListener('deviceorientation', gira)
  }, [aperta, nuova])

  function posizione(e: React.PointerEvent) {
    const r = ref.current!.getBoundingClientRect()
    return { px: (e.clientX - r.left) / r.width, py: (e.clientY - r.top) / r.height }
  }
  function giu(e: React.PointerEvent) {
    if (aperta) return
    dito.current = true
    // Lo strappo puo' partire anche da fuori, a sinistra della bustina, all'altezza della saldatura in alto.
    const { px, py } = posizione(e)
    if (py > -0.12 && py < 0.3 && px < 0.6) { trascina.current.attivo = true; (e.currentTarget as Element).setPointerCapture?.(e.pointerId) }
  }
  function muovi(e: React.PointerEvent) {
    if (aperta) return
    const { px, py } = posizione(e)
    const dentro = px >= 0 && px <= 1 && py >= 0 && py <= 1
    if (dentro || trascina.current.attivo) setTilt({ x: (0.5 - Math.min(1, Math.max(0, py))) * 18, y: (Math.min(1, Math.max(0, px)) - 0.5) * 24, lx: px * 100, ly: py * 100 })
    if (trascina.current.attivo) {
      const p = Math.max(strappo, Math.min(1, px))
      if (p > strappo) {
        setStrappo(p)
        const ora = performance.now()
        if (ora - trascina.current.ultimoSuono > 70) { suonoStrappo(false); trascina.current.ultimoSuono = ora }
        if (p >= 0.92) {
          trascina.current.attivo = false
          setStrappo(1); setAperta(true); suonoStrappo(true)
          try { navigator.vibrate?.(40) } catch { /* niente vibrazione */ }
          window.setTimeout(onAperta, ridotto() ? 0 : 700)
        }
      }
    }
  }
  function su() { trascina.current.attivo = false; dito.current = false; if (!aperta) setTilt((t) => ({ ...t, x: 0, y: 0 })) }

  return <div className={`pack-scena${aperta ? ' is-aperta' : ''}`}
    onPointerDown={giu} onPointerMove={muovi} onPointerUp={su} onPointerCancel={su}>
    <div ref={ref} className={`pk${nuova ? ' pk--v4' : ''}${promo ? ' pk--promo' : ''}`} style={{ transform: `rotateX(${tilt.x}deg) rotateY(${tilt.y}deg)`, ['--lx' as string]: `${tilt.lx}%`, ['--ly' as string]: `${tilt.ly}%` }}>
      {/* Saldatura in alto: e' la parte che si strappa */}
      <div className="pk__sald pk__sald--su">
        <span className="pk__righe" aria-hidden="true" />
        <span className="pk__taglio" aria-hidden="true"><i style={{ width: `${strappo * 100}%` }} /></span>
      </div>
      {/* Corpo: grafica ordinata in colonna, con curvatura e riflessi sopra */}
      <div className="pk__corpo">
        {promo ? <FacciataPromo premiati={premiati} stagione={stagione} /> : <>
        <div className="pk__arte" aria-hidden="true" />
        <div className="pk__contenuto">
          <p className="pk__sopra">Figurine ufficiali</p>
          <div className="pk__emblema"><img src="/specialone-mark.svg" alt="" /></div>
          <p className="pk__marchio"><b>SPECIAL</b><span>ONE</span></p>
          {nuova ? <LogoSeason n={stagione} className="pk__season" /> : <p className="pk__stagione">Stagione {stagione}</p>}
        </div>
        </>}
        <div className="pk__bollino" aria-hidden="true"><b>3</b><small>figurine</small></div>
        <div className="pk__curva" aria-hidden="true" />
        {/* Plastica: riflesso che segue l'inclinazione, grinze del foglio, pieghe delle saldature, lampo periodico */}
        <div className="pk__luce" aria-hidden="true" />
        {nuova && <>
          <div className="pk__riflesso" aria-hidden="true" />
          <div className="pk__grinze" aria-hidden="true" />
          <div className="pk__pieghe" aria-hidden="true" />
          <div className="pk__lampo" aria-hidden="true" />
        </>}
      </div>
      <div className="pk__sald pk__sald--giu">
        <span className="pk__righe" aria-hidden="true" />
      </div>
    </div>
    {!aperta && <p className="pack-aiuto"><span className="pack-aiuto__dito" aria-hidden="true">👆</span>Scorri il dito sulla linea in alto per aprire</p>}
    {!aperta && <button type="button" className="pack-salta" onClick={() => { setStrappo(1); setAperta(true); suonoStrappo(true); window.setTimeout(onAperta, ridotto() ? 0 : 500) }}>Apri subito</button>}
  </div>
}

type Props = { leagueId: number; teamId: number; dati: Dati; conferenze: boolean }

export function Album({ leagueId, teamId, dati, conferenze }: Props) {
  const [stagione, setStagione] = useState<number | null>(null)
  // Archivio: gli album delle stagioni passate restano sfogliabili, in sola lettura (richiesta del 7/11/2026).
  // null = album della stagione in corso.
  const [vedi, setVedi] = useState<number | null>(null)
  const [passate, setPassate] = useState<number[]>([])
  // Prima stagione con le figurine nuove (rarita', card FUT): gli album precedenti restano come erano.
  const [nuovaDal, setNuovaDal] = useState(1)
  const [bustinaNuova, setBustinaNuova] = useState(false)
  const [premiati, setPremiati] = useState<Premiato[]>([])
  const [crediti, setCrediti] = useState(0)
  const [gratis, setGratis] = useState(0)
  const [figurine, setFigurine] = useState<Figurina[]>([])
  const [possesso, setPossesso] = useState<Map<number, Possesso>>(new Map())
  const [ana, setAna] = useState<Map<number, Anagrafica>>(new Map())
  const [errore, setErrore] = useState('')
  const [pagina, setPagina] = useState<number | 'conf' | 'agg' | null>(null)
  const [busta, setBusta] = useState<Uscita[] | null>(null)
  const [scoperte, setScoperte] = useState<Set<number>>(new Set())
  const [strappo, setStrappo] = useState(false)
  const [compro, setCompro] = useState(false)
  const [avviso, setAvviso] = useState('')
  const [classifica, setClassifica] = useState<RigaClassifica[]>([])
  const scheda = useRef<HTMLDivElement>(null)
  // Scambi di figurine (solo doppioni, almeno una per parte, 24 ore).
  const [vista, setVista] = useState<'album' | 'scambi'>('album')
  const [scambi, setScambi] = useState<ScambioFig[]>([])
  const [controparte, setControparte] = useState<number | null>(null)
  const [miei, setMiei] = useState<Doppione[]>([])
  const [suoi, setSuoi] = useState<Doppione[]>([])
  // Dei miei doppioni, quelli che all'altro giocatore mancano del tutto (per sapere cosa gli interessa davvero).
  const [glimancano, setGlimancano] = useState<Set<number>>(new Set())
  const [offro, setOffro] = useState<Voce[]>([])
  const [chiedo, setChiedo] = useState<Voce[]>([])
  const [contro, setContro] = useState<number | null>(null)
  const [lavoro, setLavoro] = useState(false)

  const carica = useCallback(async () => {
    const { data: a, error } = await supabase.rpc('album_apri', { p_league_id: leagueId })
    if (error) { setErrore(error.message); return }
    const st = (a as { stagione: number; crediti: number }).stagione
    setStagione(st); setCrediti((a as { crediti: number }).crediti)
    const { data: cs } = await supabase.rpc('casino_stato', { p_league_id: leagueId })
    setGratis(Number((cs as { bustine_gratis?: number } | null)?.bustine_gratis ?? 0))
    const { data: lg } = await supabase.from('leagues').select('album_nuovo_dalla_stagione').eq('id', leagueId).maybeSingle()
    setNuovaDal(Number((lg as { album_nuovo_dalla_stagione?: number } | null)?.album_nuovo_dalla_stagione ?? 1))
    // Le stagioni precedenti che hanno un album (conteggio senza scaricare le figurine).
    const conteggi = await Promise.all(Array.from({ length: Math.max(0, st - 1) }, (_, i) => i + 1).map(async (n) => {
      const { count } = await supabase.from('album_figurine').select('id', { count: 'exact', head: true }).eq('league_id', leagueId).eq('stagione', n)
      return (count ?? 0) > 0 ? n : null
    }))
    setPassate(conteggi.filter((n): n is number => n != null).sort((a, b) => b - a))
    const [{ data: f }, { data: p }, { data: cl }] = await Promise.all([
      supabase.from('album_figurine').select('id, tipo, team_id, player_id, conferenza, overall, aggiornamento, statistiche, posizioni').eq('league_id', leagueId).eq('stagione', vedi ?? st).order('id'),
      supabase.from('album_possesso').select('figurina_id, normali, rare, ultra, ultimate').eq('league_id', leagueId),
      supabase.rpc('album_classifica', { p_league_id: leagueId }),
    ])
    const figs = (f ?? []) as Figurina[]
    setFigurine(figs)
    // L'album della stagione in corso e' nato dopo l'arrivo della bustina v4?
    const { data: primo } = await supabase.from('album_figurine').select('creata_il').eq('league_id', leagueId).eq('stagione', st).order('id').limit(1).maybeSingle()
    const v4 = primo != null && Date.parse((primo as { creata_il: string }).creata_il) >= BUSTINA_V4_DAL
    setBustinaNuova(v4)
    if (v4) void caricaPremiati(leagueId, st).then(setPremiati).catch(() => setPremiati([]))
    setPossesso(new Map(((p ?? []) as Possesso[]).map((x) => [x.figurina_id, x])))
    setClassifica((cl ?? []) as RigaClassifica[])
    const { data: sc } = await supabase.from('album_scambi').select('id, da_team_id, a_team_id, offerte, richieste, stato, scade_il, da_user').eq('league_id', leagueId).eq('stato', 'in_attesa').order('id', { ascending: false })
    setScambi(((sc ?? []) as ScambioFig[]).filter((x) => new Date(x.scade_il).getTime() > Date.now()))
    const { data: md } = await supabase.rpc('album_doppioni', { p_league_id: leagueId, p_team_id: teamId })
    setMiei((md ?? []) as Doppione[])
    const ids = [...new Set(figs.filter((x) => x.player_id != null).map((x) => x.player_id as number))]
    const mappa = new Map<number, Anagrafica>()
    for (let i = 0; i < ids.length; i += 300) {
      const { data: g } = await supabase.from('players').select(COLONNE_GIOCATORE).in('id', ids.slice(i, i + 300))
      for (const x of (g ?? []) as Anagrafica[]) mappa.set(x.id, x)
    }
    setAna(mappa)
  }, [leagueId, teamId, vedi])
  useEffect(() => { void carica() }, [carica])
  useEffect(() => {
    if (controparte == null) { setSuoi([]); setGlimancano(new Set()); return }
    void supabase.rpc('album_doppioni', { p_league_id: leagueId, p_team_id: controparte }).then(({ data }) => setSuoi((data ?? []) as Doppione[]))
    void supabase.rpc('album_mancano_a', { p_league_id: leagueId, p_team_id: controparte })
      .then(({ data }) => setGlimancano(new Set(((data ?? []) as Array<{ figurina_id: number }>).map((r) => r.figurina_id))))
  }, [controparte, leagueId, scambi])

  const perSquadra = useMemo(() => {
    const m = new Map<number, Figurina[]>()
    // Le figurine "AGG." (giocatori arrivati dopo l'apertura dell'album) stanno nella pagina Aggiornamenti, fuori dal conteggio.
    for (const f of figurine) if (f.team_id != null && !f.aggiornamento) m.set(f.team_id, [...(m.get(f.team_id) ?? []), f])
    for (const [k, v] of m) m.set(k, v.sort((a, b) => (a.tipo === 'stemma' ? -1 : b.tipo === 'stemma' ? 1 : 0) || (b.overall ?? 0) - (a.overall ?? 0) || a.id - b.id))
    return m
  }, [figurine])
  const agg = useMemo(() => figurine.filter((f) => f.aggiornamento).sort((a, b) => (dati.teamById.get(a.team_id ?? 0)?.nome ?? '').localeCompare(dati.teamById.get(b.team_id ?? 0)?.nome ?? '') || (b.overall ?? 0) - (a.overall ?? 0) || a.id - b.id), [figurine, dati.teamById])
  const squadre = useMemo(() => [...perSquadra.keys()].sort((a, b) => (dati.teamById.get(a)?.nome ?? '').localeCompare(dati.teamById.get(b)?.nome ?? '')), [perSquadra, dati.teamById])
  const numeri = useMemo(() => { const m = new Map<number, number>(); let n = 1; for (const t of squadre) for (const f of perSquadra.get(t) ?? []) m.set(f.id, n++); for (const f of figurine.filter((x) => x.tipo === 'conferenza')) m.set(f.id, n++); for (const f of agg) m.set(f.id, n++); return m }, [squadre, perSquadra, figurine, agg])
  const conf = figurine.filter((f) => f.tipo === 'conferenza')
  // Figurina di esempio per far vedere com'e' un'ultimate: il giocatore con l'overall piu' alto dell'album.
  const esempioUltra = useMemo(() => figurine.filter((f) => f.tipo === 'giocatore').sort((a, b) => (b.overall ?? 0) - (a.overall ?? 0))[0], [figurine])

  const archivio = vedi != null
  const mostrata = vedi ?? stagione
  const classica = mostrata != null && mostrata < nuovaDal
  // La figurina giusta per l'album: quella di prima o la card FUT con la sua versione.
  const carta = (p: { f: Figurina; ana?: Anagrafica; versione: Versione; vuota?: boolean; numero?: number; piccola?: boolean }) => classica
    ? <CartaClassica {...p} dati={dati} ultra={speciale(p.versione) || p.f.tipo === 'conferenza'} />
    : <Carta {...p} dati={dati} />
  const ce = (id: number) => totale(possesso.get(id)) > 0
  // Nella pagina si vede la versione migliore che possiedi.
  const migliore = (id: number): Versione => VERSIONI.find((v) => copie(possesso.get(id), v) > 0) ?? 'common'
  const base = figurine.filter((f) => f.tipo !== 'conferenza' && !f.aggiornamento)
  const attaccate = base.filter((f) => ce(f.id)).length
  const ultraTot = figurine.filter((f) => copie(possesso.get(f.id), 'ultra') > 0).length
  const ultimateTot = figurine.filter((f) => copie(possesso.get(f.id), 'ultimate') > 0).length
  // Si riciclano solo i doppioni non impegnati in uno scambio in attesa.
  const doppioni = miei.reduce((s, d) => s + Math.max(0, d.copie - (d.impegnate ?? 0)), 0)
  const valoreDoppioni = miei.reduce((s, d) => s + Math.max(0, d.copie - (d.impegnate ?? 0)) * RICICLO[d.versione], 0)

  async function compra(conGratis = false) {
    if (compro) return
    setCompro(true); setErrore(''); setAvviso('')
    if (bustinaNuova) chiediGiroscopio()
    const { data, error } = await supabase.rpc('album_compra_bustina', { p_league_id: leagueId, p_gratis: conGratis })
    setCompro(false)
    if (error) { setErrore(error.message); return }
    const r = data as { figurine: Uscita[]; premi: Array<{ pagina?: number; album?: boolean }>; crediti: number; bustine_gratis?: number }
    setCrediti(r.crediti)
    if (r.bustine_gratis != null) setGratis(r.bustine_gratis)
    setScoperte(new Set()); setStrappo(false); setBusta(r.figurine)
    const premi = r.premi.map((p) => p.album ? '📒 Album completato!' : `Pagina di ${dati.teamById.get(p.pagina ?? 0)?.nome ?? 'una squadra'} completa: +200 crediti`)
    if (premi.length) setAvviso(premi.join(' · '))
    void carica()
  }

  function scopri(i: number, versione: Versione) {
    setScoperte((prev) => {
      if (prev.has(i)) return prev
      if (speciale(versione)) { try { navigator.vibrate?.([30, 40, 60]) } catch { /* niente */ } }
      const n = new Set(prev); n.add(i); return n
    })
  }

  const chiave = (v: Voce) => `${v.figurina_id}:${v.versione}`
  const alterna = (lista: Voce[], set: (v: Voce[]) => void, v: Voce) => set(lista.some((x) => chiave(x) === chiave(v)) ? lista.filter((x) => chiave(x) !== chiave(v)) : [...lista, v])
  async function proponi() {
    if (controparte == null) return
    setLavoro(true); setErrore(''); setAvviso('')
    const { error } = await supabase.rpc('album_proponi_scambio', { p_league_id: leagueId, p_a_team_id: controparte, p_offerte: offro, p_richieste: chiedo, p_controproposta_di: contro })
    setLavoro(false)
    if (error) { setErrore(error.message); return }
    setAvviso('Proposta inviata: l\'altro ha 24 ore per rispondere.')
    setOffro([]); setChiedo([]); setContro(null); setControparte(null)
    void carica()
  }
  async function rispondi(id: number, accetta: boolean) {
    setLavoro(true); setErrore(''); setAvviso('')
    const { error } = await supabase.rpc('album_rispondi_scambio', { p_id: id, p_accetta: accetta })
    setLavoro(false)
    if (error) { setErrore(error.message); return }
    setAvviso(accetta ? 'Scambio fatto: le figurine sono nel tuo album.' : 'Proposta rifiutata.')
    void carica()
  }
  async function ritira(id: number) {
    const { error } = await supabase.rpc('album_ritira_scambio', { p_id: id })
    if (error) { setErrore(error.message); return }
    void carica()
  }
  function controproposta(sc: ScambioFig) {
    setContro(sc.id); setControparte(sc.da_team_id)
    setOffro(sc.richieste.map(voce)); setChiedo(sc.offerte.map(voce))
    window.requestAnimationFrame(() => document.querySelector('.alb-sc-componi')?.scrollIntoView({ behavior: 'smooth', block: 'start' }))
  }
  const fig = (id: number) => figurine.find((x) => x.id === id)
  // Figurine ancora libere di un doppione: nella controproposta lo scambio originale si chiude, quindi le sue figurine non contano come impegnate.
  const originale = contro != null ? scambi.find((x) => x.id === contro) : undefined
  const libere = (d: Doppione, dellOriginale: VoceSalvata[] | undefined) =>
    d.copie - Math.max(0, (d.impegnate ?? 0) - (dellOriginale?.map(voce).filter((x) => chiave(x) === chiave(d)).length ?? 0))
  const miniCarta = (salvata: VoceSalvata, scelta?: boolean, onClick?: () => void, nota?: string) => {
    const v = voce(salvata)
    const f = fig(v.figurina_id)
    if (!f) return null
    return <button key={chiave(v)} type="button" className={`alb-sc-mini${scelta ? ' is-scelta' : ''}${nota === 'in scambio' ? ' is-impegnata' : ''}`} onClick={onClick} disabled={!onClick} aria-pressed={scelta}>
      {carta({ f, ana: f.player_id != null ? ana.get(f.player_id) : undefined, versione: v.versione, piccola: true })}
      {nota && <em>{nota}</em>}
      {scelta && <i aria-hidden="true">✓</i>}
    </button>
  }

  async function ricicla() {
    const { data, error } = await supabase.rpc('album_ricicla_doppioni', { p_league_id: leagueId })
    if (error) { setErrore(error.message); return }
    const r = data as { riciclati: number; crediti_guadagnati: number; crediti?: number }
    if (r.crediti != null) setCrediti(r.crediti)
    setAvviso(r.riciclati ? `Riciclati ${r.riciclati} doppioni: +${fmt(r.crediti_guadagnati)} crediti` : 'Nessun doppione da riciclare.')
    void carica()
  }

  if (errore && stagione == null) return <section className="alb-vuoto"><p role="alert">{errore}</p></section>
  if (stagione == null) return <section className="alb-vuoto"><p>Apro l'album…</p></section>

  const figPagina = pagina === 'conf' ? conf : pagina === 'agg' ? agg : pagina != null ? perSquadra.get(pagina) ?? [] : []
  const completaPagina = (t: number) => (perSquadra.get(t) ?? []).every((f) => ce(f.id))

  const sfoglia = (n: number | null) => { setVedi(n === stagione ? null : n); setPagina(null); setVista('album'); setAvviso(''); setErrore('') }

  return <section className="alb">
    {passate.length > 0 && <nav className="alb-scaffale" aria-label="I tuoi album">
      {[stagione, ...passate].map((n) => <button key={n} type="button" className={`alb-scaffale__album${(mostrata === n) ? ' is-aperto' : ''}${n === stagione ? ' is-corrente' : ''}`}
        aria-pressed={mostrata === n} onClick={() => sfoglia(n)}>
        <span className="alb-scaffale__copertina" aria-hidden="true"><span>ALBUM</span><b>{n}</b></span>
        <small>{n === stagione ? 'In corso' : `Season ${n}`}</small>
      </button>)}
    </nav>}

    <div className={`alb-testa${archivio ? ' alb-testa--archivio' : ''}`}>
      <div className="alb-testa__copertina" aria-hidden="true"><span>ALBUM</span><b>{mostrata}</b></div>
      <div className="alb-testa__dati">
        <small>{archivio ? `Archivio · Stagione ${mostrata}` : `Stagione ${stagione}`}</small>
        <strong>{attaccate}<span>/{base.length}</span></strong>
        <div className="alb-barra" aria-label={`Completamento ${Math.round(attaccate * 100 / Math.max(1, base.length))}%`}><i style={{ width: `${(attaccate * 100) / Math.max(1, base.length)}%` }} /></div>
        <p>{classica ? '' : `${ultimateTot} ultimate · `}{ultraTot} ultrarare{archivio ? '' : ` · ${fmt(crediti)} crediti`}</p>
      </div>
    </div>
    {archivio && <p className="alb-archivio-nota">Album chiuso: si sfoglia e basta. Bustine e scambi valgono solo per l'album della stagione in corso. <button type="button" onClick={() => sfoglia(null)}>Torna all'album di oggi ›</button></p>}

    {!archivio && <>
    <div className="alb-azioni">
      {gratis > 0
        ? <button type="button" className="alb-compra alb-compra--gratis" disabled={compro} onClick={() => void compra(true)}>
          <span className="alb-compra__busta" aria-hidden="true" />
          <span><b>{compro ? 'Apro…' : 'Apri una bustina gratis'}</b><small>🎁 {gratis} {gratis === 1 ? 'bustina vinta' : 'bustine vinte'} al casinò</small></span>
        </button>
        : <button type="button" className="alb-compra" disabled={compro || crediti < PREZZO} onClick={() => void compra()}>
          <span className="alb-compra__busta" aria-hidden="true" />
          <span><b>{compro ? 'Apro…' : 'Compra una bustina'}</b><small>{PREZZO} crediti · 3 figurine</small></span>
        </button>}
      <button type="button" className="alb-ricicla" disabled={doppioni === 0} onClick={() => void ricicla()}>
        <b>{doppioni}</b><small>doppioni</small><em>{doppioni ? `+${fmt(valoreDoppioni)}` : 'ricicla'}</em>
      </button>
    </div>
    {crediti < PREZZO && <p className="bet-nota">Servono {PREZZO} crediti: si vincono con le schedine e al casinò, e ogni giorno alle 22:10 ne arrivano 1.000.</p>}
    </>}
    {(avviso || errore) && <p className={errore ? 'alb-errore' : 'alb-avviso'} role="status">{errore || avviso}</p>}

    {!archivio && <div className="alb-viste" role="tablist">
      <button type="button" role="tab" aria-selected={vista === 'album'} className={vista === 'album' ? 'is-attiva' : ''} onClick={() => setVista('album')}>Le pagine</button>
      <button type="button" role="tab" aria-selected={vista === 'scambi'} className={vista === 'scambi' ? 'is-attiva' : ''} onClick={() => setVista('scambi')}>Scambi{scambi.some((x) => x.a_team_id === teamId) ? <b>{scambi.filter((x) => x.a_team_id === teamId).length}</b> : null}</button>
    </div>}

    {vista === 'scambi' ? <section className="alb-sc">
      {scambi.filter((x) => x.a_team_id === teamId).length > 0 && <div className="alb-sc-blocco"><h3>Proposte ricevute</h3>
        {scambi.filter((x) => x.a_team_id === teamId).map((sc) => <article key={sc.id} className="alb-sc-card">
          <header><Crest value={dati.teamById.get(sc.da_team_id)?.stemma_url ?? null} imageUrl={dati.crestUrlByTeamId.get(sc.da_team_id)} size="small" /><strong>{dati.teamById.get(sc.da_team_id)?.nome}</strong><small>scade {new Intl.DateTimeFormat('it-IT', { weekday: 'short', hour: '2-digit', minute: '2-digit', timeZone: 'Europe/Rome' }).format(new Date(sc.scade_il))}</small></header>
          <div className="alb-sc-lato"><small>Ti dà</small><div>{sc.offerte.map((v) => miniCarta(v, false, undefined, ce(v.figurina_id) ? undefined : 'ti manca'))}</div></div>
          <div className="alb-sc-lato"><small>Ti chiede</small><div>{sc.richieste.map((v) => miniCarta(v))}</div></div>
          <footer>
            <button type="button" className="button button--secondary" disabled={lavoro} onClick={() => void rispondi(sc.id, false)}>Rifiuta</button>
            <button type="button" className="button button--secondary" disabled={lavoro} onClick={() => controproposta(sc)}>Controproposta</button>
            <button type="button" className="alb-compra alb-compra--piccola" disabled={lavoro} onClick={() => void rispondi(sc.id, true)}><span><b>Accetta</b></span></button>
          </footer>
        </article>)}
      </div>}
      {scambi.filter((x) => x.da_team_id === teamId).length > 0 && <div className="alb-sc-blocco"><h3>Proposte inviate</h3>
        {scambi.filter((x) => x.da_team_id === teamId).map((sc) => <article key={sc.id} className="alb-sc-card">
          <header><Crest value={dati.teamById.get(sc.a_team_id)?.stemma_url ?? null} imageUrl={dati.crestUrlByTeamId.get(sc.a_team_id)} size="small" /><strong>A {dati.teamById.get(sc.a_team_id)?.nome}</strong><small>in attesa</small></header>
          <div className="alb-sc-lato"><small>Dai</small><div>{sc.offerte.map((v) => miniCarta(v))}</div></div>
          <div className="alb-sc-lato"><small>Chiedi</small><div>{sc.richieste.map((v) => miniCarta(v))}</div></div>
          <footer><button type="button" className="button button--secondary" onClick={() => void ritira(sc.id)}>Ritira</button></footer>
        </article>)}
      </div>}

      <div className="alb-sc-blocco alb-sc-componi"><h3>{contro ? 'Controproposta' : 'Nuovo scambio'}</h3>
        <p className="bet-nota">Si scambiano solo i doppioni, almeno una figurina per parte. La proposta vale 24 ore. Una figurina dentro uno scambio in attesa è bloccata finché non viene accettato, rifiutato o ritirato.</p>
        <div className="alb-sc-squadre">
          {dati.teams.filter((t) => t.id !== teamId && t.attiva !== false && t.user_id && !t.controllata_da_pc).map((t) => <button key={t.id} type="button" className={controparte === t.id ? 'is-scelta' : ''} title={t.nome} aria-label={t.nome}
            onClick={() => { setControparte(t.id); setChiedo([]); setContro(null) }}>
            <Crest value={t.stemma_url ?? null} imageUrl={dati.crestUrlByTeamId.get(t.id)} size="small" />
          </button>)}
        </div>
        {controparte != null && <>
          <h4>Chiedi a {dati.teamById.get(controparte)?.nome} <span>i suoi doppioni</span></h4>
          {suoi.length === 0 ? <p className="bet-nota">Non ha doppioni da scambiare.</p> : <div className="alb-sc-griglia">
            {[...suoi].sort((a, b) => Number(libere(a, originale?.offerte) <= 0) - Number(libere(b, originale?.offerte) <= 0) || Number(ce(a.figurina_id)) - Number(ce(b.figurina_id))).map((d) => libere(d, originale?.offerte) <= 0
              ? miniCarta(d, false, undefined, 'in scambio')
              : miniCarta(d, chiedo.some((x) => chiave(x) === chiave(d)), () => alterna(chiedo, setChiedo, { figurina_id: d.figurina_id, versione: d.versione }), ce(d.figurina_id) ? undefined : 'ti manca'))}
          </div>}
          <h4>Offri <span>i tuoi doppioni</span></h4>
          {miei.length === 0 ? <p className="bet-nota">Non hai doppioni da scambiare.</p> : <div className="alb-sc-griglia">
            {[...miei].sort((a, b) => Number(libere(a, originale?.richieste) <= 0) - Number(libere(b, originale?.richieste) <= 0) || Number(glimancano.has(b.figurina_id)) - Number(glimancano.has(a.figurina_id))).map((d) => libere(d, originale?.richieste) <= 0
              ? miniCarta(d, false, undefined, 'in scambio')
              : miniCarta(d, offro.some((x) => chiave(x) === chiave(d)), () => alterna(offro, setOffro, { figurina_id: d.figurina_id, versione: d.versione }), glimancano.has(d.figurina_id) ? 'gli manca' : undefined))}
          </div>}
          <button type="button" className="alb-compra" disabled={lavoro || offro.length === 0 || chiedo.length === 0} onClick={() => void proponi()}>
            <span><b>{lavoro ? 'Invio…' : contro ? 'Invia la controproposta' : 'Proponi lo scambio'}</b><small>dai {offro.length} · ricevi {chiedo.length}</small></span>
          </button>
          {(offro.length === 0) !== (chiedo.length === 0) && <p className="bet-nota">{offro.length === 0 ? 'Scegli anche cosa offri.' : 'Scegli anche cosa chiedi.'}</p>}
        </>}
      </div>
    </section> : <>

    {pagina == null && esempioUltra && !archivio && <section className="alb-esempio" aria-label={`Esempio di figurina ${classica ? 'ultrarara' : 'ultimate'}`}>
      <div className="alb-esempio__carta">
        {carta({ f: esempioUltra, ana: esempioUltra.player_id != null ? ana.get(esempioUltra.player_id) : undefined, versione: classica ? 'ultra' : 'ultimate', numero: numeri.get(esempioUltra.id) })}
        <em>Esempio</em>
      </div>
      {classica ? <div className="alb-esempio__testo">
        <p className="alb-esempio__kicker">✦ Ultrarara</p>
        <h3>La figurina più ambita</h3>
        <p>Esce circa una volta ogni 50 figurine: cornice d'oro, riflesso olografico arcobaleno e scintille. Si attacca sopra la versione normale.{conferenze ? ' In questa lega ci sono anche le due figurine delle Conference, solo ultrarare.' : ''} Dall'album della prossima stagione arrivano le figurine nuove in quattro rarità.</p>
      </div> : <div className="alb-esempio__testo">
        <p className="alb-esempio__kicker">✦ Quattro rarità</p>
        <h3>Common, Rara, Ultrarara, Ultimate</h3>
        <p>Ogni giocatore ha la versione <b>Common</b> (argento); da 70 di overall anche la <b>Rara</b> (oro), da 78 l'<b>Ultrarara</b> (oro olografico) e da 83 l'<b>Ultimate</b> (iridescente), che esce circa una figurina su cento. Gli stemmi{conferenze ? ' e le due Conference' : ''} esistono solo Ultimate. Per completare l'album basta una versione qualsiasi; nella pagina vedi la più preziosa che hai.</p>
      </div>}
    </section>}

    {pagina == null ? <>
      <h2 className="alb-titolo">Le pagine</h2>
      <ul className="alb-indice">
        {squadre.map((t) => {
          const figs = perSquadra.get(t) ?? []
          const n = figs.filter((f) => ce(f.id)).length
          const team = dati.teamById.get(t)
          return <li key={t}>
            <button type="button" className={`${completaPagina(t) ? 'is-completa' : ''}${t === teamId ? ' is-mia' : ''}`} onClick={() => { setPagina(t); window.requestAnimationFrame(() => scheda.current?.scrollIntoView({ behavior: 'smooth', block: 'start' })) }}>
              <span className="alb-indice__stemma"><Crest value={team?.stemma_url ?? null} imageUrl={dati.crestUrlByTeamId.get(t)} size="small" /></span>
              <span className="alb-indice__nome"><strong>{team?.nome ?? '—'}</strong><small>{n}/{figs.length}</small></span>
              <span className="alb-indice__barra" aria-hidden="true"><i style={{ width: `${(n * 100) / Math.max(1, figs.length)}%` }} /></span>
              {completaPagina(t) && <em aria-label="Pagina completa">✓</em>}
            </button>
          </li>
        })}
        {conferenze && conf.length > 0 && <li>
          <button type="button" className="alb-indice__conf" onClick={() => setPagina('conf')}>
            <span className="alb-indice__stemma">✨</span>
            <span className="alb-indice__nome"><strong>Conference</strong><small>{conf.filter((f) => ce(f.id)).length}/{conf.length} {classica ? 'ultrarare' : 'ultimate'}</small></span>
          </button>
        </li>}
        {agg.length > 0 && <li>
          <button type="button" className="alb-indice__conf alb-indice__agg" onClick={() => { setPagina('agg'); window.requestAnimationFrame(() => scheda.current?.scrollIntoView({ behavior: 'smooth', block: 'start' })) }}>
            <span className="alb-indice__stemma">🆕</span>
            <span className="alb-indice__nome"><strong>Aggiornamenti</strong><small>{agg.filter((f) => ce(f.id)).length}/{agg.length} · extra</small></span>
          </button>
        </li>}
      </ul>
    </> : <div ref={scheda} className="alb-pagina">
      <div className="alb-pagina__testa">
        <button type="button" className="alb-indietro" onClick={() => setPagina(null)}>‹ Pagine</button>
        <strong>{pagina === 'conf' ? 'Conference' : pagina === 'agg' ? 'Aggiornamenti' : dati.teamById.get(pagina)?.nome}</strong>
        <span>{figPagina.filter((f) => ce(f.id)).length}/{figPagina.length}</span>
      </div>
      {pagina === 'agg' && <p className="bet-nota">Giocatori arrivati nelle rose dopo l'apertura dell'album. Si collezionano e si scambiano come le altre, ma non contano per il completamento, le pagine e la classifica.</p>}
      <ul className="alb-griglia">
        {figPagina.map((f) => <li key={f.id}>
          {carta({ f, ana: f.player_id != null ? ana.get(f.player_id) : undefined, versione: migliore(f.id), vuota: !ce(f.id), numero: numeri.get(f.id) })}
          {totale(possesso.get(f.id)) > 1 && <span className="alb-doppio">×{totale(possesso.get(f.id))}</span>}
        </li>)}
      </ul>
    </div>}

    </>}

    {!archivio && <section className="alb-classifica">
      <h2>Collezionisti</h2>
      {classifica.length === 0 ? <p className="bet-nota">Ancora nessuno ha aperto una bustina.</p> : <ol>
        {classifica.map((r, i) => {
          const t = dati.teamById.get(r.team_id)
          return <li key={r.team_id} className={r.team_id === teamId ? 'is-mia' : ''}>
            <span className={`bet-pos${i < 3 ? ` bet-pos--${i + 1}` : ''}`}>{i + 1}</span>
            <span className="bet-giocatori__stemma"><Crest value={t?.stemma_url ?? null} imageUrl={dati.crestUrlByTeamId.get(r.team_id)} size="small" /></span>
            <span className="bet-classifica__nome"><strong>{t?.nome ?? '—'}</strong><small>{r.ultra} ultrarare e ultimate · {r.pagine} pagine complete</small></span>
            <span className="slot-classifica__crediti"><b>{Math.round((r.attaccate * 100) / Math.max(1, r.totale))}%</b><small>{r.attaccate}/{r.totale}</small></span>
          </li>
        })}
      </ol>}
    </section>}

    {busta && <div className="alb-apertura" role="dialog" aria-modal="true" aria-label="Apertura della bustina">
      <button type="button" className="alb-chiudi" aria-label="Chiudi" onClick={() => setBusta(null)}>✕</button>
      {!strappo ? <Bustina stagione={stagione} nuova={bustinaNuova} premiati={premiati} onAperta={() => setStrappo(true)} /> : <>
        <div className="alb-carte">
          {busta.map((u, i) => {
            const f = figurine.find((x) => x.id === u.figurina_id) ?? { id: u.figurina_id, tipo: u.tipo, team_id: null, player_id: null, conferenza: null, overall: null, aggiornamento: false } as Figurina
            const girata = scoperte.has(i)
            const ver: Versione = u.versione ?? (u.ultra ? 'ultra' : 'common')
            return <button key={i} type="button" className={`alb-carta${girata ? ' is-girata' : ''}${speciale(ver) ? ' is-ultra' : ''}${ver !== 'common' ? ` is-${ver}` : ''}`} style={{ ['--i' as string]: i }}
              onClick={() => scopri(i, ver)} aria-label={girata ? 'Figurina scoperta' : 'Tocca per scoprire'}>
              <span className="alb-carta__retro" aria-hidden="true"><img src="/specialone-mark.svg" alt="" /><i /></span>
              <span className="alb-carta__fronte">
                {carta({ f, ana: f.player_id != null ? ana.get(f.player_id) : undefined, versione: ver, numero: numeri.get(f.id) })}
                {girata && speciale(ver) && <span className="alb-carta__boom" aria-hidden="true" />}
                {/* Dentro il fronte (gia' girato di 180 gradi): cosi' la scritta si legge dritta */}
                {girata && <em className={`alb-carta__etichetta${speciale(ver) ? ` is-ultra is-${ver}` : ver === 'rare' ? ' is-rare' : u.nuova ? ' is-nuova' : ''}`}>{ver === 'ultimate' ? '✦ ULTIMATE ✦' : ver === 'ultra' ? '✦ ULTRARARA ✦' : ver === 'rare' ? `RARA${u.nuova ? ' · NUOVA' : ''}` : u.nuova ? 'NUOVA' : 'DOPPIONE'}</em>}
              </span>
            </button>
          })}
        </div>
        <div className="alb-apertura__azioni">
          {scoperte.size < busta.length ? <button type="button" className="button button--secondary" onClick={() => busta.forEach((u, i) => scopri(i, u.versione ?? (u.ultra ? 'ultra' : 'common')))}>Scopri tutte</button>
            : <>
              <button type="button" className="button button--secondary" onClick={() => setBusta(null)}>Chiudi</button>
              {gratis > 0
                ? <button type="button" className="alb-compra alb-compra--piccola alb-compra--gratis" disabled={compro} onClick={() => void compra(true)}><span><b>Un'altra</b><small>🎁 gratis ({gratis})</small></span></button>
                : <button type="button" className="alb-compra alb-compra--piccola" disabled={compro || crediti < PREZZO} onClick={() => void compra()}><span><b>Un'altra</b><small>{PREZZO} crediti</small></span></button>}
            </>}
        </div>
      </>}
    </div>}
  </section>
}

// Nell'anteprima (anche senza login) i premiati della Season 2 della Serie F, dalle foto pubbliche delle figurine.
const PREMIATI_ANTEPRIMA: Premiato[] = [
  { premio: 'marcatore', nome: 'O. Diakité', foto: urlFotoGiocatore('cutout/6174.webp') },
  { premio: 'assistman', nome: 'M. Carrizo', foto: urlFotoGiocatore('cutout/6076.webp') },
  { premio: 'portiere', nome: 'David Raya', foto: urlFotoGiocatore('cutout/4384.webp') },
]

// Anteprima della bustina senza comprarla (?anteprima=bustina): si strappa e ricomincia, non scrive niente.
export function AnteprimaBustina() {
  const [giro, setGiro] = useState(0)
  return <div className="alb-apertura" onPointerDown={chiediGiroscopio}>
    <Bustina key={giro} stagione={3} nuova premiati={PREMIATI_ANTEPRIMA} onAperta={() => window.setTimeout(() => setGiro((g) => g + 1), 900)} />
  </div>
}
