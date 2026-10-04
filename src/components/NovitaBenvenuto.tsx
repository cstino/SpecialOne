import { useCallback, useEffect, useState, type ReactNode } from 'react'
import { TestoAdattato } from './TestoAdattato'
import { supabase } from '../lib/supabase'

// Stesso meccanismo di PopupSpiegazione (tabella hint_visti), ma senza
// casella "non mostrare più": qui basta chiudere o arrivare in fondo, non
// serve una scelta esplicita per un annuncio una tantum. La chiave e'
// versionata: la prossima ondata di novita' ne usera' una nuova, e tornera'
// visibile a tutti anche a chi ha gia' chiuso questa.
export const HINT_NOVITA = 'novita-2026-10-season-2'

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

// ---- Ondata della Season 2 (lancio, ottobre 2026) ----
// Un solo giro con tutte le novita' (deciso col committente il 4 ottobre):
// quelle della Season 2 (tattiche, schemi, allenamento, partita) e quelle
// arrivate su main nel frattempo (mercato svincolati, scelte, off-season,
// albo d'oro). Stile broadcast come Rosa e dashboard: ogni pagina ha il
// colore di una fase (--fz-*), titoli in Oswald, elenchi brevi.

type Fase = 'regular' | 'title' | 'draft'
type Pagina = { fase: Fase; sfondo: string; occhiello: string; titolo: string; punti: ReactNode[]; grafico?: ReactNode; marchio?: boolean }

// Infografica: le due card degli schemi, con la riserva che impara.
function GraficoSchemi() {
  return <div className="nv-schemi">
    <div className="nv-schema is-attivo"><small>Attivo</small><b><TestoAdattato minimo={0.6}>Schema 1</TestoAdattato></b><em>4-3-3</em></div>
    <div className="nv-schema"><small>&nbsp;</small><b><TestoAdattato minimo={0.6}>Schema 2</TestoAdattato></b><em>3-5-2</em>
      <span className="nv-barra"><i style={{ width: '60%' }} /></span><small className="nv-nota">Lo impari: 3/5 partite</small></div>
  </div>
}

// Infografica: i segnalini sulle magliette (ritaglio di una formazione vera)
// con la legenda. Il segno misura quanto il giocatore e' adatto al RUOLO che
// gli si da' (segnoIdoneita in lib/tattica.ts), non allo stile di gioco.
function GraficoSegnalini() {
  const voci: { segno: string; tono: 'piu' | 'meno'; testo: string }[] = [
    { segno: '++', tono: 'piu', testo: 'Perfetto' },
    { segno: '+', tono: 'piu', testo: 'Adatto' },
    { segno: '−', tono: 'meno', testo: 'Poco adatto' },
    { segno: '−−', tono: 'meno', testo: 'Inadatto' },
  ]
  return <div className="nv-segnalini">
    <img src="/novita/segnalini.jpg" alt="Giocatori in formazione con i segnalini ++ e − accanto alla foto" />
    <div className="nv-segnalini__legenda">
      {voci.map((v) => <span key={v.segno}><b className={`is-${v.tono}`}>{v.segno}</b>{v.testo}</span>)}
    </div>
  </div>
}

// Infografica: l'overall effettivo, pieno e ridotto (giallino).
function GraficoOverall() {
  return <div className="nv-overall">
    <div><span className="nv-ovr">84</span><small>Nel suo ruolo</small></div>
    <div><span className="nv-ovr is-ridotto">78</span><small>Fuori ruolo o stanco</small></div>
  </div>
}

// Infografica: la partita con i cambi, 3 soste piu' l'intervallo.
function GraficoCambi() {
  const soste = [{ min: 45, label: 'Int.' }, { min: 62, label: '1' }, { min: 76, label: '2' }, { min: 86, label: '3' }]
  return <div className="nv-cambi">
    <div className="nv-cambi__pista">
      {soste.map((s) => <span key={s.min} className={s.label === 'Int.' ? 'is-intervallo' : ''} style={{ left: `${(s.min / 90) * 100}%` }}><b>{s.label}</b></span>)}
    </div>
    <div className="nv-cambi__minuti"><small>0'</small><small>45'</small><small>90'</small></div>
    <p className="nv-didascalia">Fino a 5 cambi in 3 soste, più l'intervallo.</p>
  </div>
}

