export type League = {
  id: number
  nome: string
  admin_id: string
  codice_invito: string
  n_squadre: number
  n_gironi: number
  budget_iniziale: number
  reroll_draft: number
  slot_rosa: number
  portieri_minimi: number
  campionati_attivi: string[]
  partite_per_squadra: number
  giornate_totali: number
  stato: 'setup' | 'draft' | 'stagione' | 'conclusa'
}

export type Team = {
  id: number
  league_id: number
  user_id: string
  nome: string
  stemma_url: string | null
  budget: number
  reroll_rimasti: number
  ordine_draft: number | null
}

export type Membership = Team & { league?: League }

export type RpcResult = {
  league_id: number
  team_id: number
  codice_invito: string
}

export type CrestChoice =
  | { type: 'preset'; value: string }
  | { type: 'upload'; file: File; previewUrl: string }
