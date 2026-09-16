// ============================================================
//  DOVE VANNO GLI UNDICI SUL CAMPO
//
//  Prima questo calcolo era una catena di casi speciali per nome di modulo
//  dentro Formazione.tsx, con due bug gia' corretti nei commenti (il 4-2-4 che
//  scambiava le ali, il CAM del 4-3-3 offensivo che finiva di lato invece che
//  fra i due CM). Con gli schemi personalizzati quel modo smette di funzionare
//  del tutto: il nome del modulo non dice piu' dove stanno gli undici, perche'
//  due squadre col 4-4-2 possono schierarsi in modo diverso.
//
//  Qui la posizione si DERIVA dallo slot, quindi vale per qualunque
//  schieramento, standard o inventato.
//
//    - la riga viene da quanto la posizione e' avanzata;
//    - la colonna viene dai PESI_CORSIA del motore, che gia' sanno che un LB
//      sta a sinistra e un CB al centro: una verita' sola, non due.
//
//  I doppioni (due CB, due CM) si distribuiscono nella loro riga tenendo
//  l'ordine in cui compaiono, che e' il motivo per cui il vecchio codice non
//  riusciva a separarli: indexOf() su due slot identici restituisce lo stesso
//  indice.
// ============================================================
import { CORSIA_X } from './tattica'

// Quanto una posizione e' avanzata. Valori non interi di proposito: un LWB sta
// fra i difensori e i centrocampisti, e sul campo si deve vedere.
const LINEA: Record<string, number> = {
  GK: 0,
  CB: 1, LB: 1, RB: 1,
  LWB: 1.55, RWB: 1.55,
  CDM: 2.1,
  CM: 2.7, LM: 2.7, RM: 2.7,
  CAM: 3.25,
  LW: 3.7, RW: 3.7,
  ST: 4.2, CF: 3.9,
}

export type PostoInCampo = { index: number; slot: string; x: number; y: number }

// -1 tutta a sinistra, +1 tutta a destra. Deriva dai PESI_CORSIA del motore.
const corsiaX = (slot: string): number => CORSIA_X[slot] ?? 0

/**
 * Le coordinate degli undici, in percentuale del campo.
 * y: 0 = linea di porta propria, 100 = porta avversaria.
 * x: 0 = fascia sinistra, 100 = fascia destra.
 */
export function schieramentoInCampo(slots: string[]): PostoInCampo[] {
  const posti = slots.map((slot, index) => ({ index, slot, linea: LINEA[slot] ?? 2.5, cx: corsiaX(slot) }))

  // Le righe si formano da sole: posizioni con la stessa altezza stanno
  // insieme. Non c'e' un elenco di righe per modulo da tenere aggiornato.
  const righe = new Map<number, typeof posti>()
  for (const p of posti) {
    const chiave = p.linea
    if (!righe.has(chiave)) righe.set(chiave, [])
    righe.get(chiave)!.push(p)
  }

  const altezze = [...righe.keys()].sort((a, b) => a - b)
  const minLinea = altezze[0] ?? 0
  const maxLinea = altezze[altezze.length - 1] ?? 4.2
  const span = Math.max(0.001, maxLinea - minLinea)

  const out: PostoInCampo[] = []
  for (const [linea, gruppo] of righe) {
    const y = 6 + (84 * (linea - minLinea)) / span
    // La colonna viene dalla CORSIA della posizione, non da una spartizione in
    // parti uguali della riga. Distribuire e' sbagliato: due CDM stanno
    // entrambi al centro, e spalmandoli sulla riga finivano sulle fasce come
    // se fossero due esterni.
    const ordinati = [...gruppo].sort((a, b) => (a.cx - b.cx) || (a.index - b.index))
    // I doppioni (due CB, tre CM) condividono la stessa corsia: si sfalsano
    // attorno a essa, tenendo l'ordine in cui compaiono.
    const perCorsia = new Map<number, typeof ordinati>()
    for (const p of ordinati) {
      const k = Math.round(p.cx * 20)
      if (!perCorsia.has(k)) perCorsia.set(k, [])
      perCorsia.get(k)!.push(p)
    }
    for (const stessaCorsia of perCorsia.values()) {
      const n = stessaCorsia.length
      stessaCorsia.forEach((p, i) => {
        const base = 50 + p.cx * 34
        const scarto = n === 1 ? 0 : (i - (n - 1) / 2) * (n === 2 ? 17 : 18)
        out.push({ index: p.index, slot: p.slot, x: Math.max(10, Math.min(90, base + scarto)), y })
      })
    }
  }
  return out.sort((a, b) => a.index - b.index)
}

/** Le righe, dalla piu' avanzata alla piu' arretrata: per chi disegna a liste. */
export function righeDiCampo(slots: string[]): PostoInCampo[][] {
  const posti = schieramentoInCampo(slots)
  const per = new Map<number, PostoInCampo[]>()
  for (const p of posti) {
    if (!per.has(p.y)) per.set(p.y, [])
    per.get(p.y)!.push(p)
  }
  return [...per.entries()]
    .sort((a, b) => b[0] - a[0])
    .map(([, riga]) => riga.sort((l, r) => l.x - r.x))
}
