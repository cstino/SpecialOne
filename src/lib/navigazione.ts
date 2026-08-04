import { createContext, useContext } from 'react'
import type { Notifica } from './notifiche'

// Ritorno alla schermata iniziale (elenco leghe) da dentro una lega.
// Passa da un contesto invece che da una prop, altrimenti andrebbe infilata
// in tutte e otto le schermate solo per arrivare a GameNav.
export const ContestoHome = createContext<(() => void) | null>(null)

export function useTornaAllaHome() {
  return useContext(ContestoHome)
}

// Stessa ragione: la navigazione della lega non conosce l'utente, ma deve
// mostrare il badge e aprire gli avvisi. Lo stato e' unico in App: menu e
// pagina non creano due canali Realtime per la stessa inbox.
export type Notifiche = {
  userId: string
  notifiche: Notifica[]
  nonLette: number
  caricamento: boolean
  ricarica: () => Promise<void>
  segnaLette: (ids?: number[]) => Promise<void>
  elimina: (id: number) => Promise<boolean>
  apri: (notifica: Notifica) => void
}

export const ContestoNotifiche = createContext<Notifiche | null>(null)

export function useNotificheContesto() {
  return useContext(ContestoNotifiche)
}
