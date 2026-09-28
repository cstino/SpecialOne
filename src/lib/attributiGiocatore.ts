// ============================================================
//  GLI ATTRIBUTI SI CARICANO QUANDO SERVONO
//
//  players.attributi pesa 958 byte a giocatore. Una riga di players senza
//  attributi ne pesa 187: gli attributi sono l'84% del peso.
//
//  Le pagine Mercato e Scambi li chiedevano per TUTTI i giocatori della lega —
//  in Serie F circa novecento fra rose (456) e aste (473) — quindi ogni
//  apertura scaricava un megabyte di cui 860 KB di attributi che servono solo
//  quando si apre la scheda di UNO.
//
//  Sedici partecipanti che aprono il mercato dieci volte al giorno fanno sei
//  gigabyte al mese da quella sola pagina: e' il motivo per cui il piano
//  gratuito Supabase ha sforato la quota di banda.
//
//  Qui si caricano per un giocatore alla volta, quando la sua scheda viene
//  aperta davvero, e si tengono in memoria per la durata della sessione: chi
//  riapre la stessa scheda non paga due volte.
// ============================================================
import { supabase } from './supabase'

export type Attributi = Record<string, number | null>

const inMemoria = new Map<number, Attributi>()

/**
 * Gli attributi di un giocatore. Un errore non deve impedire di aprire la
 * scheda: si torna un oggetto vuoto e la scheda mostra il resto.
 */
export async function attributiDi(playerId: number): Promise<Attributi> {
  const gia = inMemoria.get(playerId)
  if (gia) return gia
  const { data, error } = await supabase
    .from('players').select('attributi').eq('id', playerId).maybeSingle()
  if (error || !data?.attributi) return {}
  const attributi = data.attributi as Attributi
  inMemoria.set(playerId, attributi)
  return attributi
}

// ============================================================
//  GLI ATTRIBUTI VERI DI UN GIOCATORE IN ROSA
//
//  Quelli del catalogo sono il giocatore di quando e' stato importato. Un
//  giocatore in rosa ha in piu' la crescita (o il calo) insieme all'overall e
//  il piano di sviluppo dell'allenamento: li calcola il database con la
//  stessa formula che usa il motore (private.attributi_istanza), cosi' la
//  scheda mostra esattamente i numeri con cui il giocatore scende in campo.
//
//  Qui niente memoria di sessione: cambiano a ogni giornata.
// ============================================================

/** Attributi correnti di piu' istanze (player_instances.id) in una chiamata. */
export async function attributiCorrenti(instanceIds: readonly number[]): Promise<Map<number, Attributi>> {
  const out = new Map<number, Attributi>()
  if (instanceIds.length === 0) return out
  const { data, error } = await supabase.rpc('attributi_correnti', { p_instance_ids: [...instanceIds] })
  if (error) return out
  for (const riga of (data ?? []) as Array<{ instance_id: number; attributi: Attributi }>) out.set(riga.instance_id, riga.attributi)
  return out
}

/** Attributi correnti di un giocatore in rosa. Vuoto se qualcosa va storto: la scheda mostra il resto. */
export async function attributiIstanza(instanceId: number): Promise<Attributi> {
  return (await attributiCorrenti([instanceId])).get(instanceId) ?? {}
}

/**
 * Attributi di un giocatore come li vede una lega, anche se non e' in rosa
 * (svincolati del Mercato): crescita e piano compresi, dall'overall vero.
 * Ripiega sul catalogo se la chiamata fallisce.
 */
export async function attributiInLega(leagueId: number, playerId: number): Promise<Attributi> {
  const { data, error } = await supabase.rpc('attributi_giocatore_lega', { p_league_id: leagueId, p_player_id: playerId })
  if (error || !data || Object.keys(data as object).length === 0) return attributiDi(playerId)
  return data as Attributi
}
