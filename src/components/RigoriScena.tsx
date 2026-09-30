import { cognome } from '../lib/nomi'
import type { RigoreTiro } from '../types'
import { Crest } from './Crest'

export type FaseRigore = 'intro' | 'rincorsa' | 'tiro' | 'esito'

type Giocatore = { nome: string; foto?: string }
type SquadraScena = { nome: string; stemma: string | null; stemmaUrl?: string | null }

type Props = {
  serie: RigoreTiro[]
  // Il rigore in scena: uguale a serie.length quando la serie e' conclusa.
  indice: number
  fase: FaseRigore
  seed: number
  casa: SquadraScena
  ospite: SquadraScena
  giocatori: Map<number, Giocatore>
  portiereCasa: number | null
  portiereOspite: number | null
}

// Il motore salva solo chi tira e se segna. Il "come" (spiazza, para, fuori,
// cucchiaio...) e' pura messa in scena: si ricava da un numero pseudo-casuale
// legato alla partita e al rigore, cosi' rivedendola il rigore e' sempre lo
// stesso e non cambia mai l'esito.
function casuale(seed: number, n: number, sale: number) {
  let x = Math.imul(seed ^ 0x9e3779b9, 0x85ebca6b) ^ Math.imul(n + 1, 0xc2b2ae35) ^ Math.imul(sale + 7, 0x27d4eb2f)
  x = Math.imul(x ^ (x >>> 15), 0x2c1b3c6d)
  x = Math.imul(x ^ (x >>> 12), 0x297a2d39)
  return ((x ^ (x >>> 15)) >>> 0) / 4294967296
}

function scegli<T>(r: number, pesi: Array<[T, number]>): T {
  let resto = r * pesi.reduce((totale, [, peso]) => totale + peso, 0)
  for (const [valore, peso] of pesi) {
    resto -= peso
    if (resto < 0) return valore
  }
  return pesi[pesi.length - 1][0]
}

type Variante = 'spiazza' | 'intuisce' | 'freddezza' | 'cucchiaio' | 'para' | 'fuori' | 'male'

function varianteDi(seed: number, indice: number, segnato: boolean): Variante {
  const r = casuale(seed, indice, 1)
  return segnato
    ? scegli<Variante>(r, [['spiazza', 35], ['intuisce', 30], ['freddezza', 29], ['cucchiaio', 6]])
    : scegli<Variante>(r, [['para', 55], ['fuori', 30], ['male', 15]])
}

// Coordinate in % del riquadro della porta (0,0 = angolo in alto a sinistra).
// `lato` e' da che parte va il pallone: -1 sinistra, +1 destra; `dir` la
// direzione del tuffo del portiere, nello stesso verso.
function traiettoria(variante: Variante, lato: -1 | 1) {
  const x = (scarto: number) => `${50 + lato * scarto}%`
  const tuffo = (dir: number, scarto: number) => ({
    kl: `${50 + dir * scarto}%`,
    kr: `${dir * 68}deg`,
    ky: '-14%',
  })
  switch (variante) {
    case 'spiazza': return { bx: x(35), by: '70%', bs: 0.55, arco: '0%', ...tuffo(-lato, 30) }
    case 'intuisce': return { bx: x(41), by: '66%', bs: 0.55, arco: '0%', ...tuffo(lato, 30) }
    case 'freddezza': return { bx: x(38), by: '16%', bs: 0.5, arco: '0%', ...tuffo(-lato, 28) }
    case 'cucchiaio': return { bx: '50%', by: '30%', bs: 0.52, arco: '-70%', ...tuffo(lato, 28) }
    case 'para': return { bx: x(20), by: '56%', bs: 0.6, arco: '0%', ...tuffo(lato, 22) }
    case 'fuori': return { bx: x(68), by: '26%', bs: 0.45, arco: '0%', ...tuffo(lato, 26) }
    case 'male': return { bx: x(12), by: '-50%', bs: 0.32, arco: '-20%', ...tuffo(-lato, 26) }
  }
}

