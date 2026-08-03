import { supabase } from '../lib/supabase'
import { MACRO_LABEL, ORDINE_MACRO_RUOLO, macroRuolo } from '../lib/ruoli'

export type RosterPlayer = {
  id: number
  nome: string
  club: string
  overall: number
  eta: number
  posizioni: string[]
  foto_url: string | null
  ingaggio: number
}

export async function firmaFoto(path: string | null | undefined): Promise<string | undefined> {
  if (!path) return undefined
  const { data } = await supabase.storage.from('player-photos').createSignedUrl(path, 3600)
  return data?.signedUrl
}

type RosaElencoProps = {
  giocatori: RosterPlayer[]
  foto: Map<number, string>
  loading: boolean
}

// Elenco rosa raggruppato per reparto: lo usano sia la finestra del draft
// (RosaModale in Draft.tsx) sia la pagina "La mia rosa". Un solo componente
// perche' l'utente li vuole identici, e prima erano due marcature diverse
// che divergevano visivamente senza che nessuno lo decidesse.
export function RosaElenco({ giocatori, foto, loading }: RosaElencoProps) {
  if (loading) return <p className="empty-state">Carico la rosa…</p>
  if (giocatori.length === 0) return <p className="empty-state">Non hai ancora scelto giocatori.</p>

  return (
    <div className="modale-rosa__lista">
      {ORDINE_MACRO_RUOLO.map((ruolo) => {
        const delReparto = giocatori.filter((g) => macroRuolo(g.posizioni) === ruolo)
        if (delReparto.length === 0) return null
        return (
          <div className="modale-rosa__reparto" key={ruolo}>
            <p className={`modale-rosa__reparto-titolo modale-rosa__reparto-titolo--${ruolo.toLowerCase()}`}>{MACRO_LABEL[ruolo]} · {delReparto.length}</p>
            {delReparto.map((g) => (
              <div className="modale-rosa__riga" key={g.id}>
                <div className="modale-rosa__foto">
                  {foto.get(g.id) ? <img src={foto.get(g.id)} alt="" loading="lazy" /> : <span aria-hidden="true">{g.nome.charAt(0)}</span>}
                </div>
                <div className="modale-rosa__nome">
                  <strong>{g.nome}</strong>
                  <small>{g.eta} anni · {g.posizioni[0] ?? '—'}</small>
                </div>
                <div className="modale-rosa__destra">
                  <b className="modale-rosa__ovr">{g.overall}</b>
                  <b className="modale-rosa__ingaggio">{(g.ingaggio / 1_000_000).toFixed(1)} M€</b>
                </div>
              </div>
            ))}
          </div>
        )
      })}
    </div>
  )
}
