import { useCallback, useEffect, useState, type ReactNode } from 'react'
import { supabase } from '../lib/supabase'

// Stesso meccanismo di PopupSpiegazione (tabella hint_visti), ma senza
// casella "non mostrare più": qui basta chiudere o arrivare in fondo, non
// serve una scelta esplicita per un annuncio una tantum. La chiave e'
// versionata: la prossima ondata di novita' ne usera' una nuova, e tornera'
// visibile a tutti anche a chi ha gia' chiuso questa.
export const HINT_NOVITA = 'novita-2026-09-gestione-risorse'

export function useNovitaBenvenuto(userId: string | undefined) {
  const [pronto, setPronto] = useState(false)
  const [daMostrare, setDaMostrare] = useState(false)

  useEffect(() => {
    if (!userId) { setPronto(true); setDaMostrare(false); return }
    let vivo = true
    async function controlla() {
      const { data } = await supabase.from('hint_visti')
        .select('hint_key').eq('user_id', userId).eq('hint_key', HINT_NOVITA).maybeSingle()
      if (!vivo) return
      setDaMostrare(!data)
      setPronto(true)
    }
    void controlla()
    return () => { vivo = false }
  }, [userId])

  const segnaVista = useCallback(async () => {
    setDaMostrare(false)
    if (!userId) return
    await supabase.from('hint_visti').insert({ user_id: userId, hint_key: HINT_NOVITA })
  }, [userId])

  return { pronto, daMostrare, segnaVista }
}

// Icone disegnate nello stesso stile di GameNav (stroke, viewBox 24x24):
// tenute qui, non condivise, perche' questo componente vive per una sola
// ondata di novita' e sparisce con la prossima.
const ICONE: Record<string, ReactNode> = {
  pallone: <><circle cx="12" cy="12" r="9" /><path d="m12 7 4.3 3.1-1.6 5h-5.4l-1.6-5z" /></>,
  campana: <><path d="M18 9a6 6 0 1 0-12 0c0 4.5-1.5 5.6-2 6.5h16c-.5-.9-2-2-2-6.5" /><path d="M10 19a2.2 2.2 0 0 0 4 0" /><circle cx="18" cy="6" r="3.4" fill="currentColor" stroke="none" /></>,
  domanda: <><circle cx="12" cy="12" r="9" /><path d="M9.3 9.3a2.7 2.7 0 1 1 3.6 2.5c-.8.4-1.4 1-1.4 2v.4" /><path d="M12 16.8v.1" /></>,
  risorse: <><path d="M12 3.5 5 9.5 12 20.5 19 9.5z" /><path d="M5 9.5h14M9 9.5l3-6 3 6" /></>,
  vivaio: <><path d="M12 3.5 5 6.5v5c0 4.5 3 7.2 7 9 4-1.8 7-4.5 7-9v-5z" /><path d="m9.2 12 1.9 1.9 3.7-3.9" /></>,
  ruolo: <><path d="M7 7h7.5A3.5 3.5 0 0 1 18 10.5V12" /><path d="m15 8-1-3 3 1" /><path d="M17 17H9.5A3.5 3.5 0 0 1 6 13.5V12" /><path d="m9 16 1 3-3-1" /></>,
  bandiera: <><path d="M6 3v18" /><path d="M6 4h12l-3 4 3 4H6" /></>,
}

function Icona({ nome }: { nome: string }) {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true" focusable="false">
      {ICONE[nome]}
    </svg>
  )
}

type Slide = { icona: string; occhiello: string; titolo: string; corpo: ReactNode }

