import { TestoAdattato } from './TestoAdattato'
import { useEffect, useLayoutEffect, useRef, useState, type MouseEvent as ReactMouseEvent } from 'react'
import { supabase } from '../lib/supabase'
import { attributiCorrenti } from '../lib/attributiGiocatore'
import { disponiCard, nomeSchieramento, schieramentoInCampo } from '../lib/schieramento'
import SchemaTattico, { type XpDisposizione } from './SchemaTattico'
import { STILE_LABEL } from '../lib/stili'
import { idoneitaRuolo, segnoIdoneita } from '../lib/tattica'
import { PRESET, applicaPreset } from '../lib/preset'
import { DialogoNomeRiserva, SchemiCard } from './SchemiCard'
import { urlFotoGiocatore } from '../lib/fotoGiocatore'
import { cognome } from '../lib/nomi'
import { ROSA_MASSIMA } from '../lib/league'
import type { League, Membership } from '../types'
import { GameNav } from './GameNav'
import { SchedaGiocatore } from './SchedaGiocatore'
import type { GameView } from './GameNav'
import { LoadingLogo } from './LoadingLogo'
import { PopupSpiegazione } from './PopupSpiegazione'
import { SFONDO_FASE_VERTICALE, useFaseSquadra } from '../lib/faseSquadra'
import { FtsgGauge } from './FtsgGauge'
import { Icona } from './Icona'

// Mirror di engine/config.js CFG.FAM_PARTITE_PIENA: qui serve solo a
// mostrare la stessa percentuale che il motore usa per il malus di
// familiarita' (engine.js, familiarita()), non a ricalcolarla — nessuna
// formula del motore viene duplicata, solo questa soglia.
const FAM_PARTITE_PIENA = 5

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


type PlayerStats = Record<string, number | null>
type Player = { id: number; fc_id: number; nome: string; club: string; nazionalita: string | null; overall_corrente: number; eta_corrente: number; posizioni: string[]; piede: string | null; altezza: number | null; condizione: number; infortunato_fino_a: number; squalificato_fino_a: number; ritiro_annunciato: boolean; attributi: PlayerStats; foto_url: string | null }
// Uno schema salvato con un nome (tabella moduli_personalizzati): posizioni,
// ruoli, compiti e dove si attacca. Al massimo 3 per squadra, visibili solo a
// chi li ha salvati.
type ModuloPersonalizzato = { id: number; nome: string; modulo: string; disposizione: string[]; ruoli: (string | null)[] | null; compiti: (string | null)[] | null; focus_corsia: string | null; stile: string | null; linea_difensiva: string | null; ampiezza: string | null; ruolo_portiere: string | null }
const MODULI_PERSONALIZZATI_MAX = 3
// Uno schema tattico: tutto cio' che lo Schema Tattico e la pagina Squadra decidono.
type Tattica = {
  modulo: string; disposizione: string[] | null; ruoli: (string | null)[] | null; compiti: (string | null)[] | null
  focus: string | null; stile: string; linea: string | null; ampiezza: string | null; portiere: string | null
}
const stessiValori = (a: (string | null)[] | null | undefined, b: (string | null)[] | null | undefined) =>
  JSON.stringify((a ?? []).map((v) => v ?? null)) === JSON.stringify((b ?? []).map((v) => v ?? null))
  || (!(a ?? []).some(Boolean) && !(b ?? []).some(Boolean))

type SavedLineup = { modulo: string; stile_gioco: string; titolari: number[]; panchina: number[]; tribuna: number[]; salvata_il: string; disposizione: string[] | null; ruoli: (string | null)[] | null; compiti: (string | null)[] | null; focus_corsia: string | null; linea_difensiva: string | null; ampiezza: string | null; ruolo_portiere: string | null }

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
  // Il ruolo dato alla posizione nello Schema Tattico: se c'e', la maglietta
  // dice al volo quanto il giocatore e' adatto, senza aprire lo schema.
  ruolo?: string | null
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
// Stessa eccezione mirata di engine/config.js (penalitaRuolo, decisa con
// l'utente il 30 agosto 2026): LB/LM per LWB, RB/RM per RWB valgono come una
// posizione secondaria elencata in scheda (0.98, "natural" ai fini del
// warning), non la penalita' di reparto/adiacenza.
const QUASI_NATURALI: Record<string, string[]> = { LWB: ['LB', 'LM'], RWB: ['RB', 'RM'] }

