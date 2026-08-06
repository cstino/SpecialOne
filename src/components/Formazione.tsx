import { useEffect, useState, type CSSProperties, type MouseEvent as ReactMouseEvent } from 'react'
import { supabase } from '../lib/supabase'
import { cognome } from '../lib/nomi'
import { ROSA_MASSIMA } from '../lib/league'
import type { League, Membership } from '../types'
import { GameNav } from './GameNav'
import { SchedaGiocatore } from './SchedaGiocatore'
import type { GameView } from './GameNav'

// Tetti fissi di rosa in campo (design.md §6): 11 titolari sempre, panchina
// fino a 9. La tribuna non ha un tetto suo — e' semplicemente "il resto
// della rosa" — ma per gli slot vuoti serve comunque un numero: quello
// raggiunto quando la rosa e' al massimo (30) e la panchina e' piena.
const PANCHINA_MAX = 9
const TRIBUNA_MAX = ROSA_MASSIMA - 11 - PANCHINA_MAX

const MODULI: Record<string, string[]> = {
  '4-3-3': ['GK', 'LB', 'CB', 'CB', 'RB', 'CM', 'CM', 'CM', 'LW', 'ST', 'RW'],
  '4-3-3 offensivo': ['GK', 'LB', 'CB', 'CB', 'RB', 'CM', 'CM', 'CAM', 'LW', 'ST', 'RW'],
  '4-3-3 difensivo': ['GK', 'LB', 'CB', 'CB', 'RB', 'CM', 'CM', 'CDM', 'LW', 'ST', 'RW'],
  '4-4-2': ['GK', 'LB', 'CB', 'CB', 'RB', 'LM', 'CM', 'CM', 'RM', 'ST', 'ST'],
  '4-2-3-1': ['GK', 'LB', 'CB', 'CB', 'RB', 'CDM', 'CDM', 'CAM', 'LW', 'RW', 'ST'],
  '3-5-2': ['GK', 'CB', 'CB', 'CB', 'LWB', 'CM', 'CM', 'CM', 'RWB', 'ST', 'ST'],
  '3-4-3': ['GK', 'CB', 'CB', 'CB', 'LM', 'CM', 'CM', 'RM', 'LW', 'ST', 'RW'],
  '5-3-2': ['GK', 'LB', 'CB', 'CB', 'CB', 'RB', 'CM', 'CM', 'CM', 'ST', 'ST'],
  '4-2-4': ['GK', 'LB', 'CB', 'CB', 'RB', 'CM', 'CM', 'LW', 'ST', 'ST', 'RW'],
}

const MODULO_DESCRIZIONI: Record<string, string> = {
  '4-3-3': '4 dif · 3 cen · 3 att',
  '4-3-3 offensivo': '4 dif · 2 cen + CAM · 3 att',
  '4-3-3 difensivo': '4 dif · 2 cen + CDM · 3 att',
  '4-4-2': '4 dif · 4 cen · 2 att',
  '4-2-3-1': '4 dif · 2 med · 3 treq · 1 att',
  '3-5-2': '3 dif · 5 cen · 2 att',
  '3-4-3': '3 dif · 4 cen · 3 att',
  '5-3-2': '5 dif · 3 cen · 2 att',
  '4-2-4': '4 dif · 2 cen · 4 att',
}

// Le stesse 7 chiavi di engine/config.js STILI e private.stili_validi() lato DB
// (sync a mano, stesso pattern gia' in uso per MODULI/moduli_validi()).
const STILI: string[] = ['equilibrato', 'contropiede', 'possesso_palla', 'fasce', 'recupero_veloce', 'diretto', 'blocco_basso']

const STILE_LABEL: Record<string, string> = {
  equilibrato: 'EQUILIBRATO',
  contropiede: 'CONTROPIEDE',
  possesso_palla: 'POSSESSO PALLA',
  fasce: 'GIOCO SULLE FASCE',
  recupero_veloce: 'RECUPERO VELOCE',
  diretto: 'GIOCO DIRETTO',
  blocco_basso: 'DIFESA A OLTRANZA',
}

const STILE_DESCRIZIONI: Record<string, string> = {
  equilibrato: 'Nessun aggiustamento tattico.',
  contropiede: 'Difensivo e attendista, sfrutta le occasioni in ripartenza.',
  possesso_palla: 'Dominio del centrocampo e del possesso.',
  fasce: 'Veloce sulle corsie, cross e ampiezza.',
  recupero_veloce: 'Difesa alta e pressing per riconquistare la palla.',
  diretto: 'Verticale, salta il centrocampo, punta sulla profondità.',
  blocco_basso: 'Massima solidità difensiva, rischia il minimo indispensabile.',
}

type PlayerStats = Record<string, number | null>
type Player = { id: number; fc_id: number; nome: string; club: string; nazionalita: string | null; overall_corrente: number; eta_corrente: number; posizioni: string[]; piede: string | null; altezza: number | null; condizione: number; infortunato_fino_a: number; ritiro_annunciato: boolean; attributi: PlayerStats; foto_url: string | null }
type SavedLineup = { modulo: string; stile_gioco: string; titolari: number[]; panchina: number[]; tribuna: number[]; salvata_il: string }

