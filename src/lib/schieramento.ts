// ============================================================
//  LE POSTAZIONI DEL CAMPO
//
//  Il campo ha un insieme FISSO di postazioni. Ognuna sta sempre nello stesso
//  punto, ha un nome di posizione e ospita un giocatore solo. Uno schieramento
//  non e' altro che l'elenco di quali postazioni sono occupate.
//
//  PERCHE' FISSE. Servono per trascinare: una card si sposta a calamita sulla
//  postazione libera piu' vicina, come nelle tattiche personalizzate di FC. Con
//  coordinate ricalcolate dallo schieramento corrente le postazioni si
//  sposterebbero MENTRE trascini, e il divieto "questa e' gia' occupata" non
//  avrebbe nemmeno un posto a cui riferirsi.
//
//  Due tentativi precedenti, entrambi sbagliati, vale la pena ricordarli:
//    - una catena di casi speciali per nome di modulo, dentro Formazione.tsx,
//      con due bug corretti a mano (il 4-2-4 che scambiava le ali, il CAM del
//      4-3-3 offensivo che finiva di lato). Cade con gli schemi personalizzati:
//      il nome del modulo non dice piu' dove stanno gli undici.
//    - un calcolo derivato che spartiva ogni riga in parti uguali. Mandava due
//      CDM sulle fasce come se fossero due esterni, perche' una spartizione non
//      sa niente di corsie.
//  Le postazioni fisse chiudono entrambi: le coordinate sono scritte una volta
//  e si guardano.
//
//  x: 0 = fascia sinistra, 100 = fascia destra.
//  y: 0 = porta propria, 100 = porta avversaria.
// ============================================================

export type Ancora = { id: string; slot: string; x: number; y: number }

// Le postazioni, riga per riga. Chi ne ha piu' d'una con lo stesso nome (tre
// CB, tre CM) le occupa dal centro verso fuori: vedi scegliAncore().
export const ANCORE: Ancora[] = [
  { id: 'gk', slot: 'GK', x: 50, y: 5 },

  { id: 'lb', slot: 'LB', x: 13, y: 22 },
  { id: 'cb1', slot: 'CB', x: 34, y: 20 },
  { id: 'cb2', slot: 'CB', x: 50, y: 19 },
  { id: 'cb3', slot: 'CB', x: 66, y: 20 },
  { id: 'rb', slot: 'RB', x: 87, y: 22 },

  { id: 'lwb', slot: 'LWB', x: 10, y: 38 },
  { id: 'rwb', slot: 'RWB', x: 90, y: 38 },

  { id: 'cdm1', slot: 'CDM', x: 34, y: 39 },
  { id: 'cdm2', slot: 'CDM', x: 50, y: 37 },
  { id: 'cdm3', slot: 'CDM', x: 66, y: 39 },

  { id: 'lm', slot: 'LM', x: 12, y: 57 },
  { id: 'cm1', slot: 'CM', x: 32, y: 56 },
  { id: 'cm2', slot: 'CM', x: 50, y: 55 },
  { id: 'cm3', slot: 'CM', x: 68, y: 56 },
  { id: 'rm', slot: 'RM', x: 88, y: 57 },

  { id: 'cam1', slot: 'CAM', x: 32, y: 72 },
  { id: 'cam2', slot: 'CAM', x: 50, y: 71 },
  { id: 'cam3', slot: 'CAM', x: 68, y: 72 },

  { id: 'lw', slot: 'LW', x: 13, y: 86 },
  { id: 'st1', slot: 'ST', x: 36, y: 90 },
  { id: 'st2', slot: 'ST', x: 50, y: 92 },
  { id: 'st3', slot: 'ST', x: 64, y: 90 },
  { id: 'rw', slot: 'RW', x: 87, y: 86 },
]

export const ancorePerSlot = (slot: string): Ancora[] => ANCORE.filter((a) => a.slot === slot)
export const ancoraPerId = (id: string): Ancora | undefined => ANCORE.find((a) => a.id === id)

/**
 * Quali postazioni occupa chi ne ha n con lo stesso nome.
 *
 * La scelta e' SIMMETRICA rispetto al centro del campo, non "le n piu' vicine
 * al centro": due difensori centrali su tre postazioni vanno alla prima e alla
 * terza, non alla prima e alla seconda — altrimenti la difesa si accartoccia a
 * sinistra e lascia un buco a destra.
 */
function scegliAncore(disponibili: Ancora[], n: number): Ancora[] {
  const m = disponibili.length
  if (n >= m) return disponibili
  if (n <= 0) return []
  if (n === 1) return [disponibili[Math.round((m - 1) / 2)]]
  const passo = (m - 1) / (n - 1)
  const scelti = new Set<number>()
  for (let i = 0; i < n; i++) scelti.add(Math.round(i * passo))
  return disponibili.filter((_, i) => scelti.has(i))
}

