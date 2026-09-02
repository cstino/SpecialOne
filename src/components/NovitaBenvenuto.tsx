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

function FrecciaDestra() {
  return <svg className="novita-freccia" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
    <path d="M4 12h15M13 6l6 6-6 6" />
  </svg>
}

// Infografica 1: i tre rami di Gestione risorse come colonne a 10 tacche,
// con un esempio di ripartizione a mostrare che i punti non bastano per
// riempirli tutti — e' il punto centrale della meccanica, va visto subito.
function GraficoRami() {
  const rami: { nome: string; livello: number; colore: string }[] = [
    { nome: 'Vivaio', livello: 7, colore: '#9b4cff' },
    { nome: 'Training', livello: 4, colore: '#4cc9f0' },
    { nome: 'Reparto medico', livello: 2, colore: '#ff5972' },
  ]
  return (
    <div className="novita-barre">
      {rami.map((r) => (
        <div className="novita-barra" key={r.nome}>
          <div className="novita-barra__pista">
            {Array.from({ length: 10 }, (_, i) => (
              <span key={i} className={i < r.livello ? 'is-pieno' : ''} style={i < r.livello ? { background: r.colore } : undefined} />
            ))}
          </div>
          <b style={{ color: r.colore }}>Lv. {r.livello}</b>
          <small>{r.nome}</small>
        </div>
      ))}
    </div>
  )
}

// Infografica 2: la fascia di potenziale che si stringe salendo di livello
// nel ramo Vivaio. Stesso prospetto in entrambe le righe: 71-86 a livello
// 0 (esempio reale di ampiezza), valore vero 74 a livello 10 — non 78,
// che sarebbe quasi la media dei due estremi e avrebbe suggerito il
// contrario di quello che la fascia vuole spiegare.
function GraficoPotenziale() {
  return (
    <div className="novita-fasce">
      <div className="novita-fascia-riga">
        <small>Vivaio Lv. 0</small>
        <div className="novita-fascia-pista"><span className="novita-fascia-banda" style={{ left: '18%', width: '64%' }} /></div>
        <b>71–86</b>
      </div>
      <div className="novita-fascia-riga">
        <small>Vivaio Lv. 10</small>
        <div className="novita-fascia-pista"><span className="novita-fascia-banda is-stretta" style={{ left: '16%', width: '8%' }} /></div>
        <b>74</b>
      </div>
    </div>
  )
}

// Infografica 3: quanto si accorcia una riqualificazione con il Training
// (numeri reali della formula: base 14 giornate per uno specialista puro,
// fino a -40% con Training al massimo).
function GraficoCambioRuolo() {
  return (
    <div className="novita-cambio-ruolo">
      <div className="novita-cambio-ruolo__pills">
        <span className="role-pill role-pill--att">ATT</span>
        <FrecciaDestra />
        <span className="role-pill role-pill--mid">CC</span>
      </div>
      <div className="novita-tempi">
        <div className="novita-tempo-riga">
          <small>Training Lv. 0</small>
          <div className="novita-tempo-pista"><span style={{ width: '100%' }} /></div>
          <b>14 giornate</b>
        </div>
        <div className="novita-tempo-riga">
          <small>Training Lv. 10</small>
          <div className="novita-tempo-pista"><span style={{ width: '57%' }} /></div>
          <b>8 giornate</b>
        </div>
      </div>
    </div>
  )
}

// Infografica 4: l'altro fronte di TRAINING, la crescita dei giovani (numeri
// reali: moltiplicatore x1,00 a livello 0, fino a x1,50 a livello 9 — si
// applica solo alla crescita vera, mai al declino dei giocatori piu' anziani).
function GraficoCrescita() {
  return (
    <div className="novita-tempi">
      <div className="novita-tempo-riga">
        <small>Training Lv. 0</small>
        <div className="novita-tempo-pista"><span style={{ width: '20%' }} /></div>
        <b>x1,00</b>
      </div>
      <div className="novita-tempo-riga">
        <small>Training Lv. 9</small>
        <div className="novita-tempo-pista"><span style={{ width: '100%' }} /></div>
        <b>x1,50</b>
      </div>
    </div>
  )
}

