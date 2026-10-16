import { useState } from 'react'
import { FaccinaMorale, etichettaMorale, type FasciaMorale } from './FaccinaMorale'

// Il morale di squadra nel sommario del club: un indicatore a mezzaluna e, toccandolo,
// la spiegazione di come incide. Misura i titolari della formazione per la prossima partita, perche' il
// morale conta in campo solo per chi gioca (CLAUDE.md: la media di tutta la rosa e' una metrica
// inutile, meta' dei giocatori non gioca mai); senza formazione salvata, i migliori 11 per overall.
// Solo per la propria squadra: il morale degli altri non si vede.

type Props = { morali: number[]; daFormazione: boolean }

const FASCE: Array<{ classe: FasciaMorale; testo: string; da: string }> = [
  { classe: 'ottimo', testo: 'Entusiasta', da: '80–100' },
  { classe: 'buono', testo: 'Sereno', da: '60–79' },
  { classe: 'medio', testo: 'Insoddisfatto', da: '40–59' },
  { classe: 'basso', testo: 'Scontento', da: '20–39' },
  { classe: 'critico', testo: 'In rotta', da: '0–19' },
]

// L'arco va da 180° a 360° (mezzaluna): 0 = sinistra, 100 = destra.
const R = 78
const C = 100
function punto(valore: number) {
  const a = Math.PI * (1 - valore / 100)
  return { x: C + R * Math.cos(a), y: C - R * Math.sin(a) }
}
function arco(da: number, a: number) {
  const p = punto(da), q = punto(a)
  return `M ${p.x.toFixed(2)} ${p.y.toFixed(2)} A ${R} ${R} 0 0 1 ${q.x.toFixed(2)} ${q.y.toFixed(2)}`
}

export function MoraleSquadra({ morali, daFormazione }: Props) {
  const [aperto, setAperto] = useState(false)
  if (!morali.length) return null
  const media = morali.reduce((a, b) => a + b, 0) / morali.length
  const valore = Math.round(media)
  const { testo, classe } = etichettaMorale(valore)
  const conteggi = FASCE.map((f) => ({ ...f, n: morali.filter((m) => etichettaMorale(m).classe === f.classe).length }))
  const cursore = punto(Math.max(0, Math.min(100, media)))

  return <>
    <button className={`morale-squadra morale-squadra--${classe}`} type="button" onClick={() => setAperto(true)}
      aria-label={`Morale di squadra ${valore} su 100, ${testo}. Tocca per capire come incide.`}>
      <span className="morale-squadra__intestazione">
        <small>Morale di squadra</small>
        <em aria-hidden="true">Come incide ›</em>
      </span>
      <span className="morale-squadra__corpo">
        <svg className="morale-squadra__arco" viewBox="0 0 200 112" aria-hidden="true">
          <defs>
            <linearGradient id="morale-gradiente" x1="0" x2="1" y1="0" y2="0">
              <stop offset="0" stopColor="#ff7188" /><stop offset=".3" stopColor="#ffa06b" />
              <stop offset=".5" stopColor="#f0c44d" /><stop offset=".72" stopColor="#c9a6ff" /><stop offset="1" stopColor="#65e69a" />
            </linearGradient>
          </defs>
          <path className="morale-squadra__binario" d={arco(0, 100)} />
          <path className="morale-squadra__riempimento" d={arco(0, Math.max(0.5, media))} stroke="url(#morale-gradiente)" />
          <circle className="morale-squadra__cursore" cx={cursore.x} cy={cursore.y} r="7" />
        </svg>
        <span className="morale-squadra__valore">
          <FaccinaMorale morale={valore} className="morale-squadra__faccina" />
          <b>{valore}</b>
          <span>{testo}</span>
        </span>
      </span>
      <span className="morale-squadra__fasce" aria-hidden="true">
        {conteggi.map((f) => <i key={f.classe} className={`morale-squadra__fascia morale-squadra__fascia--${f.classe}`} style={{ flexGrow: f.n }} title={`${f.testo}: ${f.n}`} />)}
      </span>
      <small className="morale-squadra__nota">{morali.length} {daFormazione ? 'titolari' : 'giocatori'} considerati · {conteggi.filter((f) => f.n).map((f) => `${f.n} ${f.testo.toLowerCase()}`).join(' · ')}</small>
    </button>

    {aperto && <div className="popup-spiegazione-sfondo" role="dialog" aria-modal="true" aria-label="Come incide il morale di squadra" onClick={() => setAperto(false)}>
      <div className="popup-spiegazione popup-morale" onClick={(e) => e.stopPropagation()}>
        <h2>Il morale di squadra</h2>
        <div className="popup-spiegazione__corpo">
          <p>Il valore è la <b>media del morale {daFormazione ? `degli ${morali.length} titolari che hai schierato` : `dei ${morali.length} migliori giocatori`}</b>{daFormazione ? ' nella formazione per la prossima partita: se cambi formazione, cambia anche il numero' : ' della rosa (non hai ancora salvato una formazione)'}. Ogni giocatore ha un morale da 0 a 100, e <b>70 è il punto neutro</b>: sopra gioca un filo meglio, sotto un filo peggio.</p>

          <h3>Come incide in partita</h3>
          <p>Poco, di proposito: nel calcio vero (e nelle misure su Football Manager) il morale è la leva più piccola. Un giocatore a morale 100 rende come se avesse circa <b>+0,3 di overall</b>, uno a morale 40 circa <b>−0,3</b>; sotto i 20 circa smette di peggiorare. Fra una squadra a morale 45 e una a 95 corrono circa <b>3–4 punti in una stagione da 38 giornate</b>. Non cambia una partita, può spostare un campionato quando le squadre sono vicine.</p>
          <p>Il <b>capitano</b> tiene su lo spogliatoio: attenua buona parte del malcontento dei compagni. Se però è lui il più scontento, lo peggiora.</p>

          <h3>Cosa lo fa muovere</h3>
          <ul>
            <li><b>Minutaggio</b> — giocare meno di quanto ci si aspetta delude più di quanto giocare tanto faccia piacere. Una promessa di minuti non mantenuta pesa il 50% in più.</li>
            <li><b>Ingaggio</b> — chi guadagna meno del suo valore è scontento, chi guadagna di più è contento (conta chi è interessato ai soldi).</li>
            <li><b>Risultati</b> — in alto in classifica fa bene, in basso fa male (conta chi vuole vincere).</li>
            <li><b>Carattere</b> — i giocatori "bandiera" assorbono parte del malcontento.</li>
            <li><b>Rinnovi</b> — un rinnovo accettato dà una spinta immediata.</li>
            <li><b>Conferenze stampa</b> — le tue parole in sala stampa muovono subito il morale di tutta la rosa, e dei giocatori che citi. Dire sempre le stesse frasi fa perdere valore.</li>
          </ul>
          <p>Il ricalcolo di minutaggio, ingaggio e risultati avviene <b>a ogni quarto di stagione</b>: le conferenze invece contano subito.</p>

          <h3>Le fasce</h3>
          <ul className="popup-morale__fasce">
            {conteggi.map((f) => <li key={f.classe}><i className={`morale-squadra__fascia morale-squadra__fascia--${f.classe}`} /><b>{f.testo}</b> <span>{f.da}</span> <em>{f.n} {f.n === 1 ? 'giocatore' : 'giocatori'}</em></li>)}
          </ul>
        </div>
        <button className="button button--primary" type="button" onClick={() => setAperto(false)}>Ho capito</button>
      </div>
    </div>}
  </>
}
