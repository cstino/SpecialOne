import type { CSSProperties } from 'react'
import type { useSeasonData } from '../lib/useSeasonData'
import { urlFotoGiocatore } from '../lib/fotoGiocatore'
import { cognome } from '../lib/nomi'
import { macroRuolo, ruoloIt } from '../lib/ruoli'
import { stemmaPresetDaValore } from '../lib/teamCrests'
import { useColoriStemma, COLORI_PREDEFINITI } from '../lib/coloriStemma'
import { bandiera } from '../lib/bandiere'

// Figurina in stile card FUT (Season 3, docs/DIARIO-SEASON3.md §8-9): sagoma a scudo, sfondo nei colori dello stemma
// della squadra SpecialOne, overall e ruolo in alto a sinistra, foto scontornata, nome, sei statistiche, bandiera e
// stemma della squadra. La rarita' si vede dalla cornice: argento, oro, oro olografico, iridescente.

export type Versione = 'common' | 'rare' | 'ultra' | 'ultimate'
export type Figurina = { id: number; tipo: 'stemma' | 'giocatore' | 'conferenza'; team_id: number | null; player_id: number | null; conferenza: 'est' | 'ovest' | null; overall: number | null; aggiornamento: boolean }
export type Statistiche = Partial<Record<'pace' | 'shooting' | 'passing' | 'dribbling_generale' | 'defending' | 'physic' | 'gk_diving' | 'gk_handling' | 'gk_kicking' | 'gk_reflexes' | 'goalkeeping_speed' | 'gk_positioning', number | null>>
export type Anagrafica = { id: number; nome: string; posizioni: string[]; foto_url: string | null; foto_figurina: string | null; nazionalita: string | null } & Statistiche
type Dati = ReturnType<typeof useSeasonData>

const STAT_GIOCATORE: Array<[keyof Statistiche, string]> = [['pace', 'RIT'], ['shooting', 'TIR'], ['passing', 'PAS'], ['dribbling_generale', 'DRI'], ['defending', 'DIF'], ['physic', 'FIS']]
const STAT_PORTIERE: Array<[keyof Statistiche, string]> = [['gk_diving', 'TUF'], ['gk_handling', 'PRE'], ['gk_kicking', 'RIN'], ['gk_reflexes', 'RIF'], ['goalkeeping_speed', 'VEL'], ['gk_positioning', 'POS']]
const NOME_VERSIONE: Record<Versione, string> = { common: 'common', rare: 'rara', ultra: 'ultrarara', ultimate: 'ultimate' }

export function urlStemma(dati: Dati, teamId: number | null | undefined): string | undefined {
  if (teamId == null) return undefined
  const team = dati.teamById.get(teamId)
  return dati.crestUrlByTeamId.get(teamId) ?? stemmaPresetDaValore(team?.stemma_url ?? null)?.src
}

type Props = { f: Figurina; ana?: Anagrafica; dati: Dati; versione: Versione; vuota?: boolean; numero?: number; piccola?: boolean }

export function Carta({ f, ana, dati, versione, vuota, numero, piccola }: Props) {
  const team = f.team_id != null ? dati.teamById.get(f.team_id) : undefined
  const stemma = urlStemma(dati, f.team_id)
  const coloriSquadra = useColoriStemma(f.tipo === 'conferenza' ? undefined : stemma)
  const colori = f.tipo === 'conferenza' ? { primo: '#4a2a86', secondo: '#0a0614', chiaro: false } : coloriSquadra ?? COLORI_PREDEFINITI
  const speciale = versione === 'ultra' || versione === 'ultimate'
  const stile = { '--fut-c1': colori.primo, '--fut-c2': colori.secondo, '--fut-testo': colori.chiaro ? '#1d1608' : '#fff4d8' } as CSSProperties
  const classe = `fut fut--${versione} fut--${f.tipo}${piccola ? ' fut--piccola' : ''}${colori.chiaro ? ' fut--chiara' : ''}`

  if (vuota) return <div className="fut fut--vuota" aria-label={`Figurina ${numero ?? ''} mancante`}><span className="fut__vuota-num">{numero}</span></div>

  const effetti = <>
    <span className="fut__lucido" aria-hidden="true" />
    {speciale && <><span className="fut__olo" aria-hidden="true" /><span className="fut__scintille" aria-hidden="true"><i /><i /><i /><i /><i /></span></>}
    {numero != null && <span className="fut__num" aria-hidden="true">{numero}</span>}
  </>
  const fondo = <div className="fut__fondo" aria-hidden="true">
    <i className="fut__righe" /><i className="fut__luce" />
    {stemma && f.tipo === 'giocatore' && <img className="fut__filigrana" src={stemma} alt="" />}
  </div>

  if (f.tipo === 'conferenza') {
    const est = f.conferenza === 'est'
    return <div className={classe} style={stile} aria-label={`Figurina ${NOME_VERSIONE[versione]} ${est ? 'Eastern' : 'Western'} Conference`}>
      {fondo}
      <div className="fut__centro"><img src={est ? '/loghi-conferenza/east.svg' : '/loghi-conferenza/west.svg'} alt="" /></div>
      <div className="fut__basso fut__basso--solo-nome"><strong>{est ? 'Eastern' : 'Western'}</strong><small>Conference</small></div>
      {effetti}
    </div>
  }
  if (f.tipo === 'stemma') {
    return <div className={classe} style={stile} aria-label={`Stemma ${team?.nome ?? ''}`}>
      {fondo}
      <div className="fut__centro">{stemma && <img src={stemma} alt="" />}</div>
      <div className="fut__basso fut__basso--solo-nome"><strong>{team?.nome ?? '—'}</strong><small>Stemma ufficiale</small></div>
      {effetti}
    </div>
  }

  const portiere = macroRuolo(ana?.posizioni ?? []) === 'GK'
  const foto = urlFotoGiocatore(ana?.foto_figurina ?? ana?.foto_url)
  const flag = bandiera(ana?.nazionalita)
  return <div className={`${classe}${ana?.foto_figurina ? ' fut--scontornata' : ''}`} style={stile}
    aria-label={`${ana?.nome ?? 'Giocatore'}, ${f.overall ?? ''} di overall, figurina ${NOME_VERSIONE[versione]}`}>
    {fondo}
    <div className="fut__alto"><b>{f.overall ?? ''}</b><span>{ruoloIt(ana?.posizioni?.[0] ?? '')}</span></div>
    <div className="fut__foto">{foto ? <img src={foto} alt="" loading="lazy" /> : null}</div>
    <div className="fut__basso">
      <strong>{ana ? cognome(ana.nome) : '—'}</strong>
      <dl className="fut__stat">
        {(portiere ? STAT_PORTIERE : STAT_GIOCATORE).map(([chiave, etichetta]) => <div key={chiave}><dt>{etichetta}</dt><dd>{ana?.[chiave] ?? '–'}</dd></div>)}
      </dl>
      <div className="fut__id">
        {flag && <span className="fut__bandiera" title={ana?.nazionalita ?? ''}>{flag}</span>}
        {stemma && <img className="fut__stemma" src={stemma} alt={team?.nome ?? ''} />}
      </div>
    </div>
    {f.aggiornamento && <em className="fut__agg">AGG.</em>}
    {effetti}
  </div>
}
