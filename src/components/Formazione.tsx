import { useEffect, useState, type CSSProperties, type MouseEvent as ReactMouseEvent } from 'react'
import { supabase } from '../lib/supabase'
import type { League, Membership } from '../types'
import { GameNav } from './GameNav'
import type { GameView } from './GameNav'

const MODULI: Record<string, string[]> = {
  '4-3-3': ['GK', 'LB', 'CB', 'CB', 'RB', 'CM', 'CM', 'CM', 'LW', 'ST', 'RW'],
  '4-4-2': ['GK', 'LB', 'CB', 'CB', 'RB', 'LM', 'CM', 'CM', 'RM', 'ST', 'ST'],
  '4-2-3-1': ['GK', 'LB', 'CB', 'CB', 'RB', 'CDM', 'CDM', 'CAM', 'LW', 'RW', 'ST'],
  '3-5-2': ['GK', 'CB', 'CB', 'CB', 'LWB', 'CM', 'CM', 'CM', 'RWB', 'ST', 'ST'],
  '3-4-3': ['GK', 'CB', 'CB', 'CB', 'LM', 'CM', 'CM', 'RM', 'LW', 'ST', 'RW'],
  '5-3-2': ['GK', 'LB', 'CB', 'CB', 'CB', 'RB', 'CM', 'CM', 'CM', 'ST', 'ST'],
  '4-2-4': ['GK', 'LB', 'CB', 'CB', 'RB', 'CM', 'CM', 'LW', 'ST', 'ST', 'RW'],
}

const MODULO_DESCRIZIONI: Record<string, string> = {
  '4-3-3': '4 dif · 3 cen · 3 att',
  '4-4-2': '4 dif · 4 cen · 2 att',
  '4-2-3-1': '4 dif · 2 med · 3 treq · 1 att',
  '3-5-2': '3 dif · 5 cen · 2 att',
  '3-4-3': '3 dif · 4 cen · 3 att',
  '5-3-2': '5 dif · 3 cen · 2 att',
  '4-2-4': '4 dif · 2 cen · 4 att',
}

type PlayerStats = Record<string, number | null>
type Player = { id: number; fc_id: number; nome: string; club: string; nazionalita: string | null; overall_corrente: number; eta_corrente: number; posizioni: string[]; piede: string | null; altezza: number | null; condizione: number; infortunato_fino_a: number; attributi: PlayerStats; foto_url: string | null }
type SavedLineup = { modulo: string; titolari: number[]; panchina: number[]; tribuna: number[] }

type FormazioneProps = { membership: Membership; onNavigate: (view: GameView) => void }
type PlayerZone = 'starter' | 'bench' | 'tribuna'
type PlayerLocation = { zone: PlayerZone; index: number; id: number }
type PlayerAction = { player: Player; location: PlayerLocation; position: string; x: number; y: number }

type PlayerPortraitProps = {
  player?: Player
  imageUrl?: string
  position: string
  selected?: boolean
  onClick: (event: ReactMouseEvent<HTMLButtonElement>) => void
  compact?: boolean
}

type PositionFit = 'natural' | 'adapted' | 'out'

const STAT_LABELS: Array<[string, string]> = [
  ['pace', 'Velocità'], ['shooting', 'Tiro'], ['passing', 'Passaggio'], ['dribbling_generale', 'Dribbling'], ['defending', 'Difesa'], ['physic', 'Fisico'],
  ['stamina', 'Resistenza'], ['finishing', 'Finalizzazione'], ['short_passing', 'Passaggi corti'], ['standing_tackle', 'Contrasti'],
  ['gk_diving', 'Tuffo'], ['gk_handling', 'Presa'], ['gk_kicking', 'Rinvio'], ['gk_positioning', 'Posizionamento'], ['gk_reflexes', 'Riflessi'],
]

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

function eaPortraitUrl(fcId?: number) {
  return fcId ? `https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p${fcId}.png?padding=0.7` : undefined
}

function AnonymousPlayer() {
  return <span className="anonymous-player" aria-hidden="true"><svg viewBox="0 0 100 110" focusable="false"><circle cx="50" cy="33" r="22" /><path d="M12 108c2-31 16-48 38-48s36 17 38 48H12Z" /></svg></span>
}

