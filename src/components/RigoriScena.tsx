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

export function RigoriScena({ serie, indice, fase, seed, casa, ospite, giocatori, portiereCasa, portiereOspite }: Props) {
  const finita = indice >= serie.length
  const tiro = finita ? null : serie[indice]
  const visti = serie.slice(0, finita ? serie.length : indice + (fase === 'esito' ? 1 : 0))
  const punti = (lato: 'casa' | 'ospite') => visti.filter((item) => item.lato === lato && item.segnato).length
  const ultimo = !finita && indice === serie.length - 1
  // rincorsa e tiro condividono lo stesso testo: la pausa in piu' allunga
  // l'attesa prima dell'esito, che (testo, pallini, punteggio) si svela solo
  // in 'esito'.
  const faseTesto = fase === 'tiro' ? 'rincorsa' : fase

  const variante = tiro ? varianteDi(seed, indice, tiro.segnato) : null

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
      <span className="rig__stemma"><Crest value={squadra.stemma} imageUrl={squadra.stemmaUrl} size="small" /></span>
      <b>{squadra.nome}</b>
      <div className="rig__pallini">{pallini(lato)}</div>
      <strong key={punti(lato)}>{punti(lato)}</strong>
    </div>
  )

  const esito = fase === 'esito' && tiro ? (tiro.segnato ? 'gol' : 'errore') : null
  const vincitrice = punti('casa') > punti('ospite') ? casa : ospite

  return <div className={`rig ${esito ? `is-${esito}` : ''} ${finita ? 'is-finita' : ''}`} data-fase={finita ? 'fine' : faseTesto}>
    <div className="rig__tabellone">
      {riga('casa', casa)}
      {riga('ospite', ospite)}
    </div>

    <div className="rig__palco">
      {tiro && variante && <div className="rig__card" key={indice}>
        <span className="rig__filigrana" aria-hidden="true">{nomeTiratore}</span>
        <p className="rig__numero">{ultimo ? 'Rigore decisivo' : `Rigore n. ${tiro.numero}`}</p>
        <div className="rig__ritratto">
          <div className="rig__foto">
            {tiratore?.foto ? <img src={tiratore.foto} alt="" /> : <span aria-hidden="true">{nomeTiratore.charAt(0)}</span>}
          </div>
          {esito && <div className="rig__banda" key={`banda-${indice}`}><strong>{tiro.segnato ? 'GOOOL!' : 'SBAGLIA!'}</strong></div>}
        </div>
        <div className="rig__testi" key={faseTesto}>
          {faseTesto === 'intro' && <>
            <small>È il momento di</small>
            <strong className="rig__nome">{nomeTiratore}</strong>
          </>}
          {faseTesto === 'rincorsa' && <>
            <small>{nomeTiratore} sul dischetto</small>
            <strong className="rig__nome rig__puntini">Parte il tiro<i>.</i><i>.</i><i>.</i></strong>
          </>}
          {faseTesto === 'esito' && <>
            <small>{nomeTiratore}</small>
            <strong className={`rig__frase is-${esito}`}>{testoEsito(variante, nomePortiere, nomeTiratore)}</strong>
          </>}
        </div>
        <div className="rig__squadra-tiro">
          <span className="rig__stemma"><Crest value={squadraTiro.stemma} imageUrl={squadraTiro.stemmaUrl} size="small" /></span>
          <span>{squadraTiro.nome}</span>
          <em>contro {nomePortiere} · {squadraPorta.nome}</em>
        </div>
        {faseTesto === 'rincorsa' && <div className="rig__attesa" aria-hidden="true"><span /></div>}
      </div>}

      {finita && <div className="rig__finale">
        <small>Vittoria ai rigori</small>
        <span className="rig__stemma rig__stemma--grande"><Crest value={vincitrice.stemma} imageUrl={vincitrice.stemmaUrl} size="large" /></span>
        <strong>{vincitrice.nome}</strong>
        <b>{punti('casa')}–{punti('ospite')}</b>
      </div>}
    </div>
  </div>
}
