// Uno schema deve avere senso nel calcio: un terzino destro senza il sinistro,
// o un'ala destra senza la sinistra, non esiste. Stessa regola di
// private.disposizione_simmetrica in SQL (che e' quella che fa fede).
const COPPIE: Array<{ sinistra: string[]; destra: string[]; nome: string }> = [
  { sinistra: ['LB', 'LWB'], destra: ['RB', 'RWB'], nome: 'terzino' },
  { sinistra: ['LM'], destra: ['RM'], nome: 'esterno di centrocampo' },
  { sinistra: ['LW'], destra: ['RW'], nome: 'ala' },
]

export function erroreSimmetriaSchema(slots: readonly string[]): string | null {
  for (const { sinistra, destra, nome } of COPPIE) {
    const s = slots.filter((x) => sinistra.includes(x)).length
    const d = slots.filter((x) => destra.includes(x)).length
    if (s > d) return `C'è un ${nome} sinistro senza il destro: sistema lo schema: servono gli stessi lati a destra e a sinistra.`
    if (d > s) return `C'è un ${nome} destro senza il sinistro: sistema lo schema: servono gli stessi lati a destra e a sinistra.`
  }
  return null
}
