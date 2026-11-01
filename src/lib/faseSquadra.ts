import { useEffect, useState } from 'react'
import { supabase } from './supabase'

// Le tre fasi della stagione, ciascuna con la propria identità visiva
// (sfondo hero): stagione regolare, poi — solo per chi ci arriva — Title
// Playoff o Draft Playoff (docs/decisioni-draft-picks.md §1).
export type FaseSquadra = 'regular' | 'title' | 'draft'

export const SFONDO_FASE: Record<FaseSquadra, string> = {
  regular: '/sfondi-fase/regular_season.png',
  title: '/sfondi-fase/title_playoffs.png',
  draft: '/sfondi-fase/draft_playoffs.png',
}

// Stesse immagini, formato verticale: per le schermate a pieno schermo in
// verticale (MatchIntro.tsx, lo sfondo dietro la cronaca live in
// MatchReveal.tsx). Quelle di SFONDO_FASE sono pensate per una fascia larga
// (l'hero di Overview) e su schermo verticale verrebbero ritagliate parecchio
// invece di mostrare la composizione pensata per quel formato.
export const SFONDO_FASE_VERTICALE: Record<FaseSquadra, string> = {
  regular: '/sfondi-fase-verticali/regular_season_vert.png',
  title: '/sfondi-fase-verticali/title_playoffs_vert.png',
  draft: '/sfondi-fase-verticali/draft_playoffs_vert.png',
}

// Loghi testuali delle fasi: un vero canale alpha (non mix-blend-mode, che
// lasciava un alone se lo sfondo dell'immagine non era un nero perfetto),
// calcolato dalla luminanza di ogni pixel — nero diventa trasparente, la
// scritta resta piena.
export const LOGO_FASE: Record<FaseSquadra, string> = {
  regular: '/loghi-fase/regular-season.png',
  title: '/loghi-fase/title-playoffs.png',
  draft: '/loghi-fase/draft-playoffs.png',
}

// Musica dell'intro pre-partita (MatchIntro.tsx): una traccia per fase, la
// stessa in loop per tutti i 25 secondi, non una per ogni schermata
// dell'intro. File da aggiungere in public/musica-fase/ (mp3).
export const MUSICA_FASE: Record<FaseSquadra, string> = {
  regular: '/musica-fase/regular_season.m4a',
  title: '/musica-fase/titleplayoffs.mp3',
  draft: '/musica-fase/draftplayoffs.mp3',
}

// Ultima fase vista per squadra: in memoria (tornando alla home) e nel browser (all'apertura dell'app), cosi'
// la pagina non parte dai colori della regular season per poi cambiare quando arriva la risposta del database.
// E' solo un ricordo estetico: la fase vera si ricalcola sempre e sostituisce questo valore.
const faseRicordata = new Map<string, FaseSquadra>()
const chiaveFase = (leagueId: number, teamId: number) => `so-fase:${leagueId}:${teamId}`
function leggiFase(leagueId: number, teamId: number): FaseSquadra {
  const chiave = chiaveFase(leagueId, teamId)
  const inMemoria = faseRicordata.get(chiave)
  if (inMemoria) return inMemoria
  try {
    const salvata = localStorage.getItem(chiave)
    if (salvata === 'regular' || salvata === 'title' || salvata === 'draft') return salvata
  } catch { /* storage non disponibile: si parte da regular */ }
  return 'regular'
}
function ricordaFase(leagueId: number, teamId: number, fase: FaseSquadra) {
  const chiave = chiaveFase(leagueId, teamId)
  faseRicordata.set(chiave, fase)
  try { localStorage.setItem(chiave, fase) } catch { /* niente: resta il ricordo in memoria */ }
}

// In quale fase si trova una squadra: guarda se partecipa a un tabellone
// ancora in corso per la stagione data. Nessun tabellone attivo (stagione
// regolare, o tabelloni già tutti conclusi) ricade su 'regular'.
export function useFaseSquadra(leagueId: number, teamId: number, seasonId: number | null | undefined): FaseSquadra {
  const [fase, setFaseStato] = useState<FaseSquadra>(() => leggiFase(leagueId, teamId))

  useEffect(() => {
    let vivo = true
    const setFase = (f: FaseSquadra) => { ricordaFase(leagueId, teamId, f); setFaseStato(f) }
    // Cambiando squadra si riparte dal ricordo di quella squadra. Senza stagione (anche mentre i dati della
    // stagione stanno ancora arrivando) si resta sul ricordo invece di tornare per un attimo alla regular season.
    setFaseStato(leggiFase(leagueId, teamId))
    if (!seasonId) return

    async function carica() {
      const { data: brackets } = await supabase.from('brackets')
        .select('id, tipo').eq('league_id', leagueId).eq('season_id', seasonId).neq('stato', 'concluso')
      if (!vivo) return
      if (!brackets || brackets.length === 0) { setFase('regular'); return }

      const { data: ties } = await supabase.from('bracket_ties')
        .select('bracket_id')
        .in('bracket_id', brackets.map((b) => b.id))
        .or(`alta_team_id.eq.${teamId},bassa_team_id.eq.${teamId}`)
      if (!vivo) return

      const idsPropri = new Set((ties ?? []).map((t) => t.bracket_id))
      const proprio = brackets.find((b) => idsPropri.has(b.id))
      setFase(proprio ? (proprio.tipo as FaseSquadra) : 'regular')
    }
    void carica()
    return () => { vivo = false }
  }, [leagueId, teamId, seasonId])

  return fase
}
