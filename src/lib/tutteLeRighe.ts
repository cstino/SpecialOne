// Il server restituisce al massimo 1000 righe per lettura (PGRST_DB_MAX_ROWS). Una lettura che puo' superarle va
// fatta a pagine, altrimenti le righe oltre la millesima spariscono in silenzio: e' successo alle statistiche della
// rosa il 12/11/2026 (i minuti della stagione in corso risultavano 0).
//
// Uso: const { data, error } = await tutteLeRighe((da, a) => supabase.from('x').select('...').eq(...).order('id').range(da, a))
// La lettura deve avere un ordine stabile (.order su una colonna unica), altrimenti le pagine possono sovrapporsi.

const PAGINA = 1000

type Esito<T> = { data: T[] | null; error: { message: string } | null }

export async function tutteLeRighe<T>(pagina: (da: number, a: number) => PromiseLike<Esito<T>>): Promise<Esito<T>> {
  const righe: T[] = []
  for (let da = 0; ; da += PAGINA) {
    const { data, error } = await pagina(da, da + PAGINA - 1)
    if (error) return { data: null, error }
    righe.push(...(data ?? []))
    if ((data ?? []).length < PAGINA) return { data: righe, error: null }
  }
}