function testoEsito(variante: Variante, portiere: string, tiratore: string) {
  switch (variante) {
    case 'spiazza': return `Spiazza ${portiere}!`
    case 'intuisce': return `${portiere} intuisce ma non può nulla!`
    case 'freddezza': return 'Che freddezza! Rigore calciato alla perfezione.'
    case 'cucchiaio': return 'Incredibile! Con il cucchiaio!'
    case 'para': return `La para ${portiere}!`
    case 'fuori': return `Termina fuori il tiro di ${tiratore}.`
    case 'male': return 'Ha colpito malissimo il pallone!'
  }
}

function Portiere({ colore }: { colore: string }) {
  return <svg viewBox="0 0 64 84" aria-hidden="true" style={{ ['--maglia' as string]: colore }}>
    <path d="M22 54 L18 80 M42 54 L46 80" stroke="#1b1330" strokeWidth="9" strokeLinecap="round" />
    <path d="M20 28 L6 12 M44 28 L58 12" stroke="var(--maglia)" strokeWidth="8" strokeLinecap="round" />
    <circle cx="5" cy="9" r="6" fill="#f4f1ff" />
    <circle cx="59" cy="9" r="6" fill="#f4f1ff" />
    <rect x="18" y="24" width="28" height="34" rx="11" fill="var(--maglia)" />
    <rect x="18" y="44" width="28" height="14" rx="6" fill="rgba(0,0,0,.18)" />
    <circle cx="32" cy="14" r="9" fill="#f0cfb3" />
    <path d="M23 12 Q32 2 41 12 Q32 8 23 12Z" fill="#2a1d3d" />
  </svg>
}

