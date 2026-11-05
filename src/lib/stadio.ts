import { useEffect, useState } from 'react'
import { supabase } from './supabase'
import type { League, Team } from '../types'

// Lo stadio (Season 3, docs/DIARIO-SEASON3.md §4): quarto ramo delle risorse. Il calcolo vero sta nel database
// (public.moltiplicatori_casa, private.effetti_ramo); qui solo nome, immagine e bonus da mostrare.

export const NOME_STADIO_MAX = 25

// Il nome non e' mai vuoto: il database ne assegna uno di default a ogni squadra, diverso dalle altre della lega
// (private.nomi_stadio_default). 'Stadio' resta solo come ripiego se la riga non e' ancora arrivata.
export function nomeStadio(team: Pick<Team, 'nome_stadio'> | null | undefined): string {
  return team?.nome_stadio?.trim() || 'Stadio'
}

/** Il nome si cambia (Club > Modifica squadra) solo a stagione in corso con lo stadio acceso. */
export function nomeStadioModificabile(league: Pick<League, 'stadio_attivo' | 'stato' | 'fase_carriera'>): boolean {
  return Boolean(league.stadio_attivo) && league.stato === 'stagione' && league.fase_carriera !== 'offseason'
}

// Immagine per grandezza: provincia, due anelli, maxischermo, arena col tetto.
export function immagineStadio(livello: number): string {
  if (livello <= 2) return '/stadio/stadio-0-2.webp'
  if (livello <= 5) return '/stadio/stadio-3-5.webp'
  if (livello <= 8) return '/stadio/stadio-6-8.webp'
  return '/stadio/stadio-9-10.webp'
}

/** Massimo del bonus casa del pubblico: +1,0 a livello 0, +0,2 a livello. Senza stadio (null) resta +2,0. */
export function bonusCasaMassimo(livello: number | null | undefined): number {
  return livello == null ? 2 : 1 + 0.2 * livello
}

/** Livello dello stadio di ogni squadra della lega; vuota se la lega non ha ancora lo stadio. */
export function useLivelliStadio(leagueId: number, attivo: boolean | undefined): Map<number, number> {
  const [livelli, setLivelli] = useState<Map<number, number>>(new Map())
  useEffect(() => {
    if (!attivo) { setLivelli(new Map()); return }
    let vivo = true
    void supabase.from('team_risorse').select('team_id, livello_stadio').eq('league_id', leagueId).then(({ data }) => {
      if (!vivo || !data) return
      setLivelli(new Map((data as { team_id: number; livello_stadio: number }[]).map((r) => [r.team_id, r.livello_stadio])))
    })
    return () => { vivo = false }
  }, [leagueId, attivo])
  return livelli
}
