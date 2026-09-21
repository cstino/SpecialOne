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