export function RigoriScena({ serie, indice, fase, seed, casa, ospite, giocatori, portiereCasa, portiereOspite }: Props) {
  const finita = indice >= serie.length
  const tiro = finita ? null : serie[indice]
  const visti = serie.slice(0, finita ? serie.length : indice + (fase === 'esito' ? 1 : 0))
  const punti = (lato: 'casa' | 'ospite') => visti.filter((item) => item.lato === lato && item.segnato).length
  const ultimo = !finita && indice === serie.length - 1
  // Il pallone parte in 'tiro' e l'esito (testo, pallini, punteggio) si svela
  // solo dopo, in 'esito': rincorsa e tiro condividono lo stesso testo.
  const inVolo = fase === 'tiro' || fase === 'esito'
  const faseTesto = fase === 'tiro' ? 'rincorsa' : fase

  const variante = tiro ? varianteDi(seed, indice, tiro.segnato) : null
  const latoPalla: -1 | 1 = casuale(seed, indice, 2) < 0.5 ? -1 : 1
  const percorso = variante ? traiettoria(variante, latoPalla) : null

  const squadraTiro = tiro?.lato === 'casa' ? casa : ospite
  const squadraPorta = tiro?.lato === 'casa' ? ospite : casa
  const idPortiere = tiro?.lato === 'casa' ? portiereOspite : portiereCasa
  const nomePortiere = cognome(giocatori.get(idPortiere ?? -1)?.nome ?? 'il portiere')
  const tiratore = tiro ? giocatori.get(tiro.tiratoreId ?? -1) : undefined
  const nomeTiratore = cognome(tiro?.tiratore ?? tiratore?.nome ?? '—')

  const numeroMassimo = Math.max(5, ...serie.slice(0, indice + 1).map((item) => item.numero))
  const pallini = (lato: 'casa' | 'ospite') => Array.from({ length: numeroMassimo }, (_, i) => {
    const numero = i + 1
    const colpo = serie.find((item) => item.lato === lato && item.numero === numero)
    const stato = colpo && visti.includes(colpo) ? (colpo.segnato ? 'gol' : 'errore')
      : colpo && colpo === tiro ? 'attivo' : 'vuoto'
    return <i className={`rig__pallino is-${stato}`} key={numero}>{stato === 'gol' ? '✓' : stato === 'errore' ? '✕' : ''}</i>
  })

  const riga = (lato: 'casa' | 'ospite', squadra: SquadraScena) => (
    <div className={`rig__squadra ${tiro?.lato === lato ? 'is-attiva' : ''}`}>
      <Crest value={squadra.stemma} imageUrl={squadra.stemmaUrl} size="small" />
      <b>{squadra.nome}</b>
      <div className="rig__pallini">{pallini(lato)}</div>
      <strong key={punti(lato)}>{punti(lato)}</strong>
    </div>
  )

  const esito = fase === 'esito' && tiro ? (tiro.segnato ? 'gol' : 'errore') : null
  const vincitrice = punti('casa') > punti('ospite') ? casa : ospite

  return <div className={`rig ${esito ? `is-${esito}` : ''} ${finita ? 'is-finita' : ''}`} data-fase={finita ? 'fine' : fase}>
    <div className="rig__tabellone">
      {riga('casa', casa)}
      {riga('ospite', ospite)}
    </div>

    <div className="rig__scena">
      <div className="rig__campo">
        <div className="rig__prato" aria-hidden="true"><span className="rig__dischetto" /></div>
        <div className="rig__porta">
          <div className="rig__rete" aria-hidden="true" />
          {percorso && <div
            className={`rig__portiere ${inVolo ? 'is-tuffo' : 'is-attesa'}`}
            style={{ ['--kl' as string]: percorso.kl, ['--kr' as string]: percorso.kr, ['--ky' as string]: percorso.ky }}
          ><Portiere colore={tiro?.lato === 'casa' ? '#3de0b0' : '#ffc94d'} /></div>}
          {!finita && percorso && <span
            key={indice}
            className={`rig__palla ${inVolo ? 'is-tiro' : ''}`}
            style={{ ['--bx' as string]: percorso.bx, ['--by' as string]: percorso.by, ['--bs' as string]: percorso.bs, ['--arco' as string]: percorso.arco }}
          />}
        </div>
        {esito && tiro && <div className="rig__esito" key={`esito-${indice}`}>
          <strong>{tiro.segnato ? 'GOOOL!' : 'SBAGLIA!'}</strong>
        </div>}
        {finita && <div className="rig__finale">
          <small>Vittoria ai rigori</small>
          <Crest value={vincitrice.stemma} imageUrl={vincitrice.stemmaUrl} size="large" />
          <strong>{vincitrice.nome}</strong>
          <b>{punti('casa')}–{punti('ospite')}</b>
        </div>}
      </div>
    </div>

    {tiro && variante && <div className="rig__pannello" key={`${indice}-${faseTesto}`}>
      <div className="rig__foto">
        {tiratore?.foto ? <img src={tiratore.foto} alt="" /> : <span aria-hidden="true">{nomeTiratore.charAt(0)}</span>}
        <Crest value={squadraTiro.stemma} imageUrl={squadraTiro.stemmaUrl} size="small" />
      </div>
      <div className="rig__testi">
        {faseTesto === 'intro' && <>
          <small>{ultimo ? 'Rigore decisivo · è il momento di' : 'È il momento di'}</small>
          <strong>{nomeTiratore}</strong>
          <span>{squadraTiro.nome}</span>
        </>}
        {faseTesto === 'rincorsa' && <>
          <small>{nomeTiratore} · {squadraTiro.nome}</small>
          <strong className="rig__puntini">Parte il tiro<i>.</i><i>.</i><i>.</i></strong>
          <span>Davanti a lui {nomePortiere} ({squadraPorta.nome})</span>
        </>}
        {faseTesto === 'esito' && <>
          <small>{nomeTiratore} · {squadraTiro.nome}</small>
          <strong className={tiro.segnato ? 'is-gol' : 'is-errore'}>{testoEsito(variante, nomePortiere, nomeTiratore)}</strong>
        </>}
      </div>
    </div>}
  </div>
}