const SLIDE: Slide[] = [
  {
    icona: 'pallone',
    occhiello: 'Novità',
    titolo: 'Un bel po’ di cose nuove.',
    corpo: <p>Nelle ultime giornate sono arrivati parecchi aggiornamenti — dalla cronaca live a una nuova
      area della gestione squadra. Ecco un giro veloce di cosa è cambiato.</p>,
  },
  {
    icona: 'pallone',
    occhiello: 'Cronaca live',
    titolo: 'Il gol adesso si vive.',
    corpo: <>
      <p>Quando segna una squadra, la partita si ferma per un attimo: una card al centro mostra il
        marcatore, il minuto e lo stemma, con tanto di boato del pubblico e sottofondo da stadio per tutta
        la diretta.</p>
      <p>Gli eventi minori (i tiri) non affollano più la cronaca, e i minuti restano sempre coerenti dal
        primo all'ultimo — niente più eventi fuori posto.</p>
    </>,
  },
  {
    icona: 'campana',
    occhiello: 'Notifiche',
    titolo: 'Il menu ora ti avvisa.',
    corpo: <p>Non solo la campanella degli Avvisi: da oggi il pallino rosso compare anche sulla singola voce
      di menu interessata — Risorse quando hai punti da spendere, e così via. Un colpo d'occhio, non serve
      più aprire tutto per scoprire cosa è successo.</p>,
  },
  {
    icona: 'domanda',
    occhiello: 'Aiuto in pagina',
    titolo: 'Ogni pagina si spiega da sola.',
    corpo: <p>La prima volta che apri una pagina di gioco, un popup ti spiega in due righe come funziona
      quella meccanica. Se la conosci già, spunta "non mostrare più" e non lo rivedrai — puoi sempre
      ripassare tutto dalla sezione Aiuto.</p>,
  },
  {
    icona: 'risorse',
    occhiello: 'Novità di squadra',
    titolo: 'Gestione risorse.',
    corpo: <>
      <p>Ogni quarto di stagione la squadra riceve punti abilità da investire su tre rami: <strong>Vivaio</strong>,
        {' '}<strong>Training</strong> e <strong>Reparto medico</strong>. Ognuno arriva fino al livello 10, ma i
        punti totali non bastano per riempirli tutti — bisogna scegliere una direzione.</p>
      <p>Più Reparto medico significa recuperi più rapidi e meno infortuni. Più Training accelera la
        crescita dei giovani e le riqualificazioni. Più Vivaio allarga la cantera e mostra il potenziale dei
        prospetti con più precisione.</p>
    </>,
  },
  {
    icona: 'vivaio',
    occhiello: 'Settore giovanile',
    titolo: 'Vivaio e mercato UNDER.',
    corpo: <p>Ogni giorno arrivano nuovi quindicenni da mettere in cantera tramite aste dedicate, fuori dal
      conteggio rosa. Il potenziale si vede come una fascia che si stringe salendo di livello nel ramo
      Vivaio — e ora ogni prospetto ha anche un volto.</p>,
  },
  {
    icona: 'ruolo',
    occhiello: 'Rosa',
    titolo: 'Cambio ruolo.',
    corpo: <p>Dalla scheda di un giocatore in rosa puoi avviare una riqualificazione verso un altro ruolo
      compatibile: dopo un certo numero di giornate (più corto salendo di livello in Training) il giocatore
      è pronto nel nuovo ruolo.</p>,
  },
  {
    icona: 'bandiera',
    occhiello: 'Pronti via',
    titolo: 'Buon proseguimento.',
    corpo: <p>Questo era il giro di novità. Trovi sempre tutti i dettagli nella sezione Aiuto, e i popup di
      ogni pagina restano lì pronti a ripassare le regole quando serve.</p>,
  },
]

export function NovitaBenvenuto({ onChiudi }: { onChiudi: () => void }) {
  const [indice, setIndice] = useState(0)
  const ultima = indice === SLIDE.length - 1
  const slide = SLIDE[indice]

  return (
    <div className="novita-sfondo" role="dialog" aria-modal="true" aria-label="Novità dell'app">
      <div className="novita-cassetta">
        <button className="novita-salta" type="button" onClick={onChiudi}>Salta</button>
        <div className="novita-corpo">
          <div className="novita-icona"><Icona nome={slide.icona} /></div>
          <p className="kicker">{slide.occhiello}</p>
          <h2>{slide.titolo}</h2>
          <div className="novita-testo">{slide.corpo}</div>
        </div>
        <footer className="novita-piede">
          <div className="novita-puntini">
            {SLIDE.map((_, i) => (
              <span className={`novita-puntino ${i === indice ? 'is-attivo' : ''}`} key={i} />
            ))}
          </div>
          <div className="novita-azioni">
            {indice > 0 && <button className="button button--secondary" type="button" onClick={() => setIndice((i) => i - 1)}>Indietro</button>}
            <button className="button button--primary" type="button" onClick={() => ultima ? onChiudi() : setIndice((i) => i + 1)}>
              {ultima ? 'Ho capito, si gioca' : 'Avanti'}
            </button>
          </div>
        </footer>
      </div>
    </div>
  )
}
