import { STEMMI_SQUADRA } from './teamCrests'
import { ANTICIPO_PRIMA_ESTRAZIONE } from './conferenze'
import type { ScelteLiveStato, ScelteLivePick } from './useScelteLive'
import type { Team } from '../types'

// Dati FITTIZI per l'anteprima delle dirette di fine off-season (draft dei
// giocatori e sorteggio delle conference): squadre inventate, giocatori veri del
// catalogo solo per mostrare foto e carte. Non tocca il database.

const NOMI = ['Aquila Calcio', 'Real Aquila', 'Borgo Alce', 'Stella Verde', 'Genius FC', 'Leoni 1926', 'Lupi FC', 'Atletico Nebbia', 'Dinamo Pioggia', 'FC Tramonto', 'Sporting Pesto', 'Union Cantina', 'Olimpia Brezza', 'Virtus Faro', 'Città del Sale', 'Sparta Mare', 'Inter Orto', 'Juventus Pane', 'Torino Vento', 'Rovigo Stars', 'Bologna Neve', 'Napoli Pizza', 'Padova Ruote', 'Como Lago']

export const SQUADRE_DEMO: Team[] = NOMI.map((nome, i) => ({
  id: i + 1, league_id: 0, user_id: '', nome, sigla: nome.replace(/[^A-Za-z]/g, '').slice(0, 3).toUpperCase(),
  stemma_url: `preset:${STEMMI_SQUADRA[i % STEMMI_SQUADRA.length].id}`, reroll_rimasti: 0, ordine_draft: null,
  attiva: true, controllata_da_pc: false, entrata_stagione: 1, uscita_stagione: null, titoli_title: i === 2 ? 1 : 0,
} as unknown as Team))

// La squadra «tua» nell'anteprima.
export const MIA_DEMO = 3

const GIOCATORI = [
  {
    "eta": 29,
    "foto_url": "players/226271.webp",
    "nome": "Fabián Ruiz",
    "overall": 85,
    "posizioni": [
      "CM",
      "CDM"
    ]
  },
  {
    "eta": 25,
    "foto_url": "players/238074.webp",
    "nome": "R. James",
    "overall": 81,
    "posizioni": [
      "RB"
    ]
  },
  {
    "eta": 28,
    "foto_url": "players/230666.webp",
    "nome": "Gabriel Jesus",
    "overall": 80,
    "posizioni": [
      "ST",
      "CAM"
    ]
  },
  {
    "eta": 24,
    "foto_url": "players/247246.webp",
    "nome": "K. Thuram",
    "overall": 81,
    "posizioni": [
      "CM",
      "CDM"
    ]
  },
  {
    "eta": 26,
    "foto_url": "players/256675.webp",
    "nome": "O. Marmoush",
    "overall": 84,
    "posizioni": [
      "ST",
      "CAM",
      "LW"
    ]
  },
  {
    "eta": 26,
    "foto_url": "players/259694.webp",
    "nome": "Mingueza",
    "overall": 80,
    "posizioni": [
      "RB",
      "RM",
      "LM"
    ]
  },
  {
    "eta": 21,
    "foto_url": "players/270531.webp",
    "nome": "O. Diomande",
    "overall": 80,
    "posizioni": [
      "CB"
    ]
  },
  {
    "eta": 21,
    "foto_url": "players/251570.webp",
    "nome": "R. Cherki",
    "overall": 81,
    "posizioni": [
      "RW",
      "RM",
      "CAM"
    ]
  },
  {
    "eta": 26,
    "foto_url": "players/239231.webp",
    "nome": "Marc Cucurella",
    "overall": 84,
    "posizioni": [
      "LB"
    ]
  },
  {
    "eta": 32,
    "foto_url": "players/203980.webp",
    "nome": "K. Fortounis",
    "overall": 80,
    "posizioni": [
      "CAM",
      "ST",
      "RW",
      "CM"
    ]
  },
  {
    "eta": 28,
    "foto_url": "players/237238.webp",
    "nome": "S. McTominay",
    "overall": 85,
    "posizioni": [
      "CM",
      "CAM",
      "LM"
    ]
  },
  {
    "eta": 27,
    "foto_url": "players/236499.webp",
    "nome": "Douglas Luiz",
    "overall": 80,
    "posizioni": [
      "CM",
      "CDM"
    ]
  },
  {
    "eta": 28,
    "foto_url": "players/239580.webp",
    "nome": "Bremer",
    "overall": 85,
    "posizioni": [
      "CB"
    ]
  },
  {
    "eta": 23,
    "foto_url": "players/254796.webp",
    "nome": "N. Madueke",
    "overall": 80,
    "posizioni": [
      "RW",
      "RM"
    ]
  },
  {
    "eta": 23,
    "foto_url": "players/246420.webp",
    "nome": "J. Doku",
    "overall": 80,
    "posizioni": [
      "LW",
      "RW",
      "LM"
    ]
  },
  {
    "eta": 28,
    "foto_url": "players/231652.webp",
    "nome": "S. Banza",
    "overall": 81,
    "posizioni": [
      "ST"
    ]
  }
]

