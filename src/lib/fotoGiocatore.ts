// ============================================================
//  L'INDIRIZZO DI UNA FOTO, STABILE
//
//  Il bucket player-photos e' pubblico (migrazione 20260921090000), e questo
//  file esiste per una ragione sola: l'indirizzo dev'essere SEMPRE LO STESSO
//  per lo stesso file.
//
//  Prima ogni foto passava da createSignedUrl, che produce un indirizzo
//  firmato DIVERSO A OGNI CHIAMATA. Il browser non poteva riconoscere
//  un'immagine gia' scaricata e la riscaricava ogni volta: una foto da 5,7 KB
//  vista cento volte costava 570 KB invece di 5,7. Con novecento foto nella
//  pagina Mercato erano cinque megabyte a ogni apertura, piu' novecento
//  round-trip per firmare gli indirizzi.
//
//  Ora l'indirizzo e' stabile: il browser lo riconosce, rivalida con l'ETag e
//  riceve un 304 senza corpo. E la firma non serve piu', quindi la funzione e'
//  sincrona e non fa nessuna chiamata di rete.
//
//  team-crests resta privato e continua a usare createSignedUrl: sono quattro
//  file caricati dagli utenti, irrilevanti per la banda, e non c'e' motivo di
//  allargarne l'accesso.
// ============================================================
import { supabase } from './supabase'

/**
 * L'indirizzo pubblico della foto di un giocatore.
 * `path` e' il valore di players.foto_url. Un indirizzo gia' completo (http)
 * viene restituito com'e': alcune righe del catalogo puntano fuori.
 */
export function urlFotoGiocatore(path: string | null | undefined): string | undefined {
  if (!path) return undefined
  if (path.startsWith('http')) return path
  return supabase.storage.from('player-photos').getPublicUrl(path).data.publicUrl
}

/**
 * Le foto di piu' giocatori, nella stessa forma che il codice chiamante usava
 * con gli indirizzi firmati: una mappa id -> indirizzo.
 */
export function urlFotoGiocatori<T extends { id: number; foto_url: string | null }>(
  giocatori: readonly T[],
): Record<number, string> {
  const out: Record<number, string> = {}
  for (const g of giocatori) {
    const url = urlFotoGiocatore(g.foto_url)
    if (url) out[g.id] = url
  }
  return out
}