function positionFit(slot: string, preferred: string[]): PositionFit {
  if (preferred.includes(slot)) return 'natural'
  if (QUASI_NATURALI[slot]?.some((position) => preferred.includes(position))) return 'natural'
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
// La forma fisica sull'overall: copia di fattoreCondizione() in
// engine/engine.js, stesse ancore (da 85 in su nessuna perdita, a 25 il -18%).
// Se cambia il motore va aggiornata anche qui.
const ANCORE_CONDIZIONE: Array<[number, number]> = [[25, 0.820], [40, 0.890], [55, 0.940], [70, 0.975], [85, 1.000]]
function fattoreCondizione(c: number): number {
  if (c >= 85) return 1
  if (c <= 25) return 0.82
  for (let i = ANCORE_CONDIZIONE.length - 1; i > 0; i--) {
    const [x1, y1] = ANCORE_CONDIZIONE[i - 1], [x2, y2] = ANCORE_CONDIZIONE[i]
    if (c >= x1) return y1 + (y2 - y1) * ((c - x1) / (x2 - x1))
  }
  return 0.82
}
// L'overall che il giocatore avrebbe in campo oggi in quel posto: penalita'
// di ruolo E forma fisica, come ovrEfficace() del motore (senza tattiche).
function overallInCampo(player: Player, slot: string): number {
  return Math.round(overallEfficacePosizione(player, slot) * fattoreCondizione(player.condizione))
}

function overallEfficacePosizione(player: Player, slot: string): number {
  const repSlot = reparto(slot)
  const repNat = reparto(player.posizioni[0] ?? slot)
  if (repSlot === 'GK' && repNat !== 'GK') return Math.min(45, player.overall_corrente * 0.45)
  if (repSlot !== 'GK' && repNat === 'GK') return Math.min(48, player.overall_corrente * 0.50)
  if (repSlot === 'GK' && repNat === 'GK') return player.overall_corrente
  if (player.posizioni[0] === slot) return player.overall_corrente
  if (player.posizioni.includes(slot)) return player.overall_corrente * 0.98
  if (QUASI_NATURALI[slot]?.includes(player.posizioni[0])) return player.overall_corrente * 0.98
  if (repNat === repSlot) return player.overall_corrente * 0.91
  if (ADIACENTI_REPARTO[repNat]?.includes(repSlot)) return player.overall_corrente * 0.80
  return player.overall_corrente * 0.65
}

// La soglia di cambio del motore e' 55: sotto quel valore il giocatore viene
// sostituito da solo, quindi e' li' che l'avviso deve diventare rosso.
function livelloEnergia(player: Player) {
  if (player.infortunato_fino_a > 0) return 'infortunato'
  if (player.squalificato_fino_a > 0) return 'squalificato'
  if (player.condizione < 55) return 'scarica'
  if (player.condizione < 75) return 'media'
  return 'piena'
}

// Infortunato o squalificato: stesso vincolo di disponibilita', non
// selezionabile fra titolari o panchina in nessuno dei due casi.
function indisponibile(player: Pick<Player, 'infortunato_fino_a' | 'squalificato_fino_a'> | undefined | null) {
  return (player?.infortunato_fino_a ?? 0) > 0 || (player?.squalificato_fino_a ?? 0) > 0
}

function AnonymousPlayer() {
  return <span className="anonymous-player" aria-hidden="true"><svg viewBox="0 0 100 110" focusable="false"><circle cx="50" cy="33" r="22" /><path d="M12 108c2-31 16-48 38-48s36 17 38 48H12Z" /></svg></span>
}

function PlayerPortrait({ player, imageUrl, position, selected = false, onClick, compact = false, empty = false, ruolo = null }: PlayerPortraitProps) {
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
  const idoneo = player && ruolo ? segnoIdoneita(idoneitaRuolo(player.attributi, player.overall_corrente, ruolo)) : null
  return <button className={`lineup-player ${compact ? 'lineup-player--compact' : ''} ${selected ? 'is-selected' : ''}`} type="button" onClick={onClick} aria-label={`${player?.nome ?? 'Slot vuoto'}, ${position}, overall ${player?.overall_corrente ?? 'non disponibile'}`}>
    <span className={`lineup-player__portrait lineup-player__portrait--${reparto(position)} ${imageUrl ? 'has-photo' : ''}`}>
      <AnonymousPlayer />
      {imageUrl && <img src={imageUrl} alt="" onError={(event) => { event.currentTarget.hidden = true; event.currentTarget.parentElement?.classList.remove('has-photo') }} />}
      {player && <span className={`energia energia--${livelloEnergia(player)}`} title={
        player.infortunato_fino_a > 0 ? `Infortunato: salta ancora ${player.infortunato_fino_a} ${player.infortunato_fino_a === 1 ? 'giornata' : 'giornate'}`
        : player.squalificato_fino_a > 0 ? `Squalificato: salta ancora ${player.squalificato_fino_a} ${player.squalificato_fino_a === 1 ? 'giornata' : 'giornate'}`
        : `Energia ${player.condizione}%`
      }>
        {player.infortunato_fino_a > 0 ? '✚' : player.squalificato_fino_a > 0 ? '■' : `${player.condizione}%`}
      </span>}
      {fit !== 'natural' && <i className={`position-warning position-warning--${fit}`} title={fit === 'adapted' ? 'Giocatore adattato in un ruolo vicino' : 'Giocatore completamente fuori posizione'} aria-label={fit === 'adapted' ? 'Fuori posizione di poco' : 'Completamente fuori posizione'}>!</i>}
    </span>
    <span className="lineup-player__plate">
      <strong><TestoAdattato>{player ? cognome(player.nome) : 'Seleziona'}</TestoAdattato></strong>
      <span className="lineup-player__meta">
        <span className={`lineup-player__position lineup-player__position--${reparto(position)}`}>{position}</span>
        <b>{player?.overall_corrente ?? '—'}</b>
        {idoneo && <span className={`lineup-player__ruolo lineup-player__ruolo--${idoneo.tono}`}
          title={idoneo.tono === 'piu' ? 'Adatto al ruolo che gli hai dato nello schema' : 'Poco adatto al ruolo che gli hai dato nello schema'}>{idoneo.segno}</span>}
      </span>
    </span>
  </button>
}

// La card di un titolare sul campo, nello stile dell'intro del match: foto con
// fascio di luce, targhetta nera col cognome, sotto ruolo e OVR. Quello che
// l'intro non ha sta dove non copre il volto (indicazioni della chat di main,
// 1° ottobre 2026): energia in alto al centro, fuori posizione in alto a
// destra, idoneita' al ruolo in basso a destra.
export function CartaCampo({ player, imageUrl, position, selected, onClick, ruolo }: { player?: Player; imageUrl?: string; position: string; selected: boolean; onClick: (event: ReactMouseEvent<HTMLButtonElement>) => void; ruolo: string | null }) {
  if (!player) {
    return <button className="rosa-card rosa-card--vuota" type="button" onClick={onClick} aria-label={`Posizione ${position} libera: tocca per assegnare un giocatore`}>
      <span className="rosa-card__foto"><span className="rosa-card__ritratto"><span className="rosa-card__iniziale">+</span></span></span>
      <span className="rosa-card__nome">Libero</span>
      <span className="rosa-card__riga"><i className={`rosa-card__ruolo--${reparto(position)}`}>{position}</i></span>
    </button>
  }
  const fit = positionFit(position, player.posizioni)
  // L'overall che ha davvero in quel posto oggi: penalita' di fuori ruolo e
  // forma fisica (stessi moltiplicatori del motore). E' quello che conta in partita.
  const efficace = overallInCampo(player, position)
  const idoneo = ruolo ? segnoIdoneita(idoneitaRuolo(player.attributi, player.overall_corrente, ruolo)) : null
  const livello = livelloEnergia(player)
  const fuoriGioco = player.infortunato_fino_a > 0 || player.squalificato_fino_a > 0
  return <button className={`rosa-card${selected ? ' is-selected' : ''}${fuoriGioco ? ' is-indisponibile' : ''}`} type="button" onClick={onClick}
    aria-label={`${player.nome}, ${position}, overall ${efficace}${efficace !== player.overall_corrente ? ` in questo ruolo (${player.overall_corrente} nel suo)` : ''}`}>
    <span className="rosa-card__foto">
      <span className="rosa-card__ritratto">
        {imageUrl ? <img src={imageUrl} alt="" onError={(event) => { event.currentTarget.hidden = true }} /> : <span className="rosa-card__iniziale">{player.nome.charAt(0)}</span>}
      </span>
      {/* Infortunio o squalifica: il segnalino resta sulla foto. L'energia
          invece e' la barretta sotto il nome. */}
      {fuoriGioco && <span className={`rosa-card__energia energia--${livello}`} title={player.infortunato_fino_a > 0
        ? `Infortunato: salta ancora ${player.infortunato_fino_a} ${player.infortunato_fino_a === 1 ? 'giornata' : 'giornate'}`
        : `Squalificato: salta ancora ${player.squalificato_fino_a} ${player.squalificato_fino_a === 1 ? 'giornata' : 'giornate'}`}>
        {player.infortunato_fino_a > 0 ? '✚' : '■'}
      </span>}
      {fit !== 'natural' && <i className={`rosa-card__fuori rosa-card__fuori--${fit}`} title={fit === 'adapted' ? 'Adattato in un ruolo vicino' : 'Completamente fuori posizione'} aria-label={fit === 'adapted' ? 'Fuori posizione di poco' : 'Completamente fuori posizione'} >!</i>}
      {idoneo && <i className={`rosa-card__idoneo rosa-card__idoneo--${idoneo.tono}`} title={idoneo.tono === 'piu' ? 'Adatto al ruolo che gli hai dato nello schema' : 'Poco adatto al ruolo che gli hai dato nello schema'}>{idoneo.segno}</i>}
    </span>
    <span className="rosa-card__nome"><TestoAdattato>{cognome(player.nome)}</TestoAdattato></span>
    <span className="rosa-card__barra" title={`Energia ${player.condizione}%`} aria-label={`Energia ${player.condizione}%`}><i className={`energia--${livello}`} style={{ width: `${Math.max(4, Math.min(100, player.condizione))}%` }} /></span>
    <span className="rosa-card__riga"><i className={`rosa-card__ruolo--${reparto(position)}`}>{position}</i><b className={efficace < player.overall_corrente ? 'is-ridotto' : undefined}>{efficace}</b></span>
  </button>
}

export function Formazione({ membership, onNavigate }: FormazioneProps) {
  const league = membership.league as League
  const tatticheAttive = Boolean(league.tattiche_attive)
  const [players, setPlayers] = useState<Player[]>([])
  const [imageUrls, setImageUrls] = useState<Record<number, string>>({})
  const [modulo, setModulo] = useState('4-3-3')
  const [moduleMenuOpen, setModuleMenuOpen] = useState(false)
  // Due schemi tattici con un nome (season 2, stile EA FC): l'ATTIVO gioca (e'
  // la formazione salvata), la RISERVA si prepara e impara il suo modulo a ogni
  // partita anche se non e' schierata. Le variabili di sotto (modulo, ruoli,
  // stile...) mostrano sempre lo schema SELEZIONATO; l'altro sta messo da parte
  // in `attivoFermo` / `riservaFerma`. Salvando, vanno entrambi.
  const [schemaSel, setSchemaSel] = useState<'attivo' | 'riserva'>('attivo')
  const [nomeAttivo, setNomeAttivo] = useState('Schema 1')
  const [haRiserva, setHaRiserva] = useState(false)
  const [nomeRiserva, setNomeRiserva] = useState('Schema 2')
  const [attivoFermo, setAttivoFermo] = useState<Tattica | null>(null)
  const [riservaFerma, setRiservaFerma] = useState<Tattica | null>(null)
  // La riserva e' gia' stata salvata col suo nome? Se no, la prima volta lo chiede.
  const [nomeRiservaConfermato, setNomeRiservaConfermato] = useState(false)
  const [chiediNomeRiserva, setChiediNomeRiserva] = useState(false)
  const schemiSalvati = useRef('')
  const [stile, setStile] = useState('equilibrato')
  const [salvataIl, setSalvataIl] = useState<string | null>(null)
  const [titolari, setTitolari] = useState<number[]>([])
  const [panchina, setPanchina] = useState<number[]>([])
  const [tribuna, setTribuna] = useState<number[]>([])
  // Schema personalizzato (engine/ruoli.js, migrazione 20260917020000). NULL su
  // tutti e tre = lo schieramento standard del modulo, cioe' il gioco di prima.
  const [disposizione, setDisposizione] = useState<string[] | null>(null)
  const [ruoli, setRuoli] = useState<(string | null)[] | null>(null)
  const [compiti, setCompiti] = useState<(string | null)[] | null>(null)
  const [focusCorsia, setFocusCorsia] = useState<string | null>(null)
  const [moduliPersonalizzati, setModuliPersonalizzati] = useState<ModuloPersonalizzato[]>([])
  // La fase della squadra (stagione regolare, Title o Draft Playoffs) da' il
  // colore alla pagina, come scoreboard, tabellone e riepilogo partita.
  const [stagioneId, setStagioneId] = useState<number | null>(null)
  useEffect(() => {
    let vivo = true
    void supabase.from('seasons').select('id').eq('league_id', league.id).eq('numero', league.stagione_corrente).maybeSingle()
      .then(({ data }) => { if (vivo) setStagioneId(data?.id ?? null) })
    return () => { vivo = false }
  }, [league.id, league.stagione_corrente])
  const fase = useFaseSquadra(league.id, membership.id, stagioneId)
  // Indicazioni di squadra (registro tattico, punto 30). null = predefinita.
  const [linea, setLinea] = useState<string | null>(null)
  const [ampiezza, setAmpiezza] = useState<string | null>(null)
  const [portiere, setPortiere] = useState<string | null>(null)
  const [schemaAperto, setSchemaAperto] = useState(false)
  const [xpDisposizione, setXpDisposizione] = useState<XpDisposizione[]>([])
  const [xpIndicazioni, setXpIndicazioni] = useState(0)
  const [selected, setSelected] = useState<PlayerLocation | null>(null)
  const [openZone, setOpenZone] = useState<PlayerZone>('starter')
  const [detailPlayer, setDetailPlayer] = useState<Player | null>(null)
  const [playerAction, setPlayerAction] = useState<PlayerAction | null>(null)
  // Il posto titolare vuoto per cui e' aperta la tendina di scelta.
  const [sceltaPosto, setSceltaPosto] = useState<number | null>(null)
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [saved, setSaved] = useState(false)
  // La formazione com'era all'ultimo salvataggio (o al caricamento di una
  // distinta gia' salvata): il bottone Salva si accende solo se quella attuale
  // e' diversa. null = mai salvata, quindi c'e' sempre qualcosa da salvare.
  const [firmaSalvata, setFirmaSalvata] = useState<string | null>(null)
  const fissaFirma = useRef(false)
  const [error, setError] = useState<string | null>(null)
  const [giornata, setGiornata] = useState(1)
  const [esperienzaModulo, setEsperienzaModulo] = useState<Record<string, number>>({})
  const [esperienzaStile, setEsperienzaStile] = useState<Record<string, number>>({})
  const [ftsgInfoOpen, setFtsgInfoOpen] = useState(false)

  // La scheda giocatore gestisce da se' Escape e blocco dello scorrimento:
  // qui resta solo la mini-card delle azioni.
  useEffect(() => {
    if (!playerAction) return
    const chiudiConEsc = (event: KeyboardEvent) => { if (event.key === 'Escape') setPlayerAction(null) }
    document.addEventListener('keydown', chiudiConEsc)
    return () => { document.removeEventListener('keydown', chiudiConEsc) }
  }, [playerAction])

  useEffect(() => {
    if (!ftsgInfoOpen) return
    const chiudiConEsc = (event: KeyboardEvent) => { if (event.key === 'Escape') setFtsgInfoOpen(false) }
    document.addEventListener('keydown', chiudiConEsc)
    return () => { document.removeEventListener('keydown', chiudiConEsc) }
  }, [ftsgInfoOpen])

  useEffect(() => {
    let active = true
    async function load() {
      const { data: instances, error: rosterError } = await supabase
        .from('player_instances')
        .select('id, overall_corrente, eta_corrente, condizione, infortunato_fino_a, squalificato_fino_a, ritiro_annunciato, player_id, posizioni_override')
        .eq('league_id', league.id)
        .eq('team_id', membership.id)
        .order('overall_corrente', { ascending: false })
      if (rosterError) { setError(rosterError.message); setLoading(false); return }
      const roster = instances ?? []
      // Gli attributi veri (crescita + piano di sviluppo) arrivano a parte:
      // vedi lib/attributiGiocatore. Quelli del catalogo restano di riserva.
      const [{ data: catalog, error: playerError }, attributiVeri] = await Promise.all([
        supabase.from('players').select('id, fc_id, nome, club, nazionalita, posizioni, piede, altezza, attributi, foto_url').in('id', roster.map((item) => item.player_id)),
        attributiCorrenti(roster.map((item) => item.id)),
      ])
      if (playerError) { setError(playerError.message); setLoading(false); return }
      const catalogById = new Map((catalog ?? []).map((player) => [player.id, player]))
      const loaded = roster.map((item) => ({ ...item, fc_id: catalogById.get(item.player_id)?.fc_id, nome: catalogById.get(item.player_id)?.nome ?? `Giocatore ${item.player_id}`, club: catalogById.get(item.player_id)?.club ?? '—', nazionalita: catalogById.get(item.player_id)?.nazionalita ?? null, posizioni: item.posizioni_override ?? catalogById.get(item.player_id)?.posizioni ?? [], piede: catalogById.get(item.player_id)?.piede ?? null, altezza: catalogById.get(item.player_id)?.altezza ?? null, attributi: attributiVeri.get(item.id) ?? catalogById.get(item.player_id)?.attributi ?? {}, foto_url: catalogById.get(item.player_id)?.foto_url ?? null })) as Player[]
      if (!active) return
      setPlayers(loaded)
      const signed = await Promise.all(loaded.filter((player) => player.foto_url).map(async (player) => {
        if (player.foto_url?.startsWith('http')) return [player.id, player.foto_url] as const
        return [player.id, urlFotoGiocatore(player.foto_url)] as const
      }))
      if (active) setImageUrls(Object.fromEntries(signed.filter((item): item is [number, string] => Boolean(item[1]))))
      const [{ data: formationXp, error: formationXpError }, { data: stileXp, error: stileXpError }, { data: indicazioniXp }] = await Promise.all([
        supabase.from('formation_xp').select('modulo, disposizione, partite_giocate').eq('league_id', league.id).eq('team_id', membership.id),
        supabase.from('stile_xp').select('stile, partite_giocate').eq('league_id', league.id).eq('team_id', membership.id),
        supabase.from('indicazioni_xp').select('partite_giocate').eq('team_id', membership.id).maybeSingle(),
      ])
      // I moduli salvati non sono indispensabili per schierare: se la lettura
      // fallisce la pagina funziona lo stesso, senza la sezione "I tuoi moduli".
      const { data: moduliSalvati } = await supabase.from('moduli_personalizzati')
        .select('id, nome, modulo, disposizione, ruoli, compiti, focus_corsia, stile, linea_difensiva, ampiezza, ruolo_portiere')
        .eq('team_id', membership.id).order('creato_il')
      if (active) setModuliPersonalizzati((moduliSalvati ?? []) as ModuloPersonalizzato[])
      if (formationXpError) { setError(formationXpError.message); setLoading(false); return }
      if (stileXpError) { setError(stileXpError.message); setLoading(false); return }
      if (active) {
        setEsperienzaModulo(Object.fromEntries((formationXp ?? []).map((riga) => [riga.modulo, riga.partite_giocate])))
        setEsperienzaStile(Object.fromEntries((stileXp ?? []).map((riga) => [riga.stile, riga.partite_giocate])))
        setXpDisposizione((formationXp ?? [])
          .filter((riga) => Array.isArray(riga.disposizione) && riga.disposizione.length === 11)
          .map((riga) => ({ disposizione: riga.disposizione as string[], partite: riga.partite_giocate })))
        setXpIndicazioni(indicazioniXp?.partite_giocate ?? 0)
      }
      if (league.tattiche_attive) {
        const { data: sc } = await supabase.from('schemi_squadra').select('*').eq('team_id', membership.id).maybeSingle()
        if (active) {
          const nomeA = (sc?.nome_attivo as string | undefined) ?? 'Schema 1'
          setNomeAttivo(nomeA)
          let riservaCaricata: Tattica | null = null
          if (sc?.riserva_modulo && Array.isArray(sc.riserva_disposizione)) {
            const standard = MODULI[sc.riserva_modulo as string] ?? []
            riservaCaricata = {
              modulo: sc.riserva_modulo as string,
              disposizione: stessiValori(sc.riserva_disposizione as string[], standard) ? null : sc.riserva_disposizione as string[],
              ruoli: (sc.riserva_ruoli as (string | null)[] | null) ?? null, compiti: (sc.riserva_compiti as (string | null)[] | null) ?? null,
              focus: (sc.riserva_focus_corsia as string | null) ?? null, stile: (sc.riserva_stile as string | null) ?? 'equilibrato',
              linea: (sc.riserva_linea as string | null) ?? null, ampiezza: (sc.riserva_ampiezza as string | null) ?? null,
              portiere: (sc.riserva_portiere as string | null) ?? null,
            }
            setHaRiserva(true); setNomeRiserva(sc.riserva_nome as string); setNomeRiservaConfermato(true)
            setRiservaFerma(riservaCaricata)
          }
          // La stessa firma che calcola save(): niente chiamata se non cambia nulla.
          schemiSalvati.current = JSON.stringify({ nomeAttivo: nomeA, ris: riservaCaricata, nome: riservaCaricata ? sc?.riserva_nome : 'Schema 2' })
        }
      }
      const { data: nextFixture, error: fixtureError } = await supabase.from('fixtures').select('giornata')
        .eq('league_id', league.id).in('stato', ['programmata', 'in_corso']).order('giornata').limit(1).maybeSingle()
      if (fixtureError) { setError(fixtureError.message); setLoading(false); return }
      const targetGiornata = nextFixture?.giornata ?? league.giornate_totali
      if (active) setGiornata(targetGiornata)
      const { data: lineup, error: lineupError } = await supabase.from('lineups')
        .select('modulo, stile_gioco, titolari, panchina, tribuna, salvata_il, disposizione, ruoli, compiti, focus_corsia, linea_difensiva, ampiezza, ruolo_portiere')
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
        // I titolari si rimpiazzano SUL POSTO, non si filtrano via. Ogni indice
        // di questo array e' uno slot del modulo: filtrare accorciava l'array e
        // faceva scalare a sinistra tutti quelli dopo il ceduto, cioe' li
        // spostava in slot che non erano i loro. Chi usciva dalla rosa a
        // centrocampo si portava dietro mezza squadra, e il posto vuoto
        // compariva in fondo invece che dove mancava davvero il giocatore.
        // Con 0 (sentinella "vuoto") lo slot resta esattamente dov'era.
        // Segnalato il 13 settembre 2026 dopo uno scambio in Serie F.
        const titolariSalvati = current.titolari.map((id) => (idsRosa.has(id) ? id : 0))
        const panchinaSalvata = current.panchina.filter((id) => idsRosa.has(id))
        const tribunaSalvata = current.tribuna.filter((id) => idsRosa.has(id))
        const giaInDistinta = new Set([...titolariSalvati, ...panchinaSalvata, ...tribunaSalvata])
        const nuoviArrivi = loaded.filter((player) => !giaInDistinta.has(player.id)).map((player) => player.id)
        // Resta il riempimento in coda, ma ora copre solo il caso di una
        // distinta salvata con meno slot di quelli del modulo corrente. Un
        // array piu' corto e' un problema vero, non solo estetico: gli
        // aggiornamenti per indice (`.map((v,i)=>i===index?id:v)`) su un array
        // che non ha ancora quell'indice non lo creano, quindi lo slot
        // resterebbe permanentemente non assegnabile.
        const slotTitolari = MODULI[current.modulo]?.length ?? 11
        const titolariCompleti = titolariSalvati.length >= slotTitolari
          ? titolariSalvati
          : [...titolariSalvati, ...Array(slotTitolari - titolariSalvati.length).fill(0)]
        setModulo(current.modulo)
        setDisposizione(current.disposizione ?? null)
        setRuoli(current.ruoli ?? null)
        setCompiti(current.compiti ?? null)
        setFocusCorsia(current.focus_corsia ?? null)
        setLinea(current.linea_difensiva ?? null)
        setAmpiezza(current.ampiezza ?? null)
        setPortiere(current.ruolo_portiere ?? null)
        setStile(current.stile_gioco)
        setSalvataIl(current.salvata_il)
        fissaFirma.current = true
        setTitolari(titolariCompleti)
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

  // Lo schieramento davvero in campo: quello personalizzato se c'e', altrimenti
  // lo standard del modulo.
  const slots = disposizione ?? MODULI[modulo]
  // Le righe si DERIVANO dalle posizioni (src/lib/schieramento.ts). Prima qui
  // c'era una catena di casi per nome di modulo, con due bug gia' corretti a
  // mano dentro — il 4-2-4 che scambiava le ali e il CAM del 4-3-3 offensivo
  // che finiva di lato. Con gli schemi personalizzati quel modo non regge piu':
  // due squadre col 4-4-2 possono schierarsi in modo diverso, quindi il nome
  // del modulo non dice piu' dove stanno gli undici.
  // Posizionamento assoluto, non righe a griglia: una griglia ridistribuisce
  // in parti uguali, quindi due CDM — che stanno entrambi al centro — finivano
  // sulle fasce come se fossero due esterni.
  const posti = schieramentoInCampo(slots)

  // Le card non devono mai coprirsi (lib/schieramento.ts, disponiCard): si
  // misurano campo e card veri e si allontanano solo quelle che si toccano,
  // rimpicciolendole se lo spazio non basta. La misura si ripete quando il
  // campo cambia dimensione (rotazione, finestra).
  const campoRef = useRef<HTMLDivElement | null>(null)
  const [misure, setMisure] = useState<{ w: number; h: number; cw: number; ch: number } | null>(null)
  useLayoutEffect(() => {
    const el = campoRef.current
    if (!el) return
    const misura = () => {
      const card = el.querySelector<HTMLElement>('.pitch-posto')
      if (!card || !el.clientWidth) return
      // offsetWidth/offsetHeight non risentono della scala applicata: e' la
      // misura "piena" della card. Qualche pixel in piu' per il badge
      // dell'energia, che sporge sopra la foto.
      const nuove = { w: el.clientWidth, h: el.clientHeight, cw: card.offsetWidth, ch: card.offsetHeight + 14 }
      setMisure((prima) => (prima && prima.w === nuove.w && prima.h === nuove.h && prima.cw === nuove.cw && prima.ch === nuove.ch ? prima : nuove))
    }
    misura()
    const osservatore = new ResizeObserver(misura)
    osservatore.observe(el)
    return () => osservatore.disconnect()
  })
  const disposizioneCard = misure
    ? disponiCard(posti.map((p) => ({ x: p.x, y: p.y })), { w: misure.w, h: misure.h }, { w: misure.cw, h: misure.ch }, 10)
    : null

  // Overall medio dei titolari, nello slot in cui sono davvero schierati:
  // un giocatore fuori ruolo pesa meno, esattamente come nel motore —
  // altrimenti il cerchio direbbe "forte" anche con tre titolari fuori
  // posto, mentre l'avviso (!) su ognuno di loro racconta un'altra storia.
  const titolariConSlot = titolari
    .map((id, index) => ({ player: players.find((item) => item.id === id), slot: slots[index] }))
    .filter((item): item is { player: Player; slot: string } => Boolean(item.player))
  const overallTitolari = titolariConSlot.length
    ? Math.round(titolariConSlot.reduce((somma, item) => somma + overallEfficacePosizione(item.player, item.slot) * fattoreCondizione(item.player.condizione), 0) / titolariConSlot.length)
    : null

  // Indice FTSG: stessa combinazione (media modulo+stile) che il motore usa
  // per il malus di familiarita' sul modulo/stile selezionati ORA, anche
  // prima di salvare — cosi' si vede subito l'effetto di un cambio prima
  // di confermarlo.
  const ftsgModuloPct = Math.min(100, ((esperienzaModulo[modulo] ?? 0) / FAM_PARTITE_PIENA) * 100)
  const ftsgStilePct = Math.min(100, ((esperienzaStile[stile] ?? 0) / FAM_PARTITE_PIENA) * 100)

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

    // Se si sostituisce un titolare indisponibile (infortunato o squalificato)
    // con una riserva disponibile, l'indisponibile va direttamente in tribuna
    // e lascia libero il suo posto in panchina: non deve servire un secondo
    // scambio manuale.
    const injuredStarter = indisponibile(firstPlayer) && selected.zone === 'starter'
      ? selected
      : indisponibile(secondPlayer) && location.zone === 'starter'
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
        .filter((item) => !indisponibile(item.player))
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
    if ((indisponibile(firstPlayer) && firstDestination !== 'tribuna')
      || (indisponibile(secondPlayer) && secondDestination !== 'tribuna')) {
      setError('Un giocatore infortunato o squalificato può essere spostato soltanto in tribuna.')
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
    if (indisponibile(player) && zone !== 'tribuna') {
      setError('Un giocatore infortunato o squalificato può essere spostato soltanto in tribuna.')
      return
    }
    if (selected.zone === 'bench') setPanchina((current) => current.filter((_value, index) => index !== selected.index))
    else setTribuna((current) => current.filter((_value, index) => index !== selected.index))
    if (zone === 'bench') setPanchina((current) => [...current, id])
    else setTribuna((current) => [...current, id])
    setSelected(null)
    setError(null)
  }

  // Equivalente di selectEmptySlot per uno slot titolare vuoto (id 0: nessun
  // player_instance ha mai quell'id). A differenza di panchina e tribuna,
  // che sono liste libere dove "arrivare" significa accodarsi, un titolare
  // ha una posizione fissa legata al modulo: bisogna scrivere esattamente
  // in quell'indice, non in coda. Instradarlo invece per selectPlayer (lo
  // scambio) lascerebbe un id 0 fittizio nella zona di partenza — un
  // "fantasma" che poi il salvataggio manderebbe al server.
  function selectEmptyStarter(index: number) {
    if (!selected) return
    setSaved(false)
    if (selected.zone === 'starter' && selected.index === index) { setSelected(null); return }
    const id = playerAt(selected)
    const player = players.find((item) => item.id === id)
    if (indisponibile(player)) {
      setError('Un giocatore infortunato o squalificato può essere spostato soltanto in tribuna.')
      return
    }
    if (selected.zone === 'bench') setPanchina((current) => current.filter((_value, i) => i !== selected.index))
    else if (selected.zone === 'tribuna') setTribuna((current) => current.filter((_value, i) => i !== selected.index))
    setTitolari((current) => current.map((value, i) => {
      if (i === index) return id
      if (selected.zone === 'starter' && i === selected.index) return 0
      return value
    }))
    setSelected(null)
    setError(null)
  }

  // Dalla tendina del posto vuoto: il giocatore scelto lascia panchina o
  // tribuna e prende quel posto (stesso effetto di selezionarlo e poi
  // toccare il posto, in un tocco solo).
  function mettiTitolare(index: number, location: PlayerLocation) {
    setSaved(false)
    if (location.zone === 'bench') setPanchina((current) => current.filter((_value, i) => i !== location.index))
    else if (location.zone === 'tribuna') setTribuna((current) => current.filter((_value, i) => i !== location.index))
    setTitolari((current) => current.map((value, i) => i === index ? location.id : value))
    setSceltaPosto(null)
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

  async function save(nomeRiservaScelto?: string) {
    // La prima volta che si salva uno schema riserva se ne chiede il nome.
    if (tatticheAttive && haRiserva && !nomeRiservaConfermato && nomeRiservaScelto === undefined) { setChiediNomeRiserva(true); return }
    setSaving(true); setSaved(false); setError(null)
    if (titolari.length !== slots.length || titolari.some((id) => !id)) {
      setError('Completa tutti e undici i titolari prima di salvare.')
      setSaving(false)
      return
    }
    const cleanBench = panchina.filter((id) => !titolari.includes(id)).slice(0, PANCHINA_MAX)
    const nonSelezionabili = [...titolari, ...cleanBench].filter((id) => indisponibile(players.find((player) => player.id === id)))
    if (nonSelezionabili.length) {
      setError('Sposta tutti i giocatori infortunati o squalificati in tribuna prima di salvare.')
      setSaving(false)
      return
    }
    // Va in partita lo schema SELEZIONATO al momento del salvataggio: se e' la
    // riserva, diventa lo schema attivo e quello di prima passa a riserva
    // (continua a imparare); i nomi seguono gli schemi.
    const invertire = tatticheAttive && haRiserva && schemaSel === 'riserva'
    const nomeSel = nomeRiservaScelto ?? nomeRiserva
    const att = invertire ? tatticaCorrente : attivoCanonico
    const { error: saveError } = await supabase.rpc('salva_formazione', {
      p_league_id: league.id, p_giornata: giornata, p_modulo: att.modulo,
      p_disposizione: att.disposizione, p_ruoli: att.ruoli, p_compiti: att.compiti, p_focus_corsia: att.focus,
      p_titolari: titolari, p_panchina: cleanBench, p_tribuna: tribuna,
      p_stile_gioco: att.stile,
      p_linea: att.linea, p_ampiezza: att.ampiezza, p_portiere: att.portiere,
    })
    if (saveError) { setError(saveError.message); setSaving(false); return }
    // E, nelle leghe con le tattiche accese, i nomi e la riserva.
    if (tatticheAttive) {
      const ris = !haRiserva ? null : invertire ? attivoFermo : riservaCanonica
      const nomeA = invertire ? nomeSel : nomeAttivo
      const nome = invertire ? nomeAttivo : nomeSel
      const firmaSchemi = JSON.stringify({ nomeAttivo: nomeA, ris, nome })
      if (firmaSchemi !== schemiSalvati.current) {
        const { error: schemiError } = await supabase.rpc('salva_schemi', {
          p_league_id: league.id, p_nome_attivo: nomeA,
          p_riserva_nome: ris ? nome : null, p_modulo: ris?.modulo ?? null,
          p_disposizione: ris ? (ris.disposizione ?? MODULI[ris.modulo]) : null,
          p_ruoli: ris?.ruoli ?? null, p_compiti: ris?.compiti ?? null, p_focus_corsia: ris?.focus ?? null,
          p_stile: ris?.stile ?? null, p_linea: ris?.linea ?? null, p_ampiezza: ris?.ampiezza ?? null, p_portiere: ris?.portiere ?? null,
        })
        if (schemiError) { setError(`Formazione salvata, ma gli schemi no: ${schemiError.message}`); setSaving(false); return }
        schemiSalvati.current = firmaSchemi
        if (ris) { setNomeRiserva(nome); setNomeRiservaConfermato(true) }
        setNomeAttivo(nomeA)
      }
      if (invertire) { setRiservaFerma(attivoFermo); setAttivoFermo(null); setSchemaSel('attivo') }
    }
    setPanchina(cleanBench); setSaved(true); setSalvataIl(new Date().toISOString()); fissaFirma.current = true
    setSaving(false)
  }

  function applicaTattica(t: Tattica) {
    setModulo(t.modulo); setDisposizione(t.disposizione); setRuoli(t.ruoli); setCompiti(t.compiti)
    setFocusCorsia(t.focus); setStile(t.stile); setLinea(t.linea); setAmpiezza(t.ampiezza); setPortiere(t.portiere)
    setSelected(null); setPlayerAction(null)
  }

  // Si guarda (e si modifica) uno dei due schemi: quello non selezionato resta
  // da parte. La riserva vuota si crea come COPIA dell'attivo, da ritoccare.
  function selezionaSchema(quale: 'attivo' | 'riserva') {
    if (quale === schemaSel) return
    if (quale === 'riserva') {
      setAttivoFermo(tatticaCorrente)
      if (haRiserva && riservaFerma) applicaTattica(riservaFerma)
      else { setHaRiserva(true); setNomeRiserva('Schema 2'); setNomeRiservaConfermato(false) }
      setRiservaFerma(null)
      setSchemaSel('riserva')
    } else {
      setRiservaFerma(tatticaCorrente)
      if (attivoFermo) applicaTattica(attivoFermo)
      setAttivoFermo(null)
      setSchemaSel('attivo')
    }
  }

  function eliminaRiserva() {
    if (!haRiserva) return
    if (schemaSel === 'riserva' && attivoFermo) applicaTattica(attivoFermo)
    setAttivoFermo(null); setRiservaFerma(null); setHaRiserva(false); setSchemaSel('attivo')
    setNomeRiserva('Schema 2'); setNomeRiservaConfermato(false)
    setSaved(false)
  }

  // Un preset tattico: stile, linea, ampiezza, compiti e solo i ruoli per cui il
  // giocatore del posto e' adatto. Non tocca le posizioni, dove si attacca ne'
  // il portiere. Restituisce una frase per dire cosa e' successo.
  function usaPreset(id: string): string | null {
    const preset = PRESET.find((p) => p.id === id)
    if (!preset) return null
    const r = applicaPreset(preset, slots, (i, ruolo) => {
      const giocatore = players.find((p) => p.id === titolari[i])
      return giocatore ? idoneitaRuolo(giocatore.attributi, giocatore.overall_corrente, ruolo) : 0
    })
    setStile(r.stile); setLinea(r.linea); setAmpiezza(r.ampiezza); setPortiere(r.portiere)
    setRuoli(r.ruoli.some(Boolean) ? r.ruoli : null)
    setCompiti(r.compiti.some(Boolean) ? r.compiti : null)
    setSaved(false)
    const nGiocatori = slots.filter((s) => s !== 'GK').length
    return `${preset.nome} applicato: ${r.ruoliAssegnati} ruoli assegnati dove i giocatori sono adatti, gli altri ${nGiocatori - r.ruoliAssegnati} senza indicazione. Ricordati di salvare.`
  }

  function chooseModule(nextModule: string) {
    setModulo(nextModule)
    // Lo schema personalizzato appartiene al modulo da cui nasce: le posizioni
    // spostate sono spostamenti DI QUELLE posizioni, e portarsele su un modulo
    // diverso non vuol dire niente. Ruoli e compiti seguono, perche' anche loro
    // sono agganciati agli slot.
    setDisposizione(null)
    setRuoli(null)
    setCompiti(null)
    setFocusCorsia(null)
    setSaved(false)
    setSelected(null)
    setPlayerAction(null)
    setModuleMenuOpen(false)
  }

  function scegliModuloPersonalizzato(m: ModuloPersonalizzato) {
    chooseModule(m.modulo)
    const standard = MODULI[m.modulo] ?? []
    setDisposizione(stessiValori(m.disposizione, standard) ? null : m.disposizione)
    setRuoli(m.ruoli?.some(Boolean) ? m.ruoli : null)
    setCompiti(m.compiti?.some((c) => c && c !== 'equilibrio') ? m.compiti : null)
    setFocusCorsia(m.focus_corsia)
    if (m.stile) setStile(m.stile)
    setLinea(m.linea_difensiva)
    setAmpiezza(m.ampiezza)
    setPortiere(m.ruolo_portiere)
  }

  async function ricaricaModuliPersonalizzati() {
    const { data } = await supabase.from('moduli_personalizzati')
      .select('id, nome, modulo, disposizione, ruoli, compiti, focus_corsia, stile, linea_difensiva, ampiezza, ruolo_portiere')
      .eq('team_id', membership.id).order('creato_il')
    setModuliPersonalizzati((data ?? []) as ModuloPersonalizzato[])
  }

  async function salvaModuloPersonalizzato(nome: string, sostituisci: number | null): Promise<string | null> {
    const { error } = await supabase.rpc('salva_modulo_personalizzato', {
      p_league_id: league.id, p_nome: nome, p_modulo: modulo,
      p_disposizione: disposizione ?? MODULI[modulo], p_ruoli: ruoli, p_compiti: compiti,
      p_focus_corsia: focusCorsia, p_sostituisci: sostituisci,
      p_stile: stile, p_linea: linea, p_ampiezza: ampiezza, p_portiere: portiere,
    })
    if (error) return error.message
    await ricaricaModuliPersonalizzati()
    return null
  }

  async function eliminaModuloPersonalizzato(id: number): Promise<string | null> {
    const { error } = await supabase.rpc('elimina_modulo_personalizzato', { p_id: id })
    if (error) return error.message
    setModuliPersonalizzati((lista) => lista.filter((m) => m.id !== id))
    return null
  }

  // Il modulo salvato che corrisponde esattamente a quello in campo, se c'e':
  // il suo nome va nel selettore al posto del modulo di partenza.
  const moduloPersonalizzatoAttivo = moduliPersonalizzati.find((m) =>
    m.modulo === modulo
    && stessiValori(m.disposizione, disposizione ?? MODULI[modulo])
    && stessiValori(m.ruoli, ruoli)
    && stessiValori((m.compiti ?? []).map((c) => (c === 'equilibrio' ? null : c)), (compiti ?? []).map((c) => (c === 'equilibrio' ? null : c)))
    && (m.focus_corsia ?? null) === (focusCorsia ?? null)
    && (m.stile ?? 'equilibrato') === stile
    && (m.linea_difensiva ?? null) === linea && (m.ampiezza ?? null) === ampiezza && (m.ruolo_portiere ?? null) === portiere) ?? null


  // Gli schemi "canonici": quello che gioca e la riserva, indipendentemente da
  // quale dei due si sta guardando.
  const tatticaCorrente: Tattica = { modulo, disposizione, ruoli, compiti, focus: focusCorsia, stile, linea, ampiezza, portiere }
  const attivoCanonico: Tattica = schemaSel === 'attivo' ? tatticaCorrente : (attivoFermo ?? tatticaCorrente)
  const riservaCanonica: Tattica | null = !haRiserva ? null : schemaSel === 'riserva' ? tatticaCorrente : riservaFerma
  const firmaCorrente = JSON.stringify({ attivoCanonico, riservaCanonica, haRiserva, nomeAttivo, nomeRiserva, titolari, panchina, tribuna, schemaSel })
  const modificata = firmaSalvata === null || firmaSalvata !== firmaCorrente
  // Dopo il caricamento di una distinta salvata, o dopo un salvataggio
  // riuscito, la formazione in pagina diventa il nuovo riferimento.
  useEffect(() => {
    if (loading || !fissaFirma.current) return
    fissaFirma.current = false
    setFirmaSalvata(firmaCorrente)
  }, [loading, firmaCorrente])

  if (loading) return <main className="loading-screen"><LoadingLogo /><p>Preparo la formazione…</p></main>

  return (
    <main className="app-shell formation-shell">
      <GameNav league={league} active="squad" onNavigate={onNavigate} />
      <header className="topbar"><div className="brand-lockup brand-lockup--dark"><img src="/specialone-mark.svg" alt="" /><span>SpecialOne</span></div><span className="kicker">Giornata {giornata}</span></header>
      {schemaAperto && <SchemaTattico
        fase={fase}
        modulo={modulo}
        disposizione={disposizione}
        ruoli={ruoli}
        compiti={compiti}
        focus={focusCorsia}
        xpDisposizione={xpDisposizione}
        xpIndicazioni={xpIndicazioni}
        onChange={(d, r, c) => { setDisposizione(d); setRuoli(r); setCompiti(c); setSaved(false) }}
        onFocus={(f) => { setFocusCorsia(f); setSaved(false) }}
        onPreset={usaPreset}
        squadra={{ stile, linea, ampiezza, portiere }}
        onSquadra={(q) => {
          if (q.stile !== undefined) setStile(q.stile ?? 'equilibrato')
          if (q.linea !== undefined) setLinea(q.linea)
          if (q.ampiezza !== undefined) setAmpiezza(q.ampiezza)
          if (q.portiere !== undefined) setPortiere(q.portiere)
          setSaved(false)
        }}
        moduliSalvati={moduliPersonalizzati.map((m) => ({ id: m.id, nome: m.nome }))}
        moduloSalvatoAttivo={moduloPersonalizzatoAttivo?.id ?? null}
        onSalvaModulo={salvaModuloPersonalizzato}
        onEliminaModulo={eliminaModuloPersonalizzato}
        onClose={() => setSchemaAperto(false)}
      />}
      {/* Chiavi nuove (-v2): con la Season 2 il popup torna a tutti, aggiornato. */}
      {league.tattiche_attive
        ? <PopupSpiegazione userId={membership.user_id} hintKey="formazione-v2" titolo="Come funziona la Formazione">
          <p>Scegli il modulo e metti un giocatore in ogni posto: titolari, panchina e tribuna. Chi gioca fuori
            ruolo rende meno, e la Rosa ti mostra subito il suo <strong>overall effettivo</strong>: in giallo quando è
            più basso del normale, per il ruolo o per la stanchezza.</p>
          <p>Dalla card dello stile decidi <strong>come gioca la squadra</strong>: stile di gioco, dove attacca, linea
            difensiva, ampiezza e portiere. A ogni giocatore puoi dare un <strong>ruolo</strong> (un ruolo adatto a lui dà
            un bonus, uno sbagliato una penalità) e un <strong>compito</strong>: più difesa, equilibrio o più attacco. Se non
            vuoi perderci tempo, i <strong>preset tattici</strong> sistemano tutto con un tocco.</p>
          <p>La squadra rende meglio con ciò che conosce. La <strong>familiarità</strong> ha due barre: la disposizione in
            campo e le indicazioni. Si riempiono in 5 partite. Cambiare modulo non fa perdere quello già imparato:
            tornando al vecchio lo ritrovi.</p>
          <p>Hai <strong>due schemi</strong>. Quello segnato "Attivo" va in partita; l'altro lo prepari, e il suo modulo
            si impara un po' a ogni partita anche senza schierarlo. Selezionalo e salva per farlo diventare attivo.
            Se non schieri entro le <strong>23:00</strong>, il sistema mette una formazione automatica.</p>
        </PopupSpiegazione>
        : <PopupSpiegazione userId={membership.user_id} hintKey="formazione" titolo="Come funziona la Formazione">
        <p>Scegli uno dei moduli disponibili e assegna un giocatore a ogni slot: titolari, panchina e il
          resto in tribuna. Un giocatore fuori dal suo ruolo naturale gioca comunque, ma con un
          <strong> malus di rendimento</strong> — più marcato quanto più il ruolo è lontano dal suo.</p>
        <p>Più usi lo stesso modulo <strong>e</strong> lo stesso stile di gioco, più la squadra ci prende
          confidenza e rende meglio: è l'indice <strong>FTSG</strong> (familiarità tattiche e stile di
          gioco), il cerchio accanto a OVR titolari. Ogni partita giocata vale +20% di familiarità con quel
          modulo e quello stile; cambiarne anche solo uno per una giornata fa scendere l'indice. Se non
          schieri entro le <strong>23:00</strong>, il sistema genera una formazione automatica di riserva
          per non farti saltare la giornata.</p>
        <p>La barretta sotto il nome di ogni giocatore è la sua <strong>energia</strong>: più è bassa, meno
          rende in campo (il suo overall effettivo scende, fino a −18% sotto il 40%) e più rischia di
          infortunarsi. Recupera da sola fra una partita e l'altra, più in fretta se investi nel Reparto
          medico in Gestione risorse. Un giocatore infortunato o squalificato non può scendere in campo: va
          spostato in tribuna finché non torna disponibile.</p>
        </PopupSpiegazione>}
      <section className="formation-hero"><p className="kicker">La tua distinta · {league.nome}</p><h1>Schiera la squadra.</h1></section>
      {error && <p className="notice notice--error" role="alert">{error}</p>}
      {players.length < 11 ? <section className="formation-panel"><h2>Rosa incompleta</h2><p>Servono almeno 11 giocatori prima di poter salvare una formazione.</p></section> : (
        <section className={`formation-panel formation-panel--tactical formazione-broadcast formazione-broadcast--${fase}`}>
          <div className="formation-toolbar">
            <div className="formation-save-row">
              <button className={`formation-save-button button button--primary${modificata ? '' : ' is-salvata'}`} type="button" disabled={saving || !modificata} onClick={() => void save()}>{saving ? 'Salvo…' : modificata ? 'Salva' : 'Salvata'}</button>
              {(saved || salvataIl) && <div className="formation-save-stato">
                {saved && <span>Formazione salvata</span>}
                {salvataIl && <small>Salvata il {formatSalvataIl(salvataIl)}</small>}
              </div>}
            </div>
            {overallTitolari !== null && <div className="formation-overall" title="Overall medio effettivo degli undici titolari, nello slot in cui sono schierati: chi è fuori ruolo pesa meno">
              <strong>{overallTitolari}</strong>
              <span>OVR titolari</span>
            </div>}
            <div className="formation-ftsg">
              <FtsgGauge moduloPct={ftsgModuloPct} stilePct={ftsgStilePct} onClick={() => setFtsgInfoOpen(true)} />
              <span>Familiarità</span>
            </div>
            <div className="formation-tattica">
              {tatticheAttive && <SchemiCard
              nomeAttivo={nomeAttivo}
              nomeRiserva={haRiserva ? nomeRiserva : null}
              selezionato={schemaSel}
              descrizioneAttivo={`${attivoCanonico.modulo} · ${(STILE_LABEL[attivoCanonico.stile] ?? attivoCanonico.stile).toLowerCase()}`}
              descrizioneRiserva={riservaCanonica ? `${riservaCanonica.modulo} · ${(STILE_LABEL[riservaCanonica.stile] ?? riservaCanonica.stile).toLowerCase()}` : ''}
              partite={riservaCanonica ? xpDisposizione.find((r) => stessiValori(r.disposizione, riservaCanonica.disposizione ?? MODULI[riservaCanonica.modulo]))?.partite ?? 0 : 0}
              partitePiene={FAM_PARTITE_PIENA}
              onSeleziona={selezionaSchema}
              onRinomina={(quale, nome) => { if (quale === 'attivo') setNomeAttivo(nome); else { setNomeRiserva(nome); setNomeRiservaConfermato(true) } setSaved(false) }}
              onEliminaRiserva={() => { if (window.confirm(`Eliminare lo schema riserva «${nomeRiserva}»?`)) eliminaRiserva() }}
            />}
              <div className="formation-tattica__voce formation-module-selector">
                <button className="formation-tattica__trigger" type="button" aria-haspopup="listbox" aria-expanded={moduleMenuOpen} onClick={() => { setModuleMenuOpen((open) => !open) }}>
                  <span className="formation-tattica__testo"><small>{moduloPersonalizzatoAttivo ? `Modulo personalizzato · da ${modulo}` : 'Modulo tattico'}</small><strong>{moduloPersonalizzatoAttivo?.nome ?? modulo}</strong></span>
                  <i aria-hidden="true"><Icona nome={moduleMenuOpen ? 'chiudi' : 'giu'} /></i>
                </button>
                {moduleMenuOpen && <><button className="formation-module-scrim" type="button" aria-label="Chiudi selezione modulo" onClick={() => setModuleMenuOpen(false)} /><div className="formation-module-menu" role="listbox" aria-label="Scegli il modulo">{Object.keys(MODULI).map((name) => { const attivo = name === modulo && !moduloPersonalizzatoAttivo; return <button className={attivo ? 'is-active' : ''} type="button" role="option" aria-selected={attivo} key={name} onClick={() => chooseModule(name)}><MiniModulo slots={MODULI[name]} /><strong>{name}</strong><small>{MODULO_DESCRIZIONI[name]}</small><span>{attivo ? '✓' : '›'}</span></button> })}
                  {moduliPersonalizzati.length > 0 && <>
                    <p className="formation-module-menu__sezione">I tuoi moduli · {moduliPersonalizzati.length}/{MODULI_PERSONALIZZATI_MAX}</p>
                    {moduliPersonalizzati.map((m) => { const attivo = moduloPersonalizzatoAttivo?.id === m.id; return <div className="formation-module-menu__personale" key={`p-${m.id}`}>
                      <button className={attivo ? 'is-active' : ''} type="button" role="option" aria-selected={attivo} onClick={() => scegliModuloPersonalizzato(m)}><MiniModulo slots={m.disposizione} /><strong>{m.nome}</strong><small>da {m.modulo} · {nomeSchieramento(m.disposizione, MODULI)}</small><span>{attivo ? '✓' : '›'}</span></button>
                      <button className="formation-module-menu__elimina" type="button" aria-label={`Elimina il modulo ${m.nome}`} onClick={() => { if (window.confirm(`Eliminare il modulo "${m.nome}"?`)) void eliminaModuloPersonalizzato(m.id).then((e) => { if (e) setError(e) }) }}><Icona nome="chiudi" /></button>
                    </div> })}
                  </>}
                </div></>}
              </div>
              <div className="formation-tattica__voce">
                <button className="formation-tattica__trigger" type="button" onClick={() => { setSchemaAperto(true); setModuleMenuOpen(false) }}>
                  <span className="formation-tattica__testo">
                    <small>Schema e stile{disposizione || ruoli || compiti || focusCorsia || linea || ampiezza || portiere ? <em className="formation-tattica__tag">personalizzato</em> : null}</small>
                    <strong>{(STILE_LABEL[stile] ?? stile).toLowerCase()}</strong>
                  </span>
                  <i aria-hidden="true"><Icona nome="avanti" /></i>
                </button>
              </div>
            </div>
          </div>
          {/* Schede in vetro come Title/Draft nel tabellone: barra luminosa
              sotto quella attiva, nel colore della fase. */}
          <div className="formazione-schede" role="tablist" aria-label="Zone della distinta">
            {([['starter', 'Titolari', locations.starter.length], ['bench', 'Panchina', locations.bench.length], ['tribuna', 'Tribuna', locations.tribuna.length]] as const).map(([zona, etichetta, quanti]) =>
              <button key={zona} type="button" role="tab" aria-selected={openZone === zona}
                className={`formazione-scheda${openZone === zona ? ' is-attiva' : ''}`} onClick={() => setOpenZone(zona)}>
                <span>{etichetta}</span><b>{quanti}</b>
              </button>)}
          </div>
          {selected && <p className="formation-swap-hint">Tocca il giocatore (o uno slot libero) con cui spostare {selectedPlayer?.nome ?? ''}.</p>}
          <div className="formation-view-card">
            {openZone === 'starter' ? (
              // Il campo e le card nello stile della formazione dell'intro del
              // match (MatchIntro): gesso puntinato e fascio di luce nel colore
              // della fase, sullo sfondo verticale della fase.
              <div className="pitch-field rosa-campo" aria-label={`Campo con modulo ${modulo}`} style={{ ['--und-fondo' as string]: `url(${SFONDO_FASE_VERTICALE[fase]})` }}>
                <div className="match-intro__gesso" aria-hidden="true">
                  <span className="match-intro__gesso-area match-intro__gesso-area--alto" />
                  <span className="match-intro__gesso-meta" />
                  <span className="match-intro__gesso-cerchio" />
                  <span className="match-intro__gesso-area match-intro__gesso-area--basso" />
                </div>
                <div className="pitch-grid pitch-grid--assoluta" ref={campoRef} style={{ ['--scala-card' as string]: disposizioneCard?.scala ?? 1 }}>
                  {posti.map(({ slot, index, x: x0, y: y0 }, i) => {
                    const { x, y } = disposizioneCard?.posti[i] ?? { x: x0, y: y0 }
                    const player = players.find((item) => item.id === titolari[index])
                    const location = { zone: 'starter', index, id: titolari[index] ?? 0 } as PlayerLocation
                    return <div className={`pitch-posto pitch-slot pitch-slot--${reparto(slot)}`} style={{ left: `${x}%`, top: `${100 - y}%` }} key={`${slot}-${index}`}><CartaCampo player={player} imageUrl={imageUrls[player?.id ?? 0]} position={slot} ruolo={ruoli?.[index] ?? null} selected={selected?.zone === 'starter' && selected.index === index} onClick={player ? (event) => handlePlayerClick(event, location, player) : () => selected ? selectEmptyStarter(index) : setSceltaPosto(index)} /></div>
                  })}
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
      {sceltaPosto !== null && (() => {
        const posto = slots[sceltaPosto]
        // Chi puo' entrare: panchina e tribuna. Ordine: prima l'affinita' col
        // ruolo (naturale, adattato, fuori ruolo), poi l'overall che avrebbe
        // in quel posto; gli indisponibili in fondo, non selezionabili.
        const ordineFit: Record<PositionFit, number> = { natural: 0, adapted: 1, out: 2 }
        const candidati = [
          ...panchina.map((id, index) => ({ id, location: { zone: 'bench', index, id } as PlayerLocation })),
          ...tribuna.map((id, index) => ({ id, location: { zone: 'tribuna', index, id } as PlayerLocation })),
        ].flatMap((c) => {
          const player = players.find((item) => item.id === c.id)
          return player ? [{ ...c, player, fit: positionFit(posto, player.posizioni), efficace: overallInCampo(player, posto), fuori: indisponibile(player) }] : []
        }).sort((a, b) => Number(a.fuori) - Number(b.fuori) || ordineFit[a.fit] - ordineFit[b.fit] || b.efficace - a.efficace || b.player.overall_corrente - a.player.overall_corrente)
        const etichettaFit: Record<PositionFit, string> = { natural: 'Nel suo ruolo', adapted: 'Adattato', out: 'Fuori ruolo' }
        return <div className={`scelta-titolare-layer formazione-broadcast formazione-broadcast--${fase}`} role="presentation" onPointerDown={(event) => { if (event.target === event.currentTarget) setSceltaPosto(null) }}>
          <section className="scelta-titolare" role="dialog" aria-label={`Scegli il titolare per ${posto}`}>
            <header>
              <div><small>Posto libero</small><strong>Chi gioca <i className={`rosa-card__ruolo--${reparto(posto)}`}>{posto}</i>?</strong></div>
              <button className="button-icona" type="button" onClick={() => setSceltaPosto(null)} aria-label="Chiudi"><Icona nome="chiudi" /></button>
            </header>
            {candidati.length === 0 ? <p className="scelta-titolare__vuoto">Nessun giocatore in panchina o in tribuna.</p>
              : <ul>{candidati.map((c) => <li key={c.id}>
                <button type="button" disabled={c.fuori} onClick={() => mettiTitolare(sceltaPosto, c.location)}>
                  <span className="scelta-titolare__foto">{imageUrls[c.id] ? <img src={imageUrls[c.id]} alt="" /> : <b>{c.player.nome.charAt(0)}</b>}</span>
                  <span className="scelta-titolare__nome">
                    <span className="scelta-titolare__testa">
                      <strong><TestoAdattato minimo={0.6}>{cognome(c.player.nome)}</TestoAdattato></strong>
                      {/* L'energia si vede sempre: pastiglia accanto al nome, mai troncata. */}
                      <em className={`scelta-titolare__energia energia--${livelloEnergia(c.player)}`}>
                        {c.player.infortunato_fino_a > 0 ? 'Infortunato' : c.player.squalificato_fino_a > 0 ? 'Squalificato' : `${c.player.condizione}%`}
                      </em>
                    </span>
                    {/* Ruolo primario in evidenza nel colore del reparto, poi i secondari. */}
                    <small>
                      <i className={`scelta-titolare__primario scelta-titolare__primario--${reparto(c.player.posizioni[0] ?? posto)}`}>{c.player.posizioni[0]}</i>
                      {c.player.posizioni.slice(1).map((pos) => <span key={pos}> · {pos}</span>)}
                    </small>
                  </span>
                  <span className={`scelta-titolare__fit scelta-titolare__fit--${c.fit}`}>{etichettaFit[c.fit]}</span>
                  <span className="scelta-titolare__ovr"><b className={c.efficace < c.player.overall_corrente ? 'is-ridotto' : undefined}>{c.efficace}</b>{c.efficace !== c.player.overall_corrente && <small>{c.player.overall_corrente}</small>}</span>
                </button>
              </li>)}</ul>}
          </section>
        </div>
      })()}
      {chiediNomeRiserva && <DialogoNomeRiserva nomeIniziale={nomeRiserva} classe={`formazione-broadcast formazione-broadcast--${fase}`} onAnnulla={() => setChiediNomeRiserva(false)}
        onConferma={(nome) => { setChiediNomeRiserva(false); setNomeRiserva(nome); void save(nome) }} />}
      {playerAction && <div className="player-action-layer" role="presentation" onPointerDown={(event) => { if (event.target === event.currentTarget) setPlayerAction(null) }}>
        <section className="player-action-menu" role="dialog" aria-label={`Azioni per ${playerAction.player.nome}`} style={{ left: playerAction.x, top: playerAction.y }}>
          <div className="player-action-menu__player">
            <span className={`player-action-menu__photo player-action-menu__photo--${reparto(playerAction.player.posizioni[0] ?? 'ATT')} has-photo`}><AnonymousPlayer /><img src={imageUrls[playerAction.player.id]} alt="" onError={(event) => { event.currentTarget.hidden = true; event.currentTarget.parentElement?.classList.remove('has-photo') }} /></span>
            <div><strong>{playerAction.player.nome}</strong><small>{playerAction.player.posizioni.join(' · ')} · OVR {playerAction.player.overall_corrente}</small></div>
            <button type="button" onClick={() => setPlayerAction(null)} aria-label="Chiudi menu"><Icona nome="chiudi" /></button>
          </div>
          <div className="player-action-menu__choices">
            <button type="button" onClick={() => { const location = playerAction.location; setPlayerAction(null); selectPlayer(location) }}><span>⇄</span><strong>Sostituzione</strong></button>
            <button type="button" onClick={() => { const player = playerAction.player; setPlayerAction(null); setDetailPlayer(player) }}><span>ⓘ</span><strong>Dettagli</strong></button>
          </div>
        </section>
      </div>}
      {detailPlayer && <SchedaGiocatore
        fase={fase}
        tatticheAttive={Boolean(league.tattiche_attive)}
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
          squalificatoFinoA: detailPlayer.squalificato_fino_a,
          ritiroAnnunciato: detailPlayer.ritiro_annunciato,
          attributi: detailPlayer.attributi,
        }}
        fotoUrl={imageUrls[detailPlayer.id]}
        onClose={() => setDetailPlayer(null)}
      />}
      {ftsgInfoOpen && <div className="popup-spiegazione-sfondo" role="presentation" onPointerDown={(event) => { if (event.target === event.currentTarget) setFtsgInfoOpen(false) }}>
        <div className="popup-spiegazione" role="dialog" aria-modal="true" aria-label="Indice FTSG">
          <h2>Indice FTSG</h2>
          <div className="popup-spiegazione__corpo">
            <p><strong>Familiarità tattiche e stile di gioco.</strong> La percentuale al centro è la media
              tra quanto la squadra conosce il modulo scelto ora (metà viola) e quanto conosce lo stile di
              gioco scelto ora (metà turchese).</p>
            <p>Ogni partita giocata vale <strong>+20%</strong> di familiarità con quel modulo e quello
              stile. Cambiarne anche solo uno per una giornata fa scendere l'indice: un modulo nuovo insieme
              a uno stile nuovo equivalgono a 0%.</p>
            <p>Modulo <strong>{Math.round(ftsgModuloPct)}%</strong> · Stile di gioco <strong>{Math.round(ftsgStilePct)}%</strong></p>
          </div>
          <button className="button button--primary" type="button" onClick={() => setFtsgInfoOpen(false)}>Ho capito</button>
        </div>
      </div>}
    </main>
  )
}

// La forma di un modulo in undici puntini, nel menu dei moduli: si riconosce a
// colpo d'occhio, come nella scelta della formazione di EA FC.
function MiniModulo({ slots }: { slots: string[] }) {
  return (
    <span className="mini-modulo" aria-hidden="true">
      {schieramentoInCampo(slots).map((p) => (
        <i key={p.index} className={`mini-modulo__punto mini-modulo__punto--${reparto(p.slot)}`} style={{ left: `${p.x}%`, top: `${100 - p.y}%` }} />
      ))}
    </span>
  )
}