const formatSalvataIl = (iso: string) => new Intl.DateTimeFormat('it-IT', {
  timeZone: 'Europe/Rome', day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit',
}).format(new Date(iso)).replace(',', ' alle')

type FormazioneProps = { membership: Membership; onNavigate: (view: GameView) => void }
type PlayerZone = 'starter' | 'bench' | 'tribuna'
type PlayerLocation = { zone: PlayerZone; index: number; id: number }
type PlayerAction = { player: Player; location: PlayerLocation; x: number; y: number }

type PlayerPortraitProps = {
  player?: Player
  imageUrl?: string
  position: string
  selected?: boolean
  onClick: (event: ReactMouseEvent<HTMLButtonElement>) => void
  compact?: boolean
  empty?: boolean
}

type PositionFit = 'natural' | 'adapted' | 'out'

function reparto(slot: string) {
  if (slot === 'GK') return 'GK'
  if (['CB', 'LB', 'RB', 'LWB', 'RWB'].includes(slot)) return 'DEF'
  if (['CDM', 'CM', 'CAM', 'LM', 'RM'].includes(slot)) return 'MID'
  return 'ATT'
}

const REPARTO_ORDINE: Record<string, number> = { GK: 0, DEF: 1, MID: 2, ATT: 3 }
const POSIZIONI_CONFINANTI: Record<string, string[]> = {
  LB: ['LWB', 'LM'], LWB: ['LB', 'LM', 'LW'], LM: ['LB', 'LWB', 'LW'], LW: ['LWB', 'LM'],
  RB: ['RWB', 'RM'], RWB: ['RB', 'RM', 'RW'], RM: ['RB', 'RWB', 'RW'], RW: ['RWB', 'RM'],
  CB: ['CDM'], CDM: ['CB'], CAM: ['CF'], CF: ['CAM', 'ST'], ST: ['CF'],
}

function positionFit(slot: string, preferred: string[]): PositionFit {
  if (preferred.includes(slot)) return 'natural'
  if (preferred.some((position) => reparto(position) === reparto(slot))) return 'adapted'
  if (preferred.some((position) => POSIZIONI_CONFINANTI[slot]?.includes(position) || POSIZIONI_CONFINANTI[position]?.includes(slot))) return 'adapted'
  return 'out'
}

// Stessa formula del motore per l'overall efficace nello slot assegnato
// (engine/config.js penalitaRuolo + engine/engine.js ovrEfficace) — solo la
// parte di posizionamento, non condizione/infortuni (che hanno gia' un
// indicatore proprio su ogni maglietta). Non e' un'approssimazione: sono
// gli stessi moltiplicatori con cui il motore decide davvero la partita.
const ADIACENTI_REPARTO: Record<string, string[]> = { DEF: ['MID'], MID: ['DEF', 'ATT'], ATT: ['MID'] }
function overallEfficacePosizione(player: Player, slot: string): number {
  const repSlot = reparto(slot)
  const repNat = reparto(player.posizioni[0] ?? slot)
  if (repSlot === 'GK' && repNat !== 'GK') return Math.min(45, player.overall_corrente * 0.45)
  if (repSlot !== 'GK' && repNat === 'GK') return Math.min(48, player.overall_corrente * 0.50)
  if (repSlot === 'GK' && repNat === 'GK') return player.overall_corrente
  if (player.posizioni[0] === slot) return player.overall_corrente
  if (player.posizioni.includes(slot)) return player.overall_corrente * 0.98
  if (repNat === repSlot) return player.overall_corrente * 0.91
  if (ADIACENTI_REPARTO[repNat]?.includes(repSlot)) return player.overall_corrente * 0.80
  return player.overall_corrente * 0.65
}

// La soglia di cambio del motore e' 55: sotto quel valore il giocatore viene
// sostituito da solo, quindi e' li' che l'avviso deve diventare rosso.
function livelloEnergia(player: Player) {
  if (player.infortunato_fino_a > 0) return 'infortunato'
  if (player.condizione < 55) return 'scarica'
  if (player.condizione < 75) return 'media'
  return 'piena'
}

function AnonymousPlayer() {
  return <span className="anonymous-player" aria-hidden="true"><svg viewBox="0 0 100 110" focusable="false"><circle cx="50" cy="33" r="22" /><path d="M12 108c2-31 16-48 38-48s36 17 38 48H12Z" /></svg></span>
}