export type PostoInCampo = { index: number; slot: string; ancora: string; x: number; y: number }

/**
 * Su quali postazioni finiscono gli undici di uno schieramento.
 * L'array torna nell'ordine degli slot, cioe' nell'ordine dei titolari.
 */
export function schieramentoInCampo(slots: string[]): PostoInCampo[] {
  const perNome = new Map<string, number[]>()
  slots.forEach((slot, index) => {
    if (!perNome.has(slot)) perNome.set(slot, [])
    perNome.get(slot)!.push(index)
  })

  const out: PostoInCampo[] = []
  for (const [slot, indici] of perNome) {
    const scelte = scegliAncore(ancorePerSlot(slot), indici.length)
    indici.forEach((index, i) => {
      const a = scelte[i]
      // Uno slot senza postazione finisce al centro invece di sparire: un buco
      // silenzioso sarebbe peggio di una card fuori posto.
      out.push(a
        ? { index, slot, ancora: a.id, x: a.x, y: a.y }
        : { index, slot, ancora: `${slot}-${i}`, x: 50, y: 50 })
    })
  }
  return out.sort((a, b) => a.index - b.index)
}

// ============================================================
//  COME SI CHIAMA QUESTO SCHIERAMENTO
//
//  Spostando le posizioni si arriva a una forma che col modulo di partenza non
//  c'entra piu' niente, e continuare a chiamarla "4-4-2" e' una bugia —
//  segnalato dall'utente con uno schieramento che era di fatto un 4-2-1-3.
//
//  Il nome si ricava quindi dalla forma, in due passi:
//    1. se lo schieramento e' identico a quello standard di un modulo noto, si
//       usa il nome di quel modulo. Cosi' i moduli veri tengono il loro nome
//       proprio, "4-2-3-1" e non "4-2-1-3" — la notazione del calcio non e'
//       deducibile dalle sole posizioni, e inventarla darebbe nomi giusti in
//       aritmetica e sbagliati per chi legge;
//    2. altrimenti si contano le FASCE occupate dal basso verso l'alto.
//
//  Il modulo di partenza resta comunque quello scelto dall'utente: e' la chiave
//  della familiarita' e non cambia. Qui si descrive solo cosa c'e' in campo.
// ============================================================

/** In quale fascia orizzontale cade una postazione. */
const fasciaDi = (y: number): number =>
  y < 10 ? 0 : y < 30 ? 1 : y < 48 ? 2 : y < 65 ? 3 : y < 80 ? 4 : 5

/** La forma, letta dalle fasce: "4-2-1-3". Il portiere non si conta, come da uso. */
export function formaDiSchieramento(slots: string[]): string {
  const per = new Map<number, number>()
  for (const p of schieramentoInCampo(slots)) {
    const f = fasciaDi(p.y)
    if (f === 0) continue // il portiere
    per.set(f, (per.get(f) ?? 0) + 1)
  }
  return [...per.entries()].sort((a, b) => a[0] - b[0]).map(([, n]) => n).join('-')
}

/**
 * Il nome da mostrare. `moduli` e' la tavola dei moduli noti: se lo
 * schieramento e' esattamente quello di uno di loro, vince il suo nome proprio.
 */
export function nomeSchieramento(slots: string[], moduli: Record<string, string[]>): string {
  for (const [nome, std] of Object.entries(moduli)) {
    if (std.length === slots.length && std.every((s, i) => s === slots[i])) return nome
  }
  return formaDiSchieramento(slots)
}

// ============================================================
//  NIENTE CARD UNA SOPRA L'ALTRA
//
//  Le postazioni sono percentuali del campo, le card hanno una misura in
//  pixel: su un telefono il 15% che separa il portiere dai centrali e' una
//  settantina di pixel, e una card ne e' alta un centinaio. Segnalato dal
//  committente (1° ottobre 2026): ogni giocatore deve avere sempre il suo
//  spazio.
//
//  Si parte dalle postazioni tattiche e si allontanano solo le card che si
//  toccano: di lato se stanno sulla stessa linea, in verticale se stanno su
//  linee diverse, senza mai uscire dal campo. Se lo spazio non basta neanche
//  cosi', il chiamante rimpicciolisce le card (scalaCard) e riprova.
// ============================================================

export type Punto = { x: number; y: number }

/** Quante linee distinte ci sono (postazioni entro `tolleranza` punti di altezza = stessa linea). */
export function lineeDistinte(posti: Punto[], tolleranza = 6): number {
  const ys = [...posti.map((p) => p.y)].sort((a, b) => a - b)
  let n = 0
  let ultima = -Infinity
  for (const y of ys) { if (y - ultima > tolleranza) n++; ultima = y }
  return n
}

