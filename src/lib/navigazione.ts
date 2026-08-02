import { createContext, useContext } from 'react'
import type { Notifica } from './notifiche'

// Ritorno alla schermata iniziale (elenco leghe) da dentro una lega.
// Passa da un contesto invece che da una prop, altrimenti andrebbe infilata
// in tutte e otto le schermate solo per arrivare a GameNav.
export const ContestoHome = createContext<(() => void) | null>(null)

export function useTornaAllaHome() {
  return useContext(ContestoHome)
}

// Stessa ragione: la campanella vive dentro GameNav, che non conosce l'utente
// e non deve conoscerlo. Il contesto porta l'id e il gesto di apertura.
export type Notifiche = { userId: string; apri: (notifica: Notifica) => void }

export const ContestoNotifiche = createContext<Notifiche | null>(null)

export function useNotificheContesto() {
  return useContext(ContestoNotifiche)
}