function PlayerPortrait({ player, imageUrl, position, selected = false, onClick, compact = false }: PlayerPortraitProps) {
  const fit = player ? positionFit(position, player.posizioni) : 'natural'
  return <button className={`lineup-player ${compact ? 'lineup-player--compact' : ''} ${selected ? 'is-selected' : ''}`} type="button" onClick={onClick} aria-label={`${player?.nome ?? 'Slot vuoto'}, ${position}, overall ${player?.overall_corrente ?? 'non disponibile'}`}>
    <span className={`lineup-player__portrait lineup-player__portrait--${reparto(position)} ${imageUrl ? 'has-photo' : ''}`}>
      <AnonymousPlayer />
      {imageUrl && <img src={imageUrl} alt="" onError={(event) => { event.currentTarget.hidden = true; event.currentTarget.parentElement?.classList.remove('has-photo') }} />}
      {fit !== 'natural' && <i className={`position-warning position-warning--${fit}`} title={fit === 'adapted' ? 'Giocatore adattato in un ruolo vicino' : 'Giocatore completamente fuori posizione'} aria-label={fit === 'adapted' ? 'Fuori posizione di poco' : 'Completamente fuori posizione'}>!</i>}
    </span>
    <span className="lineup-player__plate">
      <span className={`lineup-player__position lineup-player__position--${reparto(position)}`}>{position}</span>
      <strong>{player?.nome ?? 'Seleziona'}</strong>
      <b>{player?.overall_corrente ?? '—'}</b>
    </span>
  </button>
}