function PlayerPortrait({ player, imageUrl, position, selected = false, onClick, compact = false, empty = false }: PlayerPortraitProps) {
  // Slot libero (panchina/tribuna non ancora al tetto): un riquadro
  // grigio/trasparente con un "+", non la sagoma anonima del giocatore
  // ne' overall/ruolo, che qui non hanno senso.
  if (empty) {
    return <button className="lineup-player lineup-player--compact lineup-player--empty" type="button" onClick={onClick} aria-label="Slot libero: tocca per assegnare un giocatore">
      <span className="lineup-player__portrait lineup-player__portrait--empty"><span className="lineup-player__plus" aria-hidden="true">+</span></span>
      <span className="lineup-player__plate"><strong>Slot libero</strong></span>
    </button>
  }
  const fit = player ? positionFit(position, player.posizioni) : 'natural'
  return <button className={`lineup-player ${compact ? 'lineup-player--compact' : ''} ${selected ? 'is-selected' : ''}`} type="button" onClick={onClick} aria-label={`${player?.nome ?? 'Slot vuoto'}, ${position}, overall ${player?.overall_corrente ?? 'non disponibile'}`}>
    <span className={`lineup-player__portrait lineup-player__portrait--${reparto(position)} ${imageUrl ? 'has-photo' : ''}`}>
      <AnonymousPlayer />
      {imageUrl && <img src={imageUrl} alt="" onError={(event) => { event.currentTarget.hidden = true; event.currentTarget.parentElement?.classList.remove('has-photo') }} />}
      {player && <span className={`energia energia--${livelloEnergia(player)}`} title={player.infortunato_fino_a > 0 ? `Infortunato: salta ancora ${player.infortunato_fino_a} ${player.infortunato_fino_a === 1 ? 'giornata' : 'giornate'}` : `Energia ${player.condizione}%`}>
        {player.infortunato_fino_a > 0 ? '✚' : `${player.condizione}%`}
      </span>}
      {fit !== 'natural' && <i className={`position-warning position-warning--${fit}`} title={fit === 'adapted' ? 'Giocatore adattato in un ruolo vicino' : 'Giocatore completamente fuori posizione'} aria-label={fit === 'adapted' ? 'Fuori posizione di poco' : 'Completamente fuori posizione'}>!</i>}
    </span>
    <span className="lineup-player__plate">
      <strong>{player ? cognome(player.nome) : 'Seleziona'}</strong>
      <span className="lineup-player__meta">
        <span className={`lineup-player__position lineup-player__position--${reparto(position)}`}>{position}</span>
        <b>{player?.overall_corrente ?? '—'}</b>
      </span>
    </span>
  </button>
}