// Infografica 5: reparto medico, i due effetti (numeri reali: -30% di
// rischio infortuni a livello 10, -40% sul calo di condizione non
// riassorbito dal recupero post-partita — non tocca il consumo in gara).
function GraficoMedico() {
  return (
    <div className="novita-tempi">
      <div className="novita-tempo-riga">
        <small>Rischio infortuni</small>
        <div className="novita-tempo-pista"><span style={{ width: '70%' }} /></div>
        <b>-30% a Lv. 10</b>
      </div>
      <div className="novita-tempo-riga">
        <small>Recupero post-partita</small>
        <div className="novita-tempo-pista"><span style={{ width: '60%' }} /></div>
        <b>-40% a Lv. 10</b>
      </div>
      <p className="novita-didascalia">Esempio: un calo di condizione da 100 a 91 in partita, con Reparto medico
        al massimo, recupera fino a 95 invece di 91.</p>
    </div>
  )
}

type Slide = { foto: string; fotoMarchio?: boolean; occhiello: string; titolo: string; corpo: ReactNode; grafico?: ReactNode }

const SLIDE: Slide[] = [
  {
    foto: '/risorse/vivaio.jpg',
    occhiello: 'Novità · Gestione risorse',
    titolo: 'Punti abilità da investire.',
    corpo: <p>Ogni quarto di stagione la squadra riceve punti da distribuire su tre rami — <strong>Vivaio</strong>,
      {' '}<strong>Training</strong> e <strong>Reparto medico</strong> — fino al livello 10 ciascuno. Non bastano
      per riempirli tutti: bisogna scegliere una direzione.</p>,
    grafico: <GraficoRami />,
  },
  {
    foto: '/risorse/vivaio.jpg',
    occhiello: 'Novità · Vivaio e mercato UNDER',
    titolo: 'Prospetti con un volto vero.',
    corpo: <p>Ogni giorno arrivano quindicenni da mettere in cantera con aste dedicate, fuori dal conteggio
      rosa. Il potenziale è una fascia che si stringe salendo di livello nel ramo Vivaio, ma <strong>non è
      centrata</strong> sul valore vero: fare la media dei due estremi non lo svela. E ora ogni prospetto ha
      anche una foto.</p>,
    grafico: <GraficoPotenziale />,
  },
  {
    foto: '/risorse/training.jpg',
    occhiello: 'Novità · Training · Crescita',
    titolo: 'I giovani crescono più in fretta.',
    corpo: <p>Il Training moltiplica la crescita vera nella progressione trimestrale — mai il declino dei
      giocatori più anziani, quello resta invariato — fino a x1,50 al livello massimo: un ragazzo di talento
      matura prima.</p>,
    grafico: <GraficoCrescita />,
  },
  {
    foto: '/risorse/training.jpg',
    occhiello: 'Novità · Training · Cambio ruolo',
    titolo: 'Riqualifica un giocatore.',
    corpo: <p>Dalla scheda di un giocatore in rosa puoi avviare il passaggio a un ruolo compatibile: il
      Training riduce i tempi fino al 40%, e chi conosce già più ruoli impara più in fretta.</p>,
    grafico: <GraficoCambioRuolo />,
  },
  {
    foto: '/risorse/medico.jpg',
    occhiello: 'Novità · Reparto medico',
    titolo: 'Meno infortuni, recupero più rapido.',
    corpo: <p>Il Reparto medico abbassa il rischio di infortuni e attenua quanto della condizione persa in
      partita non viene riassorbito dal recupero post-partita — non tocca il consumo durante i 90 minuti,
      solo quanto ne resta dopo.</p>,
    grafico: <GraficoMedico />,
  },
  {
    foto: '/specialone-icon-512.png',
    fotoMarchio: true,
    occhiello: 'Pronti via',
    titolo: 'Buon proseguimento.',
    corpo: <p>Questo era il giro di novità. Trovi sempre tutti i dettagli nella sezione Aiuto, o nei popup di
      ogni pagina alla prima apertura.</p>,
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
        <div className={`novita-foto ${slide.fotoMarchio ? 'is-marchio' : ''}`}>
          <img src={slide.foto} alt="" />
        </div>
        <div className="novita-corpo">
          <p className="kicker">{slide.occhiello}</p>
          <h2>{slide.titolo}</h2>
          <div className="novita-testo">{slide.corpo}</div>
          {slide.grafico && <div className="novita-grafico">{slide.grafico}</div>}
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