export function Formazione({ membership, onNavigate }: FormazioneProps) {
  const league = membership.league as League
  const [players, setPlayers] = useState<Player[]>([])
  const [imageUrls, setImageUrls] = useState<Record<number, string>>({})
  const [modulo, setModulo] = useState('4-3-3')
  const [moduleMenuOpen, setModuleMenuOpen] = useState(false)
  const [titolari, setTitolari] = useState<number[]>([])
  const [panchina, setPanchina] = useState<number[]>([])
  const [tribuna, setTribuna] = useState<number[]>([])
  const [selected, setSelected] = useState<PlayerLocation | null>(null)
  const [openZone, setOpenZone] = useState<PlayerZone | null>('bench')
  const [detailPlayer, setDetailPlayer] = useState<Player | null>(null)
  const [playerAction, setPlayerAction] = useState<PlayerAction | null>(null)
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [saved, setSaved] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const giornata = 1

  useEffect(() => {
    if (!detailPlayer && !playerAction) return
    const closeOnEscape = (event: KeyboardEvent) => { if (event.key === 'Escape') { setDetailPlayer(null); setPlayerAction(null) } }
    document.addEventListener('keydown', closeOnEscape)
    const previousOverflow = document.body.style.overflow
    if (detailPlayer) document.body.style.overflow = 'hidden'
    return () => { document.removeEventListener('keydown', closeOnEscape); document.body.style.overflow = previousOverflow }
  }, [detailPlayer, playerAction])

  useEffect(() => {
    let active = true
    async function load() {
      const { data: instances, error: rosterError } = await supabase
        .from('player_instances')
        .select('id, overall_corrente, eta_corrente, condizione, infortunato_fino_a, player_id')
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
      const { data: lineup } = await supabase.from('lineups').select('modulo, titolari, panchina, tribuna').eq('team_id', membership.id).eq('giornata', giornata).maybeSingle()
      if (lineup) {
        const current = lineup as SavedLineup
        setModulo(current.modulo); setTitolari(current.titolari); setPanchina(current.panchina); setTribuna(current.tribuna)
      } else {
        const keeper = loaded.find((player) => player.posizioni[0] === 'GK') ?? loaded[0]
        const starters = [keeper, ...loaded.filter((player) => player.id !== keeper?.id).slice(0, 10)].map((player) => player.id)
        const bench = loaded.filter((player) => !starters.includes(player.id)).slice(0, 9).map((player) => player.id)
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
              : [['GK'], ['LB', 'CB', 'RB', 'LWB', 'RWB'], ['CDM', 'CM', 'CAM', 'LM', 'RM'], ['LW', 'RW', 'ST', 'CF']]
  const rows = rowGroups.map((group) => slots
    .map((slot, index) => ({ slot, index }))
    .filter((item) => group.includes(item.slot))
    .sort((left, right) => group.indexOf(left.slot) - group.indexOf(right.slot)))
    .reverse()
  const locations: Record<PlayerZone, PlayerLocation[]> = {
    starter: titolari.map((id, index) => ({ zone: 'starter', index, id })),
    bench: panchina.map((id, index) => ({ zone: 'bench', index, id })),
    tribuna: tribuna.map((id, index) => ({ zone: 'tribuna', index, id })),
  }
  const visibleLocations = openZone ? [...locations[openZone]].sort((left, right) => {
    if (openZone === 'starter') return left.index - right.index
    const leftPlayer = players.find((player) => player.id === left.id)
    const rightPlayer = players.find((player) => player.id === right.id)
    const roleDifference = REPARTO_ORDINE[reparto(leftPlayer?.posizioni[0] ?? 'ATT')] - REPARTO_ORDINE[reparto(rightPlayer?.posizioni[0] ?? 'ATT')]
    if (roleDifference !== 0) return roleDifference
    const overallDifference = (rightPlayer?.overall_corrente ?? 0) - (leftPlayer?.overall_corrente ?? 0)
    if (overallDifference !== 0) return overallDifference
    return (leftPlayer?.nome ?? '').localeCompare(rightPlayer?.nome ?? '', 'it')
  }) : []
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
      setSelected(location)
      setOpenZone(location.zone === 'starter' ? 'bench' : 'starter')
      return
    }
    if (selected.zone === location.zone && selected.index === location.index) { setSelected(null); return }
    const firstId = playerAt(selected)
    const secondId = playerAt(location)
    setPlayerAt(selected, secondId)
    setPlayerAt(location, firstId)
    setSelected(null)
  }

  function handlePlayerClick(event: ReactMouseEvent<HTMLButtonElement>, location: PlayerLocation, player: Player | undefined, position: string) {
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
    setPlayerAction({ player, location, position, x, y })
  }

  async function save() {
    setSaving(true); setSaved(false); setError(null)
    const cleanBench = panchina.filter((id) => !titolari.includes(id)).slice(0, 9)
    const { error: saveError } = await supabase.rpc('salva_formazione', {
      p_league_id: league.id, p_giornata: giornata, p_modulo: modulo,
      p_titolari: titolari, p_panchina: cleanBench, p_tribuna: tribuna,
    })
    if (saveError) setError(saveError.message)
    else { setPanchina(cleanBench); setSaved(true) }
    setSaving(false)
  }

  function chooseModule(nextModule: string) {
    setModulo(nextModule)
    setSaved(false)
    setSelected(null)
    setPlayerAction(null)
    setModuleMenuOpen(false)
  }

  if (loading) return <main className="loading-screen"><span className="loading-mark">S1</span><p>Preparo la formazione…</p></main>

  return (
    <main className="app-shell formation-shell">
      <GameNav league={league} active="squad" onNavigate={onNavigate} />
      <header className="topbar"><div className="brand-lockup brand-lockup--dark"><img src="/specialone-mark.svg" alt="" /><span>SpecialOne</span></div><span className="kicker">Giornata {giornata}</span></header>
      <section className="formation-hero"><p className="kicker">La tua distinta · {league.nome}</p><h1>Schiera la squadra.</h1><p>Scegli il modulo e assegna i giocatori slot per slot. Il server controlla rosa, indisponibilità e duplicati prima del salvataggio.</p></section>
      {error && <p className="notice notice--error" role="alert">{error}</p>}
      {players.length < 11 ? <section className="formation-panel"><h2>Rosa incompleta</h2><p>Servono almeno 11 giocatori prima di poter salvare una formazione.</p></section> : (
        <section className="formation-panel formation-panel--tactical">
          <div className="formation-toolbar">
            <div className="formation-module-selector">
              <p className="kicker">Modulo tattico</p>
              <button className="formation-module-trigger" type="button" aria-haspopup="listbox" aria-expanded={moduleMenuOpen} onClick={() => setModuleMenuOpen((open) => !open)}><strong>{modulo}</strong><span>{moduleMenuOpen ? '×' : '⌄'}</span></button>
              {moduleMenuOpen && <><button className="formation-module-scrim" type="button" aria-label="Chiudi selezione modulo" onClick={() => setModuleMenuOpen(false)} /><div className="formation-module-menu" role="listbox" aria-label="Scegli il modulo">{Object.keys(MODULI).map((name) => <button className={name === modulo ? 'is-active' : ''} type="button" role="option" aria-selected={name === modulo} key={name} onClick={() => chooseModule(name)}><strong>{name}</strong><small>{MODULO_DESCRIZIONI[name]}</small><span>{name === modulo ? '✓' : '›'}</span></button>)}</div></>}
            </div>
          </div>
          <div className={`formation-swapper ${selected ? 'has-selection' : ''}`}>
            <div className="formation-swapper__status">
              <span>{selected ? 'Sostituisci' : 'Gestione rosa'}</span>
              <strong>{selectedPlayer ? selectedPlayer.nome : 'Seleziona un giocatore'}</strong>
              <small>{selected ? 'Ora tocca il giocatore con cui vuoi scambiarlo.' : 'Tocca un giocatore per sostituirlo o vedere i dettagli.'}</small>
            </div>
            <div className="formation-zone-tabs" role="tablist" aria-label="Gruppi della formazione">
              {([['starter', 'Titolari'], ['bench', 'Panchina'], ['tribuna', 'Tribuna']] as const).map(([zone, label]) => <button className={openZone === zone ? 'is-active' : ''} type="button" role="tab" aria-selected={openZone === zone} aria-expanded={openZone === zone} key={zone} onClick={() => setOpenZone((current) => current === zone ? null : zone)}><span>{label}</span><b>{locations[zone].length}</b><i>{openZone === zone ? '−' : '+'}</i></button>)}
            </div>
            {openZone && <div className="formation-player-tray" role="tabpanel">
              {visibleLocations.filter((location) => !(selected?.zone === location.zone && selected.index === location.index)).map((location) => {
                const player = players.find((item) => item.id === location.id)
                const position = location.zone === 'starter' ? slots[location.index] : player?.posizioni[0] ?? '—'
                return <PlayerPortrait compact key={`${location.zone}-${location.index}-${location.id}`} player={player} imageUrl={imageUrls[location.id] ?? eaPortraitUrl(player?.fc_id)} position={position} selected={selected?.zone === location.zone && selected.index === location.index} onClick={(event) => handlePlayerClick(event, location, player, position)} />
              })}
            </div>}
          </div>
          <div className="formation-poster-heading"><span>Dream Team</span><small>{league.nome} · Giornata {giornata}</small></div>
          <div className="pitch-field" aria-label={`Campo con modulo ${modulo}`}>
            <div className="pitch-field__line pitch-field__line--half" />
            <div className="pitch-field__circle" />
            <div className="pitch-field__box pitch-field__box--top" /><div className="pitch-field__box pitch-field__box--bottom" />
            <div className="pitch-grid">
              {rows.map((row, rowIndex) => <div className={`pitch-row pitch-row--${rowIndex}`} style={{ '--row-count': row.length } as CSSProperties} key={rowIndex}>{row.map(({ slot, index }) => { const player = players.find((item) => item.id === titolari[index]); const location = { zone: 'starter', index, id: titolari[index] ?? 0 } as PlayerLocation; return <div className={`pitch-slot pitch-slot--${reparto(slot)}`} key={`${slot}-${index}`}><PlayerPortrait player={player} imageUrl={imageUrls[player?.id ?? 0] ?? eaPortraitUrl(player?.fc_id)} position={slot} selected={selected?.zone === 'starter' && selected.index === index} onClick={(event) => handlePlayerClick(event, location, player, slot)} /></div> })}</div>)}
            </div>
          </div>
          <div className="role-legend"><span><i className="role-bar role-bar--GK" />Portiere</span><span><i className="role-bar role-bar--DEF" />Difensori</span><span><i className="role-bar role-bar--MID" />Centrocampisti</span><span><i className="role-bar role-bar--ATT" />Attaccanti</span></div>
          <div className="formation-footer"><span>{saved ? 'Formazione salvata' : `${titolari.length} titolari · ${panchina.length} panchina · ${tribuna.length} tribuna`}</span><button className="button button--primary" type="button" disabled={saving} onClick={save}>{saving ? 'Salvataggio…' : 'Salva formazione'}</button></div>
        </section>
      )}
      {playerAction && <div className="player-action-layer" role="presentation" onPointerDown={(event) => { if (event.target === event.currentTarget) setPlayerAction(null) }}>
        <section className="player-action-menu" role="dialog" aria-label={`Azioni per ${playerAction.player.nome}`} style={{ left: playerAction.x, top: playerAction.y }}>
          <div className="player-action-menu__player">
            <span className={`player-action-menu__photo player-action-menu__photo--${reparto(playerAction.position)} has-photo`}><AnonymousPlayer /><img src={imageUrls[playerAction.player.id] ?? eaPortraitUrl(playerAction.player.fc_id)} alt="" onError={(event) => { event.currentTarget.hidden = true; event.currentTarget.parentElement?.classList.remove('has-photo') }} /></span>
            <div><strong>{playerAction.player.nome}</strong><small>{playerAction.player.posizioni.join(' · ')} · OVR {playerAction.player.overall_corrente}</small></div>
            <button type="button" onClick={() => setPlayerAction(null)} aria-label="Chiudi menu">×</button>
          </div>
          <div className="player-action-menu__choices">
            <button type="button" onClick={() => { const location = playerAction.location; setPlayerAction(null); selectPlayer(location) }}><span>⇄</span><strong>Sostituzione</strong></button>
            <button type="button" onClick={() => { const player = playerAction.player; setPlayerAction(null); setDetailPlayer(player) }}><span>ⓘ</span><strong>Dettagli</strong></button>
          </div>
        </section>
      </div>}
      {detailPlayer && <div className="player-modal-backdrop" role="presentation" onPointerDown={(event) => { if (event.target === event.currentTarget) setDetailPlayer(null) }}>
        <section className="player-modal" role="dialog" aria-modal="true" aria-labelledby="player-modal-title">
          <button className="player-modal__close" type="button" onClick={() => setDetailPlayer(null)} aria-label="Chiudi dettagli giocatore">×</button>
          <div className="player-modal__hero">
            <div className={`player-modal__photo player-modal__photo--${reparto(detailPlayer.posizioni[0] ?? 'ATT')} has-photo`}><AnonymousPlayer /><img src={imageUrls[detailPlayer.id] ?? eaPortraitUrl(detailPlayer.fc_id)} alt={detailPlayer.nome} onError={(event) => { event.currentTarget.hidden = true; event.currentTarget.parentElement?.classList.remove('has-photo') }} /></div>
            <div><p className="kicker">Scheda giocatore</p><h2 id="player-modal-title">{detailPlayer.nome}</h2><p>{detailPlayer.club}{detailPlayer.nazionalita ? ` · ${detailPlayer.nazionalita}` : ''}</p></div>
            <strong className="player-modal__overall"><span>OVR</span>{detailPlayer.overall_corrente}</strong>
          </div>
          <dl className="player-modal__facts"><div><dt>Età</dt><dd>{detailPlayer.eta_corrente}</dd></div><div><dt>Ruoli</dt><dd>{detailPlayer.posizioni.join(' · ')}</dd></div><div><dt>Piede</dt><dd>{detailPlayer.piede ?? '—'}</dd></div><div><dt>Altezza</dt><dd>{detailPlayer.altezza ? `${detailPlayer.altezza} cm` : '—'}</dd></div><div><dt>Condizione</dt><dd>{detailPlayer.condizione}%</dd></div></dl>
          <div className="player-modal__stats"><h3>Statistiche</h3><div className="player-stats-grid">{STAT_LABELS.map(([key, label]) => { const value = detailPlayer.attributi[key]; return typeof value === 'number' ? <div className="player-stat" key={key}><span>{label}</span><b>{value}</b><i><span style={{ width: `${value}%` }} /></i></div> : null })}</div></div>
        </section>
      </div>}
    </main>
  )
}