export function Formazione({ membership, onNavigate }: FormazioneProps) {
  const league = membership.league as League
  const [players, setPlayers] = useState<Player[]>([])
  const [imageUrls, setImageUrls] = useState<Record<number, string>>({})
  const [modulo, setModulo] = useState('4-3-3')
  const [moduleMenuOpen, setModuleMenuOpen] = useState(false)
  const [stile, setStile] = useState('equilibrato')
  const [stileMenuOpen, setStileMenuOpen] = useState(false)
  const [salvataIl, setSalvataIl] = useState<string | null>(null)
  const [titolari, setTitolari] = useState<number[]>([])
  const [panchina, setPanchina] = useState<number[]>([])
  const [tribuna, setTribuna] = useState<number[]>([])
  const [selected, setSelected] = useState<PlayerLocation | null>(null)
  const [openZone, setOpenZone] = useState<PlayerZone>('starter')
  const [detailPlayer, setDetailPlayer] = useState<Player | null>(null)
  const [playerAction, setPlayerAction] = useState<PlayerAction | null>(null)
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [saved, setSaved] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [giornata, setGiornata] = useState(1)

  // La scheda giocatore gestisce da se' Escape e blocco dello scorrimento:
  // qui resta solo la mini-card delle azioni.
  useEffect(() => {
    if (!playerAction) return
    const chiudiConEsc = (event: KeyboardEvent) => { if (event.key === 'Escape') setPlayerAction(null) }
    document.addEventListener('keydown', chiudiConEsc)
    return () => { document.removeEventListener('keydown', chiudiConEsc) }
  }, [playerAction])

  useEffect(() => {
    let active = true
    async function load() {
      const { data: instances, error: rosterError } = await supabase
        .from('player_instances')
        .select('id, overall_corrente, eta_corrente, condizione, infortunato_fino_a, ritiro_annunciato, player_id')
        .eq('league_id', league.id)
        .eq('team_id', membership.id)
        .order('overall_corrente', { ascending: false })
      if (rosterError) { setError(rosterError.message); setLoading(false); return }
      const roster = instances ?? []
      const { data: catalog, error: playerError } = await supabase
        .from('players').select('id, fc_id, nome, club, nazionalita, posizioni, piede, altezza, attributi, foto_url').in('id', roster.map((item) => item.player_id))
      if (playerError) { setError(playerError.message); setLoading(false); return }
      const catalogById = new Map((catalog ?? []).map((player) => [player.id, player]))
      const loaded = roster.map((item) => ({ ...item, fc_id: catalogById.get(item.player_id)?.fc_id, nome: catalogById.get(item.player_id)?.nome ?? `Giocatore ${item.player_id}`, club: catalogById.get(item.player_id)?.club ?? '—', nazionalita: catalogById.get(item.player_id)?.nazionalita ?? null, posizioni: catalogById.get(item.player_id)?.posizioni ?? [], piede: catalogById.get(item.player_id)?.piede ?? null, altezza: catalogById.get(item.player_id)?.altezza ?? null, attributi: catalogById.get(item.player_id)?.attributi ?? {}, foto_url: catalogById.get(item.player_id)?.foto_url ?? null })) as Player[]
      if (!active) return
      setPlayers(loaded)
      const signed = await Promise.all(loaded.filter((player) => player.foto_url).map(async (player) => {
        if (player.foto_url?.startsWith('http')) return [player.id, player.foto_url] as const
        const { data } = await supabase.storage.from('player-photos').createSignedUrl(player.foto_url!, 3600)
        return [player.id, data?.signedUrl] as const
      }))
      if (active) setImageUrls(Object.fromEntries(signed.filter((item): item is [number, string] => Boolean(item[1]))))
      const { data: nextFixture, error: fixtureError } = await supabase.from('fixtures').select('giornata')
        .eq('league_id', league.id).in('stato', ['programmata', 'in_corso']).order('giornata').limit(1).maybeSingle()
      if (fixtureError) { setError(fixtureError.message); setLoading(false); return }
      const targetGiornata = nextFixture?.giornata ?? league.giornate_totali
      if (active) setGiornata(targetGiornata)
      const { data: lineup, error: lineupError } = await supabase.from('lineups')
        .select('modulo, stile_gioco, titolari, panchina, tribuna, salvata_il')
        .eq('league_id', league.id)
        .eq('team_id', membership.id)
        .lte('giornata', targetGiornata)
        .order('automatica', { ascending: true })
        .order('giornata', { ascending: false })
        .limit(1)
        .maybeSingle()
      if (lineupError) { setError(lineupError.message); setLoading(false); return }
      if (lineup) {
        const current = lineup as SavedLineup
        // La distinta salvata e' una fotografia della rosa al momento del
        // salvataggio. Dopo un'asta o uno scambio puo' mancare un nuovo
        // acquisto (o restare l'id di un ceduto): la riallineiamo alla rosa
        // corrente senza toccare titolari e panchina gia' scelti.
        const idsRosa = new Set(loaded.map((player) => player.id))
        const titolariSalvati = current.titolari.filter((id) => idsRosa.has(id))
        const panchinaSalvata = current.panchina.filter((id) => idsRosa.has(id))
        const tribunaSalvata = current.tribuna.filter((id) => idsRosa.has(id))
        const giaInDistinta = new Set([...titolariSalvati, ...panchinaSalvata, ...tribunaSalvata])
        const nuoviArrivi = loaded.filter((player) => !giaInDistinta.has(player.id)).map((player) => player.id)
        setModulo(current.modulo)
        setStile(current.stile_gioco)
        setSalvataIl(current.salvata_il)
        setTitolari(titolariSalvati)
        setPanchina(panchinaSalvata)
        setTribuna([...tribunaSalvata, ...nuoviArrivi])
      } else {
        const keeper = loaded.find((player) => player.posizioni[0] === 'GK') ?? loaded[0]
        const starters = [keeper, ...loaded.filter((player) => player.id !== keeper?.id).slice(0, 10)].map((player) => player.id)
        const bench = loaded.filter((player) => !starters.includes(player.id)).slice(0, PANCHINA_MAX).map((player) => player.id)
        setTitolari(starters); setPanchina(bench); setTribuna(loaded.filter((player) => !starters.includes(player.id) && !bench.includes(player.id)).map((player) => player.id))
      }
      setLoading(false)
    }
    void load()
    return () => { active = false }
  }, [league.id, membership.id])

  const slots = MODULI[modulo]
  const rowGroups = modulo === '4-2-3-1'
    ? [['GK'], ['LB', 'CB', 'RB'], ['CDM'], ['LW', 'CAM', 'RW'], ['ST']]
    : modulo === '4-3-3'
      ? [['GK'], ['LB', 'CB', 'RB'], ['CM'], ['LW', 'ST', 'RW']]
      : modulo === '4-4-2'
        ? [['GK'], ['LB', 'CB', 'RB'], ['LM', 'CM', 'RM'], ['ST']]
        : modulo === '3-4-3'
          ? [['GK'], ['CB'], ['LM', 'CM', 'RM'], ['LW', 'ST', 'RW']]
          : modulo === '3-5-2'
            ? [['GK'], ['CB'], ['LWB', 'CM', 'RWB'], ['ST']]
            : modulo === '5-3-2'
              ? [['GK'], ['LB', 'CB', 'RB'], ['CM'], ['ST']]
              : modulo === '4-2-4'
                // Senza questo caso il modulo cadeva nel gruppo generico
                // ['LW','RW','ST','CF'], che ordina RW prima di entrambi gli
                // ST: sul campo comparivano scambiati, con l'ala destra
                // stretta al centro invece che larga sulla fascia.
                ? [['GK'], ['LB', 'CB', 'RB'], ['CM'], ['LW', 'ST', 'RW']]
                : modulo === '4-3-3 offensivo' || modulo === '4-3-3 difensivo'
                  ? [['GK'], ['LB', 'CB', 'RB'], ['CM', 'CAM', 'CDM'], ['LW', 'ST', 'RW']]
                  : [['GK'], ['LB', 'CB', 'RB', 'LWB', 'RWB'], ['CDM', 'CM', 'CAM', 'LM', 'RM'], ['LW', 'RW', 'ST', 'CF']]
  const rows = rowGroups.map((group) => slots
    .map((slot, index) => ({ slot, index }))
    .filter((item) => group.includes(item.slot))
    .sort((left, right) => group.indexOf(left.slot) - group.indexOf(right.slot)))
    .reverse()
  // Il CAM/CDM delle varianti del 4-3-3 deve stare fra i due CM, non a un
  // lato: l'ordinamento per ruolo qui sopra non puo' separare due 'CM'
  // identici (indexOf collassa i duplicati), quindi si corregge a mano
  // l'unica riga coinvolta dopo il calcolo generico. Lo stesso indice viene
  // anche scostato leggermente in verticale (CSS, sotto) per leggerlo come
  // mediano/trequartista e non come un terzo centrale identico agli altri
  // due — ma SOLO per queste due varianti: il CDM/CAM del 4-2-3-1 sta gia'
  // su una riga propria e non va toccato.
  let scostamentoIndex: number | undefined
  let scostamentoDirezione: 'su' | 'giu' | undefined
  if (modulo === '4-3-3 offensivo' || modulo === '4-3-3 difensivo') {
    const specialSlot = modulo === '4-3-3 offensivo' ? 'CAM' : 'CDM'
    const midRow = rows.find((row) => row.some((item) => item.slot === specialSlot))
    if (midRow) {
      const cm = midRow.filter((item) => item.slot === 'CM')
      const special = midRow.find((item) => item.slot === specialSlot)
      if (cm.length === 2 && special) {
        midRow.splice(0, midRow.length, cm[0], special, cm[1])
        scostamentoIndex = special.index
        scostamentoDirezione = specialSlot === 'CAM' ? 'su' : 'giu'
      }
    }
  }
  // Overall medio dei titolari, nello slot in cui sono davvero schierati:
  // un giocatore fuori ruolo pesa meno, esattamente come nel motore —
  // altrimenti il cerchio direbbe "forte" anche con tre titolari fuori
  // posto, mentre l'avviso (!) su ognuno di loro racconta un'altra storia.
  const titolariConSlot = titolari
    .map((id, index) => ({ player: players.find((item) => item.id === id), slot: slots[index] }))
    .filter((item): item is { player: Player; slot: string } => Boolean(item.player))
  const overallTitolari = titolariConSlot.length
    ? Math.round(titolariConSlot.reduce((somma, item) => somma + overallEfficacePosizione(item.player, item.slot), 0) / titolariConSlot.length)
    : null

  const locations: Record<PlayerZone, PlayerLocation[]> = {
    starter: titolari.map((id, index) => ({ zone: 'starter', index, id })),
    bench: panchina.map((id, index) => ({ zone: 'bench', index, id })),
    tribuna: tribuna.map((id, index) => ({ zone: 'tribuna', index, id })),
  }
  const visibleLocations = [...locations[openZone]].sort((left, right) => {
    if (openZone === 'starter') return left.index - right.index
    const leftPlayer = players.find((player) => player.id === left.id)
    const rightPlayer = players.find((player) => player.id === right.id)
    const roleDifference = REPARTO_ORDINE[reparto(leftPlayer?.posizioni[0] ?? 'ATT')] - REPARTO_ORDINE[reparto(rightPlayer?.posizioni[0] ?? 'ATT')]
    if (roleDifference !== 0) return roleDifference
    const overallDifference = (rightPlayer?.overall_corrente ?? 0) - (leftPlayer?.overall_corrente ?? 0)
    if (overallDifference !== 0) return overallDifference
    return (leftPlayer?.nome ?? '').localeCompare(rightPlayer?.nome ?? '', 'it')
  })
  const selectedPlayer = selected ? players.find((player) => player.id === playerAt(selected)) : undefined

  function playerAt(location: PlayerLocation) {
    if (location.zone === 'starter') return titolari[location.index]
    if (location.zone === 'bench') return panchina[location.index]
    return tribuna[location.index]
  }

  function setPlayerAt(location: PlayerLocation, id: number) {
    if (location.zone === 'starter') setTitolari((current) => current.map((value, index) => index === location.index ? id : value))
    if (location.zone === 'bench') setPanchina((current) => current.map((value, index) => index === location.index ? id : value))
    if (location.zone === 'tribuna') setTribuna((current) => current.map((value, index) => index === location.index ? id : value))
  }

  function selectPlayer(location: PlayerLocation) {
    setSaved(false)
    if (!selected) {
      // Non cambiamo vista da soli: non e' detto che il sostituto stia nella
      // zona "opposta" (es. si puo' scambiare un titolare con un altro
      // titolare). Sceglie l'utente quale scheda aprire dopo aver armato
      // la sostituzione.
      setSelected(location)
      return
    }
    if (selected.zone === location.zone && selected.index === location.index) { setSelected(null); return }
    const firstId = playerAt(selected)
    const secondId = playerAt(location)
    const firstPlayer = players.find((player) => player.id === firstId)
    const secondPlayer = players.find((player) => player.id === secondId)

    // Se si sostituisce un titolare infortunato con una riserva sana,
    // l'infortunato va direttamente in tribuna e lascia libero il suo posto
    // in panchina: non deve servire un secondo scambio manuale.
    const injuredStarter = (firstPlayer?.infortunato_fino_a ?? 0) > 0 && selected.zone === 'starter'
      ? selected
      : (secondPlayer?.infortunato_fino_a ?? 0) > 0 && location.zone === 'starter'
        ? location
        : null
    const healthyBench = injuredStarter === selected && location.zone === 'bench'
      ? location
      : injuredStarter === location && selected.zone === 'bench'
        ? selected
        : null
    if (injuredStarter && healthyBench) {
      const injuredId = playerAt(injuredStarter)
      const replacementId = playerAt(healthyBench)
      const benchReplacement = tribuna
        .map((id, index) => ({ id, index, player: players.find((item) => item.id === id) }))
        .filter((item) => (item.player?.infortunato_fino_a ?? 0) === 0)
        .sort((left, right) => (right.player?.overall_corrente ?? 0) - (left.player?.overall_corrente ?? 0))[0]
      setTitolari((current) => current.map((value, index) => index === injuredStarter.index ? replacementId : value))
      setPanchina((current) => benchReplacement
        ? current.map((value, index) => index === healthyBench.index ? benchReplacement.id : value)
        : current.filter((_value, index) => index !== healthyBench.index))
      setTribuna((current) => benchReplacement
        ? current.map((value, index) => index === benchReplacement.index ? injuredId : value)
        : current.includes(injuredId) ? current : [...current, injuredId])
      setSelected(null)
      setError(null)
      return
    }

    const firstDestination = location.zone
    const secondDestination = selected.zone
    if (((firstPlayer?.infortunato_fino_a ?? 0) > 0 && firstDestination !== 'tribuna')
      || ((secondPlayer?.infortunato_fino_a ?? 0) > 0 && secondDestination !== 'tribuna')) {
      setError('Un giocatore infortunato può essere spostato soltanto in tribuna.')
      return
    }
    setPlayerAt(selected, secondId)
    setPlayerAt(location, firstId)
    setSelected(null)
    setError(null)
  }

  // Uno slot libero non ha nessuno con cui scambiare: chi era selezionato
  // si limita a spostarsi li', lasciando vuoto il suo posto di partenza
  // invece di riceverne uno in cambio.
  function selectEmptySlot(zone: 'bench' | 'tribuna') {
    if (!selected) return
    setSaved(false)
    if (selected.zone === 'starter') {
      setError('Uno slot libero non basta per liberare un titolare: scambialo con un giocatore di panchina o tribuna.')
      return
    }
    if (selected.zone === zone) { setSelected(null); return }
    const id = playerAt(selected)
    const player = players.find((item) => item.id === id)
    if ((player?.infortunato_fino_a ?? 0) > 0 && zone !== 'tribuna') {
      setError('Un giocatore infortunato può essere spostato soltanto in tribuna.')
      return
    }
    if (selected.zone === 'bench') setPanchina((current) => current.filter((_value, index) => index !== selected.index))
    else setTribuna((current) => current.filter((_value, index) => index !== selected.index))
    if (zone === 'bench') setPanchina((current) => [...current, id])
    else setTribuna((current) => [...current, id])
    setSelected(null)
    setError(null)
  }

  function handlePlayerClick(event: ReactMouseEvent<HTMLButtonElement>, location: PlayerLocation, player: Player | undefined) {
    if (selected) {
      setPlayerAction(null)
      selectPlayer(location)
      return
    }
    if (!player) return
    const rect = event.currentTarget.getBoundingClientRect()
    const menuWidth = 230
    const menuHeight = 138
    const x = Math.max(12, Math.min(rect.left + rect.width / 2 - menuWidth / 2, window.innerWidth - menuWidth - 12))
    const y = rect.bottom + menuHeight + 8 < window.innerHeight ? rect.bottom + 8 : Math.max(12, rect.top - menuHeight - 8)
    setPlayerAction({ player, location, x, y })
  }

  async function save() {
    setSaving(true); setSaved(false); setError(null)
    const cleanBench = panchina.filter((id) => !titolari.includes(id)).slice(0, PANCHINA_MAX)
    const indisponibili = [...titolari, ...cleanBench].filter((id) => (players.find((player) => player.id === id)?.infortunato_fino_a ?? 0) > 0)
    if (indisponibili.length) {
      setError('Sposta tutti i giocatori infortunati in tribuna prima di salvare.')
      setSaving(false)
      return
    }
    const { error: saveError } = await supabase.rpc('salva_formazione', {
      p_league_id: league.id, p_giornata: giornata, p_modulo: modulo,
      p_titolari: titolari, p_panchina: cleanBench, p_tribuna: tribuna,
      p_stile_gioco: stile,
    })
    if (saveError) setError(saveError.message)
    else { setPanchina(cleanBench); setSaved(true); setSalvataIl(new Date().toISOString()) }
    setSaving(false)
  }

  function chooseModule(nextModule: string) {
    setModulo(nextModule)
    setSaved(false)
    setSelected(null)
    setPlayerAction(null)
    setModuleMenuOpen(false)
  }

  function chooseStile(nextStile: string) {
    setStile(nextStile)
    setSaved(false)
    setStileMenuOpen(false)
  }

  if (loading) return <main className="loading-screen"><img className="loading-mark" src="/specialone-mark.svg" alt="" /><p>Preparo la formazione…</p></main>

  return (
    <main className="app-shell formation-shell">
      <GameNav league={league} active="squad" onNavigate={onNavigate} />
      <header className="topbar"><div className="brand-lockup brand-lockup--dark"><img src="/specialone-mark.svg" alt="" /><span>SpecialOne</span></div><span className="kicker">Giornata {giornata}</span></header>
      <section className="formation-hero"><p className="kicker">La tua distinta · {league.nome}</p><h1>Schiera la squadra.</h1><p>Scegli il modulo e assegna i giocatori slot per slot. Il server controlla rosa, indisponibilità e duplicati prima del salvataggio.</p></section>
      {error && <p className="notice notice--error" role="alert">{error}</p>}
      {players.length < 11 ? <section className="formation-panel"><h2>Rosa incompleta</h2><p>Servono almeno 11 giocatori prima di poter salvare una formazione.</p></section> : (
        <section className="formation-panel formation-panel--tactical">
          <div className="formation-toolbar">
            <div className="formation-save-row">
              <button className="formation-save-button button button--primary" type="button" disabled={saving} onClick={save}>{saving ? 'Salvo…' : 'Salva'}</button>
              {(saved || salvataIl) && <div className="formation-save-stato">
                {saved && <span>Formazione salvata</span>}
                {salvataIl && <small>Salvata il {formatSalvataIl(salvataIl)}</small>}
              </div>}
            </div>
            {overallTitolari !== null && <div className="formation-overall" title="Overall medio effettivo degli undici titolari, nello slot in cui sono schierati: chi è fuori ruolo pesa meno">
              <strong>{overallTitolari}</strong>
              <span>OVR titolari</span>
            </div>}
            <div className="formation-tattica">
              <div className="formation-tattica__voce formation-module-selector">
                <button className="formation-tattica__trigger" type="button" aria-haspopup="listbox" aria-expanded={moduleMenuOpen} onClick={() => { setModuleMenuOpen((open) => !open); setStileMenuOpen(false) }}>
                  <span className="formation-tattica__testo"><small>Modulo tattico</small><strong>{modulo}</strong></span>
                  <i aria-hidden="true">{moduleMenuOpen ? '×' : '⌄'}</i>
                </button>
                {moduleMenuOpen && <><button className="formation-module-scrim" type="button" aria-label="Chiudi selezione modulo" onClick={() => setModuleMenuOpen(false)} /><div className="formation-module-menu" role="listbox" aria-label="Scegli il modulo">{Object.keys(MODULI).map((name) => <button className={name === modulo ? 'is-active' : ''} type="button" role="option" aria-selected={name === modulo} key={name} onClick={() => chooseModule(name)}><strong>{name}</strong><small>{MODULO_DESCRIZIONI[name]}</small><span>{name === modulo ? '✓' : '›'}</span></button>)}</div></>}
              </div>
              <div className="formation-tattica__voce formation-stile-selector">
                <button className="formation-tattica__trigger" type="button" aria-haspopup="listbox" aria-expanded={stileMenuOpen} onClick={() => { setStileMenuOpen((open) => !open); setModuleMenuOpen(false) }}>
                  <span className="formation-tattica__testo"><small>Stile di gioco</small><strong>{STILE_LABEL[stile]}</strong></span>
                  <i aria-hidden="true">{stileMenuOpen ? '×' : '⌄'}</i>
                </button>
                {stileMenuOpen && <><button className="formation-stile-scrim" type="button" aria-label="Chiudi selezione stile di gioco" onClick={() => setStileMenuOpen(false)} /><div className="formation-stile-menu" role="listbox" aria-label="Scegli lo stile di gioco">{STILI.map((key) => <button className={key === stile ? 'is-active' : ''} type="button" role="option" aria-selected={key === stile} key={key} onClick={() => chooseStile(key)}><strong>{STILE_LABEL[key]}</strong><small>{STILE_DESCRIZIONI[key]}</small><span>{key === stile ? '✓' : '›'}</span></button>)}</div></>}
              </div>
            </div>
          </div>
          <div className="formation-zone-tabs" role="tablist" aria-label="Vista formazione">
            {([['starter', 'Titolari'], ['bench', 'Panchina'], ['tribuna', 'Tribuna']] as const).map(([zone, label]) => <button className={openZone === zone ? 'is-active' : ''} type="button" role="tab" aria-selected={openZone === zone} key={zone} onClick={() => setOpenZone(zone)}><span>{label}</span><b>{locations[zone].length}</b></button>)}
          </div>
          {selected && <p className="formation-swap-hint">Tocca il giocatore (o uno slot libero) con cui spostare {selectedPlayer?.nome ?? ''}.</p>}
          <div className="formation-view-card">
            {openZone === 'starter' ? (
              <div className="pitch-field" aria-label={`Campo con modulo ${modulo}`}>
                <div className="pitch-field__line pitch-field__line--half" />
                <div className="pitch-field__circle" />
                <div className="pitch-field__box pitch-field__box--top" /><div className="pitch-field__box pitch-field__box--bottom" />
                <div className="pitch-grid">
                  {rows.map((row, rowIndex) => <div className={`pitch-row pitch-row--${rowIndex}`} style={{ '--row-count': row.length } as CSSProperties} key={rowIndex}>{row.map(({ slot, index }) => { const player = players.find((item) => item.id === titolari[index]); const location = { zone: 'starter', index, id: titolari[index] ?? 0 } as PlayerLocation; return <div className={`pitch-slot pitch-slot--${reparto(slot)}${index === scostamentoIndex ? ` pitch-slot--scostato-${scostamentoDirezione}` : ''}`} key={`${slot}-${index}`}><PlayerPortrait player={player} imageUrl={imageUrls[player?.id ?? 0]} position={slot} selected={selected?.zone === 'starter' && selected.index === index} onClick={(event) => handlePlayerClick(event, location, player)} /></div> })}</div>)}
                </div>
              </div>
            ) : (
              <div className="formation-player-tray formation-player-tray--standalone" role="tabpanel">
                {visibleLocations.filter((location) => !(selected?.zone === location.zone && selected.index === location.index)).map((location) => {
                  const player = players.find((item) => item.id === location.id)
                  const position = player?.posizioni[0] ?? '—'
                  return <PlayerPortrait compact key={`${location.zone}-${location.index}-${location.id}`} player={player} imageUrl={imageUrls[location.id]} position={position} selected={selected?.zone === location.zone && selected.index === location.index} onClick={(event) => handlePlayerClick(event, location, player)} />
                })}
                {openZone === 'bench' && Array.from({ length: Math.max(0, PANCHINA_MAX - panchina.length) }).map((_, i) => (
                  <PlayerPortrait compact empty key={`bench-vuoto-${i}`} position="—" onClick={() => selectEmptySlot('bench')} />
                ))}
                {openZone === 'tribuna' && Array.from({ length: Math.max(0, TRIBUNA_MAX - tribuna.length) }).map((_, i) => (
                  <PlayerPortrait compact empty key={`tribuna-vuoto-${i}`} position="—" onClick={() => selectEmptySlot('tribuna')} />
                ))}
              </div>
            )}
          </div>
          <div className="role-legend"><span><i className="role-bar role-bar--GK" />Portiere</span><span><i className="role-bar role-bar--DEF" />Difensori</span><span><i className="role-bar role-bar--MID" />Centrocampisti</span><span><i className="role-bar role-bar--ATT" />Attaccanti</span></div>
          <div className="formation-footer">
            <span>{titolari.length} titolari · {panchina.length} panchina · {tribuna.length} tribuna</span>
          </div>
        </section>
      )}
      {playerAction && <div className="player-action-layer" role="presentation" onPointerDown={(event) => { if (event.target === event.currentTarget) setPlayerAction(null) }}>
        <section className="player-action-menu" role="dialog" aria-label={`Azioni per ${playerAction.player.nome}`} style={{ left: playerAction.x, top: playerAction.y }}>
          <div className="player-action-menu__player">
            <span className={`player-action-menu__photo player-action-menu__photo--${reparto(playerAction.player.posizioni[0] ?? 'ATT')} has-photo`}><AnonymousPlayer /><img src={imageUrls[playerAction.player.id]} alt="" onError={(event) => { event.currentTarget.hidden = true; event.currentTarget.parentElement?.classList.remove('has-photo') }} /></span>
            <div><strong>{playerAction.player.nome}</strong><small>{playerAction.player.posizioni.join(' · ')} · OVR {playerAction.player.overall_corrente}</small></div>
            <button type="button" onClick={() => setPlayerAction(null)} aria-label="Chiudi menu">×</button>
          </div>
          <div className="player-action-menu__choices">
            <button type="button" onClick={() => { const location = playerAction.location; setPlayerAction(null); selectPlayer(location) }}><span>⇄</span><strong>Sostituzione</strong></button>
            <button type="button" onClick={() => { const player = playerAction.player; setPlayerAction(null); setDetailPlayer(player) }}><span>ⓘ</span><strong>Dettagli</strong></button>
          </div>
        </section>
      </div>}
      {detailPlayer && <SchedaGiocatore
        giocatore={{
          nome: detailPlayer.nome,
          club: detailPlayer.club,
          nazionalita: detailPlayer.nazionalita,
          posizioni: detailPlayer.posizioni,
          overall: detailPlayer.overall_corrente,
          eta: detailPlayer.eta_corrente,
          piede: detailPlayer.piede,
          altezza: detailPlayer.altezza,
          condizione: detailPlayer.condizione,
          infortunatoFinoA: detailPlayer.infortunato_fino_a,
          ritiroAnnunciato: detailPlayer.ritiro_annunciato,
          attributi: detailPlayer.attributi,
        }}
        fotoUrl={imageUrls[detailPlayer.id]}
        onClose={() => setDetailPlayer(null)}
      />}
    </main>
  )
}