// Linea del tempo (secondi virtuali): attesa, 16 scelte da 30 s, pausa di 3 minuti, 24 estrazioni da 20 s.
export const DEMO = { avvioDraft: 10, passo: 30, intro: 15, scelte: 16, pausa: 180, passoSorteggio: 20, squadre: 24 }
export const DEMO_FINE_DRAFT = DEMO.avvioDraft + DEMO.scelte * DEMO.passo
export const DEMO_AVVIO_SORTEGGIO = DEMO_FINE_DRAFT + DEMO.pausa
export const DEMO_FINE = DEMO_AVVIO_SORTEGGIO + DEMO.squadre * DEMO.passoSorteggio + 20

const ORDINE_SCELTE = [5, 12, 3, 18, 9, 21, 1, 14, 7, 16, 2, 20, 11, 6, 23, 8]
// Qualche scelta «vuota» e una ceduta, per vedere anche quei casi.
const VUOTE = new Set([4, 9, 13])

export function statoDraftDemo(origine: number, adesso: number): ScelteLiveStato {
  const avvio = origine + DEMO.avvioDraft * 1000
  const picks: ScelteLivePick[] = Array.from({ length: DEMO.scelte }, (_, k) => {
    const intro = avvio + k * DEMO.passo * 1000
    const reveal = intro + DEMO.intro * 1000
    const visibile = adesso >= reveal
    const vuota = VUOTE.has(k + 1)
    const g = GIOCATORI[k % GIOCATORI.length]
    const team = ORDINE_SCELTE[k]
    return {
      n: k + 1, posizione: k + 1, team_id: team, team_origine_id: k === 5 ? 15 : team,
      intro_il: new Date(intro).toISOString(), reveal_il: new Date(reveal).toISOString(),
      esito: visibile ? (vuota ? 'vuota' : 'usata') : null,
      giocatore: visibile && !vuota ? {
        player_id: k + 1, nome: g.nome, overall: g.overall, eta: g.eta, posizioni: g.posizioni, foto_url: g.foto_url,
        ingaggio: 3_000_000 + (k % 7) * 700_000, nazionalita: null, club: null,
      } : null,
    }
  })
  return {
    ora_server: new Date(adesso).toISOString(), stagione: 1, finestra: 'off',
    avviato_il: new Date(avvio).toISOString(), passo_secondi: DEMO.passo, intro_secondi: DEMO.intro, totale: DEMO.scelte,
    fine_il: new Date(avvio + DEMO.scelte * DEMO.passo * 1000).toISOString(),
    // Avvio visibile = avviato_il del sorteggio + anticipo (come fa l'hook con i dati veri).
    sorteggio_il: new Date(origine + DEMO_AVVIO_SORTEGGIO * 1000 + ANTICIPO_PRIMA_ESTRAZIONE * 1000).toISOString(), picks,
  }
}

const ORDINE_SORTEGGIO = [7, 20, 3, 14, 11, 24, 1, 18, 9, 22, 5, 16, 13, 2, 21, 8, 15, 10, 23, 4, 17, 12, 19, 6]

export function sorteggioDemo(origine: number, adesso: number) {
  const avvio = origine + DEMO_AVVIO_SORTEGGIO * 1000
  const dovute = Math.max(0, Math.min(DEMO.squadre, Math.floor((adesso - avvio) / (DEMO.passoSorteggio * 1000))))
  return {
    stato: {
      sorteggio_id: 0, stagione: 2, avviato_il: new Date(avvio).toISOString(), passo_secondi: DEMO.passoSorteggio,
      totale: DEMO.squadre, rivelate: dovute, completato: false, ora_server: new Date(adesso).toISOString(),
    },
    estrazioni: ORDINE_SORTEGGIO.slice(0, dovute).map((team_id, k) => ({ ordine: k + 1, team_id, conferenza: ((k + 1) % 2 === 1 ? 'est' : 'ovest') as 'est' | 'ovest' })),
    squadre: SQUADRE_DEMO,
    adesso,
  }
}