/**
 * Sposta le postazioni (x e y in percentuale, y dal basso come in ANCORE)
 * finche' nessuna card, larga `card.w` e alta `card.h` pixel, ne tocca un'altra
 * in un campo di `campo.w` x `campo.h` pixel. Restituisce le nuove percentuali
 * e se ci e' riuscita.
 */
export function senzaSovrapposizioni(
  posti: Punto[], campo: { w: number; h: number }, card: { w: number; h: number }, margine = 4,
): { posti: Punto[]; riuscito: boolean } {
  const cw = card.w + margine, ch = card.h + margine
  const P = posti.map((p) => ({ X: (p.x / 100) * campo.w, Y: ((100 - p.y) / 100) * campo.h }))
  const limita = (q: { X: number; Y: number }) => {
    q.X = Math.min(campo.w - card.w / 2, Math.max(card.w / 2, q.X))
    q.Y = Math.min(campo.h - card.h / 2, Math.max(card.h / 2, q.Y))
  }
  P.forEach(limita)
  let riuscito = false
  for (let giro = 0; giro < 400 && !riuscito; giro++) {
    riuscito = true
    for (let i = 0; i < P.length; i++) {
      for (let j = i + 1; j < P.length; j++) {
        const a = P[i], b = P[j]
        const dx = b.X - a.X, dy = b.Y - a.Y
        const ox = cw - Math.abs(dx), oy = ch - Math.abs(dy)
        if (ox <= 0.5 || oy <= 0.5) continue
        riuscito = false
        // Stessa linea (poco scarto in altezza): si allargano. Linee diverse:
        // si allontanano in verticale, che e' come si legge un modulo.
        if (Math.abs(dy) < card.h * 0.45) {
          const s = (dx === 0 ? (i < j ? 1 : -1) : Math.sign(dx)) * (ox / 2 + 0.5)
          a.X -= s; b.X += s
        } else {
          const s = Math.sign(dy) * (oy / 2 + 0.5)
          a.Y -= s; b.Y += s
        }
        limita(a); limita(b)
      }
    }
  }
  return {
    posti: P.map((q) => ({ x: (q.X / campo.w) * 100, y: 100 - (q.Y / campo.h) * 100 })),
    riuscito,
  }
}

/**
 * La disposizione finale per un campo vero: la scala piu' grande (fino a 1) a
 * cui le card stanno tutte senza toccarsi, e le postazioni a quella scala.
 */
export function disponiCard(posti: Punto[], campo: { w: number; h: number }, card: { w: number; h: number }): { posti: Punto[]; scala: number } {
  if (!campo.w || !campo.h || !card.w || !card.h) return { posti, scala: 1 }
  // Una linea troppo affollata per la larghezza (cinque difensori su un
  // telefono) non si risolve rimpicciolendo tutto: le due card piu' esterne
  // salgono un poco, come fanno i quinti e i terzini in campo, e la linea
  // respira. Si ripete finche' quelle rimaste stanno in larghezza.
  posti = sfalsaLineeAffollate(posti, campo, card)
  // Punto di partenza: abbastanza piccole da far stare tutte le linee in altezza.
  const linee = Math.max(1, lineeDistinte(posti))
  let scala = Math.min(1, campo.h / (linee * (card.h + 4)))
  for (let tentativo = 0; tentativo < 12; tentativo++) {
    const r = senzaSovrapposizioni(posti, campo, { w: card.w * scala, h: card.h * scala })
    if (r.riuscito) return { posti: r.posti, scala }
    scala *= 0.92
  }
  return { posti: senzaSovrapposizioni(posti, campo, { w: card.w * scala, h: card.h * scala }).posti, scala }
}

function sfalsaLineeAffollate(posti: Punto[], campo: { w: number; h: number }, card: { w: number; h: number }, tolleranza = 6): Punto[] {
  const out = posti.map((p) => ({ ...p }))
  const salita = (card.h * 0.75 / campo.h) * 100
  const indici = out.map((_, i) => i).sort((a, b) => out[a].y - out[b].y)
  const gruppi: number[][] = []
  for (const i of indici) {
    const g = gruppi[gruppi.length - 1]
    if (g && out[i].y - out[g[g.length - 1]].y <= tolleranza) g.push(i)
    else gruppi.push([i])
  }
  for (const g of gruppi) {
    const restanti = [...g].sort((a, b) => out[a].x - out[b].x)
    // Solo dalle cinque in su: con quattro basta stringerle un poco, e farle
    // salire costringerebbe a rimpicciolire tutte le altre.
    if (g.length < 5) continue
    while (restanti.length >= 3 && restanti.length * (card.w + 4) > campo.w * 0.98) {
      const sx = restanti.shift()!, dx = restanti.pop()!
      out[sx].y += salita
      out[dx].y += salita
    }
  }
  return out
}