// Infografica: il tetto ingaggi con uno svincolato ancora a carico.
function GraficoTetto() {
  return <div className="nv-tetto">
    <div className="nv-tetto__barra"><span className="nv-tetto__rosa" style={{ width: '72%' }} /><span className="nv-tetto__peso" style={{ width: '12%' }} /></div>
    <div className="nv-tetto__legenda"><small><i className="nv-tetto__rosa" />Rosa</small><small><i className="nv-tetto__peso" />Svincolato ancora a carico</small></div>
  </div>
}

const PAGINE: Pagina[] = [
  {
    fase: 'regular', sfondo: '/sfondi-fase/regular_season.png', marchio: true,
    occhiello: 'Benvenuto nella Season 2',
    titolo: 'Si cambia gioco.',
    punti: [
      <>In queste pagine trovi <strong>tutto quello che è cambiato</strong>: tattiche, allenamento, partita, mercato e albo d'oro.</>,
      <>Anche la grafica è nuova, nello stile dei videogiochi di calcio. I colori seguono la fase della tua squadra: verde in Regular Season, blu nei Title Playoff, arancio nei Draft Playoff.</>,
    ],
  },
  {
    fase: 'regular', sfondo: '/sfondi-fase/regular_season.png',
    occhiello: 'Novità · Tattiche',
    titolo: 'La tua squadra ha un’identità.',
    punti: [
      <>Scegli lo <strong>stile di gioco</strong> fra 7, dove attaccare, l'altezza della linea, l'ampiezza e come gioca il portiere. Lo stile cambia davvero la partita: ritmo, possesso, quanti tiri fai.</>,
      <>Non vuoi perderci tempo? I <strong>preset tattici</strong> (Palleggio, Pressing alto, Contropiede, Catenaccio…) sistemano tutto con un tocco.</>,
    ],
  },
  {
    fase: 'regular', sfondo: '/sfondi-fase/regular_season.png',
    occhiello: 'Novità · Ruoli e compiti',
    titolo: 'Ogni giocatore al suo posto.',
    punti: [
      <>A ogni giocatore dai un <strong>ruolo</strong> (regista, finalizzatore…) e un <strong>compito</strong>: difesa, equilibrio o attacco.</>,
      <>Il <strong>segnalino</strong> accanto alla foto dice quanto è adatto al ruolo che gli hai dato: con <strong>++</strong> e <strong>+</strong> rende di più, con <strong>−</strong> e <strong>−−</strong> rende di meno.</>,
    ],
    grafico: <GraficoSegnalini />,
  },
  {
    fase: 'regular', sfondo: '/sfondi-fase/regular_season.png',
    occhiello: 'Novità · Schemi e familiarità',
    titolo: 'Due schemi, uno pronto in panchina.',
    punti: [
      <>La <strong>familiarità</strong> si riempie in 5 partite, e tornando a un modulo già usato ritrovi quello che avevi imparato.</>,
      <>Hai <strong>due schemi</strong>. Quello "Attivo" va in partita; l'altro lo prepari, e il suo modulo si impara un po' a ogni partita <strong>anche senza schierarlo</strong>. Selezionalo e salva per metterlo in partita.</>,
    ],
    grafico: <GraficoSchemi />,
  },
  {
    fase: 'regular', sfondo: '/risorse/training.jpg',
    occhiello: 'Novità · Rosa e allenamento',
    titolo: 'Vedi quanto vale davvero.',
    punti: [
      <>Nella Rosa l'overall è quello <strong>effettivo</strong>: tiene conto del ruolo e della forma. Diventa giallo quando è più basso del normale. La barretta sotto il nome è l'energia.</>,
      <>Il <strong>piano di sviluppo</strong> vale da subito e si può fare <strong>insieme al cambio ruolo</strong>. Anche i portieri hanno i loro piani.</>,
    ],
    grafico: <GraficoOverall />,
  },
  {
    fase: 'title', sfondo: '/sfondi-fase/title_playoffs.png',
    occhiello: 'Novità · Partita',
    titolo: 'La partita come in TV.',
    punti: [
      <>Prima del calcio d'inizio c'è l'<strong>intro</strong> con locandina e presentazione degli undici.</>,
      <>Nella live c'è la <strong>telecronaca</strong> con il grafico della pressione, e i gol possono nascere da calci piazzati.</>,
      <>Ogni giocatore ha il suo <strong>voto in pagella</strong>: anche un difensore può essere il migliore in campo.</>,
    ],
    grafico: <GraficoCambi />,
  },
  {
    fase: 'draft', sfondo: '/sfondi-fase/draft_playoffs.png',
    occhiello: 'Novità · Mercato svincolati',
    titolo: 'Svincolare ora costa.',
    punti: [
      <>Ogni sera esce <strong>un solo giocatore per ruolo</strong>, più tutti quelli svincolati dalle squadre: restano in vetrina finché qualcuno non li prende.</>,
      <>Se svincoli un giocatore liberi il posto in rosa, ma <strong>il suo ingaggio resta sul tuo tetto</strong> finché il contratto non scade o un'altra squadra non lo prende. In Finanza vedi quanto paghi ancora.</>,
      <>Morale: per cambiare la rosa conviene <strong>scambiare</strong>.</>,
    ],
    grafico: <GraficoTetto />,
  },
  {
    fase: 'draft', sfondo: '/sfondi-fase/draft_playoffs.png',
    occhiello: 'Novità · Scambi, scelte e playoff',
    titolo: 'Trattare è più semplice.',
    punti: [
      <>La pagina <strong>Scambi</strong> è stata rifatta: scegli la squadra, tocca chi chiedi e chi offri, e vedi subito il riepilogo.</>,
      <>Se hai più scelte nella stessa finestra del draft, componi <strong>una lista sola</strong>: ogni scelta prende la prima preferenza ancora libera.</>,
      <>Il <strong>tabellone</strong> è in stile UEFA, con andata, ritorno e totale per ogni sfida. L'ordine delle scelte dipende da chi ti elimina nei playoff.</>,
    ],
  },
  {
    fase: 'title', sfondo: '/sfondi-fase/title_playoffs.png',
    occhiello: 'Novità · Off-season e albo d’oro',
    titolo: 'Ogni stagione lascia il segno.',
    punti: [
      <>L'off-season si apre dopo l'ultima giornata e dura quanto decide la lega. Rinnovi, scambi e UNDER restano aperti per tutta la durata; il mercato svincolati è chiuso.</>,
      <>L'<strong>Albo d'oro</strong> premia anche miglior marcatore, assistman e portiere, in Regular Season e nei Title Playoff.</>,
      <>A fine stagione una <strong>presentazione a sorpresa</strong> svela campione e premi, con le carte da girare.</>,
    ],
  },
  {
    fase: 'regular', sfondo: '/sfondi-fase/regular_season.png', marchio: true,
    occhiello: 'Pronti via',
    titolo: 'Buona Season 2.',
    punti: [
      <>Le spiegazioni di ogni pagina sono state aggiornate e <strong>riappaiono alla prima apertura</strong>. Tutti i dettagli sono sempre nella sezione Aiuto.</>,
    ],
  },
]

