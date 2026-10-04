import { useEffect, useState } from 'react'
import { supabase } from './supabase'

// Minutaggio promesso (docs/decisioni-minutaggio.md). Le soglie arrivano dal
// database (private.soglie_minutaggio): qui si fa lo stesso conto per
// mostrare cosa chiede un giocatore anche fuori dalla rosa, nel mercato
// svincolati e nel mercato a scelte. La firma la scrive comunque il database.

export type GradinoMinutaggio = 'titolare' | 'turnover' | 'sporadico' | 'promessa'

// quota = minuti attesi sul totale delle partite; soglia = minimo per dire che la
// promessa e' rispettata (60% della quota), in percentuale (docs/decisioni-minutaggio.md).
export const GRADINI_MINUTAGGIO: Record<GradinoMinutaggio, { nome: string; detto: string; quota: number; soglia: number }> = {
  titolare: { nome: 'Titolare fisso', detto: 'Gioca la maggior parte delle partite.', quota: 0.75, soglia: 45 },
  turnover: { nome: 'Turnover', detto: 'Entra quando i titolari sono stanchi.', quota: 0.40, soglia: 24 },
  sporadico: { nome: 'Sporadico', detto: 'Gioca poche partite.', quota: 0.05, soglia: 3 },
  promessa: { nome: 'Promessa futura', detto: 'Under 21: avrà spazio nei prossimi anni.', quota: 0.05, soglia: 3 },
}

/** Il gradino con la sua soglia minima: «Titolare fisso (min. 45%)». */
export function nomeConSoglia(gradino: GradinoMinutaggio): string {
  const g = GRADINI_MINUTAGGIO[gradino]
  return `${g.nome} (min. ${g.soglia}%)`
}

/**
 * Come stanno i minuti rispetto alla promessa. Stessa regola del controllo dei
 * richiami (private.controlla_minutaggio): verde se raggiunge la soglia minima,
 * rosso se e' molto sotto (meno del 70% della soglia e almeno 10 punti sotto
 * la quota: e' il caso in cui il giocatore si fa sentire), giallo in mezzo.
 */
export function statoMinuti(pct: number | null | undefined, gradino: GradinoMinutaggio): 'ok' | 'sotto' | 'molto' | null {
  if (pct == null) return null
  const { quota } = GRADINI_MINUTAGGIO[gradino]
  if (pct >= 0.6 * quota) return 'ok'
  if (pct < 0.42 * quota && quota - pct >= 0.10) return 'molto'
  return 'sotto'
}

export function percentuale(pct: number): string {
  return `${Math.round(pct * 100)}%`
}

export type SoglieMinutaggio = Map<string, { titolare: number; turnover: number }>

function repartoMinutaggio(posizione: string | undefined): string {
  if (posizione === 'GK') return 'GK'
  if (['CB', 'LB', 'RB', 'LWB', 'RWB'].includes(posizione ?? '')) return 'DEF'
  if (['CDM', 'CM', 'CAM', 'LM', 'RM'].includes(posizione ?? '')) return 'MID'
  return 'ATT'
}

/** Stessa regola di private.gradino_richiesto. */
export function gradinoRichiesto(soglie: SoglieMinutaggio | null, overall: number, eta: number, posizione: string | undefined): GradinoMinutaggio | null {
  const reparto = repartoMinutaggio(posizione)
  const s = soglie?.get(reparto)
  if (!s) return null
  if (overall >= s.titolare) return 'titolare'
  if (eta < 21) return 'promessa'
  if (reparto !== 'GK' && overall >= s.turnover) return 'turnover'
  return 'sporadico'
}

/** Le soglie della lega; null se le tattiche sono spente o la chiamata fallisce. */
export function useSoglieMinutaggio(leagueId: number, attive: boolean): SoglieMinutaggio | null {
  const [soglie, setSoglie] = useState<SoglieMinutaggio | null>(null)
  useEffect(() => {
    if (!attive) { setSoglie(null); return }
    let vivo = true
    void supabase.rpc('soglie_minutaggio', { p_league_id: leagueId }).then(({ data }) => {
      if (!vivo || !data) return
      setSoglie(new Map((data as { reparto: string; soglia_titolare: number; soglia_turnover: number }[])
        .map((r) => [r.reparto, { titolare: r.soglia_titolare, turnover: r.soglia_turnover }])))
    })
    return () => { vivo = false }
  }, [leagueId, attive])
  return soglie
}
