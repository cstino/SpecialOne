export type League = {
  id: number
  nome: string
  admin_id: string
  codice_invito: string
  n_squadre: number
  n_gironi: number
  budget_iniziale: number
  budget_draft: number
  reroll_draft: number
  slot_rosa: number
  portieri_minimi: number
  campionati_attivi: string[]
  partite_per_squadra: number
  giornate_totali: number
  stato: 'setup' | 'draft' | 'stagione' | 'conclusa'
  stagione_corrente: number
  fase_carriera: 'normale' | 'offseason' | 'terminata'
  offseason_fine: string | null
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
  attiva: boolean
  entrata_stagione: number
  uscita_stagione: number | null
}

export type Membership = Team & { league?: League }

export type Season = {
  id: number
  league_id: number
  numero: number
  stato: 'preparazione' | 'in_corso' | 'conclusa'
  data_inizio: string | null
  data_fine: string | null
  creata_il: string
}

export type Transaction = {
  id: number
  league_id: number
  team_id: number
  tipo: string
  importo: number
  descrizione: string
  saldo_dopo: number
  creata_il: string
}

export type Fixture = {
  id: number
  season_id: number
  league_id: number
  giornata: number
  home_team_id: number
  away_team_id: number
  data_sim: string
  stato: 'programmata' | 'in_corso' | 'simulata' | 'annullata'
  campo_neutro: boolean
}

export type Match = {
  id: number
  fixture_id: number
  league_id: number
  gol_home: number
  gol_away: number
  modulo_home: string
  modulo_away: string
  titolari_home: number[]
  titolari_away: number[]
  stats_squadra: {
    home: MatchTeamStats
    away: MatchTeamStats
  }
  blocchi: EventoGol[]
  simulata_il: string
}

// Minuto e assist sono un'attribuzione della Edge Function: il motore decide
// gol e marcatori, non il singolo passaggio.
export type EventoGol = {
  minuto: number
  blocco: number
  lato: 'casa' | 'ospite'
  team_id: number
  marcatore: number
  assist: number | null
}

export type MatchTeamStats = {
  possesso: number
  tiri: number
  inPorta: number
  passaggiT: number
  passaggiR: number
  passaggiPct: number
  contrasti: number
  dribbling: number
  gol: number
}

export type MatchPlayerStat = {
  id: number
  match_id: number
  league_id: number
  team_id: number
  player_instance_id: number
  minuti: number
  gol: number
  assist: number
  tiri: number
  tiri_porta: number
  passaggi_tentati: number
  passaggi_riusciti: number
  contrasti_vinti: number
  contrasti_persi: number
  dribbling: number
}

export type Standing = {
  season_id: number
  league_id: number
  team_id: number
  punti: number
  vittorie: number
  pareggi: number
  sconfitte: number
  gol_fatti: number
  gol_subiti: number
  differenza_reti: number
  giocate: number
  posizione: number | null
}

export type RpcResult = {
  league_id: number
  team_id: number
  codice_invito: string
}

export type CrestChoice =
  | { type: 'preset'; value: string }
  | { type: 'upload'; file: File; previewUrl: string }
  | { type: 'existing'; value: string; previewUrl: string }
