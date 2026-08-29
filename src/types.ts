export type League = {
  id: number
  nome: string
  admin_id: string
  codice_invito: string
  n_squadre: number
  n_gironi: number
  budget_iniziale: number
  budget_draft: number
  tetto_ingaggi: number
  reroll_draft: number
  slot_rosa: number
  portieri_minimi: number
  modalita_draft: '2_of_4' | 'by_role'
  campionati_attivi: string[]
  partite_per_squadra: number
  giornate_totali: number
  stato: 'setup' | 'draft' | 'stagione' | 'conclusa'
  stagione_corrente: number
  reveal_dalla_giornata: number
  fase_carriera: 'normale' | 'offseason' | 'terminata'
  offseason_fine: string | null
}

export type Team = {
  id: number
  league_id: number
  // Le squadre PC arrivano dal database senza utente; il client le normalizza
  // a stringa vuota prima di usarle nei componenti che indicizzano per user id.
  user_id: string
  nome: string
  stemma_url: string | null
  reroll_rimasti: number
  ordine_draft: number | null
  attiva: boolean
  controllata_da_pc: boolean
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
  // Giornate di stagione REGOLARE, fissate alla creazione del calendario.
  // Da preferire sempre a league.giornate_totali, che e' una colonna generata
  // da squadre e gironi e cambia anche per le stagioni gia' concluse.
  giornate_totali: number | null
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
  // Valorizzati solo per le partite di Title/Draft Playoff (docs/decisioni-draft-picks.md §1).
  bracket_tie_id: number | null
  mano: 1 | 2 | null
}

export type RigoreTiro = { numero: number; lato: 'casa' | 'ospite'; tiratoreId: number | null; tiratore: string; segnato: boolean }

export type SceltaDraft = {
  id: number
  league_id: number
  team_origine_id: number
  team_proprietario_id: number
  stagione: number
  finestra: 'on' | 'off'
  posizione: number | null
  stato: 'futura' | 'determinata' | 'usata' | 'vuota'
  player_instance_id: number | null
}

export type Bracket = {
  id: number
  league_id: number
  season_id: number
  tipo: 'title' | 'draft'
  stato: 'in_corso' | 'concluso'
  vincitore_team_id: number | null
  finalista_team_id: number | null
}

export type BracketTie = {
  id: number
  bracket_id: number
  league_id: number
  turno: number
  posizione: number
  alta_team_id: number | null
  bassa_team_id: number | null
  alta_seed: number | null
  bassa_seed: number | null
  gara_secca: boolean
  vincitore_team_id: number | null
  stato: 'in_attesa' | 'in_corso' | 'concluso'
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
  blocchi: EventoPartita[]
  simulata_il: string
  // Parziale dei 90': valorizzato solo se si sono giocati i supplementari.
  gol_home_90: number | null
  gol_away_90: number | null
  rigori_home: number | null
  rigori_away: number | null
  rigori_serie: RigoreTiro[] | null
}

// Minuto e assist sono un'attribuzione della Edge Function: il motore decide
// gol e marcatori, non il singolo passaggio.
type EventoBase = {
  minuto: number
  blocco: number
  lato: 'casa' | 'ospite'
  team_id: number
}

export type EventoGol = EventoBase & {
  // Le partite giocate prima della cronaca estesa non hanno `tipo`: restano
  // gol legacy e devono continuare a comparire nel tabellino.
  tipo?: 'gol'
  marcatore: number
  assist: number | null
}

export type EventoTiro = EventoBase & {
  tipo: 'tiro_parato' | 'tiro_fuori'
  giocatore: number
}

export type EventoSostituzione = EventoBase & {
  tipo: 'sostituzione'
  esce: number
  entra: number
}

export type EventoInfortunio = EventoBase & {
  tipo: 'infortunio'
  esce: number
  entra: number
}

export type EventoCartellino = EventoBase & {
  tipo: 'cartellino'
  giocatore: number
  colore: 'giallo' | 'rosso_diretto' | 'doppio_giallo'
}

export type EventoPartita = EventoGol | EventoTiro | EventoSostituzione | EventoInfortunio | EventoCartellino

export function isEventoGol(evento: EventoPartita): evento is EventoGol {
  return evento.tipo === 'gol' || 'marcatore' in evento
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