export function NovitaBenvenuto({ onChiudi }: { onChiudi: () => void }) {
  const [indice, setIndice] = useState(0)
  const ultima = indice === PAGINE.length - 1
  const pagina = PAGINE[indice]

  return (
    <div className={`nv-sfondo formazione-broadcast formazione-broadcast--${pagina.fase}`} role="dialog" aria-modal="true" aria-label="Novità della Season 2">
      <div className="nv-cassetta">
        <button className="nv-salta" type="button" onClick={onChiudi}>Salta</button>
        <div className="nv-testata" style={{ backgroundImage: `url(${pagina.sfondo})` }}>
          {pagina.marchio && <img className="nv-marchio" src="/specialone-icon-512.png" alt="" />}
          <span className="nv-contatore">{indice + 1} / {PAGINE.length}</span>
        </div>
        <div className="nv-corpo" key={indice}>
          <p className="nv-occhiello">{pagina.occhiello}</p>
          <h2>{pagina.titolo}</h2>
          <ul className="nv-punti">{pagina.punti.map((p, i) => <li key={i}>{p}</li>)}</ul>
          {pagina.grafico && <div className="nv-grafico">{pagina.grafico}</div>}
        </div>
        <footer className="nv-piede">
          <div className="nv-puntini">
            {PAGINE.map((_, i) => <button key={i} type="button" aria-label={`Pagina ${i + 1}`}
              className={`nv-puntino ${i === indice ? 'is-attivo' : ''}`} onClick={() => setIndice(i)} />)}
          </div>
          <div className="nv-azioni">
            {indice > 0 && <button className="nv-bottone" type="button" onClick={() => setIndice((i) => i - 1)}>Indietro</button>}
            <button className="nv-bottone is-primario" type="button" onClick={() => ultima ? onChiudi() : setIndice((i) => i + 1)}>
              {ultima ? 'Si gioca' : 'Avanti'}
            </button>
          </div>
        </footer>
      </div>
    </div>
  )
}
